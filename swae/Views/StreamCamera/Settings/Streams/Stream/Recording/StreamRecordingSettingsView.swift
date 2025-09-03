import SwiftUI

private struct PickerView: UIViewControllerRepresentable {
    @EnvironmentObject var model: Model

    func makeUIViewController(context _: Context) -> UIDocumentPickerViewController {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        documentPicker.delegate = model
        return documentPicker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}
}

private struct RecordingPathView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var stream: SettingsStream
    @ObservedObject var recording: SettingsStreamRecording
    @State var showPicker = false

    private func onUrl(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        do {
            recording.recordingPath = try url.bookmarkData()
        } catch {
            logger.info("Failed to create bookmark with error: \(error)")
        }
        url.stopAccessingSecurityScopedResource()
    }

    private func getRecordingPath(recordingPath: Data) -> String {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: recordingPath, bookmarkDataIsStale: &isStale) {
            return url.absoluteString
        } else {
            return String(localized: "Disk not connected?")
        }
    }

    var body: some View {
        NavigationLink {
            Form {
                Section {
                    Button {
                        showPicker = true
                        model.onDocumentPickerUrl = onUrl
                    } label: {
                        HCenter {
                            if let recordingPath = recording.recordingPath {
                                Text(getRecordingPath(recordingPath: recordingPath))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            } else {
                                Text("Select")
                            }
                        }
                    }
                    .sheet(isPresented: $showPicker) {
                        PickerView()
                    }
                } header: {
                    Text("Folder")
                }
                Section {
                    Button {
                        recording.recordingPath = nil
                    } label: {
                        HCenter {
                            Text("Reset")
                                .tint(.red)
                        }
                    }
                }
            }
            .navigationTitle("Recording path")
        } label: {
            HStack {
                Text("Recording path")
                Spacer()
                if let recordingPath = recording.recordingPath {
                    Text(getRecordingPath(recordingPath: recordingPath))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

struct StreamRecordingSettingsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var stream: SettingsStream
    @ObservedObject var recording: SettingsStreamRecording

    private func submitVideoBitrateChange(value: String) {
        guard var bitrate = Float(value) else {
            return
        }
        bitrate = max(bitrate, 0)
        bitrate = min(bitrate, 50)
        recording.videoBitrate = bitrateFromMbps(bitrate: bitrate)
    }

    private func submitMaxKeyFrameInterval(value: String) {
        guard let interval = Int32(value) else {
            return
        }
        guard interval >= 0, interval <= 10 else {
            return
        }
        recording.maxKeyFrameInterval = interval
    }

    var body: some View {
        Form {
            Section {
                Picker("Video codec", selection: $recording.videoCodec) {
                    ForEach(SettingsStreamCodec.allCases, id: \.self) {
                        Text($0.rawValue)
                    }
                }
                .disabled(stream.enabled && model.isRecording)
                NavigationLink {
                    TextEditView(
                        title: String(localized: "Video bitrate"),
                        value: String(bitrateToMbps(bitrate: recording.videoBitrate)),
                        footers: [String(localized: "Up to 50 Mbps. Set to 0 for automatic.")],
                        keyboardType: .numbersAndPunctuation
                    ) {
                        submitVideoBitrateChange(value: $0)
                    }
                } label: {
                    TextItemView(
                        name: String(localized: "Video bitrate"),
                        value: recording.videoBitrateString()
                    )
                }
                .disabled(stream.enabled && model.isRecording)
                NavigationLink {
                    TextEditView(
                        title: String(localized: "Key frame interval"),
                        value: String(recording.maxKeyFrameInterval),
                        footers: [
                            String(localized: "Maximum key frame interval in seconds. Set to 0 for automatic."),
                        ],
                        keyboardType: .numbersAndPunctuation
                    ) {
                        submitMaxKeyFrameInterval(value: $0)
                    }
                } label: {
                    TextItemView(
                        name: String(localized: "Key frame interval"),
                        value: recording.maxKeyFrameIntervalString()
                    )
                }
                .disabled(stream.enabled && model.isRecording)
                NavigationLink {
                    StreamRecordingAudioSettingsView(
                        stream: stream,
                        bitrate: Float(recording.audioBitrate / 1000)
                    )
                } label: {
                    TextItemView(
                        name: String(localized: "Audio bitrate"),
                        value: recording.audioBitrateString()
                    )
                }
                .disabled(stream.enabled && model.isRecording)
            } footer: {
                Text("Resolution and FPS are same as for live stream.")
            }
            RecordingPathView(stream: stream, recording: recording)
            Section {
                Toggle("Clean recordings", isOn: $recording.cleanRecordings)
                    .onChange(of: recording.cleanRecordings) { _ in
                        model.setCleanRecordings()
                    }
            } footer: {
                Text("Do not show widgets in recordings.")
            }
            Section {
                Toggle("Auto start recording when going live", isOn: $recording.autoStartRecording)
                Toggle("Auto stop recording when ending stream", isOn: $recording.autoStopRecording)
            }
        }
        .navigationTitle("Recording")
    }
}
