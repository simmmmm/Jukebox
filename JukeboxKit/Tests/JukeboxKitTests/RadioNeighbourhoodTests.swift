// A song station stays near its song: "radio gaat nog steeds niet echt
// lekker hoor, wat doet bring me the horizon hier of maruja" (the
// photographer, 24 November 2026, of Bunker Radio at Familiar). Balthazar
// has no genre in his files and Last.fm had not yet named its similar
// artists when the station started, so it knew twelve songs: Balthazar's
// own and two that Last.fm finds like "Bunker". Every other pick was a
// stranger that only taste ranked, "From the 2010s". Lines starting
// RADIO-NEAR are in docs/RADIO.md.

import Foundation
import JukeboxKit
import XCTest

final class RadioNeighbourhoodTests: XCTestCase {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func line(_ text: String) { print("RADIO-NEAR " + text) }

    /// A library in the shape of his at the station's start. The seed
    /// artist without genre or gain; the two artists of Last.fm's similar
    /// songs as loud as the metalcore band (his The National −10 … −12 dB,
    /// Bring Me The Horizon −11.6 … −13), so loudness cannot tell them
    /// apart; a ten-minute post-punk band as loud; strangers he plays more
    /// than any of them.
    struct Bunker {
        let snapshot: LibrarySnapshot
        let taste: TasteProfile
        let graph: SimilarityGraph
        static let seedArtist = "Harbour Lights"
        static let near: Set<String> = [seedArtist, "Night Office", "Red Road"]
        static let seed: ItemID = "h0"
        /// Last.fm's similar songs for the seed that are in the library.
        static let hits: [ItemID] = ["n0", "r0"]

        init() {
            var tracks: [Track] = []
            var history = ListeningHistory()
            func add(_ id: String, _ artist: String, album: String, genres: [String] = [], year: Int, gain: Double?,
                     duration: TimeInterval = 240, plays: Int = 0) {
                var t = RadioTestTracks.track(id, artist, album: album, genres: genres, year: year, number: tracks.count % 10 + 1,
                                              plays: plays, lastPlayed: plays > 0 ? now.addingTimeInterval(-86_400 * 6) : nil,
                                              duration: duration)
                t.normalizationGain = gain
                tracks.append(t)
                for d in 0..<plays {
                    history.append(PlayEvent(track: t, date: now.addingTimeInterval(-86_400 * Double(6 + d)),
                                             listened: duration, outcome: .completed))
                }
            }
            for k in 0..<10 { add("h\(k)", Self.seedArtist, album: "Thin Walls", year: 2015, gain: nil, duration: 200 + Double(k * 12), plays: k == 0 ? 1 : 0) }
            for k in 0..<40 { add("n\(k)", "Night Office", album: "Night Office \(k / 10)", year: 2010 + k / 5, gain: -10 - Double(k % 5) * 0.5) }
            for k in 0..<10 { add("r\(k)", "Red Road", album: "Red Road", year: 2014, gain: -9.3 - Double(k % 3) * 0.5) }
            for k in 0..<26 {
                add("m\(k)", "Horizon Fall", album: "Horizon \(k / 13)", genres: ["Metalcore"], year: 2013 + k / 13 * 6,
                    gain: -11.6 - Double(k % 4) * 0.4, duration: 250, plays: 3)
            }
            for k in 0..<12 { add("x\(k)", "Marula", album: "Marula", year: 2023, gain: -9.7 - Double(k % 4) * 0.5, duration: 604, plays: 2) }
            // Strangers: piano, britpop, electronic, pop, as his library has.
            let others: [(String, [String], Double, Int)] = [
                ("Quiet Keys", [], 5, 2020), ("Snow Hall", [], 7, 2018), ("Brit Rows", [], -13, 1995),
                ("Pulse Garden", ["Electronic"], -7, 1998), ("Velvet Pop", ["Pop"], -8, 2017), ("Low Coast", ["Rock"], -9, 2021),
                ("Dust Choir", [], -6, 2016), ("Neon Wells", ["Electronic"], -5, 2012), ("Saffron", ["Pop"], -9, 2019),
                ("Old Pier", [], -8, 2008),
            ]
            for (a, (name, genres, gain, year)) in others.enumerated() {
                for k in 0..<10 {
                    add("o\(a)-\(k)", name, album: name, genres: genres, year: year, gain: gain - Double(k % 3) * 0.3,
                        duration: 180 + Double((a * 7 + k * 13) % 120), plays: 2 + (a + k) % 3)
                }
            }
            snapshot = LibrarySnapshot(tracks: tracks)
            taste = TasteProfile(snapshot: snapshot, history: history, now: now)
            graph = .fromLibrary(snapshot)
        }

        /// The station as the app plays it: the seed song, then Last.fm's
        /// similar songs arrive (`addCandidates`, as `RadioController`
        /// passes them; his first two picks were theirs, so they were in
        /// by then) and the rest is chosen.
        func picks(adventurousness: Double, randomSeed: UInt64, count: Int = 30) -> [RadioPick] {
            var session = RadioSession(station: Station(seed: .track(Self.seed), snapshot: snapshot), snapshot: snapshot,
                                       taste: taste, graph: graph, settings: RadioSettings(adventurousness: adventurousness),
                                       randomSeed: randomSeed)
            var picks = session.next(1)
            session.addCandidates(Self.hits, weight: 0.8, reason: .similarTrack("Song h0"))
            picks += session.next(count - 1)
            return picks
        }
    }

    struct Tally {
        var all = 0, strangers = 0, metalcore = 0, long = 0, near = 0, own = 0
        var wrongLike = 0
        var soundsLike = 0
        /// Where the first stranger came, in each run that had one.
        var firstStranger: [Int] = []
    }

    func tally(_ bunker: Bunker, adventurousness: Double, count: Int) -> Tally {
        var t = Tally()
        for run in 0..<12 {
            var first: Int?
            for (k, pick) in bunker.picks(adventurousness: adventurousness, randomSeed: UInt64(4100 + run), count: count).enumerated().dropFirst() {
                let artist = pick.track.artists.first?.name ?? ""
                t.all += 1
                if Bunker.near.contains(artist) {
                    t.near += 1
                } else {
                    t.strangers += 1
                    if first == nil { first = k }
                }
                if artist == Bunker.seedArtist { t.own += 1 }
                if artist == "Horizon Fall" { t.metalcore += 1 }
                if artist == "Marula" { t.long += 1 }
                // "Like “Song”" only for the songs Last.fm named.
                if case .similarTrack = pick.reason, !Bunker.hits.contains(pick.track.id) { t.wrongLike += 1 }
                if pick.reason == .similarArtist(Bunker.seedArtist) { t.soundsLike += 1 }
            }
            if let first { t.firstStranger.append(first) }
        }
        return t
    }

    func testASongStationStaysInItsNeighbourhood() {
        let bunker = Bunker()
        var at: [Double: Tally] = [:]
        for adv in [0.0, 0.35] {
            let t = tally(bunker, adventurousness: adv, count: 60)
            Self.line("Bunker Radio at \(adv), 12 × 59 picks: strangers \(t.strangers), metalcore \(t.metalcore), the ten-minute band \(t.long), the seed artist \(t.own); first stranger at \(t.firstStranger.min().map(String.init) ?? "none") in \(t.firstStranger.count) runs")
            // The neighbourhood is 60 songs: strangers only once nearly all
            // of them have played, not once two of its three artists have.
            XCTAssertGreaterThanOrEqual(t.firstStranger.min() ?? 60, 50, "the first stranger at \(adv)")
        }
        for adv in [0.0, 0.35, 0.7, 1.0] {
            let t = tally(bunker, adventurousness: adv, count: 30)
            at[adv] = t
            let share = { (n: Int) in String(format: "%.3f", Double(n) / Double(max(1, t.all))) }
            Self.line("Bunker Radio in his shape at \(adv), 12 × 29 picks: strangers \(share(t.strangers)), metalcore \(t.metalcore), the ten-minute band \(t.long), \"Sounds like\" \(share(t.soundsLike)), the seed artist \(share(t.own))")
            XCTAssertEqual(t.wrongLike, 0, "\"Like\" on a song Last.fm did not name at \(adv)")
        }
        // Familiar and the default: the neighbourhood, never the far-out.
        for adv in [0.0, 0.35] {
            let t = at[adv]!
            XCTAssertEqual(t.metalcore, 0, "metalcore at \(adv)")
            XCTAssertEqual(t.long, 0, "the ten-minute band at \(adv)")
            XCTAssertLessThan(Double(t.strangers) / Double(t.all), 0.05, "strangers at \(adv)")
            XCTAssertGreaterThan(t.soundsLike, 0, "the similar songs' artists join at \(adv)")
        }
        // Further out, strangers come, as long as the station's songs: the
        // ten-minute band came 20 times at 0.7 before its length counted.
        XCTAssertEqual(at[0.7]!.long, 0)
        XCTAssertGreaterThan(at[1.0]!.strangers, 0)
    }
}
