//
//  PlayerConfig.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import Foundation
import NostrSDK
import SwiftUI

enum PlayerState: Equatable {
    case hidden
    case minimized
    case fullscreen
    case fullscreenWithChat
}

enum VideoAspectRatio: Equatable {
    case landscape16_9
    case portrait9_16
    case square1_1
    case unknown

    var ratio: CGFloat {
        switch self {
        case .landscape16_9: return 16.0 / 9.0
        case .portrait9_16: return 9.0 / 16.0
        case .square1_1: return 1.0
        case .unknown: return 16.0 / 9.0  // Default to landscape
        }
    }
}

struct PlayerConfig: Equatable {
    var position: CGFloat = .zero
    var lastPosition: CGFloat = .zero
    var progress: CGFloat = .zero
    var selectedLiveActivitiesEvent: LiveActivitiesEvent?
    var showMiniPlayer: Bool = false

    // YouTube-like draggable player properties
    var playerState: PlayerState = .hidden
    var draggablePosition: CGPoint = CGPoint(x: 0, y: 0)
    var lastDraggablePosition: CGPoint = CGPoint(x: 0, y: 0)
    var isDragging: Bool = false
    var miniPlayerSize: CGSize = CGSize(width: 240, height: 135)  // 16:9 aspect ratio
    var cornerRadius: CGFloat = 12
    var shadowOpacity: Double = 0.3

    // Animation and interaction properties
    var dragVelocity: CGSize = .zero
    var snapToEdge: Bool = true
    var isAnimating: Bool = false

    // LiveChatView integration properties
    var chatRevealProgress: CGFloat = 0.0  // 0 = hidden, 1 = fully revealed
    var isDraggingChat: Bool = false
    var chatDragOffset: CGFloat = 0.0
    var showChatByDefault: Bool = false

    // Video aspect ratio and sizing
    var videoAspectRatio: VideoAspectRatio = .unknown
    var videoSize: CGSize = .zero
    var adaptiveVideoSize: CGSize = .zero

    mutating func resetPosition() {
        position = .zero
        lastPosition = .zero
        progress = .zero
        playerState = .hidden
        draggablePosition = CGPoint(x: 0, y: 0)
        lastDraggablePosition = CGPoint(x: 0, y: 0)
        isDragging = false
        isAnimating = false
        chatRevealProgress = 0.0
        isDraggingChat = false
        chatDragOffset = 0.0
    }

    mutating func setMinimizedState() {
        playerState = .minimized
        showMiniPlayer = true
    }

    mutating func setFullscreenState() {
        playerState = showChatByDefault ? .fullscreenWithChat : .fullscreen
        showMiniPlayer = true
        chatRevealProgress = showChatByDefault ? 1.0 : 0.0
    }

    mutating func toggleChatDefault() {
        showChatByDefault.toggle()
    }

    mutating func setFullscreenWithChatState() {
        playerState = .fullscreenWithChat
        showMiniPlayer = true
        chatRevealProgress = 1.0
    }

    mutating func setHiddenState() {
        playerState = .hidden
        showMiniPlayer = false
        resetPosition()
    }

    // MARK: - Video Aspect Ratio Helpers

    mutating func updateVideoAspectRatio(from size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }

        let ratio = size.width / size.height

        if ratio > 1.5 {
            videoAspectRatio = .landscape16_9
        } else if ratio < 0.7 {
            videoAspectRatio = .portrait9_16
        } else if ratio > 0.9 && ratio < 1.1 {
            videoAspectRatio = .square1_1
        } else {
            videoAspectRatio = .unknown
        }

        videoSize = size
        updateAdaptiveVideoSize()
    }

    mutating func updateAdaptiveVideoSize() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        switch videoAspectRatio {
        case .landscape16_9:
            adaptiveVideoSize = CGSize(
                width: screenWidth, height: screenWidth / videoAspectRatio.ratio)
        case .portrait9_16:
            adaptiveVideoSize = CGSize(
                width: screenWidth, height: screenWidth / videoAspectRatio.ratio)
        case .square1_1:
            adaptiveVideoSize = CGSize(width: screenWidth, height: screenWidth)
        case .unknown:
            adaptiveVideoSize = CGSize(width: screenWidth, height: screenWidth / (16.0 / 9.0))
        }
    }

    // Initialize with default values
    mutating func initializeDefaults() {
        if adaptiveVideoSize == .zero {
            adaptiveVideoSize = CGSize(
                width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width / (16.0 / 9.0)
            )
        }
    }
}
