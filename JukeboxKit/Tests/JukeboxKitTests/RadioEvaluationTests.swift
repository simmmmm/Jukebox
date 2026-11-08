// The radio, measured (docs/RADIO.md has these numbers). On the made-up
// library of RadioFixtures: does a station stay near its seed, does it
// keep its rules, does it listen, and does the dial do what it says.
// Prints a report (`--filter RadioEvaluation` shows it) and holds the
// numbers to the bar the radio was tuned to.

import Foundation
import JukeboxKit
import XCTest

final class RadioEvaluationTests: XCTestCase {
    struct World {
        let library: RadioSyntheticLibrary
        let snapshot: LibrarySnapshot
        let taste: TasteProfile
        let graph: SimilarityGraph

        init(_ library: RadioSyntheticLibrary = RadioSyntheticLibrary()) {
            self.library = library
            snapshot = LibrarySnapshot(tracks: library.tracks)
            taste = TasteProfile(snapshot: snapshot, history: library.history, now: library.now)
            graph = SimilarityGraph.fromLibrary(snapshot)
        }

        func session(_ seed: StationSeed, adventurousness: Double = 0.35, randomSeed: UInt64) -> RadioSession {
            RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot, taste: taste, graph: graph,
                         settings: RadioSettings(adventurousness: adventurousness), randomSeed: randomSeed)
        }

        func artistSeed(_ info: RadioSyntheticLibrary.ArtistInfo) -> StationSeed {
            .artist(key: info.key, name: info.name, id: info.id)
        }

        /// By an artist of the seed artist's cluster, or by (or with) the seed
        /// artist or one of its neighbours in the graph.
        func coherent(_ pick: RadioPick, seed: RadioSyntheticLibrary.ArtistInfo) -> Bool {
            let keys = snapshot.artistKeys(of: pick.track)
            guard let primary = keys.first else { return false }
            if library.clusterOfArtist[primary] == seed.cluster { return true }
            return keys.contains { $0 == seed.key || graph.weight(seed.key, $0) > 0 }
        }

        func clusterOf(_ pick: RadioPick) -> Int? {
            snapshot.primaryArtistKey(of: pick.track).flatMap { library.clusterOfArtist[$0] }
        }

        func unheard(_ pick: RadioPick) -> Bool {
            pick.track.playCount == 0 && taste.familiarity(pick.track.id) == 0
        }
    }

    nonisolated(unsafe) static var world: World?
    static var shared: World {
        if let world { return world }
        let made = World()
        world = made
        return made
    }

    static func line(_ text: String) {
        print("RADIO-EVAL " + text)
    }

    // MARK: Coherence, rules, variety, the dial

    struct DialNumbers {
        var coherence = 0.0
        var inCluster = 0.0
        /// In cluster, for seeds the listener plays and for those they do not.
        var inClusterPlayed = 0.0
        var inClusterUnplayed = 0.0
        var played = 0.0
        var unplayed = 0.0
        var unheard = 0.0
        var favorites = 0.0
        var distinctArtists = 0.0
        var seedArtistShare = 0.0
        var separation = 0
        var repeats = 0
        var albums = 0
        var picks = 0
    }

    static func dial(_ adventurousness: Double, world w: World, runs: Int = 3, length: Int = 50) -> DialNumbers {
        var n = DialNumbers()
        var stations = 0
        // Two artists of every cluster, three random seeds each.
        let seeds = w.library.artists.enumerated().filter { $0.offset < 16 }.map(\.element)
        for seedArtist in seeds {
            for run in 0..<runs {
                var session = w.session(w.artistSeed(seedArtist), adventurousness: adventurousness,
                                        randomSeed: UInt64(run * 1000 + seedArtist.cluster))
                let picks = session.next(length)
                stations += 1
                n.picks += picks.count
                n.coherence += Double(picks.filter { w.coherent($0, seed: seedArtist) }.count) / Double(picks.count)
                let inCluster = Double(picks.filter { w.clusterOf($0) == seedArtist.cluster }.count) / Double(picks.count)
                n.inCluster += inCluster
                if seedArtist.liking > 0 {
                    n.inClusterPlayed += inCluster
                    n.played += 1
                } else {
                    n.inClusterUnplayed += inCluster
                    n.unplayed += 1
                }
                n.unheard += Double(picks.filter(w.unheard).count) / Double(picks.count)
                n.favorites += Double(picks.filter(\.track.isFavorite).count) / Double(picks.count)
                n.distinctArtists += Double(RadioMetrics.distinctArtists(picks, snapshot: w.snapshot))
                n.seedArtistShare += Double(picks.dropFirst().filter {
                    w.snapshot.artistKeys(of: $0.track).contains(seedArtist.key)
                }.count) / Double(max(1, picks.count - 1))
                n.separation += RadioMetrics.separationViolations(picks, snapshot: w.snapshot, separation: 3)
                n.repeats += RadioMetrics.repeats(picks)
                n.albums += RadioMetrics.albumBackToBack(picks)
            }
        }
        let s = Double(stations)
        n.coherence /= s
        n.inCluster /= s
        n.inClusterPlayed /= max(1, n.played)
        n.inClusterUnplayed /= max(1, n.unplayed)
        n.unheard /= s
        n.favorites /= s
        n.distinctArtists /= s
        n.seedArtistShare /= s
        return n
    }

    func testDialCoherenceAndRules() {
        let w = Self.shared
        Self.line("library: \(w.snapshot.tracks.count) tracks, \(w.snapshot.artistTrackCounts.count) artists, "
            + "\(w.snapshot.genreTrackCounts.count) genres; graph: \(w.graph.artistKeys.count) artists with edges")
        Self.line("artist stations, 16 seeds x 3 random seeds x 50 picks")
        Self.line("adv  | coherent | in cluster (played/unplayed seeds) | unheard | favourites | distinct artists/50 | seed artist share | sep/repeat/album violations")
        var results: [Double: DialNumbers] = [:]
        for adv in [0.0, 0.35, 0.7, 1.0] {
            let n = Self.dial(adv, world: w)
            results[adv] = n
            Self.line(String(format: "%.2f | %.3f    | %.3f (%.3f/%.3f)              | %.3f   | %.3f      | %.1f                | %.3f             | %d/%d/%d",
                             adv, n.coherence, n.inCluster, n.inClusterPlayed, n.inClusterUnplayed, n.unheard, n.favorites, n.distinctArtists,
                             n.seedArtistShare, n.separation, n.repeats, n.albums))
            XCTAssertEqual(n.separation, 0, "artist separation at \(adv)")
            XCTAssertEqual(n.repeats, 0, "repeats at \(adv)")
            XCTAssertEqual(n.albums, 0, "same album back to back at \(adv)")
            XCTAssertLessThanOrEqual(n.seedArtistShare, 0.21, "the seed artist at most one in five, at \(adv)")
        }
        let familiar = results[0]!, middle = results[0.35]!, far = results[1]!
        XCTAssertGreaterThanOrEqual(familiar.coherence, 0.9)
        XCTAssertGreaterThanOrEqual(middle.coherence, 0.8)
        XCTAssertLessThan(far.coherence, familiar.coherence)
        XCTAssertLessThan(familiar.unheard, middle.unheard)
        XCTAssertLessThan(middle.unheard, far.unheard)
        XCTAssertGreaterThan(familiar.favorites, far.favorites)
        XCTAssertGreaterThanOrEqual(middle.distinctArtists, 8)
        XCTAssertGreaterThan(far.distinctArtists, familiar.distinctArtists)
    }

    // MARK: Listening

    func testDislikeRemovesTheArtist() {
        let w = Self.shared
        var before = 0.0, after = 0.0, runs = 0.0
        for seedArtist in w.library.artists.prefix(16) {
            for run in 0..<3 {
                var control = w.session(w.artistSeed(seedArtist), randomSeed: UInt64(77 + run))
                var session = w.session(w.artistSeed(seedArtist), randomSeed: UInt64(77 + run))
                let opening = session.next(6)
                _ = control.next(6)
                // Thumbs down on the first pick not by the seed artist.
                guard let victim = opening.dropFirst().first(where: {
                    w.snapshot.primaryArtistKey(of: $0.track) != seedArtist.key
                }), let x = w.snapshot.primaryArtistKey(of: victim.track) else { continue }
                let unplayed = session.handedOut.drop { $0 != victim.track.id }.dropFirst()
                session.record(.disliked(victim.track.id))
                session.returnUnplayed(Array(unplayed))
                control.returnUnplayed(Array(unplayed))
                let next = session.next(30)
                let baseline = control.next(30)
                after += Double(next.filter { w.snapshot.artistKeys(of: $0.track).contains(x) }.count)
                before += Double(baseline.filter { w.snapshot.artistKeys(of: $0.track).contains(x) }.count)
                runs += 1
                XCTAssertFalse(next.contains { $0.track.id == victim.track.id })
            }
        }
        Self.line(String(format: "dislike: the disliked track's artist in the next 30 picks: %.2f without the dislike, %.2f after (%d stations)",
                         before / runs, after / runs, Int(runs)))
        XCTAssertLessThan(after / runs, 0.2)
        XCTAssertLessThan(after, before / 4)
    }

    func testThreeSkipsMoveTheStation() {
        let w = Self.shared
        // Rock Radio; the listener skips Shoegaze three times.
        let seed = StationSeed.genre(key: NameKey.genre("Rock"), name: "Rock")
        let skippedGenre = NameKey.genre("Shoegaze")
        var before = 0.0, after = 0.0, runs = 0.0
        for run in 0..<12 {
            var control = w.session(seed, randomSeed: UInt64(500 + run))
            var session = w.session(seed, randomSeed: UInt64(500 + run))
            var skips = 0
            var steps = 0
            // Play on, skipping every Shoegaze track until three are skipped.
            while skips < 3, steps < 60 {
                guard let pick = session.next(1).first else { break }
                _ = control.next(1)
                steps += 1
                if w.snapshot.genreKeys(of: pick.track).contains(skippedGenre) {
                    session.record(.skipped(pick.track.id, after: 8))
                    skips += 1
                } else {
                    session.record(.finished(pick.track.id))
                    control.record(.finished(pick.track.id))
                }
            }
            guard skips == 3 else { continue }
            let next = session.next(30)
            let baseline = control.next(30)
            after += Double(next.filter { w.snapshot.genreKeys(of: $0.track).contains(skippedGenre) }.count) / 30
            before += Double(baseline.filter { w.snapshot.genreKeys(of: $0.track).contains(skippedGenre) }.count) / 30
            runs += 1
        }
        Self.line(String(format: "three skips of Shoegaze on Rock Radio: its share of the next 30 picks %.3f without the skips, %.3f after (%d runs)",
                         before / runs, after / runs, Int(runs)))
        XCTAssertGreaterThan(runs, 6)
        XCTAssertLessThan(after, before * 0.5)
    }

    func testLikeRaisesSimilarPicks() {
        let w = Self.shared
        var before = 0.0, after = 0.0, because = 0.0, runs = 0.0
        var ownBefore = 0.0, ownAfter = 0.0
        for seedArtist in w.library.artists.prefix(16) {
            for run in 0..<2 {
                var control = w.session(w.artistSeed(seedArtist), adventurousness: 0.6, randomSeed: UInt64(900 + run))
                var session = w.session(w.artistSeed(seedArtist), adventurousness: 0.6, randomSeed: UInt64(900 + run))
                let opening = session.next(5)
                _ = control.next(5)
                guard let liked = opening.dropFirst().first(where: {
                    w.snapshot.primaryArtistKey(of: $0.track) != seedArtist.key
                }), let y = w.snapshot.primaryArtistKey(of: liked.track) else { continue }
                session.record(.liked(liked.track.id))
                let unplayed = Array(session.handedOut.drop { $0 != liked.track.id }.dropFirst())
                session.returnUnplayed(unplayed)
                control.returnUnplayed(unplayed)
                let near = { (p: RadioPick) -> Bool in
                    guard let k = w.snapshot.primaryArtistKey(of: p.track) else { return false }
                    return k == y || w.graph.weight(y, k) >= 0.5
                }
                let own = { (p: RadioPick) -> Bool in w.snapshot.primaryArtistKey(of: p.track) == y }
                let next = session.next(15)
                let baseline = control.next(15)
                after += Double(next.filter(near).count) / 15
                before += Double(baseline.filter(near).count) / 15
                ownAfter += Double(next.filter(own).count) / 15
                ownBefore += Double(baseline.filter(own).count) / 15
                because += Double(next.filter { if case .becauseYouLiked = $0.reason { true } else { false } }.count) / 15
                runs += 1
            }
        }
        Self.line(String(format: "like (at 0.6): in the next 15 picks, the liked track's artist %.3f without the like, %.3f after; with its close neighbours (edge >= 0.5) %.3f, %.3f; \"Because you liked\" on %.3f",
                         ownBefore / runs, ownAfter / runs, before / runs, after / runs, because / runs))
        // Three tracks between two by one artist hold any artist to a quarter
        // of the picks; the like moves the liked artist toward that.
        XCTAssertGreaterThan(ownAfter, ownBefore * 1.15)
        XCTAssertGreaterThan(after, before * 1.1)
        XCTAssertGreaterThan(because, 0)
    }

    // MARK: Every kind of seed

    func testEverySeedStartsRightAndRunsLong() {
        let w = Self.shared
        let snapshot = w.snapshot
        let artist = w.library.artists[0]
        let track = snapshot.tracks[40]
        let album = snapshot.tracks[100]
        let playlist = Array(snapshot.tracks.filter { $0.isFavorite }.prefix(12).map(\.id))
        let seeds: [(String, StationSeed)] = [
            ("track", .track(track.id)),
            ("artist", w.artistSeed(artist)),
            ("album", .album(album.albumID!)),
            ("genre", .genre(key: NameKey.genre("Jazz"), name: "Jazz")),
            ("decade", .decade(1990)),
            ("collection", .collection(id: "pl1", name: "Mine", trackIDs: playlist)),
            ("personal", .personal),
            ("discovery", .discovery),
            ("favorites", .favorites),
        ]
        for (name, seed) in seeds {
            var session = w.session(seed, randomSeed: 3)
            let picks = session.next(200)
            XCTAssertEqual(picks.count, 200, name)
            XCTAssertEqual(RadioMetrics.repeats(picks), 0, name)
            XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: snapshot, separation: 3), 0, name)
            guard let first = picks.first else { continue }
            let firstLine: String
            switch seed {
            case .track:
                XCTAssertEqual(first.track.id, track.id)
                XCTAssertEqual(first.reason, .seed)
                firstLine = "the seed track"
            case .artist:
                XCTAssertEqual(snapshot.primaryArtistKey(of: first.track), artist.key)
                firstLine = "by the artist, affinity \(String(format: "%.2f", w.taste.trackAffinity(first.track.id)))"
            case .album:
                XCTAssertEqual(first.track.albumID, album.albumID)
                firstLine = "from the album"
            case .genre:
                XCTAssertTrue(snapshot.genreKeys(of: first.track).contains(NameKey.genre("Jazz")))
                firstLine = "Jazz, affinity \(String(format: "%.2f", w.taste.trackAffinity(first.track.id)))"
            case .decade:
                XCTAssertEqual((first.track.year ?? 0) / 10 * 10, 1990)
                firstLine = "from \(first.track.year ?? 0)"
            case .collection:
                XCTAssertTrue(playlist.contains(first.track.id))
                firstLine = "from the playlist"
            case .personal:
                XCTAssertGreaterThan(w.taste.trackAffinity(first.track.id), 0.3)
                firstLine = "affinity \(String(format: "%.2f", w.taste.trackAffinity(first.track.id)))"
            case .discovery:
                XCTAssertLessThan(w.taste.familiarity(first.track.id), 0.2)
                firstLine = "familiarity \(String(format: "%.2f", w.taste.familiarity(first.track.id)))"
            case .favorites:
                XCTAssertTrue(first.track.isFavorite)
                firstLine = "a favourite"
            }
            let reasons = Dictionary(grouping: picks.prefix(50), by: { Self.reasonKind($0.reason) }).mapValues(\.count)
            let summary = reasons.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            Self.line("\(name): first \(firstLine); reasons in 50: \(summary)")
        }
    }

    static func reasonKind(_ reason: PickReason) -> String {
        switch reason {
        case .seed: "seed"
        case .byArtist: "byArtist"
        case .similarArtist: "similarArtist"
        case .similarTrack: "similarTrack"
        case .genre: "genre"
        case .era: "era"
        case .favorite: "favorite"
        case .rediscover: "rediscover"
        case .discovery: "discovery"
        case .becauseYouLiked: "becauseYouLiked"
        case .instantMix: "instantMix"
        }
    }
}
