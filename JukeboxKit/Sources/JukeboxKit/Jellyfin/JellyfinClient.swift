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
// on a 404.

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
    public static func normalize(serverAddress: String) -> URL? {
        fatalError("JellyfinClient.normalize is not built yet")
    }

    // MARK: Signing in

    /// GET /System/Info/Public — answers without signing in; how the app
    /// knows the address is a Jellyfin server before asking for a password.
    public func publicInfo() async throws -> ServerInfo {
        fatalError("not built yet")
    }

    /// POST /Users/AuthenticateByName.
    public func signIn(username: String, password: String) async throws -> Credentials {
        fatalError("not built yet")
    }

    /// GET /QuickConnect/Enabled.
    public func quickConnectEnabled() async -> Bool {
        fatalError("not built yet")
    }

    /// POST /QuickConnect/Initiate.
    public func quickConnectStart() async throws -> QuickConnectState {
        fatalError("not built yet")
    }

    /// GET /QuickConnect/Connect?secret= — poll every few seconds until
    /// `isAuthenticated`.
    public func quickConnectState(secret: String) async throws -> QuickConnectState {
        fatalError("not built yet")
    }

    /// POST /Users/AuthenticateWithQuickConnect, once the state says so.
    public func signIn(quickConnectSecret: String) async throws -> Credentials {
        fatalError("not built yet")
    }

    /// POST /Sessions/Logout; errors are ignored, the app forgets the token
    /// either way.
    public func signOut() async {
        fatalError("not built yet")
    }

    // MARK: The library

    /// Album artists (GET /Artists/AlbumArtists), the list Music's Artists
    /// shows: an artist who is only a guest somewhere is not in it.
    public func artists(searchTerm: String? = nil, favoritesOnly: Bool = false,
                        start: Int = 0, limit: Int? = nil) async throws -> Page<Artist> {
        fatalError("not built yet")
    }

    public func artist(id: ItemID) async throws -> Artist {
        fatalError("not built yet")
    }

    public func albums(_ query: AlbumQuery) async throws -> Page<Album> {
        fatalError("not built yet")
    }

    public func album(id: ItemID) async throws -> Album {
        fatalError("not built yet")
    }

    public func tracks(_ query: TrackQuery) async throws -> Page<Track> {
        fatalError("not built yet")
    }

    /// Every track in the user's music libraries, in pages of `pageSize`,
    /// for the index the radio and the mixes work from. `progress` is told
    /// (done, total) after each page.
    public func allTracks(pageSize: Int = 2000,
                          progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [Track] {
        fatalError("not built yet")
    }

    /// A track as it is now: its play count and favourite after a change.
    public func track(id: ItemID) async throws -> Track {
        fatalError("not built yet")
    }

    public func genres() async throws -> [Genre] {
        fatalError("not built yet")
    }

    public func playlists() async throws -> [Playlist] {
        fatalError("not built yet")
    }

    /// GET /Playlists/{id}/Items: each track with its `playlistEntryID`.
    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        fatalError("not built yet")
    }

    /// POST /Playlists; the new playlist's id.
    @discardableResult
    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        fatalError("not built yet")
    }

    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        fatalError("not built yet")
    }

    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        fatalError("not built yet")
    }

    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        fatalError("not built yet")
    }

    /// DELETE /Items/{id}.
    public func deletePlaylist(id: ItemID) async throws {
        fatalError("not built yet")
    }

    /// GET /Items/{id}/Similar for an artist: Jellyfin's own idea of who is
    /// alike (shared genres and tags), when Last.fm is not set up.
    public func similarArtists(artistID: ItemID, limit: Int = 20) async throws -> [Artist] {
        fatalError("not built yet")
    }

    /// GET /Items/{id}/InstantMix: Jellyfin's mix from any track, album,
    /// artist, playlist or genre id — one of the radio's sources.
    public func instantMix(seedID: ItemID, limit: Int = 100) async throws -> [Track] {
        fatalError("not built yet")
    }

    /// Artists, albums, tracks and playlists matching `term`, `limit` of
    /// each, asked for at once.
    public func search(_ term: String, limit: Int = 20) async throws -> SearchResults {
        fatalError("not built yet")
    }

    /// GET /Audio/{id}/Lyrics (10.9+); nil when the track has none.
    public func lyrics(trackID: ItemID) async throws -> Lyrics? {
        fatalError("not built yet")
    }

    public func setFavorite(_ isFavorite: Bool, itemID: ItemID) async throws {
        fatalError("not built yet")
    }

    // MARK: Playing

    /// The universal audio URL (GET /Audio/{id}/universal): the file as it
    /// is when AVPlayer can play its container (MP3, AAC, ALAC, FLAC, WAV),
    /// AAC over HLS when it cannot or when `quality` asks for less. The
    /// token is in the URL (`api_key`), since AVPlayer sends no headers.
    public func streamURL(trackID: ItemID, quality: StreamQuality, playSessionID: String) -> URL {
        fatalError("not built yet")
    }

    /// GET /Items/{id}/Images/Primary, square, `maxPixelSize` on its longer
    /// side, with the tag so it caches for good. Needs no token.
    public func imageURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        fatalError("not built yet")
    }

    /// POST /Sessions/Playing, /Sessions/Playing/Progress and
    /// /Sessions/Playing/Stopped. Jellyfin counts a play at the stop report
    /// when enough was heard. Errors are swallowed: a missed report must
    /// never stop the music.
    public func reportStart(_ report: PlaybackReport) async {
        fatalError("not built yet")
    }

    public func reportProgress(_ report: PlaybackReport) async {
        fatalError("not built yet")
    }

    public func reportStopped(_ report: PlaybackReport) async {
        fatalError("not built yet")
    }
}
