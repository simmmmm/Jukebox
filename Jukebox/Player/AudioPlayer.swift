// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// The one player: a queue of tracks streamed from Jellyfin through
// AVQueuePlayer (the next track preloaded, so albums play without a gap),
// in the background and on the lock screen (MPNowPlayingInfoCenter,
// MPRemoteCommandCenter, thumbs up and down there too while a station
// plays), AirPlay, interruptions and headphones handled as Music does.
// It tells Jellyfin what plays (so play counts are right on every client),
// writes each play to the history, and asks the radio for more when a
// station's queue runs low.

import Foundation
import JukeboxKit
import Observation

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

@Observable
final class AudioPlayer {
    /// Everything, played and to come, in play order.
    private(set) var queue: [QueueEntry] = []
    /// Into `queue`; nil when nothing is loaded.
    private(set) var currentIndex: Int?
    private(set) var context: QueueContext?
    private(set) var isPlaying = false
    /// Waiting for the network.
    private(set) var isBuffering = false
    /// Seconds into the current track.
    private(set) var elapsed: TimeInterval = 0
    /// The current track's length, seconds.
    private(set) var duration: TimeInterval = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off
    /// The last error, for a moment in Now Playing ("Could not play …").
    private(set) var errorMessage: String?

    var client: JellyfinClient?
    /// Set by AppModel; the radio this player asks for more.
    weak var radio: RadioController?

    init(settings: AppSettings, history: HistoryStore) {
        fatalError("not built yet")
    }

    var current: QueueEntry? { currentIndex.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var currentTrack: Track? { current?.track }
    /// After the current one, in order.
    var upNext: [QueueEntry] {
        guard let currentIndex else { return queue }
        return Array(queue[(currentIndex + 1)...])
    }
    /// Before the current one, oldest first.
    var played: [QueueEntry] {
        guard let currentIndex else { return [] }
        return Array(queue[..<currentIndex])
    }
    var hasTrack: Bool { current != nil }

    // MARK: Starting

    /// Replace the queue with `tracks` and play from `index`; shuffled
    /// starts at a random track unless `index` is given explicitly as
    /// anything but 0.
    func play(_ tracks: [Track], startingAt index: Int = 0, context: QueueContext, shuffled: Bool = false) {
        fatalError("not built yet")
    }

    /// The radio's picks as a new queue (RadioController calls this).
    func playRadio(_ picks: [RadioPick], station: Station) {
        fatalError("not built yet")
    }

    /// The radio's further picks at the end of the queue.
    func appendRadio(_ picks: [RadioPick]) {
        fatalError("not built yet")
    }

    /// Drop everything after the current track that the radio chose, so it
    /// can choose again after feedback; returns those tracks' ids.
    @discardableResult
    func removeUpcomingRadioPicks() -> [ItemID] {
        fatalError("not built yet")
    }

    func playNext(_ tracks: [Track]) {
        fatalError("not built yet")
    }

    func addToQueue(_ tracks: [Track]) {
        fatalError("not built yet")
    }

    // MARK: Transport

    func togglePlayPause() { fatalError("not built yet") }
    func resume() { fatalError("not built yet") }
    func pause() { fatalError("not built yet") }
    func next() { fatalError("not built yet") }
    /// Back to the start of the track after 3 s, else the track before.
    func previous() { fatalError("not built yet") }
    func seek(to seconds: TimeInterval) { fatalError("not built yet") }
    func skip(to entry: QueueEntry) { fatalError("not built yet") }
    func toggleShuffle() { fatalError("not built yet") }
    /// off → all → one → off.
    func cycleRepeat() { fatalError("not built yet") }
    func stop() { fatalError("not built yet") }

    // MARK: Editing Up Next

    /// Offsets into `upNext`.
    func removeUpcoming(atOffsets offsets: IndexSet) { fatalError("not built yet") }
    /// Offsets into `upNext`, as List's onMove gives them.
    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) { fatalError("not built yet") }
    func clearUpcoming() { fatalError("not built yet") }
}
