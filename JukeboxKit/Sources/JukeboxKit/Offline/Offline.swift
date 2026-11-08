// CONTRACT — signatures fixed; bodies the offline kit agent's (docs/OFFLINE.md).
//
// Music on the phone, for when there is no network — the photographer,
// 8 November 2026, asked whether there was "cache in offline/downloads", and
// to the three parts proposed ("Downloaden bij een album, een afspeellijst
// of een mix; automatisch bewaren wat je vaak of kort geleden hebt gespeeld,
// tot een grootte die je kiest; offline speelt de app alleen wat op de
// telefoon staat, ook de radio") answered "Alle drie".
//
// What is on the phone is one manifest: each song's file once, with every
// reason it is there. A song is kept while it has a reason: an album, a
// playlist or a mix chosen for download, or `.kept`, the automatic keep of
// what is played. Removing an album's download takes its reason away from
// its songs; a song another playlist also wants stays. The automatic keep
// has a limit of its own; what was chosen never counts against it and is
// never removed to make room.

import Foundation

/// Why a song is on the phone.
public enum OfflineReason: Hashable, Codable, Sendable {
    /// Its album was downloaded.
    case album(ItemID)
    /// A playlist with it was downloaded.
    case playlist(ItemID)
    /// A mix with it was downloaded (MixStore's mix id).
    case mix(String)
    /// The automatic keep: played often or lately (KeepPolicy).
    case kept

    /// Chosen by the listener, not by the keep.
    public var isChosen: Bool {
        if case .kept = self { return false }
        return true
    }
}

/// The quality songs are saved in. A file the phone keeps is a file it
/// stores: the original can be ten times the size of a good AAC.
public enum DownloadQuality: String, Codable, Sendable, Hashable, CaseIterable {
    /// The file as it is on the server.
    case original
    /// AAC at 256 kbit/s, or the file itself when it is no larger.
    case high
    /// AAC at 128 kbit/s, or the file itself when it is no larger.
    case normal
}

/// One song on the phone.
public struct OfflineFile: Hashable, Codable, Sendable {
    public var trackID: ItemID
    /// The file's name in the offline folder (the app owns the folder).
    public var fileName: String
    public var bytes: Int64
    public var savedAt: Date
    public var quality: DownloadQuality
    public var reasons: Set<OfflineReason>

    public init(trackID: ItemID, fileName: String, bytes: Int64, savedAt: Date,
                quality: DownloadQuality, reasons: Set<OfflineReason>) {
        self.trackID = trackID
        self.fileName = fileName
        self.bytes = bytes
        self.savedAt = savedAt
        self.quality = quality
        self.reasons = reasons
    }

    /// Kept because someone chose it, not only by the automatic keep.
    public var isChosen: Bool { reasons.contains { $0.isChosen } }
}

/// Everything on the phone, saved as JSON beside the files.
public struct OfflineManifest: Codable, Sendable {
    /// Bump when the shape changes: an old manifest is then read as empty
    /// and its files are found again by the app (or removed).
    public static let version = 1

    public var version: Int
    public private(set) var files: [ItemID: OfflineFile]

    public init() {
        fatalError("contract")
    }

    public func has(_ trackID: ItemID) -> Bool {
        fatalError("contract")
    }

    public func file(_ trackID: ItemID) -> OfflineFile? {
        fatalError("contract")
    }

    /// The songs that have this reason.
    public func tracks(with reason: OfflineReason) -> [ItemID] {
        fatalError("contract")
    }

    /// Bytes of the songs someone chose, and of those only the keep holds.
    public var chosenBytes: Int64 { fatalError("contract") }
    public var keptBytes: Int64 { fatalError("contract") }

    /// A song saved, or a reason added to one already there.
    public mutating func add(_ file: OfflineFile) {
        fatalError("contract")
    }

    /// Adds a reason to a song already on the phone. False when it is not.
    @discardableResult
    public mutating func addReason(_ reason: OfflineReason, to trackID: ItemID) -> Bool {
        fatalError("contract")
    }

    /// Takes a reason away from every song that has it; returns the files
    /// left with no reason at all, which the app deletes.
    public mutating func removeReason(_ reason: OfflineReason) -> [OfflineFile] {
        fatalError("contract")
    }

    /// Takes one reason away from some songs (the keep letting go of a few);
    /// returns the files left with no reason, which the app deletes.
    public mutating func removeReason(_ reason: OfflineReason, from trackIDs: [ItemID]) -> [OfflineFile] {
        fatalError("contract")
    }

    /// Forgets songs whose files are gone (the app checked the folder).
    public mutating func forget(_ trackIDs: [ItemID]) {
        fatalError("contract")
    }

    /// The manifest at `url`; empty when there is none, it does not read, or
    /// it is of another version.
    public static func load(from url: URL) -> OfflineManifest {
        fatalError("contract")
    }

    /// Written atomically.
    public func save(to url: URL) throws {
        fatalError("contract")
    }
}

/// What the automatic keep should change: songs to fetch, best first, and
/// songs to let go of (only songs the keep alone holds).
public struct KeepPlan: Sendable, Equatable {
    public var download: [ItemID]
    public var remove: [ItemID]

    public init(download: [ItemID], remove: [ItemID]) {
        self.download = download
        self.remove = remove
    }
}

/// The automatic keep: which of the library's songs are worth having on the
/// phone, by how often and how lately they were heard (and liked), within a
/// limit in bytes. Measured, not guessed: docs/OFFLINE.md says how it ranks
/// and what a real history gives.
public enum KeepPolicy {
    /// What to fetch and what to let go of so the keep holds the best songs
    /// that fit in `limitBytes`. Songs someone chose are on the phone anyway:
    /// they are never in either list and do not count against the limit.
    public static func plan(tracks: [Track], history: ListeningHistory, manifest: OfflineManifest,
                            limitBytes: Int64, quality: DownloadQuality, now: Date) -> KeepPlan {
        fatalError("contract")
    }

    /// A song's size before it is fetched, for the limit and for Settings'
    /// "about … GB": its length at the quality's bitrate (the original's from
    /// a typical lossless or MP3 rate when the server does not say).
    public static func estimatedBytes(of track: Track, quality: DownloadQuality) -> Int64 {
        fatalError("contract")
    }
}

extension JellyfinClient {
    /// A song's file to save, at a quality: a plain file (never HLS), so a
    /// download task can fetch it in the background. The token is in the
    /// URL, as for streaming. Which endpoint, measured on 12.4: OFFLINE.md.
    public func downloadURL(trackID: ItemID, quality: DownloadQuality) -> URL {
        fatalError("contract")
    }
}
