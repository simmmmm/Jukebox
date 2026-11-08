// The mixes' rules one by one, on small hand-made libraries: what goes into
// On Repeat, Rediscover, Deep Cuts, Loved Tracks, New Arrivals, the decade
// and genre mixes; a thumbs down; the eight-track minimum; the day; the
// stations; and that the mixes do not depend on the library's order.

import Foundation
@testable import JukeboxKit
import XCTest

final class MixesRuleTests: XCTestCase {
    typealias T = MixesTracks

    /// `artists` artists of `perArtist` songs each, one album each, genres
    /// and years by artist.
    static func library(artists: Int, perArtist: Int, genres: (Int) -> [String] = { _ in ["Rock"] },
                        year: (Int) -> Int = { _ in 2000 }, added: (Int) -> Date? = { _ in nil }) -> [Track] {
        var tracks: [Track] = []
        for a in 0..<artists {
            for k in 0..<perArtist {
                tracks.append(T.track("a\(a)t\(k)", "Artist \(a)", album: "album-\(a)", genres: genres(a), year: year(a),
                                      added: added(a)))
            }
        }
        return tracks
    }

    static func events(_ track: Track, times: Int, daysAgo: (Int) -> Double, outcome: PlayOutcome = .completed) -> [PlayEvent] {
        (0..<times).map { PlayEvent(track: track, date: T.daysAgo(daysAgo($0)), listened: track.duration, outcome: outcome) }
    }

    static func history(_ events: [PlayEvent]) -> ListeningHistory {
        ListeningHistory(events: events.sorted { $0.date < $1.date })
    }

    func testNothingFromAnEmptyLibrary() {
        let generator = T.generator([])
        XCTAssertEqual(generator.mixes(), [])
        XCTAssertEqual(generator.suggestedStations(), [])
    }

    func testAMixOfFewerThanEightIsLeftOut() {
        // Seven favourites: no Loved Tracks; seven more make one.
        var tracks = Self.library(artists: 3, perArtist: 5)
        for i in 0..<7 { tracks[i * 2].isFavorite = true }
        XCTAssertFalse(T.generator(tracks).mixes().contains { $0.kind == .favorites })
        tracks[1].isFavorite = true
        let loved = T.generator(tracks).mixes().first { $0.kind == .favorites }
        XCTAssertEqual(loved?.tracks.count, 8)
        XCTAssertEqual(loved?.title, "Loved Tracks")
        XCTAssertEqual(loved?.stationSeed, .favorites)
    }

    func testOnRepeatIsWhatWasPlayedMostThisMonth() throws {
        let tracks = Self.library(artists: 4, perArtist: 10)
        // Twelve songs played this month, the first most: 14 plays, 13, …, 3.
        let played = (0..<12).map { tracks[($0 * 7) % 40] }
        var events: [PlayEvent] = []
        for (i, t) in played.enumerated() { events += Self.events(t, times: 14 - i, daysAgo: { Double(1 + $0) }) }
        // Played a lot, but two months ago.
        let old = tracks[39]
        events += Self.events(old, times: 10, daysAgo: { Double(60 + $0) })
        // Played only today (it is 10:00): it counts from tomorrow.
        let today = tracks[38]
        events += (0..<5).map { PlayEvent(track: today, date: T.now.addingTimeInterval(-Double($0 + 1) * 900),
                                          listened: 200, outcome: .completed) }
        let history = Self.history(events)

        let mix = try XCTUnwrap(T.generator(tracks, history: history).mixes().first { $0.kind == .onRepeat })
        XCTAssertEqual(mix.title, "On Repeat")
        XCTAssertEqual(Set(mix.tracks.map(\.id)), Set(played.map(\.id)))
        XCTAssertEqual(mix.tracks.first?.id, played[0].id, "the most played first")
        XCTAssertEqual(mix.stationSeed, .collection(id: mix.id, name: "On Repeat", trackIDs: mix.tracks.map(\.id)))

        let tomorrow = T.now.addingTimeInterval(86_400)
        let next = try XCTUnwrap(T.generator(tracks, history: history, now: tomorrow).mixes().first { $0.kind == .onRepeat })
        XCTAssertTrue(next.tracks.contains { $0.id == today.id })
        XCTAssertFalse(next.tracks.contains { $0.id == old.id })
    }

    func testOnRepeatFromJellyfinsLastPlayedToo() throws {
        // No history on this device: Jellyfin's counts of songs last played
        // this month stand in (another device, or before Jukebox).
        var tracks = Self.library(artists: 3, perArtist: 6)
        for i in 0..<10 {
            tracks[i].playCount = 12 - i
            tracks[i].lastPlayed = T.daysAgo(2)
        }
        tracks[17].playCount = 40
        tracks[17].lastPlayed = T.daysAgo(200)
        let mix = try XCTUnwrap(T.generator(tracks).mixes().first { $0.kind == .onRepeat })
        XCTAssertEqual(Set(mix.tracks.map(\.id)), Set(tracks.prefix(10).map(\.id)))
    }

    func testRediscoverIsWhatWasLovedAndNotHeardInTwoMonths() throws {
        var tracks = Self.library(artists: 3, perArtist: 12)
        let rediscover = Array(0..<10)
        for i in rediscover {
            tracks[i * 3].playCount = 6
            tracks[i * 3].lastPlayed = T.daysAgo(90)
        }
        // Played as much, last week.
        for i in [1, 4, 7, 10, 13] {
            tracks[i].playCount = 6
            tracks[i].lastPlayed = T.daysAgo(7)
        }
        // Played once, long ago: not "loved".
        for i in [2, 5, 8] {
            tracks[i].playCount = 1
            tracks[i].lastPlayed = T.daysAgo(120)
        }
        let mix = try XCTUnwrap(T.generator(tracks).mixes().first { $0.kind == .rediscover })
        XCTAssertEqual(Set(mix.tracks.map(\.id)), Set(rediscover.map { tracks[$0 * 3].id }))
    }

    func testDeepCutsAreTheUnplayedSongsOfTheArtistsLikedMost() throws {
        var tracks = Self.library(artists: 5, perArtist: 20)
        // Artists 0, 1 and 2 loved: half their songs played a lot, lately.
        for a in 0..<3 {
            for k in 0..<10 {
                tracks[a * 20 + k].playCount = 15
                tracks[a * 20 + k].lastPlayed = T.daysAgo(3)
            }
        }
        let mix = try XCTUnwrap(T.generator(tracks).mixes().first { $0.kind == .deepCuts })
        XCTAssertEqual(mix.title, "Deep Cuts")
        XCTAssertEqual(mix.stationSeed, .discovery)
        XCTAssertTrue(mix.tracks.allSatisfy { $0.playCount == 0 })
        XCTAssertTrue(mix.tracks.allSatisfy { ["Artist 0", "Artist 1", "Artist 2"].contains($0.albumArtist?.name ?? "") })
        XCTAssertEqual(mix.tracks.count, 30)
        XCTAssertEqual(MixesCheck.separationViolations(mix.tracks, snapshot: LibrarySnapshot(tracks: tracks), window: 2), 0)

        // One loved artist only: their page, not a mix.
        var one = Self.library(artists: 5, perArtist: 20)
        for k in 0..<10 {
            one[k].playCount = 15
            one[k].lastPlayed = T.daysAgo(3)
        }
        XCTAssertFalse(T.generator(one).mixes().contains { $0.kind == .deepCuts })
    }

    func testAThumbsDownLeavesEveryMixAtOnce() throws {
        var tracks = Self.library(artists: 4, perArtist: 10)
        for i in 0..<20 { tracks[i * 2].isFavorite = true }
        let disliked = tracks[0]
        // At 09:30 today.
        let history = ListeningHistory(events: [PlayEvent(track: disliked, date: T.now.addingTimeInterval(-1800),
                                                          listened: 20, outcome: .disliked)])
        let mixes = T.generator(tracks, history: history).mixes()
        XCTAssertTrue(mixes.contains { $0.kind == .favorites })
        for mix in mixes { XCTAssertFalse(mix.tracks.contains { $0.id == disliked.id }, mix.title) }
    }

    func testNewArrivalsAreTheAlbumsOfTheLastMonth() throws {
        // Six albums from more than a year ago, two from last week.
        let tracks = Self.library(artists: 8, perArtist: 10, added: { a in a < 6 ? T.daysAgo(400 + Double(a)) : T.daysAgo(Double(a)) })
        let mix = try XCTUnwrap(T.generator(tracks).mixes().first { $0.kind == .newArrivals })
        XCTAssertEqual(mix.title, "New Arrivals")
        XCTAssertEqual(Set(mix.tracks.compactMap(\.albumID)), ["album-6", "album-7"])
        XCTAssertEqual(mix.tracks.count, 20)
        XCTAssertEqual(MixesCheck.albumBackToBack(mix.tracks), 0)

        // Nothing this month: the newest albums there are, until there is a
        // mix of 40.
        let old = Self.library(artists: 8, perArtist: 10, added: { a in T.daysAgo(100 + Double(a) * 10) })
        let fallback = try XCTUnwrap(T.generator(old).mixes().first { $0.kind == .newArrivals })
        XCTAssertEqual(Set(fallback.tracks.compactMap(\.albumID)), ["album-0", "album-1", "album-2", "album-3"])
    }

    func testDecadeMixesAreTheDecadesPlayedMost() throws {
        // Three artists in each of the 1970s, 1990s and 2010s; the listener
        // plays the 1990s, a little the 2010s.
        var tracks = Self.library(artists: 9, perArtist: 8, year: { a in [1975, 1995, 2015][a / 3] })
        for i in tracks.indices {
            let year = tracks[i].year ?? 0
            if year == 1995 { tracks[i].playCount = 8; tracks[i].lastPlayed = T.daysAgo(5) }
            if year == 2015, i % 4 == 0 { tracks[i].playCount = 1; tracks[i].lastPlayed = T.daysAgo(20) }
        }
        let decades = T.generator(tracks).mixes().filter { $0.kind == .decade }
        XCTAssertEqual(decades.first?.title, "1990s Mix")
        XCTAssertEqual(decades.first?.stationSeed, .decade(1990))
        XCTAssertTrue(decades.first?.tracks.allSatisfy { $0.year == 1995 } ?? false)
        // Two always; a third only with a fifth of the first one's plays.
        XCTAssertEqual(decades.map(\.title), ["1990s Mix", "2010s Mix"])
    }

    func testGenreMixesLeaveOutAGenreThatIsTheSameSongs() throws {
        // Artists 0–5 are "Rock; Alternative", 6–8 "Rock", 9–11 "Jazz": every
        // alternative song is rock, and two thirds of rock alternative.
        let tracks = Self.library(artists: 12, perArtist: 8, genres: { a in a < 6 ? ["Rock; Alternative"] : a < 9 ? ["Rock"] : ["Jazz"] })
        let genres = T.generator(tracks).mixes().filter { $0.kind == .genre }
        XCTAssertEqual(Set(genres.map(\.title)), ["Rock Mix", "Jazz Mix"])
        let rock = try XCTUnwrap(genres.first { $0.title == "Rock Mix" })
        XCTAssertEqual(rock.stationSeed, .genre(key: "rock", name: "Rock"))
        XCTAssertEqual(rock.id, "genre-rock-2026-11-08")
        XCTAssertLessThanOrEqual(rock.tracks.count, 40)
    }

    func testAGenreOfOneArtistIsNotAMix() {
        let tracks = Self.library(artists: 4, perArtist: 20, genres: { a in a == 0 ? ["Americana"] : ["Folk"] })
        let titles = T.generator(tracks).mixes().filter { $0.kind == .genre }.map(\.title)
        XCTAssertEqual(titles, ["Folk Mix"])
    }

    func testTheSubtitleNamesTheLeadingArtists() {
        let tracks = [T.track("1", "Portishead", album: "a"), T.track("2", "Massive Attack", album: "b"),
                      T.track("3", "Portishead", album: "c"), T.track("4", "Tricky", album: "d"),
                      T.track("5", "Portishead", album: "e")]
        let model = T.generator(tracks).model
        XCTAssertEqual(model.artistLine([0, 1, 2, 3, 4]), "Portishead, Massive Attack and more")
        XCTAssertEqual(model.artistLine([0, 1]), "Portishead and Massive Attack")
        XCTAssertEqual(model.artistLine([0, 2]), "Portishead")
        XCTAssertEqual(model.artistLine([]), "")
        // The cluster's lead first, whatever the counts.
        XCTAssertEqual(model.artistLine([0, 1, 2, 3, 4], lead: [model.index.artistByKey["tricky"] ?? -1]), "Tricky, Portishead and more")
    }

    func testTheCoversAreFourAlbumsOfDifferentArtistsFirst() {
        var tracks: [Track] = []
        for k in 0..<4 { tracks.append(T.track("p\(k)", "Portishead", album: "portishead-\(k)")) }
        for (k, name) in ["Massive Attack", "Tricky", "Björk"].enumerated() { tracks.append(T.track("o\(k)", name, album: "other-\(k)")) }
        tracks.append(T.track("p4", "Portishead", album: "portishead-0"))
        let model = T.generator(tracks).model
        let covers = model.covers(Array(0..<tracks.count))
        XCTAssertEqual(covers.map(\.itemID), ["portishead-0", "other-0", "other-1", "other-2"])
        // Fewer artists than four: a second album of one.
        XCTAssertEqual(model.covers([0, 1, 7, 2]).map(\.itemID), ["portishead-0", "portishead-1", "portishead-2"])
    }

    func testTheOrderKeepsArtistsApartWherePossible() {
        // Twelve songs: six by A, three by B, three by C. Two between two by
        // one artist cannot hold for A (six in twelve), one between can.
        var tracks: [Track] = []
        for k in 0..<6 { tracks.append(T.track("a\(k)", "A", album: "a\(k)")) }
        for k in 0..<3 { tracks.append(T.track("b\(k)", "B", album: "b\(k)")) }
        for k in 0..<3 { tracks.append(T.track("c\(k)", "C", album: "c\(k)")) }
        let model = T.generator(tracks).model
        let ordered = model.order([Array(0..<12)], separation: 1).map { tracks[$0] }
        XCTAssertEqual(ordered.count, 12)
        XCTAssertEqual(ordered.first?.id, "a0", "the lane's best first")
        XCTAssertEqual(MixesCheck.separationViolations(ordered, snapshot: model.snapshot, window: 1), 0)
        // Two lanes, 8 and 4: the second's share is spread, not at the end.
        let lanes = model.order([Array(0..<8), Array(8..<12)], separation: 1)
        let second = lanes.enumerated().filter { $0.element >= 8 }.map(\.offset)
        XCTAssertLessThan(second.first ?? 99, 4)
        XCTAssertGreaterThan(second.last ?? 0, 7)
    }

    func testTheStationsSuggested() {
        // Two kinds of music; the six liked most are all of the first and
        // close (Last.fm says so), two of the second next.
        var tracks = Self.library(artists: 10, perArtist: 6, genres: { a in a < 7 ? ["Shoegaze"] : ["Jazz"] })
        for i in tracks.indices {
            let a = i / 6
            tracks[i].playCount = a < 7 ? 20 - a : (a < 9 ? 8 : 0)
            tracks[i].lastPlayed = T.daysAgo(4)
        }
        let snapshot = LibrarySnapshot(tracks: tracks)
        var graph = SimilarityGraph.fromLibrary(snapshot)
        for a in 0..<7 { for b in 0..<7 where a != b { graph.addArtistEdge(NameKey.artist("Artist \(a)"), NameKey.artist("Artist \(b)"), weight: 0.8) } }
        let generator = MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: ListeningHistory(), now: T.now),
                                     history: ListeningHistory(), graph: graph, now: T.now, calendar: MixesCheck.calendar)
        let stations = generator.suggestedStations()
        XCTAssertEqual(stations.prefix(2).map(\.title), ["Your Station", "Discovery"])
        XCTAssertFalse(stations.contains { $0.seed == .favorites }, "no favourites, no Loved")
        let artists = stations.compactMap { station -> String? in
            if case let .artist(_, name, _) = station.seed { return name }
            return nil
        }
        XCTAssertEqual(artists.count, 6)
        XCTAssertEqual(artists.first, "Artist 0")
        XCTAssertTrue(artists.contains("Artist 7") && artists.contains("Artist 8"), "\(artists)")
        XCTAssertEqual(stations.first { if case .artist = $0.seed { true } else { false } }?.title, "Artist 0 Radio")
        let genres = stations.compactMap { station -> String? in
            if case let .genre(_, name) = station.seed { return name }
            return nil
        }
        XCTAssertEqual(genres, ["Shoegaze", "Jazz"])
        XCTAssertTrue(stations.contains { $0.seed == .decade(2000) })

        tracks[0].isFavorite = true
        XCTAssertEqual(T.generator(tracks).suggestedStations().prefix(3).map(\.seed), [.personal, .discovery, .favorites])
    }

    func testTheMixesDoNotDependOnTheLibrarysOrder() throws {
        let library = MixesLibrary()
        let mixes = library.generator().mixes()
        // The same tracks in another order.
        var rng = SplitMix64(seed: 99)
        var shuffled = library.tracks
        for i in stride(from: shuffled.count - 1, to: 0, by: -1) {
            shuffled.swapAt(i, Int(rng.next() % UInt64(i + 1)))
        }
        let snapshot = LibrarySnapshot(tracks: shuffled)
        let again = MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: library.history, now: library.now),
                                 history: library.history, graph: .fromLibrary(snapshot), now: library.now,
                                 calendar: MixesCheck.calendar).mixes()
        XCTAssertEqual(mixes.map(\.id), again.map(\.id))
        for (a, b) in zip(mixes, again) {
            XCTAssertEqual(a.tracks.map(\.id), b.tracks.map(\.id), a.title)
            XCTAssertEqual(a.subtitle, b.subtitle)
            XCTAssertEqual(a.artwork, b.artwork)
        }

        // An album added today, by an artist the listener does not know:
        // the daily mixes stay as they were.
        var added = library.tracks
        for k in 0..<10 {
            added.append(T.track("new\(k)", "Newcomer", album: "new-album", genres: ["Classical"], year: 2026, added: library.now))
        }
        let withAlbum = LibrarySnapshot(tracks: added)
        let after = MixGenerator(snapshot: withAlbum, taste: TasteProfile(snapshot: withAlbum, history: library.history, now: library.now),
                                 history: library.history, graph: .fromLibrary(withAlbum), now: library.now,
                                 calendar: MixesCheck.calendar).mixes()
        for mix in mixes where mix.kind == .daily {
            XCTAssertEqual(after.first { $0.id == mix.id }?.tracks.map(\.id), mix.tracks.map(\.id), mix.title)
        }
        XCTAssertTrue(after.first { $0.kind == .newArrivals }?.tracks.contains { $0.albumID == "new-album" } ?? false)
    }

    func testATasteFromAnOlderLibraryStillWorks() {
        // The app may hand over a taste made before the library last changed.
        let library = MixesLibrary()
        let older = LibrarySnapshot(tracks: Array(library.tracks.dropLast(100)))
        let taste = TasteProfile(snapshot: older, history: library.history, now: library.now)
        let generator = MixGenerator(snapshot: library.snapshot, taste: taste, history: library.history,
                                     graph: .fromLibrary(library.snapshot), now: library.now, calendar: MixesCheck.calendar)
        XCTAssertEqual(generator.mixes().map(\.id), library.generator().mixes().map(\.id))
    }

    func testTheDayIsTheCalendarsDay() {
        // 23:30 in Amsterdam is 22:30 UTC: the Amsterdam calendar's day.
        var amsterdam = Calendar(identifier: .gregorian)
        amsterdam.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? amsterdam.timeZone
        let late = MixesCheck.date("2026-11-08T22:30:00Z")
        XCTAssertEqual(MixModel.dayKey(late, calendar: amsterdam), "2026-11-08")
        XCTAssertEqual(MixModel.dayKey(MixesCheck.date("2026-11-08T23:30:00Z"), calendar: amsterdam), "2026-11-09")
        XCTAssertEqual(MixModel.dayKey(late, calendar: MixesCheck.calendar), "2026-11-08")
    }
}
