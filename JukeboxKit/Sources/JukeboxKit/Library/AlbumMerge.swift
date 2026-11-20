// One album that the server lists twice, put back together.
//
// Jellyfin and Navidrome split an album by its album artist: when a few of
// its files say "Jack Johnson, Jack Johnson" and the rest "Jack Johnson",
// Recently Added shows "From Here To Now To You" twice (the photographer,
// 20 November 2026; the same for "Stoned and Dethroned" and "Portraits").
// The tags are his to fix; this is the safety net he chose ("ik volg wat je
// aanraad"), applied once where the library is loaded, so every client and
// every list (Albums, Recently Added, an artist's, search, the radio and
// the mixes) sees one album.
//
// The rule is careful on purpose: the same title (trimmed, any case), the
// same first album artist (the part before ", ", " & ", " feat" or ";", any
// case), and the same year where both parts have one. "Deluxe" and other
// editions have another title and stay apart; so do two artists' albums of
// one name, and two years of one title.

import Foundation

public enum AlbumMerge {
    /// The albums with each split album once, in the place of its first
    /// part, and the tracks with the other parts' album ids turned into the
    /// kept one's, so the album's page, play, shuffle, the queue, downloads
    /// and the album's radio all take every part. Nothing changes (and
    /// nothing is copied) when nothing is split.
    public static func merge(albums: [Album], tracks: [Track]) -> (albums: [Album], tracks: [Track]) {
        var groups: [String: [Int]] = [:]
        var order: [String] = []
        for (i, album) in albums.enumerated() {
            guard let key = key(album) else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(i)
        }

        var replaced: [ItemID: ItemID] = [:]
        var mergedAt: [Int: Album] = [:]
        var dropped = Set<Int>()
        for key in order {
            guard let positions = groups[key], positions.count > 1 else { continue }
            for cluster in byYear(positions, in: albums) where cluster.count > 1 {
                let parts = cluster.map { albums[$0] }
                let whole = combine(parts)
                mergedAt[cluster[0]] = whole
                for position in cluster.dropFirst() { dropped.insert(position) }
                for part in parts where part.id != whole.id { replaced[part.id] = whole.id }
            }
        }
        guard !replaced.isEmpty else { return (albums, tracks) }
        let coverTag = Dictionary(mergedAt.values.map { ($0.id, $0.imageTag) }, uniquingKeysWith: { a, _ in a })

        var outAlbums: [Album] = []
        outAlbums.reserveCapacity(albums.count - dropped.count)
        for (i, album) in albums.enumerated() where !dropped.contains(i) {
            outAlbums.append(mergedAt[i] ?? album)
        }
        let outTracks = tracks.map { track -> Track in
            guard let id = track.albumID, let kept = replaced[id] else { return track }
            var moved = track
            moved.albumID = kept
            // The cover's tag goes with the album id it is asked under.
            moved.albumImageTag = coverTag[kept] ?? nil
            return moved
        }
        return (outAlbums, outTracks)
    }

    /// Title and first album artist, folded; nil for an album without one
    /// of them, which is never merged.
    static func key(_ album: Album) -> String? {
        let title = fold(album.name)
        let artist = firstArtist(album.artistLine)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return title + "\u{1F}" + artist
    }

    /// "jack johnson" from "Jack Johnson, Jack Johnson" and from "Jack
    /// Johnson feat. G. Love".
    static func firstArtist(_ line: String) -> String {
        var first = fold(line)
        for separator in [", ", " & ", " feat", ";"] {
            if let range = first.range(of: separator) { first = String(first[..<range.lowerBound]) }
        }
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: nil)
    }

    /// Parts of one title and artist that may be one album: all of them when
    /// they name at most one year between them; else one group per year,
    /// and a part without a year stays alone, since it could be either.
    static func byYear(_ positions: [Int], in albums: [Album]) -> [[Int]] {
        let years = Set(positions.compactMap { albums[$0].year })
        guard years.count > 1 else { return [positions] }
        var byYear: [Int: [Int]] = [:]
        for position in positions {
            if let year = albums[position].year { byYear[year, default: []].append(position) }
        }
        return byYear.values.sorted { $0[0] < $1[0] }
    }

    /// The parts as one album. Its id, and so its favourite and its stars,
    /// is the primary part's: a part that is a favourite first (so the heart
    /// he set stays and can be taken off again), then one with a cover, then
    /// the one with the most tracks. Its artists are the cleanest part's,
    /// the shortest name ("Jack Johnson", not "Jack Johnson, Jack Johnson").
    /// Dates: added as the newest part, so Recently Added puts it where the
    /// latest files are; played as the last part played.
    static func combine(_ parts: [Album]) -> Album {
        let primary = parts.max { a, b in
            (a.isFavorite ? 1 : 0, a.imageTag == nil ? 0 : 1, a.trackCount ?? 0)
                < (b.isFavorite ? 1 : 0, b.imageTag == nil ? 0 : 1, b.trackCount ?? 0)
        } ?? parts[0]
        let cleanest = parts.min { $0.artistLine.count < $1.artistLine.count } ?? primary
        var whole = primary
        whole.artists = cleanest.artists
        whole.year = primary.year ?? parts.lazy.compactMap(\.year).first
        var genres: [String] = []
        for genre in parts.flatMap(\.genres) where !genres.contains(genre) { genres.append(genre) }
        whole.genres = genres
        let counts = parts.compactMap(\.trackCount)
        whole.trackCount = counts.isEmpty ? nil : counts.reduce(0, +)
        let durations = parts.compactMap(\.duration)
        whole.duration = durations.isEmpty ? nil : durations.reduce(0, +)
        whole.dateAdded = parts.compactMap(\.dateAdded).max()
        whole.playCount = parts.reduce(0) { $0 + $1.playCount }
        whole.lastPlayed = parts.compactMap(\.lastPlayed).max()
        // Every id the album had, also those merged on an earlier load.
        let ids = parts.flatMap { [$0.id] + ($0.mergedIDs ?? []) }.filter { $0 != whole.id }
        whole.mergedIDs = ids
        return whole
    }
}
