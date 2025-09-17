//
//  CustomVideoPlayer.swift
//  swae
//
//  Created by Suhail Saqan on 1/25/25.
//

import AVKit
import SwiftUI

struct CustomVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer
    @Binding var videoSize: CGSize

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect

        // Set up video size observation
        context.coordinator.updateObservedItem(player.currentItem)

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Critical: Update the player when it changes
        if uiViewController.player !== player {
            uiViewController.player = player

            // Force video layer refresh when player changes
            DispatchQueue.main.async {
                // Small delay to ensure player is properly set
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Force a seek to refresh the video layer
                    let currentTime = self.player.currentTime()
                    self.player.seek(to: currentTime) { _ in
                        // Video layer should now be properly refreshed
                    }
                }
            }
        }

        // Update video gravity if needed
        uiViewController.videoGravity = .resizeAspect

        // Update observer for video size detection
        context.coordinator.updateObservedItem(player.currentItem)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: CustomVideoPlayer
        private var observedItem: AVPlayerItem?

        init(_ parent: CustomVideoPlayer) {
            self.parent = parent
        }

        deinit {
            // Clean up observer
            if let item = observedItem {
                item.removeObserver(self, forKeyPath: "presentationSize")
            }
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

        func updateObservedItem(_ newItem: AVPlayerItem?) {
            // Remove old observer
            if let oldItem = observedItem {
                oldItem.removeObserver(self, forKeyPath: "presentationSize")
            }

            // Add new observer
            if let newItem = newItem {
                newItem.addObserver(
                    self, forKeyPath: "presentationSize", options: .new, context: nil)
            }

            observedItem = newItem
        }
    }
}
