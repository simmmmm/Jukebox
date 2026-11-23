// A station takes up what Last.fm says after it started: "Ja, doe maar"
// (the photographer, 24 November 2026), after Bunker Radio started a
// moment before Last.fm knew Balthazar. Its tags and similar artists came
// minutes later and the station never saw them. Lines starting RADIO-LATE
// are in docs/RADIO.md.

import Foundation
import JukeboxKit
import XCTest

final class RadioLateDataTests: XCTestCase {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func line(_ text: String) { print("RADIO-LATE " + text) }

    /// Bunker Radio's library as the station started: the seed artist with
    /// no genre, two artists of Last.fm's similar songs, two artists
    /// Last.fm names as the seed's neighbours a little later (no genre in
    /// the files either), a metalcore band and strangers he plays.
    struct Library {
        let plain: LibrarySnapshot
        let tagged: LibrarySnapshot
        let history: ListeningHistory
        static let seedArtist = "Harbour Lights"
        static let neighbours: Set<String> = ["Warm House", "Absent Minds"]
        static let hits: [ItemID] = ["n0", "r0"]

        init() {
            var tracks: [Track] = []
            var history = ListeningHistory()
            func add(_ prefix: String, _ artist: String, count: Int, genres: [String] = [], year: Int, gain: Double?, plays: Int = 0) {
                for k in 0..<count {
                    var t = RadioTestTracks.track("\(prefix)\(k)", artist, album: "\(artist) \(k / 10)", genres: genres, year: year,
                                                  number: k % 10 + 1, plays: plays,
                                                  lastPlayed: plays > 0 ? now.addingTimeInterval(-86_400 * 6) : nil, duration: 240)
                    t.normalizationGain = gain
                    tracks.append(t)
                    for d in 0..<plays {
                        history.append(PlayEvent(track: t, date: now.addingTimeInterval(-86_400 * Double(6 + d)), listened: 240, outcome: .completed))
                    }
                }
            }
            add("h", Self.seedArtist, count: 10, year: 2015, gain: nil)
            add("n", "Night Office", count: 40, year: 2013, gain: -11)
            add("r", "Red Road", count: 10, year: 2014, gain: -10)
            add("w", "Warm House", count: 15, year: 2016, gain: -9)
            add("a", "Absent Minds", count: 15, year: 2012, gain: -9.5)
            add("m", "Horizon Fall", count: 26, genres: ["Metalcore"], year: 2015, gain: -12, plays: 3)
            for s in 0..<8 { add("o\(s)-", "Stranger \(s)", count: 10, genres: s % 2 == 0 ? [] : ["Pop"], year: 2000 + s * 3, gain: -8, plays: 2) }
            plain = LibrarySnapshot(tracks: tracks)
            // Last.fm's tags, as they came for Balthazar: "indie", "belgian".
            let tags = [LibrarySnapshot.GenreTag(name: "indie", weight: 1), LibrarySnapshot.GenreTag(name: "belgian", weight: 0.9)]
            tagged = LibrarySnapshot(tracks: tracks, artistTags: [
                NameKey.artist(Self.seedArtist): tags,
                NameKey.artist("Warm House"): [LibrarySnapshot.GenreTag(name: "indie", weight: 1), LibrarySnapshot.GenreTag(name: "belgian", weight: 0.7)],
                NameKey.artist("Absent Minds"): [LibrarySnapshot.GenreTag(name: "indie", weight: 1)],
            ])
            self.history = history
        }

        /// The graph once Last.fm answered for the seed's artist.
        var lateGraph: SimilarityGraph {
            var graph = SimilarityGraph.fromLibrary(tagged)
            graph.addArtistEdge(NameKey.artist(Self.seedArtist), NameKey.artist("Warm House"), weight: 1)
            graph.addArtistEdge(NameKey.artist(Self.seedArtist), NameKey.artist("Absent Minds"), weight: 0.72)
            return graph
        }
    }

    struct Run {
        var before: [ItemID] = []
        var after: [RadioPick] = []
        var kept = true
    }

    /// The app's loop: the seed song, Last.fm's similar songs, 15 ahead,
    /// three of them heard; then (with `late`) Last.fm's answers for the
    /// seed's artist arrive: what is ahead after the next song is chosen
    /// again, and 30 more.
    func run(_ lib: Library, late: Bool, randomSeed: UInt64) -> Run {
        let taste = TasteProfile(snapshot: lib.plain, history: lib.history, now: Self.now)
        var session = RadioSession(station: Station(seed: .track("h0"), snapshot: lib.plain), snapshot: lib.plain, taste: taste,
                                   graph: .fromLibrary(lib.plain), settings: RadioSettings(adventurousness: 0), randomSeed: randomSeed)
        var queue = session.next(1).map(\.track.id)
        session.addCandidates(Library.hits, weight: 0.8, reason: .similarTrack("Song h0"))
        queue += session.next(15).map(\.track.id)
        for id in queue.prefix(4) { session.record(.finished(id)) }
        var r = Run()
        r.before = Array(queue.prefix(5))
        if late {
            let lateTaste = TasteProfile(snapshot: lib.tagged, history: lib.history, now: Self.now)
            XCTAssertTrue(session.takeUp(snapshot: lib.tagged, graph: lib.lateGraph, taste: lateTaste))
            // Again with the same: nothing new for its artists.
            XCTAssertFalse(session.takeUp(snapshot: lib.tagged, graph: lib.lateGraph, taste: lateTaste))
        }
        // Playing the fourth, the fifth loaded: those stay, the rest is chosen again.
        session.returnUnplayed(Array(queue.dropFirst(5)))
        r.kept = Array(session.handedOut.prefix(5)) == r.before
        r.after = session.next(30)
        return r
    }

    func testAStationTakesUpWhatLastFMSaysLater() {
        let lib = Library()
        var share: [Bool: Double] = [:]
        var strangers: [Bool: Int] = [:]
        for late in [false, true] {
            var near = 0, all = 0, odd = 0
            for seed in 0..<12 {
                let r = run(lib, late: late, randomSeed: UInt64(5200 + seed))
                XCTAssertTrue(r.kept, "the songs heard and the next one stay")
                XCTAssertTrue(Set(r.before).isDisjoint(with: r.after.map(\.track.id)), "nothing heard comes again")
                for pick in r.after {
                    let artist = pick.track.artists.first?.name ?? ""
                    all += 1
                    if Library.neighbours.contains(artist) { near += 1 }
                    if artist.hasPrefix("Stranger") || artist == "Horizon Fall" { odd += 1 }
                }
            }
            share[late] = Double(near) / Double(all)
            strangers[late] = odd
            Self.line(String(format: "Bunker Radio at Familiar, Last.fm's answers for its artist after the start, 12 × 30 picks after them: their neighbours %.3f, strangers %d (%@)",
                             share[late]!, odd, late ? "taken up" : "as it started"))
        }
        XCTAssertEqual(share[false], 0, "as it started the station knows nothing of them")
        XCTAssertGreaterThan(share[true]!, 0.2)
        XCTAssertEqual(strangers[true], 0)
    }

    func testOtherSongsAreNotTakenUp() {
        let lib = Library()
        let taste = TasteProfile(snapshot: lib.plain, history: lib.history, now: Self.now)
        var session = RadioSession(station: Station(seed: .track("h0"), snapshot: lib.plain), snapshot: lib.plain, taste: taste,
                                   graph: .fromLibrary(lib.plain), randomSeed: 1)
        _ = session.next(5)
        let other = LibrarySnapshot(tracks: Array(lib.plain.tracks.dropLast()))
        XCTAssertFalse(session.takeUp(snapshot: other, graph: .fromLibrary(other), taste: taste), "another library is a new station")
    }
}
