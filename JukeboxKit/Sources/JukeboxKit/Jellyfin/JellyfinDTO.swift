// What Jellyfin sends, as it spells it (BaseItemDto and friends), and the
// one place it becomes Jukebox's own Track, Album, Artist, Playlist and
// Genre (Library/Models.swift). Nothing above the client reads these.
//
// Almost every field is optional on purpose: one odd item (no name, a date
// in a shape nobody expected) must cost that item, not the whole page of
// 2000 tracks it came in. Dates arrive as strings and are read by
// JellyfinDate, so a date that cannot be read is nil rather than a
// decoding error.
//
// Seen on Jellyfin 12.4 (the test server, 8 November 2026):
// - Genres and artists come exactly as tagged. The test library's tags are
//   "Rock; Alternative" and the library does not split them
//   (LibraryOptions.UseCustomTagDelimiters is false by default), so there
//   they arrive as one genre "Rock; Alternative". The client passes them on
//   as Jellyfin has them: splitting here would give names no Genre item and
//   no genre id has.
// - Tracks have no image of their own (ImageTags is {}) and carry their
//   album's as AlbumPrimaryImageTag.
// - Albums have RunTimeTicks (the sum of their tracks) and no
//   CumulativeRunTimeTicks; ChildCount is the number of tracks.
// - PlaylistItemId is the track's own id, so a track that is twice in a
//   playlist has one entry id for both (see removeFromPlaylist).
// - NormalizationGain is absent: the library's LUFS scan is off
//   (EnableLUFSScan false), so its mapping is tested on a literal only.
// - Genres and DateCreated are not in the default answer; Fields asks for
//   them (JellyfinRequests.swift).

import Foundation

/// An id and a name, as Jellyfin names artists and genres on an item.
struct JellyfinNameID: Decodable, Sendable, Hashable {
    var name: String?
    var id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

/// The listener's own data on an item.
struct JellyfinUserData: Decodable, Sendable, Hashable {
    var isFavorite: Bool?
    var playCount: Int?
    var lastPlayedDate: String?
    var played: Bool?

    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
        case playCount = "PlayCount"
        case lastPlayedDate = "LastPlayedDate"
        case played = "Played"
    }
}

/// Jellyfin's BaseItemDto, only the fields Jukebox reads.
struct JellyfinItem: Decodable, Sendable {
    var id: String?
    var name: String?
    var type: String?
    var mediaType: String?

    var album: String?
    var albumID: String?
    var albumArtist: String?
    var albumArtists: [JellyfinNameID]?
    var artists: [String]?
    var artistItems: [JellyfinNameID]?
    var genres: [String]?

    var productionYear: Int?
    var premiereDate: String?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var runTimeTicks: Int64?
    var cumulativeRunTimeTicks: Int64?

    var imageTags: [String: String]?
    var albumPrimaryImageTag: String?
    /// Search hints name the image this way instead of ImageTags.
    var primaryImageTag: String?

    var userData: JellyfinUserData?
    var dateCreated: String?
    var normalizationGain: Double?
    var playlistItemID: String?

    var childCount: Int?
    var songCount: Int?
    var albumCount: Int?
    var overview: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case mediaType = "MediaType"
        case album = "Album"
        case albumID = "AlbumId"
        case albumArtist = "AlbumArtist"
        case albumArtists = "AlbumArtists"
        case artists = "Artists"
        case artistItems = "ArtistItems"
        case genres = "Genres"
        case productionYear = "ProductionYear"
        case premiereDate = "PremiereDate"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case runTimeTicks = "RunTimeTicks"
        case cumulativeRunTimeTicks = "CumulativeRunTimeTicks"
        case imageTags = "ImageTags"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag"
        case primaryImageTag = "PrimaryImageTag"
        case userData = "UserData"
        case dateCreated = "DateCreated"
        case normalizationGain = "NormalizationGain"
        case playlistItemID = "PlaylistItemId"
        case childCount = "ChildCount"
        case songCount = "SongCount"
        case albumCount = "AlbumCount"
        case overview = "Overview"
    }
}

/// A page of items: /Items, /Artists/AlbumArtists, /MusicGenres,
/// /Playlists/{id}/Items, /Items/{id}/Similar, /Items/{id}/InstantMix.
struct JellyfinItemsResult: Decodable, Sendable {
    var items: [JellyfinItem]?
    var totalRecordCount: Int?
    var startIndex: Int?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }
}

/// GET /System/Info/Public.
struct JellyfinPublicInfo: Decodable, Sendable {
    var id: String?
    var serverName: String?
    var version: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
    }
}

/// POST /Users/AuthenticateByName and /Users/AuthenticateWithQuickConnect.
/// The user's ServerName is null on 12.4, so the server's name comes from
/// /System/Info/Public instead.
struct JellyfinAuthResult: Decodable, Sendable {
    struct User: Decodable, Sendable {
        var id: String?
        var name: String?
        var serverID: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case serverID = "ServerId"
        }
    }

    var user: User?
    var accessToken: String?
    var serverID: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverID = "ServerId"
    }
}

/// POST /QuickConnect/Initiate and GET /QuickConnect/Connect. 12.4 also
/// sends DeviceId, DeviceName, AppName, AppVersion and DateAdded.
struct JellyfinQuickConnectResult: Decodable, Sendable {
    var secret: String?
    var code: String?
    var authenticated: Bool?

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
        case code = "Code"
        case authenticated = "Authenticated"
    }
}

/// GET /Audio/{id}/Lyrics (10.9+): {"Metadata": {...}, "Lyrics": [{"Start": ticks?, "Text": "..."}]}.
/// 12.x also sends "Cues" (word timings) on a line; Jukebox shows lines.
struct JellyfinLyrics: Decodable, Sendable {
    struct Line: Decodable, Sendable {
        var start: Int64?
        var text: String?

        enum CodingKeys: String, CodingKey {
            case start = "Start"
            case text = "Text"
        }
    }

    struct Metadata: Decodable, Sendable {
        var isSynced: Bool?

        enum CodingKeys: String, CodingKey {
            case isSynced = "IsSynced"
        }
    }

    var lyrics: [Line]?
    var metadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case lyrics = "Lyrics"
        case metadata = "Metadata"
    }
}

/// POST /Playlists answers {"Id": "…"}.
struct JellyfinCreatedPlaylist: Decodable, Sendable {
    var id: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

// MARK: Request bodies

struct JellyfinAuthenticateByName: Encodable, Sendable {
    var username: String
    var password: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case password = "Pw"
    }
}

struct JellyfinQuickConnectSecret: Encodable, Sendable {
    var secret: String

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
    }
}

struct JellyfinCreatePlaylist: Encodable, Sendable {
    var name: String
    var ids: [String]
    var userID: String
    var mediaType = "Audio"

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case ids = "Ids"
        case userID = "UserId"
        case mediaType = "MediaType"
    }
}

/// The body of /Sessions/Playing, /Progress and /Stopped.
struct JellyfinPlaybackInfo: Encodable, Sendable {
    var itemID: String
    var mediaSourceID: String
    var positionTicks: Int64
    var isPaused: Bool
    var playSessionID: String
    /// DirectStream for every play, as the player only knows the URL it was
    /// given. Jellyfin uses the PlaySessionId, not this, to find and stop a
    /// transcode.
    var playMethod = "DirectStream"
    var canSeek = true

    enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playSessionID = "PlaySessionId"
        case playMethod = "PlayMethod"
        case canSeek = "CanSeek"
    }

    init(_ report: PlaybackReport) {
        itemID = report.trackID
        // An audio item's one media source has the item's own id.
        mediaSourceID = report.trackID
        positionTicks = JellyfinTicks.ticks(seconds: report.position)
        isPaused = report.isPaused
        playSessionID = report.playSessionID
    }
}

// MARK: Ticks

/// Jellyfin's times: 10 000 000 ticks a second (.NET's TimeSpan).
enum JellyfinTicks {
    static let perSecond: Double = 10_000_000

    static func seconds(_ ticks: Int64?) -> TimeInterval? {
        guard let ticks, ticks >= 0 else { return nil }
        return Double(ticks) / perSecond
    }

    static func ticks(seconds: TimeInterval) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * perSecond).rounded())
    }
}

// MARK: Into Jukebox's models

extension JellyfinItem {
    /// The item's id, when it has one worth keeping.
    var itemID: ItemID? {
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    var primaryImageTagOrNil: String? {
        imageTags?["Primary"] ?? primaryImageTag
    }

    /// ProductionYear, else the year of the PremiereDate (some taggers only
    /// give a full date).
    var year: Int? {
        if let productionYear, productionYear > 0 { return productionYear }
        // "2016-01-01T00:00:00.0000000Z": the year is the first four digits.
        guard let premiereDate, JellyfinDate.parse(premiereDate) != nil,
              let year = Int(premiereDate.prefix(4)), year > 1 else { return nil }
        return year
    }

    /// The performers with their ids (ArtistItems), else the names alone
    /// (search hints have only Artists).
    var artistRefs: [ArtistRef] {
        if let artistItems, !artistItems.isEmpty {
            return artistItems.compactMap(Self.ref)
        }
        return (artists ?? []).filter { !$0.isEmpty }.map { ArtistRef(id: nil, name: $0) }
    }

    /// The album artists with ids, else the AlbumArtist name alone.
    var albumArtistRefs: [ArtistRef] {
        if let albumArtists, !albumArtists.isEmpty {
            return albumArtists.compactMap(Self.ref)
        }
        if let albumArtist, !albumArtist.isEmpty { return [ArtistRef(id: nil, name: albumArtist)] }
        return []
    }

    private static func ref(_ pair: JellyfinNameID) -> ArtistRef? {
        guard let name = pair.name, !name.isEmpty else { return nil }
        let id = pair.id.flatMap { $0.isEmpty ? nil : $0 }
        return ArtistRef(id: id, name: name)
    }

    var cleanGenres: [String] {
        (genres ?? []).filter { !$0.isEmpty }
    }

    func asTrack() -> Track? {
        guard let id = itemID else { return nil }
        return Track(
            id: id,
            name: name ?? "",
            albumID: albumID.flatMap { $0.isEmpty ? nil : $0 },
            albumName: album,
            artists: artistRefs,
            albumArtist: albumArtistRefs.first,
            genres: cleanGenres,
            year: year,
            trackNumber: indexNumber,
            discNumber: parentIndexNumber,
            duration: JellyfinTicks.seconds(runTimeTicks) ?? 0,
            imageTag: imageTags?["Primary"],
            albumImageTag: albumPrimaryImageTag,
            isFavorite: userData?.isFavorite ?? false,
            playCount: userData?.playCount ?? 0,
            lastPlayed: userData?.lastPlayedDate.flatMap(JellyfinDate.parse),
            dateAdded: dateCreated.flatMap(JellyfinDate.parse),
            normalizationGain: normalizationGain,
            playlistEntryID: playlistItemID.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func asAlbum() -> Album? {
        guard let id = itemID else { return nil }
        let albumArtists = albumArtistRefs
        return Album(
            id: id,
            name: name ?? "",
            artists: albumArtists.isEmpty ? artistRefs : albumArtists,
            year: year,
            genres: cleanGenres,
            imageTag: primaryImageTagOrNil,
            trackCount: childCount ?? songCount,
            duration: JellyfinTicks.seconds(cumulativeRunTimeTicks ?? runTimeTicks),
            isFavorite: userData?.isFavorite ?? false,
            dateAdded: dateCreated.flatMap(JellyfinDate.parse),
            playCount: userData?.playCount ?? 0,
            lastPlayed: userData?.lastPlayedDate.flatMap(JellyfinDate.parse)
        )
    }

    func asArtist() -> Artist? {
        guard let id = itemID else { return nil }
        let overview = overview.flatMap { $0.isEmpty ? nil : $0 }
        return Artist(
            id: id,
            name: name ?? "",
            imageTag: primaryImageTagOrNil,
            genres: cleanGenres,
            isFavorite: userData?.isFavorite ?? false,
            albumCount: albumCount,
            songCount: songCount,
            overview: overview
        )
    }

    func asPlaylist() -> Playlist? {
        guard let id = itemID else { return nil }
        return Playlist(
            id: id,
            name: name ?? "",
            imageTag: primaryImageTagOrNil,
            trackCount: childCount,
            duration: JellyfinTicks.seconds(cumulativeRunTimeTicks ?? runTimeTicks),
            dateAdded: dateCreated.flatMap(JellyfinDate.parse)
        )
    }

    func asGenre() -> Genre? {
        guard let id = itemID else { return nil }
        return Genre(
            id: id,
            name: name ?? "",
            imageTag: primaryImageTagOrNil,
            songCount: songCount,
            albumCount: albumCount
        )
    }
}

extension JellyfinLyrics {
    /// Nil when there are no lines: the same as no lyrics.
    func asLyrics() -> Lyrics? {
        let lines = (lyrics ?? []).map {
            Lyrics.Line(start: JellyfinTicks.seconds($0.start), text: $0.text ?? "")
        }
        guard !lines.isEmpty else { return nil }
        if metadata?.isSynced == false {
            return Lyrics(lines: lines.map { Lyrics.Line(start: nil, text: $0.text) })
        }
        // Unsynced lyrics have no Start, or (some providers) 0 on every line:
        // a 0 on every line is no timing at all.
        if lines.count > 1, lines.allSatisfy({ ($0.start ?? 0) == 0 }) {
            return Lyrics(lines: lines.map { Lyrics.Line(start: nil, text: $0.text) })
        }
        return Lyrics(lines: lines)
    }
}
