// One signed-in session with a Subsonic server — Navidrome, Gonic,
// Airsonic(-Advanced), Ampache's Subsonic API, LMS, the original Subsonic —
// as a MusicServer, through the Subsonic API only (docs/SERVERS.md has the
// design, the map from each call to its requests, and the measurements on
// Navidrome 0.64.2). Immutable and Sendable, like JellyfinClient.
//
// The photographer, 8 November 2026: "Moet eigenlijk ook voor navidrome en
// die ander".
//
// Every call goes through `SubsonicConnection` (SubsonicRequests.swift),
// so the tests can answer for the server; the answers are read leniently
// (SubsonicDTO.swift). Every call throws MusicServerError.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SubsonicClient: MusicServer {
    public let credentials: ServerCredentials
    public let identity: ClientIdentity
    let connection: SubsonicConnection

    /// A session the credentials are for, without asking the server
    /// (`MusicServers.open`).
    public init(credentials: ServerCredentials, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.credentials = credentials
        self.identity = identity
        let user = credentials.userName.isEmpty ? credentials.userID : credentials.userName
        connection = SubsonicConnection(baseURL: credentials.serverURL,
                                        auth: SubsonicConnection.auth(credentials.secret, user: user),
                                        serverAPIVersion: credentials.apiVersion,
                                        clientName: identity.clientName, transport: transport)
    }

    public var kind: ServerKind { credentials.kind }
    public var capabilities: Set<ServerCapability> { credentials.capabilities }
    public var serverURL: URL { credentials.serverURL }

    /// The answer of a call that needs the session.
    func call(_ endpoint: String, _ query: [URLQueryItem] = [], timeout: TimeInterval = 30,
              lacking capability: ServerCapability? = nil, post: Bool = false) async throws -> SubsonicBody {
        guard !connection.auth.isEmpty else { throw MusicServerError.notSignedIn }
        return try await connection.call(endpoint, query, timeout: timeout, lacking: capability, post: post)
    }

    // MARK: Who

    /// A ping, and getOpenSubsonicExtensions: a server upgraded since
    /// sign-in may have grown an extension (or an API version).
    public func currentCapabilities() async throws -> Set<ServerCapability> {
        let ping = try await call("ping", timeout: 15)
        let openSubsonic = ping.openSubsonic == true
        let extensions = openSubsonic ? await connection.extensions() : []
        return SubsonicConnection.capabilities(apiVersion: ping.version ?? credentials.apiVersion,
                                               openSubsonic: openSubsonic, extensions: extensions)
            .subtracting(ServerCapability.signingInOnly)
    }

    /// Subsonic has no sign-out: the app forgets the token, which holds
    /// until the password changes.
    public func signOut() async {}

    // MARK: The library, all of it

    /// Every song, from `search3` with an empty query, which lists them all
    /// (the OpenSubsonic spec, for offline sync), 1000 a request.
    ///
    /// Measured on Navidrome 0.64.2 (358 songs, about 1.07 kB of JSON
    /// each): one request answers all 358 in 17–26 ms; pages of 100 at
    /// offsets 0/100/200/300 gave 100/100/100/58. The albums come first
    /// (getAlbumList2, 4–6 ms for 54): their song counts are the total for
    /// `progress`, they name the album artist where a song does not
    /// (no OpenSubsonic), and they show whether the search missed songs. A
    /// server whose empty search lists fewer songs than its albums hold (or
    /// refuses one) has the missing albums walked, getAlbum four at once
    /// (124–160 ms for all 54 on Navidrome, one after another).
    public func allTracks(progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track] {
        try await allTracks(pageSize: 1000, progress: progress)
    }

    func allTracks(pageSize: Int, progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track] {
        let size = max(1, pageSize)
        let albums = try await albumAnswers()
        let expected = albums.reduce(0) { $0 + max(0, $1.songCount ?? 0) }
        var tracks: [Track] = []
        tracks.reserveCapacity(expected)
        var seen = Set<ItemID>()
        var perAlbum: [ItemID: Int] = [:]
        func add(_ songs: [SubsonicChild]) -> Int {
            var added = 0
            for song in songs {
                guard let track = song.asTrack(), seen.insert(track.id).inserted else { continue }
                tracks.append(track)
                if let albumID = track.albumID { perAlbum[albumID, default: 0] += 1 }
                added += 1
            }
            return added
        }
        func tell() { progress?(tracks.count, max(expected, tracks.count)) }
        progress?(0, expected)

        var offset = 0
        do {
            while true {
                let body = try await call("search3", [
                    URLQueryItem(name: "query", value: ""),
                    URLQueryItem(name: "artistCount", value: "0"),
                    URLQueryItem(name: "albumCount", value: "0"),
                    URLQueryItem(name: "songCount", value: String(size)),
                    URLQueryItem(name: "songOffset", value: String(offset)),
                ], timeout: 120)
                let songs = body.searchResult3?.song ?? []
                guard !songs.isEmpty else { break }
                let added = add(songs)
                tell()
                // Nothing new: a server that does not page (it answers the
                // first page again).
                guard added > 0 else { break }
                offset += songs.count
                // A short page with every song in: the end. A short page
                // short of the total may be a server that gives fewer than
                // asked: ask on.
                if songs.count < size, tracks.count >= expected { break }
            }
        } catch let error as MusicServerError where Self.walkingTheAlbumsHelps(error) {
            // A server that will not search for nothing: the albums below.
        }

        if tracks.count < expected {
            let missing = albums.compactMap { album -> ItemID? in
                guard let id = album.id, !id.isEmpty, let count = album.songCount, count > 0,
                      perAlbum[id, default: 0] < count else { return nil }
                return id
            }
            try await withThrowingTaskGroup(of: [SubsonicChild].self) { group in
                var next = missing.makeIterator()
                for _ in 0..<4 {
                    guard let id = next.next() else { break }
                    group.addTask { try await self.albumAnswer(id: id).song }
                }
                while let songs = try await group.next() {
                    _ = add(songs)
                    tell()
                    if let id = next.next() { group.addTask { try await self.albumAnswer(id: id).song } }
                }
            }
        }

        // Without OpenSubsonic a song names its artist, not its album's.
        let albumArtists = Dictionary(albums.compactMap { album in album.id.flatMap { id in album.albumArtist.map { (id, $0) } } },
                                      uniquingKeysWith: { first, _ in first })
        for i in tracks.indices where tracks[i].albumArtist == nil {
            if let albumID = tracks[i].albumID { tracks[i].albumArtist = albumArtists[albumID] }
        }
        return tracks
    }

    /// Errors after which the albums are worth walking: the server
    /// answered, but not with songs. Not signing-in or network errors.
    static func walkingTheAlbumsHelps(_ error: MusicServerError) -> Bool {
        switch error {
        case .server, .unsupported, .decoding, .notFound: true
        default: false
        }
    }

    /// getAlbumList2 by name, 500 a request (the spec's maximum; Navidrome
    /// took 1000 for its 54), until a page brings nothing new: a server may
    /// give fewer than asked, so a short page is not taken as the end.
    func albumAnswers() async throws -> [SubsonicAlbum] {
        var albums: [SubsonicAlbum] = []
        var seen = Set<String>()
        var offset = 0
        while true {
            let body = try await call("getAlbumList2", [
                URLQueryItem(name: "type", value: "alphabeticalByName"),
                URLQueryItem(name: "size", value: "500"),
                URLQueryItem(name: "offset", value: String(offset)),
            ], timeout: 60)
            let page = body.albumList2?.album ?? []
            var added = 0
            for album in page {
                guard let id = album.id, !id.isEmpty, seen.insert(id).inserted else { continue }
                albums.append(album)
                added += 1
            }
            guard !page.isEmpty, added > 0 else { return albums }
            offset += page.count
        }
    }

    public func allAlbums() async throws -> [Album] {
        try await albumAnswers().compactMap { $0.asAlbum() }
    }

    /// getArtists, every index at once (it is not paged). OpenSubsonic's
    /// `roles` leave out who is only a guest; a server without them lists
    /// whom it lists (the original Subsonic: everyone with an album).
    public func allArtists() async throws -> [Artist] {
        let body = try await call("getArtists", timeout: 60)
        var seen = Set<ItemID>()
        return (body.artists?.artists ?? []).filter { artist in
            artist.roles.isEmpty || artist.roles.contains { $0.lowercased() == "albumartist" }
        }.compactMap { $0.asArtist() }.filter { seen.insert($0.id).inserted }
    }

    /// getPlaylists, by name (as Jellyfin's).
    public func playlists() async throws -> [Playlist] {
        let body = try await call("getPlaylists")
        return (body.playlists?.playlist ?? []).compactMap { $0.asPlaylist(user: credentials.userName) }
            .sorted { Self.byName($0.name, $1.name) }
    }

    /// getGenres, by name. Navidrome splits tags itself: 23 genres on the
    /// test library, where Jellyfin lists 19 joined ones (measured).
    public func genres() async throws -> [Genre] {
        let body = try await call("getGenres")
        return (body.genres?.genre ?? []).compactMap { $0.asGenre() }.sorted { Self.byName($0.name, $1.name) }
    }

    static func byName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric]) == .orderedAscending
    }

    // MARK: One item

    /// getSong; an unknown id is error 70 "Song not found" (measured).
    public func track(id: ItemID) async throws -> Track {
        guard let track = try await call("getSong", [URLQueryItem(name: "id", value: id)]).song?.asTrack() else {
            throw MusicServerError.notFound
        }
        return track
    }

    public func album(id: ItemID) async throws -> Album {
        guard let album = try await albumAnswer(id: id).asAlbum() else { throw MusicServerError.notFound }
        return album
    }

    public func artist(id: ItemID) async throws -> Artist {
        let body = try await call("getArtist", [URLQueryItem(name: "id", value: id)])
        guard let artist = body.artist?.asArtist() else { throw MusicServerError.notFound }
        return artist
    }

    func albumAnswer(id: ItemID) async throws -> SubsonicAlbum {
        guard let album = try await call("getAlbum", [URLQueryItem(name: "id", value: id)]).album else {
            throw MusicServerError.notFound
        }
        return album
    }

    /// getAlbum's songs, by disc and track (as Navidrome lists them,
    /// measured; sorted again for a server that does not).
    public func albumTracks(albumID: ItemID) async throws -> [Track] {
        let album = try await albumAnswer(id: albumID)
        let albumArtist = album.albumArtist
        let tracks = album.song.compactMap { song -> Track? in
            guard var track = song.asTrack() else { return nil }
            if track.albumArtist == nil { track.albumArtist = albumArtist }
            return track
        }
        return tracks.enumerated().sorted { a, b in
            let x = (a.element.discNumber ?? 1, a.element.trackNumber ?? Int.max, a.offset)
            let y = (b.element.discNumber ?? 1, b.element.trackNumber ?? Int.max, b.offset)
            return x < y
        }.map(\.element)
    }

    /// search3 for artists, albums and songs; playlists are matched by name
    /// here, as Subsonic does not search them.
    public func search(_ term: String, limit: Int) async throws -> SearchResults {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return SearchResults() }
        let count = String(max(1, limit))
        async let found = call("search3", [
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "artistCount", value: count),
            URLQueryItem(name: "albumCount", value: count),
            URLQueryItem(name: "songCount", value: count),
        ])
        async let lists = playlists()
        let result = try await found.searchResult3
        let matching = ((try? await lists) ?? []).filter {
            $0.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return SearchResults(artists: (result?.artist ?? []).compactMap { $0.asArtist() },
                             albums: (result?.album ?? []).compactMap { $0.asAlbum() },
                             tracks: (result?.song ?? []).compactMap { $0.asTrack() },
                             playlists: Array(matching.prefix(max(1, limit))))
    }

    // MARK: Changes

    /// star / unstar: a song by `id`, an album by `albumId`, an artist by
    /// `artistId`, as the spec has it (Navidrome takes `id` for all three,
    /// measured; the others need not). An unknown id is ok on Navidrome.
    public func setFavorite(_ isFavorite: Bool, item: ItemRef) async throws {
        let name = switch item {
        case .track: "id"
        case .album: "albumId"
        case .artist: "artistId"
        }
        _ = try await call(isFavorite ? "star" : "unstar", [URLQueryItem(name: name, value: item.id)])
    }

    /// getPlaylist's songs in order, duplicates kept, each with an entry id
    /// made here: "<songID>#<n>", n counting that song's earlier places
    /// from 0 (docs/SERVERS.md, "Playlist entries").
    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        let entries = try await playlistAnswer(id: playlistID).entry
        let ids = Self.entryIDs(entries.map { $0.id ?? "" })
        return zip(entries, ids).compactMap { entry, entryID in
            guard var track = entry.asTrack() else { return nil }
            track.playlistEntryID = entryID
            return track
        }
    }

    func playlistAnswer(id: ItemID) async throws -> SubsonicPlaylist {
        guard let playlist = try await call("getPlaylist", [URLQueryItem(name: "id", value: id)], timeout: 60).playlist
        else { throw MusicServerError.notFound }
        return playlist
    }

    /// The playlist's song ids as they are now, every place counted (also
    /// one that is not a song the kit reads: positions are the server's).
    func playlistSongIDs(_ id: ItemID) async throws -> [ItemID] {
        try await playlistAnswer(id: id).entry.map { $0.id ?? "" }
    }

    /// createPlaylist with the songs (API 1.14.0+ answers with the
    /// playlist, measured on Navidrome); more than one GET takes go in one
    /// form POST where the server lists `formPost`, else the first 100 here
    /// and the rest added after. Before 1.14.0 the answer is empty: the
    /// newest playlist of that name is the one. An unknown song id is
    /// dropped by the server (measured).
    @discardableResult
    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        let post = trackIDs.count > SubsonicConnection.idsPerRequest ? await postsForms() : false
        let first = post ? trackIDs : Array(trackIDs.prefix(SubsonicConnection.idsPerRequest))
        let body = try await call("createPlaylist", [URLQueryItem(name: "name", value: name)]
            + first.map { URLQueryItem(name: "songId", value: $0) }, post: post)
        var id = body.playlist?.id.flatMap { $0.isEmpty ? nil : $0 }
        if id == nil {
            let named = (try await call("getPlaylists").playlists?.playlist ?? []).filter { $0.name == name }
            id = named.max { ($0.created.flatMap(JellyfinDate.parse) ?? .distantPast)
                < ($1.created.flatMap(JellyfinDate.parse) ?? .distantPast) }?.id
        }
        guard let id else { throw MusicServerError.decoding("the new playlist has no id") }
        try await update(id, adding: Array(trackIDs.dropFirst(first.count)), removing: [], forms: post)
        return id
    }

    /// updatePlaylist songIdToAdd, at the end, in order, duplicates kept
    /// (measured: A B C A + D A → A B C A D A).
    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        try await update(playlistID, adding: trackIDs, removing: [])
    }

    /// The playlist read again, each entry found there, and updatePlaylist
    /// songIndexToRemove with their positions. The positions count in the
    /// list before the change (measured: removing 0 and 2 of A B C A D A
    /// left B A D A).
    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        guard !entryIDs.isEmpty else { return }
        let songs = try await playlistSongIDs(playlistID)
        try await update(playlistID, adding: [], removing: Self.positions(of: entryIDs, in: songs))
    }

    /// The playlist read again, the move made in the list, and its changed
    /// part written again: every place from the first one the move touches
    /// is removed and the songs from there on added back in the new order,
    /// in one updatePlaylist where it fits (a move near the end of a long
    /// playlist sends a few songs, not all of them). Measured on Navidrome
    /// 0.64.2: removals and additions in one request apply the removals
    /// first (A B C D E, remove 1 and 3, add X: A C E X); a server that
    /// adds first ends the same, as the additions go after every place
    /// removed. `index` is the place the entry ends up in, as on Jellyfin
    /// (measured on 12.4: A to 2 in A B C D gives B C A D) and as
    /// PlaylistsView sends it. An entry the playlist no longer has is
    /// .notFound.
    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        var songs = try await playlistSongIDs(playlistID)
        guard let from = Self.positions(of: [entryID], in: songs).first else { throw MusicServerError.notFound }
        let to = min(max(0, index), songs.count - 1)
        guard from != to else { return }
        let count = songs.count
        songs.insert(songs.remove(at: from), at: to)
        let first = min(from, to)
        try await update(playlistID, adding: Array(songs[first...]), removing: Array(first..<count))
    }

    /// deletePlaylist; an unknown id is 70 (measured): .notFound.
    public func deletePlaylist(id: ItemID) async throws {
        _ = try await call("deletePlaylist", [URLQueryItem(name: "id", value: id)])
    }

    /// One updatePlaylist where it fits in a GET (100 ids and positions), or
    /// in a form POST where the server lists `formPost` (Navidrome does).
    /// Otherwise several, the additions first and then the removals,
    /// highest first: the positions are the list's before the change, the
    /// additions go after all of them, and a request lost on the way leaves
    /// a song twice, never one gone. (Writing the whole list again, as an
    /// earlier version moved, lost every song after the first 100 when the
    /// second request failed.) `forms`: whether the server takes a form
    /// POST, when the caller knows already.
    func update(_ playlistID: ItemID, adding ids: [ItemID], removing positions: [Int],
                forms: Bool? = nil) async throws {
        guard !ids.isEmpty || !positions.isEmpty else { return }
        func query(_ ids: [ItemID], _ positions: [Int]) -> [URLQueryItem] {
            [URLQueryItem(name: "playlistId", value: playlistID)]
                + positions.map { URLQueryItem(name: "songIndexToRemove", value: String($0)) }
                + ids.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        }
        if ids.count + positions.count <= SubsonicConnection.idsPerRequest {
            _ = try await call("updatePlaylist", query(ids, positions))
            return
        }
        let post: Bool
        if let forms { post = forms } else { post = await postsForms() }
        if post {
            _ = try await call("updatePlaylist", query(ids, positions), timeout: 60, post: true)
            return
        }
        for chunk in SubsonicConnection.chunks(ids) { _ = try await call("updatePlaylist", query(chunk, [])) }
        for chunk in SubsonicConnection.chunks(positions.sorted(by: >)) {
            _ = try await call("updatePlaylist", query([], chunk))
        }
    }

    /// Whether the server takes a form POST (OpenSubsonic's `formPost`):
    /// asked only for a list too long for one GET (2 ms on Navidrome).
    func postsForms() async -> Bool {
        await connection.extensions().contains("formPost")
    }

    // MARK: Playlist entries

    /// "<songID>#<n>" for each place: n counts the song's earlier places.
    static func entryIDs(_ songIDs: [ItemID]) -> [String] {
        var count: [ItemID: Int] = [:]
        return songIDs.map { id in
            let n = count[id, default: 0]
            count[id] = n + 1
            return "\(id)#\(n)"
        }
    }

    /// The song and the occurrence an entry id names; an id without "#n"
    /// is a song's first place.
    static func parse(entryID: String) -> (song: ItemID, occurrence: Int) {
        if let mark = entryID.lastIndex(of: "#"), let n = Int(entryID[entryID.index(after: mark)...]), n >= 0 {
            return (String(entryID[..<mark]), n)
        }
        return (entryID, 0)
    }

    /// Where each entry is in the playlist as it is now, each place once:
    /// the n-th place of its song; if the song has fewer places now (the
    /// list changed elsewhere), its last place not already taken; nothing
    /// if the song is gone (skipped, as Jellyfin skips an unknown entry).
    static func positions(of entryIDs: [String], in songIDs: [ItemID]) -> [Int] {
        var places: [ItemID: [Int]] = [:]
        for (i, id) in songIDs.enumerated() where !id.isEmpty { places[id, default: []].append(i) }
        var taken = Set<Int>()
        var result: [Int] = []
        var asked = Set<String>()
        for entryID in entryIDs where asked.insert(entryID).inserted {
            let (song, n) = parse(entryID: entryID)
            guard let list = places[song] else { continue }
            let chosen = n < list.count && !taken.contains(list[n]) ? list[n] : list.last { !taken.contains($0) }
            if let chosen, taken.insert(chosen).inserted { result.append(chosen) }
        }
        return result
    }

    // MARK: What only the server knows

    /// getArtistInfo2's similar artists, the ones in the library. From
    /// Last.fm on the server: Navidrome without its agents answers `{}`
    /// (measured), which is an empty list here.
    public func similarArtists(artistID: ItemID, limit: Int) async throws -> [Artist] {
        let body = try await call("getArtistInfo2", [
            URLQueryItem(name: "id", value: artistID),
            URLQueryItem(name: "count", value: String(max(1, limit))),
            URLQueryItem(name: "includeNotPresent", value: "false"),
        ], lacking: .similarArtists)
        let artists = (body.artistInfo2?.similarArtist ?? []).compactMap { $0.asArtist() }.filter { $0.id != artistID }
        return Array(artists.prefix(max(1, limit)))
    }

    /// A song or album: getSimilarSongs (it takes either); an artist:
    /// getSimilarSongs2; a playlist: its first song's; a genre:
    /// getRandomSongs in that genre, by name. Navidrome without agents mixes
    /// by genre: a jazz song's 20 were all jazz (measured).
    public func instantMix(from seed: MixSeed, limit: Int) async throws -> [Track] {
        let count = String(max(1, limit))
        let body: SubsonicBody
        switch seed {
        case let .track(id), let .album(id):
            body = try await call("getSimilarSongs", [URLQueryItem(name: "id", value: id),
                                                      URLQueryItem(name: "count", value: count)], lacking: .instantMix)
        case let .artist(id):
            body = try await call("getSimilarSongs2", [URLQueryItem(name: "id", value: id),
                                                       URLQueryItem(name: "count", value: count)], lacking: .instantMix)
        case let .playlist(id):
            guard let first = try await playlistSongIDs(id).first(where: { !$0.isEmpty }) else { return [] }
            return try await instantMix(from: .track(first), limit: limit)
        case let .genre(name, _):
            // getRandomSongs' size is at most 500 (the spec).
            body = try await call("getRandomSongs", [URLQueryItem(name: "genre", value: name),
                                                     URLQueryItem(name: "size", value: String(min(500, max(1, limit))))],
                                  lacking: .instantMix)
        }
        return Array((body.songs?.song ?? []).compactMap { $0.asTrack() }.prefix(max(1, limit)))
    }

    /// getTopSongs by name (the classic call needs `artist`), with the id
    /// too for a server with `topSongsByArtistId` (Navidrome; a server
    /// without it ignores it). From Last.fm on the server: Navidrome
    /// without agents answers `{}` (measured both ways).
    public func topSongs(of artist: ArtistRef, limit: Int) async throws -> [Track] {
        var query = [URLQueryItem(name: "artist", value: artist.name),
                     URLQueryItem(name: "count", value: String(max(1, limit)))]
        if let id = artist.id, !id.isEmpty { query.append(URLQueryItem(name: "id", value: id)) }
        let body = try await call("getTopSongs", query, lacking: .topSongs)
        return (body.songs?.song ?? []).compactMap { $0.asTrack() }
    }

    /// OpenSubsonic's getLyricsBySongId where the server has `songLyrics`
    /// (timed lines); otherwise the classic getLyrics, by artist and title,
    /// plain text. None: Navidrome answers `lyricsList: {}` and
    /// `lyrics: {value: ""}` (measured), nil here.
    public func lyrics(for track: Track) async throws -> Lyrics? {
        if capabilities.contains(.syncedLyrics) {
            do {
                let body = try await call("getLyricsBySongId", [URLQueryItem(name: "id", value: track.id)],
                                          lacking: .syncedLyrics)
                return body.lyricsList?.asLyrics()
            } catch MusicServerError.unsupported {
                // Listed but not there: the classic call.
            }
        }
        var query = [URLQueryItem(name: "title", value: track.name)]
        if let artist = track.artists.first?.name ?? track.albumArtist?.name {
            query.insert(URLQueryItem(name: "artist", value: artist), at: 0)
        }
        return try await call("getLyrics", query, lacking: .lyrics).lyrics?.asLyrics()
    }

    // MARK: Playing

    /// What AVPlayer cannot play as it is, by Subsonic's `suffix`: asked for
    /// as MP3 even at `.original`, since nothing else converts it.
    static let unplayable: Set<String> = ["ogg", "oga", "opus", "spx", "wma", "ape", "wv", "mpc", "tta", "tak",
                                         "dsf", "dff", "mka", "webm"]

    static func cannotPlay(_ track: Track) -> Bool {
        track.container.map { unplayable.contains($0.lowercased()) } ?? false
    }

    /// The MP3 a capped stream or download asks for: `maxBitRate` in kbit/s
    /// and `format=mp3`.
    static func mp3(kbps: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "maxBitRate", value: String(kbps)), URLQueryItem(name: "format", value: "mp3")]
    }

    /// `stream?id=` with the credentials (AVPlayer sends no headers). With a
    /// cap: `maxBitRate=<kbit/s>&format=mp3`. Navidrome sends the file when
    /// it is under the cap, like Jellyfin, but converts to Ogg Opus when
    /// only `maxBitRate` is given (measured), which AVPlayer cannot play;
    /// MP3 is the format every Subsonic server converts to. No
    /// `estimateContentLength`: Navidrome's guess was 49 397 bytes for 48 499
    /// sent (measured). `playSessionID` is Jellyfin's; Subsonic has none.
    ///
    /// `.original` says `format=raw` (the API's "no conversion", since
    /// 1.9.0): without a format a server converts by its player settings,
    /// which Airsonic's are by default for FLAC; Navidrome sends the file
    /// either way (200 with Content-Length and Accept-Ranges: bytes,
    /// measured).
    public func streamURL(for track: Track, quality: StreamQuality, playSessionID: String) -> URL {
        var query = [URLQueryItem(name: "id", value: track.id)]
        if let bitrate = quality.maxBitrate {
            query += Self.mp3(kbps: bitrate / 1000)
        } else if Self.cannotPlay(track) {
            query += Self.mp3(kbps: 320)
        } else {
            query.append(URLQueryItem(name: "format", value: "raw"))
        }
        return connection.url("stream", query)
    }

    /// A song's file to save on the phone (docs/OFFLINE.md), a plain file
    /// a background download fetches with no headers:
    /// - `.original`: `download?id=`, the file as it is (the spec: "without
    ///   transcoding or downsampling"); for a format AVPlayer cannot play,
    ///   the MP3 at 320 that `.original` streams.
    /// - `.high`, `.normal`: `stream?id=&maxBitRate=256` / `128` with
    ///   `format=mp3`.
    ///
    /// Measured on Navidrome 0.64.2 (9 November 2026, curl with no header,
    /// one mono file of each kind from the test library: MP3 129 kbit/s
    /// 97 196 bytes, FLAC 97 kbit/s 69 347, M4A AAC 126 kbit/s 80 892):
    /// - `download`: each file byte for byte, 200 with its own type
    ///   (audio/mpeg, audio/flac, audio/mp4), Content-Length, Accept-Ranges:
    ///   bytes — resumable.
    /// - `format=mp3`: the MP3 as itself at 256 (it is under the cap) and
    ///   re-encoded at 128 (129 is over it; 96 779 bytes, 6.03 s); the FLAC
    ///   as MP3 at the cap (161 541 bytes at 256, 80 875 at 128: these
    ///   sine tones are smaller as FLAC than any MP3, a real FLAC is
    ///   800–1000 kbit/s); the M4A as MP3 at 128 at both (Navidrome caps a
    ///   lossy file's conversion at its own rate). Every conversion 200
    ///   audio/mpeg, CBR, a duration ffprobe reads within 0.05 s, chunked
    ///   with no Content-Length (no total for progress, not resumable); a
    ///   second request for one already made had a Content-Length.
    /// - `format=aac` is ADTS (audio/aac): AVPlayer plays it, but an ADTS
    ///   file says nothing of its length, and ffprobe made 6.42 s of the
    ///   6.03 s MP3's and 5.41 s of the 5.00 s M4A's (8% off), a scrubber
    ///   that would be as wrong. And not every Subsonic server converts to
    ///   AAC; every one converts to MP3, which streaming uses too.
    /// - `format=m4a` is no conversion Navidrome has: the MP3 and the FLAC
    ///   came as Ogg Opus (audio/ogg), which AVPlayer cannot play.
    /// - Downloads turned off (ND_ENABLEDOWNLOADS=false): `download` is 200
    ///   with a JSON error 50 "downloads are disabled", `stream` converts
    ///   as before — so it is `downloadsAllowed()` that keeps to what the
    ///   admin said, as on Jellyfin.
    /// - An unknown id: 200, application/json, error 70; no credentials:
    ///   error 10. A JSON answer is never audio.
    public func downloadURL(for track: Track, quality: DownloadQuality) -> URL {
        let id = URLQueryItem(name: "id", value: track.id)
        switch quality {
        case .original where Self.cannotPlay(track): return connection.url("stream", [id] + Self.mp3(kbps: 320))
        case .original: return connection.url("download", [id])
        case .high: return connection.url("stream", [id] + Self.mp3(kbps: 256))
        case .normal: return connection.url("stream", [id] + Self.mp3(kbps: 128))
        }
    }

    /// getUser's `downloadRole` for the signed-in user (Navidrome 0.64.2:
    /// true, and false with ND_ENABLEDOWNLOADS=false, measured). True when
    /// the answer does not say, or the server has no getUser (404), as
    /// Jellyfin's is when its policy does not say: the download itself
    /// then tells. Other errors are thrown; the app keeps what it knew.
    public func downloadsAllowed() async throws -> Bool {
        let user = credentials.userName.isEmpty ? credentials.userID : credentials.userName
        do {
            let body = try await call("getUser", [URLQueryItem(name: "username", value: user)], timeout: 15)
            return body.user?.downloadRole ?? true
        } catch MusicServerError.unsupported {
            return true
        }
    }

    /// `getCoverArt?id=<the coverArt id, else the item's>&size=` with the
    /// credentials (it needs them: without, error 10, measured). Album
    /// covers come back "public, max-age=31536000, immutable"; an unknown
    /// id answers 200 with JSON, which the image view reads as no image.
    public func artworkURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        let id = artwork.tag.flatMap { $0.isEmpty ? nil : $0 } ?? artwork.itemID
        return connection.url("getCoverArt", [URLQueryItem(name: "id", value: id),
                                              URLQueryItem(name: "size", value: String(max(1, maxPixelSize)))])
    }

    /// The app's moments (docs/SERVERS.md, "Playback reports"): the play
    /// counts at `.played`, with `scrobble submission=true`, and only then;
    /// the timeline (OpenSubsonic's `playbackReport`) goes with
    /// `ignoreScrobble=true`, so Navidrome's own rule (more than half heard,
    /// measured) never counts a second one. Measured: starting and playing
    /// with ignoreScrobble, then the scrobble, then stopped at the end:
    /// exactly one play. Errors are swallowed: a missed report must never
    /// stop the music.
    public func report(_ event: PlaybackEvent, _ report: PlaybackReport) async {
        guard !connection.auth.isEmpty else { return }
        let timeline = capabilities.contains(.playbackTimeline)
        switch event {
        case .nowPlaying:
            if timeline {
                await send("reportPlayback", playback(report, state: "starting"))
                await send("reportPlayback", playback(report, state: "playing"))
            } else {
                await send("scrobble", [URLQueryItem(name: "id", value: report.trackID),
                                        URLQueryItem(name: "submission", value: "false")])
            }
        case .played:
            let began = (Date().timeIntervalSince1970 - max(0, report.position)) * 1000
            await send("scrobble", [URLQueryItem(name: "id", value: report.trackID),
                                    URLQueryItem(name: "submission", value: "true"),
                                    URLQueryItem(name: "time", value: String(Int64(began.rounded())))])
        case .progress:
            if timeline { await send("reportPlayback", playback(report, state: report.isPaused ? "paused" : "playing")) }
        case .stopped:
            if timeline { await send("reportPlayback", playback(report, state: "stopped")) }
        }
    }

    func playback(_ report: PlaybackReport, state: String) -> [URLQueryItem] {
        [URLQueryItem(name: "mediaId", value: report.trackID),
         URLQueryItem(name: "mediaType", value: "song"),
         URLQueryItem(name: "state", value: state),
         URLQueryItem(name: "positionMs", value: String(Int64((max(0, report.position) * 1000).rounded()))),
         URLQueryItem(name: "ignoreScrobble", value: "true")]
    }

    func send(_ endpoint: String, _ query: [URLQueryItem]) async {
        _ = try? await call(endpoint, query, timeout: 15)
    }
}

extension ServerCapability {
    /// Questions for the sign-in screen, not the session: they are not in
    /// a signed-in server's capabilities (as `jellyfin` has no Quick Connect).
    static let signingInOnly: Set<ServerCapability> = [.quickConnect, .apiKeySignIn]
}
