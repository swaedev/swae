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
    @State private var chatDragOffset: CGFloat = 0
    @State private var isDraggingChat: Bool = false
    @State private var videoSize: CGSize = .zero
    @GestureState private var dragTranslation: CGFloat = 0

    // Safe area insets
    private var safeAreaInsets: UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {
            return window.safeAreaInsets
        }
        return .zero
    }

    // Calculate video frame - YouTube-like behavior
    private var videoFrame: CGRect {
        let screenWidth = screenSize.width
        let screenHeight = screenSize.height
        let availableHeight = screenHeight - safeAreaInsets.top - safeAreaInsets.bottom

        if playerConfig.chatRevealProgress > 0 {
            // When chat is visible: video takes exactly 30% of available height
            let videoHeight = availableHeight * 0.3
            let frame = CGRect(
                x: 0,
                y: safeAreaInsets.top,
                width: screenWidth,
                height: videoHeight
            )
            print("Video frame (with chat): \(frame)")
            return frame
        } else {
            // When no chat: video takes full available height
            let frame = CGRect(
                x: 0,
                y: safeAreaInsets.top,
                width: screenWidth,
                height: availableHeight
            )
            print("Video frame (no chat): \(frame)")
            return frame
        }
    }

    // Calculate chat frame - YouTube-like behavior with live drag
    private var chatFrame: CGRect {
        let screenWidth = screenSize.width
        let screenHeight = screenSize.height
        let availableHeight = screenHeight - safeAreaInsets.top

        let videoHeight = availableHeight * 0.3
        let chatHeight = availableHeight * 0.7

        // Target Y when fully shown
        let shownY = safeAreaInsets.top + videoHeight
        // Target Y when fully hidden (off bottom of screen)
        let hiddenY = screenHeight

        // Interpolate between hidden and shown positions
        let baseY = hiddenY - (playerConfig.chatRevealProgress * (hiddenY - shownY))
        // Add live drag offset for continuous dragging
        let chatY = baseY + dragTranslation

        return CGRect(
            x: 0,
            y: chatY,
            width: screenWidth,
            height: chatHeight
        )
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Video Player Section - Always full screen below safe area
            VideoPlayerSection()
                .frame(width: videoFrame.width, height: videoFrame.height)
                .position(x: videoFrame.midX, y: videoFrame.midY)
                .clipped()

            // LiveChatView Section - Overlay below actual video content
            LiveChatSection()
                .frame(width: chatFrame.width, height: chatFrame.height)
                .position(x: chatFrame.midX, y: chatFrame.midY)
                .clipped()

            // Controls Overlay
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
        .gesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let threshold =
                        (screenSize.height
                            - (safeAreaInsets.top + (screenSize.height - safeAreaInsets.top)
                                * 0.3))
                        / 2
                    if value.translation.height > threshold {
                        // close
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            playerConfig.chatRevealProgress = 0
                            playerConfig.playerState = .fullscreen
                        }
                    } else {
                        // open
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            playerConfig.chatRevealProgress = 1
                            playerConfig.setFullscreenWithChatState()
                        }
                    }

                    // Add haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }
        )
    }

    @ViewBuilder
    private func VideoPlayerSection() -> some View {
        ZStack {
            if let event = playerConfig.selectedLiveActivitiesEvent,
                let url = event.recording ?? event.streaming
            {
                // Use the new YouTubeVideoPlayer for proper aspect ratio handling
                if let videoPlayerModel = videoPlayerModel {
                    YouTubeVideoPlayer(
                        player: videoPlayerModel.player,
                        videoSize: Binding(
                            get: { videoPlayerModel.detectedVideoSize },
                            set: { _ in }
                        ),
                        actualVideoFrame: Binding(
                            get: { .zero },
                            set: { _ in }
                        )
                    )
                    .onAppear {
                        print("YouTubeVideoPlayer appeared with URL: \(url)")
                        videoPlayerModel.setMiniPlayerMode(false)
                    }
                    .onDisappear {
                        print("YouTubeVideoPlayer disappeared")
                        videoPlayerModel.player.pause()
                    }
                } else {
                    // Fallback to original VideoPlayerView if videoPlayerModel is not ready
                    VideoPlayerView(
                        size: videoFrame.size,
                        url: url,
                        onDragUp: nil,
                        onSizeChange: nil
                    )
                    .onAppear {
                        print("Fallback VideoPlayerView appeared with URL: \(url)")
                        setupVideoPlayer()
                    }
                }
            } else {
                // Placeholder with debug info
                Rectangle()
                    .fill(.black)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.7))
                            Text("No Video Available")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.7))

                            // Debug information
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Debug Info:")
                                    .font(.caption)
                                    .foregroundColor(.yellow)

                                if let event = playerConfig.selectedLiveActivitiesEvent {
                                    Text("Event: \(event.title ?? "No title")")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("Recording: \(event.recording?.absoluteString ?? "None")")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("Streaming: \(event.streaming?.absoluteString ?? "None")")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                } else {
                                    Text("No event selected")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }

                                Text(
                                    "VideoPlayerModel: \(videoPlayerModel != nil ? "Ready" : "Nil")"
                                )
                                .font(.caption)
                                .foregroundColor(videoPlayerModel != nil ? .green : .red)

                                if let model = videoPlayerModel {
                                    Text("Video Size: \(model.detectedVideoSize)")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                        }
                    }
            }

            // Video controls overlay
            VideoControlsOverlay()
        }
    }

    @ViewBuilder
    private func LiveChatSection() -> some View {
        if let event = playerConfig.selectedLiveActivitiesEvent {
            LiveChatView(liveActivitiesEvent: event)
                .background(.regularMaterial)
                .cornerRadius(16, corners: [.topLeft, .topRight])
        }
    }

    @ViewBuilder
    private func ControlsOverlay() -> some View {
        VStack {
            // Top controls
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

            // Bottom controls
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
        // The VideoPlayerView already has its own controls, so we don't need additional overlay
        EmptyView()
    }

    // MARK: - Gesture Handling

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
                playerConfig.chatRevealProgress = 0.0
                playerConfig.playerState = .fullscreen
            } else {
                playerConfig.chatRevealProgress = 1.0
                playerConfig.setFullscreenWithChatState()
            }
        }
    }

    // MARK: - Video Player Setup

    private func setupVideoPlayer() {
        guard let event = playerConfig.selectedLiveActivitiesEvent,
            let url = event.recording ?? event.streaming
        else {
            print("No video URL available")
            return
        }

        print("Setting up video player with URL: \(url)")
        cleanupVideoPlayer()
        videoPlayerModel = VideoPlayerModel(url: url)

        // Start playing the video immediately
        videoPlayerModel?.player.play()
        print("Video player created and started playing")

        // Detect video size when player is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            videoPlayerModel?.detectVideoSize()
            print("Video size detection triggered")
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
