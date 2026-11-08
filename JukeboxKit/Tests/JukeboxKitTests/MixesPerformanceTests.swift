// The mixes' speed on a 20 000-track library with a year of history (the
// history's limit), the radio's two made-up shapes: 600 artists and 32
// genres, and 2 500 artists and 300 genres. The bar, release build:
// MixGenerator made, its mixes and its stations, under 300 ms together.
// Debug builds are several times slower; there the bound only catches
// something gone badly wrong. The real numbers:
//   KIT_DIR=… dev/kit-test.sh -c release -Xswiftc -enable-testing --filter MixesPerformance

import Foundation
@testable import JukeboxKit
import XCTest

final class MixesPerformanceTests: XCTestCase {
    #if DEBUG
    static let slack = 12.0
    static let build = "debug"
    #else
    static let slack = 1.0
    static let build = "release"
    #endif

    static func time<T>(_ work: () -> T) -> (T, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = work()
        return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    func testTwentyThousandTracks() {
        measure(RadioSyntheticLibrary(artistCount: 600, targetTracks: 20_000, seed: 11), name: "600 artists")
    }

    func testTwentyThousandTracksManyArtists() {
        measure(RadioSyntheticLibrary(artistCount: 2500, albumsPerArtist: 1...2, tracksPerAlbum: 5...9,
                                      targetTracks: 20_000, styleTags: 264, seed: 12), name: "2 500 artists")
    }

    func measure(_ base: RadioSyntheticLibrary, name: String) {
        var events: [PlayEvent] = []
        var rng = SplitMix64(seed: 5)
        for k in 0..<ListeningHistory.limit {
            let t = base.tracks[Int(rng.next() % UInt64(base.tracks.count))]
            let outcome: PlayOutcome = rng.nextUnit() < 0.75 ? .completed : .skipped
            events.append(PlayEvent(track: t, date: base.now.addingTimeInterval(-Double(ListeningHistory.limit - k) * 1500),
                                    listened: outcome == .skipped ? 10 : t.duration, outcome: outcome))
        }
        let library = MixesLibrary(base, newAlbumCount: 12, history: ListeningHistory(events: events))
        XCTAssertEqual(library.tracks.count, 20_000)
        let snapshot = library.snapshot
        let now = library.now

        var generatorMS: [Double] = []
        var mixesMS: [Double] = []
        var stationsMS: [Double] = []
        var totalMS: [Double] = []
        var pipelineMS: [Double] = []
        var mixCount = 0
        var stationCount = 0
        for _ in 0..<5 {
            // What MixStore does: the taste and the graph, then the generator.
            let (setup, setupMS) = Self.time { () -> (TasteProfile, SimilarityGraph) in
                (TasteProfile(snapshot: snapshot, history: library.history, now: now), SimilarityGraph.fromLibrary(snapshot))
            }
            let (generator, makeMS) = Self.time {
                MixGenerator(snapshot: snapshot, taste: setup.0, history: library.history, graph: setup.1, now: now,
                             calendar: MixesCheck.calendar)
            }
            let (mixes, oneMixesMS) = Self.time { generator.mixes() }
            let (stations, oneStationsMS) = Self.time { generator.suggestedStations() }
            generatorMS.append(makeMS)
            mixesMS.append(oneMixesMS)
            stationsMS.append(oneStationsMS)
            totalMS.append(makeMS + oneMixesMS + oneStationsMS)
            pipelineMS.append(setupMS + makeMS + oneMixesMS + oneStationsMS)
            mixCount = mixes.count
            stationCount = stations.count
        }

        // A listener with nothing heard, on the same library.
        let fresh = snapshot.tracks.map { track -> Track in
            var t = track
            t.playCount = 0
            t.lastPlayed = nil
            t.isFavorite = false
            return t
        }
        let freshSnapshot = LibrarySnapshot(tracks: fresh, sharingIndexOf: snapshot)
        let empty = ListeningHistory()
        let freshTaste = TasteProfile(snapshot: freshSnapshot, history: empty, now: now)
        let graph = SimilarityGraph.fromLibrary(snapshot)
        let (freshMixes, freshMS) = Self.time { () -> [Mix] in
            let generator = MixGenerator(snapshot: freshSnapshot, taste: freshTaste, history: empty, graph: graph, now: now,
                                         calendar: MixesCheck.calendar)
            _ = generator.suggestedStations()
            return generator.mixes()
        }

        let line = "speed, \(name), \(Self.build): MixGenerator made \(MixesCheck.fmt(Self.median(generatorMS), 1)) ms, "
            + "mixes() \(MixesCheck.fmt(Self.median(mixesMS), 1)) ms (\(mixCount) mixes), "
            + "suggestedStations() \(MixesCheck.fmt(Self.median(stationsMS), 1)) ms (\(stationCount)), "
            + "together \(MixesCheck.fmt(Self.median(totalMS), 1)) ms median, \(MixesCheck.fmt(totalMS.max() ?? 0, 1)) max; "
            + "with MixStore's taste and graph \(MixesCheck.fmt(Self.median(pipelineMS), 1)) ms; "
            + "a new listener \(MixesCheck.fmt(freshMS, 1)) ms (\(freshMixes.count) mixes)"
        MixesCheck.line(line)
        XCTAssertLessThan(Self.median(totalMS), 300 * Self.slack, line)
        XCTAssertLessThan(freshMS, 300 * Self.slack, line)
        XCTAssertGreaterThanOrEqual(mixCount, 10)
    }

    /// SimilarityService on the same size: 150 artists asked about (what
    /// RadioController asks for), each answered with 100 similar artists of
    /// which 60 are in the library; then a second launch making the graph
    /// from what is on disk.
    func testSimilarityServiceOnTwentyThousandTracks() async throws {
        let base = RadioSyntheticLibrary(artistCount: 2500, albumsPerArtist: 1...2, tracksPerAlbum: 5...9,
                                         targetTracks: 20_000, styleTags: 264, seed: 12)
        let snapshot = LibrarySnapshot(tracks: base.tracks)
        let names = base.artists.map(\.name)
        let mock = LastFMMockTransport { request in
            var rng = SplitMix64(seed: SplitMix64.stableSeed(request.artist))
            var similar: [(name: String, match: Double)] = []
            for k in 0..<100 {
                let name = k % 5 < 3 ? names[Int(rng.next() % UInt64(names.count))] : "Somebody \(rng.next() % 100_000)"
                similar.append((name, 1 - Double(k) / 100))
            }
            return LastFMFixtures.respond(200, LastFMFixtures.similarArtists(request.artist, similar))
        }
        let directory = LastFMFixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SimilarityService(directory: directory, lastFM: LastFMClient(apiKey: "key", transport: mock))
        await service.setPacing(minimumInterval: .zero, backoff: .milliseconds(1))
        let priority = TasteProfile(snapshot: snapshot, history: base.history, now: base.now).topArtists(150)

        let clock = ContinuousClock()
        var start = clock.now
        let enriched = await service.enrich(snapshot: snapshot, priority: priority)
        let enrichTime = clock.now - start
        XCTAssertEqual(mock.count, 150)
        XCTAssertEqual(enriched.enrichedArtistCount, 150)

        let relaunched = SimilarityService(directory: directory, lastFM: nil)
        start = clock.now
        let fromDisk = await relaunched.graph(for: snapshot)
        let launchTime = clock.now - start
        start = clock.now
        _ = await relaunched.graph(for: snapshot)
        let againTime = clock.now - start
        XCTAssertEqual(fromDisk.enrichedArtistCount, 150)
        let size = ((try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("lastfm-artists.json").path))?[.size] as? Int) ?? 0
        func ms(_ d: Duration) -> String { MixesCheck.fmt(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15, 1) }
        let line = "speed, SimilarityService, 2 500 artists, \(Self.build): enrich of 150 artists with no pause between "
            + "requests \(ms(enrichTime)) ms (Last.fm's own time not counted; at four a second it is 37.5 s), "
            + "lastfm-artists.json \(size / 1024) kB, graph(for:) on the next launch \(ms(launchTime)) ms, again \(ms(againTime)) ms"
        MixesCheck.line(line)
        XCTAssertLessThan(launchTime, .milliseconds(Int(1000 * Self.slack)), line)
    }
}
