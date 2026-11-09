// Jellyfin as a MusicServer: a thin wrapper around JellyfinClient, which
// stays as it is (its public API, its tests and its measurements), so the
// app compiles unchanged until it moves to MusicServer.
//
// A wrapper rather than JellyfinClient conforming in an extension, for
// three reasons found while writing it:
// - The protocol says every call throws MusicServerError. Many of
//   JellyfinClient's calls already have the protocol's exact signature
//   (`genres()`, `playlists()`, `track(id:)`, `deletePlaylist(id:)`, …), so
//   a conformance would take them as they are, throwing JellyfinError, and
//   the app catches JellyfinError from them today (LibraryStore,
//   OnboardingView), so they cannot change what they throw.
// - `credentials` (the server's name and version, the user's name) is not
//   something JellyfinClient holds, and an extension cannot add it.
// - `allTracks(pageSize:progress:)` with its default and the protocol's
//   `allTracks(progress:)` side by side would make the app's call
//   ambiguous to read.
// So this is where JellyfinError becomes MusicServerError (`init(_:)`).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct JellyfinServer: MusicServer {
    public let client: JellyfinClient
    public let credentials: ServerCredentials

    public init(client: JellyfinClient, credentials: ServerCredentials) {
        self.client = client
        self.credentials = credentials
    }

    /// The session the credentials are for (`MusicServers.open`).
    public init(credentials: ServerCredentials, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        let token: String? = if case let .jellyfinToken(token) = credentials.secret { token } else { nil }
        self.init(client: JellyfinClient(serverURL: credentials.serverURL, identity: identity, accessToken: token,
                                         userID: credentials.userID, transport: transport),
                  credentials: credentials)
    }

    public var kind: ServerKind { .jellyfin }
    public var capabilities: Set<ServerCapability> { credentials.capabilities }

    /// What a Jellyfin of this version has once signed in: lyrics and
    /// NormalizationGain came with 10.9. A version that cannot be read is
    /// taken as new.
    static func capabilities(version: String) -> Set<ServerCapability> {
        guard !SubsonicConnection.numbers(version).isEmpty,
              SubsonicConnection.compare(version, "10.9.0") == .orderedAscending else { return ServerCapability.jellyfin }
        return ServerCapability.jellyfin.subtracting([.lyrics, .syncedLyrics, .replayGain])
    }

    /// JellyfinError as MusicServerError; cancellation as it is.
    func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as JellyfinError {
            throw MusicServerError(error)
        }
    }

    // MARK: Who

    /// /System/Info/Public's version (an upgrade to or past 10.9 adds
    /// lyrics).
    public func currentCapabilities() async throws -> Set<ServerCapability> {
        let info = try await mapped { try await client.publicInfo() }
        return Self.capabilities(version: info.version)
    }

    public func signOut() async {
        await client.signOut()
    }

    // MARK: The library

    public func allTracks(progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track] {
        try await mapped { try await client.allTracks(progress: progress) }
    }

    /// 1000 a page, as LibraryStore asked for them.
    public func allAlbums() async throws -> [Album] {
        try await mapped {
            var albums: [Album] = []
            while true {
                let page = try await client.albums(AlbumQuery(sort: .name, start: albums.count, limit: 1000))
                albums += page.items
                if page.items.isEmpty || albums.count >= page.totalCount { return albums }
            }
        }
    }

    public func allArtists() async throws -> [Artist] {
        try await mapped {
            var artists: [Artist] = []
            while true {
                let page = try await client.artists(start: artists.count, limit: 1000)
                artists += page.items
                if page.items.isEmpty || artists.count >= page.totalCount { return artists }
            }
        }
    }

    public func playlists() async throws -> [Playlist] {
        try await mapped { try await client.playlists() }
    }

    public func genres() async throws -> [Genre] {
        try await mapped { try await client.genres() }
    }

    // MARK: One item

    public func track(id: ItemID) async throws -> Track {
        try await mapped { try await client.track(id: id) }
    }

    public func album(id: ItemID) async throws -> Album {
        try await mapped { try await client.album(id: id) }
    }

    public func artist(id: ItemID) async throws -> Artist {
        try await mapped { try await client.artist(id: id) }
    }

    /// The album's own order: disc, then track (TrackQuery's default with
    /// an album).
    public func albumTracks(albumID: ItemID) async throws -> [Track] {
        try await mapped { try await client.tracks(TrackQuery(albumID: albumID)).items }
    }

    public func search(_ term: String, limit: Int) async throws -> SearchResults {
        try await mapped { try await client.search(term, limit: limit) }
    }

    // MARK: Changes

    /// Jellyfin needs the id alone, whatever the item.
    public func setFavorite(_ isFavorite: Bool, item: ItemRef) async throws {
        try await mapped { try await client.setFavorite(isFavorite, itemID: item.id) }
    }

    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        try await mapped { try await client.playlistTracks(playlistID: playlistID) }
    }

    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        try await mapped { try await client.createPlaylist(name: name, trackIDs: trackIDs) }
    }

    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        try await mapped { try await client.addToPlaylist(playlistID: playlistID, trackIDs: trackIDs) }
    }

    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        try await mapped { try await client.removeFromPlaylist(playlistID: playlistID, entryIDs: entryIDs) }
    }

    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        try await mapped { try await client.movePlaylistEntry(playlistID: playlistID, entryID: entryID, to: index) }
    }

    public func deletePlaylist(id: ItemID) async throws {
        try await mapped { try await client.deletePlaylist(id: id) }
    }

    // MARK: What only the server knows

    public func similarArtists(artistID: ItemID, limit: Int) async throws -> [Artist] {
        try await mapped { try await client.similarArtists(artistID: artistID, limit: limit) }
    }

    /// /Items/{id}/InstantMix takes any of the seeds' ids. A genre the
    /// library split out of a joined tag ("Shoegaze" of "Rock; Shoegaze")
    /// has no id on Jellyfin: nothing to go on, so no tracks (the radio
    /// carries on with its own picks, as RadioController's isJellyfinID
    /// made it do).
    public func instantMix(from seed: MixSeed, limit: Int) async throws -> [Track] {
        let id: ItemID? = switch seed {
        case let .track(id), let .album(id), let .artist(id), let .playlist(id): id
        case let .genre(_, id): id
        }
        guard let id, !id.isEmpty else { return [] }
        return try await mapped { try await client.instantMix(seedID: id, limit: limit) }
    }

    /// Jellyfin has no top songs of its own.
    public func topSongs(of artist: ArtistRef, limit: Int) async throws -> [Track] {
        throw MusicServerError.unsupported(.topSongs)
    }

    public func lyrics(for track: Track) async throws -> Lyrics? {
        try await mapped { try await client.lyrics(trackID: track.id) }
    }

    // MARK: Playing

    public func streamURL(for track: Track, quality: StreamQuality, playSessionID: String) -> URL {
        client.streamURL(trackID: track.id, quality: quality, playSessionID: playSessionID)
    }

    public func downloadURL(for track: Track, quality: DownloadQuality) -> URL {
        client.downloadURL(trackID: track.id, quality: quality)
    }

    public func downloadsAllowed() async throws -> Bool {
        do {
            return try await client.downloadsAllowed()
        } catch let error as JellyfinError {
            throw MusicServerError(error)
        }
    }

    public func artworkURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        client.imageURL(artwork, maxPixelSize: maxPixelSize)
    }

    /// Jellyfin counts a play at its start report (measured on 12.4), so
    /// `.played` is the start report and `.nowPlaying` is nothing: a skip
    /// is never counted, as AudioPlayer holds the start back today.
    public func report(_ event: PlaybackEvent, _ report: PlaybackReport) async {
        switch event {
        case .nowPlaying: return
        case .played: await client.reportStart(report)
        case .progress: await client.reportProgress(report)
        case .stopped: await client.reportStopped(report)
        }
    }
}

// MARK: - Signing in

/// Signing in to a Jellyfin `MusicServers.detect` found.
public struct JellyfinSignIn: ServerSignIn {
    public let server: DetectedServer
    let client: JellyfinClient

    public init(server: DetectedServer, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.server = server
        client = JellyfinClient(serverURL: server.url, identity: identity, transport: transport)
    }

    /// POST /Users/AuthenticateByName.
    public func signIn(username: String, password: String) async throws -> ServerCredentials {
        do {
            return session(try await client.signIn(username: username, password: password))
        } catch let error as JellyfinError {
            throw MusicServerError(error)
        }
    }

    func session(_ credentials: Credentials) -> ServerCredentials {
        ServerCredentials(jellyfin: credentials, serverVersion: server.version,
                          capabilities: JellyfinServer.capabilities(version: server.version))
    }
}

/// A Jellyfin with Quick Connect enabled (`server.capabilities` has
/// `.quickConnect`): a code typed into another signed-in client.
public struct JellyfinQuickConnectSignIn: QuickConnectSignIn {
    let base: JellyfinSignIn

    public init(server: DetectedServer, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        base = JellyfinSignIn(server: server, identity: identity, transport: transport)
    }

    public var server: DetectedServer { base.server }

    public func signIn(username: String, password: String) async throws -> ServerCredentials {
        try await base.signIn(username: username, password: password)
    }

    public func quickConnectStart() async throws -> QuickConnectState {
        do { return try await base.client.quickConnectStart() } catch let error as JellyfinError {
            throw MusicServerError(error)
        }
    }

    public func quickConnectState(secret: String) async throws -> QuickConnectState {
        do { return try await base.client.quickConnectState(secret: secret) } catch let error as JellyfinError {
            throw MusicServerError(error)
        }
    }

    public func signIn(quickConnectSecret: String) async throws -> ServerCredentials {
        do {
            return base.session(try await base.client.signIn(quickConnectSecret: quickConnectSecret))
        } catch let error as JellyfinError {
            throw MusicServerError(error)
        }
    }
}
