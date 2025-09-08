//
//  ProfileTabView.swift
//  swae
//
//  Created by Suhail Saqan on 2/26/25.
//

import Kingfisher
import NostrSDK
import SwiftUI

struct ProfileTabView: View {
    @State private var selectedTab = 0
    @State private var isHorizontalSwipe = false

    var body: some View {
        VStack(spacing: 0) {
            // Custom Tab Header
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ProfileTabButton(title: "Live Streams", selectedTab: $selectedTab, tabIndex: 0)
                    ProfileTabButton(title: "Shorts", selectedTab: $selectedTab, tabIndex: 1)
                }
                .padding(.horizontal)
                .padding(.top)

                // Animated Indicator
                GeometryReader { geo in
                    let buttonWidth = geo.size.width / 2
                    let indicatorWidth: CGFloat = 75

                    Capsule()
                        .fill(Color.purple)
                        .frame(width: indicatorWidth, height: 2)
                        .offset(
                            x: selectedTab == 0
                                ? (buttonWidth - indicatorWidth) / 2
                                : buttonWidth + (buttonWidth - indicatorWidth) / 2
                        )
                        .animation(.easeInOut(duration: 0.3), value: selectedTab)
                }
                .frame(height: 2)
                .padding(.horizontal)
            }

            ZStack(alignment: .topLeading) {
                if selectedTab == 0 {
                    LiveActivitiesView()
                        .transition(.move(edge: .leading))
                } else {
                    ShortsView()
                        .transition(.move(edge: .trailing))
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        // Activate only when clearly horizontal and passes threshold
                        if abs(dx) > abs(dy) + 10 && abs(dx) > 20 {
                            isHorizontalSwipe = true
                        }
                    }
                    .onEnded { value in
                        defer { isHorizontalSwipe = false }
                        guard isHorizontalSwipe else { return }
                        let threshold: CGFloat = 60
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if value.translation.width < -threshold && selectedTab == 0 {
                                selectedTab = 1
                            } else if value.translation.width > threshold && selectedTab == 1 {
                                selectedTab = 0
                            }
                        }
                    }
            )
        }
    }
}

// MARK: - Custom Tab Button (unchanged)
struct ProfileTabButton: View {
    let title: String
    @Binding var selectedTab: Int
    let tabIndex: Int

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = tabIndex
            }
        }) {
            Text(title)
                .font(.headline)
                .fontWeight(selectedTab == tabIndex ? .semibold : .medium)
                .foregroundColor(selectedTab == tabIndex ? .purple : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - LiveActivitiesView
struct LiveActivitiesView: View {
    @EnvironmentObject var appState: AppState
    @State private var timeTabFilter: TimeTabs = .past
    var publicKeyHex: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Live activities list
            if let key = (publicKeyHex ?? appState.publicKey?.hex) {
                let events = appState.profileEvents(key)

                if events.isEmpty {
                    VStack {
                        Text("No streams found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(events, id: \.id) { event in
                            ProfileStreamCard(event: event)
                                .onTapGesture {
                                    appState.playerConfig.selectedLiveActivitiesEvent = event
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        appState.playerConfig.showMiniPlayer = true
                                    }
                                }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            } else {
                VStack {

                    Text("Please sign in to view your streams")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Second Tab Content
struct ShortsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("No shorts yet")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Profile Stream Card
struct ProfileStreamCard: View {
    @EnvironmentObject var appState: AppState
    let event: LiveActivitiesEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail
            ZStack(alignment: .topLeading) {
                KFImage.url(event.image)
                    .placeholder {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))

                            VStack(spacing: 8) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)

                                Text("No Preview")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .cornerRadius(12)

                // Live/Ended badge
                HStack {
                    Text(event.status != .live ? "ENDED" : "LIVE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(event.status != .live ? Color.gray : Color.red)
                        .cornerRadius(4)

                    Spacer()
                }
                .padding(8)
            }

            // Stream info
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled Stream")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let startTime = event.startsAt {
                    Text(formatStreamTime(startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview
struct ProfileTabView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTabView()
    }
}
