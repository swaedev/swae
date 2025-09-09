//
//  ProfileTabView.swift
//  swae
//
//  Created by Suhail Saqan on 2/26/25.
//

import Kingfisher
import NostrSDK
import SwiftUI

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
                            .padding(.top, 16)
                        Spacer()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
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
                .padding(.top, 16)
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
        VStack(alignment: .leading, spacing: 5) {
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
            VStack(alignment: .leading) {
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
    }
}
