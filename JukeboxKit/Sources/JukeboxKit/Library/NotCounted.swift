// What is played but not counted: songs, albums and playlists the listener
// marked, and Private Listening, which counts nothing while it is on. The
// photographer, 19 November 2026: "kun je het ook mogelijk maken om
// nummers/albums/playlists niet te scrobblen? of mee te laten tellen voor
// die stats bijv voor kerstmuziek oid?", and then "zet daar dan uberhaupt
// gewoon een modus aan of uit of tot volgende restart als een soort prive
// modus overall".
//
// Not counted means the server hears nothing of the play (so no play count,
// no scrobble from it, no Playback Reporting row) and the device keeps no
// memory of it (the history: the radio's learning, the clock, Your Year,
// the mixes). It still plays, queues and shows in this session's Up Next.
// The app asks `counts` in one place, PlayQueue.counts.

import Foundation

public struct NotCounted: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case song
        case album
        case playlist
    }

    public struct Item: Codable, Sendable, Hashable {
        public let kind: Kind
        public let id: ItemID
        /// For Settings' list; the name when it was marked.
        public let name: String

        public init(kind: Kind, id: ItemID, name: String) {
            self.kind = kind
            self.id = id
            self.name = name
        }

        /// Unique in the list: a Subsonic server may give a song and an
        /// album the same id.
        public var key: String { "\(kind.rawValue):\(id)" }
    }

    /// Newest first.
    public private(set) var items: [Item] = []

    public init(items: [Item] = []) {
        self.items = items
    }

    public func contains(_ kind: Kind, _ id: ItemID) -> Bool {
        items.contains { $0.kind == kind && $0.id == id }
    }

    /// Marked as not counted (`counted` false), or counted again.
    public mutating func set(_ item: Item, counted: Bool) {
        items.removeAll { $0.kind == item.kind && $0.id == item.id }
        if !counted { items.insert(item, at: 0) }
    }

    /// Whether a play of `track` counts: not when the song, its album, or
    /// the playlist it was played from is marked.
    public func counts(_ track: Track, playlistID: ItemID?) -> Bool {
        if contains(.song, track.id) { return false }
        if let album = track.albumID, contains(.album, album) { return false }
        if let playlistID, contains(.playlist, playlistID) { return false }
        return true
    }
}

/// Private Listening: nothing counts while it is on. `untilRestart` is
/// never kept, so the next launch counts again.
public enum PrivateListening: String, Codable, Sendable, CaseIterable {
    case off
    case on
    case untilRestart

    /// What may be kept across launches: only `on`.
    public static func restored(_ saved: String?) -> PrivateListening {
        saved == PrivateListening.on.rawValue ? .on : .off
    }
}
