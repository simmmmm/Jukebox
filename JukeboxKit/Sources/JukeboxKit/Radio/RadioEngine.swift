// How a station chooses (docs/RADIO.md has the why and the measurements).
//
// 1. The seed becomes a profile: artists with weights (the seed's own, then
//    their neighbours in the graph, and at higher adventurousness the
//    neighbours' neighbours), genres with weights, an era, and tracks with
//    weights of their own (the seed track, similar tracks, Instant Mix).
// 2. Every track gets a closeness to that profile: the best of its
//    channels (artist, genre, track, era) plus a quarter of the second
//    best, times how near its year is. The channel that won is the reason.
// 3. A base score: closeness^γ × taste × familiarity × freshness. γ and
//    the familiarity term are where adventurousness acts.
// 4. Each pick: the base times what this session has learnt (skips, thumbs,
//    artists already heard), over the tracks the rules allow; the best K
//    are drawn from at random in proportion to their score — never the
//    argmax, so a station is never the same twice. Ties go by the session's
//    own random order, never the library's. The rules loosen one at a time
//    when nothing passes; a song (any recording of it) comes back only
//    after `noRepeatHours` of music, or in a library that has run out.
// 5. Feedback moves the profile (a little, the seed keeps 70%) and the
//    session's penalties and boosts; the scores are worked out again before
//    the next pick.
//
// Everything is by track, artist and genre number (LibrarySnapshot.Index),
// in plain arrays, and nothing depends on a Dictionary's order, so the same
// random seed gives the same station in every process.

import Foundation

struct RadioEngine: Sendable {
    enum Kind: Sendable, Equatable {
        case track, artist, album, genre, decade, collection, personal, discovery, favorites
    }

    /// Which part of the profile a track's closeness came from.
    enum Channel: Sendable, Equatable {
        case none
        case seedTrack
        case track
        case artist(Int)
        case genre(Int)
        case era
    }

    /// The station's profile from its seed alone (before any feedback).
    struct Anchor: Sendable {
        var kind: Kind = .personal
        /// By artist number: the artist channel.
        var artistWeight: [Double] = []
        /// By artist number: −1 when the artist is the seed's own, else the
        /// artist it was reached through ("Sounds like …").
        var artistVia: [Int] = []
        /// Artist stations: the artist whose share is held to one in five.
        var capArtist = -1
        /// The artists a song, artist or album station is named after. A
        /// thumbs down on one of their songs there is about the song more
        /// than the artist: the listener chose their station.
        var subject: Set<Int> = []
        /// By genre number, summing to 1.
        var genreWeight: [Double] = []
        /// How much a perfect genre fit is worth.
        var genreScale = 0.7
        var eraCenter: Double?
        var eraSpread = 6.0
        var decade: Int?
        /// Tracks with a weight of their own, and why.
        var trackWeight: [Int: Double] = [:]
        var trackReason: [Int: PickReason] = [:]
        var seedTrack: Int?
        /// Where the first track comes from, and what it says.
        var first: [Int] = []
        var firstReason: PickReason?
    }

    /// A thumbs up, and what it makes more likely.
    struct Like: Sendable {
        var track: Int
        /// `handed.count` when it was liked.
        var at: Int
        /// By artist number: 1 for the liked track's artists, the graph's
        /// weight for their neighbours.
        var artists: [Int: Double]
        var genres: [Int]
    }

    struct Candidate {
        var track: Int
        var score: Double
        /// How much a like lifted it, when the like's artist (or a close
        /// neighbour) is what it shares; 0 otherwise.
        var likeStrength: Double
        var like: Int
    }

    let snapshot: LibrarySnapshot
    let graph: SimilarityGraph
    let seed: StationSeed
    var index: LibrarySnapshot.Index { snapshot.index }

    // Taste, by track, artist and genre number.
    let affinity: [Double]
    let familiarity: [Double]
    let hoursSince: [Double]
    let artistAffinity: [Double]
    let genreAffinity: [Double]
    let rankedTracks: [Int]
    let rankedArtists: [Int]
    let rankedGenres: [Int]
    let maxSpecificity: Double
    /// By track number: the session's own order for tracks that score the
    /// same, from its random seed. Without it ties went by the library's
    /// order, and when nothing is known of the listener, ties are most of
    /// the library: The Lanterns Radio opened with one of the same three
    /// songs (of 20) for any random seed, and a library without genres
    /// played 64% from its first half (measured, RadioCriticTests).
    let ties: [UInt64]
    let tieSeed: UInt64

    var rng: SplitMix64
    var recently: Set<Int>
    var settings: RadioSettings

    var anchor = Anchor()
    var anchorBuiltFor = -1.0
    var needsScoring = true

    // Scores, by track number, valid while !needsScoring.
    var closeness: [Double] = []
    var base: [Double] = []
    var channel: [Channel] = []
    /// The artists' current weights and vias (anchor plus drift).
    var artistWeightNow: [Double] = []
    var artistViaNow: [Int] = []
    /// Closeness above `minCloseness`, best base first.
    var pool: [Int] = []
    /// The rest of the library, best base first, made when a station runs
    /// out of its neighbourhood.
    var rest: [Int]?
    var restBase: [Double] = []

    // The session.
    var handed: [Int] = []
    /// By song number (LibrarySnapshot.Index.trackSong: the album's and
    /// the best-of's "Karma Police" are one song): where it was handed last,
    /// a position in `handed`.
    var lastAt: [Int: Int] = [:]
    /// Seconds of music handed out up to and including each position.
    var handedEnd: [Double] = []
    var disliked = Set<Int>()
    var skipped = Set<Int>()
    /// Skips against an artist (1 a skip, 0.4 as a guest), fading 2% a track.
    var artistPressure: [Double]
    /// Thumbs down on an artist: a factor that does not fade.
    var artistBan: [Double]
    /// Skips against a genre, by how much it set the skipped track apart
    /// (`distinctiveness`), fading 2% a track.
    var genrePressure: [Double]
    var driftGenre: [Double]
    var driftArtist: [Double]
    var driftWeight = 0.0
    var likes: [Like] = []
    var added: [Int: Double] = [:]
    var addedReason: [Int: PickReason] = [:]
    var started = false

    static let minCloseness = 0.02
    /// A thumbs up makes its own artist up to 2.5 times as likely, a
    /// neighbour by the edge's weight, fading by half every 15 tracks.
    static let likeBoost = 1.5
    /// What a track outside the neighbourhood counts as, when a station has
    /// run out of its own.
    static let floorCloseness = 0.03
    /// A thumbs down on a song of the station's own artist, on their
    /// station: that artist × 0.12 rather than × 0.02. At × 0.02 (as for
    /// anyone else) Radiohead all but left Radiohead Radio after one song
    /// (5.9 → 0.3 of the next 30, measured); at × 0.2, 5.9 → 4.7, as if
    /// nothing was said; at × 0.07, 1.0.
    static let subjectBan = 0.12
    /// A song heard earlier in the session, once `noRepeatHours` of music
    /// (at least three) have played since, is back in the running: at its
    /// freshness (as a song heard that long ago anywhere, 0.37 after 12
    /// hours, 0.63 after 48) times 0.4, for being the same station again.
    /// A song near the seed then beats a new one far from it, not a new one
    /// near. Without it a long session ran out of its neighbourhood and
    /// left it: an artist station on the made-up library played 0% of the
    /// seed's cluster after pick 400 (about 27 hours). At a flat 0.5
    /// (tried first) two picks in three after the first 200 were repeats
    /// (measured, RadioCriticTests).
    static let laterRepeat = 0.4

    init(seed: StationSeed, snapshot: LibrarySnapshot, taste: TasteProfile, graph: SimilarityGraph,
         settings: RadioSettings, recentlyPlayed: Set<ItemID>, randomSeed: UInt64) {
        self.snapshot = snapshot
        self.graph = graph
        self.seed = seed
        self.settings = settings
        rng = SplitMix64(seed: randomSeed)
        let index = snapshot.index
        let n = snapshot.tracks.count

        let data = taste.data
        var known: [Double], heard: [Double]
        if data.index === index {
            affinity = data.trackAffinity
            known = data.familiarity
            heard = data.hoursSinceHeard
            artistAffinity = data.artistAffinity
            genreAffinity = data.genreAffinity
        } else {
            // A taste made from another snapshot (the library changed since):
            // the same numbers, looked up by id and key.
            affinity = snapshot.tracks.map { taste.trackAffinity($0.id) }
            known = snapshot.tracks.map { taste.familiarity($0.id) }
            heard = snapshot.tracks.map { data.hoursSinceHeard(id: $0.id) }
            artistAffinity = index.artistKeys.map { taste.artistAffinity($0) }
            genreAffinity = index.genreKeys.map { taste.genreAffinity($0) }
        }
        // A song is as known and as lately heard as its most played
        // recording: the best-of's copy of a song heard twenty times is not
        // "New to you", nor fresh because that copy was never played.
        for tracks in index.songTracks where tracks.count > 1 {
            var most = 0.0, latest = Double.infinity
            for t in tracks {
                most = max(most, known[t])
                latest = min(latest, heard[t])
            }
            for t in tracks {
                known[t] = most
                heard[t] = latest
            }
        }
        familiarity = known
        hoursSince = heard
        rankedTracks = data.rankedTracks.compactMap { index.trackByID[$0] }
        rankedArtists = data.rankedArtists.compactMap { index.artistByKey[$0] }
        rankedGenres = data.rankedGenres.compactMap { index.genreByKey[$0] }
        maxSpecificity = max(1e-9, index.genreIDF.max() ?? 1)
        // A stream of its own, so the picks' random numbers stay those of
        // the seed.
        tieSeed = randomSeed ^ 0x5DEE_CE66_D1CE_4E5B
        var tieNumbers = SplitMix64(seed: tieSeed)
        ties = (0..<n).map { _ in tieNumbers.next() }

        // Songs thumbed down on this device stay out, except the one a song
        // station is started from: the listener chose it.
        let down = data.index === index
            ? data.thumbsDown.indices.filter { data.thumbsDown[$0] }
            : snapshot.tracks.indices.filter { data.isThumbedDown(id: snapshot.tracks[$0].id) }
        // A song's other recordings with it (the best-of's, the live one).
        for t in down { disliked.formUnion(index.songTracks[index.trackSong[t]]) }
        if case let .track(id) = seed, let t = index.trackByID[id] { disliked.remove(t) }

        recently = Set(recentlyPlayed.compactMap { index.trackByID[$0] }.flatMap { index.songTracks[index.trackSong[$0]] })
        artistPressure = [Double](repeating: 0, count: index.artistCount)
        artistBan = [Double](repeating: 1, count: index.artistCount)
        genrePressure = [Double](repeating: 0, count: index.genreCount)
        driftGenre = [Double](repeating: 0, count: index.genreCount)
        driftArtist = [Double](repeating: 0, count: index.artistCount)
        closeness = [Double](repeating: 0, count: n)
        base = [Double](repeating: 0, count: n)
        channel = [Channel](repeating: .none, count: n)
    }

    var adventurousness: Double {
        let a = settings.adventurousness
        return a.isFinite ? min(1, max(0, a)) : 0.35
    }

    // MARK: - The profile

    mutating func buildAnchor() {
        let adv = adventurousness
        var a = Anchor()
        a.artistWeight = [Double](repeating: 0, count: index.artistCount)
        a.artistVia = [Int](repeating: -1, count: index.artistCount)
        a.genreWeight = [Double](repeating: 0, count: index.genreCount)
        var seedArtists: [Int] = []
        /// Artists whose neighbours the station reaches without playing the
        /// artists themselves on their own account (a genre station's).
        var sources: [(artist: Int, weight: Double)] = []

        func setOwn(_ artist: Int, _ weight: Double) {
            if weight > a.artistWeight[artist] {
                a.artistWeight[artist] = weight
                a.artistVia[artist] = -1
            }
            if !seedArtists.contains(artist) { seedArtists.append(artist) }
        }
        func shareGenres(_ tracks: [Int], weights: [Double]? = nil) {
            var total = 0.0
            for (k, t) in tracks.enumerated() {
                let w = weights?[k] ?? 1
                let genres = index.trackGenres[t]
                guard !genres.isEmpty, w > 0 else { continue }
                total += w
                for g in genres { a.genreWeight[g] += w }
            }
            if total > 0 { for g in a.genreWeight.indices { a.genreWeight[g] /= total } }
        }
        func setEra(_ tracks: [Int], spread minimum: Double) {
            let years = tracks.map { index.trackYear[$0] }.filter { $0 > 0 }.sorted()
            guard !years.isEmpty else { return }
            a.eraCenter = Double(years[years.count / 2])
            let q1 = Double(years[years.count / 4]), q3 = Double(years[(years.count * 3) / 4])
            a.eraSpread = max(minimum, (q3 - q1) / 1.35)
        }
        func personal() {
            a.kind = seed == .discovery ? .discovery : .personal
            let liked = rankedArtists.filter { artistAffinity[$0] > 0 }.prefix(30)
            if liked.isEmpty {
                // A listener Jukebox knows nothing of yet: the library's
                // biggest artists and genres stand in for their taste.
                // Ties (artists of one size) in the session's own order, not
                // the library's: of 500 artists of three albums each, the
                // first 30 alphabetically were Your Station.
                let biggest = (0..<index.artistCount).sorted {
                    let x = index.artistOwnTracks[$0].count, y = index.artistOwnTracks[$1].count
                    return x != y ? x > y : artistTie($0) < artistTie($1)
                }.prefix(30)
                for artist in biggest where !index.artistOwnTracks[artist].isEmpty { setOwn(artist, 0.5) }
                shareGenres(Array(0..<snapshot.tracks.count))
            } else {
                for artist in liked { setOwn(artist, 0.45 + 0.4 * artistAffinity[artist]) }
                var total = 0.0
                for g in rankedGenres.prefix(12) where genreAffinity[g] > 0 {
                    a.genreWeight[g] = genreAffinity[g]
                    total += genreAffinity[g]
                }
                if total > 0 { for g in a.genreWeight.indices { a.genreWeight[g] /= total } }
            }
            if a.kind == .personal {
                for t in rankedTracks.prefix(300) where affinity[t] > 0.2 {
                    a.trackWeight[t] = 0.45 + 0.4 * affinity[t]
                    // "One of your favourites" for a heart or a song played a
                    // lot (affinity 0.6 is about eight recent plays).
                    if snapshot.tracks[t].isFavorite || affinity[t] >= 0.6 {
                        a.trackReason[t] = .favorite
                    } else if isRediscovery(t) {
                        a.trackReason[t] = .rediscover
                    } else if let own = index.trackArtists[t].first {
                        a.trackReason[t] = .byArtist(index.artistRefs[own].name)
                    }
                }
                a.first = Array(rankedTracks.prefix(30))
                a.firstReason = .favorite
            }
        }

        switch seed {
        case let .track(id):
            if let t = index.trackByID[id] {
                a.kind = .track
                a.seedTrack = t
                a.capArtist = index.trackArtists[t].first ?? -1
                a.subject = Set(index.trackArtists[t])
                for (k, artist) in index.trackArtists[t].enumerated() { setOwn(artist, k == 0 ? 0.88 : 0.75) }
                shareGenres([t])
                setEra([t], spread: 5)
                let name = snapshot.tracks[t].name
                for neighbor in graph.similarTracks(to: id, limit: 50) {
                    guard let other = index.trackByID[neighbor.key], other != t else { continue }
                    let w = 0.35 + 0.6 * min(1, max(0, neighbor.weight))
                    if w > (a.trackWeight[other] ?? 0) {
                        a.trackWeight[other] = w
                        a.trackReason[other] = .similarTrack(name)
                    }
                }
            } else {
                personal()
            }

        case let .artist(key, name, _):
            if let artist = index.artistByKey[key] ?? snapshot.matchArtist(name).flatMap({ index.artistByKey[$0] }) {
                a.kind = .artist
                a.capArtist = artist
                a.subject = [artist]
                setOwn(artist, 0.88)
                // The artist's own records say what they sound like; their
                // guest spots are someone else's (as in the graph).
                let own = index.artistOwnTracks[artist].isEmpty ? index.artistTracks[artist] : index.artistOwnTracks[artist]
                shareGenres(own)
                setEra(own, spread: 4)
                a.first = own
                a.firstReason = .byArtist(index.artistRefs[artist].name)
            } else {
                personal()
            }

        case let .album(id):
            if let album = index.albumByID[id], !index.albumTracks[album].isEmpty {
                a.kind = .album
                let tracks = index.albumTracks[album]
                a.capArtist = index.trackArtists[tracks[0]].first ?? -1
                a.subject = Set(tracks.compactMap { index.trackArtists[$0].first })
                var counts: [Int: Double] = [:]
                for t in tracks {
                    for (k, artist) in index.trackArtists[t].enumerated() { counts[artist, default: 0] += k == 0 ? 1 : 0.5 }
                }
                let most = counts.values.max() ?? 1
                for (artist, c) in counts.sorted(by: { $0.key < $1.key }) { setOwn(artist, 0.6 + 0.28 * c / most) }
                shareGenres(tracks)
                setEra(tracks, spread: 4)
                a.first = tracks
                a.firstReason = .seed
            } else {
                personal()
            }

        case let .genre(key, name):
            if let g = index.genreByKey[key] ?? index.genreByKey[NameKey.genre(name)] {
                a.kind = .genre
                a.genreScale = 0.9
                a.genreWeight[g] = 1
                // The genre's own artists (half or more of their records carry
                // it) lead, through the graph, to who is near them: what a
                // genre station plays beyond the genre itself.
                for artist in 0..<index.artistCount {
                    let own = index.artistOwnTracks[artist]
                    guard own.count >= 2 else { continue }
                    let share = Double(own.filter { index.trackGenres[$0].contains(g) }.count) / Double(own.count)
                    if share >= 0.5 { sources.append((artist, 0.55 * share)) }
                }
                // Genres that go with it, more of them further out.
                for link in index.genreRelated[g] {
                    a.genreWeight[link.genre] = max(a.genreWeight[link.genre], link.weight * (0.1 + 0.5 * adv))
                }
                let total = a.genreWeight.reduce(0, +)
                if total > 0 { for h in a.genreWeight.indices { a.genreWeight[h] /= total } }
                a.first = index.genreTracks[g]
                a.firstReason = .genre(index.genreNames[g])
            } else {
                personal()
            }

        case let .decade(year):
            let tracks = index.decadeTracks[year] ?? []
            if !tracks.isEmpty {
                a.kind = .decade
                a.decade = year
                a.eraCenter = Double(year) + 4.5
                a.eraSpread = 1 + 4 * adv
                // The listener's kind of music from that decade.
                shareGenres(tracks, weights: tracks.map { 1 + 2 * max(0, affinity[$0]) })
                for artist in rankedArtists.prefix(60) where artistAffinity[artist] > 0 {
                    let inDecade = index.artistTracks[artist].contains { index.trackYear[$0] / 10 * 10 == year }
                    if inDecade { setOwn(artist, 0.4 + 0.4 * artistAffinity[artist]) }
                }
                a.first = tracks
                a.firstReason = .era(year)
            } else {
                personal()
            }

        case let .collection(_, _, trackIDs):
            var members: [Int] = []
            var seen = Set<Int>()
            for id in trackIDs { if let t = index.trackByID[id], seen.insert(t).inserted { members.append(t) } }
            if !members.isEmpty {
                a.kind = .collection
                var counts: [Int: Double] = [:]
                for t in members {
                    for (k, artist) in index.trackArtists[t].enumerated() { counts[artist, default: 0] += k == 0 ? 1 : 0.5 }
                }
                let most = counts.values.max() ?? 1
                for (artist, c) in counts.sorted(by: { $0.key < $1.key }) { setOwn(artist, 0.55 + 0.3 * c / most) }
                shareGenres(members)
                setEra(members, spread: 5)
                for t in members {
                    a.trackWeight[t] = 0.6
                    a.trackReason[t] = .seed
                }
                a.first = members
                a.firstReason = .seed
            } else {
                personal()
            }

        case .personal, .discovery:
            personal()

        case .favorites:
            let loved = (0..<snapshot.tracks.count).filter { snapshot.tracks[$0].isFavorite }
            if !loved.isEmpty {
                a.kind = .favorites
                var counts: [Int: Double] = [:]
                for t in loved { if let artist = index.trackArtists[t].first { counts[artist, default: 0] += 1 } }
                let most = counts.values.max() ?? 1
                for (artist, c) in counts.sorted(by: { $0.key < $1.key }) { setOwn(artist, 0.45 + 0.35 * c / most) }
                shareGenres(loved)
                for t in loved {
                    a.trackWeight[t] = 0.85
                    a.trackReason[t] = .favorite
                }
                a.first = loved
                a.firstReason = .favorite
            } else {
                personal()
            }
        }

        // Neighbours: the seed's artists' in the graph, then (further out)
        // theirs. A neighbour's weight is the seed artist's times the edge.
        for s in seedArtists { sources.append((s, a.artistWeight[s])) }
        sources.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.artist < $1.artist }
        let isSource = Set(sources.map(\.artist))
        var firstDegree: [Int] = []
        for (s, sourceWeight) in sources.prefix(30) {
            for neighbor in graph.similarArtists(to: index.artistKeys[s], limit: 40) {
                guard let b = index.artistByKey[neighbor.key], !isSource.contains(b) else { continue }
                let w = sourceWeight * min(1, max(0, neighbor.weight)) * 0.95
                if w > a.artistWeight[b] {
                    if a.artistVia[b] != -1 || a.artistWeight[b] == 0 {
                        a.artistWeight[b] = w
                        a.artistVia[b] = s
                        if !firstDegree.contains(b) { firstDegree.append(b) }
                    }
                }
            }
        }
        if adv > 0.05 {
            let strongest = firstDegree.sorted {
                a.artistWeight[$0] != a.artistWeight[$1] ? a.artistWeight[$0] > a.artistWeight[$1] : $0 < $1
            }.prefix(15)
            for n1 in strongest {
                for neighbor in graph.similarArtists(to: index.artistKeys[n1], limit: 20) {
                    guard let b = index.artistByKey[neighbor.key], !isSource.contains(b) else { continue }
                    let w = a.artistWeight[n1] * min(1, max(0, neighbor.weight)) * 0.8 * adv
                    if w > a.artistWeight[b], a.artistVia[b] != -1 || a.artistWeight[b] == 0 {
                        a.artistWeight[b] = w
                        a.artistVia[b] = n1
                    }
                }
            }
        }

        // Genres that go with the station's, a little, more further out (a
        // genre station did this above).
        if a.kind != .genre {
            var extra = [Double](repeating: 0, count: index.genreCount)
            for g in a.genreWeight.indices where a.genreWeight[g] > 0 {
                for link in index.genreRelated[g] { extra[link.genre] += a.genreWeight[g] * link.weight * (0.1 + 0.4 * adv) }
            }
            var total = 0.0
            for g in a.genreWeight.indices {
                a.genreWeight[g] += extra[g]
                total += a.genreWeight[g]
            }
            if total > 0 { for g in a.genreWeight.indices { a.genreWeight[g] /= total } }
        }

        anchor = a
        anchorBuiltFor = adv
    }

    // MARK: - Scores

    /// The genre's weight in the profile now: the anchor, a little of what
    /// was accepted, less of what was skipped.
    func genreWeightsNow() -> [Double] {
        var weights = anchor.genreWeight
        var positive = 0.0
        for d in driftGenre where d > 0 { positive += d }
        if driftWeight > 0, positive > 0 {
            // The seed keeps at least 70% of the profile, however long the
            // station plays.
            let share = 0.3 * (1 - exp(-driftWeight / 6))
            for g in weights.indices {
                weights[g] = (1 - share) * weights[g] + share * max(0, driftGenre[g]) / positive
            }
        }
        for g in weights.indices where driftGenre[g] < 0 {
            weights[g] *= exp(0.6 * driftGenre[g] * index.genreIDF[g] / maxSpecificity)
        }
        return weights
    }

    mutating func scoreAll() {
        if anchorBuiltFor != adventurousness { buildAnchor() }
        let adv = adventurousness
        let n = snapshot.tracks.count
        let genreWeight = genreWeightsNow()

        var artistWeight = anchor.artistWeight
        var artistVia = anchor.artistVia
        for artist in artistWeight.indices where driftArtist[artist] > 0 {
            let w = 0.35 * (1 - exp(-driftArtist[artist] / 2))
            if w > artistWeight[artist] {
                artistWeight[artist] = w
                artistVia[artist] = -1
            }
        }
        artistWeightNow = artistWeight
        artistViaNow = artistVia

        var trackWeight = [Double](repeating: 0, count: n)
        for (t, w) in anchor.trackWeight { trackWeight[t] = w }
        for (t, w) in added where w > trackWeight[t] { trackWeight[t] = w }

        // How much of the profile's genre a track covers, the rarer genres
        // counting for more; a little less for genres of its own that the
        // profile does not have.
        var coverage = [Double](repeating: 0, count: n)
        var bestCoverage = 0.0
        for i in 0..<n {
            var covered = 0.0, total = 0.0, off = 0.0
            for g in index.trackGenres[i] {
                let idf = index.genreIDF[g]
                total += idf
                if genreWeight[g] > 0 { covered += genreWeight[g] * idf } else { off += idf }
            }
            guard covered > 0, total > 0 else { continue }
            coverage[i] = covered * (1 - 0.3 * off / total)
            bestCoverage = max(bestCoverage, coverage[i])
        }

        let gamma = Self.gamma(adv)
        let isDiscovery = anchor.kind == .discovery
        // Near the familiar end, a track must also sound like the station:
        // closeness is scaled by its genre fit, a track with none keeping 40%
        // at 0, 61% at 0.35, all at 1. Without this a guest spot linked an
        // artist to one of another genre and the dial did little below 0.7
        // (measured; half at 0 was tried first).
        let fitShare = 0.6 * (1 - adv)
        for i in 0..<n {
            var best = 0.0, second = 0.0
            var won = Channel.none
            func offer(_ value: Double, _ c: Channel) {
                guard value > 0 else { return }
                if value > best {
                    second = best
                    best = value
                    won = c
                } else if value > second {
                    second = value
                }
            }
            if anchor.seedTrack == i { offer(1, .seedTrack) }
            var bestArtist = -1, bestArtistWeight = 0.0
            for (k, artist) in index.trackArtists[i].enumerated() {
                // A guest counts, less than the artist it is filed under: it is
                // their song, with a part by the guest.
                let w = artistWeight[artist] * (k == 0 ? 1 : 0.7)
                if w > bestArtistWeight {
                    bestArtistWeight = w
                    bestArtist = artist
                }
            }
            if bestArtist >= 0 { offer(bestArtistWeight, .artist(bestArtist)) }
            var genreValue = 0.0
            if bestCoverage > 0, coverage[i] > 0 {
                genreValue = anchor.genreScale * coverage[i] / bestCoverage
                offer(genreValue, .genre(tellingGenre(i, genreWeight)))
            }
            if trackWeight[i] > 0 { offer(trackWeight[i], .track) }
            var c = min(1, best + 0.25 * second)
            // Who a track is like says more than its genre: when the artist
            // link is nearly as strong as the genre fit (three quarters), it
            // is the reason given ("Sounds like …", not "More Rock").
            if case .genre = won, bestArtist >= 0, bestArtistWeight >= 0.75 * genreValue {
                won = .artist(bestArtist)
            }
            // When Instant Mix, Last.fm or the graph's similar tracks are what
            // make a track close, they have judged how it sounds better than
            // tags and years can: neither the genre fit nor the era scales it.
            let judged = won == .track || won == .seedTrack
            if bestCoverage > 0, anchor.decade == nil, !judged {
                c *= 1 - fitShare + fitShare * coverage[i] / bestCoverage
            }

            let year = index.trackYear[i]
            if let decade = anchor.decade {
                // A decade station is the decade: closeness is how far in
                // the year is, times how well the rest fits.
                var fit = 0.0
                if year >= decade, year < decade + 10 {
                    fit = 1
                } else if year > 0 {
                    let outside = Double(year < decade ? decade - year : year - (decade + 9))
                    fit = exp(-outside * outside / (2 * anchor.eraSpread * anchor.eraSpread))
                }
                c = fit * (0.45 + 0.55 * c)
                won = .era
            } else if let center = anchor.eraCenter, !judged {
                if year > 0 {
                    let d = Double(year) - center
                    let s = anchor.eraSpread * (1 + adv)
                    c *= 0.65 + 0.35 * exp(-d * d / (2 * s * s))
                } else {
                    c *= 0.85
                }
            }
            closeness[i] = c
            channel[i] = won
            base[i] = c > Self.minCloseness ? Self.power(c, gamma) * personalFactor(i, adv: adv, discovery: isDiscovery) : 0
            // A candidate from outside counts for more by its weight: up to
            // twice at weight 1.
            if let w = added[i] { base[i] *= 1 + w / 0.9 }
        }

        // Sorted in a local: the comparator reads `self`, which a sort of
        // `pool` in place may not while it holds `pool`.
        var ranked = (0..<n).filter { closeness[$0] > Self.minCloseness }
        ranked.sort { base[$0] != base[$1] ? base[$0] > base[$1] : tiedBefore($0, $1) }
        pool = ranked
        rest = nil
        needsScoring = false
    }

    /// Taste × familiarity × freshness: what is the same for a track
    /// whatever station it is on.
    func personalFactor(_ i: Int, adv: Double, discovery: Bool) -> Double {
        let artists = index.trackArtists[i]
        let artistTaste = artists.first.map { artistAffinity[$0] } ?? 0
        var genreTaste = 0.0
        let genres = index.trackGenres[i]
        if !genres.isEmpty {
            for g in genres { genreTaste += genreAffinity[g] }
            genreTaste /= Double(genres.count)
        }
        let fam = familiarity[i]
        var exponent: Double
        if discovery {
            // Discovery: near what the listener likes, but not what they know.
            exponent = 0.8 * artistTaste + 0.4 * genreTaste - (3 + 2 * adv) * (fam - 0.35)
        } else {
            // Familiarity: up to four times for a song known well at the
            // familiar end, the other way round at the adventurous end. Not
            // more: at nine times (tried) a station from an artist the
            // listener never plays drifted to the artists they do.
            exponent = (1.2 - 0.7 * adv) * affinity[i] + (0.5 - 0.2 * adv) * artistTaste + 0.2 * genreTaste
                + 1.4 * (1 - 2 * adv) * (fam - 0.35)
        }
        var f = exp(exponent)
        if discovery, snapshot.tracks[i].isFavorite { f *= 0.15 }
        let hours = hoursSince[i]
        if hours.isFinite { f *= 1 - 0.75 * exp2(-hours / 48) }
        if isRediscovery(i), adv >= 0.2 { f *= 1.2 }
        return f.isFinite ? f : 0
    }

    func isRediscovery(_ i: Int) -> Bool {
        familiarity[i] >= 0.6 && hoursSince[i] >= 120 * 24
    }

    /// The genre of the track that says most about why it fits.
    func tellingGenre(_ i: Int, _ weights: [Double]) -> Int {
        var best = -1, bestValue = -1.0
        for g in index.trackGenres[i] {
            let v = weights[g] * index.genreIDF[g]
            if v > bestValue {
                bestValue = v
                best = g
            }
        }
        return best
    }

    /// How sharply closeness counts: 2.4 at the familiar end of the dial,
    /// 0.6 at the adventurous end.
    static func gamma(_ adventurousness: Double) -> Double { 2.4 - 1.8 * adventurousness }

    /// How many of the best are drawn from: 8 … 60.
    static func breadth(_ adventurousness: Double) -> Int { Int((8 + 52 * adventurousness).rounded()) }

    static func power(_ x: Double, _ y: Double) -> Double {
        x <= 0 ? 0 : exp(y * log(x))
    }

    /// Two tracks that score the same, in the session's own order.
    func tiedBefore(_ x: Int, _ y: Int) -> Bool {
        ties[x] != ties[y] ? ties[x] < ties[y] : x < y
    }

    /// Two artists that rank the same, in the session's own order.
    func artistTie(_ a: Int) -> UInt64 {
        var generator = SplitMix64(seed: tieSeed &+ 0x9E37_79B9_7F4A_7C15 &* UInt64(a + 1))
        return generator.next()
    }

    mutating func makeRest() {
        let adv = adventurousness
        let gamma = Self.gamma(adv)
        let floor = Self.power(Self.floorCloseness, gamma)
        let isDiscovery = anchor.kind == .discovery
        var list: [Int] = []
        var scores = [Double](repeating: 0, count: snapshot.tracks.count)
        for i in 0..<snapshot.tracks.count where closeness[i] <= Self.minCloseness {
            list.append(i)
            scores[i] = floor * personalFactor(i, adv: adv, discovery: isDiscovery)
        }
        list.sort { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : tiedBefore($0, $1) }
        rest = list
        restBase = scores
    }

    // MARK: - Picking

    struct Context {
        var blocked: [Int] = []
        var blockedHalf: [Int] = []
        var lastAlbum = -1
        var recentArtists: [Int: Int] = [:]
        var capBlocked = false
        var likeDecay: [Double] = []
        var likedArtists: Set<Int> = []
        var maxBoost = 1.0
        /// Songs not thumbed down: what a repeat waits for a share of.
        var usable = 0
    }

    func context() -> Context {
        var ctx = Context()
        let sep = max(0, settings.artistSeparation)
        let half = sep / 2
        for (k, t) in handed.reversed().enumerated() {
            if k < sep { ctx.blocked.append(contentsOf: index.trackArtists[t]) }
            if k < half { ctx.blockedHalf.append(contentsOf: index.trackArtists[t]) }
            if k < 30, let a = index.trackArtists[t].first { ctx.recentArtists[a, default: 0] += 1 }
            if k >= max(30, sep) { break }
        }
        if let last = handed.last { ctx.lastAlbum = index.trackAlbum[last] }
        if anchor.capArtist >= 0 {
            // At most one in five by the station's own artist, after the first.
            var since = 0
            var found = false
            for t in handed.reversed() {
                if index.trackArtists[t].contains(anchor.capArtist) {
                    found = true
                    break
                }
                since += 1
            }
            ctx.capBlocked = found && since < 4
        }
        var strongest = 0.0
        for like in likes {
            // A like counts less as the station plays on: half after 15 tracks.
            let decay = exp2(-Double(max(0, handed.count - like.at)) / 15)
            ctx.likeDecay.append(decay)
            strongest = max(strongest, decay)
            if decay > 0.25, let a = index.trackArtists[like.track].first { ctx.likedArtists.insert(a) }
        }
        ctx.maxBoost = 1 + Self.likeBoost * strongest
        ctx.usable = index.songCount - Set(disliked.map { index.trackSong[$0] }).count
        return ctx
    }

    /// Whether the rules of this step let the track be picked: 0 when they
    /// do not, else what its score is multiplied by (less than 1 for a song
    /// heard earlier in the session). The levels: 0 every rule; 1 the cap
    /// off (one in five by the station's own artist: of four artists,
    /// separation alone makes it one in four, and the two together used to
    /// go at once); 2 separation halved; 3 separation off; 4 the album rule
    /// off; 5 recently heard allowed. With a `window`, the songs of this
    /// session are allowed too when more than `window` tracks have come
    /// since, the longer ago the likelier; at the last level even skipped
    /// ones. Without one, only those heard `noRepeatHours` of music ago.
    func admission(_ i: Int, window: Int?, level: Int, _ ctx: Context) -> Double {
        if disliked.contains(i) { return 0 }
        let lastResort = window != nil && level >= Self.lastLevel
        if skipped.contains(i), !lastResort { return 0 }
        var factor = 1.0
        if let at = lastAt[index.trackSong[i]] {
            let since = (handedEnd.last ?? 0) - handedEnd[at]
            let after = repeatAfter
            if since >= after {
                factor = Self.laterRepeat * (1 - 0.75 * exp2(-since / 3600 / 48))
            } else {
                let gap = handed.count - at
                guard let window, gap > window else { return 0 }
                // Only repeats are left at these steps: the longest unheard
                // first.
                let share = min(1, Double(gap) / Double(max(1, ctx.usable)))
                factor = 0.01 + 0.99 * share * share * share * share
            }
        }
        if level < 5, recently.contains(i) || hoursSince[i] < settings.noRepeatHours { return 0 }
        let artists = index.trackArtists[i]
        if level == 0, ctx.capBlocked, artists.contains(anchor.capArtist) { return 0 }
        if level <= 1 {
            for a in artists where ctx.blocked.contains(a) { return 0 }
        } else if level == 2 {
            for a in artists where ctx.blockedHalf.contains(a) { return 0 }
        }
        if level <= 3, ctx.lastAlbum >= 0, index.trackAlbum[i] == ctx.lastAlbum { return 0 }
        return factor
    }

    /// Seconds of music after which a song of this session may come back:
    /// `noRepeatHours`, at least three.
    var repeatAfter: Double {
        let hours = settings.noRepeatHours
        return max(3, hours.isFinite ? hours : 12) * 3600
    }

    /// A track's length as the session counts music: four minutes when
    /// the server does not know it, at most an hour.
    func seconds(_ i: Int) -> Double {
        let d = snapshot.tracks[i].duration
        return d.isFinite && d > 0 ? min(d, 3600) : 240
    }

    /// What this session has learnt about a track: skips and thumbs on its
    /// artist and genres, artists heard lately, and likes it resembles.
    func dynamic(_ i: Int, _ ctx: Context) -> (factor: Double, likeStrength: Double, like: Int) {
        var f = 1.0
        let artists = index.trackArtists[i]
        var pressure = 0.0
        for (k, a) in artists.enumerated() {
            pressure += k == 0 ? artistPressure[a] : 0.5 * artistPressure[a]
            f *= k == 0 ? artistBan[a] : artistBan[a].squareRoot()
        }
        // One skip of a genre is a mood; two or three are a direction: the
        // pressure counts by its square. A sub-genre skipped once is worth
        // about 0.8, three times about 0.15 (docs/RADIO.md).
        var genre = 0.0
        for g in index.trackGenres[i] where genrePressure[g] > 0 {
            genre += genrePressure[g] * genrePressure[g]
        }
        f *= exp(-0.45 * pressure - 0.6 * genre)
        // Reached through an artist the listener skipped or turned down
        // ("Sounds like X" just after X was skipped): a share of that too.
        // Not through the artist the station is named after: on their
        // station everyone near is reached through them, and a song of
        // theirs thumbed down took 30% of their neighbours with it
        // (measured).
        if case let .artist(a) = channel[i], a < artistViaNow.count, artistViaNow[a] >= 0,
           !anchor.subject.contains(artistViaNow[a]) {
            let via = artistViaNow[a]
            f *= exp(-0.25 * artistPressure[via]) * artistBan[via].squareRoot()
        }
        // Variety: an artist heard lately counts against itself, by half a
        // track for each of their tracks in the last 30 — not one the
        // listener has just liked, who is welcome back (the separation rule
        // still keeps them apart).
        if let a = artists.first, a != anchor.capArtist, let count = ctx.recentArtists[a],
           !ctx.likedArtists.contains(a) {
            f /= 1 + 0.5 * Double(count)
        }
        var strongest = 0.0, byArtist = 0.0, which = -1
        for (k, like) in likes.enumerated() {
            let s = similarity(i, to: like)
            let value = s.value * ctx.likeDecay[k]
            if value > strongest {
                strongest = value
                byArtist = s.byArtist ? value : 0
                which = k
            }
        }
        f *= 1 + Self.likeBoost * strongest
        return (f, byArtist, which)
    }

    /// How like a liked track: by artist (its own, or a neighbour by the
    /// graph's weight), or by genres in common (half as much at most).
    func similarity(_ i: Int, to like: Like) -> (value: Double, byArtist: Bool) {
        var s = 0.0
        for a in index.trackArtists[i] { s = max(s, like.artists[a] ?? 0) }
        let artist = s
        let genres = index.trackGenres[i]
        if !genres.isEmpty, !like.genres.isEmpty {
            var shared = 0.0, union = 0.0
            for g in genres {
                let idf = index.genreIDF[g]
                union += idf
                if like.genres.contains(g) { shared += idf }
            }
            for g in like.genres where !genres.contains(g) { union += index.genreIDF[g] }
            if union > 0 { s = max(s, 0.5 * shared / union) }
        }
        return (s, artist > 0 && artist >= s)
    }

    /// What a repeat in a library that has run out waits for, in tracks
    /// handed out since: all but four of the library, or (when that leaves
    /// nothing that keeps the rules) half of it; at most 50. A library of
    /// one song repeats it rather than stop.
    static func repeatWindows(_ usable: Int) -> (long: Int, short: Int) {
        let short = max(0, min(50, usable / 2))
        return (max(short, min(50, usable - 4)), short)
    }

    /// The rules loosen one at a time (docs/RADIO.md, "Each pick"): first
    /// without repeats, then with them (the longest-unheard first), every
    /// rule again from the top, so a library that has run out repeats with
    /// its artists still kept apart. At each level the long window is
    /// tried before the short one: a song comes back sooner rather than
    /// two by one artist closer. Repeats used to come only once every rule
    /// was off: a 12-song library of four artists broke separation 352
    /// times in 6 × 120 picks and the album rule 126 times.
    enum Window { case none, long, short }
    static let steps: [(window: Window, wide: Bool, level: Int)] =
        [(.none, false, 0)] + (0...lastLevel).map { (.none, true, $0) }
        + (0...lastLevel).flatMap { [(.long, true, $0), (.short, true, $0)] }
    static let lastLevel = 5

    mutating func pickOne() -> RadioPick? {
        if needsScoring { scoreAll() }
        let ctx = context()
        let windows = Self.repeatWindows(ctx.usable)
        for step in Self.steps {
            if step.wide, rest == nil { makeRest() }
            let window: Int? = switch step.window {
            case .none: nil
            case .long: windows.long
            case .short: windows.short
            }
            if let pick = choose(wide: step.wide, window: window, level: step.level, ctx) { return pick }
        }
        return nil
    }

    mutating func choose(wide: Bool, window: Int?, level: Int, _ ctx: Context) -> RadioPick? {
        let adv = adventurousness
        let k = Self.breadth(adv)
        var top: [Candidate] = []
        top.reserveCapacity(k + 1)

        func consider(_ list: [Int], _ scores: [Double]) {
            for i in list {
                let b = scores[i]
                if top.count == k, let worst = top.last, b * ctx.maxBoost <= worst.score { break }
                guard b > 0 else { continue }
                let admitted = admission(i, window: window, level: level, ctx)
                guard admitted > 0 else { continue }
                let d = dynamic(i, ctx)
                let s = b * d.factor * admitted
                guard s > 0, s.isFinite else { continue }
                if top.count == k, let worst = top.last, s <= worst.score { continue }
                let candidate = Candidate(track: i, score: s, likeStrength: d.likeStrength, like: d.like)
                let at = top.firstIndex { $0.score < s } ?? top.count
                top.insert(candidate, at: at)
                if top.count > k { top.removeLast() }
            }
        }
        consider(pool, base)
        if wide, let rest { consider(rest, restBase) }
        guard !top.isEmpty else { return nil }

        // In proportion to the score, among the best K.
        let total = top.reduce(0) { $0 + $1.score }
        var u = rng.nextUnit() * total
        var chosen = top[top.count - 1]
        for candidate in top {
            u -= candidate.score
            if u < 0 {
                chosen = candidate
                break
            }
        }
        let i = chosen.track
        let inPool = closeness[i] > Self.minCloseness
        return RadioPick(track: snapshot.tracks[i],
                         reason: reason(for: i, inPool: inPool, likeStrength: chosen.likeStrength, like: chosen.like),
                         score: chosen.score)
    }

    mutating func firstPick() -> RadioPick? {
        if needsScoring { scoreAll() }
        if let t = anchor.seedTrack, !disliked.contains(t), lastAt[index.trackSong[t]] == nil {
            return RadioPick(track: snapshot.tracks[t], reason: .seed, score: 1)
        }
        var candidates = anchor.first.filter { !disliked.contains($0) && lastAt[index.trackSong[$0]] == nil }
        let fresh = candidates.filter { !recently.contains($0) && hoursSince[$0] >= settings.noRepeatHours }
        if !fresh.isEmpty { candidates = fresh }
        guard !candidates.isEmpty else { return nil }
        // One of the best liked that fits: a few to choose from, so the
        // same station does not always open with the same song.
        var scored: [(track: Int, score: Double)] = candidates.map { t in
            let fam = familiarity[t]
            var s = exp(1.6 * affinity[t] + 0.8 * (fam - 0.5))
            if snapshot.tracks[t].isFavorite { s *= 1.4 }
            let hours = hoursSince[t]
            if hours.isFinite { s *= 1 - 0.75 * exp2(-hours / 48) }
            s *= max(0.05, closeness[t])
            return (t, s.isFinite ? s : 0)
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : tiedBefore($0.track, $1.track) }
        // The best three (six on Your Station and Loved), and any as good
        // as 85% of the best, up to twelve: when little is known of the
        // listener most songs score alike, and Jazz Radio opened with one
        // of the same three songs for any random seed (measured).
        let least = anchor.kind == .personal || anchor.kind == .favorites ? 6 : 3
        let bar = 0.85 * (scored.first?.score ?? 0)
        var count = min(least, scored.count)
        while count < min(12, scored.count), scored[count].score >= bar { count += 1 }
        let top = Array(scored.prefix(count))
        let total = top.reduce(0) { $0 + $1.score }
        var chosen = top[0]
        if total > 0 {
            var u = rng.nextUnit() * total
            for candidate in top {
                u -= candidate.score
                if u < 0 {
                    chosen = candidate
                    break
                }
            }
        }
        let reason = anchor.firstReason ?? reason(for: chosen.track, inPool: true, likeStrength: 0, like: -1)
        return RadioPick(track: snapshot.tracks[chosen.track], reason: reason, score: chosen.score)
    }

    mutating func next(_ count: Int) -> [RadioPick] {
        guard count > 0, !snapshot.tracks.isEmpty else { return [] }
        if needsScoring || anchorBuiltFor != adventurousness { scoreAll() }
        var picks: [RadioPick] = []
        while picks.count < count {
            var pick: RadioPick?
            if !started {
                started = true
                pick = firstPick()
            }
            if pick == nil { pick = pickOne() }
            guard let pick, let i = index.trackByID[pick.track.id] else { break }
            hand(i)
            picks.append(pick)
        }
        return picks
    }

    mutating func hand(_ i: Int) {
        lastAt[index.trackSong[i]] = handed.count
        handed.append(i)
        handedEnd.append((handedEnd.last ?? 0) + seconds(i))
        // A skip's weight fades as the station plays on, 2% each track (half
        // in 34 tracks, about two hours). A thumbs down does not fade.
        for a in artistPressure.indices where artistPressure[a] > 0 {
            artistPressure[a] = artistPressure[a] < 0.01 ? 0 : artistPressure[a] * 0.98
        }
        for g in genrePressure.indices where genrePressure[g] > 0 {
            genrePressure[g] = genrePressure[g] < 0.01 ? 0 : genrePressure[g] * 0.98
        }
    }

    // MARK: - Reasons

    func reason(for i: Int, inPool: Bool, likeStrength: Double, like: Int) -> PickReason {
        let track = snapshot.tracks[i]
        // "Because you liked …" only when the like's artist, or one the graph
        // ties closely to it, is what lifted the track.
        if likeStrength >= 0.55, like >= 0, like < likes.count {
            return .becauseYouLiked(snapshot.tracks[likes[like].track].name)
        }
        let fam = familiarity[i]
        if anchor.kind == .discovery, fam < 0.15 { return .discovery }
        if anchor.kind == .favorites, track.isFavorite { return .favorite }
        guard inPool else { return fallbackReason(i) }
        switch channel[i] {
        case .seedTrack:
            return .seed
        case .track:
            if let r = addedReason[i], (added[i] ?? 0) >= (anchor.trackWeight[i] ?? 0) { return r }
            return anchor.trackReason[i] ?? .instantMix
        case let .artist(a):
            let via = a < artistViaNow.count ? artistViaNow[a] : -1
            if via >= 0 { return .similarArtist(index.artistRefs[via].name) }
            if anchor.kind == .personal, let r = tasteReason(i) { return r }
            return .byArtist(index.artistRefs[a].name)
        case let .genre(g):
            if anchor.kind == .personal, let r = tasteReason(i) { return r }
            // A favourite on a genre station: its taste factor (two to three
            // times) is as much the reason as the genre.
            if track.isFavorite, adventurousness < 0.5 { return .favorite }
            return g >= 0 ? .genre(index.genreNames[g]) : fallbackReason(i)
        case .era:
            return .era(anchor.decade ?? index.trackYear[i] / 10 * 10)
        case .none:
            return fallbackReason(i)
        }
    }

    /// On Your Station, where taste is the point: favourite, not heard in
    /// a while, or new.
    func tasteReason(_ i: Int) -> PickReason? {
        let adv = adventurousness
        if snapshot.tracks[i].isFavorite || affinity[i] >= 0.6 { return .favorite }
        if isRediscovery(i), adv >= 0.2 { return .rediscover }
        if familiarity[i] < 0.05, adv >= 0.5 { return .discovery }
        return nil
    }

    /// A track from outside the neighbourhood (the station ran out of its
    /// own): why it is this one rather than any other.
    func fallbackReason(_ i: Int) -> PickReason {
        if snapshot.tracks[i].isFavorite { return .favorite }
        if isRediscovery(i) { return .rediscover }
        if familiarity[i] < 0.05 { return .discovery }
        let year = index.trackYear[i]
        if year > 0 { return .era(year / 10 * 10) }
        if let g = index.trackGenres[i].first { return .genre(index.genreNames[g]) }
        return .discovery
    }

    // MARK: - Feedback

    mutating func record(_ feedback: RadioFeedback) {
        switch feedback {
        case let .finished(id):
            guard let i = index.trackByID[id] else { return }
            accept(i, weight: 1)
        case let .skipped(id, after):
            guard let i = index.trackByID[id] else { return }
            let listened = after.isFinite ? max(0, after) : 0
            switch PlayOutcome.of(listened: listened, duration: snapshot.tracks[i].duration) {
            case .completed, .liked: accept(i, weight: 1)
            case .partial: accept(i, weight: 0.25)
            case .skipped, .disliked: skip(i)
            }
        case let .liked(id):
            guard let i = index.trackByID[id] else { return }
            like(i)
        case let .disliked(id):
            guard let i = index.trackByID[id] else { return }
            dislike(i)
        }
        needsScoring = true
    }

    /// Heard: the profile moves a little toward it.
    mutating func accept(_ i: Int, weight: Double) {
        let genres = index.trackGenres[i]
        for g in genres {
            driftGenre[g] += weight / Double(genres.count)
            // Heard to the end: that genre was fine after all.
            genrePressure[g] *= exp(-0.3 * weight)
        }
        if let a = index.trackArtists[i].first {
            driftArtist[a] += weight
            artistPressure[a] *= exp(-0.5 * weight)
        }
        driftWeight += weight
    }

    mutating func like(_ i: Int) {
        accept(i, weight: 3)
        disliked.subtract(index.songTracks[index.trackSong[i]])
        var artists: [Int: Double] = [:]
        for a in index.trackArtists[i] {
            artists[a] = 1
            artistPressure[a] = 0
            artistBan[a] = 1
            for neighbor in graph.similarArtists(to: index.artistKeys[a], limit: 30) {
                if let b = index.artistByKey[neighbor.key] { artists[b] = max(artists[b] ?? 0, min(1, neighbor.weight)) }
            }
        }
        likes.removeAll { $0.track == i }
        likes.append(Like(track: i, at: handed.count, artists: artists, genres: index.trackGenres[i]))
        if likes.count > 4 { likes.removeFirst(likes.count - 4) }
    }

    /// Left early: that artist less for a while, its genres a little; the
    /// profile moves away.
    mutating func skip(_ i: Int) {
        skipped.formUnion(index.songTracks[index.trackSong[i]])
        for (k, a) in index.trackArtists[i].enumerated() { artistPressure[a] += k == 0 ? 1 : 0.4 }
        let genres = index.trackGenres[i]
        let direction = distinctiveness(of: genres)
        for (k, g) in genres.enumerated() {
            genrePressure[g] += direction[k]
            driftGenre[g] -= 1 / Double(genres.count)
        }
    }

    /// How much each genre sets a track apart from what the station plays
    /// now: 1 − its share of the station's best 300 (by score). Skipping a
    /// Shoegaze song on Rock Radio says "less Shoegaze", not "less Rock":
    /// every song there is Rock. Measured, this is what makes three skips
    /// move a station (docs/RADIO.md); weighting by the genre's
    /// specificity alone did not, as a sub-genre is barely rarer than its
    /// genre in a small library.
    func distinctiveness(of genres: [Int]) -> [Double] {
        guard !genres.isEmpty else { return [] }
        var carried = [Double](repeating: 0, count: genres.count)
        var total = 0.0
        for t in pool.prefix(300) {
            let w = base[t]
            total += w
            let own = index.trackGenres[t]
            for (k, g) in genres.enumerated() where own.contains(g) { carried[k] += w }
        }
        guard total > 0 else { return genres.map { index.genreIDF[$0] / maxSpecificity } }
        return carried.map { max(0.05, 1 - $0 / total) }
    }

    /// Thumbs down: the track is gone, its artist all but gone for the
    /// session, its genres a little less.
    mutating func dislike(_ i: Int) {
        disliked.formUnion(index.songTracks[index.trackSong[i]])
        likes.removeAll { $0.track == i }
        // 0.02: on the test server's small library 0.08 (tried first) let the
        // artist back three tracks later, when the rules had blocked everyone
        // else near.
        for (k, a) in index.trackArtists[i].enumerated() {
            artistBan[a] *= anchor.subject.contains(a) ? Self.subjectBan : (k == 0 ? 0.02 : 0.25)
        }
        let genres = index.trackGenres[i]
        let direction = distinctiveness(of: genres)
        for (k, g) in genres.enumerated() {
            genrePressure[g] += 1.5 * direction[k]
            driftGenre[g] -= 2 / Double(genres.count)
        }
    }

    mutating func addCandidates(_ ids: [ItemID], weight: Double, reason: PickReason) {
        let w = weight.isFinite ? min(1, max(0, weight)) : 0
        guard w > 0, !ids.isEmpty else { return }
        // In the order given, the first a little more: Instant Mix and
        // Last.fm list the closest first.
        for (rank, id) in ids.enumerated() {
            guard let t = index.trackByID[id] else { continue }
            // At most 0.9: the seed track keeps 1.
            let value = 0.9 * w * (1 - 0.3 * Double(rank) / Double(max(1, ids.count)))
            if value > (added[t] ?? 0) {
                added[t] = value
                addedReason[t] = reason
            }
        }
        needsScoring = true
    }

    mutating func returnUnplayed(_ ids: [ItemID]) {
        var removed = false
        for id in ids {
            guard let t = index.trackByID[id], let at = handed.lastIndex(of: t) else { continue }
            handed.remove(at: at)
            removed = true
        }
        guard removed else { return }
        // Positions moved: where each was handed, and the music up to it.
        lastAt.removeAll(keepingCapacity: true)
        handedEnd.removeAll(keepingCapacity: true)
        var total = 0.0
        for (k, t) in handed.enumerated() {
            lastAt[index.trackSong[t]] = k
            total += seconds(t)
            handedEnd.append(total)
        }
        if handed.isEmpty { started = false }
    }
}

extension TasteData {
    func hoursSinceHeard(id: ItemID) -> Double {
        index.trackByID[id].map { hoursSinceHeard[$0] } ?? .infinity
    }

    func isThumbedDown(id: ItemID) -> Bool {
        index.trackByID[id].map { thumbsDown[$0] } ?? false
    }
}
