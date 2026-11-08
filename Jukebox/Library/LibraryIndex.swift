// The library's lookups, made once per load off the main actor from the
// arrays LibraryStore holds: where each item is, an album's tracks in disc
// order, an artist's albums and tracks, a genre's, the orders the long lists
// sort by, and the folded names search runs over. Everything is a position
// into LibraryStore's arrays rather than a copy, so a change to one track
// (a favourite, a play) is made in one place and every list sees it.
//
// `nonisolated`: the app's types are on the main actor by default, and this
// is built in a detached task so a library of tens of thousands of tracks
// never holds up a scroll.

import Foundation
import JukeboxKit

/// The orders Albums can be sorted in (its toolbar's menu).
nonisolated enum LibraryAlbumSort: String, CaseIterable, Identifiable, Sendable {
    case title
    case artist
    case year
    case recentlyAdded

    var id: String { rawValue }
}

nonisolated struct LibraryIndex: Sendable {
    var trackPosition: [ItemID: Int] = [:]
    var albumPosition: [ItemID: Int] = [:]
    var artistPosition: [ItemID: Int] = [:]
    /// An artist by NameKey, for a reference without an id (a guest Jellyfin
    /// knows only by name).
    var artistByKey: [String: Int] = [:]
    var genreByKey: [String: Int] = [:]
    /// Track positions by album id, in disc and track order.
    var albumTracks: [ItemID: [Int]] = [:]
    /// Album positions by album-artist key, newest first.
    var artistAlbums: [String: [Int]] = [:]
    /// Track positions by every artist key on the track (performers and
    /// album artist), newest album first, then disc and track.
    var artistTracks: [String: [Int]] = [:]
    /// Track positions by genre key, by artist, then album, then disc.
    var genreTracks: [String: [Int]] = [:]
    /// Album positions by genre key: the album's own genres and its tracks'.
    var genreAlbums: [String: [Int]] = [:]
    var tracksByTitle: [Int] = []
    var albumOrders: [LibraryAlbumSort: [Int]] = [:]
    var artistsByName: [Int] = []
    var favoriteIDs: Set<ItemID> = []
    var snapshot: LibrarySnapshot = .empty

    // Folded once here, so a search is a scan of plain strings.
    var trackNames: [String] = []
    var trackArtistNames: [String] = []
    var albumNames: [String] = []
    var albumArtistNames: [String] = []
    var artistNames: [String] = []

    init() {}

    init(tracks: [Track], albums: [Album], artists: [Artist], genres: [Genre]) {
        snapshot = LibrarySnapshot(tracks: tracks)

        albumNames.reserveCapacity(albums.count)
        albumArtistNames.reserveCapacity(albums.count)
        for (i, album) in albums.enumerated() {
            albumPosition[album.id] = i
            if album.isFavorite { favoriteIDs.insert(album.id) }
            for key in Set(album.artists.map(\.key)) { artistAlbums[key, default: []].append(i) }
            albumNames.append(Self.fold(album.name))
            albumArtistNames.append(Self.fold(album.artistLine))
        }

        artistNames.reserveCapacity(artists.count)
        for (i, artist) in artists.enumerated() {
            artistPosition[artist.id] = i
            // Two spellings that fold to one key: the first one Jellyfin
            // listed stands for both.
            if artistByKey[artist.key] == nil { artistByKey[artist.key] = i }
            if artist.isFavorite { favoriteIDs.insert(artist.id) }
            artistNames.append(Self.fold(artist.name))
        }

        for (i, genre) in genres.enumerated() where genreByKey[genre.key] == nil {
            genreByKey[genre.key] = i
        }

        // An album's genres as Jellyfin has them on the album, and those of
        // its tracks: a file's tags often say more than the album does.
        var albumsOfGenre: [String: Set<Int>] = [:]
        for (i, album) in albums.enumerated() {
            for key in album.genres.map(NameKey.genre) { albumsOfGenre[key, default: []].insert(i) }
        }

        trackNames.reserveCapacity(tracks.count)
        trackArtistNames.reserveCapacity(tracks.count)
        for (i, track) in tracks.enumerated() {
            trackPosition[track.id] = i
            if track.isFavorite { favoriteIDs.insert(track.id) }
            var albumIndex: Int?
            if let albumID = track.albumID {
                albumTracks[albumID, default: []].append(i)
                albumIndex = albumPosition[albumID]
            }
            for key in track.artistKeys { artistTracks[key, default: []].append(i) }
            for key in Set(track.genres.map(NameKey.genre)) {
                genreTracks[key, default: []].append(i)
                if let albumIndex { albumsOfGenre[key, default: []].insert(albumIndex) }
            }
            trackNames.append(Self.fold(track.name))
            trackArtistNames.append(Self.fold(track.artistLine))
        }

        // Sort keys once, so the sorts below compare plain strings.
        let trackTitleKeys = tracks.map { Self.sortKey($0.name) }
        let trackArtistKeys = tracks.map { Self.sortKey($0.primaryArtist?.name ?? "") }
        let albumTitleKeys = albums.map { Self.sortKey($0.name) }
        let albumArtistKeys = albums.map { Self.sortKey($0.primaryArtist?.name ?? "") }

        albumTracks = albumTracks.mapValues { positions in
            positions.sorted { Self.inDiscOrder(tracks[$0], tracks[$1]) }
        }
        artistAlbums = artistAlbums.mapValues { positions in
            positions.sorted { Self.newestFirst(albums[$0], albums[$1]) }
        }
        artistTracks = artistTracks.mapValues { positions in
            positions.sorted { Self.newestAlbumThenDisc(tracks[$0], tracks[$1]) }
        }
        genreTracks = genreTracks.mapValues { positions in
            positions.sorted { a, b in
                if trackArtistKeys[a] != trackArtistKeys[b] { return trackArtistKeys[a] < trackArtistKeys[b] }
                let ya = tracks[a].year ?? 0, yb = tracks[b].year ?? 0
                if ya != yb { return ya < yb }
                if tracks[a].albumID != tracks[b].albumID {
                    return (tracks[a].albumName ?? "", tracks[a].albumID ?? "") < (tracks[b].albumName ?? "", tracks[b].albumID ?? "")
                }
                return Self.inDiscOrder(tracks[a], tracks[b])
            }
        }
        genreAlbums = albumsOfGenre.mapValues { positions in
            positions.sorted { a, b in
                if albumArtistKeys[a] != albumArtistKeys[b] { return albumArtistKeys[a] < albumArtistKeys[b] }
                let ya = albums[a].year ?? 0, yb = albums[b].year ?? 0
                if ya != yb { return ya < yb }
                return albumTitleKeys[a] < albumTitleKeys[b]
            }
        }

        tracksByTitle = Array(tracks.indices).sorted { a, b in
            if trackTitleKeys[a] != trackTitleKeys[b] { return trackTitleKeys[a] < trackTitleKeys[b] }
            return trackArtistKeys[a] < trackArtistKeys[b]
        }

        let albumIndices = Array(albums.indices)
        albumOrders[.title] = albumIndices.sorted { a, b in
            if albumTitleKeys[a] != albumTitleKeys[b] { return albumTitleKeys[a] < albumTitleKeys[b] }
            return albumArtistKeys[a] < albumArtistKeys[b]
        }
        albumOrders[.artist] = albumIndices.sorted { a, b in
            if albumArtistKeys[a] != albumArtistKeys[b] { return albumArtistKeys[a] < albumArtistKeys[b] }
            let ya = albums[a].year ?? 0, yb = albums[b].year ?? 0
            if ya != yb { return ya < yb }
            return albumTitleKeys[a] < albumTitleKeys[b]
        }
        albumOrders[.year] = albumIndices.sorted { a, b in
            // Newest first; an album without a year at the end.
            let ya = albums[a].year ?? Int.min, yb = albums[b].year ?? Int.min
            if ya != yb { return ya > yb }
            return albumTitleKeys[a] < albumTitleKeys[b]
        }
        albumOrders[.recentlyAdded] = albumIndices.sorted { a, b in
            let da = albums[a].dateAdded ?? .distantPast, db = albums[b].dateAdded ?? .distantPast
            if da != db { return da > db }
            return albumTitleKeys[a] < albumTitleKeys[b]
        }

        let artistKeys = artists.map { Self.sortKey($0.name) }
        artistsByName = Array(artists.indices).sorted { artistKeys[$0] < artistKeys[$1] }
    }

    // MARK: Orders

    static func inDiscOrder(_ a: Track, _ b: Track) -> Bool {
        let da = a.discNumber ?? 1, db = b.discNumber ?? 1
        if da != db { return da < db }
        let ta = a.trackNumber ?? Int.max, tb = b.trackNumber ?? Int.max
        if ta != tb { return ta < tb }
        return a.name < b.name
    }

    /// By year, newest first; an album without a year after those with one.
    static func newestFirst(_ a: Album, _ b: Album) -> Bool {
        switch (a.year, b.year) {
        case let (.some(x), .some(y)) where x != y: return x > y
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        let da = a.dateAdded ?? .distantPast, db = b.dateAdded ?? .distantPast
        if da != db { return da > db }
        return a.name < b.name
    }

    /// An artist's tracks as their albums come, newest album first.
    static func newestAlbumThenDisc(_ a: Track, _ b: Track) -> Bool {
        let ya = a.year ?? 0, yb = b.year ?? 0
        if ya != yb { return ya > yb }
        if a.albumID != b.albumID {
            return (a.albumName ?? "", a.albumID ?? "") < (b.albumName ?? "", b.albumID ?? "")
        }
        return inDiscOrder(a, b)
    }

    // MARK: Names

    /// Lower case, without diacritics: "Beyoncé" is found by "beyonce".
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The name a list sorts by: folded and without a leading "The", as
    /// Music files "The Beatles" under B.
    static func sortKey(_ s: String) -> String {
        var key = fold(s).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("the ") { key.removeFirst(4) }
        return key
    }

    /// The letter of a list's section: A to Z, else "#".
    static func sectionLetter(_ s: String) -> String {
        guard let first = sortKey(s).first, first.isASCII, first.isLetter else { return "#" }
        return String(first).uppercased()
    }

    // MARK: Search

    /// Positions of the names matching `term`, best first: the name starts
    /// with it, then a word in it does, then it is somewhere in it; then the
    /// same for `secondary` (a track's or an album's artist), after every
    /// match of the name itself. Shorter names first within a rank: "Kid A"
    /// before "Kid A Mnesia" for "kid a".
    static func matches(_ names: [String], secondary: [String]? = nil, term: String, limit: Int) -> [Int] {
        let needle = fold(term).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }
        var hits: [(rank: Int, length: Int, position: Int)] = []
        for (i, name) in names.enumerated() {
            if let found = Self.rank(name, needle) {
                hits.append((found, name.utf8.count, i))
            } else if let secondary, secondary.indices.contains(i), let found = Self.rank(secondary[i], needle) {
                hits.append((found + 3, name.utf8.count, i))
            }
        }
        hits.sort { ($0.rank, $0.length, $0.position) < ($1.rank, $1.length, $1.position) }
        return hits.prefix(limit).map { $0.position }
    }

    private static func rank(_ name: String, _ needle: String) -> Int? {
        if name.hasPrefix(needle) { return 0 }
        guard name.range(of: needle) != nil else { return nil }
        if name.range(of: " " + needle) != nil { return 1 }
        return 2
    }
}
