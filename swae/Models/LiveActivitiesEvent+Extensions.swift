//
//  LiveActivitiesEvent+Extensions.swift
//  swae
//
//  Created by Suhail Saqan on 12/7/24.
//

import Foundation

#if canImport(NostrSDK)
    import NostrSDK

    extension LiveActivitiesEvent {
        var isLive: Bool {
            if status == .live { return true }
            if let startsAt {
                if let endsAt { return startsAt <= Date.now && endsAt >= Date.now }
                return startsAt <= Date.now
            }
            return false
        }

        var isReplay: Bool {
            return !isLive && isPast
        }
        var isUpcoming: Bool {
            guard let startsAt else {
                return false
            }

            guard let endsAt else {
                return startsAt >= Date.now
            }
            return startsAt >= Date.now || endsAt >= Date.now
        }

        var isPast: Bool {
            guard let startsAt else {
                return false
            }

            guard let endsAt else {
                return startsAt < Date.now
            }
            return endsAt < Date.now
        }

        /// Best-effort current participants count per NIP-53. Falls back to participant list size.
        var currentParticipants: Int {
            if let raw = firstValueForRawTagName("current_participants"), let value = Int(raw) {
                return value
            }
            // Fallback: derive from participants array if tag missing
            return participants.count
        }

        /// Internal category tags (only tags that start with "internal:").
        var internalTags: [String] {
            hashtags.filter { $0.hasPrefix("internal:") }
        }

        /// Convenience popularity score used for sorting lists.
        var popularityScore: Int { currentParticipants }
    }
#endif
