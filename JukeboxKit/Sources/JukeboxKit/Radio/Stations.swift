// A station's name, id and covers, from its seed and the library
// (Station(seed:snapshot:)). Ids are stable — the same seed is the same
// station tomorrow — so the app can remember a station's dial and history.

import Foundation

extension Station {
    /// The id a seed's station has: "artist-radiohead", "decade-1990".
    public static func id(for seed: StationSeed) -> String {
        switch seed {
        case let .track(id): "track-\(id)"
        case let .artist(key, _, _): "artist-\(key)"
        case let .album(id): "album-\(id)"
        case let .genre(key, _): "genre-\(key)"
        case let .decade(year): "decade-\(year)"
        case let .collection(id, _, _): "collection-\(id)"
        case .personal: "personal"
        case .discovery: "discovery"
        case .favorites: "favorites"
        }
    }

    static func describe(_ seed: StationSeed, in snapshot: LibrarySnapshot) -> (title: String, subtitle: String?, artwork: [Artwork]) {
        let index = snapshot.index
        let tracks = snapshot.tracks
        switch seed {
        case let .track(id):
            guard let t = index.trackByID[id] else { return ("Song Radio", nil, []) }
            let names = index.trackArtists[t].map { index.artistRefs[$0].name }
            let line = names.isEmpty ? tracks[t].artistLine : names.joined(separator: ", ")
            return ("\(tracks[t].name) Radio", line.isEmpty ? nil : line, tracks[t].artwork.map { [$0] } ?? [])

        case let .artist(key, name, _):
            let a = index.artistByKey[key] ?? snapshot.matchArtist(name).flatMap { index.artistByKey[$0] }
            let shown = a.map { index.artistRefs[$0].name } ?? name
            let own = a.map { index.artistOwnTracks[$0].isEmpty ? index.artistTracks[$0] : index.artistOwnTracks[$0] } ?? []
            return ("\(shown) Radio", "\(shown) and artists like them", covers(of: own, snapshot))

        case let .album(id):
            guard let al = index.albumByID[id], let first = index.albumTracks[al].first else {
                return ("Album Radio", nil, [])
            }
            let track = tracks[first]
            let artist = index.trackArtists[first].first.map { index.artistRefs[$0].name } ?? track.albumArtist?.name
            return ("\(track.albumName ?? "Album") Radio", artist, track.artwork.map { [$0] } ?? [])

        case let .genre(key, name):
            let g = index.genreByKey[key] ?? index.genreByKey[NameKey.genre(name)]
            let shown = g.map { index.genreNames[$0] } ?? name
            return ("\(shown) Radio", "\(shown) from your library", covers(of: g.map { index.genreTracks[$0] } ?? [], snapshot))

        case let .decade(year):
            return ("\(year)s Radio", "The \(year)s in your library", covers(of: index.decadeTracks[year] ?? [], snapshot))

        case let .collection(_, name, trackIDs):
            let members = trackIDs.compactMap { index.trackByID[$0] }
            return ("\(name) Radio", "Songs like \(name)", covers(of: members, snapshot, inOrder: true))

        case .personal:
            let liked = (0..<tracks.count).filter { tracks[$0].isFavorite || tracks[$0].playCount > 0 }
            return ("Your Station", "What you love, and more like it", covers(of: liked, snapshot))

        case .discovery:
            let unheard = (0..<tracks.count).filter { tracks[$0].playCount == 0 && !tracks[$0].isFavorite }
            return ("Discovery", "New to you, near what you love", covers(of: unheard, snapshot, newestFirst: true))

        case .favorites:
            let loved = (0..<tracks.count).filter { tracks[$0].isFavorite }
            return ("Loved", "Your favourites, and songs like them", covers(of: loved, snapshot))
        }
    }

    /// Up to four covers of different albums: the most loved and played
    /// first (or the playlist's own order, or the newest), each album once.
    static func covers(of members: [Int], _ snapshot: LibrarySnapshot, inOrder: Bool = false,
                       newestFirst: Bool = false) -> [Artwork] {
        let index = snapshot.index
        let tracks = snapshot.tracks
        var albums: [Int: (score: Double, first: Int)] = [:]
        var loose: [Int] = []
        for (rank, t) in members.enumerated() {
            let track = tracks[t]
            let score: Double
            if inOrder {
                score = -Double(rank)
            } else if newestFirst {
                score = track.dateAdded?.timeIntervalSinceReferenceDate ?? 0
            } else {
                score = (track.isFavorite ? 3 : 0) + log2(1 + Double(max(0, track.playCount)))
            }
            let album = index.trackAlbum[t]
            if album < 0 {
                loose.append(t)
                continue
            }
            if let known = albums[album] {
                albums[album] = (inOrder ? known.score : known.score + score, known.first)
            } else {
                albums[album] = (score, t)
            }
        }
        let ordered = albums.sorted { x, y in
            x.value.score != y.value.score ? x.value.score > y.value.score : x.value.first < y.value.first
        }
        var out: [Artwork] = []
        var seen = Set<Artwork>()
        for (_, value) in ordered {
            if let art = tracks[value.first].artwork, seen.insert(art).inserted { out.append(art) }
            if out.count == 4 { return out }
        }
        for t in loose {
            if let art = tracks[t].artwork, seen.insert(art).inserted { out.append(art) }
            if out.count == 4 { break }
        }
        return out
    }
}
