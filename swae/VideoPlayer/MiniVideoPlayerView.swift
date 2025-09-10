//
//  MiniVideoPlayerView.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import SwiftUI

struct MiniVideoPlayerView: View {
    @ObservedObject var videoModel: VideoPlayerModel
    let size: CGSize
    let isMinimized: Bool

    @State private var isVisible: Bool = false

    var body: some View {
        ZStack {
            // Video player
            CustomVideoPlayer(player: videoModel.player, videoSize: .constant(size))
                .onAppear {
                    isVisible = true
                    if isMinimized {
                        // For mini player, we want to maintain playback but optimize performance
                        setupMiniPlayerMode()
                    } else {
                        setupFullscreenMode()
                    }
                }
                .onDisappear {
                    isVisible = false
                    cleanupPlayer()
                }
                .onChange(of: isMinimized) { _, newValue in
                    if newValue {
                        setupMiniPlayerMode()
                    } else {
                        setupFullscreenMode()
                    }
                }

            // Loading indicator
            if videoModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }

            // Error state
            if videoModel.playerError {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: isMinimized ? 16 : 24))
                        .foregroundColor(.white)
                    if !isMinimized {
                        Text("Playback Error")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }
            }

            // Play/Pause overlay for mini player
            if isMinimized && !videoModel.isLoading && !videoModel.playerError {
                Button(action: {
                    videoModel.togglePlay()
                }) {
                    Image(systemName: videoModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .opacity(videoModel.showPlayerControls ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: videoModel.showPlayerControls)
            }
        }
        .background(Color.black)
        .onTapGesture {
            if isMinimized {
                withAnimation(.easeInOut(duration: 0.2)) {
                    videoModel.showPlayerControls.toggle()
                }

                if videoModel.isPlaying {
                    videoModel.timeoutControls()
                }
            }
        }
    }

    private func setupMiniPlayerMode() {
        // Optimize for mini player performance
        videoModel.player.volume = 0.0  // Mute by default in mini player
        videoModel.player.rate = videoModel.isPlaying ? 1.0 : 0.0

        // Reduce quality for better performance in mini mode
        if let currentItem = videoModel.player.currentItem {
            // Enable automatic quality adjustment for mini player
            currentItem.preferredPeakBitRate = 500_000  // 500 kbps for mini player
        }
    }

    private func setupFullscreenMode() {
        // Full quality for fullscreen mode
        videoModel.player.volume = 1.0
        videoModel.player.rate = videoModel.isPlaying ? 1.0 : 0.0

        if let currentItem = videoModel.player.currentItem {
            // Higher quality for fullscreen
            currentItem.preferredPeakBitRate = 2_000_000  // 2 Mbps for fullscreen
        }
    }

    private func cleanupPlayer() {
        // Pause when not visible to save resources
        videoModel.player.pause()
    }
}

// MARK: - Optimized Custom Video Player for Mini Mode

struct OptimizedCustomVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer
    @Binding var videoSize: CGSize
    let isMinimized: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = isMinimized ? .resizeAspectFill : .resizeAspect

        // Optimize for mini player
        if isMinimized {
            controller.allowsPictureInPicturePlayback = false
            controller.canStartPictureInPictureAutomaticallyFromInline = false
        }

        // Observe video size
        if let item = player.currentItem {
            item.addObserver(
                context.coordinator, forKeyPath: "presentationSize", options: .new, context: nil)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.videoGravity = isMinimized ? .resizeAspectFill : .resizeAspect
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: OptimizedCustomVideoPlayer

        init(_ parent: OptimizedCustomVideoPlayer) {
            self.parent = parent
        }

        override func observeValue(
            forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            if keyPath == "presentationSize",
                let item = object as? AVPlayerItem,
                let newSize = change?[.newKey] as? CGSize
            {
                DispatchQueue.main.async {
                    self.parent.videoSize = newSize
                }
            }
        }
    }
}
