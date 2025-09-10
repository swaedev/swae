//
//  PlayerConfig.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import Foundation
import NostrSDK

enum PlayerState: Equatable {
    case hidden
    case minimized
    case fullscreen
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

    mutating func resetPosition() {
        position = .zero
        lastPosition = .zero
        progress = .zero
        playerState = .hidden
        draggablePosition = CGPoint(x: 0, y: 0)
        lastDraggablePosition = CGPoint(x: 0, y: 0)
        isDragging = false
        isAnimating = false
    }

    mutating func setMinimizedState() {
        playerState = .minimized
        showMiniPlayer = true
    }

    mutating func setFullscreenState() {
        playerState = .fullscreen
        showMiniPlayer = true
    }

    mutating func setHiddenState() {
        playerState = .hidden
        showMiniPlayer = false
        resetPosition()
    }
}
