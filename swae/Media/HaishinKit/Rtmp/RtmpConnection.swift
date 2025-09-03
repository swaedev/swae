import AVFoundation

private let supportedProtocols = ["rtmp", "rtmps", "rtmpt", "rtmpts"]

private enum SupportVideo: UInt16 {
    case h264 = 0x0080
}

private enum SupportSound: UInt16 {
    case aac = 0x0400
}

private enum VideoFunction: UInt8 {
    case clientSeek = 1
}

enum RtmpConnectionCode: String {
    case connectClosed = "NetConnection.Connect.Closed"
    case connectFailed = "NetConnection.Connect.Failed"
    case connectRejected = "NetConnection.Connect.Rejected"
    case connectSuccess = "NetConnection.Connect.Success"

    func eventData() -> AsObject {
        return [
            "code": rawValue,
        ]
    }
}

class RtmpStreamWeak {
    weak var stream: RtmpStream?

    init(stream: RtmpStream) {
        self.stream = stream
    }
}

class RtmpConnection {
    private var uri: URL?
    private(set) var connected = false
    private(set) var socket: RtmpSocket
    weak var stream: RtmpStream?
    private var chunkStreamIdToStreamId: [UInt16: UInt32] = [:]
    var callCompletions: [Int: ([Any?]) -> Void] = [:]
    var windowSizeFromServer: Int64 = 250_000 {
        didSet {
            guard socket.connected == true else {
                return
            }
            _ = socket.write(chunk: RtmpChunk(
                type: .zero,
                chunkStreamId: RtmpChunk.ChunkStreamId.control.rawValue,
                message: RtmpWindowAcknowledgementSizeMessage(100_000)
            ))
        }
    }

    private var nextTransactionId = 0
    private var timer = SimpleTimer(queue: processorControlQueue)
    private var messages: [UInt16: RtmpMessage] = [:]
    private var currentChunk: RtmpChunk?
    private var fragmentedChunks: [UInt16: RtmpChunk] = [:]
    private let name: String

    init(name: String) {
        self.name = name
        socket = RtmpSocket(name: name)
    }

    func connect(_ url: String) {
        guard let uri = URL(string: url),
              let scheme = uri.scheme,
              let host = uri.host,
              !connected,
              supportedProtocols.contains(scheme)
        else {
            return
        }
        self.uri = uri
        socket = RtmpSocket(name: name)
        socket.delegate = self
        if scheme.hasSuffix("s") {
            socket.connect(host: host, port: uri.port ?? 443, tlsOptions: .init())
        } else {
            socket.connect(host: host, port: uri.port ?? 1935, tlsOptions: nil)
        }
    }

    func disconnect() {
        timer.stop()
        stream?.closeInternal()
        socket.close()
        socket = RtmpSocket(name: name)
    }

    func call(_ commandName: String, arguments: [Any?], onCompleted: (([Any?]) -> Void)? = nil) {
        guard connected else {
            return
        }
        let message = RtmpCommandMessage(
            streamId: 0,
            transactionId: getNextTransactionId(),
            commandType: .amf0Command,
            commandName: commandName,
            commandObject: nil,
            arguments: arguments
        )
        if let onCompleted {
            callCompletions[message.transactionId] = onCompleted
        }
        _ = socket.write(chunk: RtmpChunk(message: message))
    }

    func gotCommand(data: AsObject) {
        on(data: data)
    }

    func createStream(_ stream: RtmpStream) {
        call("createStream", arguments: []) { data in
            guard let id = data[0] as? Double else {
                return
            }
            stream.id = UInt32(id)
            stream.setState(state: .open)
        }
    }

    func getNextTransactionId() -> Int {
        nextTransactionId += 1
        return nextTransactionId
    }

    private static func makeSanJoseAuthCommand(_ url: URL, description: String) -> String {
        var command = url.absoluteString
        guard let index = description.firstIndex(of: "?") else {
            return command
        }
        let query = String(description[description.index(index, offsetBy: 1)...])
        let challenge = String(format: "%08x", UInt32.random(in: 0 ... UInt32.max))
        let dictionary = URL(string: "http://localhost?" + query)!.dictionaryFromQuery()
        var response = MD5.base64("\(url.user!)\(dictionary["salt"]!)\(url.password!)")
        if let opaque = dictionary["opaque"] {
            command += "&opaque=\(opaque)"
            response += opaque
        } else if let challenge: String = dictionary["challenge"] {
            response += challenge
        }
        response = MD5.base64("\(response)\(challenge)")
        command += "&challenge=\(challenge)&response=\(response)"
        return command
    }

    private func on(data: AsObject) {
        processorControlQueue.async {
            self.onInternal(data: data)
            self.stream?.onInternal(data: data)
        }
    }

    private func onInternal(data: AsObject) {
        guard let code = data["code"] as? String else {
            return
        }
        switch RtmpConnectionCode(rawValue: code) {
        case .connectSuccess:
            handleConnectSuccess()
        case .connectRejected:
            handleConnectRejected(data: data)
        case .connectClosed:
            handleConnectClosed()
        default:
            break
        }
    }

    private func handleConnectSuccess() {
        connected = true
        socket.maximumChunkSizeToServer = 1024 * 8
        _ = socket.write(chunk: RtmpChunk(
            type: .zero,
            chunkStreamId: RtmpChunk.ChunkStreamId.control.rawValue,
            message: RtmpSetChunkSizeMessage(UInt32(socket.maximumChunkSizeToServer))
        ))
    }

    private func handleConnectRejected(data: AsObject) {
        guard
            let uri,
            let user = uri.user,
            let password = uri.password,
            let description = data["description"] as? String
        else {
            return
        }
        socket.close()
        switch true {
        case description.contains("reason=nosuchuser"):
            break
        case description.contains("reason=authfailed"):
            break
        case description.contains("reason=needauth"):
            let command = Self.makeSanJoseAuthCommand(uri, description: description)
            connect(command)
        case description.contains("authmod=adobe"):
            if user.isEmpty || password.isEmpty {
                disconnect()
                break
            }
            let query = uri.query ?? ""
            let command = uri.absoluteString + (query.isEmpty ? "?" : "&") + "authmod=adobe&user=\(user)"
            connect(command)
        default:
            break
        }
    }

    private func handleConnectClosed() {
        disconnect()
    }

    private func makeConnectChunk() -> RtmpChunk? {
        guard let uri else {
            return nil
        }
        var app = String(uri.path.trimmingPrefix(while: { $0 == "/" }))
        if let query = uri.query {
            app += "?" + query
        }
        let message = RtmpCommandMessage(
            streamId: 0,
            transactionId: getNextTransactionId(),
            commandType: .amf0Command,
            commandName: "connect",
            commandObject: [
                "app": app,
                "flashVer": "FMLE/3.0 (compatible; FMSc/1.0)",
                "swfUrl": nil,
                "tcUrl": uri.absoluteWithoutAuthenticationString,
                "fpad": false,
                "capabilities": 239,
                "audioCodecs": SupportSound.aac.rawValue,
                "videoCodecs": SupportVideo.h264.rawValue,
                "videoFunction": VideoFunction.clientSeek.rawValue,
                "pageUrl": nil,
                "objectEncoding": 0,
            ],
            arguments: []
        )
        return RtmpChunk(message: message)
    }

    private func handleHandshakeDone() {
        guard let chunk = makeConnectChunk() else {
            disconnect()
            return
        }
        _ = socket.write(chunk: chunk)
        timer.startPeriodic(interval: 1.0, handler: { [weak self] in
            guard let self else {
                return
            }
            stream?.onTimeout()
        })
    }

    private func handleClosed() {
        connected = false
        currentChunk = nil
        nextTransactionId = 0
        messages.removeAll()
        callCompletions.removeAll()
        fragmentedChunks.removeAll()
    }
}

extension RtmpConnection: RtmpSocketDelegate {
    func socketReadyStateChanged(readyState: RtmpSocketReadyState) {
        switch readyState {
        case .handshakeDone:
            handleHandshakeDone()
        case .closed:
            handleClosed()
        default:
            break
        }
    }

    func socketUpdateStats(totalBytesSent: Int64) {
        stream?.info.onWritten(sequence: totalBytesSent)
    }

    func socketDataReceived(_ socket: RtmpSocket, data: Data) -> Data {
        guard let chunk = currentChunk ?? RtmpChunk(data: data, size: socket.maximumChunkSizeFromServer) else {
            return data
        }
        let encoded = chunk.encode()
        var offset = encoded.count
        if (encoded.count >= 4) && (encoded[1] == 0xFF) && (encoded[2] == 0xFF) && (encoded[3] == 0xFF) {
            offset += 4
        }
        if currentChunk != nil {
            offset = chunk.append(data: data, maximumSize: socket.maximumChunkSizeFromServer)
        }
        if chunk.type == .two {
            offset = chunk.append(data: data, message: messages[chunk.chunkStreamId])
        }
        if chunk.type == .three && fragmentedChunks[chunk.chunkStreamId] == nil {
            offset = chunk.append(data: data, message: messages[chunk.chunkStreamId])
        }
        if let message = chunk.message, chunk.ready() {
            switch chunk.type {
            case .zero:
                chunkStreamIdToStreamId[chunk.chunkStreamId] = message.streamId
            case .one:
                if let streamId = chunkStreamIdToStreamId[chunk.chunkStreamId] {
                    message.streamId = streamId
                }
            default:
                break
            }
            message.execute(self)
            currentChunk = nil
            messages[chunk.chunkStreamId] = message
        } else {
            if chunk.fragmented {
                fragmentedChunks[chunk.chunkStreamId] = chunk
                currentChunk = nil
            } else {
                currentChunk = chunk.type == .three ? fragmentedChunks[chunk.chunkStreamId] : chunk
                fragmentedChunks.removeValue(forKey: chunk.chunkStreamId)
            }
        }
        if offset > 0 && offset < data.count {
            return socketDataReceived(socket, data: data.advanced(by: offset))
        }
        return Data()
    }

    func socketPost(data: AsObject) {
        on(data: data)
    }
}
