// What a Subsonic server sends, as the API spells it (Child, AlbumID3,
// ArtistID3, Playlist, Genre and the OpenSubsonic additions), and the one
// place it becomes Jukebox's own Track, Album, Artist, Playlist and Genre
// (Library/Models.swift). Nothing above SubsonicClient reads these.
//
// Read leniently, on purpose, as JellyfinDTO is: many servers speak this
// API, each a little differently, and one odd field must cost that field,
// not the page of 358 (or 50 000) songs it came in. So every field is
// optional, and read with the `lenient…` helpers below: an id may come as
// a number (Ampache and older Airsonic send numbers, the spec says
// strings), a duration as 5.0, a flag as "true"; a field of a type nobody
// expected is nil. A list may be missing, empty (Navidrome answers
// `"playlists": {}` when there are none, measured), or a single object
// where an array belongs (the original Subsonic's JSON did that with
// one-element lists); an element that is not an object is skipped.
//
// Seen on Navidrome 0.64.2 (the test server, 8 November 2026):
// - Dates have nine fractional digits ("2026-11-08T10:14:28.62878675Z"),
//   read by JellyfinDate, which takes any number.
// - `artists`, `albumArtists` and `genres` (OpenSubsonic) are split from
//   joined tags; `artist`, `genre` are the first or the joined string.
// - `playCount` and `played` are absent before the first play; `starred`
//   is a date, absent when not a favourite; `replayGain` is {} for files
//   without the tags.
// - A song's `coverArt` is its disc's ("dc-<albumId>:1"), an album's
//   "al-<id>_<hash>", a playlist's "pl-<id>"; artists without an image
//   have none.

import Foundation

// MARK: - Reading leniently

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let text = try? decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? decodeIfPresent(Int64.self, forKey: key) { return String(number) }
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number }
        if let number = try? decodeIfPresent(Double.self, forKey: key), number.isFinite, abs(number) < 1e15 {
            return Int(number)
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key), number.isFinite { return number }
        if let text = try? decodeIfPresent(String.self, forKey: key),
           let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite { return number }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return flag }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return number != 0 }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            switch text.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    /// An object of its own (a payload, `replayGain`), nil when absent or
    /// not one.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }

    /// A list: an array, or a single object; elements that cannot be read
    /// are left out.
    func lenientList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        lenient(SubsonicList<T>.self, key)?.items ?? []
    }

    /// A list of names, as strings ("genres": ["Rock"]) or as objects
    /// ({"name": "Rock"}).
    func lenientNames(_ key: Key) -> [String] {
        lenientList(SubsonicName.self, key).compactMap(\.name).filter { !$0.isEmpty }
    }
}

/// Any coding key, for objects read by name.
struct SubsonicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Reads anything and keeps nothing: how an element that is not what was
/// expected is stepped over in an array (a failed decode does not move an
/// unkeyed container on, so the element must be read as something).
private struct SubsonicSkip: Decodable {
    init(from decoder: any Decoder) throws {}
}

/// An array whose unreadable elements are left out, or a single object.
struct SubsonicList<T: Decodable>: Decodable {
    var items: [T]

    init(from decoder: any Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var items: [T] = []
            items.reserveCapacity(array.count ?? 0)
            while !array.isAtEnd {
                if let item = try? array.decode(T.self) {
                    items.append(item)
                } else {
                    _ = try array.decode(SubsonicSkip.self)
                }
            }
            self.items = items
        } else if let one = try? T(from: decoder) {
            items = [one]
        } else {
            items = []
        }
    }
}

/// `{"name": …}` or a bare string.
struct SubsonicName: Decodable {
    var name: String?

    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            name = text
        } else {
            let c = try decoder.container(keyedBy: SubsonicKey.self)
            name = c.lenientString(SubsonicKey("name")) ?? c.lenientString(SubsonicKey("value"))
        }
    }
}

/// An artist as a song or an album names it (OpenSubsonic's ArtistID3 in
/// `artists`, `albumArtists`).
struct SubsonicNameID: Decodable {
    var id: String?
    var name: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        id = c.lenientString(SubsonicKey("id"))
        name = c.lenientString(SubsonicKey("name"))
    }

    var ref: ArtistRef? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return ArtistRef(id: id.flatMap { $0.isEmpty ? nil : $0 }, name: name)
    }
}

// MARK: - The answer

/// `{"subsonic-response": {…}}`, HTTP 200 even for errors (measured on
/// Navidrome: an unknown song is 200 with error 70).
struct SubsonicEnvelope: Decodable {
    var body: SubsonicBody

    enum CodingKeys: String, CodingKey {
        case body = "subsonic-response"
    }
}

/// Everything an answer may hold: the status every answer has, and each
/// call's own part under its own name, nil when absent. One type for all
/// calls, as only the keys present are read.
struct SubsonicBody: Decodable {
    var status: String?
    var version: String?
    /// OpenSubsonic: "navidrome", "gonic", …
    var type: String?
    var serverVersion: String?
    var openSubsonic: Bool?
    var error: SubsonicErrorDTO?

    var searchResult3: SubsonicSearchResult?
    var albumList2: SubsonicAlbumList?
    var artists: SubsonicArtistIndexes?
    var playlists: SubsonicPlaylists?
    var playlist: SubsonicPlaylist?
    var genres: SubsonicGenres?
    var song: SubsonicChild?
    var album: SubsonicAlbum?
    var artist: SubsonicArtist?
    var artistInfo2: SubsonicArtistInfo?
    var songs: SubsonicSongs?
    var lyricsList: SubsonicLyricsList?
    var lyrics: SubsonicPlainLyrics?
    var user: SubsonicUser?
    var tokenInfo: SubsonicTokenInfo?
    var openSubsonicExtensions: [SubsonicExtension]
    var scanStatus: SubsonicScanStatus?

    var isOK: Bool { status?.lowercased() == "ok" }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        func key(_ name: String) -> SubsonicKey { SubsonicKey(name) }
        status = c.lenientString(key("status"))
        version = c.lenientString(key("version"))
        type = c.lenientString(key("type"))
        serverVersion = c.lenientString(key("serverVersion"))
        openSubsonic = c.lenientBool(key("openSubsonic"))
        error = c.lenient(SubsonicErrorDTO.self, key("error"))
        searchResult3 = c.lenient(SubsonicSearchResult.self, key("searchResult3"))
        albumList2 = c.lenient(SubsonicAlbumList.self, key("albumList2"))
        artists = c.lenient(SubsonicArtistIndexes.self, key("artists"))
        playlists = c.lenient(SubsonicPlaylists.self, key("playlists"))
        playlist = c.lenient(SubsonicPlaylist.self, key("playlist"))
        genres = c.lenient(SubsonicGenres.self, key("genres"))
        song = c.lenient(SubsonicChild.self, key("song"))
        album = c.lenient(SubsonicAlbum.self, key("album"))
        artist = c.lenient(SubsonicArtist.self, key("artist"))
        artistInfo2 = c.lenient(SubsonicArtistInfo.self, key("artistInfo2"))
        // The song lists of the mixes, each under its own name.
        songs = ["similarSongs", "similarSongs2", "randomSongs", "topSongs", "songsByGenre", "starred2"]
            .lazy.compactMap { c.lenient(SubsonicSongs.self, key($0)) }.first
        lyricsList = c.lenient(SubsonicLyricsList.self, key("lyricsList"))
        lyrics = c.lenient(SubsonicPlainLyrics.self, key("lyrics"))
        user = c.lenient(SubsonicUser.self, key("user"))
        tokenInfo = c.lenient(SubsonicTokenInfo.self, key("tokenInfo"))
        openSubsonicExtensions = c.lenientList(SubsonicExtension.self, key("openSubsonicExtensions"))
        scanStatus = c.lenient(SubsonicScanStatus.self, key("scanStatus"))
    }
}

struct SubsonicErrorDTO: Decodable {
    var code: Int?
    var message: String?
    /// OpenSubsonic: where to read how to fix it (an API key's settings page).
    var helpURL: URL?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        code = c.lenientInt(SubsonicKey("code"))
        message = c.lenientString(SubsonicKey("message"))
        helpURL = c.lenientString(SubsonicKey("helpUrl")).flatMap(URL.init(string:))
    }
}

struct SubsonicExtension: Decodable {
    var name: String?
    var versions: [Int]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        name = c.lenientString(SubsonicKey("name"))
        versions = c.lenient([Int].self, SubsonicKey("versions")) ?? []
    }
}

struct SubsonicUser: Decodable {
    var username: String?
    var streamRole: Bool?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        username = c.lenientString(SubsonicKey("username"))
        streamRole = c.lenientBool(SubsonicKey("streamRole"))
    }
}

struct SubsonicTokenInfo: Decodable {
    var username: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        username = c.lenientString(SubsonicKey("username"))
    }
}

struct SubsonicScanStatus: Decodable {
    var scanning: Bool?
    var count: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        scanning = c.lenientBool(SubsonicKey("scanning"))
        count = c.lenientInt(SubsonicKey("count"))
    }
}

// MARK: - Songs, albums, artists

/// A song: Subsonic's Child, with OpenSubsonic's additions.
struct SubsonicChild: Decodable {
    var id: String?
    var isDir: Bool?
    /// "music", "podcast", "audiobook", "video".
    var type: String?
    var title: String?
    var album: String?
    var albumID: String?
    var artist: String?
    var artistID: String?
    var artists: [SubsonicNameID]
    var albumArtists: [SubsonicNameID]
    var genre: String?
    var genres: [String]
    var year: Int?
    var track: Int?
    var discNumber: Int?
    /// Whole seconds.
    var duration: Double?
    var coverArt: String?
    var starred: String?
    var playCount: Int?
    var played: String?
    var created: String?
    var suffix: String?
    var trackGain: Double?
    var albumGain: Double?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        func key(_ name: String) -> SubsonicKey { SubsonicKey(name) }
        id = c.lenientString(key("id"))
        isDir = c.lenientBool(key("isDir"))
        type = c.lenientString(key("type"))
        title = c.lenientString(key("title")) ?? c.lenientString(key("name"))
        album = c.lenientString(key("album"))
        albumID = c.lenientString(key("albumId"))
        artist = c.lenientString(key("artist"))
        artistID = c.lenientString(key("artistId"))
        artists = c.lenientList(SubsonicNameID.self, key("artists"))
        albumArtists = c.lenientList(SubsonicNameID.self, key("albumArtists"))
        genre = c.lenientString(key("genre"))
        genres = c.lenientNames(key("genres"))
        year = c.lenientInt(key("year"))
        track = c.lenientInt(key("track"))
        discNumber = c.lenientInt(key("discNumber"))
        duration = c.lenientDouble(key("duration"))
        coverArt = c.lenientString(key("coverArt"))
        starred = c.lenientString(key("starred"))
        playCount = c.lenientInt(key("playCount"))
        played = c.lenientString(key("played"))
        created = c.lenientString(key("created"))
        suffix = c.lenientString(key("suffix"))
        let gain = c.lenient(SubsonicReplayGain.self, key("replayGain"))
        trackGain = gain?.trackGain
        albumGain = gain?.albumGain
    }
}

/// OpenSubsonic's `replayGain`, in dB.
struct SubsonicReplayGain: Decodable {
    var trackGain: Double?
    var albumGain: Double?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        trackGain = c.lenientDouble(SubsonicKey("trackGain"))
        albumGain = c.lenientDouble(SubsonicKey("albumGain"))
    }
}

/// An album: AlbumID3, and in getAlbum its songs.
struct SubsonicAlbum: Decodable {
    var id: String?
    var name: String?
    var artist: String?
    var artistID: String?
    var artists: [SubsonicNameID]
    var coverArt: String?
    var songCount: Int?
    var duration: Double?
    var created: String?
    var year: Int?
    var genre: String?
    var genres: [String]
    var starred: String?
    var playCount: Int?
    var played: String?
    var song: [SubsonicChild]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        func key(_ name: String) -> SubsonicKey { SubsonicKey(name) }
        id = c.lenientString(key("id"))
        // getAlbumList (not ID3) calls it `title`; AlbumID3 `name`.
        name = c.lenientString(key("name")) ?? c.lenientString(key("title")) ?? c.lenientString(key("album"))
        artist = c.lenientString(key("artist"))
        artistID = c.lenientString(key("artistId"))
        artists = c.lenientList(SubsonicNameID.self, key("artists"))
        coverArt = c.lenientString(key("coverArt"))
        songCount = c.lenientInt(key("songCount"))
        duration = c.lenientDouble(key("duration"))
        created = c.lenientString(key("created"))
        year = c.lenientInt(key("year"))
        genre = c.lenientString(key("genre"))
        genres = c.lenientNames(key("genres"))
        starred = c.lenientString(key("starred"))
        playCount = c.lenientInt(key("playCount"))
        played = c.lenientString(key("played"))
        song = c.lenientList(SubsonicChild.self, key("song"))
    }
}

/// An artist: ArtistID3, and in getArtist its albums.
struct SubsonicArtist: Decodable {
    var id: String?
    var name: String?
    var coverArt: String?
    var albumCount: Int?
    var starred: String?
    /// OpenSubsonic: "albumartist", "artist", "composer", … (Navidrome's
    /// getArtists: ["albumartist", "artist", "maincredit"], measured).
    var roles: [String]
    var album: [SubsonicAlbum]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        func key(_ name: String) -> SubsonicKey { SubsonicKey(name) }
        id = c.lenientString(key("id"))
        name = c.lenientString(key("name"))
        coverArt = c.lenientString(key("coverArt"))
        albumCount = c.lenientInt(key("albumCount"))
        starred = c.lenientString(key("starred"))
        roles = c.lenientNames(key("roles"))
        album = c.lenientList(SubsonicAlbum.self, key("album"))
    }
}

struct SubsonicSearchResult: Decodable {
    var artist: [SubsonicArtist]
    var album: [SubsonicAlbum]
    var song: [SubsonicChild]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        artist = c.lenientList(SubsonicArtist.self, SubsonicKey("artist"))
        album = c.lenientList(SubsonicAlbum.self, SubsonicKey("album"))
        song = c.lenientList(SubsonicChild.self, SubsonicKey("song"))
    }
}

struct SubsonicAlbumList: Decodable {
    var album: [SubsonicAlbum]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        album = c.lenientList(SubsonicAlbum.self, SubsonicKey("album"))
    }
}

/// getArtists: `index[].artist[]`, by first letter.
struct SubsonicArtistIndexes: Decodable {
    var artists: [SubsonicArtist]

    private struct Index: Decodable {
        var artist: [SubsonicArtist]

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: SubsonicKey.self)
            artist = c.lenientList(SubsonicArtist.self, SubsonicKey("artist"))
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        artists = c.lenientList(Index.self, SubsonicKey("index")).flatMap(\.artist)
    }
}

struct SubsonicSongs: Decodable {
    var song: [SubsonicChild]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        song = c.lenientList(SubsonicChild.self, SubsonicKey("song"))
    }
}

struct SubsonicArtistInfo: Decodable {
    var similarArtist: [SubsonicArtist]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        similarArtist = c.lenientList(SubsonicArtist.self, SubsonicKey("similarArtist"))
    }
}

// MARK: - Playlists and genres

struct SubsonicPlaylist: Decodable {
    var id: String?
    var name: String?
    var owner: String?
    var songCount: Int?
    var duration: Double?
    var created: String?
    var coverArt: String?
    /// OpenSubsonic.
    var readonly: Bool?
    var entry: [SubsonicChild]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        func key(_ name: String) -> SubsonicKey { SubsonicKey(name) }
        id = c.lenientString(key("id"))
        name = c.lenientString(key("name"))
        owner = c.lenientString(key("owner"))
        songCount = c.lenientInt(key("songCount"))
        duration = c.lenientDouble(key("duration"))
        created = c.lenientString(key("created"))
        coverArt = c.lenientString(key("coverArt"))
        readonly = c.lenientBool(key("readonly"))
        entry = c.lenientList(SubsonicChild.self, key("entry"))
    }
}

struct SubsonicPlaylists: Decodable {
    var playlist: [SubsonicPlaylist]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        playlist = c.lenientList(SubsonicPlaylist.self, SubsonicKey("playlist"))
    }
}

struct SubsonicGenre: Decodable {
    var value: String?
    var songCount: Int?
    var albumCount: Int?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        value = c.lenientString(SubsonicKey("value")) ?? c.lenientString(SubsonicKey("name"))
        songCount = c.lenientInt(SubsonicKey("songCount"))
        albumCount = c.lenientInt(SubsonicKey("albumCount"))
    }
}

struct SubsonicGenres: Decodable {
    var genre: [SubsonicGenre]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        genre = c.lenientList(SubsonicGenre.self, SubsonicKey("genre"))
    }
}

// MARK: - Lyrics

/// OpenSubsonic's getLyricsBySongId (`songLyrics`).
struct SubsonicLyricsList: Decodable {
    var structuredLyrics: [Structured]

    struct Structured: Decodable {
        var synced: Bool?
        /// Milliseconds; positive: the lines come sooner.
        var offset: Double?
        var line: [Line]

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: SubsonicKey.self)
            synced = c.lenientBool(SubsonicKey("synced"))
            offset = c.lenientDouble(SubsonicKey("offset"))
            line = c.lenientList(Line.self, SubsonicKey("line"))
        }
    }

    struct Line: Decodable {
        /// Milliseconds, synced lyrics only.
        var start: Double?
        var value: String?

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: SubsonicKey.self)
            start = c.lenientDouble(SubsonicKey("start"))
            value = c.lenientString(SubsonicKey("value"))
        }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        structuredLyrics = c.lenientList(Structured.self, SubsonicKey("structuredLyrics"))
    }
}

/// The classic getLyrics: plain text.
struct SubsonicPlainLyrics: Decodable {
    var value: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        value = c.lenientString(SubsonicKey("value"))
    }
}

// MARK: - To the models

extension SubsonicChild {
    /// Nil for what is not a song: a folder, a video, or no id.
    func asTrack() -> Track? {
        guard let id, !id.isEmpty, isDir != true, type?.lowercased() != "video" else { return nil }
        var performers = artists.compactMap(\.ref)
        if performers.isEmpty, let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            performers = [ArtistRef(id: artistID.flatMap { $0.isEmpty ? nil : $0 }, name: artist)]
        }
        return Track(
            id: id,
            name: title ?? "",
            albumID: albumID.flatMap { $0.isEmpty ? nil : $0 },
            albumName: album,
            artists: performers,
            albumArtist: albumArtists.lazy.compactMap(\.ref).first,
            genres: Subsonic.genres(genres, genre),
            year: year.flatMap { $0 > 0 ? $0 : nil },
            trackNumber: track.flatMap { $0 > 0 ? $0 : nil },
            discNumber: discNumber.flatMap { $0 > 0 ? $0 : nil },
            duration: max(0, duration ?? 0),
            imageTag: coverArt.flatMap { $0.isEmpty ? nil : $0 },
            albumImageTag: nil,
            isFavorite: starred.map { !$0.isEmpty } ?? false,
            playCount: max(0, playCount ?? 0),
            lastPlayed: played.flatMap(JellyfinDate.parse),
            dateAdded: created.flatMap(JellyfinDate.parse),
            // The same reference as Jellyfin's NormalizationGain (ReplayGain
            // 2.0's −18 LUFS); a file with only an album gain plays at that.
            normalizationGain: trackGain ?? albumGain,
            playlistEntryID: nil,
            container: suffix.flatMap { $0.isEmpty ? nil : $0.lowercased() })
    }
}

extension SubsonicAlbum {
    func asAlbum() -> Album? {
        guard let id, !id.isEmpty else { return nil }
        return Album(
            id: id,
            name: name ?? "",
            artists: Subsonic.artists(artists, artist, artistID),
            year: year.flatMap { $0 > 0 ? $0 : nil },
            genres: Subsonic.genres(genres, genre),
            imageTag: coverArt.flatMap { $0.isEmpty ? nil : $0 },
            trackCount: songCount,
            duration: duration,
            isFavorite: starred.map { !$0.isEmpty } ?? false,
            dateAdded: created.flatMap(JellyfinDate.parse),
            playCount: max(0, playCount ?? 0),
            lastPlayed: played.flatMap(JellyfinDate.parse))
    }

    /// Who the album is by, for a song that does not say its album artist
    /// (a server without OpenSubsonic's `albumArtists`).
    var albumArtist: ArtistRef? { Subsonic.artists(artists, artist, artistID).first }
}

extension SubsonicArtist {
    func asArtist() -> Artist? {
        guard let id, !id.isEmpty, let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return Artist(id: id, name: name, imageTag: coverArt.flatMap { $0.isEmpty ? nil : $0 },
                      isFavorite: starred.map { !$0.isEmpty } ?? false, albumCount: albumCount)
    }
}

extension SubsonicPlaylist {
    /// `user`: who is signed in, for a server without `readonly`: a
    /// playlist someone else owns cannot be changed (error 50).
    func asPlaylist(user: String) -> Playlist? {
        guard let id, !id.isEmpty else { return nil }
        let othersOwn = owner.map { !$0.isEmpty && $0.lowercased() != user.lowercased() } ?? false
        return Playlist(id: id, name: name ?? "", imageTag: coverArt.flatMap { $0.isEmpty ? nil : $0 },
                        trackCount: songCount, duration: duration,
                        dateAdded: created.flatMap(JellyfinDate.parse),
                        isReadOnly: readonly ?? othersOwn)
    }
}

extension SubsonicGenre {
    /// Subsonic genres have no id: the name is the id (getRandomSongs and
    /// getSongsByGenre take the name).
    func asGenre() -> Genre? {
        guard let name = value?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return Genre(id: name, name: name, songCount: songCount, albumCount: albumCount)
    }
}

extension SubsonicLyricsList {
    /// The synced lyrics if there are any, else the first; nil when there
    /// are none or every line is empty. A synced line starts at
    /// (start − offset) / 1000 s: OpenSubsonic's offset is how much sooner.
    func asLyrics() -> Lyrics? {
        let usable = structuredLyrics.filter { $0.line.contains { !($0.value ?? "").isEmpty } }
        guard let chosen = usable.first(where: { $0.synced == true && $0.line.contains { $0.start != nil } })
            ?? usable.first else { return nil }
        let synced = chosen.synced == true
        let offset = chosen.offset ?? 0
        let lines = chosen.line.map { line in
            Lyrics.Line(start: synced ? line.start.map { max(0, ($0 - offset) / 1000) } : nil,
                        text: line.value ?? "")
        }
        return Lyrics(lines: lines)
    }
}

extension SubsonicPlainLyrics {
    /// The text in lines; nil when empty (Navidrome's `{"value": ""}` for a
    /// song without lyrics, measured).
    func asLyrics() -> Lyrics? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var lines = value.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return Lyrics(lines: lines.map { Lyrics.Line(start: nil, text: $0) })
    }
}

/// Mapping helpers the DTOs share.
enum Subsonic {
    /// OpenSubsonic's `genres` (split by the server), else the one `genre`.
    static func genres(_ list: [String], _ one: String?) -> [String] {
        if !list.isEmpty { return list }
        guard let one = one?.trimmingCharacters(in: .whitespacesAndNewlines), !one.isEmpty else { return [] }
        return [one]
    }

    /// OpenSubsonic's `artists`, else the one `artist` and `artistId`.
    static func artists(_ list: [SubsonicNameID], _ name: String?, _ id: String?) -> [ArtistRef] {
        let refs = list.compactMap(\.ref)
        if !refs.isEmpty { return refs }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return [] }
        return [ArtistRef(id: id.flatMap { $0.isEmpty ? nil : $0 }, name: name)]
    }
}
