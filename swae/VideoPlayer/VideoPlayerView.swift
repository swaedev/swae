//
//  VideoPlayerView.swift
//  swae
//
//  Created by Suhail Saqan on 1/25/25.
//

import AVKit
import SwiftUI

struct VideoPlayerView: View {
    @Binding var videoSize: CGSize
    @Binding var actualVideoFrame: CGRect
    @Binding var playerConfig: PlayerConfig

    @GestureState private var isDragging: Bool = false

    @EnvironmentObject var orientationMonitor: OrientationMonitor

    @ObservedObject private var videoPlayerModel: VideoPlayerModel

    init(
        videoSize: Binding<CGSize>,
        actualVideoFrame: Binding<CGRect>,
        playerConfig: Binding<PlayerConfig>
    ) {
        self._videoSize = videoSize
        self._actualVideoFrame = actualVideoFrame
        self._playerConfig = playerConfig

        // Initialize VideoPlayerModel from shared instance or create new one
        if let sharedModel = playerConfig.wrappedValue.sharedVideoPlayerModel {
            self.videoPlayerModel = sharedModel
        } else {
            // Fallback (should not happen in normal flow)
            self.videoPlayerModel = VideoPlayerModel(url: URL(string: "about:blank")!)
        }
    }

    // MARK: - Body
    var body: some View {
        VStack {
            if !videoPlayerModel.playerError {
                videoPlayerView
            } else {
                errorView
            }
        }
        .zIndex(10000)
        .onAppear {
            videoPlayerModel.addTimeObserver()
            videoPlayerModel.detectVideoSize()
        }
        .onDisappear {
            videoPlayerModel.removeTimeObserver()
        }
        .onReceive(videoPlayerModel.$detectedVideoSize) { size in
            if size != .zero {
                videoSize = size
            }
        }
    }

    // MARK: - Main Player View
    private var videoPlayerView: some View {
        CustomVideoPlayer(player: videoPlayerModel.player, videoSize: $videoSize)
            .background(videoSizeReader)
            .overlay(controlsOverlay)
            .overlay(doubleTapSeekOverlay)
            .onTapGesture { handleTapGesture() }
            .overlay(alignment: .bottomLeading) {
                SeekerThumbnailView(videoSize)
                    .offset(y: orientationMonitor.isLandscape ? -85 : -60)
            }
            .overlay(alignment: .bottom) {
                VideoSeekerView(videoSize)
                    .offset(y: orientationMonitor.isLandscape ? -35 : 0)
                    .opacity(videoPlayerModel.showPlayerControls ? 1 : 0)
            }
    }

    // MARK: - Error View
    private var errorView: some View {
        VStack {
            Text("STREAM NOT LIVE")
                .font(.headline)
                .foregroundColor(.purple)
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Controls Overlay
    private var controlsOverlay: some View {
        Rectangle()
            .fill(.black.opacity(0.3))
            .opacity(videoPlayerModel.showPlayerControls || isDragging ? 1 : 0)
            .overlay { PlayBackControls() }
    }

    // MARK: - Double Tap Seek Overlay
    private var doubleTapSeekOverlay: some View {
        HStack(spacing: 60) {
            DoubleTapSeek {
                let seconds = videoPlayerModel.player.currentTime().seconds - 15
                videoPlayerModel.player.seek(
                    to: .init(seconds: seconds, preferredTimescale: 600)
                )
            }

            DoubleTapSeek(isForward: true) {
                let seconds = videoPlayerModel.player.currentTime().seconds + 15
                videoPlayerModel.player.seek(
                    to: .init(seconds: seconds, preferredTimescale: 600)
                )
            }
        }
    }

    // MARK: - Geometry Reader for Video Size
    private var videoSizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: VideoPlayerViewSizeKey.self,
                value: proxy.size
            )
        }
        .onPreferenceChange(VideoPlayerViewSizeKey.self) { newSize in
            // (onSizeChange?)(newSize)  <-- left commented as in your code
        }
    }

    // MARK: - Seeker Thumbnail View
    @ViewBuilder
    func SeekerThumbnailView(_ videoSize: CGSize) -> some View {
        let thumbSize: CGSize = .init(width: 175, height: 100)
        ZStack {
            if let draggingImage = videoPlayerModel.draggingImage {
                Image(uiImage: draggingImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if let currentItem = videoPlayerModel.player.currentItem {
                            Text(
                                CMTime(
                                    seconds: videoPlayerModel.progress
                                        * currentItem.duration.seconds,
                                    preferredTimescale: 600
                                ).toTimeString()
                            )
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .offset(y: 25)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
            } else {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.black)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white, lineWidth: 2)
                    }
            }
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .opacity(isDragging ? 1 : 0)
        .offset(x: videoPlayerModel.progress * (videoSize.width - thumbSize.width - 20))
        .offset(x: 10)
    }

    // MARK: - Video Seeker View
    @ViewBuilder
    func VideoSeekerView(_ videoSize: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.gray)
                .frame(width: max(videoSize.width, 0))

            Rectangle()
                .fill(.purple)
                .frame(
                    width: max(
                        videoSize.width
                            * (videoPlayerModel.progress.isFinite
                                ? videoPlayerModel.progress : 0),
                        0
                    )
                )
        }
        .frame(width: videoSize.width, height: 3)
        .overlay(alignment: .leading) {
            Circle()
                .fill(.purple)
                .frame(width: 15, height: 15)
                .scaleEffect(
                    videoPlayerModel.showPlayerControls || isDragging ? 1 : 0.001,
                    anchor: videoPlayerModel.progress * videoSize.width > 15 ? .trailing : .leading
                )
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
                .offset(x: videoSize.width * videoPlayerModel.progress)
                .gesture(seekerDragGesture(videoSize: videoSize))
                .offset(x: videoPlayerModel.progress * videoSize.width > 15 ? -15 : 0)
                .frame(width: 15, height: 15)
        }
    }

    // MARK: - Playback Controls View
    @ViewBuilder
    func PlayBackControls() -> some View {
        HStack(spacing: 25) {
            Button {
                if !videoPlayerModel.isLoading {
                    if videoPlayerModel.isFinishedPlaying {
                        videoPlayerModel.isFinishedPlaying = false
                        videoPlayerModel.player.seek(to: .zero)
                        videoPlayerModel.progress = .zero
                        videoPlayerModel.lastDraggedProgress = .zero
                    }
                    if videoPlayerModel.isPlaying {
                        videoPlayerModel.player.pause()
                        videoPlayerModel.timeoutTask?.cancel()
                    } else {
                        videoPlayerModel.player.play()
                        videoPlayerModel.timeoutControls()
                    }
                    togglePlayWithAnimation($videoPlayerModel.isPlaying)
                }
            } label: {
                ZStack {
                    if videoPlayerModel.isLoading {
                        LoadingCircleView(strokeColor: .white)
                            .transition(.opacity)
                    } else {
                        Image(
                            systemName: videoPlayerModel.isFinishedPlaying
                                ? "arrow.clockwise"
                                : (videoPlayerModel.isPlaying ? "pause.fill" : "play.fill")
                        )
                        .frame(width: 25, height: 25)
                        .foregroundColor(.white)
                        .padding(10)
                        .background {
                            Circle().fill(.black.opacity(0.35))
                        }
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: videoPlayerModel.isLoading)
            }
            .scaleEffect(1.1)
        }
        .opacity(videoPlayerModel.showPlayerControls && !isDragging ? 1 : 0)
    }

    // MARK: - Seeker Drag Gesture
    private func seekerDragGesture(videoSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($isDragging) { _, out, _ in
                out = true
            }
            .onChanged { value in
                if let timeoutTask = videoPlayerModel.timeoutTask {
                    timeoutTask.cancel()
                }

                let translationX: CGFloat = value.translation.width
                let calculatedProgress =
                    (translationX / videoSize.width) + videoPlayerModel.lastDraggedProgress

                videoPlayerModel.progress = max(min(calculatedProgress, 1), 0)
                videoPlayerModel.isSeeking = true

                let dragIndex = Int(videoPlayerModel.progress / 0.01)
                if videoPlayerModel.thumbnailFrames.indices.contains(dragIndex) {
                    videoPlayerModel.draggingImage =
                        videoPlayerModel.thumbnailFrames[dragIndex]
                }
            }
            .onEnded { _ in
                videoPlayerModel.lastDraggedProgress = videoPlayerModel.progress
                if let currentPlayerItem = videoPlayerModel.player.currentItem {
                    let totalDuration = currentPlayerItem.duration.seconds
                    videoPlayerModel.player.seek(
                        to: .init(
                            seconds: totalDuration * videoPlayerModel.progress,
                            preferredTimescale: 600
                        )
                    )
                    if videoPlayerModel.isPlaying {
                        videoPlayerModel.timeoutControls()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        videoPlayerModel.isSeeking = false
                        videoPlayerModel.isFinishedPlaying = false
                    }
                }
            }
    }

    // MARK: - Tap Gesture Handler
    private func handleTapGesture() {
        withAnimation(.easeInOut(duration: 0.15)) {
            videoPlayerModel.showPlayerControls.toggle()
        }
        if videoPlayerModel.isPlaying {
            videoPlayerModel.timeoutControls()
        }
    }

    // MARK: - Play/Pause Animation
    func togglePlayWithAnimation(_ isPlaying: Binding<Bool>, duration: Double = 0.15) {
        withAnimation(.easeInOut(duration: duration)) {
            isPlaying.wrappedValue.toggle()
        }
    }
}

// MARK: - Preference Key
struct VideoPlayerViewSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
