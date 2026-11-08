// The radio's parts one by one: the snapshot's indices and matching, the
// taste profile's bounds and order, the graph's edges, and the session's
// rules (docs/RADIO.md). The evaluation (RadioEvaluationTests) measures
// how well it all chooses; these say it does what it says.

import Foundation
import JukeboxKit
import XCTest

/// Small hand-made libraries.
enum RadioTestTracks {
    static func ref(_ name: String) -> ArtistRef { ArtistRef(id: "id-" + NameKey.artist(name), name: name) }

    static func track(_ id: String, _ artist: String, album: String? = nil, guests: [String] = [], genres: [String] = ["Rock"],
                      year: Int? = 2000, number: Int? = nil, favorite: Bool = false, plays: Int = 0,
                      lastPlayed: Date? = nil, duration: TimeInterval = 200) -> Track {
        Track(id: id, name: "Song \(id)", albumID: album ?? "album-\(NameKey.artist(artist))", albumName: album ?? "Album of \(artist)",
              artists: [ref(artist)] + guests.map(ref), albumArtist: ref(artist), genres: genres, year: year,
              trackNumber: number, discNumber: 1, duration: duration, albumImageTag: "tag-\(album ?? artist)",
              isFavorite: favorite, playCount: plays, lastPlayed: lastPlayed)
    }

    static func session(_ tracks: [Track], seed: StationSeed = .personal, history: ListeningHistory = ListeningHistory(),
                        settings: RadioSettings = RadioSettings(), recentlyPlayed: Set<ItemID> = [],
                        graph: SimilarityGraph? = nil, randomSeed: UInt64 = 1) -> RadioSession {
        let snapshot = LibrarySnapshot(tracks: tracks)
        let taste = TasteProfile(snapshot: snapshot, history: history, now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        return RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot, taste: taste,
                            graph: graph ?? .fromLibrary(snapshot), settings: settings, recentlyPlayed: recentlyPlayed,
                            randomSeed: randomSeed)
    }
}

// MARK: - The snapshot

final class RadioSnapshotTests: XCTestCase {
    func testIndicesSplitJoinedTags() {
        let polder = ArtistRef(id: "mp", name: "MC Polder")
        let tracks = [
            Track(id: "1", name: "One", albumID: "a", albumName: "A", artists: [ArtistRef(id: "x", name: "MC Polder; Lyric Engine")],
                  albumArtist: polder, genres: ["Hip-Hop; Nederhop"], year: 2006, trackNumber: 2, discNumber: 1),
            Track(id: "2", name: "Two", albumID: "a", albumName: "A", artists: [polder], albumArtist: polder,
                  genres: ["Hip-Hop", "Nederhop"], year: 2006, trackNumber: 1, discNumber: 1),
            Track(id: "3", name: "Three", albumID: "b", albumName: "B", artists: [ArtistRef(id: "le", name: "Lyric Engine")],
                  albumArtist: ArtistRef(id: "le", name: "Lyric Engine"), genres: ["Rap"], year: 2018),
            Track(id: "4", name: "Four", albumID: "c", albumName: "Hits", artists: [ArtistRef(id: nil, name: "Concrete Poets feat. Saskia de Wit")],
                  albumArtist: ArtistRef(id: "va", name: "Various Artists"), genres: ["Hip-Hop"], year: 0),
            Track(id: "5", name: "Five", albumID: "a", albumName: "A", artists: [polder], albumArtist: polder,
                  genres: ["Hip-Hop"], year: 2006, trackNumber: 1, discNumber: 2),
        ]
        let s = LibrarySnapshot(tracks: tracks)
        XCTAssertEqual(s.track(id: "3")?.name, "Three")
        XCTAssertNil(s.track(id: "nope"))
        XCTAssertEqual(s.tracks(albumID: "a").map(\.id), ["2", "1", "5"], "disc, then track order")
        XCTAssertEqual(Set(s.tracks(artistKey: "lyricengine").map(\.id)), ["1", "3"], "a joined tag split")
        XCTAssertEqual(s.artistKeys(of: tracks[0]), ["mcpolder", "lyricengine"], "filed-under artist first")
        XCTAssertEqual(s.artist(key: "lyricengine")?.id, "le", "a split part gets the id it has elsewhere")
        XCTAssertEqual(s.genreKeys(of: tracks[0]), ["hiphop", "nederhop"])
        XCTAssertEqual(s.genreTrackCounts["nederhop"], 2)
        XCTAssertEqual(s.genreName(key: "hiphop"), "Hip-Hop")
        XCTAssertEqual(s.artistKeys(of: tracks[3]), ["concretepoets", "saskiadewit"], "Various Artists is nobody")
        XCTAssertEqual(s.tracks(artistKey: "variousartists").map(\.id), ["4"], "but can be looked up")
        XCTAssertEqual(s.decadeTrackCounts, [2000: 3, 2010: 1], "year 0 is no year")
        XCTAssertEqual(s.tracks(decade: 2010).map(\.id), ["3"])
        XCTAssertEqual(s.artistTrackCounts["mcpolder"], 3)
        XCTAssertEqual(s.ownTracks(artistKey: "lyricengine").map(\.id), ["3"])
        XCTAssertEqual(s.position(of: "4"), 3)
        XCTAssertGreaterThan(s.genreSpecificity(key: "rap"), s.genreSpecificity(key: "hiphop"))
    }

    func testMatchPrefersTheOriginal() {
        let radiohead = ArtistRef(id: "rh", name: "Radiohead")
        func t(_ id: String, _ name: String, album: String, year: Int, plays: Int) -> Track {
            Track(id: id, name: name, albumID: album, albumName: album, artists: [radiohead], albumArtist: radiohead,
                  genres: ["Rock"], year: year, playCount: plays)
        }
        let s = LibrarySnapshot(tracks: [
            t("hits", "Karma Police", album: "Greatest Hits", year: 2008, plays: 40),
            t("live", "Karma Police (Live)", album: "Live in Paris", year: 2001, plays: 9),
            t("ok", "Karma Police", album: "OK Computer", year: 1997, plays: 3),
            t("creep", "Creep (Remastered 2009)", album: "Pablo Honey", year: 1993, plays: 1),
            Track(id: "beatles", name: "Help!", artists: [ArtistRef(id: nil, name: "Beatles")], genres: ["Pop"]),
        ])
        XCTAssertEqual(s.match(artist: "Radiohead", title: "Karma Police")?.id, "ok")
        XCTAssertEqual(s.match(artist: "radiohead", title: "Creep")?.id, "creep")
        XCTAssertEqual(s.match(artist: "The Beatles", title: "Help")?.id, "beatles")
        XCTAssertNil(s.match(artist: "Radiohead", title: "Paranoid Android"))
        XCTAssertNil(s.match(artist: "Muse", title: "Karma Police"))
        XCTAssertEqual(s.matchArtist("The Beatles"), "beatles")
        XCTAssertEqual(s.matchArtist("Radiohead feat. Someone"), "radiohead")
        XCTAssertNil(s.matchArtist("Portishead"))
    }

    func testEmpty() {
        let s = LibrarySnapshot.empty
        XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(s.artistTrackCounts.isEmpty)
        XCTAssertTrue(s.genreTrackCounts.isEmpty)
        XCTAssertTrue(s.decadeTrackCounts.isEmpty)
        XCTAssertNil(s.match(artist: "A", title: "B"))
        XCTAssertNil(s.artist(key: "a"))
        XCTAssertEqual(s.tracks(artistKey: "a"), [])
    }
}

// MARK: - Taste

final class RadioTasteTests: XCTestCase {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func days(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    func testOrderAndBounds() {
        let tracks = [
            RadioTestTracks.track("fav", "Loved", favorite: true),
            RadioTestTracks.track("played", "Loved", plays: 5, lastPlayed: days(2)),
            RadioTestTracks.track("unheard", "Stranger"),
            RadioTestTracks.track("skipped", "Skipped"),
            RadioTestTracks.track("disliked", "Hated"),
            RadioTestTracks.track("old", "Old", plays: 30, lastPlayed: days(700)),
            RadioTestTracks.track("weird", "Weird", plays: -5, lastPlayed: now.addingTimeInterval(86_400 * 30), duration: 0),
            RadioTestTracks.track("recent", "Fresh"),
            RadioTestTracks.track("longago", "Fresh"),
        ]
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var history = ListeningHistory()
        for k in 0..<4 { history.append(PlayEvent(track: byID["skipped"]!, date: days(Double(k)), listened: 5, outcome: .skipped)) }
        history.append(PlayEvent(track: byID["disliked"]!, date: days(1), listened: 10, outcome: .disliked))
        history.append(PlayEvent(track: byID["longago"]!, date: days(63), listened: 200, outcome: .completed))
        history.append(PlayEvent(track: byID["recent"]!, date: days(0), listened: 200, outcome: .completed))
        history.append(PlayEvent(trackID: "weird", date: now.addingTimeInterval(1e9), listened: .nan, duration: .infinity, outcome: .completed))
        let snapshot = LibrarySnapshot(tracks: tracks)
        let taste = TasteProfile(snapshot: snapshot, history: history, now: now)

        let a = { (id: String) in taste.trackAffinity(id) }
        XCTAssertGreaterThan(a("fav"), 0.4)
        XCTAssertGreaterThan(a("played"), 0.3)
        XCTAssertEqual(a("unheard"), 0)
        XCTAssertLessThan(a("skipped"), -0.5)
        XCTAssertLessThan(a("disliked"), a("skipped"))
        XCTAssertGreaterThan(a("old"), 0, "a lot of plays long ago is still liking")
        XCTAssertGreaterThan(a("recent"), a("longago"), "recent weighs more")
        XCTAssertGreaterThan(a("longago"), 0)
        for t in tracks {
            XCTAssertTrue(a(t.id).isFinite && (-1...1).contains(a(t.id)), t.id)
            let f = taste.familiarity(t.id)
            XCTAssertTrue(f.isFinite && (0...1).contains(f), t.id)
        }
        XCTAssertEqual(taste.familiarity("unheard"), 0)
        XCTAssertGreaterThan(taste.familiarity("played"), 0.7)
        XCTAssertGreaterThanOrEqual(taste.familiarity("fav"), 0.6)
        XCTAssertEqual(a("nope"), 0)

        XCTAssertEqual(taste.topArtists(1), [NameKey.artist("Loved")])
        XCTAssertFalse(taste.topArtists(20).contains(NameKey.artist("Hated")), "a disliked artist is not a top one")
        XCTAssertGreaterThan(taste.artistAffinity(NameKey.artist("Loved")), taste.artistAffinity(NameKey.artist("Old")))
        XCTAssertLessThan(taste.artistAffinity(NameKey.artist("Skipped")), 0)
        XCTAssertEqual(taste.topTracks(2).count, 2)
        XCTAssertEqual(taste.topTracks(1).first.map(a), [a("fav"), a("played"), a("recent"), a("old")].max())
        XCTAssertEqual(taste.topGenres(1), [NameKey.genre("Rock")])
        XCTAssertEqual(taste.lastHeard("played")?.timeIntervalSinceReferenceDate ?? 0, days(2).timeIntervalSinceReferenceDate, accuracy: 1)
        XCTAssertNil(taste.lastHeard("unheard"))
        for t in tracks { XCTAssertTrue(taste.artistAffinity(snapshot.primaryArtistKey(of: t)!).isFinite) }
    }

    func testThreeWeeksIsHalf() {
        let tracks = [RadioTestTracks.track("today", "A"), RadioTestTracks.track("weeks", "B")]
        let history = ListeningHistory(events: [
            PlayEvent(track: tracks[1], date: days(21), listened: 200, outcome: .completed),
            PlayEvent(track: tracks[0], date: days(0), listened: 200, outcome: .completed),
        ])
        let taste = TasteProfile(snapshot: LibrarySnapshot(tracks: tracks), history: history, now: now)
        // tanh(x / 3) is close to linear here: the ratio is about one half.
        let ratio = taste.trackAffinity("weeks") / taste.trackAffinity("today")
        XCTAssertEqual(ratio, 0.5, accuracy: 0.05)
    }

    func testANewListenerStillHasTopArtists() {
        var tracks: [Track] = []
        for k in 0..<5 { tracks.append(RadioTestTracks.track("big\(k)", "Big")) }
        for k in 0..<2 { tracks.append(RadioTestTracks.track("small\(k)", "Small")) }
        let taste = TasteProfile(snapshot: LibrarySnapshot(tracks: tracks), history: ListeningHistory(), now: now)
        XCTAssertEqual(taste.topArtists(5), ["big", "small"])
        XCTAssertEqual(taste.topTracks(5), [])
    }

    func testEventsKeepSplitKeys() {
        let duet = Track(id: "d", name: "Duet", artists: [ArtistRef(id: nil, name: "MC Polder; Lyric Engine")],
                         albumArtist: ArtistRef(id: nil, name: "MC Polder"), genres: ["Hip-Hop; Nederhop"])
        let event = PlayEvent(track: duet, date: now, listened: 10, outcome: .skipped)
        XCTAssertEqual(event.artistKeys, ["lyricengine", "mcpolder"])
        XCTAssertEqual(event.genreKeys, ["hiphop", "nederhop"])
    }

    func testHistoryOfTracksNoLongerInTheLibraryCountsForTheArtist() {
        let tracks = [RadioTestTracks.track("1", "Kept")]
        let history = ListeningHistory(events: [
            PlayEvent(trackID: "gone", date: days(1), listened: 200, duration: 200, outcome: .liked, artistKeys: ["kept"], genreKeys: ["rock"]),
        ])
        let taste = TasteProfile(snapshot: LibrarySnapshot(tracks: tracks), history: history, now: now)
        XCTAssertGreaterThan(taste.artistAffinity("kept"), 0)
        XCTAssertGreaterThan(taste.genreAffinity("rock"), 0)
    }
}

// MARK: - The graph

final class RadioGraphTests: XCTestCase {
    func testASpecificGenreInCommonSaysMore() {
        var tracks: [Track] = []
        // Rock is everyone's; Shoegaze two artists'.
        for k in 0..<10 { tracks.append(RadioTestTracks.track("r\(k)", "Rocker \(k)", genres: ["Rock", "Style \(k)"])) }
        tracks.append(RadioTestTracks.track("p1", "Plain One", genres: ["Rock"], year: 1990))
        tracks.append(RadioTestTracks.track("p2", "Plain Two", genres: ["Rock"], year: 1990))
        tracks.append(RadioTestTracks.track("s1", "Gaze One", genres: ["Rock", "Shoegaze"], year: 1990))
        tracks.append(RadioTestTracks.track("s2", "Gaze Two", genres: ["Rock", "Shoegaze"], year: 1990))
        let graph = SimilarityGraph.fromLibrary(LibrarySnapshot(tracks: tracks))
        let gaze = graph.weight("gazeone", "gazetwo")
        let plain = graph.weight("plainone", "plaintwo")
        RadioEvaluationTests.line(String(format: "graph: two artists both Rock and Shoegaze %.2f, two both only Rock %.2f", gaze, plain))
        XCTAssertGreaterThan(gaze, 0.4)
        XCTAssertLessThan(plain, 0.3)
        XCTAssertGreaterThan(gaze, 2 * plain)
    }

    func testGuests() {
        let tracks = [
            RadioTestTracks.track("1", "Trio", guests: ["Singer"], genres: ["Jazz"]),
            RadioTestTracks.track("2", "Trio", genres: ["Jazz"]),
            RadioTestTracks.track("3", "Singer", genres: ["Jazz", "Vocal Jazz"]),
            RadioTestTracks.track("4", "Quartet", genres: ["Jazz"]),
            RadioTestTracks.track("5", "Quartet", guests: ["Rapper"], genres: ["Jazz"]),
            RadioTestTracks.track("6", "Rapper", genres: ["Hip-Hop"]),
            RadioTestTracks.track("7", "Other Rapper", genres: ["Hip-Hop"]),
        ]
        let graph = SimilarityGraph.fromLibrary(LibrarySnapshot(tracks: tracks))
        XCTAssertGreaterThan(graph.weight("trio", "singer"), graph.weight("trio", "quartet"), "a guest who shares a genre")
        XCTAssertEqual(graph.weight("trio", "singer"), graph.weight("singer", "trio"))
        let across = graph.weight("quartet", "rapper")
        XCTAssertGreaterThan(across, 0.1, "a guest from another genre still links")
        XCTAssertLessThan(across, graph.weight("trio", "singer"), "but less")
        XCTAssertEqual(graph.weight("trio", "otherrapper"), 0)
    }

    func testBothWaysAndThirtyEach() {
        var tracks: [Track] = []
        // Everyone alike by genre, so every artist has 44 candidates and the
        // cap of 30 decides (by era, then by order).
        for k in 0..<45 { tracks.append(RadioTestTracks.track("\(k)", "Artist \(k)", genres: ["Pop", "Indie"], year: 1980 + k)) }
        let graph = SimilarityGraph.fromLibrary(LibrarySnapshot(tracks: tracks))
        for a in graph.artistKeys {
            let neighbors = graph.similarArtists(to: a, limit: 100)
            XCTAssertGreaterThanOrEqual(neighbors.count, 30)
            XCTAssertLessThan(neighbors.count, 45)
            XCTAssertEqual(neighbors.map(\.weight), neighbors.map(\.weight).sorted(by: >), "heaviest first")
            for n in neighbors {
                XCTAssertEqual(graph.weight(n.key, a), n.weight, "both ways")
                XCTAssertTrue(n.weight > 0 && n.weight <= 1)
            }
        }
        XCTAssertEqual(graph.similarArtists(to: "artist0", limit: 3).count, 3)
        XCTAssertEqual(graph.enrichedArtistCount, 0, "the library's own edges are not Last.fm's")
    }

    func testEdgesMergingAndDisk() throws {
        var graph = SimilarityGraph()
        XCTAssertEqual(graph.similarArtists(to: "a"), [])
        graph.addArtistEdge("a", "b", weight: 0.5)
        graph.addArtistEdge("b", "a", weight: 0.3)
        graph.addArtistEdge("a", "a", weight: 1)
        graph.addArtistEdge("a", "c", weight: .nan)
        graph.addArtistEdge("a", "d", weight: -1)
        XCTAssertEqual(graph.weight("a", "b"), 0.5, "the heavier kept")
        XCTAssertEqual(graph.weight("b", "a"), 0.5)
        XCTAssertEqual(graph.similarArtists(to: "a").map(\.key), ["b"])
        XCTAssertEqual(graph.enrichedArtistCount, 2)
        graph.addTrackEdge(from: "t1", to: "t2", weight: 0.7)
        graph.addTrackEdge(from: "t1", to: "t3", weight: 3)
        XCTAssertEqual(graph.similarTracks(to: "t1"), [Neighbor(key: "t3", weight: 1), Neighbor(key: "t2", weight: 0.7)])
        XCTAssertEqual(graph.similarTracks(to: "t2"), [], "one way")

        var library = SimilarityGraph()
        library.merge(graph)
        var lastFM = SimilarityGraph()
        lastFM.addArtistEdge("a", "e", weight: 0.9)
        library.merge(lastFM)
        XCTAssertEqual(library.weight("e", "a"), 0.9)
        XCTAssertEqual(library.weight("a", "b"), 0.5)
        XCTAssertEqual(library.enrichedArtistCount, 2)
        XCTAssertTrue(library.isEnriched("a"))

        let data = try JSONEncoder().encode(library)
        let back = try JSONDecoder().decode(SimilarityGraph.self, from: data)
        XCTAssertEqual(back.similarArtists(to: "a"), library.similarArtists(to: "a"))
        XCTAssertEqual(back.similarTracks(to: "t1"), library.similarTracks(to: "t1"))
        XCTAssertEqual(back.enrichedArtistCount, 2)
        let empty = try JSONDecoder().decode(SimilarityGraph.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.artistKeys, [])
    }
}

// MARK: - Stations and sessions

final class RadioSessionTests: XCTestCase {
    var world: RadioEvaluationTests.World { RadioEvaluationTests.shared }

    func testTheSameSeedIsTheSameStation() {
        let w = world
        let seed = w.artistSeed(w.library.artists[3])
        func play(_ randomSeed: UInt64) -> [ItemID] {
            var session = w.session(seed, randomSeed: randomSeed)
            var ids: [ItemID] = []
            for round in 0..<10 {
                let picks = session.next(5)
                ids += picks.map(\.track.id)
                session.record(round % 2 == 0 ? .skipped(picks[0].track.id, after: 3) : .liked(picks[1].track.id))
                session.returnUnplayed(Array(picks.suffix(2).map(\.track.id)))
                ids = Array(ids.dropLast(2))
            }
            return ids
        }
        XCTAssertEqual(play(42), play(42))
        XCTAssertNotEqual(play(42), play(43))
    }

    func testTheRulesHoldForHours() {
        let w = world
        for (k, seed) in [w.artistSeed(w.library.artists[0]), .genre(key: "rock", name: "Rock"), .personal].enumerated() {
            var session = w.session(seed, randomSeed: UInt64(k))
            let picks = session.next(400)
            XCTAssertEqual(picks.count, 400)
            XCTAssertEqual(RadioMetrics.repeats(picks), 0)
            XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: w.snapshot, separation: 3), 0)
            XCTAssertEqual(RadioMetrics.albumBackToBack(picks), 0)
            XCTAssertTrue(picks.allSatisfy { $0.score.isFinite && $0.score > 0 })
            XCTAssertEqual(session.handedOut, picks.map(\.track.id))
        }
    }

    func testATinyLibraryNeverEnds() {
        let tracks = [
            RadioTestTracks.track("a1", "A"), RadioTestTracks.track("a2", "A"), RadioTestTracks.track("a3", "A"),
            RadioTestTracks.track("b1", "B"), RadioTestTracks.track("b2", "B"),
        ]
        var session = RadioTestTracks.session(tracks)
        let picks = session.next(30).map(\.track.id)
        XCTAssertEqual(picks.count, 30)
        XCTAssertEqual(Set(picks.prefix(5)).count, 5, "every song once before any again")
        for k in 5..<picks.count {
            XCTAssertFalse(picks[(k - 2)..<k].contains(picks[k]), "a repeat waits for half the library")
        }
        var one = RadioTestTracks.session([RadioTestTracks.track("only", "Solo")])
        XCTAssertEqual(one.next(3).map(\.track.id), ["only", "only", "only"])
    }

    func testRulesLoosenInOrder() {
        // Four artists, two songs each; two of the songs were heard an hour ago.
        var tracks: [Track] = []
        for artist in ["A", "B", "C", "D"] {
            for k in 1...2 { tracks.append(RadioTestTracks.track("\(artist)\(k)", artist, album: "\(artist)-\(k)")) }
        }
        var session = RadioTestTracks.session(tracks, recentlyPlayed: ["A1", "B1"])
        let picks = session.next(10).map(\.track.id)
        // Separation loosens first: the six not heard lately come first …
        XCTAssertEqual(Set(picks.prefix(6)), ["A2", "B2", "C1", "C2", "D1", "D2"])
        // … then recency: the two heard lately …
        XCTAssertEqual(Set(picks[6..<8]), ["A1", "B1"])
        // … and only then a repeat.
        XCTAssertEqual(Set(picks).count, 8)
        // The first four keep four artists apart.
        XCTAssertEqual(Set(picks.prefix(4).map { $0.prefix(1) }).count, 4)
    }

    func testASongStationStartsWithTheSongEvenIfJustHeard() {
        let w = world
        let song = w.snapshot.tracks[77]
        var session = RadioSession(station: Station(seed: .track(song.id), snapshot: w.snapshot), snapshot: w.snapshot,
                                   taste: w.taste, graph: w.graph, recentlyPlayed: [song.id], randomSeed: 5)
        let picks = session.next(10)
        XCTAssertEqual(picks.first?.track.id, song.id)
        XCTAssertEqual(picks.first?.reason, .seed)
        XCTAssertEqual(picks.filter { $0.track.id == song.id }.count, 1)
    }

    func testReturnUnplayedPutsTracksBack() {
        let w = world
        var session = w.session(.personal, randomSeed: 9)
        let first = session.next(5).map(\.track.id)
        XCTAssertEqual(session.handedOut, first)
        session.returnUnplayed(Array(first.suffix(3)) + ["not-handed-out"])
        XCTAssertEqual(session.handedOut, Array(first.prefix(2)))
        let again = session.next(3).map(\.track.id)
        XCTAssertEqual(session.handedOut, Array(first.prefix(2)) + again)
        XCTAssertEqual(Set(session.handedOut).count, 5)
        XCTAssertTrue(Set(first.prefix(2)).isDisjoint(with: again))
    }

    func testFeedbackActsOnTheVeryNextPick() {
        let w = world
        let seedArtist = w.library.artists[1]
        var session = w.session(w.artistSeed(seedArtist), randomSeed: 21)
        let picks = session.next(8)
        guard let victim = picks.dropFirst().first(where: { w.snapshot.primaryArtistKey(of: $0.track) != seedArtist.key }),
              let artist = w.snapshot.primaryArtistKey(of: victim.track) else { return XCTFail("no other artist in 8 picks") }
        let position = picks.firstIndex(of: victim)!
        session.record(.disliked(victim.track.id))
        session.returnUnplayed(Array(picks[(position + 1)...].map(\.track.id)))
        let next = session.next(20)
        XCTAssertFalse(next.contains { $0.track.id == victim.track.id })
        XCTAssertLessThanOrEqual(next.filter { w.snapshot.artistKeys(of: $0.track).contains(artist) }.count, 1)
    }

    func testInstantMixCandidatesJoin() {
        let w = world
        let metal = w.snapshot.tracks(genreKey: "metal").prefix(12).map(\.id)
        var plain = w.session(.genre(key: "jazz", name: "Jazz"), randomSeed: 4)
        var mixed = w.session(.genre(key: "jazz", name: "Jazz"), randomSeed: 4)
        mixed.addCandidates(Array(metal) + ["not-in-library"], weight: 1, reason: .instantMix)
        let without = plain.next(30).filter { metal.contains($0.track.id) }
        let with = mixed.next(30).filter { metal.contains($0.track.id) }
        XCTAssertLessThan(without.count, with.count)
        XCTAssertTrue(with.contains { $0.reason == .instantMix })
    }

    func testSimilarTracksForASongStation() {
        let w = world
        let song = w.snapshot.tracks[300]
        let far = w.snapshot.tracks.first { w.clusterOf(RadioPick(track: $0, reason: .seed, score: 1)) != w.clusterOf(RadioPick(track: song, reason: .seed, score: 1)) }!
        var graph = w.graph
        graph.addTrackEdge(from: song.id, to: far.id, weight: 1)
        var session = RadioSession(station: Station(seed: .track(song.id), snapshot: w.snapshot), snapshot: w.snapshot,
                                   taste: w.taste, graph: graph, randomSeed: 2)
        let picks = session.next(25)
        let pick = picks.first { $0.track.id == far.id }
        XCTAssertNotNil(pick)
        XCTAssertEqual(pick?.reason, .similarTrack(song.name))
    }

    func testTheDialMidSession() {
        let w = world
        var calm = w.session(.personal, adventurousness: 0, randomSeed: 6)
        var bold = w.session(.personal, adventurousness: 0, randomSeed: 6)
        let opening = calm.next(5)
        XCTAssertEqual(bold.next(5).map(\.track.id), opening.map(\.track.id))
        bold.settings.adventurousness = 1
        bold.returnUnplayed(Array(opening.suffix(3).map(\.track.id)))
        calm.returnUnplayed(Array(opening.suffix(3).map(\.track.id)))
        let calmNext = calm.next(40).filter(w.unheard).count
        let boldNext = bold.next(40).filter(w.unheard).count
        XCTAssertGreaterThan(boldNext, calmNext + 10)
    }

    func testAnEmptyLibraryAndUnknownThings() {
        var empty = RadioSession(station: Station(seed: .personal, snapshot: .empty), snapshot: .empty,
                                 taste: TasteProfile(snapshot: .empty, history: ListeningHistory(), now: Date()),
                                 graph: SimilarityGraph(), randomSeed: 1)
        XCTAssertEqual(empty.next(5).count, 0)
        empty.record(.liked("x"))
        empty.record(.skipped("x", after: .nan))
        empty.returnUnplayed(["x"])
        XCTAssertEqual(empty.handedOut, [])

        let w = world
        var nobody = w.session(.artist(key: "nobody", name: "Nobody", id: nil), randomSeed: 3)
        XCTAssertEqual(nobody.next(10).count, 10, "an artist the library does not have still plays")
        nobody.record(.disliked("not-a-track"))
        nobody.addCandidates(["not-a-track"], weight: .infinity, reason: .instantMix)
        XCTAssertEqual(nobody.next(5).count, 5)
        var gone = w.session(.track("gone"), randomSeed: 3)
        XCTAssertEqual(gone.next(5).count, 5)
        var none = w.session(.collection(id: "c", name: "Empty", trackIDs: []), randomSeed: 3)
        XCTAssertEqual(none.next(5).count, 5)
        XCTAssertEqual(w.session(.decade(1850), randomSeed: 3).station.title, "1850s Radio")
    }

    func testStationNamesAndCovers() {
        let w = world
        let s = w.snapshot
        let artist = w.library.artists[2]
        let track = s.tracks[10]
        let cases: [(StationSeed, String, String)] = [
            (.track(track.id), "track-\(track.id)", "\(track.name) Radio"),
            (w.artistSeed(artist), "artist-\(artist.key)", "\(artist.name) Radio"),
            (.album(track.albumID!), "album-\(track.albumID!)", "\(track.albumName!) Radio"),
            (.genre(key: "jazz", name: "jazz"), "genre-jazz", "Jazz Radio"),
            (.decade(1990), "decade-1990", "1990s Radio"),
            (.collection(id: "pl", name: "Night Drive", trackIDs: [track.id]), "collection-pl", "Night Drive Radio"),
            (.personal, "personal", "Your Station"),
            (.discovery, "discovery", "Discovery"),
            (.favorites, "favorites", "Loved"),
        ]
        for (seed, id, title) in cases {
            let station = Station(seed: seed, snapshot: s)
            XCTAssertEqual(station.id, id)
            XCTAssertEqual(Station.id(for: seed), id)
            XCTAssertEqual(station.title, title)
            XCTAssertFalse(station.artwork.isEmpty, title)
            XCTAssertLessThanOrEqual(station.artwork.count, 4)
            XCTAssertEqual(Set(station.artwork).count, station.artwork.count, "\(title): each cover once")
        }
        let own = Set(s.ownTracks(artistKey: artist.key).compactMap(\.artwork))
        XCTAssertTrue(Station(seed: w.artistSeed(artist), snapshot: s).artwork.allSatisfy(own.contains))
    }

    func testPlayOutcomes() {
        XCTAssertEqual(PlayOutcome.of(listened: 10, duration: 200), .skipped)
        XCTAssertEqual(PlayOutcome.of(listened: 100, duration: 200), .partial)
        XCTAssertEqual(PlayOutcome.of(listened: 185, duration: 200), .completed)
        XCTAssertEqual(PlayOutcome.of(listened: 165, duration: 200), .completed)
        XCTAssertEqual(PlayOutcome.of(listened: 1, duration: 6), .skipped, "a short track is not heard by being started")
        XCTAssertEqual(PlayOutcome.of(listened: 5, duration: 6), .completed)
        XCTAssertEqual(PlayOutcome.of(listened: 3, duration: 0), .skipped)
    }
}
