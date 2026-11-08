// CONTRACT — the public surface the app builds on. The bodies are the
// kit agent's to write (see docs/ARCHITECTURE.md); the signatures do not
// change without changing every caller.
//
// One client per signed-in session: the server, the device and, once
// signed in, the token and the user. Immutable and Sendable, so any task
// can use it. Every call goes through `transport`, so the tests can answer
// for the server and dev/kit-test.sh can point it at a real one.
//
// Routes are Jellyfin 10.9+'s (`/Items?userId=`, `/UserFavoriteItems/{id}`);
// where a 10.8 server only has the older route, the client falls back to it
// on a 404. Checked on 12.4 (the test server): every route used here
// answers; the older /Users/{id}/Items and /Users/{id}/FavoriteItems still
// do too. Only favourites fall back (and Quick Connect's Initiate, a GET on
// 10.8); single items are asked for as /Items?Ids=, a route 10.8 has as
// well. The request plumbing is in JellyfinRequests.swift, Jellyfin's
// shapes and their mapping to the models in JellyfinDTO.swift.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ServerInfo: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var version: String

    public init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}

/// What signing in gives, and all the app keeps to stay signed in.
public struct Credentials: Codable, Sendable, Hashable {
    public var serverURL: URL
    public var serverID: String
    public var serverName: String
    public var userID: String
    public var userName: String
    public var accessToken: String

    public init(serverURL: URL, serverID: String, serverName: String, userID: String,
                userName: String, accessToken: String) {
        self.serverURL = serverURL
        self.serverID = serverID
        self.serverName = serverName
        self.userID = userID
        self.userName = userName
        self.accessToken = accessToken
    }
}

/// Quick Connect: the code the user types into another Jellyfin client that
/// is signed in already, so no password is typed on the phone.
public struct QuickConnectState: Sendable, Hashable {
    public var secret: String
    public var code: String
    public var isAuthenticated: Bool

    public init(secret: String, code: String, isAuthenticated: Bool) {
        self.secret = secret
        self.code = code
        self.isAuthenticated = isAuthenticated
    }
}

/// Who the client says it is, in every request's Authorization header.
public struct ClientIdentity: Sendable, Hashable {
    public var clientName: String
    public var clientVersion: String
    public var deviceName: String
    public var deviceID: String

    public init(clientName: String = "Jukebox", clientVersion: String, deviceName: String, deviceID: String) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.deviceName = deviceName
        self.deviceID = deviceID
    }
}

public enum SortOrder: String, Sendable, Hashable, Codable, CaseIterable {
    case name
    case artist
    case year
    case dateAdded
    case datePlayed
    case playCount
    case random
}

public struct AlbumQuery: Sendable, Hashable {
    public var artistID: ItemID?
    public var genre: String?
    public var searchTerm: String?
    public var favoritesOnly = false
    public var sort: SortOrder = .name
    public var descending = false
    public var start = 0
    public var limit: Int?

    public init(artistID: ItemID? = nil, genre: String? = nil, searchTerm: String? = nil,
                favoritesOnly: Bool = false, sort: SortOrder = .name, descending: Bool = false,
                start: Int = 0, limit: Int? = nil) {
        self.artistID = artistID
        self.genre = genre
        self.searchTerm = searchTerm
        self.favoritesOnly = favoritesOnly
        self.sort = sort
        self.descending = descending
        self.start = start
        self.limit = limit
    }
}

public struct TrackQuery: Sendable, Hashable {
    public var albumID: ItemID?
    public var artistID: ItemID?
    public var genre: String?
    public var ids: [ItemID]?
    public var searchTerm: String?
    public var favoritesOnly = false
    public var sort: SortOrder = .name
    public var descending = false
    public var start = 0
    public var limit: Int?

    public init(albumID: ItemID? = nil, artistID: ItemID? = nil, genre: String? = nil,
                ids: [ItemID]? = nil, searchTerm: String? = nil, favoritesOnly: Bool = false,
                sort: SortOrder = .name, descending: Bool = false, start: Int = 0, limit: Int? = nil) {
        self.albumID = albumID
        self.artistID = artistID
        self.genre = genre
        self.ids = ids
        self.searchTerm = searchTerm
        self.favoritesOnly = favoritesOnly
        self.sort = sort
        self.descending = descending
        self.start = start
        self.limit = limit
    }
}

/// How a track is streamed. `original` sends the file as it is when the
/// player can play it; the others ask Jellyfin to transcode down to that
/// many kilobits a second (AAC), for the mobile network.
public enum StreamQuality: String, Sendable, Hashable, Codable, CaseIterable {
    case original
    case high      // 320 kbit/s
    case normal    // 256 kbit/s
    case low       // 128 kbit/s

    public var maxBitrate: Int? {
        switch self {
        case .original: nil
        case .high: 320_000
        case .normal: 256_000
        case .low: 128_000
        }
    }
}

/// One playback report, so Jellyfin counts plays and shows the session in
/// its dashboard: what plays, where, and whether it is paused.
public struct PlaybackReport: Sendable, Hashable {
    public var trackID: ItemID
    /// Seconds.
    public var position: TimeInterval
    public var isPaused: Bool
    /// One id per play of a track, the same in its start, progress and stop.
    public var playSessionID: String

    public init(trackID: ItemID, position: TimeInterval, isPaused: Bool, playSessionID: String) {
        self.trackID = trackID
        self.position = position
        self.isPaused = isPaused
        self.playSessionID = playSessionID
    }
}

public enum JellyfinError: Error, Sendable, Equatable, LocalizedError {
    case invalidServerAddress
    case notSignedIn
    case unauthorized
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidServerAddress: "That is not a server address."
        case .notSignedIn: "Not signed in."
        case .unauthorized: "The server did not accept the user name or password."
        case .notFound: "The server does not have that."
        case let .server(status, message): message ?? "The server answered with error \(status)."
        case let .decoding(what): "The server's answer could not be read (\(what))."
        case let .transport(what): what
        }
    }
}

public final class JellyfinClient: Sendable {
    public let serverURL: URL
    public let identity: ClientIdentity
    public let accessToken: String?
    public let userID: String?
    public let transport: any HTTPTransport

    public init(serverURL: URL, identity: ClientIdentity, accessToken: String? = nil,
                userID: String? = nil, transport: any HTTPTransport = URLSessionTransport()) {
        self.serverURL = serverURL
        self.identity = identity
        self.accessToken = accessToken
        self.userID = userID
        self.transport = transport
    }

    /// A client for a signed-in session.
    public convenience init(credentials: Credentials, identity: ClientIdentity,
                            transport: any HTTPTransport = URLSessionTransport()) {
        self.init(serverURL: credentials.serverURL, identity: identity,
                  accessToken: credentials.accessToken, userID: credentials.userID, transport: transport)
    }

    /// What a person types as a server ("music.example.com", "192.168.1.5:8096",
    /// "https://jf.example.com/jellyfin/") as a base URL: https:// when no
    /// scheme is given unless it is a bare IP or `.local` host (http then,
    /// Jellyfin's default on a home network), no trailing slash, the path kept
    /// for a server behind a reverse proxy. Nil when it cannot be a URL.
    /// Also http for a name without dots ("nas"), other home suffixes
    /// (".lan", ".fritz.box", …) and port 8096; the web app's own part of a
    /// pasted address ("/web/#/home.html") is cut off (JellyfinAddress.swift).
    public static func normalize(serverAddress: String) -> URL? {
        JellyfinAddress.normalize(serverAddress)
    }

    /// The addresses to try for what a person typed, in order: the
    /// normalized one first; then, when no port was typed, the same host on
    /// http at 8096, Jellyfin's own port ("192.168.1.10" → http://192.168.1.10,
    /// http://192.168.1.10:8096). Not when "https://" was typed: that asked
    /// for TLS, and the fallback would send the password in the clear.
    /// Empty when the address cannot be normalized (JellyfinAddress.swift).
    public static func candidateAddresses(for serverAddress: String) -> [URL] {
        JellyfinAddress.candidates(serverAddress)
    }

    // MARK: Signing in

    /// GET /System/Info/Public — answers without signing in; how the app
    /// knows the address is a Jellyfin server before asking for a password.
    /// An address that answers with something else (a web page, a 404) is
    /// .invalidServerAddress; one that does not answer is .transport.
    public func publicInfo() async throws -> ServerInfo {
        let info: JellyfinPublicInfo
        do {
            info = try await get(JellyfinPublicInfo.self, "/System/Info/Public", timeout: 15)
        } catch JellyfinError.decoding, JellyfinError.notFound {
            throw JellyfinError.invalidServerAddress
        }
        guard let id = info.id, !id.isEmpty else { throw JellyfinError.invalidServerAddress }
        return ServerInfo(id: id, name: info.serverName ?? serverURL.host ?? "Jellyfin", version: info.version ?? "")
    }

    /// POST /Users/AuthenticateByName. A wrong name or password is
    /// .unauthorized (12.4 answers 401 "Error processing request.").
    public func signIn(username: String, password: String) async throws -> Credentials {
        // The sign-in answer has the server's id but not its name (User.ServerName
        // is null on 12.4): ask for both at once.
        async let info = publicInfo()
        let response = try await send("POST", "/Users/AuthenticateByName",
                                      json: JellyfinAuthenticateByName(username: username, password: password))
        let result = try decode(JellyfinAuthResult.self, from: response)
        return try credentials(from: result, info: try? await info)
    }

    /// GET /QuickConnect/Enabled. False on any error: the sign-in screen
    /// then simply does not offer it. (Enabled on the 12.4 test server.)
    public func quickConnectEnabled() async -> Bool {
        guard let response = try? await send("GET", "/QuickConnect/Enabled", timeout: 15) else { return false }
        let text = String(data: response.body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return text == "true"
    }

    /// POST /QuickConnect/Initiate. 10.8 had it as a GET: a POST there is
    /// 405 (12.4 answers a GET with 405 the other way round), so on 404 or
    /// 405 the GET is tried.
    public func quickConnectStart() async throws -> QuickConnectState {
        let response: HTTPResponse
        do {
            response = try await send("POST", "/QuickConnect/Initiate")
        } catch JellyfinError.notFound {
            response = try await send("GET", "/QuickConnect/Initiate")
        } catch JellyfinError.server(status: 405, _) {
            response = try await send("GET", "/QuickConnect/Initiate")
        }
        return try quickConnectState(from: response)
    }

    /// GET /QuickConnect/Connect?secret= — poll every few seconds until
    /// `isAuthenticated`. A secret the server no longer knows (it forgets
    /// them after a few minutes) is .notFound: 12.4 answers 404 "Unknown secret".
    public func quickConnectState(secret: String) async throws -> QuickConnectState {
        let response = try await send("GET", "/QuickConnect/Connect",
                                      query: [URLQueryItem(name: "secret", value: secret)], timeout: 15)
        return try quickConnectState(from: response)
    }

    /// POST /Users/AuthenticateWithQuickConnect, once the state says so.
    public func signIn(quickConnectSecret: String) async throws -> Credentials {
        async let info = publicInfo()
        let response = try await send("POST", "/Users/AuthenticateWithQuickConnect",
                                      json: JellyfinQuickConnectSecret(secret: quickConnectSecret))
        let result = try decode(JellyfinAuthResult.self, from: response)
        return try credentials(from: result, info: try? await info)
    }

    /// POST /Sessions/Logout; errors are ignored, the app forgets the token
    /// either way. (On 12.4 the token answers 401 afterwards.)
    public func signOut() async {
        guard let accessToken, !accessToken.isEmpty else { return }
        _ = try? await send("POST", "/Sessions/Logout", timeout: 10)
    }

    // MARK: The library

    /// Album artists (GET /Artists/AlbumArtists), the list Music's Artists
    /// shows: an artist who is only a guest somewhere is not in it.
    /// By name; with a search term in Jellyfin's own order of relevance.
    public func artists(searchTerm: String? = nil, favoritesOnly: Bool = false,
                        start: Int = 0, limit: Int? = nil) async throws -> Page<Artist> {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery + Self.paging(start: start, limit: limit)
        query.append(URLQueryItem(name: "Fields", value: Self.artistFields))
        if let term = Self.term(searchTerm) {
            query.append(URLQueryItem(name: "SearchTerm", value: term))
        } else {
            query += Self.sortQuery(["SortName"], descending: false)
        }
        if favoritesOnly { query.append(URLQueryItem(name: "IsFavorite", value: "true")) }
        let result = try await items("/Artists/AlbumArtists", query)
        return Self.page(result, start: start) { $0.asArtist() }
    }

    public func artist(id: ItemID) async throws -> Artist {
        guard let artist = try await item(id: id, fields: Self.artistFields)?.asArtist() else {
            throw JellyfinError.notFound
        }
        return artist
    }

    /// GET /Items, IncludeItemTypes=MusicAlbum. `artistID` is the album
    /// artist (AlbumArtistIds): the artist's own albums, not the ones they
    /// are a guest on.
    public func albums(_ query: AlbumQuery) async throws -> Page<Album> {
        let user = try requireUser()
        var q = userQuery(user) + Self.imageQuery + Self.paging(start: query.start, limit: query.limit)
        q += [URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
              URLQueryItem(name: "Recursive", value: "true"),
              URLQueryItem(name: "Fields", value: Self.albumFields)]
        if let artistID = query.artistID { q.append(URLQueryItem(name: "AlbumArtistIds", value: artistID)) }
        if let genre = query.genre { q.append(URLQueryItem(name: "Genres", value: genre)) }
        if query.favoritesOnly { q.append(URLQueryItem(name: "IsFavorite", value: "true")) }
        if let term = Self.term(query.searchTerm) {
            // With a search term Jellyfin orders by relevance whatever the
            // SortBy (measured on 12.4); asking no order keeps it so.
            q.append(URLQueryItem(name: "SearchTerm", value: term))
        } else {
            q += Self.sortQuery(Self.albumSortKeys(query.sort), descending: query.descending)
        }
        let result = try await items("/Items", q)
        return Self.page(result, start: query.start) { $0.asAlbum() }
    }

    public func album(id: ItemID) async throws -> Album {
        guard let album = try await item(id: id, fields: Self.albumFields)?.asAlbum() else {
            throw JellyfinError.notFound
        }
        return album
    }

    /// GET /Items, IncludeItemTypes=Audio. With `albumID` and the default
    /// sort (.name, ascending) the album's own order: disc, then track.
    /// With `ids`, the tracks in the order of `ids` (unless another sort is
    /// asked for), `start` and `limit` counted in `ids`, and ids the server
    /// does not have left out.
    public func tracks(_ query: TrackQuery) async throws -> Page<Track> {
        let user = try requireUser()
        var q = userQuery(user) + Self.imageQuery
        q += [URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
              URLQueryItem(name: "Recursive", value: "true"),
              URLQueryItem(name: "Fields", value: Self.trackFields)]
        if let albumID = query.albumID { q.append(URLQueryItem(name: "ParentId", value: albumID)) }
        if let artistID = query.artistID { q.append(URLQueryItem(name: "ArtistIds", value: artistID)) }
        if let genre = query.genre { q.append(URLQueryItem(name: "Genres", value: genre)) }
        if query.favoritesOnly { q.append(URLQueryItem(name: "IsFavorite", value: "true")) }
        let term = Self.term(query.searchTerm)
        if let term { q.append(URLQueryItem(name: "SearchTerm", value: term)) }
        let defaultSort = query.sort == .name && !query.descending
        if term == nil {
            let keys = query.albumID != nil && defaultSort ? Self.albumOrder : Self.trackSortKeys(query.sort)
            q += Self.sortQuery(keys, descending: query.descending)
        }

        guard let ids = query.ids else {
            let result = try await items("/Items", q + Self.paging(start: query.start, limit: query.limit))
            return Self.page(result, start: query.start) { $0.asTrack() }
        }

        let start = min(max(0, query.start), ids.count)
        let end = query.limit.map { min(ids.count, start + max(0, $0)) } ?? ids.count
        let wanted = Array(ids[start..<end])
        var found: [Track] = []
        for chunk in Self.chunks(wanted, of: Self.idsPerRequest) {
            let result = try await items("/Items", q + [URLQueryItem(name: "Ids", value: chunk.joined(separator: ","))])
            found += (result.items ?? []).compactMap { $0.asTrack() }
        }
        if defaultSort {
            let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            found = wanted.compactMap { byID[$0] }
        }
        return Page(items: found, totalCount: ids.count, startIndex: start)
    }

    /// Every track in the user's music libraries, in pages of `pageSize`,
    /// for the index the radio and the mixes work from. `progress` is told
    /// (done, total) after each page.
    ///
    /// Measured on the 12.4 test server (358 tracks, about 1.26 kB of JSON
    /// each; JellyfinIntegrationTests, 3 runs each, one page at a time /
    /// three at once):
    ///   pageSize 2000 (1 page)   91–131 ms
    ///   pageSize  500 (1 page)   84–143 ms
    ///   pageSize  200 (2 pages) 107–191 ms / 112–152 ms
    ///   pageSize  100 (4 pages) 141–163 ms /  88–153 ms
    ///   pageSize   50 (8 pages) 244–253 ms / 136–158 ms
    ///   pageSize   25 (15 pages) 374–397 ms / 205–238 ms
    /// Each request costs about 25 ms whatever its size, so big pages win,
    /// and asking three at once halves the time when there are many. After
    /// the first page (which says how many there are) up to three are asked
    /// at once. The result is in SortName order, each track once (tracks
    /// with the same SortName may change places between runs).
    public func allTracks(pageSize: Int = 2000,
                          progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [Track] {
        try await allTracks(pageSize: pageSize, concurrentPages: 3, progress: progress)
    }

    /// A track as it is now: its play count and favourite after a change.
    public func track(id: ItemID) async throws -> Track {
        guard let track = try await item(id: id, fields: Self.trackFields)?.asTrack() else {
            throw JellyfinError.notFound
        }
        return track
    }

    /// GET /MusicGenres, by name, with song and album counts.
    public func genres() async throws -> [Genre] {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery + Self.sortQuery(["SortName"], descending: false)
        query.append(URLQueryItem(name: "Fields", value: Self.genreFields))
        let result = try await items("/MusicGenres", query)
        return (result.items ?? []).compactMap { $0.asGenre() }
    }

    /// The user's playlists, by name. GET /Items, IncludeItemTypes=Playlist:
    /// 12.4 has no GET /Playlists (405). Video playlists are left out.
    public func playlists() async throws -> [Playlist] {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery + Self.sortQuery(["SortName"], descending: false)
        query += [URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
                  URLQueryItem(name: "Recursive", value: "true"),
                  URLQueryItem(name: "Fields", value: Self.playlistFields)]
        let result = try await items("/Items", query)
        return (result.items ?? []).filter { $0.mediaType != "Video" }.compactMap { $0.asPlaylist() }
    }

    /// GET /Playlists/{id}/Items: each track with its `playlistEntryID`.
    /// On 12.4 the entry id is the track's own id (see removeFromPlaylist).
    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery
        query.append(URLQueryItem(name: "Fields", value: Self.trackFields))
        let result = try await items("/Playlists/\(Self.segment(playlistID))/Items", query, timeout: 60)
        return (result.items ?? []).filter { $0.type == nil || $0.type == "Audio" }.compactMap { $0.asTrack() }
    }

    /// POST /Playlists; the new playlist's id. The tracks go in the JSON
    /// body, so there is no limit from the URL's length.
    @discardableResult
    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        let user = try requireUser()
        let response = try await send("POST", "/Playlists",
                                      json: JellyfinCreatePlaylist(name: name, ids: trackIDs, userID: user))
        guard let id = try decode(JellyfinCreatedPlaylist.self, from: response).id, !id.isEmpty else {
            throw JellyfinError.decoding("the new playlist has no id")
        }
        return id
    }

    /// POST /Playlists/{id}/Items?ids=, at the end, in order, 100 at a time.
    /// A track already there is added again (12.4 keeps duplicates).
    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        let user = try requireUser()
        for chunk in Self.chunks(trackIDs, of: Self.idsPerRequest) {
            try await send("POST", "/Playlists/\(Self.segment(playlistID))/Items",
                           query: [URLQueryItem(name: "ids", value: chunk.joined(separator: ",")),
                                   URLQueryItem(name: "userId", value: user)])
        }
    }

    /// DELETE /Playlists/{id}/Items?entryIds=. On 12.4 a track's entry id
    /// is its own id, so removing a track that is in the playlist twice
    /// removes both (measured); an entry id the playlist does not have is
    /// ignored (204).
    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        _ = try requireUser()
        for chunk in Self.chunks(entryIDs, of: Self.idsPerRequest) {
            try await send("DELETE", "/Playlists/\(Self.segment(playlistID))/Items",
                           query: [URLQueryItem(name: "entryIds", value: chunk.joined(separator: ","))])
        }
    }

    /// POST /Playlists/{id}/Items/{entryId}/Move/{index}, the index counted
    /// in the playlist as it is before the move. With a track that is there
    /// twice, 12.4 moves the first.
    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        _ = try requireUser()
        try await send("POST", "/Playlists/\(Self.segment(playlistID))/Items/\(Self.segment(entryID))/Move/\(max(0, index))")
    }

    /// DELETE /Items/{id}.
    public func deletePlaylist(id: ItemID) async throws {
        _ = try requireUser()
        try await send("DELETE", "/Items/\(Self.segment(id))")
    }

    /// GET /Items/{id}/Similar for an artist: Jellyfin's own idea of who is
    /// alike (shared genres and tags), when Last.fm is not set up.
    /// On the test server it gives MusicArtist items, and only the ones
    /// sharing the artist's genre string exactly ("Hip-Hop; Nederhop": the
    /// "MC Polder; Lyric Engine" guest credits), since the library does not
    /// split its tags.
    public func similarArtists(artistID: ItemID, limit: Int = 20) async throws -> [Artist] {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery
        query += [URLQueryItem(name: "limit", value: String(max(1, limit))),
                  URLQueryItem(name: "Fields", value: Self.artistFields)]
        let result = try await items("/Items/\(Self.segment(artistID))/Similar", query)
        return (result.items ?? [])
            .filter { $0.type == nil || $0.type == "MusicArtist" }
            .compactMap { $0.asArtist() }
            .filter { $0.id != artistID }
    }

    /// GET /Items/{id}/InstantMix: Jellyfin's mix from any track, album,
    /// artist, playlist or genre id — one of the radio's sources.
    /// Verified on 12.4 for a track, an album, an artist and a genre id
    /// (each 200, `limit` tracks). A track's mix starts with the track
    /// itself; the mix is the seed's genre(s), so on the test library, whose
    /// genres are unsplit strings, it stays inside one artist's genre string.
    public func instantMix(seedID: ItemID, limit: Int = 100) async throws -> [Track] {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery
        query += [URLQueryItem(name: "limit", value: String(max(1, limit))),
                  URLQueryItem(name: "Fields", value: Self.trackFields)]
        let result = try await items("/Items/\(Self.segment(seedID))/InstantMix", query)
        return (result.items ?? []).filter { $0.type == nil || $0.type == "Audio" }.compactMap { $0.asTrack() }
    }

    /// Artists, albums, tracks and playlists matching `term`, `limit` of
    /// each, asked for at once.
    ///
    /// Four requests at once rather than /Search/Hints: Hints was faster on
    /// 12.4 (26–41 ms against 45–141 ms for the four, 9 runs) but its
    /// answers have no artist ids, no favourites or play counts and no
    /// genres, one limit is shared by all kinds, and asked for artists only
    /// it found nothing for "night" where /Artists/AlbumArtists finds
    /// "Nightdrive".
    public func search(_ term: String, limit: Int = 20) async throws -> SearchResults {
        guard let term = Self.term(term) else { return SearchResults() }
        let user = try requireUser()
        async let foundArtists = self.artists(searchTerm: term, limit: limit)
        async let foundAlbums = self.albums(AlbumQuery(searchTerm: term, limit: limit))
        async let foundTracks = self.tracks(TrackQuery(searchTerm: term, limit: limit))
        async let foundPlaylists = self.searchPlaylists(term, limit: limit, user: user)
        return try await SearchResults(artists: foundArtists.items, albums: foundAlbums.items,
                                       tracks: foundTracks.items, playlists: foundPlaylists)
    }

    /// GET /Audio/{id}/Lyrics (10.9+); nil when the track has none (12.4
    /// answers 404). 10.8 had no lyrics, so there is no older route to try.
    public func lyrics(trackID: ItemID) async throws -> Lyrics? {
        _ = try requireUser()
        do {
            let lyrics = try await get(JellyfinLyrics.self, "/Audio/\(Self.segment(trackID))/Lyrics")
            return lyrics.asLyrics()
        } catch JellyfinError.notFound {
            return nil
        }
    }

    /// POST (or DELETE) /UserFavoriteItems/{id}?userId=, and on a 404
    /// 10.8's /Users/{userId}/FavoriteItems/{id}. Both work on 12.4.
    public func setFavorite(_ isFavorite: Bool, itemID: ItemID) async throws {
        let user = try requireUser()
        let id = Self.segment(itemID)
        try await send(isFavorite ? "POST" : "DELETE", "/UserFavoriteItems/\(id)",
                       orOnNotFound: "/Users/\(Self.segment(user))/FavoriteItems/\(id)",
                       query: userQuery(user))
    }

    // MARK: Playing

    /// The universal audio URL (GET /Audio/{id}/universal): the file as it
    /// is when AVPlayer can play its container (MP3, AAC, ALAC, FLAC, WAV),
    /// AAC over HLS when it cannot or when `quality` asks for less. The
    /// token is in the URL (`ApiKey`), since AVPlayer sends no headers.
    ///
    /// Measured on 12.4 (curl, the URL this makes):
    /// - .original: MP3 200 audio/mpeg, FLAC 200 audio/flac, M4A 200
    ///   audio/mp4, the file's own bytes.
    /// - A limit: Jellyfin compares it with the file's container bitrate.
    ///   At .low (128 kbit/s) the MP3 (129 kbit/s with its tags) and the M4A
    ///   (129 kbit/s) came as HLS (200 application/vnd.apple.mpegurl, a
    ///   master playlist whose media playlist and .ts segments load, AAC
    ///   44.1 kHz), the FLAC (105 kbit/s, a sine tone) as the file itself.
    ///   At 64 kbit/s all three were HLS; a segment measured 66 kbit/s.
    /// - `api_key` is refused on 12.4 (401); `ApiKey` works, and is what
    ///   10.8–10.10 read first too.
    public func streamURL(trackID: ItemID, quality: StreamQuality, playSessionID: String) -> URL {
        var query = [
            URLQueryItem(name: "UserId", value: userID ?? ""),
            URLQueryItem(name: "DeviceId", value: identity.deviceID),
            URLQueryItem(name: "PlaySessionId", value: playSessionID),
            URLQueryItem(name: "Container", value: Self.directContainers),
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
        ]
        if let bitrate = quality.maxBitrate {
            query.append(URLQueryItem(name: "MaxStreamingBitrate", value: String(bitrate)))
        }
        if let accessToken, !accessToken.isEmpty {
            query.append(URLQueryItem(name: "ApiKey", value: accessToken))
        }
        return url("/Audio/\(Self.segment(trackID))/universal", query)
    }

    /// GET /Items/{id}/Images/Primary, square, `maxPixelSize` on its longer
    /// side, with the tag so it caches for good. Needs no token.
    /// On 12.4: 200 image/jpeg; with a tag "Cache-Control: public,
    /// max-age=31536000, immutable", without one only "public". An item
    /// without the image is 404.
    public func imageURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        let size = String(max(1, maxPixelSize))
        var query = [URLQueryItem(name: "fillWidth", value: size),
                     URLQueryItem(name: "fillHeight", value: size),
                     URLQueryItem(name: "quality", value: "90")]
        if let tag = artwork.tag, !tag.isEmpty { query.append(URLQueryItem(name: "tag", value: tag)) }
        return url("/Items/\(Self.segment(artwork.itemID))/Images/Primary", query)
    }

    /// POST /Sessions/Playing, /Sessions/Playing/Progress and
    /// /Sessions/Playing/Stopped. Errors are swallowed: a missed report must
    /// never stop the music.
    ///
    /// Measured on 12.4 (8 November 2026, tracks of 5–8 s, a fresh track for
    /// each case): Jellyfin counts the play at the START report, whatever
    /// is heard after:
    /// - start alone: PlayCount 0 → 1, LastPlayedDate set, Played true;
    /// - start, then stop at 1 s or at the end: 1 (the stop adds nothing);
    /// - start twice with the same PlaySessionId: 2 — so exactly one start
    ///   per play;
    /// - stop at the end without a start, or progress alone: PlayCount
    ///   stays 0, but Played and LastPlayedDate are set;
    /// - a stop with no PositionTicks counts one more (this client always
    ///   sends one).
    /// So a player that wants a skip not to count must hold the start report
    /// back until enough is heard.
    public func reportStart(_ report: PlaybackReport) async {
        await sendReport("/Sessions/Playing", report)
    }

    public func reportProgress(_ report: PlaybackReport) async {
        await sendReport("/Sessions/Playing/Progress", report)
    }

    public func reportStopped(_ report: PlaybackReport) async {
        await sendReport("/Sessions/Playing/Stopped", report)
    }
}

// MARK: Helpers of the calls above

extension JellyfinClient {
    func sendReport(_ path: String, _ report: PlaybackReport) async {
        guard (try? requireUser()) != nil else { return }
        _ = try? await send("POST", path, json: JellyfinPlaybackInfo(report), timeout: 15)
    }

    func credentials(from result: JellyfinAuthResult, info: ServerInfo?) throws -> Credentials {
        guard let userID = result.user?.id, !userID.isEmpty,
              let token = result.accessToken, !token.isEmpty else {
            throw JellyfinError.decoding("the sign-in answer has no user or token")
        }
        let serverID = [result.serverID, result.user?.serverID, info?.id]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
        return Credentials(serverURL: serverURL, serverID: serverID,
                           serverName: info?.name ?? serverURL.host ?? "Jellyfin",
                           userID: userID, userName: result.user?.name ?? "",
                           accessToken: token)
    }

    func quickConnectState(from response: HTTPResponse) throws -> QuickConnectState {
        let result = try decode(JellyfinQuickConnectResult.self, from: response)
        guard let secret = result.secret, !secret.isEmpty else {
            throw JellyfinError.decoding("the Quick Connect answer has no secret")
        }
        return QuickConnectState(secret: secret, code: result.code ?? "",
                                 isAuthenticated: result.authenticated ?? false)
    }

    /// One item by id with the fields of its kind: GET /Items?userId=&Ids=,
    /// the same answer as a list (10.8 has the route too). Nil when the
    /// server has no such item.
    func item(id: ItemID, fields: String) async throws -> JellyfinItem? {
        let user = try requireUser()
        var query = userQuery(user) + Self.imageQuery
        query += [URLQueryItem(name: "Ids", value: id), URLQueryItem(name: "Fields", value: fields)]
        let result = try await items("/Items", query)
        return result.items?.first { $0.id == id } ?? result.items?.first
    }

    /// Search's playlists: GET /Items, IncludeItemTypes=Playlist, SearchTerm.
    func searchPlaylists(_ term: String, limit: Int, user: String) async throws -> [Playlist] {
        var query = userQuery(user) + Self.imageQuery + Self.paging(start: 0, limit: limit)
        query += [URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
                  URLQueryItem(name: "Recursive", value: "true"),
                  URLQueryItem(name: "SearchTerm", value: term),
                  URLQueryItem(name: "Fields", value: Self.playlistFields)]
        let result = try await items("/Items", query)
        return (result.items ?? []).filter { $0.mediaType != "Video" }.compactMap { $0.asPlaylist() }
    }

    /// allTracks, with how many pages may be asked at once (the tests
    /// measure 1 against 3).
    func allTracks(pageSize: Int, concurrentPages: Int,
                   progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track] {
        let user = try requireUser()
        let size = max(1, pageSize)
        var base = userQuery(user) + Self.imageQuery + Self.sortQuery(["SortName"], descending: false)
        base += [URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                 URLQueryItem(name: "Recursive", value: "true"),
                 URLQueryItem(name: "Fields", value: Self.trackFields)]
        let query = base

        // A page of 2000 is about 2.5 MB: more time than a list call.
        let first = try await items("/Items", query + Self.paging(start: 0, limit: size), timeout: 120)
        let firstTracks = (first.items ?? []).compactMap { $0.asTrack() }
        let total = max(first.totalRecordCount ?? firstTracks.count, firstTracks.count)
        var done = firstTracks.count
        progress?(done, total)

        var pages: [Int: [Track]] = [0: firstTracks]
        let starts = Array(stride(from: size, to: total, by: size))
        if !starts.isEmpty {
            let page = { @Sendable (start: Int) async throws -> (Int, [Track]) in
                let result = try await self.items("/Items", query + Self.paging(start: start, limit: size),
                                                  timeout: 120)
                return (start, (result.items ?? []).compactMap { $0.asTrack() })
            }
            try await withThrowingTaskGroup(of: (Int, [Track]).self) { group in
                var next = starts.makeIterator()
                for _ in 0..<max(1, concurrentPages) {
                    guard let start = next.next() else { break }
                    group.addTask { try await page(start) }
                }
                while let result = try await group.next() {
                    pages[result.0] = result.1
                    done += result.1.count
                    progress?(min(done, total), total)
                    if let start = next.next() { group.addTask { try await page(start) } }
                }
            }
        }

        // In page order, each track once: a library that changes while it is
        // read (a scan) can shift a track from one page into the next.
        var seen = Set<ItemID>()
        var tracks: [Track] = []
        tracks.reserveCapacity(total)
        for start in pages.keys.sorted() {
            for track in pages[start] ?? [] where seen.insert(track.id).inserted {
                tracks.append(track)
            }
        }
        return tracks
    }

    /// A search term worth sending: trimmed, not empty.
    static func term(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func page<T: Sendable>(_ result: JellyfinItemsResult, start: Int,
                                  _ map: (JellyfinItem) -> T?) -> Page<T> {
        let items = (result.items ?? []).compactMap(map)
        return Page(items: items, totalCount: result.totalRecordCount ?? items.count,
                    startIndex: result.startIndex ?? start)
    }
}
