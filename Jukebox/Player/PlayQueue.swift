// What a queue is made of, on every platform: the iPhone's AudioPlayer
// (AVFoundation) and Linux's (GStreamer, Linux/App/AudioPlayer.swift) keep
// the same queue of the same entries, and the radio, the screens and the
// usage counts speak of it in these words. Foundation only: Package.swift
// compiles this file for Linux as it is.

import Foundation
import JukeboxKit

enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one
}

/// What the queue was started from: its name in Now Playing ("Playing from
/// Kid A") and whether a station plays.
struct QueueContext: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case album(ItemID)
        case artist(ItemID)
        case playlist(ItemID)
        case mix(String)
        case genre(String)
        case songs
        case favorites
        case search
        case radio(Station)
        case other
    }

    var kind: Kind
    var title: String

    init(_ kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }

    var station: Station? {
        if case let .radio(station) = kind { return station }
        return nil
    }

    var isRadio: Bool { station != nil }
}

/// One place in the queue: the same track can be in it twice.
struct QueueEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let track: Track
    /// Why the radio chose it, shown under it in Up Next.
    let reason: PickReason?

    init(track: Track, reason: PickReason? = nil) {
        id = UUID()
        self.track = track
        self.reason = reason
    }
}
