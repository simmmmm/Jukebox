// The server's own mix on a station: the photographer, 20 November 2026, of
// "Moans Radio" (Hania Rani) at Familiar on Linux, "er klopt toch nog steeds
// geen fuck van deze radio zo? gorillaz?? cocteau twins?", then "angele".
// All three stood in Up Next as "From Jellyfin's mix", between songs Last.fm
// had named ("Sounds like Hania Rani"). Jellyfin's mix is the songs that
// share a genre with the seed, in random order; from a song without a genre,
// as his "Moans" is, the whole library. Lines starting RADIO-MIX are in
// docs/RADIO.md.

import Foundation
import JukeboxKit
import XCTest

final class RadioServerMixTests: XCTestCase {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func line(_ text: String) { print("RADIO-MIX " + text) }

    /// A library in the shape of his: calm piano without a genre in the
    /// files (two thirds of his songs have none), named by Last.fm's tags
    /// and tied by its similar artists when there is a key, five artists in
    /// all; Gorillaz, Angèle (filed as "Angele", on Last.fm a page of its
    /// own, tagged Slayer) and Cocteau Twins; and the rest of a rock and pop
    /// library. The gains are his too: the piano records anywhere from −8 to
    /// +6 dB, the three at −8 … −4 around the seed's −5.8, so by loudness
    /// alone they fit better than Nils Frahm does.
    struct Calm {
        static let calm = ["Hania Rani", "Nils Frahm", "Eydís Evensen", "Hania Rani & Dobrawa Czocher", "Peter Broderick"]
        static let misfits = ["Gorillaz", "Angele", "Cocteau Twins"]

        let tracks: [Track]
        let snapshot: LibrarySnapshot
        let taste: TasteProfile
        let graph: SimilarityGraph
        let seed: Track
        /// Jellyfin's mix from the seed: the seed, then the library at
        /// random (no genre to ask by), one of each misfit near the top as
        /// his Up Next had them.
        let mix: [ItemID]

        init(key: Bool) {
            var tracks: [Track] = []
            func add(_ artist: String, _ count: Int, genres: (Int) -> [String], plays: Int, year: Int, gain: (Int) -> Double) {
                let slug = NameKey.artist(artist)
                for k in 0..<count {
                    var t = RadioTestTracks.track("\(slug)-\(k)", artist, album: "\(artist) \(k / 8)", genres: genres(k),
                                                  year: year + k / 8, number: k % 8 + 1, plays: plays,
                                                  lastPlayed: plays > 0 ? RadioServerMixTests.now.addingTimeInterval(-86_400 * Double(20 + k)) : nil)
                    t.normalizationGain = gain(k)
                    tracks.append(t)
                }
            }
            add("Hania Rani", 24, genres: { _ in [] }, plays: 8, year: 2019) { -4 + Double($0 % 5) }
            add("Nils Frahm", 13, genres: { _ in [] }, plays: 1, year: 2013) { -4 + 2 * Double($0 % 6) }
            add("Eydís Evensen", 24, genres: { _ in [] }, plays: 1, year: 2021) { -8 + Double($0 % 4) }
            add("Hania Rani & Dobrawa Czocher", 11, genres: { _ in [] }, plays: 1, year: 2021) { -3 + Double($0 % 4) }
            add("Peter Broderick", 12, genres: { _ in [] }, plays: 1, year: 2015) { -6 + Double($0 % 4) }
            add("Gorillaz", 24, genres: { [["Pop"], ["Alternative"], ["Breakbeat / Electro"]][$0 / 8] }, plays: 2, year: 2005) { -8 + Double($0 % 4) }
            add("Angele", 12, genres: { _ in [] }, plays: 2, year: 2018) { _ in -8 }
            add("Cocteau Twins", 60, genres: { _ in ["Alternative Rock"] }, plays: 2, year: 1984) { -8 + Double($0 % 5) }
            let rest: [(String, [String])] = [
                ("Velvet Static", ["Shoegaze"]), ("Low Lanterns", ["Shoegaze", "Dream Pop"]), ("Iron Meadow", ["Alternative Rock"]),
                ("Concrete Poets", ["Hip Hop"]), ("Loud Horizon", ["Metalcore"]), ("Fontaine Rows", ["Post-punk"]),
                ("Nightdrive", ["Electronic"]), ("Kalimba Sound System", ["Electronic"]), ("Sunny Side", ["Pop"]),
                ("Mira Lux", ["Contemporary Pop"]), ("Paper Harbour", ["Indie Rock"]), ("June Hollow", ["Folk rock"]),
            ]
            for (a, (name, genres)) in rest.enumerated() {
                add(name, 12, genres: { _ in genres }, plays: a % 3, year: 1995 + 2 * a) { -7 + Double($0 % 3) }
            }
            tracks[0].isFavorite = true
            tracks[0].playCount = 21
            tracks[0].normalizationGain = -5.8
            self.tracks = tracks
            seed = tracks[0]

            // What his cache has of Last.fm, 20 November 2026: the tags that
            // name a genre, at half their count, and the similar artists the
            // library has.
            func tags(_ list: [(String, Double)]) -> [LibrarySnapshot.GenreTag] {
                list.map { LibrarySnapshot.GenreTag(name: $0.0, weight: 0.5 * $0.1) }
            }
            let piano = tags([("Piano", 1), ("Ambient", 0.9), ("Modern Classical", 0.5), ("Contemporary Classical", 0.4)])
            var artistTags: [String: [LibrarySnapshot.GenreTag]] = [:]
            for name in Self.calm { artistTags[NameKey.artist(name)] = piano }
            artistTags[NameKey.artist("Gorillaz")] = tags([("Electronic", 1), ("Alternative", 1), ("Hip-Hop", 0.44), ("Rock", 0.36), ("Indie", 0.17)])
            artistTags[NameKey.artist("Cocteau Twins")] = tags([("Dream Pop", 1), ("Shoegaze", 0.75), ("Post-Punk", 0.42), ("Ethereal", 0.34)])
            artistTags[NameKey.artist("Angele")] = tags([("Slayer", 1), ("Pop", 1), ("Megadeth", 0.66)])
            snapshot = key ? LibrarySnapshot(tracks: tracks, artistTags: artistTags) : LibrarySnapshot(tracks: tracks)
            taste = TasteProfile(snapshot: snapshot, history: ListeningHistory(), now: RadioServerMixTests.now)
            var graph = SimilarityGraph.fromLibrary(snapshot)
            if key {
                let similar: [(String, String, Double)] = [
                    ("Hania Rani", "Nils Frahm", 1), ("Eydís Evensen", "Hania Rani", 0.99),
                    ("Hania Rani", "Hania Rani & Dobrawa Czocher", 0.97), ("Hania Rani", "Peter Broderick", 0.38),
                    ("Nils Frahm", "Peter Broderick", 0.5), ("Hania Rani & Dobrawa Czocher", "Eydís Evensen", 0.28),
                    ("Cocteau Twins", "Low Lanterns", 0.83), ("Cocteau Twins", "Velvet Static", 0.6),
                ]
                for (a, b, w) in similar { graph.addArtistEdge(NameKey.artist(a), NameKey.artist(b), weight: w) }
            }
            self.graph = graph

            var others = tracks.dropFirst().map(\.id)
            var rng = SplitMix64(seed: 20_261_120)
            for i in others.indices.reversed() where i > 0 { others.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
            let top = Self.misfits.map { NameKey.artist($0) + "-0" }
            mix = Array(([seed.id] + top + others.filter { !top.contains($0) }).prefix(100))
        }

        func isMisfit(_ pick: RadioPick) -> Bool { Self.misfits.contains(pick.track.albumArtist?.name ?? "") }
        func isCalm(_ pick: RadioPick) -> Bool { Self.calm.contains(pick.track.albumArtist?.name ?? "") }

        struct Count {
            var misfits = 0, fromMix = 0, calm = 0, all = 0
            var misfitShare: Double { Double(misfits) / Double(max(1, all)) }
            var calmShare: Double { Double(calm) / Double(max(1, all)) }
            var mixShare: Double { Double(fromMix) / Double(max(1, all)) }
        }

        /// "Moans Radio", 12 stations × 30 picks. `late`: the mix arrives
        /// after the first fifteen were chosen, and all but the first two go
        /// back and are chosen again, as the app does it.
        func stations(_ adventurousness: Double, mix weight: Double? = 0.5, late: Bool = false) -> Count {
            var count = Count()
            for run in 0..<12 {
                var session = RadioSession(station: Station(seed: .track(seed.id), snapshot: snapshot), snapshot: snapshot,
                                           taste: taste, graph: graph, settings: RadioSettings(adventurousness: adventurousness),
                                           randomSeed: UInt64(300 + run))
                var picks: [RadioPick] = []
                if late {
                    let first = session.next(15)
                    picks = Array(first.prefix(2))
                    if let weight { session.addCandidates(mix, weight: weight, reason: .instantMix) }
                    session.returnUnplayed(first.dropFirst(2).map(\.track.id))
                } else if let weight {
                    session.addCandidates(mix, weight: weight, reason: .instantMix)
                }
                picks += session.next(30 - picks.count)
                count.misfits += picks.filter(isMisfit).count
                count.fromMix += picks.filter { $0.reason == .instantMix }.count
                count.calm += picks.filter(isCalm).count
                count.all += picks.count
            }
            return count
        }
    }

    /// The photographer's station: with Last.fm's similar artists in the
    /// library, nothing the server's mix alone put forward plays at
    /// Familiar, at the app's weight or any other, whenever the mix
    /// arrives; and what Last.fm named keeps its own reason.
    func testTheServersMixDoesNotBringMisfitsToACalmStation() {
        let world = Calm(key: true)
        for adv in [0.0, 0.35, 0.7, 1.0] {
            let without = world.stations(adv, mix: nil)
            let with = world.stations(adv)
            Self.line(String(format: "Moans Radio with Last.fm, at %.2f, 12 x 30 picks: Gorillaz, Angele and Cocteau Twins %.3f with the server's mix (%.3f without it), \"From Jellyfin's mix\" %.3f, the calm artists %.3f (%.3f)",
                             adv, with.misfitShare, without.misfitShare, with.mixShare, with.calmShare, without.calmShare))
        }
        for weight in [0.5, 1.0] {
            for late in [false, true] {
                let familiar = world.stations(0, mix: weight, late: late)
                XCTAssertEqual(familiar.misfits, 0, "at Familiar, weight \(weight), late \(late)")
                XCTAssertEqual(familiar.fromMix, 0, "at Familiar, weight \(weight), late \(late)")
                XCTAssertEqual(familiar.all, 360)
                let middle = world.stations(0.35, mix: weight, late: late)
                XCTAssertEqual(middle.misfits, 0, "at the default, weight \(weight), late \(late)")
            }
        }
        // Toward Adventurous the mix has a small part at most.
        XCTAssertLessThanOrEqual(world.stations(1).misfitShare, world.stations(1, mix: nil).misfitShare + 0.05)
    }

    /// Without a key the library knows nothing of Hania Rani (no genre in
    /// the files, no guests): the station is her own songs every fifth, and
    /// the rest of the library by taste. How much worse that is; the
    /// server's mix places nothing there either.
    func testWithoutAKeyTheStationKnowsLittle() {
        let key = Calm(key: true), none = Calm(key: false)
        for adv in [0.0, 0.35, 1.0] {
            let a = key.stations(adv), b = none.stations(adv), c = none.stations(adv, mix: nil)
            Self.line(String(format: "Moans Radio at %.2f: the calm artists %.3f with Last.fm, %.3f without a key (%.3f without the server's mix); the three misfits %.3f, %.3f (%.3f); \"From Jellyfin's mix\" %.3f, %.3f",
                             adv, a.calmShare, b.calmShare, c.calmShare, a.misfitShare, b.misfitShare, c.misfitShare, a.mixShare, b.mixShare))
        }
        XCTAssertGreaterThan(key.stations(0).calmShare, none.stations(0).calmShare + 0.3)
        XCTAssertEqual(none.stations(0).fromMix, 0)
        XCTAssertEqual(none.stations(0).misfits, none.stations(0, mix: nil).misfits)
    }

    // MARK: The made-up library

    /// Song stations on RadioFixtures' library: one song of each of 16
    /// artists × 3 random seeds × 30 picks, the share by an artist of the
    /// seed's cluster.
    struct Row {
        var inCluster = 0.0, fromMix = 0.0, strays = 0.0, stations = 0.0
    }

    enum Mix { case none, jellyfin, knowing }

    /// `.jellyfin`: the seed, then the songs that share any genre with it,
    /// shuffled (dev/fake-jellyfin.swift, as Jellyfin 12.4 does it).
    /// `.knowing`: a server that does know what sounds alike (Navidrome
    /// with Last.fm, a sonic analysis): songs of the seed's cluster.
    static func mix(_ kind: Mix, for seed: Track, in w: RadioEvaluationTests.World, cluster: Int, random: UInt64) -> [ItemID] {
        var others: [ItemID]
        switch kind {
        case .none: return []
        case .jellyfin:
            others = w.library.tracks.filter { $0.id != seed.id && !Set($0.genres).isDisjoint(with: seed.genres) }.map(\.id)
        case .knowing:
            others = w.library.tracks.filter {
                $0.id != seed.id && w.snapshot.primaryArtistKey(of: $0).flatMap { w.library.clusterOfArtist[$0] } == cluster
            }.map(\.id)
        }
        var rng = SplitMix64(seed: random)
        for i in others.indices.reversed() where i > 0 { others.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        return Array(([seed.id] + others).prefix(100))
    }

    static func songStations(_ w: RadioEvaluationTests.World, graph: SimilarityGraph, adventurousness: Double, mix kind: Mix) -> Row {
        var row = Row()
        for artist in w.library.artists.prefix(16) {
            guard let seed = w.library.tracks.first(where: { $0.albumArtist?.id == artist.id }) else { continue }
            for run in 0..<3 {
                var session = RadioSession(station: Station(seed: .track(seed.id), snapshot: w.snapshot), snapshot: w.snapshot,
                                           taste: w.taste, graph: graph, settings: RadioSettings(adventurousness: adventurousness),
                                           randomSeed: UInt64(run * 1000 + artist.cluster))
                let mix = Self.mix(kind, for: seed, in: w, cluster: artist.cluster, random: UInt64(run + 1))
                session.addCandidates(mix, weight: 0.5, reason: .instantMix)
                let picks = session.next(30)
                let n = Double(picks.count)
                row.inCluster += Double(picks.filter { w.clusterOf($0) == artist.cluster }.count) / n
                row.fromMix += Double(picks.filter { $0.reason == .instantMix }.count) / n
                row.strays += Double(picks.filter { $0.reason == .instantMix && w.clusterOf($0) != artist.cluster }.count) / n
                row.stations += 1
            }
        }
        row.inCluster /= row.stations
        row.fromMix /= row.stations
        row.strays /= row.stations
        return row
    }

    /// Whether the server's mix should feed a station at all: in cluster
    /// with no mix, with Jellyfin's, and with one that knows, by the
    /// library's own graph (no key) and with Last.fm-like edges (every
    /// artist tied to its cluster, 0.9 in its sub-genre, 0.5 beside it).
    func testWhatTheServersMixAddsOnTheMadeUpLibrary() {
        let w = RadioEvaluationTests.shared
        var lastFM = w.graph
        for a in w.library.artists {
            for b in w.library.artists where a.cluster == b.cluster && a.key != b.key {
                lastFM.addArtistEdge(a.key, b.key, weight: a.subgenre == b.subgenre ? 0.9 : 0.5)
            }
        }
        Self.line("song stations, 16 seeds x 3 random seeds x 30 picks: in cluster (\"From Jellyfin's mix\", of those outside the cluster)")
        var results: [String: Row] = [:]
        for (graphName, graph) in [("no key", w.graph), ("Last.fm", lastFM)] {
            for (mixName, kind) in [("no mix", Mix.none), ("Jellyfin's mix", .jellyfin), ("a mix that knows", .knowing)] {
                var cells: [String] = []
                for adv in [0.0, 0.35, 0.7, 1.0] {
                    let row = Self.songStations(w, graph: graph, adventurousness: adv, mix: kind)
                    results["\(graphName) \(mixName) \(adv)"] = row
                    cells.append(String(format: "%.2f: %.3f (%.3f, %.3f)", adv, row.inCluster, row.fromMix, row.strays))
                }
                Self.line("\(graphName), \(mixName) | " + cells.joined(separator: " | "))
            }
        }
        // Jellyfin's mix costs a station nothing at Familiar or the default,
        // key or no key, and brings nothing in from outside the cluster.
        for graphName in ["no key", "Last.fm"] {
            for adv in [0.0, 0.35] {
                let plain = results["\(graphName) no mix \(adv)"]!, mixed = results["\(graphName) Jellyfin's mix \(adv)"]!
                XCTAssertGreaterThanOrEqual(mixed.inCluster, plain.inCluster - 0.01, "\(graphName) at \(adv)")
                XCTAssertEqual(mixed.strays, 0, accuracy: 0.001, "\(graphName) at \(adv)")
            }
        }
    }
}
