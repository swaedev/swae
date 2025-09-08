//
//  NostrEventStore.swift
//  swae
//
//  Centralized dedupe/replace logic for Nostr events, optimized for LiveActivities (NIP-53).
//

import Foundation
import NostrSDK

// Tie-breaker per NIP-16: latest created_at wins; if equal, lowest id wins.
@inline(__always)
private func shouldReplace(old: NostrEvent, with new: NostrEvent) -> Bool {
    if new.createdAt > old.createdAt { return true }
    if new.createdAt < old.createdAt { return false }
    return new.id.lexicographicallyPrecedes(old.id)
}

private struct ReplaceKey: Hashable {
    let pubkey: String
    let kind: Int
}

private struct AddrKey: Hashable {
    let pubkey: String
    let kind: Int
    let d: String
}

private enum EventClass {
    case ephemeral
    case delete
    case parameterizedReplaceable(AddrKey)
    case replaceable(ReplaceKey)
    case regular
}

private func extractD(_ event: NostrEvent) -> String? {
    // Use SDK helper to fetch the first value for raw tag name "d"
    return event.firstValueForRawTagName("d")
}

private func isEphemeral(kind: Int) -> Bool {
    kind >= 20000 && kind < 30000
}

private func classify(_ event: NostrEvent) -> EventClass {
    if isEphemeral(kind: event.kind.rawValue) { return .ephemeral }
    if event.kind.rawValue == 5 { return .delete }

    // Parameterized replaceable (NIP-33): 30_000–39_999 (e.g., 30311/30312/30313)
    if event.kind.rawValue >= 30000 && event.kind.rawValue < 40000, let d = extractD(event) {
        return .parameterizedReplaceable(
            .init(pubkey: event.pubkey, kind: event.kind.rawValue, d: d))
    }

    // Replaceable (NIP-16): examples include 0, 3, 10000–19999, and 10312 presence is replaceable per NIP-53 text
    if event.kind.rawValue == 0 || event.kind.rawValue == 3
        || (event.kind.rawValue >= 10000 && event.kind.rawValue < 20000)
    {
        return .replaceable(.init(pubkey: event.pubkey, kind: event.kind.rawValue))
    }

    return .regular
}

// Basic expiration handling (NIP-40)
private func isExpired(_ event: NostrEvent, now: Int64) -> Bool {
    if let expirationStr = event.firstValueForRawTagName("expiration"),
        let t = Int64(expirationStr)
    {
        return t <= now
    }
    return false
}

public actor NostrEventStore {
    // by id ensures we drop duplicates across relays quickly
    private var byId: [String: NostrEvent] = [:]
    private var deletedIds: Set<String> = []

    // Replaceable indexes
    private var replaceable: [ReplaceKey: NostrEvent] = [:]
    private var parameterized: [AddrKey: NostrEvent] = [:]

    // Presence TTL window (e.g., 120s)
    public let presenceTTLSeconds: Int64 = 120

    public init() {}

    public func ingest(_ event: NostrEvent, now: Int64 = Int64(Date().timeIntervalSince1970))
        -> Bool
    {
        // expiration
        if isExpired(event, now: now) { return false }

        // id dedupe (except deletions which we keep for tombstoning)
        if event.kind.rawValue != 5, byId[event.id] != nil { return false }

        switch classify(event) {
        case .ephemeral:
            return false

        case .delete:
            // Prefer typed deletion event for accuracy
            if let deletion = event as? DeletionEvent {
                for id in deletion.deletedEventIds {
                    deletedIds.insert(id)
                }
            }
            byId[event.id] = event
            return true

        case .parameterizedReplaceable(let key):
            if let old = parameterized[key] {
                if shouldReplace(old: old, with: event) {
                    byId[event.id] = event
                    parameterized[key] = event
                    return true
                } else {
                    return false
                }
            } else {
                byId[event.id] = event
                parameterized[key] = event
                return true
            }

        case .replaceable(let key):
            if let old = replaceable[key] {
                if shouldReplace(old: old, with: event) {
                    byId[event.id] = event
                    replaceable[key] = event
                    return true
                } else {
                    return false
                }
            } else {
                byId[event.id] = event
                replaceable[key] = event
                return true
            }

        case .regular:
            byId[event.id] = event
            return true
        }
    }

    public func isDeleted(_ id: String) -> Bool { deletedIds.contains(id) }

    public func latestLiveStream(pubkey: String, d: String) -> NostrEvent? {
        parameterized[.init(pubkey: pubkey, kind: 30311, d: d)]
    }

    public func latestSpace(pubkey: String, d: String) -> NostrEvent? {
        parameterized[.init(pubkey: pubkey, kind: 30312, d: d)]
    }

    public func latestMeeting(pubkey: String, d: String) -> NostrEvent? {
        parameterized[.init(pubkey: pubkey, kind: 30313, d: d)]
    }

    public func latestPresence(for pubkey: String, now: Int64 = Int64(Date().timeIntervalSince1970))
        -> NostrEvent?
    {
        guard let e = replaceable[.init(pubkey: pubkey, kind: 10312)] else { return nil }
        let isFresh = (now - e.createdAt) <= presenceTTLSeconds
        return isFresh ? e : nil
    }

    public func get(_ id: String) -> NostrEvent? { byId[id] }
}
