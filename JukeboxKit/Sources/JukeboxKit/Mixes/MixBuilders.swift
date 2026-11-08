// How each of Home's mixes is made; the numbers that chose the constants
// are printed by MixesEvaluationTests (lines starting MIXES-EVAL). Each
// builder returns its mix, or nothing when it would have fewer than eight
// tracks, with how much the listener would want it today ("want", 0 … 1),
// by which the mixes after the daily ones are ordered. The wants are a
// judgement, not a measurement: what the listener plays now first (On
// Repeat 0.9), then the new (0.85), the loved (0.75), the forgotten (0.7),
// the unheard of liked artists (0.65), genres (0.6) and decades (0.55),
// each times how much there is to it.

import Foundation

extension MixModel {
    struct Made {
        var mix: Mix
        var want: Double
    }

    static let minimumTracks = 8

    /// A Mix from tracks in their order. Its id is kind, key and day; its
    /// station, unless another fits better, plays on from its own tracks.
    func make(_ kind: MixKind, key: String? = nil, title: String, tracks: [Int], lead: [Int] = [],
              coverOrder: [Int]? = nil, station: StationSeed? = nil) -> Mix? {
        guard tracks.count >= Self.minimumTracks else { return nil }
        let id = ([kind.rawValue] + (key.map { [$0] } ?? []) + [day]).joined(separator: "-")
        let ids = tracks.map { snapshot.tracks[$0].id }
        return Mix(id: id, kind: kind, title: title, subtitle: artistLine(tracks, lead: lead),
                   tracks: tracks.map { snapshot.tracks[$0] }, artwork: covers(coverOrder ?? tracks),
                   stationSeed: station ?? .collection(id: id, name: title, trackIDs: ids))
    }

    // MARK: - Daily Mix 1 … 6

    /// The artists the listener plays, in clusters of who sounds like whom,
    /// one mix each, biggest liking first.
    static let dailyArtists = 48
    static let maxClusterSize = 8
    /// The average graph weight two clusters need to be one: about what two
    /// artists who share their main genre and nothing else get from the
    /// library alone (0.20), less a margin; artists of different genres
    /// get 0 … 0.1 unless Last.fm or a guest spot says otherwise.
    static let clusterLinkage = 0.12
    static let dailyLength = 35
    static let dailyFamiliarShare = 0.6
    static let dailyMinimum = 15

    func dailyMixes() -> [Mix] {
        let clusters = artistClusters()
        var mixes: [Mix] = []
        var used = Set<Int>()
        for cluster in clusters {
            if mixes.count == 6 { break }
            guard let mix = dailyMix(cluster, number: mixes.count + 1, used: &used) else { continue }
            mixes.append(mix)
        }
        return mixes
    }

    /// Average-linkage clustering of the listener's top artists by the
    /// graph's weights, each cluster at most `maxClusterSize` artists, the
    /// clusters by the liking they hold, biggest first. A listener Jukebox
    /// knows nothing of yet gets the library's biggest artists instead.
    func artistClusters() -> [(artists: [Int], weight: Double)] {
        var pool: [Int] = []
        var weight: [Double] = []
        for a in rankedArtists where artistAffinity[a] > 0.05 && !index.artistOwnTracks[a].isEmpty {
            pool.append(a)
            weight.append(artistAffinity[a])
            if pool.count == Self.dailyArtists { break }
        }
        if pool.count < 8 {
            // Little or nothing heard: the biggest artists stand in, a little
            // weight each, so what was liked still leads.
            let maxOwn = Double(max(1, index.artistOwnTracks.map(\.count).max() ?? 1))
            let inPool = Set(pool)
            let biggest = (0..<index.artistCount).filter {
                !inPool.contains($0) && index.artistOwnTracks[$0].count >= 3 && artistAffinity[$0] >= 0
            }.sorted { x, y in
                let cx = index.artistOwnTracks[x].count, cy = index.artistOwnTracks[y].count
                return cx != cy ? cx > cy : index.artistKeys[x] < index.artistKeys[y]
            }
            for a in biggest.prefix(40 - pool.count) {
                pool.append(a)
                weight.append(0.02 + 0.03 * Double(index.artistOwnTracks[a].count) / maxOwn)
            }
        }
        let m = pool.count
        guard m > 0 else { return [] }

        // How alike two artists are for a mix: the graph's weight, scaled by
        // how alike their genres are (0.4 for none in common, all of it for
        // the same). The library's graph links artists by guest spots across
        // genres (the test server's hard rock band and its synthwave guest,
        // 0.22), which is a friendship more than a mix; Last.fm's strong
        // links (0.8 and up) stay strong enough across genres.
        let genres = pool.map { genreShares(of: $0) }
        // Linkage between clusters, kept up to date as they merge (Lance and
        // Williams: the average of the two merged, by size).
        var link = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        for i in 0..<m {
            for j in (i + 1)..<m {
                let ki = index.artistKeys[pool[i]], kj = index.artistKeys[pool[j]]
                let w = max(graph.weight(ki, kj), graph.weight(kj, ki)) * (0.4 + 0.6 * cosine(genres[i], genres[j]))
                link[i][j] = w
                link[j][i] = w
            }
        }
        var members: [[Int]] = (0..<m).map { [$0] }
        var active = [Bool](repeating: true, count: m)
        while true {
            var best = -1.0
            var pair = (0, 0)
            for i in 0..<m where active[i] {
                for j in (i + 1)..<m where active[j] {
                    guard members[i].count + members[j].count <= Self.maxClusterSize else { continue }
                    if link[i][j] > best {
                        best = link[i][j]
                        pair = (i, j)
                    }
                }
            }
            guard best >= Self.clusterLinkage else { break }
            let (i, j) = pair
            let si = Double(members[i].count), sj = Double(members[j].count)
            for k in 0..<m where active[k] && k != i && k != j {
                let w = (si * link[i][k] + sj * link[j][k]) / (si + sj)
                link[i][k] = w
                link[k][i] = w
            }
            members[i] += members[j]
            active[j] = false
        }

        var clusters: [(artists: [Int], weight: Double, first: Int)] = []
        for i in 0..<m where active[i] {
            // Members by liking; the cluster by its total.
            let sorted = members[i].sorted { weight[$0] != weight[$1] ? weight[$0] > weight[$1] : $0 < $1 }
            clusters.append((sorted.map { pool[$0] }, sorted.reduce(0) { $0 + weight[$1] }, sorted.first ?? 0))
        }
        clusters.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.first < $1.first }
        // A cluster with a twentieth of the first one's liking is a passing
        // interest, not a mix of its own. (The made-up listener's Folk and
        // Pop, played a little, hold 0.4 against Rock's 5.7, and are Daily
        // Mix 4 and 5.)
        let top = clusters.first?.weight ?? 0
        return clusters.filter { $0.weight >= 0.05 * top }.map { ($0.artists, $0.weight) }
    }

    /// An artist's genres as the share of their own songs with each, by
    /// genre number (sorted, so sums do not depend on a Dictionary's order).
    func genreShares(of artist: Int) -> [(genre: Int, share: Double)] {
        let own = index.artistOwnTracks[artist]
        guard !own.isEmpty else { return [] }
        var count: [Int: Int] = [:]
        for t in own { for g in index.trackGenres[t] { count[g, default: 0] += 1 } }
        return count.keys.sorted().map { ($0, Double(count[$0] ?? 0) / Double(own.count)) }
    }

    func cosine(_ x: [(genre: Int, share: Double)], _ y: [(genre: Int, share: Double)]) -> Double {
        var i = 0, j = 0
        var dot = 0.0
        while i < x.count, j < y.count {
            if x[i].genre == y[j].genre {
                dot += x[i].share * y[j].share
                i += 1
                j += 1
            } else if x[i].genre < y[j].genre {
                i += 1
            } else {
                j += 1
            }
        }
        let nx = x.reduce(0) { $0 + $1.share * $1.share }.squareRoot()
        let ny = y.reduce(0) { $0 + $1.share * $1.share }.squareRoot()
        return nx > 0 && ny > 0 ? dot / (nx * ny) : 0
    }

    /// One daily mix: about 60% songs of the cluster's artists the listener
    /// knows and likes, 40% songs they have rarely or never heard, by the
    /// cluster's artists and their neighbours in the graph; no track that
    /// an earlier daily mix has.
    func dailyMix(_ cluster: (artists: [Int], weight: Double), number: Int, used: inout Set<Int>) -> Mix? {
        let memberSet = Set(cluster.artists)
        // How near each artist is to the cluster: its own 1, a neighbour by
        // its strongest edge to a member.
        var closeness: [Int: Double] = [:]
        for a in cluster.artists { closeness[a] = 1 }
        var neighborEdge: [Int: Double] = [:]
        for a in cluster.artists {
            for neighbor in graph.similarArtists(to: index.artistKeys[a], limit: 25) {
                guard let b = index.artistByKey[neighbor.key], !memberSet.contains(b), artistAffinity[b] > -0.3,
                      !index.artistOwnTracks[b].isEmpty else { continue }
                neighborEdge[b] = max(neighborEdge[b] ?? 0, neighbor.weight)
            }
        }
        let neighbors = neighborEdge.filter { $0.value >= 0.15 }.sorted { x, y in
            x.value != y.value ? x.value > y.value : x.key < y.key
        }.prefix(12)
        for (b, edge) in neighbors { closeness[b] = 0.85 * edge }

        // Every track of these artists (guest spots too, at 0.7), once.
        var trackCloseness: [Int: Double] = [:]
        for a in closeness.keys.sorted() {
            let c = closeness[a] ?? 0
            for t in index.artistTracks[a] {
                let own = index.trackArtists[t].first == a
                let value = c * (own ? 1 : 0.7)
                if value > (trackCloseness[t] ?? 0) { trackCloseness[t] = value }
            }
        }

        // The cluster's genres: the share of its artists' own songs with
        // each. A neighbour's song in none of them came by a guest spot
        // across genres (the test server's hard rock band and its synthwave
        // guest): left out when the link is weak, and the fewer of the
        // cluster's genres a song has, the less it counts (a fifth for none).
        var genreShare: [Int: Double] = [:]
        var ownSongs = 0
        for a in cluster.artists {
            for t in index.artistOwnTracks[a] {
                ownSongs += 1
                for g in index.trackGenres[t] { genreShare[g, default: 0] += 1 }
            }
        }
        func fit(_ t: Int) -> Double {
            guard ownSongs > 0 else { return 1 }
            let best = index.trackGenres[t].map { genreShare[$0] ?? 0 }.max() ?? 0
            return best / Double(ownSongs)
        }

        var familiar: [(track: Int, weight: Double)] = []
        var fresh: [(track: Int, weight: Double)] = []
        for t in trackCloseness.keys.sorted() {
            guard !used.contains(t), welcome(t), let c = trackCloseness[t] else { continue }
            let byMember = index.trackArtists[t].contains { memberSet.contains($0) }
            if familiarity[t] >= 0.3 || affinity[t] >= 0.25 {
                // Known: only the cluster's own artists' (the familiar part).
                guard byMember, affinity[t] > 0 else { continue }
                familiar.append((t, (0.3 + affinity[t]) * (0.6 + 0.4 * familiarity[t]) * c * freshness(t)))
            } else {
                // A neighbour's song of other genres than the cluster's, by a
                // weak link, is not this mix's: the known songs fill in instead.
                let fits = fit(t)
                guard fits >= 0.25 || c >= 0.5 else { continue }
                let liking = primaryArtist(t).map { max(0, artistAffinity[$0]) } ?? 0
                fresh.append((t, c * c * (0.6 + 0.4 * liking) * (0.2 + 0.8 * fits) * freshness(t)))
            }
        }

        let length = Self.dailyLength
        var familiarCount = min(familiar.count, Int((Double(length) * Self.dailyFamiliarShare).rounded()))
        let freshCount = min(fresh.count, length - familiarCount)
        familiarCount = min(familiar.count, length - freshCount)
        guard familiarCount + freshCount >= Self.dailyMinimum else { return nil }

        let lead = cluster.artists[0]
        let daySeed = seed("daily", index.artistKeys[lead])
        // A fifth of the mix at most by one artist: with two songs between
        // two by one artist a third is the most there can be, and three
        // artists at a quarter each left the made-up Pop mix nothing to
        // place between them at its end.
        let cap = max(3, Int((Double(length) * 0.2).rounded(.up)))
        var counts = MixCounts()
        let knownPicks = draw(familiar, count: familiarCount, seed: daySeed, artistCap: cap, counts: &counts)
        let freshPicks = draw(fresh, count: freshCount, seed: daySeed &+ 1, artistCap: cap, counts: &counts)
        let tracks = order([knownPicks, freshPicks], separation: 2)
        used.formUnion(tracks)
        return make(.daily, key: String(number), title: "Daily Mix \(number)", tracks: tracks,
                    lead: cluster.artists, coverOrder: knownPicks + freshPicks)
    }

    // MARK: - The others

    func otherMixes() -> [Made] {
        [onRepeat(), newArrivals(), lovedTracks(), rediscover(), deepCuts()].compactMap { $0 }
            + decadeMixes() + genreMixes()
    }

    /// "On Repeat": what was played most in the last month, most first.
    func onRepeat() -> Made? {
        var candidates: [(track: Int, plays: Double)] = []
        for t in 0..<trackCount where recentPlays[t] >= 1.5 && welcome(t) {
            candidates.append((t, recentPlays[t]))
        }
        candidates.sort { $0.plays != $1.plays ? $0.plays > $1.plays : $0.track < $1.track }
        let picks = candidates.prefix(30).map(\.track)
        guard let mix = make(.onRepeat, title: "On Repeat", tracks: order([picks], separation: 1), coverOrder: picks) else { return nil }
        return Made(mix: mix, want: 0.9 * min(1, Double(candidates.count) / 20))
    }

    /// "New Arrivals": songs from the albums added in the last 30 days, the
    /// newest most; when none are that new, the newest albums there are.
    func newArrivals() -> Made? {
        let reference = now.timeIntervalSinceReferenceDate
        var albums: [(album: Int, added: Double)] = []
        for (a, members) in index.albumTracks.enumerated() {
            var added = -Double.infinity
            for t in members {
                if let date = snapshot.tracks[t].dateAdded?.timeIntervalSinceReferenceDate, date.isFinite {
                    added = max(added, date)
                }
            }
            if added > -.infinity { albums.append((a, min(added, reference))) }
        }
        guard !albums.isEmpty else { return nil }
        albums.sort { $0.added != $1.added ? $0.added > $1.added : $0.album < $1.album }

        // Thirty days to midnight, so an album does not leave at lunch; one
        // added today joins at once (new music is the point of this mix).
        let cutoff = dayStart.timeIntervalSinceReferenceDate - 30 * 86_400
        var chosen = albums.filter { $0.added >= cutoff }
        let isNew = !chosen.isEmpty
        if !isNew {
            // Nothing this month: the newest albums, until there is a mix.
            chosen = []
            var tracks = 0
            for album in albums where tracks < 40 && chosen.count < 10 {
                chosen.append(album)
                tracks += index.albumTracks[album.album].count
            }
        }

        var weighted: [(track: Int, weight: Double)] = []
        for (rank, album) in chosen.enumerated() {
            let newer = 1 / (1 + 0.15 * Double(rank))
            for t in index.albumTracks[album.album] where welcome(t) {
                let liking = primaryArtist(t).map { max(0, artistAffinity[$0]) } ?? 0
                weighted.append((t, newer * (1 + liking) * (1 - 0.5 * familiarity[t])))
            }
        }
        let count = min(40, weighted.count)
        var counts = MixCounts()
        let albumCap = max(3, Int((40 / Double(max(1, chosen.count))).rounded(.up)))
        let picks = draw(weighted, count: count, seed: seed("newArrivals"), albumCap: albumCap, counts: &counts)
        guard let mix = make(.newArrivals, title: "New Arrivals", tracks: order([picks], separation: 1), coverOrder: picks)
        else { return nil }
        let liked = picks.filter { t in primaryArtist(t).map { artistAffinity[$0] > 0.1 } ?? false }.count
        let want = isNew ? 0.85 * (0.6 + 0.4 * Double(liked) / Double(max(1, picks.count))) : 0.3
        return Made(mix: mix, want: want)
    }

    /// "Loved Tracks": the favourites, shuffled for the day, those heard
    /// lately less often. The favourites as they are now: a heart given
    /// today is in it at the next build, one taken away is gone.
    func lovedTracks() -> Made? {
        var weighted: [(track: Int, weight: Double)] = []
        for t in 0..<trackCount where snapshot.tracks[t].isFavorite && !avoided[t] {
            weighted.append((t, freshness(t)))
        }
        let count = min(50, weighted.count)
        var counts = MixCounts()
        let picks = draw(weighted, count: count, seed: seed("favorites"), artistCap: max(6, count / 3), counts: &counts)
        guard let mix = make(.favorites, title: "Loved Tracks", tracks: order([picks], separation: 2),
                             station: .favorites) else { return nil }
        return Made(mix: mix, want: 0.75 * min(1, Double(weighted.count) / 25))
    }

    /// "Rediscover": songs once played a lot or loved, not heard in more
    /// than 60 days.
    func rediscover() -> Made? {
        var weighted: [(track: Int, weight: Double)] = []
        for t in 0..<trackCount where welcome(t) && affinity[t] > -0.1 {
            let track = dayTracks[t]
            let plays = max(track.playCount, heardCount[t])
            guard plays > 0 else { continue }
            let hours = hoursSince[t]
            // Unknown when: played (Jellyfin counts it) but not when, which a
            // server only forgets for something long ago; or played today
            // on another device, which hides the play before (MixModel).
            let days = hours.isFinite ? hours / 24 : 365
            guard days > 60 else { continue }
            guard plays >= 3 || track.isFavorite || affinity[t] >= 0.35 else { continue }
            let past = 0.8 * log2(1 + Double(plays)) + (track.isFavorite ? 1.5 : 0) + 2 * max(0, affinity[t])
            weighted.append((t, past * min(1.5, 0.75 + days / 240)))
        }
        var counts = MixCounts()
        let picks = draw(weighted, count: min(30, weighted.count), seed: seed("rediscover"), artistCap: 8, counts: &counts)
        guard let mix = make(.rediscover, title: "Rediscover", tracks: order([picks], separation: 2)) else { return nil }
        return Made(mix: mix, want: 0.7 * min(1, Double(weighted.count) / 30))
    }

    /// "Deep Cuts": the songs of the artists the listener likes most that
    /// they have hardly or never played.
    func deepCuts() -> Made? {
        let top = rankedArtists.filter { artistAffinity[$0] >= 0.3 }.prefix(15)
        guard !top.isEmpty else { return nil }
        var weighted: [(track: Int, weight: Double)] = []
        for a in top {
            let liking = pow(artistAffinity[a], 1.5)
            for t in index.artistOwnTracks[a] where welcome(t) && familiarity[t] < 0.15 && dayTracks[t].playCount <= 1 {
                weighted.append((t, liking))
            }
        }
        let cap = max(4, Int((30 / Double(min(top.count, 5))).rounded(.up)))
        var counts = MixCounts()
        let picks = draw(weighted, count: min(30, weighted.count), seed: seed("deepCuts"), artistCap: cap, counts: &counts)
        // Deep cuts of one or two artists are their pages, not a mix.
        guard artistCount(picks, atLeast: 3) else { return nil }
        guard let mix = make(.deepCuts, title: "Deep Cuts", tracks: order([picks], separation: 2), station: .discovery)
        else { return nil }
        let artists = Set(picks.compactMap { primaryArtist($0) })
        let liking = artists.reduce(0) { $0 + artistAffinity[$1] } / Double(max(1, artists.count))
        return Made(mix: mix, want: 0.65 * liking)
    }

    /// The decades the listener plays most (when nothing is played, those
    /// the library has most of), best first: two, and a third when it has
    /// at least a fifth of the first one's weight.
    func rankedDecades(minimumTracks: Int) -> [(decade: Int, score: Double)] {
        let total = Double(max(1, trackCount))
        var ranked: [(decade: Int, score: Double)] = []
        for (decade, members) in index.decadeTracks where members.count >= minimumTracks && artistCount(members, atLeast: 3) {
            var score = 0.0
            for t in members { score += max(0, affinity[t]) + 0.5 * familiarity[t] }
            // The library's own share decides between decades nobody plays.
            score += 0.001 * Double(members.count) / total
            ranked.append((decade, score))
        }
        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.decade > $1.decade }
        let top = ranked.first?.score ?? 0
        return Array(ranked.enumerated().filter { $0.offset < 2 || $0.element.score >= 0.2 * top }.map(\.element).prefix(3))
    }

    func decadeMixes() -> [Made] {
        let decades = rankedDecades(minimumTracks: 15)
        let top = decades.first?.score ?? 0
        return decades.compactMap { item in
            let members = index.decadeTracks[item.decade] ?? []
            guard let mix = tasteMix(.decade, key: String(item.decade), title: "\(item.decade)s Mix", members: members,
                                     station: .decade(item.decade)) else { return nil }
            return Made(mix: mix, want: 0.55 * (top > 0 ? item.score / top : 0))
        }
    }

    /// The listener's top genres (the library's biggest when nothing is
    /// played), leaving out one that is mostly the same songs as a genre
    /// before it ("Rock" and "Alternative" when every alternative song is
    /// also rock and most rock alternative).
    func topGenres(count: Int, minimumTracks: Int) -> [Int] {
        var chosen: [Int] = []
        for g in rankedGenres where index.genreTracks[g].count >= minimumTracks {
            // A genre of one or two artists is their mix, not a genre's (the
            // test server's Americana is Old Mill Road).
            guard artistCount(index.genreTracks[g], atLeast: 3) else { continue }
            if chosen.contains(where: { jaccard(index.genreTracks[$0], index.genreTracks[g]) >= 0.6 }) { continue }
            chosen.append(g)
            if chosen.count == count { break }
        }
        return chosen
    }

    func genreMixes() -> [Made] {
        topGenres(count: 3, minimumTracks: 15).compactMap { g in
            let name = index.genreNames[g]
            guard let mix = tasteMix(.genre, key: index.genreKeys[g], title: "\(name) Mix", members: index.genreTracks[g],
                                     station: .genre(key: index.genreKeys[g], name: name), genre: g) else { return nil }
            return Made(mix: mix, want: 0.6 * (0.25 + 0.75 * max(0, genreAffinity[g])))
        }
    }

    /// A decade's or a genre's mix: 40 songs drawn by the listener's taste
    /// (the song, its artist, its genres), no artist more than four times
    /// when the decade or genre has enough others. On a genre's mix a song
    /// that is mostly that genre counts more than one that has it among
    /// five.
    func tasteMix(_ kind: MixKind, key: String, title: String, members: [Int], station: StationSeed,
                  genre: Int? = nil) -> Mix? {
        var weighted: [(track: Int, weight: Double)] = []
        weighted.reserveCapacity(members.count)
        for t in members where welcome(t) {
            let liking = primaryArtist(t).map { max(0, artistAffinity[$0]) } ?? 0
            var w = (0.15 + max(0, affinity[t]) + 0.4 * liking + 0.2 * max(0, genreTaste(t))) * freshness(t)
            if genre != nil { w /= Double(max(1, index.trackGenres[t].count)).squareRoot() }
            weighted.append((t, w))
        }
        // As long as four songs an artist allows, at least 20: a genre of
        // three artists (the test server's) is a mix of 20, not 40 of three.
        let artists = Set(weighted.compactMap { primaryArtist($0.track) }).count
        let count = min(weighted.count, 40, max(20, 4 * artists))
        var counts = MixCounts()
        let picks = draw(weighted, count: count, seed: seed(kind.rawValue, key), artistCap: 4, counts: &counts)
        return make(kind, key: key, title: title, tracks: order([picks], separation: 2), station: station)
    }

    /// Whether the tracks are filed under at least `count` artists.
    func artistCount(_ tracks: [Int], atLeast count: Int) -> Bool {
        var artists = Set<Int>()
        for t in tracks {
            if let a = primaryArtist(t), artists.insert(a).inserted, artists.count >= count { return true }
        }
        return false
    }

    /// |A ∩ B| / |A ∪ B| of two sorted lists of track numbers.
    func jaccard(_ a: [Int], _ b: [Int]) -> Double {
        var i = 0, j = 0, both = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                both += 1
                i += 1
                j += 1
            } else if a[i] < b[j] {
                i += 1
            } else {
                j += 1
            }
        }
        let union = a.count + b.count - both
        return union > 0 ? Double(both) / Double(union) : 0
    }

    // MARK: - Stations

    /// Your Station, Discovery, Loved (when there are favourites), six
    /// artists' stations, four genres' and three decades'.
    func stations() -> [Station] {
        var seeds: [StationSeed] = [.personal, .discovery]
        if snapshot.tracks.contains(where: \.isFavorite) { seeds.append(.favorites) }
        for a in stationArtists(6) {
            let ref = index.artistRefs[a]
            seeds.append(.artist(key: index.artistKeys[a], name: ref.name, id: ref.id))
        }
        for g in topGenres(count: 4, minimumTracks: 10) {
            seeds.append(.genre(key: index.genreKeys[g], name: index.genreNames[g]))
        }
        for decade in rankedDecades(minimumTracks: 10) {
            seeds.append(.decade(decade.decade))
        }
        return seeds.map { Station(seed: $0, snapshot: snapshot) }
    }

    /// The top artists, but not six of one kind: walking the fifteen liked
    /// most, an artist whose graph weight to one already chosen is 0.5 or
    /// more waits until the other liked ones have had their turn; artists
    /// not yet liked come last (for a new listener, all of them: the
    /// biggest first).
    func stationArtists(_ count: Int) -> [Int] {
        let candidates = rankedArtists.filter {
            index.artistOwnTracks[$0].count >= 3 && !LibrarySnapshot.Index.isVarious(index.artistRefs[$0].name)
        }.prefix(15)
        var chosen: [Int] = []
        var waiting: [Int] = []
        var unliked: [Int] = []
        for a in candidates {
            guard artistAffinity[a] > 0.05 else {
                unliked.append(a)
                continue
            }
            let near = chosen.contains { graph.weight(index.artistKeys[a], index.artistKeys[$0]) >= 0.5 }
            if near { waiting.append(a) } else if chosen.count < count { chosen.append(a) }
        }
        for a in waiting + unliked where chosen.count < count { chosen.append(a) }
        return chosen
    }
}
