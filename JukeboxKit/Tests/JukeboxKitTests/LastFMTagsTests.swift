// Last.fm's tags as genres (docs/RADIO.md, "Last.fm's tags"): the answer
// read leniently, the tags that name no genre left out, the snapshot with
// them (the files' own genres first, the tags on an artist's own records at
// their weight), the service asking each artist once and keeping it, and
// what the tags do for a library whose files say little. Never the
// network: the mock answers in Last.fm's documented shape. Prints
// RADIO-EVAL lines.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class LastFMTagsTests: XCTestCase {
    static func line(_ text: String) { print("RADIO-EVAL " + text) }

    var directories: [URL] = []

    override func tearDown() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
        super.tearDown()
    }

    func client(_ body: String) -> LastFMClient {
        LastFMClient(apiKey: "key", transport: LastFMMockTransport { _ in LastFMFixtures.respond(200, body) })
    }

    func service(_ mock: LastFMMockTransport?, directory: URL? = nil) async -> (SimilarityService, URL) {
        let directory = directory ?? LastFMFixtures.directory()
        directories.append(directory)
        let service = SimilarityService(directory: directory, lastFM: mock.map { LastFMClient(apiKey: "key", transport: $0) })
        await service.setPacing(minimumInterval: .milliseconds(1), backoff: .milliseconds(5))
        return (service, directory)
    }

    // MARK: The answer

    func testTopTagsLeniently() async throws {
        // A count as a string, one without a count, one without a name.
        let body = #"{"toptags":{"tag":[{"count":"100","name":"shoegaze"},{"count":61,"name":"Dream Pop"},{"name":"noise pop"},{"count":5}],"@attr":{"artist":"x"}}}"#
        let tags = try await client(body).topTags(artist: "x")
        XCTAssertEqual(tags, [.init(name: "shoegaze", count: 100), .init(name: "Dream Pop", count: 61), .init(name: "noise pop", count: 0)])
        // A list of one as the one object; an empty list as "".
        let one = try await client(#"{"toptags":{"tag":{"count":100,"name":"jazz"},"@attr":{"artist":"x"}}}"#).topTags(artist: "x")
        XCTAssertEqual(one, [.init(name: "jazz", count: 100)])
        let none = try await client(#"{"toptags":{"tag":"","@attr":{"artist":"x"}}}"#).topTags(artist: "x")
        XCTAssertEqual(none, [])
    }

    func testTheTagsThatNameAGenre() {
        let tags: [LastFMClient.Tag] = [
            .init(name: "shoegaze", count: 100), .init(name: "seen live", count: 90), .init(name: "90s", count: 80),
            .init(name: "Velvet Static", count: 70), .init(name: "dream pop", count: 60), .init(name: "british", count: 50),
            .init(name: "Shoegaze", count: 45), .init(name: "noise pop", count: 40), .init(name: "rock", count: 30),
            .init(name: "indie", count: 20), .init(name: "alternative", count: 15), .init(name: "post-rock", count: 9),
        ]
        let kept = SimilarityService.genreTags(tags, artist: "Velvet Static", weight: 0.5)
        XCTAssertEqual(kept.map(\.name), ["Shoegaze", "Dream Pop", "Noise Pop", "Rock", "Indie"])
        XCTAssertEqual(kept[0].weight, 0.5, accuracy: 1e-9)
        XCTAssertEqual(kept[1].weight, 0.3, accuracy: 1e-9)
        XCTAssertEqual(SimilarityService.genreTags([.init(name: "post-rock", count: 9)], artist: "X", weight: 0.5), [])
    }

    // MARK: The snapshot

    func testTheSnapshotWithTags() {
        let tracks = RadioRealLibraryFixture.tracks
        let plain = LibrarySnapshot(tracks: tracks)
        // No tags: the library as it was, to the byte.
        let none = LibrarySnapshot(tracks: tracks, artistTags: [:])
        XCTAssertEqual(tracks.map { none.genreKeys(of: $0) }, tracks.map { plain.genreKeys(of: $0) })
        XCTAssertEqual(LastFMServiceTests.encoded(.fromLibrary(none)), LastFMServiceTests.encoded(.fromLibrary(plain)))

        let velvet = NameKey.artist("Velvet Static")
        let dreamPop = NameKey.genre("Dream Pop"), shoegaze = NameKey.genre("Shoegaze")
        let tagged = LibrarySnapshot(tracks: tracks, artistTags: [
            velvet: [.init(name: "Dream Pop", weight: 0.4), .init(name: "Shoegaze", weight: 0.5), .init(name: "Nothing", weight: 0)],
        ])
        let own = tagged.ownTracks(artistKey: velvet)
        XCTAssertFalse(own.isEmpty)
        for track in own {
            // After the files' own; a tag the files have adds nothing.
            XCTAssertEqual(tagged.genreKeys(of: track), plain.genreKeys(of: track) + [dreamPop])
        }
        // Velvet Static as a guest on someone else's record: that record's genres.
        for track in tracks where tagged.artistKeys(of: track).dropFirst().contains(velvet) {
            XCTAssertEqual(tagged.genreKeys(of: track), plain.genreKeys(of: track))
        }
        XCTAssertEqual(tagged.genreName(key: dreamPop), "Dream Pop")
        // A genre's own tracks stay the files', where its station opens.
        XCTAssertEqual(tagged.tracks(genreKey: dreamPop).count, 0)
        XCTAssertEqual(tagged.tracks(genreKey: shoegaze).map(\.id), plain.tracks(genreKey: shoegaze).map(\.id))
        // A tag first, the files' spelling after: the files' spelling wins.
        let lower = LibrarySnapshot(tracks: tracks, artistTags: [
            NameKey.artist(tracks[0].albumArtist?.name ?? ""): [.init(name: "rock", weight: 0.5), .init(name: "shoegaze", weight: 0.5)],
        ])
        XCTAssertEqual(lower.genreName(key: shoegaze), "Shoegaze")
        XCTAssertEqual(lower.genreName(key: NameKey.genre("Rock")), "Rock")
    }

    // MARK: The service

    func testTagsAreAskedOnceAndKept() async throws {
        let snapshot = LastFMServiceTests.snapshot
        let velvet = NameKey.artist("Velvet Static")
        var knowledge = LastFMKnowledge()
        knowledge.topTags["Velvet Static"] = [("shoegaze", 100), ("dream pop", 70), ("seen live", 50)]
        let mock = LastFMMockTransport(knowledge)
        let (service, directory) = await self.service(mock)

        let first = await service.enrichTags(snapshot: snapshot, priority: [velvet], maxArtists: 5)
        // Each artist's page first (artist.search), then its tags.
        XCTAssertEqual(mock.count, 10)
        XCTAssertEqual(Array(mock.requests.map(\.asked.method).prefix(2)), ["artist.search", "artist.gettoptags"])
        XCTAssertEqual(mock.requests.first?.asked.artist, "Velvet Static")
        let track = try XCTUnwrap(snapshot.ownTracks(artistKey: velvet).first)
        XCTAssertTrue(first.genreKeys(of: track).contains(NameKey.genre("Dream Pop")))
        XCTAssertFalse(first.genreKeys(of: track).contains(NameKey.genre("Seen Live")))

        // The next round asks the next five, never the first again.
        _ = await service.enrichTags(snapshot: snapshot, priority: [velvet], maxArtists: 5)
        XCTAssertEqual(Set(mock.requests.map(\.asked.artist)).count, 10)

        // Another launch: from disk, nothing asked.
        let quiet = LastFMMockTransport(knowledge)
        let (again, _) = await self.service(quiet, directory: directory)
        let second = await again.radioSnapshot(for: snapshot)
        XCTAssertEqual(quiet.count, 0)
        XCTAssertEqual(snapshot.tracks.map { second.genreKeys(of: $0) }, snapshot.tracks.map { first.genreKeys(of: $0) })

        // Without a key the files' genres alone, whatever is on disk.
        let (keyless, _) = await self.service(nil, directory: directory)
        let plain = await keyless.radioSnapshot(for: snapshot)
        XCTAssertEqual(snapshot.tracks.map { plain.genreKeys(of: $0) }, snapshot.tracks.map { snapshot.genreKeys(of: $0) })
    }

    // MARK: What it does, measured

    /// The made-up library as a library with poor tags has it: a third of
    /// the artists' files without any genre, the rest with only the broad
    /// one ("Rock", never "Shoegaze").
    static func poorTracks(_ library: RadioSyntheticLibrary) -> [Track] {
        var number: [String: Int] = [:]
        for (i, a) in library.artists.enumerated() { number[a.id] = i }
        return library.tracks.map { track in
            var t = track
            let i = number[track.albumArtist?.id ?? ""] ?? 0
            t.genres = i % 3 == 0 ? [] : [RadioSyntheticLibrary.clusters[library.artists[i].cluster].genre]
            return t
        }
    }

    /// What Last.fm says of each made-up artist, as its listeners would:
    /// the cluster and the sub-genres, in lower case, with "seen live",
    /// where they are from and a decade; every sixth also a wrong genre,
    /// every fourth its own name, and every tenth unknown to Last.fm.
    static func knowledge(_ library: RadioSyntheticLibrary) -> LastFMKnowledge {
        var k = LastFMKnowledge()
        let clusters = RadioSyntheticLibrary.clusters
        for (i, a) in library.artists.enumerated() where i % 10 != 9 {
            let c = clusters[a.cluster]
            var tags: [(name: String, count: Int)] = [(c.genre.lowercased(), 100), (a.subgenre.lowercased(), 85)]
            if a.genres.count > 2, a.genres[2] != a.subgenre, c.subgenres.contains(a.genres[2]) {
                tags.append((a.genres[2].lowercased(), 55))
            }
            tags.append(("seen live", 45))
            tags.append((i % 3 == 0 ? "dutch" : "british", 30))
            if i % 6 == 0 { tags.append((clusters[(a.cluster + 3) % clusters.count].genre.lowercased(), 35)) }
            tags.append(("\(a.firstYear / 10 % 10)0s", 25))
            if i % 4 == 0 { tags.append((a.name.lowercased(), 12)) }
            k.topTags[a.name] = tags
        }
        return k
    }

    struct Measured {
        /// Artist stations, 16 seeds × 3 × 50: picks of the seed's cluster.
        var inCluster = 0.0
        /// … picks by another artist of the seed's sub-genre.
        var sameSubgenre = 0.0
        /// Each cluster's genre station, 3 × 50: picks of the cluster.
        var genreStation = 0.0
        /// Your Station at Tuesday 08:00 for the listener of RadioClockTests:
        /// Jazz with the clock and without, and Your Station's card.
        var jazzClock = 0.0
        var jazzBlind = 0.0
        var fact = "none"
    }

    static func measure(_ snapshot: LibrarySnapshot, _ library: RadioSyntheticLibrary,
                        clock listener: RadioClockListener) -> Measured {
        let taste = TasteProfile(snapshot: snapshot, history: library.history, now: library.now)
        let graph = SimilarityGraph.fromLibrary(snapshot)
        var m = Measured()
        var stations = 0.0
        for seed in library.artists.prefix(16) {
            for run in 0..<3 {
                var session = RadioSession(station: Station(seed: .artist(key: seed.key, name: seed.name, id: seed.id), snapshot: snapshot),
                                           snapshot: snapshot, taste: taste, graph: graph, randomSeed: UInt64(run * 1000 + seed.cluster))
                let keys = session.next(50).compactMap { snapshot.primaryArtistKey(of: $0.track) }
                stations += 1
                m.inCluster += Double(keys.filter { library.clusterOfArtist[$0] == seed.cluster }.count) / Double(max(1, keys.count))
                let others = keys.filter { $0 != seed.key }
                m.sameSubgenre += Double(others.filter { library.subgenreOfArtist[$0] == seed.subgenre }.count) / Double(max(1, others.count))
            }
        }
        m.inCluster /= stations
        m.sameSubgenre /= stations
        var genreRuns = 0.0
        for (c, cluster) in RadioSyntheticLibrary.clusters.enumerated() {
            for run in 0..<3 {
                let seed = StationSeed.genre(key: NameKey.genre(cluster.genre), name: cluster.genre)
                var session = RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot,
                                           taste: taste, graph: graph, randomSeed: UInt64(77 + run))
                let keys = session.next(50).compactMap { snapshot.primaryArtistKey(of: $0.track) }
                m.genreStation += Double(keys.filter { library.clusterOfArtist[$0] == c }.count) / Double(max(1, keys.count))
                genreRuns += 1
            }
        }
        m.genreStation /= genreRuns
        let now = RadioClockTests.tuesdayMorning
        for clock in [true, false] {
            let data = TasteData(snapshot: snapshot, history: listener.history, now: now,
                                 calendar: RadioClockListener.calendar, timeAware: clock)
            let taste = TasteProfile(data: data)
            if clock { m.fact = taste.timeFact?.text ?? "none" }
            var jazz = 0.0, picks = 0.0
            for run in 0..<20 {
                var session = RadioSession(station: Station(seed: .personal, snapshot: snapshot), snapshot: snapshot,
                                           taste: taste, graph: graph, randomSeed: UInt64(100 + run))
                for pick in session.next(30) {
                    picks += 1
                    if let key = snapshot.primaryArtistKey(of: pick.track), library.clusterOfArtist[key] == 2 { jazz += 1 }
                }
            }
            if clock { m.jazzClock = jazz / picks } else { m.jazzBlind = jazz / picks }
        }
        return m
    }

    static func describe(_ name: String, _ m: Measured) -> String {
        String(format: "tags: %@: artist stations in cluster %.3f, same sub-genre %.3f; genre stations in cluster %.3f; Jazz at Tuesday 08:00 %.3f -> %.3f with the clock (x%.2f); fact: %@",
               name, m.inCluster, m.sameSubgenre, m.genreStation, m.jazzBlind, m.jazzClock,
               m.jazzClock / max(1e-9, m.jazzBlind), m.fact)
    }

    func testTagsOnALibraryWithPoorTags() async {
        let library = RadioSyntheticLibrary()
        let listener = RadioClockListener(library: library, weeks: 8, pattern: true)
        let knowledge = Self.knowledge(library)
        let full = LibrarySnapshot(tracks: library.tracks)
        let poor = LibrarySnapshot(tracks: Self.poorTracks(library))

        let mock = LastFMMockTransport(knowledge)
        let (service, _) = await self.service(mock)
        _ = await service.enrichTags(snapshot: poor, priority: [], maxArtists: 100)
        let asked = mock.requests.filter { $0.asked.method == "artist.gettoptags" }.count
        Self.line("tags: \(asked) artists asked, \(knowledge.topTags.count) known to Last.fm; poor tags: a third of the artists without a genre, the rest with the broad one only")

        let before = Self.measure(poor, library, clock: listener)
        Self.line(Self.describe("poor tags", before))
        var at: [Double: Measured] = [:]
        for weight in [0.25, 0.5, 1.0] {
            await service.setTagWeight(weight)
            let tagged = await service.radioSnapshot(for: poor)
            let m = Self.measure(tagged, library, clock: listener)
            at[weight] = m
            Self.line(Self.describe(String(format: "poor tags + Last.fm at %.2f", weight), m))
        }
        let reference = Self.measure(full, library, clock: listener)
        Self.line(Self.describe("the files' full tags", reference))
        // The files' full tags and Last.fm's on top: it must not hurt.
        await service.setTagWeight(0.5)
        _ = await service.enrichTags(snapshot: full, priority: [], maxArtists: 100)
        let both = Self.measure(await service.radioSnapshot(for: full), library, clock: listener)
        Self.line(Self.describe("full tags + Last.fm at 0.50", both))

        let chosen = at[0.5]!
        XCTAssertGreaterThan(chosen.sameSubgenre, before.sameSubgenre)
        XCTAssertGreaterThanOrEqual(chosen.inCluster, before.inCluster - 0.01)
        XCTAssertGreaterThanOrEqual(chosen.genreStation, before.genreStation - 0.01)
        XCTAssertGreaterThanOrEqual(both.inCluster, reference.inCluster - 0.02)
    }

    // MARK: Which page: "Angele" and "Angèle"

    /// His "Angele", as Last.fm answered on 20 and 23 November 2026: three
    /// pages for the name, the one spelt as his files a small one tagged
    /// with thrash metal bands, hers with the accent. Her songs have no
    /// genre in the files, and no neighbour in the library.
    static func angele() -> (tracks: [Track], knowledge: LastFMKnowledge) {
        let her = ArtistRef(id: "angele", name: "Angele")
        var tracks = (1...12).map { n in
            Track(id: "a\(n)", name: "Song \(n)", albumID: "brol", albumName: "Brol", artists: [her], albumArtist: her)
        }
        let other = ArtistRef(id: "trio", name: "Blue Room Trio")
        tracks += (1...6).map { n in
            Track(id: "b\(n)", name: "Tune \(n)", albumID: "blue", albumName: "Blue", artists: [other], albumArtist: other, genres: ["Jazz"])
        }
        var k = LastFMKnowledge()
        k.pages["Angele"] = [("Angèle", 508_456), ("Angele", 2345), ("Angéle", 47), ("Angela", 112_133)]
        k.topTags["Angele"] = [("Slayer", 100), ("pop", 100), ("Megadeth", 66), ("Belgium", 66), ("Iron Maiden", 33),
                               ("Anthrax", 33), ("sod", 33), ("johnny fountains", 10)]
        k.topTags["Angèle"] = [("pop", 100), ("Belgium", 81), ("indie pop", 45), ("belgian", 33), ("french pop", 13), ("french", 7)]
        k.topTags["Blue Room Trio"] = [("jazz", 100)]
        k.similarArtists["Angèle"] = [("Stromae", 1), ("Clara Luciani", 0.9)]
        k.similarArtists["Angele"] = [("Grandgeorge", 1)]
        k.similarTracks["Angèle|Song 1"] = [("Angèle", "Song 2", 0.8)]
        return (tracks, k)
    }

    func testAngeleIsAskedAsAngèle() async throws {
        let (tracks, knowledge) = Self.angele()
        let snapshot = LibrarySnapshot(tracks: tracks)
        let her = NameKey.artist("Angele")
        let mock = LastFMMockTransport(knowledge)
        let (service, directory) = await self.service(mock)

        let radio = await service.enrichTags(snapshot: snapshot, priority: [her], maxArtists: 1)
        let genres = Set(radio.genreKeys(of: tracks[0]))
        XCTAssertTrue(genres.contains(NameKey.genre("Indie Pop")))
        XCTAssertTrue(genres.contains(NameKey.genre("Pop")))
        XCTAssertFalse(genres.contains(NameKey.genre("Slayer")))
        XCTAssertFalse(genres.contains(NameKey.genre("Megadeth")))
        // Her three spellings compared, most listened to first; "Angela",
        // another name, is not. With nothing in the library to go by, the
        // biggest page.
        XCTAssertEqual(mock.requests.filter { $0.asked.method == "artist.gettoptags" }.map(\.asked.artist),
                       ["Angèle", "Angele", "Angéle"])

        // Every other question about her goes to that page too.
        _ = await service.enrich(snapshot: snapshot, priority: [her])
        _ = await service.similarTracks(to: tracks[0], in: snapshot)
        let rest = mock.requests.filter { $0.asked.method == "artist.getsimilar" || $0.asked.method == "track.getsimilar" }
        XCTAssertEqual(rest.map(\.asked.artist), ["Angèle", "Angèle"])

        // Another launch: hers from disk, only the trio's asked.
        let quiet = LastFMMockTransport(knowledge)
        let (again, _) = await self.service(quiet, directory: directory)
        _ = await again.enrichTags(snapshot: snapshot, priority: [her], maxArtists: 1)
        XCTAssertEqual(Set(quiet.requests.map(\.asked.artist)), ["Blue Room Trio"])
    }

    /// An answer from before the pages were compared ("Angele"'s Slayer) is
    /// asked again, though half a year has not passed.
    func testAnOldAnswerIsAskedAgain() async throws {
        let (tracks, knowledge) = Self.angele()
        let snapshot = LibrarySnapshot(tracks: tracks)
        let her = NameKey.artist("Angele")
        let directory = LastFMFixtures.directory()
        var old = LastFMStore()
        old.tags[her] = .init(name: "Angele", fetched: Date(), tags: [.init(name: "Slayer", count: 100)], page: nil)
        old.saveTags(to: directory)
        let mock = LastFMMockTransport(knowledge)
        let (service, _) = await self.service(mock, directory: directory)
        let before = await service.radioSnapshot(for: snapshot)
        XCTAssertTrue(before.genreKeys(of: tracks[0]).contains(NameKey.genre("Slayer")))
        let radio = await service.enrichTags(snapshot: snapshot, priority: [her], maxArtists: 1)
        XCTAssertFalse(radio.genreKeys(of: tracks[0]).contains(NameKey.genre("Slayer")))
        XCTAssertTrue(radio.genreKeys(of: tracks[0]).contains(NameKey.genre("Indie Pop")))
    }

    /// Where the library does say something, it outweighs the listeners: a
    /// jazz singer filed as "Ghost", beside a far bigger "Ghöst" of black
    /// metal. Her files say Jazz; a second singer without a genre is placed
    /// by her neighbour's tags (a guest on the jazz trio's record).
    func testThePageTheLibraryAgreesWithWinsOverTheBiggerOne() async throws {
        let ghost = ArtistRef(id: "ghost", name: "Ghost")
        let nova = ArtistRef(id: "nova", name: "Nova")
        let trio = ArtistRef(id: "trio", name: "Blue Room Trio")
        var tracks = (1...6).map { n in
            Track(id: "g\(n)", name: "Ballad \(n)", albumID: "g", albumName: "G", artists: [ghost], albumArtist: ghost, genres: ["Jazz"])
        }
        tracks += (1...4).map { n in
            Track(id: "n\(n)", name: "Nova \(n)", albumID: "n", albumName: "N", artists: [nova], albumArtist: nova)
        }
        tracks += (1...6).map { n in
            Track(id: "t\(n)", name: "Tune \(n)", albumID: "t", albumName: "T", artists: n <= 3 ? [trio, nova] : [trio],
                  albumArtist: trio, genres: ["Jazz"])
        }
        let snapshot = LibrarySnapshot(tracks: tracks)
        var k = LastFMKnowledge()
        k.pages["Ghost"] = [("Ghöst", 400_000), ("Ghost", 900)]
        k.topTags["Ghöst"] = [("black metal", 100), ("metal", 80)]
        k.topTags["Ghost"] = [("vocal jazz", 100), ("jazz", 90)]
        k.pages["Nova"] = [("Növa", 300_000), ("Nova", 700)]
        k.topTags["Növa"] = [("techno", 100)]
        k.topTags["Nova"] = [("jazz", 100), ("soul", 40)]
        k.topTags["Blue Room Trio"] = [("jazz", 100), ("bebop", 60)]
        let mock = LastFMMockTransport(k)
        let (service, _) = await self.service(mock)
        // The trio first: their tags are what Nova's neighbour says.
        let radio = await service.enrichTags(snapshot: snapshot, priority: ["blueroomtrio", "ghost", "nova"], maxArtists: 3)
        let ghostGenres = Set(radio.genreKeys(of: tracks[0]))
        XCTAssertTrue(ghostGenres.contains(NameKey.genre("Vocal Jazz")))
        XCTAssertFalse(ghostGenres.contains(NameKey.genre("Black Metal")))
        let novaGenres = Set(radio.genreKeys(of: tracks[6]))
        XCTAssertTrue(novaGenres.contains(NameKey.genre("Soul")))
        XCTAssertFalse(novaGenres.contains(NameKey.genre("Techno")))
    }
}
