// CONTRACT — the server-neutral layer the app moves to in the next round
// (docs/SERVERS.md has the design, the map from each member to Jellyfin's
// and Subsonic's calls, and the measurements behind it). The value types
// here are complete; the factory's bodies (`MusicServers`) and the two
// servers (JellyfinServer, wrapping JellyfinClient, and SubsonicServer) are
// the next round's to write. The signatures do not change without changing
// every caller.
//
// The photographer, 8 November 2026: "Moet eigenlijk ook voor navidrome en
// die ander" — Jukebox for Navidrome and the other Subsonic servers too, as
// Feishin does, not only Jellyfin.
//
// What is here is what the app uses (docs/SERVERS.md, "What the app asks of
// a server"), not everything a server can do: the app sorts, filters and
// searches its library in memory (LibraryIndex), so there are no general
// queries, only "everything", one item, and the few calls that need the
// server (an album's tracks before the library is in, a playlist's entries,
// the mixes and lyrics only the server has).

import Foundation

// MARK: - What a server is

/// Which Subsonic server answers, from OpenSubsonic's `type` in every
/// answer (Navidrome 0.64.2 says "navidrome", measured). It names the server
/// in Settings and the sign-in screen; what the app may do comes from
/// `ServerCapability`, never from the flavour.
public enum SubsonicFlavour: Hashable, Sendable, Codable {
    case navidrome
    case gonic
    /// Airsonic and Airsonic-Advanced.
    case airsonic
    /// Ampache's Subsonic API.
    case ampache
    /// Lightweight Music Server.
    case lms
    /// No `type`: the original Subsonic, or a server older than OpenSubsonic.
    case subsonic
    /// Any other `type`, as the server wrote it.
    case other(String)

    /// From the `type` of a `subsonic-response`, case-insensitively.
    public init(type: String?) {
        let raw = (type ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch raw.lowercased() {
        case "": self = .subsonic
        case "navidrome": self = .navidrome
        case "gonic": self = .gonic
        case "ampache": self = .ampache
        case "lms": self = .lms
        case "subsonic": self = .subsonic
        case let name where name.hasPrefix("airsonic"): self = .airsonic
        default: self = .other(raw)
        }
    }

    public var displayName: String {
        switch self {
        case .navidrome: "Navidrome"
        case .gonic: "Gonic"
        case .airsonic: "Airsonic"
        case .ampache: "Ampache"
        case .lms: "LMS"
        case .subsonic: "Subsonic"
        case let .other(name): name
        }
    }
}

public enum ServerKind: Hashable, Sendable, Codable {
    case jellyfin
    case subsonic(flavour: SubsonicFlavour)

    /// "Jellyfin", "Navidrome", …: "Signing in to Tijmen's Music · Navidrome 0.64.2".
    public var displayName: String {
        switch self {
        case .jellyfin: "Jellyfin"
        case let .subsonic(flavour): flavour.displayName
        }
    }

    public var isSubsonic: Bool {
        if case .subsonic = self { return true }
        return false
    }
}

/// What a server can do beyond the library itself, so the app hides what
/// a server lacks rather than showing a button that fails. Each one's
/// meaning on each server is in docs/SERVERS.md ("Capabilities").
public enum ServerCapability: String, Hashable, Sendable, Codable, CaseIterable {
    /// Sign in with a code typed into another app (Jellyfin's Quick Connect,
    /// when /QuickConnect/Enabled says so).
    case quickConnect
    /// Sign in with an API key instead of a password (OpenSubsonic's
    /// `apiKeyAuthentication`).
    case apiKeySignIn
    /// A mix from a seed: Jellyfin's Instant Mix, Subsonic's getSimilarSongs.
    /// The answer may still be empty (a Subsonic server with nothing to go
    /// on); the radio carries on with the library's own picks then.
    case instantMix
    /// Who is like an artist: Jellyfin's /Similar, Subsonic's getArtistInfo2.
    case similarArtists
    /// An artist's best-known songs: Subsonic's getTopSongs (from Last.fm,
    /// on the server). Jellyfin has none.
    case topSongs
    /// Lyrics of any kind.
    case lyrics
    /// Timed lines are possible (Jellyfin 10.9+, OpenSubsonic `songLyrics`).
    case syncedLyrics
    /// A song can be moved within a playlist: Jellyfin moves an entry,
    /// Subsonic writes the playlist's songs again in the new order.
    case playlistReorder
    /// Tracks can carry a loudness gain (Jellyfin's NormalizationGain,
    /// OpenSubsonic's `replayGain`): Settings' Normalize Volume.
    case replayGain
    /// Pause and position reach the server's own "now playing": Jellyfin's
    /// sessions, OpenSubsonic's `playbackReport`. Without it the server
    /// only learns what started and what counted.
    case playbackTimeline
    /// Tracks carry the date they were last played (Jellyfin's
    /// LastPlayedDate, OpenSubsonic's `played`). Without it the radio's
    /// taste weighs play counts at 0.6 (Taste.swift).
    case lastPlayed
    /// A converted stream can start part-way (OpenSubsonic's
    /// `transcodeOffset`), for seeking in it.
    case transcodeOffset

    /// What every Jellyfin 10.9+ server has once signed in. Quick Connect
    /// is a question for the sign-in screen, not the session.
    public static let jellyfin: Set<ServerCapability> = [
        .instantMix, .similarArtists, .lyrics, .syncedLyrics, .playlistReorder,
        .replayGain, .playbackTimeline, .lastPlayed,
    ]
}

/// What answered at an address, before anyone has signed in: what the
/// sign-in screen shows ("Signing in to Tijmen's Music") and asks with.
public struct DetectedServer: Hashable, Sendable {
    public var kind: ServerKind
    /// The base URL that answered (one of `MusicServers.candidateAddresses`).
    public var url: URL
    /// Jellyfin's server Id. Subsonic servers have none: the URL, as the
    /// app's caches are kept by server and user.
    public var id: String
    /// Jellyfin's ServerName. Subsonic servers have none: the host.
    public var name: String
    /// Jellyfin's Version; OpenSubsonic's `serverVersion` ("0.64.2
    /// (10114574)"); for an older Subsonic server, its API version.
    public var version: String
    /// Subsonic's REST API version from the ping ("1.16.1"): every call
    /// sends the lower of this and 1.16.1 as `v`. Nil for Jellyfin.
    public var apiVersion: String?
    /// What is known before signing in: Quick Connect, an API key, and for
    /// OpenSubsonic what getOpenSubsonicExtensions lists (it answers
    /// without credentials, measured on Navidrome).
    public var capabilities: Set<ServerCapability>

    public init(kind: ServerKind, url: URL, id: String, name: String, version: String,
                apiVersion: String? = nil, capabilities: Set<ServerCapability> = []) {
        self.kind = kind
        self.url = url
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.capabilities = capabilities
    }
}

// MARK: - Credentials

/// What stands in for the password from sign-in on, in the keychain.
/// docs/SERVERS.md ("What the keychain keeps") has the reasons.
public enum ServerSecret: Hashable, Sendable, Codable {
    /// Jellyfin's access token (AuthenticateByName or Quick Connect).
    case jellyfinToken(String)
    /// Subsonic's token authentication: `t` = md5(password + salt) and `s`,
    /// made once at sign-in and sent with every call, so the password is
    /// never kept and every image and stream URL stays the same (the image
    /// cache is keyed by URL). Navidrome accepts the same salt on every
    /// call (measured).
    case subsonicToken(token: String, salt: String)
    /// OpenSubsonic's `apiKey`, sent without `u`.
    case subsonicAPIKey(String)
    /// The password itself, sent as `p=enc:<hex>`: only for a server that
    /// refuses tokens (error 41) and offers no API key, and only over https
    /// or on the home network.
    case subsonicPassword(String)
}

/// A signed-in session, as the keychain keeps it: everything the app needs
/// to open the library again without asking, offline too.
///
/// Reads the Jellyfin-only `Credentials` the app kept before (the same JSON
/// with `accessToken` and no `kind`), so nobody is signed out by the update.
public struct ServerCredentials: Hashable, Sendable {
    public var kind: ServerKind
    public var serverURL: URL
    /// Jellyfin's server Id; for Subsonic the URL (DetectedServer.id).
    public var serverID: String
    public var serverName: String
    public var serverVersion: String
    /// Subsonic's API version (DetectedServer.apiVersion); nil for Jellyfin.
    public var apiVersion: String?
    /// Jellyfin's user Id. Subsonic has no user ids: the user name.
    public var userID: String
    public var userName: String
    public var secret: ServerSecret
    /// What the server could do when last asked (`MusicServer.currentCapabilities`),
    /// so a launch without the network shows the same screens.
    public var capabilities: Set<ServerCapability>

    public init(kind: ServerKind, serverURL: URL, serverID: String, serverName: String,
                serverVersion: String = "", apiVersion: String? = nil, userID: String,
                userName: String, secret: ServerSecret, capabilities: Set<ServerCapability> = []) {
        self.kind = kind
        self.serverURL = serverURL
        self.serverID = serverID
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.apiVersion = apiVersion
        self.userID = userID
        self.userName = userName
        self.secret = secret
        self.capabilities = capabilities
    }

    /// A Jellyfin sign-in as JellyfinClient gives it.
    public init(jellyfin credentials: Credentials, serverVersion: String = "",
                capabilities: Set<ServerCapability> = ServerCapability.jellyfin) {
        self.init(kind: .jellyfin, serverURL: credentials.serverURL, serverID: credentials.serverID,
                  serverName: credentials.serverName, serverVersion: serverVersion,
                  userID: credentials.userID, userName: credentials.userName,
                  secret: .jellyfinToken(credentials.accessToken), capabilities: capabilities)
    }

    /// The same session as JellyfinClient takes it; nil for a Subsonic one.
    public var jellyfin: Credentials? {
        guard kind == .jellyfin, case let .jellyfinToken(token) = secret else { return nil }
        return Credentials(serverURL: serverURL, serverID: serverID, serverName: serverName,
                           userID: userID, userName: userName, accessToken: token)
    }
}

extension ServerCredentials: Codable {
    enum CodingKeys: String, CodingKey {
        case kind, serverURL, serverID, serverName, serverVersion, apiVersion
        case userID, userName, secret, capabilities
        /// The Jellyfin-only Credentials' token (read, never written).
        case accessToken
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try c.decode(URL.self, forKey: .serverURL)
        serverID = try c.decodeIfPresent(String.self, forKey: .serverID) ?? ""
        serverName = try c.decodeIfPresent(String.self, forKey: .serverName) ?? ""
        serverVersion = try c.decodeIfPresent(String.self, forKey: .serverVersion) ?? ""
        apiVersion = try c.decodeIfPresent(String.self, forKey: .apiVersion)
        userID = try c.decode(String.self, forKey: .userID)
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        if let secret = try c.decodeIfPresent(ServerSecret.self, forKey: .secret) {
            self.secret = secret
            kind = try c.decode(ServerKind.self, forKey: .kind)
        } else {
            // Kept by the Jellyfin-only app: a Credentials.
            secret = .jellyfinToken(try c.decode(String.self, forKey: .accessToken))
            kind = .jellyfin
        }
        capabilities = try c.decodeIfPresent(Set<ServerCapability>.self, forKey: .capabilities)
            ?? (kind == .jellyfin ? ServerCapability.jellyfin : [])
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(serverURL, forKey: .serverURL)
        try c.encode(serverID, forKey: .serverID)
        try c.encode(serverName, forKey: .serverName)
        try c.encode(serverVersion, forKey: .serverVersion)
        try c.encodeIfPresent(apiVersion, forKey: .apiVersion)
        try c.encode(userID, forKey: .userID)
        try c.encode(userName, forKey: .userName)
        try c.encode(secret, forKey: .secret)
        try c.encode(capabilities, forKey: .capabilities)
    }
}

// MARK: - What the calls take

/// A track, album or artist, for the calls that need to know which:
/// Subsonic stars a song by `id`, an album by `albumId` and an artist by
/// `artistId`. (Navidrome takes `id` for all three, measured; the others
/// need not.) Jellyfin uses the id alone.
public enum ItemRef: Hashable, Sendable {
    case track(ItemID)
    case album(ItemID)
    case artist(ItemID)

    public var id: ItemID {
        switch self {
        case let .track(id), let .album(id), let .artist(id): id
        }
    }
}

/// What a server mix starts from (`instantMix(from:limit:)`).
public enum MixSeed: Hashable, Sendable {
    case track(ItemID)
    case album(ItemID)
    case artist(ItemID)
    case playlist(ItemID)
    /// `id` is the server's own id for a genre of exactly this name; nil
    /// for a genre the library split out of a joined tag ("Shoegaze" of
    /// "Rock; Shoegaze", LibraryIndex.libraryGenres), which Jellyfin has no
    /// item for. Subsonic mixes a genre by name.
    case genre(name: String, id: ItemID?)
}

/// What the player tells the server, and when (docs/SERVERS.md, "Playback
/// reports"). One play is: `nowPlaying` at once; `played` once, when the
/// play counts by PlayOutcome's rule (not a skip); then `progress` and
/// `stopped`, which follow `played` only, so a skip is never written down
/// anywhere (Jellyfin sets LastPlayedDate on a stop without a start,
/// measured on 12.4).
public enum PlaybackEvent: String, Hashable, Sendable, CaseIterable {
    /// The entry began to play. Not a play yet: Jellyfin is told nothing
    /// (its start report counts one, measured), a Subsonic server shows it
    /// as playing (scrobble submission=false, or reportPlayback "starting"
    /// with ignoreScrobble).
    case nowPlaying
    /// Heard long enough to count: the server counts one play now
    /// (Jellyfin's start report; Subsonic's scrobble submission=true, with
    /// the time it began: now less the position).
    case played
    /// While it plays, every 10 s, and on pause, resume and seek.
    case progress
    /// It stopped being the current entry.
    case stopped
}

// MARK: - Errors

/// Every server's errors, as the app tells them apart. JellyfinClient's
/// become these one for one (`init(_:)`); Subsonic's error codes are mapped
/// in docs/SERVERS.md ("Errors").
public enum MusicServerError: Error, Sendable, Equatable, LocalizedError {
    /// Something answered, but not a Jellyfin or Subsonic server.
    case invalidServerAddress
    case notSignedIn
    /// The user name and password (or the key) were not accepted:
    /// Jellyfin's 401, Subsonic's 40 and 44.
    case unauthorized
    /// The server refuses a token made from the password (Subsonic's 41 or
    /// 42) and offers API keys: one is asked for rather than keeping the
    /// password, since a key can be revoked and a password is often the
    /// person's everywhere. `helpURL` is where the server says to get one
    /// (OpenSubsonic's `helpUrl`).
    case needsAPIKey(helpURL: URL?)
    /// The server needs the password itself on every call (no tokens, no
    /// API key), and the address is plain http away from home.
    case passwordNeedsHTTPS
    /// Allowed for others, not this user: Jellyfin's 403, Subsonic's 50
    /// (a playlist of someone else's, a user without the stream role).
    case notAllowed
    case notFound
    /// The server has no such call (Subsonic: HTTP 404 for an endpoint it
    /// lacks, measured on Navidrome).
    case unsupported(ServerCapability?)
    case server(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    public init(_ error: JellyfinError) {
        switch error {
        case .invalidServerAddress: self = .invalidServerAddress
        case .notSignedIn: self = .notSignedIn
        case .unauthorized: self = .unauthorized
        case .notFound: self = .notFound
        case .server(status: 403, _): self = .notAllowed
        case let .server(status, message): self = .server(status: status, message: message)
        case let .decoding(what): self = .decoding(what)
        case let .transport(what): self = .transport(what)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidServerAddress: "There is no Jellyfin or Subsonic server at this address."
        case .notSignedIn: "Not signed in."
        case .unauthorized: "The server did not accept the user name or password."
        case .needsAPIKey: "This server signs in with an API key rather than a password."
        case .passwordNeedsHTTPS: "This server needs your password on every request: use its https:// address."
        case .notAllowed: "The server does not allow that for this user."
        case .notFound: "The server does not have that."
        case .unsupported: "The server cannot do that."
        case let .server(status, message): message ?? "The server answered with error \(status)."
        case let .decoding(what): "The server's answer could not be read (\(what))."
        case let .transport(what): what
        }
    }
}

// MARK: - Signing in

/// Signing in to a server that has answered (`MusicServers.signIn(to:)`).
public protocol ServerSignIn: Sendable {
    var server: DetectedServer { get }

    /// Jellyfin: POST /Users/AuthenticateByName. Subsonic: a ping with a
    /// token made from the password (`ServerSecret.subsonicToken`); on 41
    /// the API key (`needsAPIKey`) or the password itself.
    func signIn(username: String, password: String) async throws -> ServerCredentials
}

/// A server that signs in with an API key (OpenSubsonic's
/// `apiKeyAuthentication`): `signIn as? any APIKeySignIn`.
public protocol APIKeySignIn: ServerSignIn {
    /// A ping with `apiKey`, then tokenInfo for the user's name.
    func signIn(apiKey: String) async throws -> ServerCredentials
}

/// Jellyfin's Quick Connect: `signIn as? any QuickConnectSignIn`, offered
/// when `server.capabilities` has `.quickConnect`.
public protocol QuickConnectSignIn: ServerSignIn {
    func quickConnectStart() async throws -> QuickConnectState
    /// Asked every 3 s until `isAuthenticated`.
    func quickConnectState(secret: String) async throws -> QuickConnectState
    func signIn(quickConnectSecret: String) async throws -> ServerCredentials
}

// MARK: - A signed-in server

/// One signed-in session with a server, Jellyfin or Subsonic: what
/// AppModel, LibraryStore, AudioPlayer, RadioController and the screens use
/// instead of JellyfinClient. Immutable and Sendable, like JellyfinClient.
///
/// Every call throws MusicServerError. docs/SERVERS.md maps each one to
/// Jellyfin's and Subsonic's requests.
public protocol MusicServer: Sendable {
    // MARK: Who

    var kind: ServerKind { get }
    /// The session as the keychain keeps it: the server's name and the
    /// user's, for Settings; the ids the caches are kept by.
    var credentials: ServerCredentials { get }
    /// As of sign-in or the last `currentCapabilities()`.
    var capabilities: Set<ServerCapability> { get }
    /// What the server can do now (it may have been upgraded), asked
    /// again. The app saves a changed set in the credentials.
    func currentCapabilities() async throws -> Set<ServerCapability>
    /// Jellyfin: POST /Sessions/Logout. Subsonic has no sign-out: the app
    /// forgets the token, which stays good until the password changes.
    func signOut() async

    // MARK: The library, all of it (LibraryStore)

    /// Every track, for the index the radio and the mixes work from, in no
    /// particular order (LibraryIndex sorts); `progress` is told (done,
    /// total) as pages come in.
    func allTracks(progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track]
    func allAlbums() async throws -> [Album]
    /// Album artists, the list Music's Artists shows: someone who is only
    /// a guest somewhere is not in it.
    func allArtists() async throws -> [Artist]
    func playlists() async throws -> [Playlist]
    func genres() async throws -> [Genre]

    // MARK: One item

    func track(id: ItemID) async throws -> Track
    func album(id: ItemID) async throws -> Album
    func artist(id: ItemID) async throws -> Artist
    /// An album's tracks in disc order, for an album page opened before the
    /// library is in.
    func albumTracks(albumID: ItemID) async throws -> [Track]
    /// Artists, albums, tracks and playlists matching `term`, `limit` of
    /// each. (The app searches its own library today; this is for a server
    /// too large to hold.)
    func search(_ term: String, limit: Int) async throws -> SearchResults

    // MARK: Changes

    func setFavorite(_ isFavorite: Bool, item: ItemRef) async throws

    /// A playlist's tracks in order, each with its `playlistEntryID`: what
    /// removing or moving that place needs. Jellyfin: its PlaylistItemId.
    /// Subsonic has no entry ids (updatePlaylist removes by position), so
    /// the kit makes one: the song's id and which of its occurrences this
    /// is, "<songID>#<n>" from 0 — it holds when other songs move.
    func playlistTracks(playlistID: ItemID) async throws -> [Track]
    /// The new playlist's id. The tracks in order, duplicates kept.
    func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID
    /// At the end, in order.
    func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws
    /// Entry ids as `playlistTracks` gave them. One the playlist no longer
    /// has is skipped. Subsonic reads the playlist first and removes by
    /// position there (docs/SERVERS.md, "Playlist entries").
    func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws
    /// `index` counted in the playlist as it is before the move.
    func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws
    func deletePlaylist(id: ItemID) async throws

    // MARK: What only the server knows

    /// Who the server thinks is like the artist, its own ids.
    func similarArtists(artistID: ItemID, limit: Int) async throws -> [Artist]
    /// Up to `limit` tracks that go with the seed, for the radio. Empty is
    /// an answer: the server had nothing to go on.
    func instantMix(from seed: MixSeed, limit: Int) async throws -> [Track]
    /// The artist's best-known songs (`.topSongs`): the id where the server
    /// takes one, else the name.
    func topSongs(of artist: ArtistRef, limit: Int) async throws -> [Track]
    /// Nil when the track has none. The track, not its id: Subsonic's
    /// classic getLyrics asks by artist and title.
    func lyrics(for track: Track) async throws -> Lyrics?

    // MARK: Playing

    /// A URL AVPlayer plays as it is (credentials in the query: it sends
    /// no headers). `quality` caps the bitrate; the server converts to
    /// something AVPlayer plays (Jellyfin: AAC over HLS; Subsonic: MP3,
    /// since Navidrome's own choice is Ogg Opus, measured).
    func streamURL(for track: Track, quality: StreamQuality, playSessionID: String) -> URL
    /// Square, `maxPixelSize` on its longer side. The same artwork and size
    /// give the same URL, always: the image cache is keyed by it.
    /// `artwork.tag` is the server's key to the image: Jellyfin's ImageTag
    /// (with `itemID`, the item), Subsonic's coverArt id.
    func artworkURL(_ artwork: Artwork, maxPixelSize: Int) -> URL
    /// Never throws and never waits on the music: a missed report is lost.
    func report(_ event: PlaybackEvent, _ report: PlaybackReport) async
}

// MARK: - Finding and opening servers

/// Where a server is found, signed in to and opened. The rule for finding
/// one is in docs/SERVERS.md ("Which server is at an address").
public enum MusicServers {
    /// What a person typed as their server, as base URLs to try in order:
    /// the address as typed (normalized as JellyfinClient.normalize does,
    /// with Navidrome's "/app" cut off like Jellyfin's "/web"); then, when
    /// no port and no "https://" were typed, the same host over http on
    /// Jellyfin's 8096, Navidrome's 4533, Gonic's 4747, Airsonic's 4040
    /// and LMS's 5082.
    public static func candidateAddresses(for typed: String) -> [URL] {
        ServerAddress.candidates(typed)
    }

    /// The server at what was typed. Every candidate is asked at once, both
    /// ways (Jellyfin's /System/Info/Public, Subsonic's /rest/ping.view);
    /// the first candidate in order that proves to be a server wins, a later
    /// one only once every earlier one has failed. Errors are the first
    /// candidate's: the address as typed is the one to talk about.
    public static func detect(_ typed: String, identity: ClientIdentity,
                              transport: any HTTPTransport = URLSessionTransport()) async throws -> DetectedServer {
        try await ServerAddress.detect(typed, identity: identity, transport: transport)
    }

    /// Signing in to a server `detect` found. Also an `APIKeySignIn` or a
    /// `QuickConnectSignIn` where the server offers one.
    public static func signIn(to server: DetectedServer, identity: ClientIdentity,
                              transport: any HTTPTransport = URLSessionTransport()) -> any ServerSignIn {
        switch server.kind {
        case .jellyfin:
            if server.capabilities.contains(.quickConnect) {
                return JellyfinQuickConnectSignIn(server: server, identity: identity, transport: transport)
            }
            return JellyfinSignIn(server: server, identity: identity, transport: transport)
        case .subsonic:
            if server.capabilities.contains(.apiKeySignIn) {
                return SubsonicAPIKeySignIn(server: server, identity: identity, transport: transport)
            }
            return SubsonicSignIn(server: server, identity: identity, transport: transport)
        }
    }

    /// The session the credentials are for, without asking the server.
    public static func open(_ credentials: ServerCredentials, identity: ClientIdentity,
                            transport: any HTTPTransport = URLSessionTransport()) -> any MusicServer {
        switch credentials.kind {
        case .jellyfin: JellyfinServer(credentials: credentials, identity: identity, transport: transport)
        case .subsonic: SubsonicClient(credentials: credentials, identity: identity, transport: transport)
        }
    }
}
