//
//  YouTubeDraggablePlayerView.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import SwiftUI

struct YouTubeDraggablePlayerView: View {
    @EnvironmentObject var orientationMonitor: OrientationMonitor
    @EnvironmentObject var appState: AppState

    var screenSize: CGSize
    @Binding var playerConfig: PlayerConfig
    var onClose: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var videoPlayerModel: VideoPlayerModel?

    // Safe area insets
    private var safeAreaInsets: UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {
            return window.safeAreaInsets
        }
        return .zero
    }

    // Calculate available screen area for dragging
    private var availableArea: CGRect {
        CGRect(
            x: 0,
            y: safeAreaInsets.top,
            width: screenSize.width,
            height: screenSize.height - safeAreaInsets.top - safeAreaInsets.bottom - 49  // Tab bar height
        )
    }

    var body: some View {
        ZStack {
            if playerConfig.playerState != .hidden {
                // Fullscreen player with LiveChatView integration
                if playerConfig.playerState == .fullscreen
                    || playerConfig.playerState == .fullscreenWithChat
                {
                    YouTubeFullscreenPlayerView(
                        screenSize: screenSize,
                        playerConfig: $playerConfig,
                        onClose: onClose
                    )
                    .ignoresSafeArea()
                } else {
                    // Minimized player
                    PlayerContainerView()
                        .frame(
                            width: playerConfig.miniPlayerSize.width,
                            height: playerConfig.miniPlayerSize.height
                        )
                        .cornerRadius(playerConfig.cornerRadius)
                        .shadow(
                            color: .black.opacity(playerConfig.shadowOpacity),
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                        .offset(
                            x: playerConfig.draggablePosition.x + dragOffset.width,
                            y: playerConfig.draggablePosition.y + dragOffset.height
                        )
                        .scaleEffect(isDragging ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    handleDragChanged(value)
                                }
                                .onEnded { value in
                                    handleDragEnded(value)
                                }
                        )
                        .onTapGesture {
                            expandPlayer()
                        }
                }
            }
        }
        .onAppear {
            setupVideoPlayer()
        }
        .onChange(of: playerConfig.selectedLiveActivitiesEvent) { _, newEvent in
            if newEvent != nil {
                setupVideoPlayer()
            } else {
                cleanupVideoPlayer()
            }
        }
        .onDisappear {
            cleanupVideoPlayer()
        }
    }

    @ViewBuilder
    private func PlayerContainerView() -> some View {
        ZStack {
            // Video player
            if let videoModel = videoPlayerModel {
                MiniVideoPlayerView(
                    videoModel: videoModel,
                    size: playerConfig.playerState == .minimized
                        ? playerConfig.miniPlayerSize : screenSize,
                    isMinimized: playerConfig.playerState == .minimized
                )
                .onAppear {
                    videoModel.setMiniPlayerMode(playerConfig.playerState == .minimized)
                }
                .onChange(of: playerConfig.playerState) { _, newState in
                    videoModel.setMiniPlayerMode(newState == .minimized)
                }
            } else {
                // Placeholder
                Rectangle()
                    .fill(.black)
                    .overlay {
                        VStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
            }

            // Controls overlay
            if playerConfig.playerState == .minimized {
                MinimizedControlsOverlay()
            } else {
                FullscreenControlsOverlay()
            }
        }
    }

    @ViewBuilder
    private func MinimizedControlsOverlay() -> some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Circle())
                }
                .padding(6)
            }
            Spacer()

            // Bottom info bar for mini player
            if let event = playerConfig.selectedLiveActivitiesEvent {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "Untitled Stream")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text("Tap to expand")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 6)

                    Spacer()
                }
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.7)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func FullscreenControlsOverlay() -> some View {
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
        }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard playerConfig.playerState == .minimized else { return }

        isDragging = true
        playerConfig.isDragging = true

        let newOffset = CGSize(
            width: value.translation.width,
            height: value.translation.height
        )

        // Constrain to available area
        let constrainedOffset = constrainOffsetToArea(newOffset)
        dragOffset = constrainedOffset
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        guard playerConfig.playerState == .minimized else { return }

        isDragging = false
        playerConfig.isDragging = false

        let velocity = value.velocity
        playerConfig.dragVelocity = velocity

        // Calculate final position
        let finalOffset = constrainOffsetToArea(dragOffset)
        let finalPosition = CGPoint(
            x: playerConfig.draggablePosition.x + finalOffset.width,
            y: playerConfig.draggablePosition.y + finalOffset.height
        )

        // Snap to edges if enabled
        if playerConfig.snapToEdge {
            let snappedPosition = snapToNearestEdge(finalPosition)

            // Add haptic feedback for snap
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                playerConfig.draggablePosition = snappedPosition
                dragOffset = .zero
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                playerConfig.draggablePosition = finalPosition
                dragOffset = .zero
            }
        }
    }

    private func constrainOffsetToArea(_ offset: CGSize) -> CGSize {
        let currentPosition = CGPoint(
            x: playerConfig.draggablePosition.x + offset.width,
            y: playerConfig.draggablePosition.y + offset.height
        )

        let constrainedX = max(
            availableArea.minX,
            min(availableArea.maxX - playerConfig.miniPlayerSize.width, currentPosition.x)
        )

        let constrainedY = max(
            availableArea.minY,
            min(availableArea.maxY - playerConfig.miniPlayerSize.height, currentPosition.y)
        )

        return CGSize(
            width: constrainedX - playerConfig.draggablePosition.x,
            height: constrainedY - playerConfig.draggablePosition.y
        )
    }

    private func snapToNearestEdge(_ position: CGPoint) -> CGPoint {
        let centerX = availableArea.midX
        let leftEdge = availableArea.minX + 16
        let rightEdge = availableArea.maxX - playerConfig.miniPlayerSize.width - 16

        let snappedX: CGFloat
        if position.x < centerX {
            snappedX = leftEdge
        } else {
            snappedX = rightEdge
        }

        // Keep Y position but ensure it's within bounds
        let snappedY = max(
            availableArea.minY + 16,
            min(availableArea.maxY - playerConfig.miniPlayerSize.height - 16, position.y)
        )

        return CGPoint(x: snappedX, y: snappedY)
    }

    // MARK: - Player State Management

    private func minimizePlayer() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            playerConfig.setMinimizedState()

            // Position at bottom right initially
            if playerConfig.draggablePosition == .zero {
                playerConfig.draggablePosition = CGPoint(
                    x: availableArea.maxX - playerConfig.miniPlayerSize.width - 16,
                    y: availableArea.maxY - playerConfig.miniPlayerSize.height - 16
                )
            }
        }
    }

    private func expandPlayer() {
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            playerConfig.setFullscreenState()
        }
    }

    // MARK: - Video Player Setup

    private func setupVideoPlayer() {
        guard let event = playerConfig.selectedLiveActivitiesEvent,
            let url = event.recording ?? event.streaming
        else {
            return
        }

        // Cleanup existing player
        cleanupVideoPlayer()

        // Create new player
        videoPlayerModel = VideoPlayerModel(url: url)
    }

    private func cleanupVideoPlayer() {
        videoPlayerModel?.cleanup()
        videoPlayerModel = nil
    }
}
