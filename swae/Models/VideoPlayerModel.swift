//
//  VideoPlayerModel.swift
//  swae
//
//  Created by Suhail Saqan on 1/28/25.
//

import AVKit
import Combine
import SwiftUI
import UIKit

// The model that holds video-related properties and controls
class VideoPlayerModel: ObservableObject {
    @Published var player: AVPlayer
    @Published var isPlaying: Bool = false
    @Published var showPlayerControls: Bool = false
    @Published var progress: CGFloat = 0
    @Published var isFinishedPlaying: Bool = false
    @Published var isSeeking: Bool = false
    @Published var isLoading: Bool = false
    @Published var playerError: Bool = false
    @Published var thumbnailFrames: [UIImage] = []
    @Published var draggingImage: UIImage?
    @Published var isRotated: Bool = false
    @Published var lastDraggedProgress: CGFloat = 0
    @Published var timeoutTask: DispatchWorkItem?
    @Published var isObserverAdded: Bool = false
    @Published var playerStatusObserver: NSKeyValueObservation?
    @Published var isInMiniPlayerMode: Bool = false
    @Published var shouldOptimizeForMiniPlayer: Bool = false
    @Published var detectedVideoSize: CGSize = .zero

    private var cancellables = Set<AnyCancellable>()
    private var timeObserver: Any?

    init(url: URL) {
        self.player = AVPlayer(url: url)
        observeTimeControlStatus()
    }

    // Handle video play/pause
    func togglePlay() {
        if isFinishedPlaying {
            isFinishedPlaying = false
            player.seek(to: .zero)
            progress = 0
            lastDraggedProgress = 0
        }

        if isPlaying {
            player.pause()
            timeoutControls()
        } else {
            player.play()
            timeoutControls()
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            isPlaying.toggle()
        }
    }

    // Handles timeout for controls visibility
    func timeoutControls() {
        if let timeoutTask {
            timeoutTask.cancel()
        }

        timeoutTask = .init(block: {
            withAnimation(.easeInOut(duration: 0.35)) {
                self.showPlayerControls = false
            }
        })

        if let timeoutTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeoutTask)
        }
    }

    // Video player time observer setup
    func addTimeObserver() {
        guard !isObserverAdded else { return }

        // Use different intervals based on player mode for performance
        let interval = isInMiniPlayerMode ? 2.0 : 1.0  // Less frequent updates in mini player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: interval, preferredTimescale: 600), queue: .main
        ) { time in
            guard let currentPlayerItem = self.player.currentItem else { return }
            let totalDuration = currentPlayerItem.duration.seconds
            let currentDuration = self.player.currentTime().seconds

            let calculatedProgress = currentDuration / totalDuration
            if !self.isSeeking {
                self.progress = calculatedProgress
                self.lastDraggedProgress = self.progress
            }

            if calculatedProgress == 1 {
                self.isFinishedPlaying = true
                self.isPlaying = false
            }
        }

        isObserverAdded = true
    }

    // Remove time observer for cleanup
    func removeTimeObserver() {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        isObserverAdded = false
    }

    // Seek functionality with thumbnails
    func seek(to progress: CGFloat) {
        guard let currentPlayerItem = player.currentItem else { return }
        let totalDuration = currentPlayerItem.duration.seconds
        player.seek(to: .init(seconds: totalDuration * Double(progress), preferredTimescale: 600))
        lastDraggedProgress = progress
    }

    // Generate thumbnail frames for seeking
    func generateThumbnailFrames() {
        Task {
            guard let asset = player.currentItem?.asset else { return }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 250, height: 250)

            do {
                let totalDuration = try await asset.load(.duration).seconds
                var frameTimes: [CMTime] = []

                for progress in stride(from: 0, to: 1, by: 0.01) {
                    let time = CMTime(seconds: progress * totalDuration, preferredTimescale: 600)
                    frameTimes.append(time)
                }

                for try await result in generator.images(for: frameTimes) {
                    let cgImage = try result.image
                    await MainActor.run {
                        self.thumbnailFrames.append(UIImage(cgImage: cgImage))
                    }
                }
            } catch {
                print("Error generating thumbnail frames: \(error.localizedDescription)")
            }
        }
    }

    @objc func videoDidFinishPlaying() {
        // Handle video finish logic here
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isFinishedPlaying = true
        }
    }

    // MARK: - Performance Optimization Methods

    func setMiniPlayerMode(_ isMini: Bool) {
        isInMiniPlayerMode = isMini
        shouldOptimizeForMiniPlayer = isMini

        if isMini {
            optimizeForMiniPlayer()
        } else {
            optimizeForFullscreen()
        }
    }

    private func optimizeForMiniPlayer() {
        // Reduce quality for better performance
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 500_000  // 500 kbps
        }

        // Reduce thumbnail generation frequency
        if thumbnailFrames.count > 50 {
            thumbnailFrames = Array(thumbnailFrames.prefix(50))
        }
    }

    private func optimizeForFullscreen() {
        // Higher quality for fullscreen
        if let currentItem = player.currentItem {
            currentItem.preferredPeakBitRate = 2_000_000  // 2 Mbps
        }
    }

    // Detect video size and aspect ratio
    func detectVideoSize() {
        guard let item = player.currentItem else { return }
        let size = item.presentationSize
        if size.width > 0 && size.height > 0 {
            detectedVideoSize = size
        }
    }

    // Cleanup method for proper resource management
    func cleanup() {
        removeTimeObserver()
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        player.pause()
        cancellables.removeAll()
    }

    private func observeTimeControlStatus() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }

                let loading = (status == .waitingToPlayAtSpecifiedRate)
                self.isLoading = loading

                withAnimation(.easeInOut(duration: 0.15)) {
                    self.showPlayerControls = loading
                }

                // Check if playback fails
                if status == .paused, let error = self.player.currentItem?.error {
                    print("Playback error: \(error.localizedDescription)")
                    self.playerError = true
                }
            }
            .store(in: &cancellables)
    }
}
