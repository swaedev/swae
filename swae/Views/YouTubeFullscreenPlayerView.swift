//
//  YouTubeFullscreenPlayerView.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import SwiftUI

struct YouTubeFullscreenPlayerView: View {
    @EnvironmentObject var orientationMonitor: OrientationMonitor
    @EnvironmentObject var appState: AppState

    var screenSize: CGSize
    @Binding var playerConfig: PlayerConfig
    var onClose: () -> Void

    @State private var videoPlayerModel: VideoPlayerModel?
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
        // shownY = safeAreaInsets.top + videoHeight
        // hiddenY = screenHeight
        let shownY = safeAreaInsets.top + (availableHeight * collapsedVideoRatio)
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
        return max(0, min(1, progressClamped + delta))
    }

    // videoHeight computed using effectiveProgress while dragging
    private func videoHeight(usingDrag drag: CGFloat) -> CGFloat {
        let t = effectiveProgress(forDrag: drag)  // 0 => expanded (full), 1 => collapsed (30%)
        // interpolate between expandedVideoRatio and collapsedVideoRatio
        let ratio = expandedVideoRatio + (collapsedVideoRatio - expandedVideoRatio) * t
        return availableHeight * ratio
    }

    private func chatOffsetY(usingDrag drag: CGFloat) -> CGFloat {
        // hiddenY is off bottom (y origin of chat when completely hidden)
        let shownY = safeAreaInsets.top + videoHeight(usingDrag: drag)
        let hiddenY = screenSize.height

        let distance = hiddenY - shownY
        // progress -> how much shown (0 hidden, 1 shown)
        let t = effectiveProgress(forDrag: drag)
        // compute top-of-chat Y coordinate
        let topY = hiddenY - (t * distance)
        // offset in SwiftUI is relative to the chat's natural position in layout.
        // We'll position the chat anchored at bottom of screen by placing it at y = shownY + chatHeight/2
        // Simpler: we'll compute the offset relative to "shown position" (0) and then move to topY.
        // But easiest approach: compute offset as (topY - shownY)
        let offsetFromShown = topY - shownY
        return offsetFromShown
    }

    private var chatHeight: CGFloat {
        // chat should take the rest (70%) of availableHeight; keep consistent with video ratio
        return availableHeight * (1 - collapsedVideoRatio)
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video player section - use computed height that responds to drag/progress
            VideoPlayerSection(usingDrag: dragTranslation)

            // Chat sheet - placed under the video (so it visually appears below the video)
            LiveChatSection()
                .frame(width: screenSize.width, height: chatHeight)
                // place the chat at the "shown" Y, then offset by chatOffsetY to reflect dragging/open/closed
                .position(
                    x: screenSize.width / 2,
                    y: (safeAreaInsets.top + videoHeight(usingDrag: dragTranslation)) + chatHeight
                        / 2
                )
                .offset(y: chatOffsetY(usingDrag: dragTranslation))
                .animation(
                    .interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1),
                    value: playerConfig.chatRevealProgress
                )
                .animation(.interactiveSpring(), value: dragTranslation)  // smooth while dragging

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
        .onChange(of: videoPlayerModel?.detectedVideoSize) { _, newSize in
            if let size = newSize, size.width > 0 && size.height > 0 {
                playerConfig.updateVideoAspectRatio(from: size)
            }
        }
        .gesture(chatDragGesture)
    }

    // MARK: - Subviews as functions

    @ViewBuilder
    private func VideoPlayerSection(usingDrag drag: CGFloat) -> some View {
        let height = videoHeight(usingDrag: drag)

        ZStack {
            if let event = playerConfig.selectedLiveActivitiesEvent,
                let url = event.recording ?? event.streaming
            {
                if let model = videoPlayerModel {
                    YouTubeVideoPlayer(
                        player: model.player,
                        videoSize: Binding(get: { model.detectedVideoSize }, set: { _ in }),
                        actualVideoFrame: Binding(get: { .zero }, set: { _ in })
                    )
                    .onAppear {
                        model.setMiniPlayerMode(false)
                    }
                    .onDisappear {
                        model.player.pause()
                    }
                }
            } else {
                Rectangle()
                    .fill(Color.black)
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

            VideoControlsOverlay()
        }
        .frame(width: screenSize.width, height: height)
        .position(x: screenSize.width / 2, y: safeAreaInsets.top + height / 2)
        .clipped()
        .animation(.interactiveSpring(), value: drag)  // dynamic animation while dragging
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

    @ViewBuilder
    private func VideoControlsOverlay() -> some View {
        // leave empty or place overlays specific to your player
        EmptyView()
    }

    // MARK: - Gesture

    private var chatDragGesture: some Gesture {
        DragGesture()
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
        guard let event = playerConfig.selectedLiveActivitiesEvent,
            let url = event.recording ?? event.streaming
        else {
            return
        }
        cleanupVideoPlayer()
        videoPlayerModel = VideoPlayerModel(url: url)
        videoPlayerModel?.player.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            videoPlayerModel?.detectVideoSize()
        }
    }

    private func cleanupVideoPlayer() {
        videoPlayerModel?.cleanup()
        videoPlayerModel = nil
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
