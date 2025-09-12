//
//  YouTubeVideoPlayer.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import SwiftUI
import UIKit

struct YouTubeVideoPlayer: UIViewControllerRepresentable {
    var player: AVPlayer
    @Binding var videoSize: CGSize
    @Binding var actualVideoFrame: CGRect

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect  // Preserve aspect ratio, show black bars when needed

        print("YouTubeVideoPlayer: Created controller with player: \(player)")
        print("YouTubeVideoPlayer: Player item: \(player.currentItem?.description ?? "nil")")

        // Observe video size
        if player.currentItem != nil {
            player.currentItem?.addObserver(
                context.coordinator, forKeyPath: "presentationSize", options: .new, context: nil)
            print("YouTubeVideoPlayer: Added observer for presentationSize")
        } else {
            print("YouTubeVideoPlayer: No current item to observe")
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Update the actual video frame based on the container size and video aspect ratio
        DispatchQueue.main.async {
            updateActualVideoFrame()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    private func updateActualVideoFrame() {
        guard videoSize.width > 0 && videoSize.height > 0 else { return }

        // Calculate the actual video frame within the container
        // This will be used to determine where the chat should be positioned
        let containerSize = UIScreen.main.bounds.size
        let videoAspectRatio = videoSize.width / videoSize.height
        let containerAspectRatio = containerSize.width / containerSize.height

        let actualFrame: CGRect

        if videoAspectRatio > containerAspectRatio {
            // Video is wider than container - video fills height, crops width
            let videoHeight = containerSize.height
            let videoWidth = videoHeight * videoAspectRatio
            let xOffset = (containerSize.width - videoWidth) / 2
            actualFrame = CGRect(x: xOffset, y: 0, width: videoWidth, height: videoHeight)
        } else {
            // Video is taller than container - video fills width, crops height
            let videoWidth = containerSize.width
            let videoHeight = videoWidth / videoAspectRatio
            let yOffset = (containerSize.height - videoHeight) / 2
            actualFrame = CGRect(x: 0, y: yOffset, width: videoWidth, height: videoHeight)
        }

        actualVideoFrame = actualFrame
    }

    class Coordinator: NSObject {
        var parent: YouTubeVideoPlayer

        init(_ parent: YouTubeVideoPlayer) {
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
                print("YouTubeVideoPlayer: Detected video size: \(newSize)")
                DispatchQueue.main.async {
                    self.parent.videoSize = newSize
                    self.parent.updateActualVideoFrame()
                }
            }
        }
    }
}
