import UIKit

extension Model {
    private func handleSettingsUrlsDefaultStreams(settings: SwaeSettingsUrl) {
        var newSelectedStream: SettingsStream?
        for stream in settings.streams ?? [] {
            let newStream = SettingsStream(name: stream.name)
            newStream.url = stream.url.trim()
            if stream.selected == true {
                newSelectedStream = newStream
            }
            if let video = stream.video {
                if let resolution = video.resolution {
                    newStream.resolution = resolution
                }
                if let fps = video.fps, fpss.contains(fps) {
                    newStream.fps = fps
                }
                if let bitrate = video.bitrate, bitrate >= 50000, bitrate <= 50_000_000 {
                    newStream.bitrate = bitrate
                }
                if let codec = video.codec {
                    newStream.codec = codec
                }
                if let bFrames = video.bFrames {
                    newStream.bFrames = bFrames
                }
                if let maxKeyFrameInterval = video.maxKeyFrameInterval, maxKeyFrameInterval >= 0,
                    maxKeyFrameInterval <= 10
                {
                    newStream.maxKeyFrameInterval = maxKeyFrameInterval
                }
            }
            if let audio = stream.audio {
                if let bitrate = audio.bitrate, isValidAudioBitrate(bitrate: bitrate) {
                    newStream.audioBitrate = bitrate
                }
            }
            if let srt = stream.srt {
                if let latency = srt.latency {
                    newStream.srt.latency = latency
                }
                if let adaptiveBitrateEnabled = srt.adaptiveBitrateEnabled {
                    newStream.srt.adaptiveBitrateEnabled = adaptiveBitrateEnabled
                }
                if let dnsLookupStrategy = srt.dnsLookupStrategy {
                    newStream.srt.dnsLookupStrategy = dnsLookupStrategy
                }
            }
            if let obs = stream.obs {
                newStream.obsWebSocketEnabled = true
                newStream.obsWebSocketUrl = obs.webSocketUrl.trim()
                newStream.obsWebSocketPassword = obs.webSocketPassword.trim()
            }
            if let twitch = stream.twitch {
                newStream.twitchChannelName = twitch.channelName.trim()
                newStream.twitchChannelId = twitch.channelId.trim()
            }
            if let kick = stream.kick {
                newStream.kickChannelName = kick.channelName.trim()
            }
            database.streams.append(newStream)
        }
        if let newSelectedStream, !isLive, !isRecording {
            setCurrentStream(stream: newSelectedStream)
        }
    }

    private func handleSettingsUrlsDefaultQuickButtons(settings: SwaeSettingsUrl) {
        guard let quickButtons = settings.quickButtons else {
            return
        }
        if let twoColumns = quickButtons.twoColumns {
            database.quickButtonsGeneral.twoColumns = twoColumns
        }
        if let showName = quickButtons.showName {
            database.quickButtonsGeneral.showName = showName
        }
        if let enableScroll = quickButtons.enableScroll {
            database.quickButtonsGeneral.enableScroll = enableScroll
        }
        if quickButtons.disableAllButtons == true {
            for globalButton in database.quickButtons {
                globalButton.enabled = false
            }
        }
        for button in quickButtons.buttons ?? [] {
            for globalButton in database.quickButtons {
                guard button.type == globalButton.type else {
                    continue
                }
                if let enabled = button.enabled {
                    globalButton.enabled = enabled
                }
            }
        }
    }

    private func handleSettingsUrlsDefaultWebBrowser(settings: SwaeSettingsUrl) {
        guard let webBrowser = settings.webBrowser else {
            return
        }
        if let home = webBrowser.home {
            database.webBrowser.home = home
        }
    }

    private func handleSettingsUrlsDefaultRemoteControl(settings: SwaeSettingsUrl) {
        guard let remoteControl = settings.remoteControl else {
            return
        }
        if let assistant = remoteControl.assistant {
            database.remoteControl.assistant.enabled = assistant.enabled
            database.remoteControl.assistant.port = assistant.port
            if let relay = assistant.relay {
                database.remoteControl.assistant.relay.enabled = relay.enabled
                database.remoteControl.assistant.relay.baseUrl = relay.baseUrl.trim()
                database.remoteControl.assistant.relay.bridgeId = relay.bridgeId.trim()
            }
        }
        if let streamer = remoteControl.streamer {
            database.remoteControl.streamer.enabled = streamer.enabled
            database.remoteControl.streamer.url = streamer.url.trim()
        }
        database.remoteControl.password = remoteControl.password
        reloadRemoteControlStreamer()
        reloadRemoteControlAssistant()
        reloadRemoteControlRelay()
    }

    private func handleSettingsUrlsDefault(settings: SwaeSettingsUrl) {
        handleSettingsUrlsDefaultStreams(settings: settings)
        handleSettingsUrlsDefaultQuickButtons(settings: settings)
        handleSettingsUrlsDefaultWebBrowser(settings: settings)
        handleSettingsUrlsDefaultRemoteControl(settings: settings)
        makeToast(title: String(localized: "URL import successful"))
        updateQuickButtonStates()
    }

    func handleSettingsUrls(urls: Set<UIOpenURLContext>) {
        for url in urls {
            if let message = handleSettingsUrl(url: url.url) {
                makeErrorToast(
                    title: String(localized: "URL import failed"),
                    subTitle: message
                )
            }
        }
    }

    func handleSettingsUrl(url: URL) -> String? {
        guard url.path.isEmpty else {
            return "Custom URL path is not empty"
        }
        guard let query = url.query(percentEncoded: false) else {
            return "Custom URL query is missing"
        }
        let settings: SwaeSettingsUrl
        do {
            settings = try SwaeSettingsUrl.fromString(query: query)
        } catch {
            return error.localizedDescription
        }
        if createStreamWizard.isPresenting || createStreamWizard.isPresentingSetup {
            handleSettingsUrlsInWizard(settings: settings)
        } else {
            handleSettingsUrlsDefault(settings: settings)
        }
        return nil
    }
}
