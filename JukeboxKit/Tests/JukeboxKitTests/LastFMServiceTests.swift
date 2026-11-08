// SimilarityService with a mock Last.fm and a directory of its own: the
// library's graph without a key; Last.fm's similar artists mapped onto the
// library's artists and merged; the answers kept on disk for 30 days and
// asked again after; the pace; the errors (a bad key, "rate limit", no
// network, "not found", Last.fm's own); cancelling; similar and top tracks as
// library tracks; and what Last.fm's edges do to a station.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class LastFMServiceTests: XCTestCase {
    /// The test server's library (358 tracks, 23 artists, joined tags).
    static let snapshot = LibrarySnapshot(tracks: RadioRealLibraryFixture.tracks)

    /// What the mock Last.fm knows: who sounds like whom among the test
    /// server's artists, as Last.fm spells them, with some it does not have.
    static let knowledge: LastFMKnowledge = {
        var k = LastFMKnowledge()
        k.similarArtists["Velvet Static"] = [
            ("My Bloody Valentine", 1), // not in the library
            ("Lanterns", 0.9), // "The Lanterns" in the library
            ("Paper Harbour", 0.7),
            ("Glass Animals Club feat. Somebody", 0.4), // joined: the first named
            ("Velvet Static", 0.5), // itself
        ]
        k.similarArtists["Iron Meadow"] = [("Black Sabbath", 1), ("Velvet Static", 0.6)]
        k.similarArtists["Willow & Pine"] = [("Old Mill Road", 0.8), ("June Hollow", 0.75)]
        k.similarArtists["The Lanterns"] = [("Velvet Static", 0.85), ("Glass Animals Club", 0.8), ("Paper Harbour", 0.8)]
        k.similarArtists["Paper Harbour"] = [("Glass Animals Club", 0.9), ("The Lanterns", 0.8), ("June Hollow", 0.5)]
        k.similarArtists["Glass Animals Club"] = [("Paper Harbour", 0.9), ("The Lanterns", 0.7)]
        k.similarTracks["Velvet Static|Glass Road"] = [
            ("The Lanterns", "Ocean Story", 0.9),
            ("Iron Meadow", "Fire Tide (Remastered 2011)", 0.8),
            ("Velvet Static", "Glass Road", 0.7), // itself
            ("Somebody Else", "Unknown Song", 0.6),
        ]
        k.similarTracks["MC Polder|Signal Dream"] = [("Concrete Poets", "Hollow Dance", 0.7)]
        k.topTracks["Iron Meadow"] = ["Fire Tide", "Not In The Library", "Electric Mirror", "Winter Dance"]
        return k
    }()

    static func key(_ name: String) -> String { NameKey.artist(name) }

    var directories: [URL] = []

    override func tearDown() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
        super.tearDown()
    }

    /// A service with the mock, quick pacing, and a directory of its own (or
    /// the one given, to see what a second launch finds).
    func service(_ transport: LastFMMockTransport?, directory: URL? = nil, now: Date? = nil) async -> (SimilarityService, URL) {
        let directory = directory ?? LastFMFixtures.directory()
        directories.append(directory)
        let service = SimilarityService(directory: directory,
                                        lastFM: transport.map { LastFMClient(apiKey: "key", transport: $0) })
        await service.setPacing(minimumInterval: .milliseconds(2), backoff: .milliseconds(20))
        if let now { await service.setDate { now } }
        return (service, directory)
    }

    static func encoded(_ graph: SimilarityGraph) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(graph)) ?? Data()
    }

    func testWithoutAKeyTheGraphIsTheLibrarys() async {
        let snapshot = Self.snapshot
        let (service, directory) = await service(nil)
        let library = SimilarityGraph.fromLibrary(snapshot)
        let graph = await service.graph(for: snapshot)
        XCTAssertEqual(Self.encoded(graph), Self.encoded(library))
        let enriched = await service.enrich(snapshot: snapshot, priority: [Self.key("Velvet Static")])
        XCTAssertEqual(Self.encoded(enriched), Self.encoded(library))
        XCTAssertEqual(enriched.enrichedArtistCount, 0)
        let similar = await service.similarTracks(to: snapshot.tracks[0], in: snapshot)
        XCTAssertEqual(similar, [])
        let top = await service.topTracks(artist: ArtistRef(id: nil, name: "Iron Meadow"), in: snapshot)
        XCTAssertEqual(top, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("lastfm-artists.json").path))
    }

    func testEnrichMapsLastFMsArtistsToTheLibrarysAndMerges() async throws {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, directory) = await service(mock)
        let priority = ["Velvet Static", "Iron Meadow", "Willow & Pine"].map(Self.key) + ["nosuchartist"]
        let graph = await service.enrich(snapshot: snapshot, priority: priority)

        // One request an artist the library has, with its name as the library
        // spells it, and autocorrect on.
        XCTAssertEqual(mock.requests.map(\.asked.artist), ["Velvet Static", "Iron Meadow", "Willow & Pine"])
        XCTAssertTrue(mock.requests.allSatisfy { $0.asked.method == "artist.getsimilar" && $0.asked.query["autocorrect"] == "1" })

        let velvet = Self.key("Velvet Static"), lanterns = Self.key("The Lanterns")
        // "Lanterns" is The Lanterns; the edge both ways, Last.fm's 0.9 over
        // the library's 0.24.
        XCTAssertLessThan(SimilarityGraph.fromLibrary(snapshot).weight(velvet, lanterns), 0.5)
        XCTAssertEqual(graph.weight(velvet, lanterns), 0.9, accuracy: 1e-9)
        XCTAssertEqual(graph.weight(lanterns, velvet), 0.9, accuracy: 1e-9)
        XCTAssertEqual(graph.weight(velvet, Self.key("Paper Harbour")), 0.7, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(graph.weight(velvet, Self.key("Glass Animals Club")), 0.4)
        XCTAssertEqual(graph.weight(Self.key("Willow & Pine"), Self.key("Old Mill Road")), 0.8, accuracy: 1e-9)
        XCTAssertFalse(graph.artistKeys.contains(Self.key("My Bloody Valentine")))
        XCTAssertEqual(graph.enrichedArtistCount, 3)
        XCTAssertTrue(graph.isEnriched(velvet))
        // The library's own edges are all still there.
        let library = SimilarityGraph.fromLibrary(snapshot)
        for a in library.artistKeys {
            for neighbor in library.similarArtists(to: a) {
                XCTAssertGreaterThanOrEqual(graph.weight(a, neighbor.key), neighbor.weight)
            }
        }
        for file in ["lastfm-artists.json", "lastfm-graph.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path), file)
        }
        // graph(for:) gives the same, without asking.
        let again = await service.graph(for: snapshot)
        XCTAssertEqual(Self.encoded(again), Self.encoded(graph))
        XCTAssertEqual(mock.count, 3)
    }

    func testAnswersAreKeptOnDiskForThirtyDays() async throws {
        let snapshot = Self.snapshot
        let start = Date(timeIntervalSinceReferenceDate: 815_800_000)
        let priority = ["Velvet Static", "Iron Meadow", "Willow & Pine"].map(Self.key)
        let first = LastFMMockTransport(Self.knowledge)
        let (service, directory) = await service(first, now: start)
        let graph = await service.enrich(snapshot: snapshot, priority: priority)
        XCTAssertEqual(first.count, 3)

        // The next launch: the same graph from disk, nothing asked.
        let second = LastFMMockTransport(Self.knowledge)
        let (relaunched, _) = await self.service(second, directory: directory, now: start.addingTimeInterval(10 * 86_400))
        let fromDisk = await relaunched.graph(for: snapshot)
        XCTAssertEqual(Self.encoded(fromDisk), Self.encoded(graph))
        _ = await relaunched.enrich(snapshot: snapshot, priority: priority)
        XCTAssertEqual(second.count, 0)
        // An artist not asked about before is asked, and only it.
        _ = await relaunched.enrich(snapshot: snapshot, priority: priority + [Self.key("The Lanterns")])
        XCTAssertEqual(second.requests.map(\.asked.artist), ["The Lanterns"])

        // A month and a day later the first three are stale and asked again.
        let third = LastFMMockTransport(Self.knowledge)
        let (later, _) = await self.service(third, directory: directory, now: start.addingTimeInterval(31 * 86_400))
        _ = await later.enrich(snapshot: snapshot, priority: priority)
        XCTAssertEqual(third.requests.map(\.asked.artist), ["Velvet Static", "Iron Meadow", "Willow & Pine"])
    }

    func testAtMostMaxArtistsAndInTheirOrder() async {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock)
        let names = ["Willow & Pine", "Iron Meadow", "Velvet Static", "The Lanterns", "Paper Harbour", "Glass Animals Club"]
        _ = await service.enrich(snapshot: snapshot, priority: names.map(Self.key) + names.map(Self.key), maxArtists: 4)
        XCTAssertEqual(mock.requests.map(\.asked.artist), Array(names.prefix(4)))
        // The next round goes on where this one stopped.
        _ = await service.enrich(snapshot: snapshot, priority: names.map(Self.key), maxArtists: 4)
        XCTAssertEqual(mock.requests.map(\.asked.artist), names)
        _ = await service.enrich(snapshot: snapshot, priority: names.map(Self.key), maxArtists: 0)
        XCTAssertEqual(mock.count, 6)
    }

    func testVariousArtistsIsNotAsked() async {
        let tracks = [Track(id: "1", name: "One", albumID: "c", artists: [ArtistRef(id: "p", name: "Portishead")],
                            albumArtist: ArtistRef(id: "va", name: "Various Artists"))]
        let snapshot = LibrarySnapshot(tracks: tracks)
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock)
        _ = await service.enrich(snapshot: snapshot, priority: ["variousartists", "portishead"])
        XCTAssertEqual(mock.requests.map(\.asked.artist), ["Portishead"])
    }

    func testABadKeyStopsEverything() async {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport { _ in LastFMFixtures.respond(403, LastFMFixtures.invalidKey) }
        let (service, _) = await service(mock)
        let graph = await service.enrich(snapshot: snapshot, priority: ["Velvet Static", "Iron Meadow"].map(Self.key))
        XCTAssertEqual(mock.count, 1, "stops at the first refusal")
        XCTAssertEqual(Self.encoded(graph), Self.encoded(SimilarityGraph.fromLibrary(snapshot)))
        let rejected = await service.keyRejected
        XCTAssertTrue(rejected)
        // Nothing more is asked with it.
        _ = await service.enrich(snapshot: snapshot, priority: [Self.key("The Lanterns")])
        let similar = await service.similarTracks(to: snapshot.tracks[0], in: snapshot)
        let top = await service.topTracks(artist: ArtistRef(id: nil, name: "Iron Meadow"), in: snapshot)
        XCTAssertEqual(similar, [])
        XCTAssertEqual(top, [])
        XCTAssertEqual(mock.count, 1)
    }

    func testRateLimitBacksOffAndTriesAgain() async throws {
        let snapshot = Self.snapshot
        let knowledge = Self.knowledge
        // Velvet Static's first two requests are "rate limit exceeded".
        let refused = LastFMCounter()
        let mock = LastFMMockTransport { request in
            if request.artist == "Velvet Static", refused.next() <= 2 { return LastFMFixtures.respond(200, LastFMFixtures.rateLimited) }
            return knowledge.answer(request)
        }
        let (service, _) = await service(mock)
        let graph = await service.enrich(snapshot: snapshot, priority: ["Velvet Static", "Iron Meadow"].map(Self.key))
        let sent = mock.requests
        XCTAssertEqual(sent.map(\.asked.artist), ["Velvet Static", "Velvet Static", "Velvet Static", "Iron Meadow"])
        XCTAssertEqual(graph.weight(Self.key("Velvet Static"), Self.key("The Lanterns")), 0.9, accuracy: 1e-9)
        // 20 ms after the first refusal, 40 after the second.
        XCTAssertGreaterThanOrEqual(sent[1].at - sent[0].at, .milliseconds(19))
        XCTAssertGreaterThanOrEqual(sent[2].at - sent[1].at, .milliseconds(39))

        // Always refused: three tries, then the round stops (Iron Meadow is
        // not asked), and nothing is kept, so the next round asks again.
        let always = LastFMMockTransport { _ in LastFMFixtures.respond(429, LastFMFixtures.rateLimited) }
        let (busy, _) = await self.service(always)
        _ = await busy.enrich(snapshot: snapshot, priority: ["Velvet Static", "Iron Meadow"].map(Self.key))
        XCTAssertEqual(always.requests.map(\.asked.artist), ["Velvet Static", "Velvet Static", "Velvet Static"])
        _ = await busy.enrich(snapshot: snapshot, priority: [Self.key("Velvet Static")])
        XCTAssertEqual(always.count, 6)
    }

    func testNoNetworkStopsQuietlyAndKeepsWhatCame() async {
        let snapshot = Self.snapshot
        let knowledge = Self.knowledge
        let mock = LastFMMockTransport { request in
            if request.artist == "Iron Meadow" { throw URLError(.networkConnectionLost) }
            return knowledge.answer(request)
        }
        let (service, directory) = await service(mock)
        let graph = await service.enrich(snapshot: snapshot, priority: ["Velvet Static", "Iron Meadow", "Willow & Pine"].map(Self.key))
        XCTAssertEqual(mock.requests.map(\.asked.artist), ["Velvet Static", "Iron Meadow"])
        XCTAssertEqual(graph.enrichedArtistCount, 1)
        // What came before is on disk.
        let (relaunched, _) = await self.service(nil, directory: directory)
        let fromDisk = await relaunched.graph(for: snapshot)
        XCTAssertEqual(fromDisk.weight(Self.key("Velvet Static"), Self.key("The Lanterns")), 0.9, accuracy: 1e-9)
    }

    func testNotFoundIsKeptAsAnAnswerOfNothing() async {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock)
        // Last.fm does not know Amsterdam Strings.
        _ = await service.enrich(snapshot: snapshot, priority: [Self.key("Amsterdam Strings")])
        _ = await service.enrich(snapshot: snapshot, priority: [Self.key("Amsterdam Strings")])
        XCTAssertEqual(mock.count, 1)
    }

    func testLastFMsOwnErrorSkipsOneArtistAndThreeInARowStop() async {
        let snapshot = Self.snapshot
        let knowledge = Self.knowledge
        let mock = LastFMMockTransport { request in
            if request.artist == "Iron Meadow" { return LastFMFixtures.respond(200, LastFMFixtures.operationFailed) }
            return knowledge.answer(request)
        }
        let (service, _) = await service(mock)
        let graph = await service.enrich(snapshot: snapshot, priority: ["Iron Meadow", "Velvet Static", "Willow & Pine"].map(Self.key))
        XCTAssertEqual(mock.count, 3)
        XCTAssertEqual(graph.enrichedArtistCount, 2)
        // Not kept: asked again next time.
        _ = await service.enrich(snapshot: snapshot, priority: [Self.key("Iron Meadow")])
        XCTAssertEqual(mock.count, 4)

        let failing = LastFMMockTransport { _ in LastFMFixtures.respond(200, LastFMFixtures.operationFailed) }
        let (unwell, _) = await self.service(failing)
        _ = await unwell.enrich(snapshot: snapshot, priority: ["Iron Meadow", "Velvet Static", "Willow & Pine", "The Lanterns"].map(Self.key))
        XCTAssertEqual(failing.count, 3)
    }

    func testRequestsAreAtLeastTheIntervalApart() async throws {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock)
        await service.setPacing(minimumInterval: .milliseconds(40), backoff: .milliseconds(20))
        let names = ["Willow & Pine", "Iron Meadow", "Velvet Static", "The Lanterns", "Paper Harbour"]
        let clock = ContinuousClock()
        let start = clock.now
        _ = await service.enrich(snapshot: snapshot, priority: names.map(Self.key))
        let elapsed = clock.now - start
        let sent = mock.requests
        XCTAssertEqual(sent.count, 5)
        for (later, earlier) in zip(sent.dropFirst(), sent) {
            XCTAssertGreaterThanOrEqual(later.at - earlier.at, .milliseconds(39))
        }
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(150))
        // The default: four a second, under Last.fm's five.
        let pace = await SimilarityService(directory: LastFMFixtures.directory(), lastFM: nil).minimumInterval
        XCTAssertEqual(pace, .milliseconds(250))
    }

    func testCancellingStopsAndKeepsWhatCame() async throws {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, directory) = await service(mock)
        await service.setPacing(minimumInterval: .milliseconds(60), backoff: .milliseconds(20))
        let names = ["Willow & Pine", "Iron Meadow", "Velvet Static", "The Lanterns", "Paper Harbour", "Glass Animals Club"]
        let keys = names.map { NameKey.artist($0) }
        let task = Task { await service.enrich(snapshot: snapshot, priority: keys) }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        _ = await task.value
        let asked = mock.count
        XCTAssertGreaterThanOrEqual(asked, 2)
        XCTAssertLessThan(asked, names.count)
        let (relaunched, _) = await self.service(nil, directory: directory)
        let fromDisk = await relaunched.graph(for: snapshot)
        XCTAssertTrue(fromDisk.isEnriched(Self.key("Willow & Pine")))
    }

    func testSimilarTracksAreLibraryTracks() async throws {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, directory) = await service(mock)
        let glassRoad = try XCTUnwrap(snapshot.tracks.first { $0.name == "Glass Road" && $0.albumArtist?.name == "Velvet Static" })
        let similar = await service.similarTracks(to: glassRoad, in: snapshot)
        let oceanStory = try XCTUnwrap(snapshot.match(artist: "The Lanterns", title: "Ocean Story"))
        // "Fire Tide (Remastered 2011)" is Iron Meadow's Fire Tide, not MC Polder's.
        let fireTide = try XCTUnwrap(snapshot.tracks.first { $0.name == "Fire Tide" && $0.albumArtist?.name == "Iron Meadow" })
        XCTAssertEqual(similar, [Neighbor(key: oceanStory.id, weight: 0.9), Neighbor(key: fireTide.id, weight: 0.8)])
        let asked = try XCTUnwrap(mock.requests.first?.asked)
        XCTAssertEqual(asked.method, "track.getsimilar")
        XCTAssertEqual(asked.artist, "Velvet Static")
        XCTAssertEqual(asked.track, "Glass Road")

        // Kept: the second time nothing is asked, and the graph has them as
        // the song's similar tracks (a song station started again has them
        // from its first pick).
        let again = await service.similarTracks(to: glassRoad, in: snapshot)
        XCTAssertEqual(again, similar)
        XCTAssertEqual(mock.count, 1)
        let graph = await service.graph(for: snapshot)
        XCTAssertEqual(graph.similarTracks(to: glassRoad.id), similar)
        let (relaunched, _) = await self.service(nil, directory: directory)
        let fromDisk = await relaunched.graph(for: snapshot)
        XCTAssertEqual(fromDisk.similarTracks(to: glassRoad.id), similar)

        // A song by "MC Polder; Lyric Engine" is asked as MC Polder's.
        let duet = try XCTUnwrap(snapshot.tracks.first { $0.name == "Signal Dream" })
        let duetSimilar = await service.similarTracks(to: duet, in: snapshot)
        XCTAssertEqual(mock.requests.last?.asked.artist, "MC Polder")
        XCTAssertEqual(duetSimilar.count, 1)

        // Not known to Last.fm: nothing, and kept as nothing.
        let other = try XCTUnwrap(snapshot.tracks.first { $0.albumArtist?.name == "Clara Venn" })
        let none = await service.similarTracks(to: other, in: snapshot)
        let stillNone = await service.similarTracks(to: other, in: snapshot)
        XCTAssertEqual(none, [])
        XCTAssertEqual(stillNone, [])
        XCTAssertEqual(mock.count, 3)
    }

    func testTopTracksAreLibraryTracksByRank() async throws {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock)
        let ironMeadow = try XCTUnwrap(snapshot.artist(key: Self.key("Iron Meadow")))
        let top = await service.topTracks(artist: ironMeadow, in: snapshot, limit: 2)
        XCTAssertEqual(top.map(\.name), ["Fire Tide", "Electric Mirror"])
        XCTAssertTrue(top.allSatisfy { $0.albumArtist?.name == "Iron Meadow" })
        XCTAssertEqual(mock.requests.first?.asked.method, "artist.gettoptracks")
        XCTAssertEqual(mock.requests.first?.asked.query["limit"], "50", "more than asked for: not all are in the library")
        let three = await service.topTracks(artist: ironMeadow, in: snapshot, limit: 10)
        XCTAssertEqual(three.map(\.name), ["Fire Tide", "Electric Mirror", "Winter Dance"])
        XCTAssertEqual(mock.count, 1, "kept")
        let zero = await service.topTracks(artist: ironMeadow, in: snapshot, limit: 0)
        XCTAssertEqual(zero, [])
    }

    func testABrokenCacheIsAskedAgain() async throws {
        let snapshot = Self.snapshot
        let directory = LastFMFixtures.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in ["lastfm-artists.json", "lastfm-tracks.json", "lastfm-top-tracks.json", "lastfm-graph.json"] {
            try Data("{ not json".utf8).write(to: directory.appendingPathComponent(file))
        }
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock, directory: directory)
        let graph = await service.graph(for: snapshot)
        XCTAssertEqual(Self.encoded(graph), Self.encoded(SimilarityGraph.fromLibrary(snapshot)))
        let enriched = await service.enrich(snapshot: snapshot, priority: [Self.key("Velvet Static")])
        XCTAssertEqual(mock.count, 1)
        XCTAssertEqual(enriched.enrichedArtistCount, 1)
    }

    func testWhenOnlyTheGraphIsLeft() async throws {
        let snapshot = Self.snapshot
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, directory) = await service(mock)
        let graph = await service.enrich(snapshot: snapshot, priority: ["Velvet Static", "Willow & Pine"].map(Self.key))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("lastfm-artists.json"))
        let (relaunched, _) = await self.service(nil, directory: directory)
        let fromGraph = await relaunched.graph(for: snapshot)
        XCTAssertEqual(Self.encoded(fromGraph), Self.encoded(graph))
        XCTAssertEqual(fromGraph.enrichedArtistCount, 2)
    }

    /// What Last.fm's edges do to a station: Velvet Static Radio on the test
    /// server, whose guests cross genres (docs/RADIO.md: with the library's
    /// graph alone, house and synthwave by way of guest spots).
    func testLastFMsEdgesOnAStation() async throws {
        let snapshot = Self.snapshot
        let taste = TasteProfile(snapshot: snapshot, history: ListeningHistory(), now: Date(timeIntervalSinceReferenceDate: 815_800_000))
        let mock = LastFMMockTransport(Self.knowledge)
        let (service, _) = await service(mock)
        let library = await service.graph(for: snapshot)
        let names = ["Velvet Static", "The Lanterns", "Paper Harbour", "Glass Animals Club", "Iron Meadow"]
        let enriched = await service.enrich(snapshot: snapshot, priority: names.map(Self.key))
        let velvet = try XCTUnwrap(snapshot.artist(key: Self.key("Velvet Static")))
        let electronic: Set<String> = ["electronic", "house", "synthwave", "techno", "ambient"]

        func share(_ graph: SimilarityGraph) -> (electronic: Double, indie: Double) {
            var electronicCount = 0, indieCount = 0, total = 0
            for seed in UInt64(1)...6 {
                var session = RadioSession(station: Station(seed: .artist(key: velvet.key, name: velvet.name, id: velvet.id), snapshot: snapshot),
                                           snapshot: snapshot, taste: taste, graph: graph, randomSeed: seed)
                for pick in session.next(20) {
                    let genres = Set(snapshot.genreKeys(of: pick.track))
                    if !genres.isDisjoint(with: electronic) { electronicCount += 1 }
                    if !genres.isDisjoint(with: ["indie", "alternative"]) { indieCount += 1 }
                    total += 1
                }
            }
            return (Double(electronicCount) / Double(total), Double(indieCount) / Double(total))
        }
        let without = share(library)
        let with = share(enriched)
        MixesCheck.line("Velvet Static Radio on the test server, 6 × 20 picks: electronic \(MixesCheck.fmt(without.electronic)) → "
                        + "\(MixesCheck.fmt(with.electronic)) with Last.fm's edges, indie or alternative "
                        + "\(MixesCheck.fmt(without.indie)) → \(MixesCheck.fmt(with.indie))")
        XCTAssertLessThan(with.electronic, without.electronic)
        XCTAssertGreaterThan(with.indie, without.indie)
    }
}

/// Counts calls from any task, for a mock that answers differently the
/// first few times.
final class LastFMCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
