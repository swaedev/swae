//
//  YouTubeFullscreenPlayerView.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import SwiftUI
import UIKit

struct YouTubeFullscreenPlayerView: View {
    @EnvironmentObject var orientationMonitor: OrientationMonitor
    @EnvironmentObject var appState: AppState

    var screenSize: CGSize
    @Binding var playerConfig: PlayerConfig
    var onClose: () -> Void

    @GestureState private var dragTranslation: CGFloat = 0

    init(
        screenSize: CGSize,
        playerConfig: Binding<PlayerConfig>,
        onClose: @escaping () -> Void
    ) {
        self.screenSize = screenSize
        self._playerConfig = playerConfig
        self.onClose = onClose
    }

    // MARK: - Safe area helper
    private var safeAreaInsets: UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {
            return window.safeAreaInsets
        }
        return .zero
    }

    // MARK: - Layout constants computed from screen + safe area
    private var availableHeight: CGFloat {
        screenSize.height - safeAreaInsets.top
    }
    private var collapsedVideoRatio: CGFloat { 0.35 }  // when chat is fully shown, video takes 30%
    private var expandedVideoRatio: CGFloat { 1.0 }  // when chat hidden, video takes 100%

    private var videoHeightForProgress: (CGFloat) -> CGFloat = { _ in 0 }  // will be set in computed property below

    // Distance the chat must move from hidden -> shown (top Y coordinate difference)
    private var chatRevealDistance: CGFloat {
        // Use a fixed calculation to avoid circular dependency
        // Assume video takes 35% of available height when chat is shown
        let videoHeightWhenChatShown = availableHeight * 0.35
        let shownY = safeAreaInsets.top + videoHeightWhenChatShown
        let hiddenY = screenSize.height
        return hiddenY - shownY
    }

    // MARK: - Derived positions & sizes based on playerConfig.chatRevealProgress & dragTranslation
    private var progressClamped: CGFloat {
        max(0, min(1, playerConfig.chatRevealProgress))
    }

    // Effective progress while dragging (incorporates dragTranslation gesture)
    private func effectiveProgress(forDrag drag: CGFloat) -> CGFloat {
        // drag is value.translation.height from DragGesture (positive when dragging down)
        let distance = chatRevealDistance
        guard distance > 0 else { return progressClamped }

        // When drag is positive (dragging down) the progress decreases.
        // Compute delta progress = -drag / distance
        let delta = -drag / distance
        let newProgress = progressClamped + delta

        // Use a smoother interpolation for more responsive dragging
        return max(0, min(1, newProgress))
    }

    // videoHeight computed using effectiveProgress while dragging
    private func videoHeight(usingDrag drag: CGFloat) -> CGFloat {
        // Get the actual video frame size
        let actualVideoFrame = videoFrame(usingDrag: drag)
        return actualVideoFrame.height
    }

    // videoPositionY computed to center video when chat is hidden
    private func videoPositionY(usingDrag drag: CGFloat) -> CGFloat {
        let t = effectiveProgress(forDrag: drag)  // 0 => expanded (full), 1 => collapsed (35%)
        let videoHeight = videoFrame(usingDrag: drag).height  // Get height directly to avoid circular dependency

        if t < 0.1 {  // Chat is hidden - center the video vertically
            return screenSize.height / 2
        } else {  // Chat is shown - position at top
            return safeAreaInsets.top + videoHeight / 2
        }
    }

    // chatPositionY computed to position chat under the video
    private func chatPositionY(usingDrag drag: CGFloat) -> CGFloat {
        let t = effectiveProgress(forDrag: drag)  // 0 => expanded (full), 1 => collapsed (35%)
        let videoHeight = videoFrame(usingDrag: drag).height  // Get height directly to avoid circular dependency
        let dynamicChatHeight = chatHeight(usingDrag: drag)

        if t < 0.1 {  // Chat is hidden - position at bottom
            return screenSize.height - dynamicChatHeight / 2
        } else {  // Chat is shown - position under video
            return safeAreaInsets.top + videoHeight + dynamicChatHeight / 2
        }
    }

    private func chatOffsetY(usingDrag drag: CGFloat) -> CGFloat {
        // When chat is hidden, it should be positioned off-screen at the bottom
        // When chat is shown, it should be positioned under the video
        let t = effectiveProgress(forDrag: drag)

        if t < 0.1 {  // Chat is hidden - position off-screen
            return screenSize.height  // Move chat completely off-screen
        } else {  // Chat is shown - no offset needed
            return 0
        }
    }

    private func chatHeight(usingDrag drag: CGFloat) -> CGFloat {
        // chat should take the remaining space after the video
        let actualVideoHeight = videoFrame(usingDrag: drag).height  // Use actual video frame height directly
        return screenSize.height - safeAreaInsets.top - actualVideoHeight
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video player section - use computed height that responds to drag/progress
            VideoPlayerSection(usingDrag: dragTranslation)

            // Chat sheet - placed directly under the video with no gap
            LiveChatSection()
                .frame(width: screenSize.width, height: chatHeight(usingDrag: dragTranslation))
                // Position chat directly under the video
                .position(
                    x: screenSize.width / 2,
                    y: chatPositionY(usingDrag: dragTranslation)
                )
                .offset(y: chatOffsetY(usingDrag: dragTranslation))
                .animation(
                    .interactiveSpring(response: 0.2, dampingFraction: 0.8), value: dragTranslation)  // smooth while dragging

            // Controls overlay (top/close/minimize/chat toggle)
            ControlsOverlay()
        }
        .onAppear {
            playerConfig.initializeDefaults()
            setupVideoPlayer()
        }
        .onChange(of: playerConfig.selectedLiveActivitiesEvent) { _, newEvent in
            if newEvent != nil {
                setupVideoPlayer()
            } else {
                cleanupVideoPlayer()
            }
        }
        .onChange(of: playerConfig.sharedVideoPlayerModel?.detectedVideoSize) { _, newSize in
            if let size = newSize, size.width > 0 && size.height > 0 {
                playerConfig.updateVideoAspectRatio(from: size)
            }
        }
        .gesture(chatDragGesture)
    }

    // MARK: - Subviews as functions

    private func videoFrame(usingDrag drag: CGFloat) -> CGSize {
        guard let model = playerConfig.sharedVideoPlayerModel else {
            return CGSize(width: screenSize.width, height: availableHeight * expandedVideoRatio)
        }

        let videoSize = model.detectedVideoSize
        guard videoSize.width > 0 && videoSize.height > 0 else {
            return CGSize(width: screenSize.width, height: availableHeight * expandedVideoRatio)
        }

        let containerWidth = screenSize.width
        let t = effectiveProgress(forDrag: drag)  // 0 => expanded (full), 1 => collapsed (35%)

        // Dynamic max height based on chat state
        let maxHeight: CGFloat
        if t < 0.1 {  // Chat is hidden - use full available height
            maxHeight = availableHeight
        } else {  // Chat is shown - use 35% of available height
            maxHeight = availableHeight * 0.35
        }

        let videoAspect = videoSize.width / videoSize.height
        let containerAspect = containerWidth / maxHeight

        // Calculate the optimal size that fits within the constraints
        let width: CGFloat
        let height: CGFloat

        if videoAspect > containerAspect {
            // Video is wider than container → scale to fit width, may be shorter than max height
            width = containerWidth
            height = width / videoAspect
        } else {
            // Video is taller than container → scale to fit max height, may be narrower than container width
            height = maxHeight
            width = height * videoAspect
        }

        return CGSize(width: width, height: height)
    }

    @ViewBuilder
    private func VideoPlayerSection(usingDrag drag: CGFloat) -> some View {
        let actualVideoFrame = videoFrame(usingDrag: drag)
        let videoHeight = actualVideoFrame.height
        let videoWidth = actualVideoFrame.width

        ZStack {
            if let event = playerConfig.selectedLiveActivitiesEvent,
                (event.recording ?? event.streaming) != nil
            {
                VideoPlayerView(
                    videoSize: Binding(
                        get: { actualVideoFrame },
                        set: { _ in }
                    ),
                    actualVideoFrame: Binding(get: { .zero }, set: { _ in }),
                    playerConfig: $playerConfig
                )
                .frame(width: videoWidth, height: videoHeight)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: videoWidth, height: videoHeight)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.7))
                            Text("No Video Available")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
            }
        }
        .frame(width: screenSize.width, height: videoHeight)
        .position(x: screenSize.width / 2, y: videoPositionY(usingDrag: drag))
        .clipped()
        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.8), value: drag)  // dynamic animation while dragging
    }

    @ViewBuilder
    private func LiveChatSection() -> some View {
        if let event = playerConfig.selectedLiveActivitiesEvent {
            LiveChatView(liveActivitiesEvent: event)
                .background(.regularMaterial)
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .shadow(radius: 8)
        } else {
            // Keep an invisible container so layout remains stable even when no event
            Color.clear
        }
    }

    @ViewBuilder
    private func ControlsOverlay() -> some View {
        VStack {
            HStack {
                Button(action: minimizePlayer) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, safeAreaInsets.top + 10)

            Spacer()

            HStack {
                Button(action: toggleChat) {
                    Image(
                        systemName: playerConfig.chatRevealProgress > 0 ? "message.fill" : "message"
                    )
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, safeAreaInsets.bottom + 20)
        }
    }

    // MARK: - Gesture

    private var chatDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                // Use predictedEndTranslation for a more natural snap
                let predictedEnd = value.predictedEndTranslation.height
                let effective = effectiveProgress(forDrag: predictedEnd)

                // decide final state based on predicted end or mid-threshold
                let shouldOpen = effective > 0.5

                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.prepare()

                withAnimation(
                    .interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
                ) {
                    if shouldOpen {
                        playerConfig.chatRevealProgress = 1.0
                        playerConfig.setFullscreenWithChatState()
                    } else {
                        playerConfig.chatRevealProgress = 0.0
                        playerConfig.playerState = .fullscreen
                    }
                }

                impact.impactOccurred()
            }
    }

    // MARK: - Actions

    private func minimizePlayer() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            playerConfig.setMinimizedState()
        }
    }

    private func toggleChat() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if playerConfig.chatRevealProgress > 0 {
                playerConfig.chatRevealProgress = 0
                playerConfig.playerState = .fullscreen
            } else {
                playerConfig.chatRevealProgress = 1
                playerConfig.setFullscreenWithChatState()
            }
        }
    }

    // MARK: - Video player setup/cleanup

    private func setupVideoPlayer() {
        guard let event = playerConfig.selectedLiveActivitiesEvent else {
            return
        }

        // Use shared video player model to prevent duplicate audio streams
        playerConfig.setupSharedVideoPlayer(for: event)

        // Start playing if not already playing
        if let model = playerConfig.sharedVideoPlayerModel, !model.isPlaying {
            model.player.play()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            playerConfig.sharedVideoPlayerModel?.detectVideoSize()
        }
    }

    private func cleanupVideoPlayer() {
        // Only cleanup if we're completely hiding the player
        if playerConfig.playerState == .hidden {
            playerConfig.cleanupSharedVideoPlayer()
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
