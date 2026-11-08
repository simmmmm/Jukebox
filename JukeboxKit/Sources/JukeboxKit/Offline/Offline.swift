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
        version = Self.version
        files = [:]
    }

    public func has(_ trackID: ItemID) -> Bool {
        files[trackID] != nil
    }

    public func file(_ trackID: ItemID) -> OfflineFile? {
        files[trackID]
    }

    /// The songs that have this reason, by id: a dictionary has no order of
    /// its own, and the same manifest must give the same list (the app puts
    /// an album's songs in the album's order itself).
    public func tracks(with reason: OfflineReason) -> [ItemID] {
        files.values.filter { $0.reasons.contains(reason) }.map(\.trackID).sorted()
    }

    /// Bytes of the songs someone chose, and of those only the keep holds.
    /// A song both chosen and kept is chosen: it stays when the keep lets
    /// it go, so it is not the keep's room.
    public var chosenBytes: Int64 { files.values.filter(\.isChosen).reduce(0) { $0 + $1.bytes } }
    public var keptBytes: Int64 { files.values.filter { !$0.isChosen }.reduce(0) { $0 + $1.bytes } }

    /// A song saved, or a reason added to one already there. Saved again
    /// (another quality, or two downloads of one song that crossed), the
    /// newest save is the file: its name, size, date and quality, with the
    /// reasons of both. When the name changed, the older file is no longer
    /// the manifest's, so the app deletes it (`file(_:)` before `add` names
    /// it); a name made by `OfflineFile.fileName(trackID:contentType:)` is
    /// the same for the same song and kind of file, and is overwritten.
    public mutating func add(_ file: OfflineFile) {
        var file = file
        if let old = files[file.trackID] { file.reasons.formUnion(old.reasons) }
        files[file.trackID] = file
    }

    /// Adds a reason to a song already on the phone. False when it is not.
    @discardableResult
    public mutating func addReason(_ reason: OfflineReason, to trackID: ItemID) -> Bool {
        guard files[trackID] != nil else { return false }
        files[trackID]?.reasons.insert(reason)
        return true
    }

    /// Takes a reason away from every song that has it; returns the files
    /// left with no reason at all, which the app deletes.
    public mutating func removeReason(_ reason: OfflineReason) -> [OfflineFile] {
        removeReason(reason, from: tracks(with: reason))
    }

    /// Takes one reason away from some songs (the keep letting go of a few);
    /// returns the files left with no reason, which the app deletes. A song
    /// asked about that had no reason left already is returned too, so it
    /// does not stay on the phone for nothing; one not here is passed over.
    public mutating func removeReason(_ reason: OfflineReason, from trackIDs: [ItemID]) -> [OfflineFile] {
        var orphans: [OfflineFile] = []
        for id in trackIDs {
            guard var file = files[id] else { continue }
            file.reasons.remove(reason)
            if file.reasons.isEmpty {
                files[id] = nil
                orphans.append(file)
            } else {
                files[id] = file
            }
        }
        return orphans
    }

    /// Forgets songs whose files are gone (the app checked the folder).
    public mutating func forget(_ trackIDs: [ItemID]) {
        for id in trackIDs { files[id] = nil }
    }

    /// The manifest at `url`; empty when there is none, it does not read, or
    /// it is of another version.
    public static func load(from url: URL) -> OfflineManifest {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(OfflineManifest.self, from: data),
              manifest.version == Self.version else {
            return OfflineManifest()
        }
        return manifest
    }

    /// Written atomically: a crash halfway leaves the old manifest, never
    /// half a new one (which would read as empty and lose every reason).
    /// Keys sorted, so the file reads song by song.
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
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
        // How it ranks and fills, and why each number: Keep.swift.
        plan(tracks: tracks, history: history, manifest: manifest, limitBytes: limitBytes,
             quality: quality, now: now, tuning: .standard)
    }

    /// A song's size before it is fetched, for the limit and for Settings'
    /// "about … GB": its length at the quality's bitrate (the original's from
    /// a typical lossless or MP3 rate when the server does not say).
    ///
    /// Measured on 12.4 (downloadURL's files, a 4-minute stereo song): the
    /// AAC is its bitrate and 2.8 kbit/s more, the m4a's index of its
    /// frames (7 765 392 bytes at 256, 3 924 627 at 128, for 240.05 s); 3
    /// kbit/s is allowed, which is 0.1% over. At .high and .normal that is
    /// at most what comes: a file the server sends as it is is smaller.
    /// Jellyfin knows the original's bitrate, but Track does not carry it,
    /// so .original assumes 900 kbit/s: CD-quality FLAC or ALAC of pop and
    /// rock is 800–1000 kbit/s, and a library of MP3 and AAC is below it.
    /// Erring large is the side that does no harm: the keep then holds a
    /// little less than its limit until the real sizes are in (the plan
    /// counts a kept song by its file), where erring small would fetch songs
    /// it must let go of again. A song of no known length counts as four
    /// minutes, not as nothing.
    public static func estimatedBytes(of track: Track, quality: DownloadQuality) -> Int64 {
        let seconds = track.duration.isFinite && track.duration > 0 ? track.duration : 240
        let bitsPerSecond: Double = switch quality {
        case .original: 900_000
        case .high, .normal: Double(quality.aacBitrate ?? 0) + 3_000
        }
        return Int64((seconds * bitsPerSecond / 8).rounded(.up))
    }
}

extension JellyfinClient {
    /// A song's file to save, at a quality: a plain file (never HLS), so a
    /// download task can fetch it in the background. The token is in the
    /// URL, as for streaming. Which endpoint, measured on 12.4: OFFLINE.md.
    ///
    /// GET /Audio/{id}/universal with TranscodingProtocol=http: Jellyfin
    /// sends the file itself when the phone plays its container and (at
    /// .high and .normal) it is no larger than the quality, and otherwise
    /// transcodes it to AAC in an m4a as one plain response. `.original` is
    /// the file as it is for every container AVPlayer plays; for one it
    /// cannot (Ogg, Opus, WMA …) it is AAC at 256, since a file the phone
    /// cannot play is no use on it. "No larger" allows 10% for the
    /// container: the test library's 128 kbit/s MP3 and M4A are 129.2 and
    /// 129.5 kbit/s with their tags, and asked for exactly 128 Jellyfin
    /// re-encoded the M4A into a larger file (99 224 bytes, from 97 105) —
    /// so the cap is 141 / 282 kbit/s and the AAC asked for 128 / 256.
    ///
    /// Measured on 12.4 (8 November 2026, curl, no header, this URL):
    /// - The test library (6–8 s mono tones): at every quality the MP3 (200
    ///   audio/mpeg), FLAC (audio/flac) and M4A (audio/mp4) came as
    ///   themselves, byte for byte the files /Items/{id}/Download gives,
    ///   with Content-Length and Accept-Ranges: bytes. With the cap at 70
    ///   kbit/s: 200 audio/mp4, AAC LC 64 kbit/s, an m4a ffprobe reads to the
    ///   end (8.05 s), Transfer-Encoding: chunked, Accept-Ranges: none.
    /// - A second server with four 4-minute stereo files (FLAC 512 kbit/s,
    ///   MP3 320, AAC 222, Ogg Vorbis 96):
    ///   .original: FLAC 15 369 415 bytes and MP3 9 602 787 as themselves
    ///     in 0.05–0.16 s, AAC 6 659 361 as itself, the Ogg as AAC 256
    ///     (7 765 165 bytes, 2.0 s);
    ///   .high: FLAC, MP3 and Ogg as AAC 256 kbit/s m4a (7.77 MB, 2.2–2.4 s),
    ///     the AAC as itself;
    ///   .normal: all four as AAC 128 kbit/s m4a (3.88–3.92 MB, 1.8–2.1 s).
    ///   Every transcode: AAC LC, stereo, 240.05 s to ffprobe; Jellyfin's
    ///   ffmpeg writes it with `-movflags empty_moov+delay_moov`: ftyp, moov,
    ///   one moof, mdat, mfra — a fragmented MP4, one fragment for the
    ///   whole song. AVFoundation reads movie fragments (AVAsset's
    ///   containsFragments); that AVPlayer plays this one from a file is
    ///   not checked on a phone here (docs/OFFLINE.md, "In the app").
    ///   Four transcodes at once and an HLS stream, one device: all four
    ///   whole. A transcode read slowly (8 s rather than 1.9): the same bytes.
    /// - A transcode has no Content-Length (progress has no total) and
    ///   cannot be resumed from the middle; the file itself can.
    /// - /Items/{id}/Download is the same file for the original, but 403
    ///   for a user whose admin turned downloads off, where this URL is 200:
    ///   `downloadsAllowed()` asks what the admin said.
    /// - /Audio/{id}/stream.m4a (and .aac, .mp4) always transcode, even a
    ///   file already small enough (the 222 kbit/s AAC asked for 256 came
    ///   re-encoded, 7 724 036 bytes for 6 659 361); /Audio/{id}/stream?static=true
    ///   never does. TranscodingContainer=aac gives ADTS instead (200 audio/aac,
    ///   7 681 532 bytes for the FLAC at .high) — the fallback, should a
    ///   phone not play the fragmented m4a.
    /// - Mono is capped at 128 kbit/s by Jellyfin (asked for 256, a mono
    ///   FLAC came as 128); AudioBitRate below that is kept (96 → 96).
    /// - No token: 401; `api_key` instead of ApiKey: 401.
    public func downloadURL(trackID: ItemID, quality: DownloadQuality) -> URL {
        var query = [
            URLQueryItem(name: "UserId", value: userID ?? ""),
            URLQueryItem(name: "DeviceId", value: identity.deviceID),
            URLQueryItem(name: "Container", value: Self.directContainers),
            URLQueryItem(name: "TranscodingContainer", value: "m4a"),
            URLQueryItem(name: "TranscodingProtocol", value: "http"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
        ]
        if let bitrate = quality.aacBitrate {
            query.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(bitrate + bitrate / 10)))
        }
        query.append(URLQueryItem(name: "AudioBitRate", value: String(quality.aacBitrate ?? 256_000)))
        if let accessToken, !accessToken.isEmpty {
            query.append(URLQueryItem(name: "ApiKey", value: accessToken))
        }
        return url("/Audio/\(Self.segment(trackID))/universal", query)
    }
}
