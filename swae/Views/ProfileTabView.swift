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

    var body: some View {
            VStack(spacing: 0) {
                // Top Tab Bar
//                HStack {
//                    ProfileTabButton(title: "Live Streams", selectedTab: $selectedTab, tabIndex: 0)
//                    ProfileTabButton(title: "Shorts", selectedTab: $selectedTab, tabIndex: 1)
//                }
//                .padding(.horizontal)
//                .padding(.top)

                // Underline Indicator
//                GeometryReader { geo in
//                    let buttonWidth = geo.size.width / 2
//                    Capsule()
//                        .fill(Color.purple)
//                        .frame(width: 75, height: 2)
//                        .offset(x: selectedTab == 0 ? (buttonWidth - 75) / 2 : buttonWidth + (buttonWidth - 75) / 2)
//                        .animation(.easeInOut, value: selectedTab)
//                }
//                .frame(height: 2)

                LiveActivities()

                // TabView
//                TabView(selection: $selectedTab) {
//                    LiveActivities()
//                        .tag(0)
//                    Shorts()
//                        .tag(1)
//                }
//                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
}

// MARK: - Custom Tab Button
struct ProfileTabButton: View {
    var title: String
    @Binding var selectedTab: Int
    var tabIndex: Int

    var body: some View {
        Button(action: {
            withAnimation {
                selectedTab = tabIndex
            }
        }) {
            Text(title)
                .font(.headline)
                .foregroundColor(selectedTab == tabIndex ? .purple : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - First Tab Content
struct LiveActivities: View {
    @EnvironmentObject var appState: AppState
    @State private var timeTabFilter: TimeTabs = .past

    var body: some View {
        VStack(spacing: 0) {
            // Time filter picker
            CustomSegmentedPicker(selectedTimeTab: $timeTabFilter) {
                // Optional scroll action if needed
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Live activities list
            if let publicKeyHex = appState.publicKey?.hex {
                let events =
                    timeTabFilter == .upcoming
                    ? appState.upcomingProfileEvents(publicKeyHex)
                    : appState.pastProfileEvents(publicKeyHex)

                if events.isEmpty {
                    VStack {
                        Spacer()
                        Text("No streams found")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text(timeTabFilter == .upcoming ? "No upcoming streams" : "No past streams")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
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
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Please sign in to view your streams")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Second Tab Content
struct Shorts: View {
    var body: some View {
        Text("yo")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.green.opacity(0.2))
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

    private func formatStreamTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview
struct ProfileTabView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTabView()
    }
}
