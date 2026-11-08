// CONTRACT — signatures fixed; bodies the library agent's (docs/ARCHITECTURE.md).
//
// The whole library in memory: every track, album, artist, playlist and
// genre, from the disk cache at once and then from the server. Screens read
// from here, not from the server, so lists open without a spinner and the
// radio and the mixes see everything. Changes the listener makes (a
// favourite, a playlist) go to the server and are mirrored here at once.

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
    private(set) var genres: [Genre] = []
    /// The index the radio and the mixes work from; rebuilt off the main
    /// actor when `tracks` changes.
    private(set) var snapshot: LibrarySnapshot = .empty
    private(set) var lastLoaded: Date?
    private(set) var client: JellyfinClient?

    init() {}

    /// Signed in: the cache at once, then the server.
    func open(client: JellyfinClient, credentials: Credentials) async {
        fatalError("not built yet")
    }

    /// Everything again from the server (pull to refresh, and a launch).
    func refresh() async {
        fatalError("not built yet")
    }

    /// Signed out: forget everything.
    func reset() {
        fatalError("not built yet")
    }

    // MARK: Lookups (instant, from memory)

    func album(id: ItemID) -> Album? { fatalError("not built yet") }
    func artist(id: ItemID) -> Artist? { fatalError("not built yet") }
    /// The artist by a track's or album's reference: by id, else by name.
    func artist(_ ref: ArtistRef) -> Artist? { fatalError("not built yet") }
    func genre(named name: String) -> Genre? { fatalError("not built yet") }
    func track(id: ItemID) -> Track? { fatalError("not built yet") }

    /// In disc and track order.
    func tracks(inAlbum albumID: ItemID) -> [Track] { fatalError("not built yet") }
    /// Newest first.
    func albums(by artist: Artist) -> [Album] { fatalError("not built yet") }
    /// Albums the artist is a guest on, but not the album artist of.
    func appearances(of artist: Artist) -> [Album] { fatalError("not built yet") }
    /// The artist's tracks, most played first (the listener's own top songs).
    func topTracks(by artist: Artist, limit: Int = 10) -> [Track] { fatalError("not built yet") }
    func tracks(by artist: Artist) -> [Track] { fatalError("not built yet") }
    func albums(inGenre genre: Genre) -> [Album] { fatalError("not built yet") }
    func tracks(inGenre genre: Genre) -> [Track] { fatalError("not built yet") }

    var favoriteTracks: [Track] { fatalError("not built yet") }
    var favoriteAlbums: [Album] { fatalError("not built yet") }
    var favoriteArtists: [Artist] { fatalError("not built yet") }
    /// Newest first.
    var recentlyAddedAlbums: [Album] { fatalError("not built yet") }
    /// Albums with a track played most recently first (Jellyfin's last-played dates).
    var recentlyPlayedAlbums: [Album] { fatalError("not built yet") }

    /// Search the library in memory: names that start with or contain
    /// `term`, by NameKey-like folding, best first, `limit` of each kind.
    func search(_ term: String, limit: Int = 25) -> SearchResults { fatalError("not built yet") }

    // MARK: Changes (to the server, mirrored here)

    func isFavorite(_ itemID: ItemID) -> Bool { fatalError("not built yet") }
    /// Track, album or artist.
    func setFavorite(_ isFavorite: Bool, itemID: ItemID) async { fatalError("not built yet") }
    func toggleFavorite(_ itemID: ItemID) async { fatalError("not built yet") }

    /// A playlist's tracks, from the server (playlists change elsewhere too).
    func tracks(in playlist: Playlist) async throws -> [Track] { fatalError("not built yet") }
    @discardableResult
    func createPlaylist(named name: String, with tracks: [Track]) async throws -> Playlist { fatalError("not built yet") }
    func add(_ tracks: [Track], to playlist: Playlist) async throws { fatalError("not built yet") }
    /// `tracks` as `tracks(in:)` gave them, with their playlist entry ids.
    func remove(_ tracks: [Track], from playlist: Playlist) async throws { fatalError("not built yet") }
    func move(_ track: Track, in playlist: Playlist, to index: Int) async throws { fatalError("not built yet") }
    func delete(_ playlist: Playlist) async throws { fatalError("not built yet") }

    /// A track's play count and last-played date after a play, without
    /// asking the server.
    func notePlayed(_ trackID: ItemID, at date: Date) { fatalError("not built yet") }
}
