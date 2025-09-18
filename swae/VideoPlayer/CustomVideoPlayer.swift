//
//  CustomVideoPlayer.swift
//  swae
//
//  Created by Suhail Saqan on 1/25/25.
//

import AVKit
import SwiftUI

/// A SwiftUI video player that displays videos at their exact natural dimensions
/// without cropping or adding black bars above/below the video.
///
/// Key Features:
/// - Uses AVPlayerLayer directly for precise sizing control
/// - Never crops the video content
/// - No black bars above or below (only on sides if needed)
/// - Dynamically resizes to match video's natural resolution
/// - Preserves aspect ratio with .resizeAspect gravity
struct CustomVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    @Binding var videoSize: CGSize

    func makeUIView(context: Context) -> ExactVideoPlayerView {
        let view = ExactVideoPlayerView()
        view.player = player
        view.coordinator = context.coordinator

        // Set up video size observation
        context.coordinator.updateObservedItem(player.currentItem)

        return view
    }

    func updateUIView(_ uiView: ExactVideoPlayerView, context: Context) {
        // Update player when it changes
        if uiView.player !== player {
            uiView.player = player
            context.coordinator.updateObservedItem(player.currentItem)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: CustomVideoPlayer
        private var observedItem: AVPlayerItem?
        private var presentationSizeObserver: NSKeyValueObservation?

        init(_ parent: CustomVideoPlayer) {
            self.parent = parent
        }

        deinit {
            cleanupObservers()
        }

        func updateObservedItem(_ newItem: AVPlayerItem?) {
            // Clean up existing observer
            cleanupObservers()

            // Add new observer for presentation size changes
            if let newItem = newItem {
                presentationSizeObserver = newItem.observe(\.presentationSize, options: [.new]) {
                    [weak self] item, _ in
                    DispatchQueue.main.async {
                        let size = item.presentationSize
                        if size.width > 0 && size.height > 0 {
                            self?.parent.videoSize = size
                        }
                    }
                }
            }

            observedItem = newItem
        }

        private func cleanupObservers() {
            presentationSizeObserver?.invalidate()
            presentationSizeObserver = nil
        }
    }
}

/// Custom UIView that wraps AVPlayerLayer for precise video sizing
class ExactVideoPlayerView: UIView {
    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
        }
    }

    weak var coordinator: CustomVideoPlayer.Coordinator?

    private var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPlayerLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayerLayer()
    }

    private func setupPlayerLayer() {
        // Configure player layer for exact video sizing
        playerLayer.videoGravity = .resizeAspect  // Preserve aspect ratio, no cropping
        playerLayer.backgroundColor = UIColor.black.cgColor  // Black background for letterboxing

        // Ensure the layer fills the view bounds
        playerLayer.frame = bounds
        playerLayer.masksToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure player layer always fills the view
        playerLayer.frame = bounds
    }
}
