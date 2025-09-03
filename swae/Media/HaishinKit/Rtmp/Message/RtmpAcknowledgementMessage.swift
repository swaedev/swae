import Foundation

final class RtmpAcknowledgementMessage: RtmpMessage {
    var sequence: UInt32 = 0

    init() {
        super.init(type: .ack)
    }

    override func execute(_ connection: RtmpConnection) {
        connection.stream?.info.onAck(sequence: sequence)
    }

    override var encoded: Data {
        get {
            guard super.encoded.isEmpty else {
                return super.encoded
            }
            super.encoded = sequence.bigEndian.data
            return super.encoded
        }
        set {
            if super.encoded == newValue {
                return
            }
            sequence = UInt32(data: newValue).bigEndian
            super.encoded = newValue
        }
    }
}
