// CONTRACT — signatures fixed; bodies the library agent's (docs/ARCHITECTURE.md).
//
// The whole library in memory: every track, album, artist, playlist and
// genre, from the disk cache at once and then from the server. Screens read
// from here, not from the server, so lists open without a spinner and the
// radio and the mixes see everything. Changes the listener makes (a
// favourite, a playlist) go to the server and are mirrored here at once.
//
// How it is kept: the five arrays below are the one copy of each item;
// LibraryIndex (built off the main actor, with the LibrarySnapshot) holds
// positions into them. A favourite or a play changes one element in place,
// so every list, the hearts and the next snapshot agree without a reload.

import Foundation
import JukeboxKit
import Observation

@Observable
final class LibraryStore {
    enum LoadState: Equatable {
        case empty
        /// Loading from the server; `progress` 0 … 1 when known. The cached
        /// library, if any, is shown meanwhile.
        case loading(progress: Double?)
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .empty
    private(set) var tracks: [Track] = []
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var playlists: [Playlist] = []
    /// The library's genres as the snapshot splits them ("Rock" and
    /// "Shoegaze", not the server's "Rock; Shoegaze"), by name, each with
    /// the server's id when it has a genre of exactly that name and
    /// "genre:" + key when not (LibraryIndex.libraryGenres).
    private(set) var genres: [Genre] = []
    /// The index the radio and the mixes work from; rebuilt off the main
    /// actor when `tracks` changes.
    private(set) var snapshot: LibrarySnapshot = .empty
    private(set) var lastLoaded: Date?
    private(set) var client: JellyfinClient?

    /// Favourite tracks, albums and artists by id: what every heart reads,
    /// changed at once when one is tapped.
    private var favoriteIDs: Set<ItemID> = []
    /// Positions into the arrays above; replaced together with them.
    private var index = LibraryIndex()

    @ObservationIgnored private var credentials: Credentials?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    /// Bumped by `open` and `reset`: a load that ends after a sign-out (or
    /// after signing in as someone else) is dropped, not shown.
    @ObservationIgnored private var generation = 0

    init() {}

    /// Signed in: the cache at once, then the server.
    func open(client: JellyfinClient, credentials: Credentials) async {
        let started = Date()
        if let previous = self.credentials,
           previous.serverID != credentials.serverID || previous.userID != credentials.userID {
            clearLibrary()
        }
        generation += 1
        let generation = self.generation
        loadTask?.cancel()
        loadTask = nil
        self.client = client
        self.credentials = credentials

        let url = Self.cacheURL(for: credentials)
        let cached = await Task.detached(priority: .userInitiated) { () -> (CachedLibrary, LibraryIndex)? in
            guard let library = LibraryCache.load(from: url) else { return nil }
            let built = LibraryIndex(tracks: library.tracks, albums: library.albums,
                                     artists: library.artists, genres: library.genres)
            return (library, built)
        }.value
        guard generation == self.generation else { return }

        if let cached {
            let (library, built) = cached
            apply(tracks: library.tracks, albums: library.albums, artists: library.artists,
                  playlists: library.playlists, index: built)
            lastLoaded = library.savedAt
            state = .loaded
            // How large, from where and how quickly (Stats): buckets only.
            Stats.track(.libraryLoaded, ["tracks": Stats.trackCount(library.tracks.count), "from": "cache", "seconds": Stats.duration(Date().timeIntervalSince(started))])
            // The server behind the cache, without holding up the caller:
            // Home's mixes and the radio start from the cache at once, and
            // `lastLoaded` changes when the fresh library is in.
            startLoad(generation: generation)
            return
        }
        // First launch on this server: nothing to show until the server
        // answers, so the caller (and Home's mixes) wait for it.
        await refresh()
    }

    /// Everything again from the server (pull to refresh, and a launch).
    func refresh() async {
        guard client != nil else { return }
        if let loadTask {
            await loadTask.value
            return
        }
        startLoad(generation: generation)
        await loadTask?.value
    }

    /// Signed out: forget everything.
    func reset() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        // "Forget everything": the cached library goes too.
        if let credentials {
            let url = Self.cacheURL(for: credentials)
            Task.detached(priority: .utility) { _ = try? FileManager.default.removeItem(at: url) }
        }
        credentials = nil
        client = nil
        clearLibrary()
    }

    // MARK: Lookups (instant, from memory)

    func album(id: ItemID) -> Album? { item(index.albumPosition[id], in: albums) }
    func artist(id: ItemID) -> Artist? { item(index.artistPosition[id], in: artists) }

    /// The artist by a track's or album's reference: by id, else by name.
    func artist(_ ref: ArtistRef) -> Artist? {
        if let id = ref.id, let found = artist(id: id) { return found }
        return item(index.artistByKey[ref.key], in: artists)
    }

    func genre(named name: String) -> Genre? { item(index.genreByKey[NameKey.genre(name)], in: genres) }
    func track(id: ItemID) -> Track? { item(index.trackPosition[id], in: tracks) }

    /// In disc and track order.
    func tracks(inAlbum albumID: ItemID) -> [Track] { items(index.albumTracks[albumID], in: tracks) }

    /// Newest first.
    func albums(by artist: Artist) -> [Album] { items(index.artistAlbums[artist.key], in: albums) }

    /// Albums the artist is a guest on, but not the album artist of.
    func appearances(of artist: Artist) -> [Album] {
        let key = artist.key
        var seen = Set<ItemID>()
        var result: [Album] = []
        for track in items(index.artistTracks[key], in: tracks) {
            guard let albumID = track.albumID, seen.insert(albumID).inserted,
                  let found = album(id: albumID),
                  !found.artists.contains(where: { $0.key == key }) else { continue }
            result.append(found)
        }
        return result.sorted(by: LibraryIndex.newestFirst)
    }

    /// The artist's tracks, most played first (the listener's own top songs).
    func topTracks(by artist: Artist, limit: Int = 10) -> [Track] {
        let all = tracks(by: artist)
        // Ties (nothing played yet, the usual first week) keep the newest
        // album's order, so the list is never a random draw.
        let ranked = all.indices.sorted { a, b in
            let x = all[a], y = all[b]
            if x.playCount != y.playCount { return x.playCount > y.playCount }
            let fx = favoriteIDs.contains(x.id), fy = favoriteIDs.contains(y.id)
            if fx != fy { return fx }
            let lx = x.lastPlayed ?? .distantPast, ly = y.lastPlayed ?? .distantPast
            if lx != ly { return lx > ly }
            return a < b
        }
        return ranked.prefix(max(0, limit)).map { all[$0] }
    }

    func tracks(by artist: Artist) -> [Track] { items(index.artistTracks[artist.key], in: tracks) }
    func albums(inGenre genre: Genre) -> [Album] { items(index.genreAlbums[genre.key], in: albums) }
    func tracks(inGenre genre: Genre) -> [Track] { items(index.genreTracks[genre.key], in: tracks) }

    var favoriteTracks: [Track] {
        favoriteIDs.compactMap { track(id: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var favoriteAlbums: [Album] {
        favoriteIDs.compactMap { album(id: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var favoriteArtists: [Artist] {
        favoriteIDs.compactMap { artist(id: $0) }
            .sorted { LibraryIndex.sortKey($0.name) < LibraryIndex.sortKey($1.name) }
    }

    /// Newest first.
    var recentlyAddedAlbums: [Album] { items(index.albumOrders[.recentlyAdded], in: albums) }

    /// Albums with a track played most recently first (Jellyfin's last-played dates).
    var recentlyPlayedAlbums: [Album] {
        var latest: [ItemID: Date] = [:]
        for album in albums {
            if let date = album.lastPlayed { latest[album.id] = date }
        }
        for track in tracks {
            guard let date = track.lastPlayed, let albumID = track.albumID else { continue }
            if let known = latest[albumID], known >= date { continue }
            latest[albumID] = date
        }
        return latest.sorted { $0.value > $1.value }.compactMap { album(id: $0.key) }
    }

    /// Search the library in memory: names that start with or contain
    /// `term`, by NameKey-like folding, best first, `limit` of each kind.
    func search(_ term: String, limit: Int = 25) -> SearchResults {
        SearchResults(artists: matchingArtists(term, limit: limit),
                      albums: matchingAlbums(term, limit: limit),
                      tracks: matchingTracks(term, limit: limit),
                      playlists: matchingPlaylists(term, limit: limit))
    }

    // MARK: Changes (to the server, mirrored here)

    func isFavorite(_ itemID: ItemID) -> Bool { favoriteIDs.contains(itemID) }

    /// Track, album or artist.
    func setFavorite(_ isFavorite: Bool, itemID: ItemID) async {
        let was = favoriteIDs.contains(itemID)
        guard was != isFavorite else { return }
        // At once, before the server answers: a heart that waits for the
        // network feels broken. Put back if the server says no.
        mirrorFavorite(isFavorite, itemID: itemID)
        guard let client else {
            mirrorFavorite(was, itemID: itemID)
            return
        }
        do {
            try await client.setFavorite(isFavorite, itemID: itemID)
            // What kind of thing, never which (Stats).
            Stats.track(.favoriteSet, ["item": favoriteKind(of: itemID), "on": isFavorite])
            // The radio's taste reads favourites from the snapshot.
            scheduleSnapshotRebuild(after: 2)
        } catch {
            mirrorFavorite(was, itemID: itemID)
        }
    }

    func toggleFavorite(_ itemID: ItemID) async {
        await setFavorite(!isFavorite(itemID), itemID: itemID)
    }

    /// A playlist's tracks, from the server (playlists change elsewhere too).
    func tracks(in playlist: Playlist) async throws -> [Track] {
        guard let client else { throw JellyfinError.notSignedIn }
        let entries = try await client.playlistTracks(playlistID: playlist.id)
        let count = entries.count
        let total = entries.reduce(0) { $0 + $1.duration }
        updatePlaylist(playlist.id) { playlist in
            playlist.trackCount = count
            playlist.duration = total
        }
        return entries
    }

    @discardableResult
    func createPlaylist(named name: String, with tracks: [Track]) async throws -> Playlist {
        guard let client else { throw JellyfinError.notSignedIn }
        let id = try await client.createPlaylist(name: name, trackIDs: tracks.map(\.id))
        let total = tracks.reduce(0) { $0 + $1.duration }
        let playlist = Playlist(id: id, name: name, trackCount: tracks.count, duration: total, dateAdded: Date())
        playlists.append(playlist)
        playlists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return playlist
    }

    func add(_ tracks: [Track], to playlist: Playlist) async throws {
        guard let client else { throw JellyfinError.notSignedIn }
        guard !tracks.isEmpty else { return }
        try await client.addToPlaylist(playlistID: playlist.id, trackIDs: tracks.map(\.id))
        let count = tracks.count
        let added = tracks.reduce(0) { $0 + $1.duration }
        updatePlaylist(playlist.id) { playlist in
            playlist.trackCount = (playlist.trackCount ?? 0) + count
            playlist.duration = (playlist.duration ?? 0) + added
        }
    }

    /// `tracks` as `tracks(in:)` gave them, with their playlist entry ids.
    func remove(_ tracks: [Track], from playlist: Playlist) async throws {
        guard let client else { throw JellyfinError.notSignedIn }
        let entryIDs = tracks.compactMap(\.playlistEntryID)
        guard !entryIDs.isEmpty else { return }
        try await client.removeFromPlaylist(playlistID: playlist.id, entryIDs: entryIDs)
        let count = entryIDs.count
        let removed = tracks.reduce(0) { $0 + $1.duration }
        updatePlaylist(playlist.id) { playlist in
            playlist.trackCount = max(0, (playlist.trackCount ?? count) - count)
            playlist.duration = max(0, (playlist.duration ?? removed) - removed)
        }
    }

    func move(_ track: Track, in playlist: Playlist, to index: Int) async throws {
        guard let client else { throw JellyfinError.notSignedIn }
        guard let entryID = track.playlistEntryID else { throw JellyfinError.notFound }
        try await client.movePlaylistEntry(playlistID: playlist.id, entryID: entryID, to: index)
    }

    func delete(_ playlist: Playlist) async throws {
        guard let client else { throw JellyfinError.notSignedIn }
        try await client.deletePlaylist(id: playlist.id)
        playlists.removeAll { $0.id == playlist.id }
    }

    /// A track's play count and last-played date after a play, without
    /// asking the server.
    func notePlayed(_ trackID: ItemID, at date: Date) {
        guard let i = index.trackPosition[trackID], tracks.indices.contains(i) else { return }
        tracks[i].playCount += 1
        tracks[i].lastPlayed = date
        if let albumID = tracks[i].albumID, let a = index.albumPosition[albumID], albums.indices.contains(a) {
            albums[a].lastPlayed = date
        }
        // Not after every song: a snapshot of a large library is a moment's
        // work, and the radio only needs it roughly current.
        scheduleSnapshotRebuild(after: 30)
    }
}

// MARK: - Beyond the contract, for the library's screens

extension LibraryStore {
    /// Songs: every track by title.
    var songsByTitle: [Track] { items(index.tracksByTitle, in: tracks) }

    /// Artists: alphabetical, a leading "The" ignored.
    var artistsByName: [Artist] { items(index.artistsByName, in: artists) }

    func albums(sortedBy sort: LibraryAlbumSort) -> [Album] { items(index.albumOrders[sort], in: albums) }

    func trackCount(inGenre genre: Genre) -> Int { index.genreTracks[genre.key]?.count ?? 0 }

    /// Whether any of the artist's songs has been played or is a favorite:
    /// until then `topTracks` is only the newest album's order, and the
    /// artist's page calls them Songs, not Top Songs.
    func hasPlaysOrFavorites(by artist: Artist) -> Bool {
        guard let positions = index.artistTracks[artist.key] else { return false }
        return positions.contains { i in
            tracks.indices.contains(i) && (tracks[i].playCount > 0 || favoriteIDs.contains(tracks[i].id))
        }
    }

    /// The server's name, for "Loading the music on …".
    var serverName: String? { credentials?.serverName }

    /// Nothing to list yet: the first load, an error before it, or an empty server.
    var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }

    /// Filtering a long list: the same ranking as search, more of it.
    func matchingTracks(_ term: String, limit: Int = 500) -> [Track] {
        items(LibraryIndex.matches(index.trackNames, secondary: index.trackArtistNames, term: term, limit: limit),
              in: tracks)
    }

    func matchingAlbums(_ term: String, limit: Int = 500) -> [Album] {
        items(LibraryIndex.matches(index.albumNames, secondary: index.albumArtistNames, term: term, limit: limit),
              in: albums)
    }

    func matchingArtists(_ term: String, limit: Int = 500) -> [Artist] {
        items(LibraryIndex.matches(index.artistNames, term: term, limit: limit), in: artists)
    }

    func matchingPlaylists(_ term: String, limit: Int = 500) -> [Playlist] {
        let names = playlists.map { LibraryIndex.fold($0.name) }
        return items(LibraryIndex.matches(names, term: term, limit: limit), in: playlists)
    }
}

// MARK: - Loading

private extension LibraryStore {
    func startLoad(generation: Int) {
        let task = Task { await self.load(generation: generation) }
        loadTask = task
    }

    func load(generation: Int) async {
        // However this ends, the next refresh starts a new load, unless a
        // sign-out or another sign-in has already replaced this one.
        defer {
            if generation == self.generation { loadTask = nil }
        }
        guard let client else { return }
        let started = Date()
        state = .loading(progress: nil)
        // Every page of tracks moves the bar: they are most of the wait.
        let progress: @Sendable (Int, Int) -> Void = { done, total in
            guard total > 0 else { return }
            let fraction = min(1, Double(done) / Double(total))
            Task { @MainActor in self.noteProgress(fraction, generation: generation) }
        }
        do {
            async let fetchedTracks = client.allTracks(progress: progress)
            async let fetchedAlbums = LibraryStore.allAlbums(client)
            async let fetchedArtists = LibraryStore.allArtists(client)
            async let fetchedPlaylists = client.playlists()
            // The server's genres only lend their ids and images to the
            // library's own split list (LibraryIndex): without them the
            // library still loads, with the ids the genres already had.
            async let fetchedGenres = try? await client.genres()
            let (newTracks, newAlbums, newArtists, newPlaylists, newGenres) =
                try await (fetchedTracks, fetchedAlbums, fetchedArtists, fetchedPlaylists, fetchedGenres)
            guard generation == self.generation else { return }

            let serverGenres = newGenres ?? genres
            let built = await Task.detached(priority: .userInitiated) {
                LibraryIndex(tracks: newTracks, albums: newAlbums, artists: newArtists, genres: serverGenres)
            }.value
            guard generation == self.generation else { return }

            apply(tracks: newTracks, albums: newAlbums, artists: newArtists,
                  playlists: newPlaylists, index: built)
            lastLoaded = Date()
            state = .loaded
            Stats.track(.libraryLoaded, ["tracks": Stats.trackCount(newTracks.count), "from": "server", "seconds": Stats.duration(Date().timeIntervalSince(started))])
            saveCache()
        } catch {
            guard generation == self.generation else { return }
            // The cached library stays on screen; the message says why it
            // may be out of date.
            state = .failed(error.localizedDescription)
        }
    }

    func noteProgress(_ fraction: Double, generation: Int) {
        // A page's report can arrive after the load has ended: only while
        // loading does it move the bar.
        guard generation == self.generation, case .loading = state else { return }
        state = .loading(progress: fraction)
    }

    /// Albums come in pages: a large library has thousands.
    static func allAlbums(_ client: JellyfinClient) async throws -> [Album] {
        var albums: [Album] = []
        while true {
            let page = try await client.albums(AlbumQuery(sort: .name, start: albums.count, limit: 1000))
            albums += page.items
            if page.items.isEmpty || albums.count >= page.totalCount { return albums }
        }
    }

    static func allArtists(_ client: JellyfinClient) async throws -> [Artist] {
        var artists: [Artist] = []
        while true {
            let page = try await client.artists(start: artists.count, limit: 1000)
            artists += page.items
            if page.items.isEmpty || artists.count >= page.totalCount { return artists }
        }
    }

    func apply(tracks: [Track], albums: [Album], artists: [Artist], playlists: [Playlist],
               index built: LibraryIndex) {
        // Arrays and index in one go: the index's positions are into these.
        // The genres are the index's own (split, sorted): its genreByKey
        // points into that list.
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
        self.playlists = playlists.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.genres = built.genres
        index = built
        favoriteIDs = built.favoriteIDs
        snapshot = built.snapshot
    }

    func clearLibrary() {
        state = .empty
        tracks = []
        albums = []
        artists = []
        playlists = []
        genres = []
        index = LibraryIndex()
        favoriteIDs = []
        snapshot = .empty
        lastLoaded = nil
    }

    func saveCache() {
        guard let credentials else { return }
        let url = Self.cacheURL(for: credentials)
        let library = CachedLibrary(savedAt: lastLoaded ?? Date(), tracks: tracks, albums: albums,
                                    artists: artists, playlists: playlists, genres: genres)
        Task.detached(priority: .utility) { _ = try? LibraryCache.save(library, to: url) }
    }

    static func cacheURL(for credentials: Credentials) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return LibraryCache.url(in: caches.appendingPathComponent("Jukebox", isDirectory: true),
                                serverID: credentials.serverID, userID: credentials.userID)
    }

    // MARK: Small changes

    /// A favourite's kind, for the usage counts: "track", "album" or "artist".
    func favoriteKind(of itemID: ItemID) -> String {
        if index.trackPosition[itemID] != nil { return "track" }
        if index.albumPosition[itemID] != nil { return "album" }
        return "artist"
    }

    func mirrorFavorite(_ isFavorite: Bool, itemID: ItemID) {
        if isFavorite { favoriteIDs.insert(itemID) } else { favoriteIDs.remove(itemID) }
        if let i = index.trackPosition[itemID], tracks.indices.contains(i) {
            tracks[i].isFavorite = isFavorite
        } else if let i = index.albumPosition[itemID], albums.indices.contains(i) {
            albums[i].isFavorite = isFavorite
        } else if let i = index.artistPosition[itemID], artists.indices.contains(i) {
            artists[i].isFavorite = isFavorite
        }
    }

    func updatePlaylist(_ id: ItemID, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        var playlist = playlists[i]
        change(&playlist)
        if playlist != playlists[i] { playlists[i] = playlist }
    }

    /// A new snapshot from the tracks as they are now, a while after the
    /// last small change, unless a full load is under way (it makes one).
    func scheduleSnapshotRebuild(after seconds: Double) {
        snapshotTask?.cancel()
        let generation = self.generation
        snapshotTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, generation == self.generation, self.loadTask == nil else { return }
            let current = self.tracks
            let rebuilt = await Task.detached(priority: .utility) { LibrarySnapshot(tracks: current) }.value
            guard !Task.isCancelled, generation == self.generation, self.loadTask == nil else { return }
            self.snapshot = rebuilt
            self.saveCache()
        }
    }

    // MARK: Positions to items

    func item<T>(_ position: Int?, in array: [T]) -> T? {
        guard let position, array.indices.contains(position) else { return nil }
        return array[position]
    }

    func items<T>(_ positions: [Int]?, in array: [T]) -> [T] {
        guard let positions else { return [] }
        return positions.compactMap { array.indices.contains($0) ? array[$0] : nil }
    }
}
