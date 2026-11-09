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

    /// A playlist's tracks with an entry id for each place. Jellyfin 12.4's
    /// own (PlaylistItemId) is the song's id (measured), so a song twice in
    /// a playlist has one id for both places, which the contract and the
    /// app's rows (PlaylistsView's ForEach) need apart. Then every place
    /// gets "<its id>#<n>", n counting that id's earlier places from 0, as
    /// Subsonic's are made (SubsonicClient.entryIDs); a playlist where no
    /// song repeats keeps Jellyfin's ids and Jellyfin's own calls.
    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        var tracks = try await mapped { try await client.playlistTracks(playlistID: playlistID) }
        let entries = tracks.map(Self.entry)
        guard Set(entries).count < entries.count else { return tracks }
        for (i, id) in SubsonicClient.entryIDs(entries).enumerated() { tracks[i].playlistEntryID = id }
        return tracks
    }

    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        try await mapped { try await client.createPlaylist(name: name, trackIDs: trackIDs) }
    }

    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        try await mapped { try await client.addToPlaylist(playlistID: playlistID, trackIDs: trackIDs) }
    }

    /// Jellyfin's own ids: DELETE them. A place of a song that repeats
    /// ("<id>#<n>"): Jellyfin removes every place of an entry id (measured
    /// on 12.4: A B A C A, remove A, gives B C), so the song's other places
    /// are added back where they were (`rewrite`).
    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        guard entryIDs.contains(where: Self.isPlace) else {
            return try await mapped { try await client.removeFromPlaylist(playlistID: playlistID, entryIDs: entryIDs) }
        }
        try await mapped {
            let places = try await self.places(playlistID)
            let gone = Set(SubsonicClient.positions(of: entryIDs, in: places.map(\.entry)))
            let kept = places.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            try await rewrite(playlistID, to: kept, songs: Set(gone.map { places[$0].entry }))
        }
    }

    /// Jellyfin's own id: its Move (`index` the place the entry ends up in,
    /// measured: A to 2 in A B C D gives B C A D). A place of a song that
    /// repeats: Jellyfin moves the first place of that id, and not by that
    /// rule (measured on 12.4: A B A C A, A to 3, gave B A A C A), so the
    /// song comes out and goes back at its places in the new order.
    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        guard Self.isPlace(entryID) else {
            return try await mapped { try await client.movePlaylistEntry(playlistID: playlistID, entryID: entryID, to: index) }
        }
        try await mapped {
            var places = try await self.places(playlistID)
            guard let from = SubsonicClient.positions(of: [entryID], in: places.map(\.entry)).first else {
                throw JellyfinError.notFound
            }
            let to = min(max(0, index), places.count - 1)
            guard from != to else { return }
            let song = places[from].entry
            places.insert(places.remove(at: from), at: to)
            try await rewrite(playlistID, to: places, songs: [song])
        }
    }

    /// One place in a playlist: Jellyfin's entry id and the track there.
    struct Place: Sendable {
        var entry: String
        var track: ItemID
    }

    static func entry(_ track: Track) -> String { track.playlistEntryID ?? track.id }

    /// An entry id made by `playlistTracks`, "<id>#<n>"; Jellyfin's own are
    /// GUIDs, without "#".
    static func isPlace(_ entryID: String) -> Bool {
        guard let mark = entryID.lastIndex(of: "#") else { return false }
        let digits = entryID[entryID.index(after: mark)...]
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    func places(_ playlistID: ItemID) async throws -> [Place] {
        try await client.playlistTracks(playlistID: playlistID).map { Place(entry: Self.entry($0), track: $0.id) }
    }

    /// The playlist made into `target`, which differs from what it is only
    /// in the places of `songs` (entry ids): every place of those removed in
    /// one DELETE, then each place they have in `target` added at its
    /// position (POST /Playlists/{id}/Items?ids=&position=, measured on
    /// 12.4 to insert there and keep it), in order from the start, so the
    /// places before each one are already right; neighbours go in one
    /// request. Not atomic, as Jellyfin has no call that is: a request lost
    /// after the DELETE leaves those songs' places out, never another song's.
    /// (POST /Playlists/{id} with `Ids` would write the whole list at once,
    /// but on 12.4 its items showed the new order while the playlist kept
    /// the old one and the next change went on from that: not used.)
    func rewrite(_ playlistID: ItemID, to target: [Place], songs: Set<String>) async throws {
        guard !songs.isEmpty else { return }
        let user = try client.requireUser()
        try await client.removeFromPlaylist(playlistID: playlistID, entryIDs: songs.sorted())
        var i = 0
        while i < target.count {
            guard songs.contains(target[i].entry) else { i += 1; continue }
            var run = [target[i].track]
            var next = i + 1
            while next < target.count, songs.contains(target[next].entry), run.count < JellyfinClient.idsPerRequest {
                run.append(target[next].track)
                next += 1
            }
            try await client.send("POST", "/Playlists/\(JellyfinClient.segment(playlistID))/Items", query: [
                URLQueryItem(name: "ids", value: run.joined(separator: ",")),
                URLQueryItem(name: "position", value: String(i)),
                URLQueryItem(name: "userId", value: user),
            ])
            i = next
        }
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
