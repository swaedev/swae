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
    @State private var interimProgress: CGFloat? = nil  // Tracks effective progress during drag

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
        screenSize.height - safeAreaInsets.top - safeAreaInsets.bottom
    }
    private var collapsedVideoRatio: CGFloat { 0.35 }
    private var expandedVideoRatio: CGFloat { 1.0 }

    private var videoHeightForProgress: (CGFloat) -> CGFloat = { _ in 0 }  // Unused, kept for compatibility

    // Distance the chat must move from hidden -> shown (top Y coordinate difference)
    private var chatRevealDistance: CGFloat {
        let videoHeightWhenChatShown = availableHeight * collapsedVideoRatio
        let shownY = safeAreaInsets.top + videoHeightWhenChatShown
        let hiddenY = screenSize.height + (availableHeight - videoHeightWhenChatShown) / 2
        return hiddenY - shownY
    }

    // MARK: - Derived positions & sizes based on playerConfig.chatRevealProgress & dragTranslation
    private var progressClamped: CGFloat {
        max(0, min(1, playerConfig.chatRevealProgress))
    }

    // Effective progress while dragging (incorporates dragTranslation gesture)
    private func effectiveProgress(forDrag drag: CGFloat) -> CGFloat {
        let baseProgress = interimProgress ?? progressClamped
        let distance = chatRevealDistance
        guard distance > 0 else { return baseProgress }

        let delta = -drag / distance
        let newProgress = baseProgress + delta
        return max(0, min(1, newProgress))
    }

    // videoHeight computed using effectiveProgress while dragging
    private func videoHeight(usingDrag drag: CGFloat) -> CGFloat {
        let actualVideoFrame = videoFrame(usingDrag: drag)
        return actualVideoFrame.height
    }

    // MARK: - Smooth Positions (Adjusted for Initial Hidden State)
    private func videoPositionY(usingDrag drag: CGFloat) -> CGFloat {
        let t = effectiveProgress(forDrag: drag)
        let videoHeight = videoFrame(usingDrag: drag).height

        // Targets: t=0 (expanded, centered within safe area), t=1 (collapsed, top-aligned with safe area)
        let expandedY = (screenSize.height + safeAreaInsets.top) / 2.0  // Center within safe area
        let collapsedY = safeAreaInsets.top + videoHeight / 2.0  // Top edge at safe area bottom

        // Linear interpolation
        return (1 - t) * expandedY + t * collapsedY
    }

    // chatPositionY computed to position chat under the video or fully off-screen
    private func chatPositionY(usingDrag drag: CGFloat) -> CGFloat {
        let t = effectiveProgress(forDrag: drag)
        let dynamicChatHeight = chatHeight(usingDrag: drag)
        let videoHeight = videoFrame(usingDrag: drag).height

        // Targets: t=0 (hidden, fully off-screen), t=1 (shown, immediately below video)
        let expandedY = screenSize.height + dynamicChatHeight  // Fully off-screen bottom (use full height)
        let collapsedY = safeAreaInsets.top + videoHeight + dynamicChatHeight / 2.0  // Start right below video

        // Linear interpolation
        return (1 - t) * expandedY + t * collapsedY
    }

    private func chatHeight(usingDrag drag: CGFloat) -> CGFloat {
        let actualVideoHeight = videoFrame(usingDrag: drag).height
        let remainingHeight = availableHeight - actualVideoHeight
        // Ensure chat fills remaining space, accounting for bottom safe area
        return max(0, remainingHeight + safeAreaInsets.bottom)
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
                .position(
                    x: screenSize.width / 2,
                    y: chatPositionY(usingDrag: dragTranslation)
                )

            // Controls overlay (top/close/minimize/chat toggle)
            ControlsOverlay()
        }
        .onAppear {
            playerConfig.initializeDefaults()
            playerConfig.chatRevealProgress = 0  // Force chat to start hidden
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
            return CGSize(width: screenSize.width, height: availableHeight * expandedVideoRatio)  // Default to full height
        }

        let videoSize = model.detectedVideoSize
        guard videoSize.width > 0 && videoSize.height > 0 else {
            return CGSize(width: screenSize.width, height: availableHeight * expandedVideoRatio)  // Default during loading
        }

        let containerWidth = screenSize.width
        let t = effectiveProgress(forDrag: drag)

        // Smooth maxHeight: Ensure full height when t=1, adjusted for aspect ratio
        let heightFactor = expandedVideoRatio + t * (collapsedVideoRatio - expandedVideoRatio)
        let maxHeight = availableHeight * heightFactor
        let targetHeight = (t == 1) ? (availableHeight * collapsedVideoRatio) : maxHeight

        let videoAspect = videoSize.width / videoSize.height
        let containerAspect = containerWidth / targetHeight

        let width: CGFloat
        let height: CGFloat

        if videoAspect > containerAspect {
            width = containerWidth
            height = min(width / videoAspect, targetHeight)
        } else {
            height = targetHeight
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
    }

    @ViewBuilder
    private func LiveChatSection() -> some View {
        if let event = playerConfig.selectedLiveActivitiesEvent {
            LiveChatView(liveActivitiesEvent: event)
                .background(.regularMaterial)
                .cornerRadius(16, corners: [.topLeft, .topRight])
                .shadow(radius: 8)
                .clipped()
        } else {
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
        DragGesture(minimumDistance: 10)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
                let distance = chatRevealDistance
                guard distance > 0 else { return }
                let delta = -value.translation.height / distance
                interimProgress = max(0, min(1, progressClamped + delta))
            }
            .onEnded { value in
                let predictedEnd = value.predictedEndTranslation.height
                let distance = chatRevealDistance
                guard distance > 0 else { return }
                let predictedProgress = max(0, min(1, progressClamped - predictedEnd / distance))
                let shouldOpen = predictedProgress > 0.5

                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.prepare()

                // Set chatRevealProgress immediately to the predicted progress
                playerConfig.chatRevealProgress = predictedProgress
                interimProgress = predictedProgress

                withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                    if shouldOpen {
                        playerConfig.chatRevealProgress = 1.0
                        playerConfig.setFullscreenWithChatState()
                    } else {
                        playerConfig.chatRevealProgress = 0.0
                        playerConfig.playerState = .fullscreen
                    }
                    interimProgress = nil
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

        playerConfig.setupSharedVideoPlayer(for: event)

        if let model = playerConfig.sharedVideoPlayerModel, !model.isPlaying {
            model.player.play()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            playerConfig.sharedVideoPlayerModel?.detectVideoSize()
        }
    }

    private func cleanupVideoPlayer() {
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
