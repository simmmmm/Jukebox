// Who sounds like whom, from the library alone (docs/RADIO.md, "The graph").
// Three kinds of evidence, combined as independent ones are (noisy-or:
// 1 − (1 − a)(1 − b)(1 − c)):
//
// - genres in common, weighted by how specific they are: two artists who
//   are both "Shoegaze" are far more alike than two who are both "Rock".
//   A weighted Jaccard of their genre shares (IDF weights), times a
//   confidence that grows with the specificity they share. At most 0.6:
//   tags are weaker evidence than Last.fm's listeners.
// - guests: an artist on another's record (0.45 for one track together, up
//   to 0.65 for three or more), when the two share some genre; 40% of that
//   when they share none. With shared genres on top it is the strongest
//   edge the library has.
// - era, only between artists who share a genre: up to 0.15 for the same
//   median year, nothing beyond ten years apart.
//
// Each artist keeps its 30 strongest; an edge stays when either end keeps
// it, so the graph stays symmetric.

import Foundation

extension SimilarityGraph {
    static let libraryNeighbors = 30
    /// The specificity at which shared genres are fully trusted: a genre one
    /// artist in twenty has (ln(1 + 20)).
    static let trustedSpecificity = log(21.0)

    static func build(from snapshot: LibrarySnapshot) -> SimilarityGraph {
        let index = snapshot.index
        let artists = index.artistCount
        var graph = SimilarityGraph()
        guard artists > 1 else { return graph }

        // Each artist's genre shares, over their own records (a guest spot is
        // someone else's record, and its genre is theirs); an artist who is
        // only ever a guest, over those.
        var shares = [[(genre: Int, share: Double)]](repeating: [], count: artists)
        var mass = [Double](repeating: 0, count: artists)
        var genreArtists = [[(artist: Int, share: Double)]](repeating: [], count: index.genreCount)
        for a in 0..<artists {
            var counts: [Int: Int] = [:]
            var total = 0
            let records = index.artistOwnTracks[a].isEmpty ? index.artistTracks[a] : index.artistOwnTracks[a]
            for t in records where index.trackArtists[t].contains(a) {
                total += 1
                for g in index.trackGenres[t] { counts[g, default: 0] += 1 }
            }
            guard total > 0 else { continue }
            let list = counts.map { (genre: $0.key, share: Double($0.value) / Double(total)) }
                .sorted { $0.genre < $1.genre }
            shares[a] = list
            for item in list {
                mass[a] += index.genreIDF[item.genre] * item.share
                genreArtists[item.genre].append((a, item.share))
            }
        }

        // Guests: who appears on whose tracks, and how often.
        var guests = [[Int: Int]](repeating: [:], count: artists)
        for t in 0..<index.trackCount {
            let own = index.trackArtists[t]
            guard own.count > 1 else { continue }
            let main = own[0]
            for guest in own.dropFirst() where guest != main {
                guests[main][guest, default: 0] += 1
                guests[guest][main, default: 0] += 1
            }
        }

        // Every artist's candidates: those sharing a genre (through the
        // inverted index, so each artist meets only its genre-mates) and its
        // guests.
        var numerator = [Double](repeating: 0, count: artists)
        var touched: [Int] = []
        var kept = [[(artist: Int, weight: Double)]](repeating: [], count: artists)
        for a in 0..<artists {
            touched.removeAll(keepingCapacity: true)
            for item in shares[a] {
                let idf = index.genreIDF[item.genre]
                for other in genreArtists[item.genre] where other.artist != a {
                    if numerator[other.artist] == 0 { touched.append(other.artist) }
                    numerator[other.artist] += idf * min(item.share, other.share)
                }
            }
            for b in guests[a].keys where numerator[b] == 0 { touched.append(b) }

            var candidates: [(artist: Int, weight: Double)] = []
            candidates.reserveCapacity(touched.count)
            for b in touched {
                let shared = numerator[b]
                numerator[b] = 0
                var genreSimilarity = 0.0
                var era = 0.0
                if shared > 0 {
                    let union = mass[a] + mass[b] - shared
                    let jaccard = union > 0 ? shared / union : 0
                    let confidence = min(1, shared / trustedSpecificity)
                    genreSimilarity = jaccard * confidence
                    let ya = index.artistYear[a], yb = index.artistYear[b]
                    if ya > 0, yb > 0 {
                        let apart = Double(abs(ya - yb))
                        if apart < 10 { era = 0.15 * (1 - apart / 10) * min(1, 2 * confidence) }
                    }
                }
                // A guest spot between artists who share no genre is a
                // friendship more than a likeness: 40% of its weight, rising to
                // all of it from a genre similarity of 0.25. Without this, on
                // the test server Velvet Static Radio played house and Signal
                // Dream Radio played classical, by way of guests.
                var guest = 0.0
                if let together = guests[a][b] {
                    guest = min(0.65, 0.35 + 0.1 * Double(together)) * (0.4 + 0.6 * min(1, genreSimilarity / 0.25))
                }
                let weight = 1 - (1 - 0.6 * genreSimilarity) * (1 - guest) * (1 - era)
                if weight >= 0.03, weight.isFinite { candidates.append((b, weight)) }
            }
            candidates.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.artist < $1.artist }
            kept[a] = Array(candidates.prefix(libraryNeighbors))
        }

        for a in 0..<artists {
            for edge in kept[a] {
                graph.setArtistEdge(index.artistKeys[a], index.artistKeys[edge.artist], weight: edge.weight)
            }
        }
        return graph
    }

    /// Both ways, the heavier kept; not counted as enriched.
    mutating func setArtistEdge(_ a: String, _ b: String, weight: Double) {
        guard a != b, !a.isEmpty, !b.isEmpty, weight.isFinite, weight > 0 else { return }
        let w = min(1, weight)
        if (artistEdges[a]?[b] ?? 0) < w { artistEdges[a, default: [:]][b] = w }
        if (artistEdges[b]?[a] ?? 0) < w { artistEdges[b, default: [:]][a] = w }
    }

    static func sorted(_ edges: [String: Double]?, limit: Int) -> [Neighbor] {
        guard let edges, limit > 0 else { return [] }
        let all = edges.map { Neighbor(key: $0.key, weight: $0.value) }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.key < $1.key }
        return Array(all.prefix(limit))
    }
}

// MARK: - On disk, and for building on

extension SimilarityGraph {
    enum CodingKeys: String, CodingKey {
        case artistEdges = "artists"
        case trackEdges = "tracks"
        case enriched
    }

    /// Lenient: a cache missing a part (an older one) opens with that part
    /// empty rather than not at all.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        artistEdges = try container.decodeIfPresent([String: [String: Double]].self, forKey: .artistEdges) ?? [:]
        trackEdges = try container.decodeIfPresent([ItemID: [ItemID: Double]].self, forKey: .trackEdges) ?? [:]
        enriched = try container.decodeIfPresent(Set<String>.self, forKey: .enriched) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(artistEdges, forKey: .artistEdges)
        try container.encode(trackEdges, forKey: .trackEdges)
        try container.encode(enriched.sorted(), forKey: .enriched)
    }

    /// The edge between two artists, 0 when there is none.
    public func weight(_ a: String, _ b: String) -> Double {
        artistEdges[a]?[b] ?? 0
    }

    /// Every artist with at least one edge, sorted.
    public var artistKeys: [String] { artistEdges.keys.sorted() }

    /// Whether Last.fm (or anything else through `addArtistEdge`) has been
    /// asked about this artist.
    public func isEnriched(_ key: String) -> Bool { enriched.contains(key) }
}
