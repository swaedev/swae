//
//  SimpleVideoPlayer.swift
//  swae
//
//  Created by Suhail Saqan on 2/16/25.
//

import AVKit
import Combine
import SwiftUI

/// Simplified video player that directly handles video display and controls
/// Fixes the video display and time update issues by being more direct
struct SimpleVideoPlayer: View {
    @Binding var videoSize: CGSize
    @Binding var actualVideoFrame: CGRect
    @Binding var playerConfig: PlayerConfig
    
    // Direct player management
    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var timeObserver: Any?
    @State private var isPlaying: Bool = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var isLoading: Bool = false
    @State private var hasError: Bool = false
    
    // Controls
    @State private var isControlsVisible: Bool = true
    @State private var hideControlsTask: DispatchWorkItem?
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                if let player = player {
                    VideoPlayer(player: player)
                        .onTapGesture {
                            toggleControls()
                        }
                        .onAppear {
                            setupTimeObserver()
                        }
                        .onDisappear {
                            removeTimeObserver()
                        }
                } else {
                    // Loading or error state
                    Rectangle()
                        .fill(Color.black)
                        .overlay {
                            if isLoading {
                                loadingView
                            } else if hasError {
                                errorView
                            } else {
                                loadingView
                            }
                        }
                }
                
                // Controls overlay
                if isControlsVisible && player != nil {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: playerConfig.selectedLiveActivitiesEvent) { _, newEvent in
            if let event = newEvent, let url = event.recording ?? event.streaming {
                loadVideo(url: url)
            }
        }
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        guard let event = playerConfig.selectedLiveActivitiesEvent,
              let url = event.recording ?? event.streaming
        else {
            return
        }
        
        loadVideo(url: url)
    }
    
    private func loadVideo(url: URL) {
        isLoading = true
        hasError = false
        
        // Create player item
        let item = AVPlayerItem(url: url)
        self.playerItem = item
        
        // Create player
        let newPlayer = AVPlayer(playerItem: item)
        self.player = newPlayer
        
        // Set up player in PlayerConfig for compatibility
        playerConfig.sharedVideoPlayerModel = VideoPlayerModel(url: url)
        
        // Observe player item status using Combine
        observePlayerItem(item)
        
        // Start playing
        newPlayer.play()
        isPlaying = true
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.1, preferredTimescale: timeScale)
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: time, queue: .main) {
            [self] time in
            currentTime = time.seconds
            if duration == 0 {
                duration = player.currentItem?.duration.seconds ?? 0
            }
        }
    }
    
    private func removeTimeObserver() {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
    
    private func cleanup() {
        removeTimeObserver()
        player?.pause()
        player = nil
        playerItem = nil
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
            
            Text("Playback Error")
                .font(.caption)
                .foregroundColor(.white)
            
            Button(action: {
                setupPlayer()
            }) {
                Text("Retry")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var controlsOverlay: some View {
        VStack(spacing: 12) {
            Spacer()
            // Control buttons
            HStack(spacing: 20) {
                // Play/Pause
                Button(action: {
                    togglePlayPause()
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                
                // Time display
                timeDisplay
                
                Spacer()
                
                // Volume
                Button(action: {
                    toggleVolume()
                }) {
                    Image(
                        systemName: player?.volume == 0
                        ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
                }
                
                // Fullscreen
                Button(action: {
                    toggleFullscreen()
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
            
            // Seek bar
            DirectSeekBar(player: player, currentTime: $currentTime, duration: $duration)
                .padding(.horizontal, 12)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var timeDisplay: some View {
        HStack(spacing: 4) {
            Text(formatTime(currentTime))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            Text("/")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            Text(formatTime(duration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }
    
    // MARK: - Actions
    
    private func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func toggleVolume() {
        guard let player = player else { return }
        player.volume = player.volume == 0 ? 1 : 0
    }
    
    private func toggleFullscreen() {
        if playerConfig.playerState == .fullscreen {
            playerConfig.playerState = .fullscreenWithChat
        } else {
            playerConfig.playerState = .fullscreen
        }
    }
    
    private func toggleControls() {
        if isControlsVisible {
            hideControls()
        } else {
            showControlsTemporarily()
        }
    }
    
    private func showControlsTemporarily() {
        isControlsVisible = true
        cancelHideTask()
        
        hideControlsTask = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.3)) {
                isControlsVisible = false
            }
        }
        
        if let task = hideControlsTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: task)
        }
    }
    
    private func hideControls() {
        cancelHideTask()
        withAnimation(.easeInOut(duration: 0.3)) {
            isControlsVisible = false
        }
    }
    
    private func cancelHideTask() {
        hideControlsTask?.cancel()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func observePlayerItem(_ item: AVPlayerItem) {
        // Use a simple timer to check status instead of KVO
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak item] timer in
            guard let item = item else {
                timer.invalidate()
                return
            }
            
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.hasError = false
                    if item.duration.isValid {
                        self.duration = item.duration.seconds
                    }
                case .failed:
                    self.isLoading = false
                    self.hasError = true
                case .unknown:
                    self.isLoading = true
                @unknown default:
                    break
                }
            }
        }
    }
}

// MARK: - Preview

struct SimpleVideoPlayer_Previews: PreviewProvider {
    static var previews: some View {
        SimpleVideoPlayer(
            videoSize: .constant(CGSize(width: 1920, height: 1080)),
            actualVideoFrame: .constant(.zero),
            playerConfig: .constant(PlayerConfig())
        )
        .background(Color.black)
    }
}
