// Where the songs on the phone live, and the few files that say why each is
// there. One folder per account — server and user — in Application Support,
// excluded from backup (the music is on the server; an iCloud backup of
// gigabytes of it would only cost the listener their backup space):
//
//   Application Support/Offline/<server>-<user>/
//     manifest.json     every song on the phone, once, with its reasons (JukeboxKit's OfflineManifest)
//     collections.json  the albums, playlists and mixes chosen, with their songs in order
//     queue.json        the songs still to fetch, and those the server would not give
//     reports.json      plays heard offline, for the server once it answers
//     files/            the songs, "<track id>.<ext>" (the kit's OfflineFile.fileName,
//                       from the Content-Type the server sent)
//
// Another account's folder is never read: signing out removes the account's
// folder (OfflineStore.signOut), and a folder of an account that is not the
// one signing in is a leftover of that and goes too. So the next account,
// perhaps on another server, never plays the last one's songs.
//
// Everything here runs off the main actor (the store's writer queue, a
// detached task at sign-in, the download session's queue): `nonisolated`,
// and the types are values that cross freely.

import Foundation
import JukeboxKit

/// What a chosen download is of: an album, a playlist or a mix, with what
/// its page needs to open again without the server.
nonisolated enum OfflineItem: Codable, Sendable, Hashable {
    case album(Album)
    case playlist(Playlist)
    /// A mix of one day (MixStore makes new ones every day, with new ids):
    /// kept as it was when it was downloaded.
    case mix(SavedMix)
}

/// A mix as it was downloaded: Mix itself is not Codable.
nonisolated struct SavedMix: Codable, Sendable, Hashable {
    var id: String
    var kind: MixKind
    var title: String
    var subtitle: String
    var artwork: [Artwork]
    var stationSeed: StationSeed

    init(_ mix: Mix) {
        id = mix.id
        kind = mix.kind
        title = mix.title
        subtitle = mix.subtitle
        artwork = mix.artwork
        stationSeed = mix.stationSeed
    }

    func mix(tracks: [Track]) -> Mix {
        Mix(id: id, kind: kind, title: title, subtitle: subtitle, tracks: tracks, artwork: artwork,
            stationSeed: stationSeed)
    }
}

/// An album, a playlist or a mix chosen for the phone, with its songs in
/// their order: the manifest knows which songs a reason holds, not in what
/// order, and offline a playlist's page cannot ask the server.
nonisolated struct OfflineCollection: Codable, Sendable, Hashable, Identifiable {
    var item: OfflineItem
    var tracks: [Track]
    var addedAt: Date

    init(item: OfflineItem, tracks: [Track], addedAt: Date = Date()) {
        self.item = item
        self.tracks = tracks
        self.addedAt = addedAt
    }

    init(album: Album, tracks: [Track]) {
        self.init(item: .album(album), tracks: tracks)
    }

    init(playlist: Playlist, tracks: [Track]) {
        self.init(item: .playlist(playlist), tracks: tracks)
    }

    init(mix: Mix) {
        self.init(item: .mix(SavedMix(mix)), tracks: mix.tracks)
    }

    var id: OfflineReason { reason }

    /// The manifest's reason for its songs.
    var reason: OfflineReason {
        switch item {
        case let .album(album): return .album(album.id)
        case let .playlist(playlist): return .playlist(playlist.id)
        case let .mix(mix): return .mix(mix.id)
        }
    }

    var title: String {
        switch item {
        case let .album(album): return album.name
        case let .playlist(playlist): return playlist.name
        case let .mix(mix): return mix.title
        }
    }

    /// Its kind in the usage counts (Stats, `download_chosen`): never which.
    var kind: String {
        switch item {
        case .album: return "album"
        case .playlist: return "playlist"
        case .mix: return "mix"
        }
    }

    var trackIDs: [ItemID] { tracks.map(\.id) }
}

/// A song still to fetch, with every reason it is wanted.
nonisolated struct OfflineWanted: Codable, Sendable, Hashable {
    var trackID: ItemID
    var reasons: Set<OfflineReason>
    var quality: DownloadQuality
    /// Its size before it is fetched (KeepPolicy.estimatedBytes): the
    /// progress of a file whose length the server does not send.
    var estimate: Int64

    /// Chosen by the listener, not only by the keep: fetched first, also in
    /// Low Power Mode.
    var isChosen: Bool { reasons.contains { $0.isChosen } }
}

/// A play heard while the server could not be told: its start report (Jellyfin
/// counts the play there, and its Last.fm plugin scrobbles from these
/// reports) and its stop, sent in order when the server answers again.
nonisolated struct PendingPlay: Codable, Sendable, Hashable {
    var trackID: ItemID
    var playSessionID: String
    /// Where the start report was made; nil when it was sent at the time.
    var startPosition: TimeInterval?
    /// Nil while the song still plays, or when the app ended before it did.
    var stopPosition: TimeInterval?
}

/// queue.json.
nonisolated struct OfflineQueueFile: Codable, Sendable {
    var wanted: [OfflineWanted] = []
    var failed: [ItemID] = []
    /// What the server said last of "Allow media downloading" for this
    /// user; nil before it was asked (a queue.json of before it was kept).
    var downloadsAllowed: Bool?
}

/// Everything one account keeps, as read at sign-in and written after a change.
nonisolated struct OfflineAccountState: Sendable {
    var manifest: OfflineManifest
    var collections: [OfflineCollection]
    var wanted: [OfflineWanted]
    var failed: [ItemID]
    var reports: [PendingPlay]
    var downloadsAllowed: Bool
}

nonisolated enum OfflinePaths {
    /// Application Support/Offline.
    static var base: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("Offline", isDirectory: true)
    }

    /// The account's folder name: the server's id and the user's, which are
    /// Jellyfin's hex GUIDs; anything else in them is left out, so the name
    /// is always a plain folder name.
    static func account(for credentials: Credentials) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let server = String(credentials.serverID.filter { allowed.contains($0) })
        let user = String(credentials.userID.filter { allowed.contains($0) })
        return "\(server)-\(user)"
    }

    static func folder(_ account: String) -> URL {
        base.appendingPathComponent(account, isDirectory: true)
    }

    static func files(_ account: String) -> URL {
        folder(account).appendingPathComponent("files", isDirectory: true)
    }

    static func manifest(_ account: String) -> URL {
        folder(account).appendingPathComponent("manifest.json", isDirectory: false)
    }

    static func collections(_ account: String) -> URL {
        folder(account).appendingPathComponent("collections.json", isDirectory: false)
    }

    static func queue(_ account: String) -> URL {
        folder(account).appendingPathComponent("queue.json", isDirectory: false)
    }

    static func reports(_ account: String) -> URL {
        folder(account).appendingPathComponent("reports.json", isDirectory: false)
    }
}

nonisolated enum OfflineDisk {
    /// Made once a launch: the folder, kept out of backups (which a
    /// directory's flag does for everything in it).
    static func prepareBase() {
        var base = OfflinePaths.base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
    }

    /// The account's state at sign-in, checked against its folder: a file
    /// that is gone is forgotten (the contract's `forget`); a file the
    /// manifest does not know is a download whose news was lost (the app
    /// was ended as it finished) and is kept for the reasons it was wanted
    /// for, or removed when nothing wanted it. Other accounts' folders are
    /// leftovers of a sign-out, and go.
    static func load(_ account: String) -> OfflineAccountState {
        prepareBase()
        removeOtherAccounts(keeping: account)
        var manifest = OfflineManifest.load(from: OfflinePaths.manifest(account))
        let collections = read([OfflineCollection].self, from: OfflinePaths.collections(account)) ?? []
        let queue = read(OfflineQueueFile.self, from: OfflinePaths.queue(account)) ?? OfflineQueueFile()
        let reports = read([PendingPlay].self, from: OfflinePaths.reports(account)) ?? []
        var wanted = queue.wanted

        let folder = OfflinePaths.files(account)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])

        let missing = manifest.files.values.filter { !names.contains($0.fileName) }.map(\.trackID)
        if !missing.isEmpty { manifest.forget(missing) }

        let known = Set(manifest.files.values.map(\.fileName))
        for name in names where !known.contains(name) {
            let url = folder.appendingPathComponent(name, isDirectory: false)
            let trackID = (name as NSString).deletingPathExtension
            if let at = wanted.firstIndex(where: { $0.trackID == trackID }), !manifest.has(trackID) {
                let item = wanted.remove(at: at)
                manifest.add(OfflineFile(trackID: trackID, fileName: name, bytes: fileSize(url), savedAt: Date(),
                                         quality: item.quality, reasons: item.reasons))
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // Wanted, and on the phone after all: its reasons join the file's.
        for item in wanted where manifest.has(item.trackID) {
            for reason in item.reasons { manifest.addReason(reason, to: item.trackID) }
        }
        wanted.removeAll { manifest.has($0.trackID) }

        return OfflineAccountState(manifest: manifest, collections: collections, wanted: wanted,
                                   failed: queue.failed, reports: reports,
                                   downloadsAllowed: queue.downloadsAllowed ?? true)
    }

    static func save(_ state: OfflineAccountState, of account: String) {
        try? FileManager.default.createDirectory(at: OfflinePaths.folder(account), withIntermediateDirectories: true)
        try? state.manifest.save(to: OfflinePaths.manifest(account))
        write(state.collections, to: OfflinePaths.collections(account))
        write(OfflineQueueFile(wanted: state.wanted, failed: state.failed, downloadsAllowed: state.downloadsAllowed),
              to: OfflinePaths.queue(account))
        write(state.reports, to: OfflinePaths.reports(account))
    }

    static func removeFiles(_ names: [String], of account: String) {
        let folder = OfflinePaths.files(account)
        for name in names {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name, isDirectory: false))
        }
    }

    /// Remove All Downloads: the songs; the account's small files are
    /// written again, empty, by the store.
    static func removeAllFiles(of account: String) {
        try? FileManager.default.removeItem(at: OfflinePaths.files(account))
    }

    /// Signing out: everything of the account.
    static func removeAccount(_ account: String) {
        try? FileManager.default.removeItem(at: OfflinePaths.folder(account))
    }

    static func fileSize(_ url: URL) -> Int64 {
        // The size alone: not the file's dates, which the privacy manifest
        // would have to give a reason for.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return Int64(size)
    }

    private static func removeOtherAccounts(keeping account: String) {
        let base = OfflinePaths.base
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        for name in names where name != account {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(name, isDirectory: true))
        }
    }

    private static func write<Value: Encodable>(_ value: Value, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
