// The radio's speed on a 20 000-track library (docs/RADIO.md, "Speed").
// The bar, release build: the snapshot under 500 ms, a session built and its
// first five tracks under 300 ms, each next five well under 50 ms. Debug
// builds (the default `swift test`) are several times slower, so there the
// bounds are loose and only catch something gone badly wrong; the real
// numbers come from
//   KIT_DIR=… dev/kit-test.sh -c release -Xswiftc -enable-testing --filter RadioPerformance

import Foundation
import JukeboxKit
import XCTest

final class RadioPerformanceTests: XCTestCase {
    static func time<T>(_ work: () -> T) -> (T, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = work()
        return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    #if DEBUG
    static let slack = 12.0
    static let build = "debug"
    #else
    static let slack = 1.0
    static let build = "release"
    #endif

    func testTwentyThousandTracks() throws {
        try measure(RadioSyntheticLibrary(artistCount: 600, targetTracks: 20_000, seed: 11))
    }

    /// The same size with many more artists and genres, as a real library
    /// has: 2 500 artists, 300 genres.
    func testTwentyThousandTracksManyArtists() throws {
        try measure(RadioSyntheticLibrary(artistCount: 2500, albumsPerArtist: 1...2, tracksPerAlbum: 5...9,
                                          targetTracks: 20_000, styleTags: 264, seed: 12))
    }

    func measure(_ library: RadioSyntheticLibrary) throws {
        // A year of listening on this device: 20 000 events, the history's limit.
        var events: [PlayEvent] = []
        var rng = SplitMix64(seed: 5)
        for k in 0..<ListeningHistory.limit {
            let t = library.tracks[Int(rng.next() % UInt64(library.tracks.count))]
            let outcome: PlayOutcome = rng.nextUnit() < 0.75 ? .completed : .skipped
            events.append(PlayEvent(track: t, date: library.now.addingTimeInterval(-Double(ListeningHistory.limit - k) * 1500),
                                    listened: outcome == .skipped ? 10 : t.duration, outcome: outcome))
        }
        let history = ListeningHistory(events: events)
        XCTAssertEqual(library.tracks.count, 20_000)

        let (snapshot, snapshotMS) = Self.time { LibrarySnapshot(tracks: library.tracks) }
        let (taste, tasteMS) = Self.time { TasteProfile(snapshot: snapshot, history: history, now: library.now) }
        let (graph, graphMS) = Self.time { SimilarityGraph.fromLibrary(snapshot) }
        let (data, encodeMS) = Self.time { try? JSONEncoder().encode(graph) }
        let (_, decodeMS) = Self.time { try? JSONDecoder().decode(SimilarityGraph.self, from: data ?? Data()) }

        var sessionMS: [Double] = []
        var nextMS: [Double] = []
        var feedbackMS: [Double] = []
        let seeds: [StationSeed] = [
            .artist(key: library.artists[0].key, name: library.artists[0].name, id: library.artists[0].id),
            .track(library.tracks[1234].id),
            .genre(key: NameKey.genre("Rock"), name: "Rock"),
            .decade(1990),
            .personal,
            .discovery,
        ]
        for (k, seed) in seeds.enumerated() {
            let station = Station(seed: seed, snapshot: snapshot)
            let (built, buildMS) = Self.time { () -> (RadioSession, [RadioPick]) in
                var session = RadioSession(station: station, snapshot: snapshot, taste: taste, graph: graph,
                                           randomSeed: UInt64(k))
                let first = session.next(5)
                return (session, first)
            }
            var session = built.0
            XCTAssertEqual(built.1.count, 5)
            sessionMS.append(buildMS)
            for round in 0..<10 {
                let (picks, ms) = Self.time { session.next(5) }
                XCTAssertEqual(picks.count, 5)
                nextMS.append(ms)
                // What the app does after a skip: tell, put back what is
                // queued, choose again.
                let (_, fms) = Self.time { () -> Int in
                    session.record(round % 3 == 0 ? .disliked(picks[0].track.id) : .skipped(picks[0].track.id, after: 9))
                    session.returnUnplayed(Array(picks.dropFirst().map(\.track.id)))
                    return session.next(5).count
                }
                feedbackMS.append(fms)
            }
        }
        func stats(_ values: [Double]) -> String {
            let sorted = values.sorted()
            return String(format: "median %.1f ms, max %.1f ms", sorted[sorted.count / 2], sorted.last ?? 0)
        }
        RadioEvaluationTests.line("speed (\(Self.build)), \(snapshot.tracks.count) tracks, \(snapshot.artistTrackCounts.count) artists, \(snapshot.genreTrackCounts.count) genres, 20 000 history events:")
        RadioEvaluationTests.line(String(format: "  LibrarySnapshot(tracks:) %.0f ms; TasteProfile %.0f ms; SimilarityGraph.fromLibrary %.0f ms (%d artists with edges); graph JSON %d kB, encode %.0f ms, decode %.0f ms",
                                         snapshotMS, tasteMS, graphMS, graph.artistKeys.count, (data?.count ?? 0) / 1024, encodeMS, decodeMS))
        RadioEvaluationTests.line("  session built + first next(5): \(stats(sessionMS))")
        RadioEvaluationTests.line("  next(5): \(stats(nextMS))")
        RadioEvaluationTests.line("  feedback + returnUnplayed + next(5): \(stats(feedbackMS))")

        XCTAssertLessThan(snapshotMS, 500 * Self.slack)
        XCTAssertLessThan(sessionMS.max() ?? 0, 300 * Self.slack)
        XCTAssertLessThan(nextMS.sorted()[nextMS.count / 2], 50 * Self.slack)
        XCTAssertLessThan(feedbackMS.sorted()[feedbackMS.count / 2], 100 * Self.slack)
    }
}
