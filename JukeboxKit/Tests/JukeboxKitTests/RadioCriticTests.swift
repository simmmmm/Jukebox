// The radio, tried the way a demanding listener would try to break it
// (docs/RADIO.md, "What it does when …"). Each test builds the awkward case,
// measures, prints a line starting RADIO-CRITIC, and holds the number the
// fix reached. `dev/kit-test.sh --filter RadioCritic` shows them.

import Foundation
@testable import JukeboxKit
import XCTest

/// Small awkward libraries and what is counted on them.
enum RadioCriticFixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func track(_ id: String, artist: String, album: String, number: Int, genres: [String] = ["Rock"],
                      year: Int? = 2000, performers: [String]? = nil, favorite: Bool = false, plays: Int = 0,
                      duration: TimeInterval = 200) -> Track {
        let albumArtist = ArtistRef(id: "id-" + NameKey.artist(artist), name: artist)
        let names = performers ?? [artist]
        return Track(id: id, name: "Song \(id)", albumID: "al-\(album)", albumName: album,
                     artists: names.map { ArtistRef(id: $0 == artist ? albumArtist.id : nil, name: $0) },
                     albumArtist: albumArtist, genres: genres, year: year, trackNumber: number, discNumber: 1,
                     duration: duration, albumImageTag: "tag-\(album)", isFavorite: favorite, playCount: plays)
    }

    /// `artists` artists of `albums` albums of `perAlbum` tracks, in library
    /// order (artist, album, track number), as Jellyfin lists them. Their
    /// years are shuffled against that order, so that a station near in
    /// era is not also near in the library's order.
    static func library(artists: Int, albums: Int, perAlbum: Int, genres: (Int) -> [String] = { _ in ["Rock"] },
                        year: (Int) -> Int? = { 1990 + ($0 * 7) % 20 }) -> [Track] {
        var tracks: [Track] = []
        for a in 0..<artists {
            for b in 0..<albums {
                for t in 1...perAlbum {
                    tracks.append(track("a\(a)-b\(b)-t\(t)", artist: "Artist \(a)", album: "Album \(a)-\(b)", number: t,
                                        genres: genres(a), year: year(a).map { $0 + b }))
                }
            }
        }
        return tracks
    }

    struct Setup {
        let snapshot: LibrarySnapshot
        let taste: TasteProfile
        let graph: SimilarityGraph

        init(_ tracks: [Track], history: ListeningHistory = ListeningHistory(), now: Date = RadioCriticFixtures.now) {
            snapshot = LibrarySnapshot(tracks: tracks)
            taste = TasteProfile(snapshot: snapshot, history: history, now: now)
            graph = .fromLibrary(snapshot)
        }

        func session(_ seed: StationSeed, adventurousness: Double = 0.35, randomSeed: UInt64 = 1,
                     recentlyPlayed: Set<ItemID> = []) -> RadioSession {
            RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot, taste: taste, graph: graph,
                         settings: RadioSettings(adventurousness: adventurousness), recentlyPlayed: recentlyPlayed,
                         randomSeed: randomSeed)
        }

        func artistSeed(_ name: String) -> StationSeed {
            .artist(key: NameKey.artist(name), name: name, id: nil)
        }
    }

    /// The shortest distance between two plays of one track (`Int.max` when
    /// nothing repeats).
    static func shortestRepeat(_ ids: [ItemID]) -> Int {
        var last: [ItemID: Int] = [:]
        var shortest = Int.max
        for (k, id) in ids.enumerated() {
            if let before = last[id] { shortest = min(shortest, k - before) }
            last[id] = k
        }
        return shortest
    }

    /// The least music, in seconds, between two plays of one track
    /// (infinity when nothing repeats).
    static func leastMusicBetweenPlays(_ picks: [RadioPick]) -> Double {
        var end: [Double] = []
        var total = 0.0
        for pick in picks {
            total += pick.track.duration > 0 ? pick.track.duration : 240
            end.append(total)
        }
        var last: [ItemID: Int] = [:]
        var least = Double.infinity
        for (k, pick) in picks.enumerated() {
            if let before = last[pick.track.id] { least = min(least, end[k - 1] - end[before]) }
            last[pick.track.id] = k
        }
        return least
    }

    /// Of every two picks from one album, the share that came in the album's
    /// own order: 0.5 when the radio does not follow it, 1 when it walks
    /// through albums track by track.
    static func albumOrderShare(_ picks: [RadioPick]) -> Double {
        var byAlbum: [ItemID: [Int]] = [:]
        for pick in picks {
            guard let album = pick.track.albumID, let number = pick.track.trackNumber else { continue }
            byAlbum[album, default: []].append(number)
        }
        var inOrder = 0, pairs = 0
        for numbers in byAlbum.values {
            for i in numbers.indices {
                for j in (i + 1)..<numbers.count {
                    pairs += 1
                    if numbers[i] < numbers[j] { inOrder += 1 }
                }
            }
        }
        return pairs > 0 ? Double(inOrder) / Double(pairs) : 0.5
    }

    static func line(_ text: String) {
        print("RADIO-CRITIC " + text)
    }
}

final class RadioCriticTests: XCTestCase {
    typealias F = RadioCriticFixtures

    // MARK: Tiny libraries

    /// Twelve tracks, four artists: the station plays on for hours. Every
    /// song once before any again; then a song waits as long as it can, and
    /// four artists are enough to keep three songs between two by one.
    func testTwelveTracks() {
        let tracks = F.library(artists: 4, albums: 1, perAlbum: 3)
        let setup = F.Setup(tracks)
        var shortest = Int.max, violations = 0, firstRound = 0, albums = 0, firstCycle = 0
        for seed in 0..<6 {
            var session = setup.session(seed % 2 == 0 ? .personal : setup.artistSeed("Artist 1"), randomSeed: UInt64(seed))
            let picks = session.next(120)
            XCTAssertEqual(picks.count, 120)
            let ids = picks.map(\.track.id)
            firstCycle += Set(ids.prefix(12)).count == 12 ? 1 : 0
            shortest = min(shortest, F.shortestRepeat(ids))
            let all = RadioMetrics.separationViolations(picks, snapshot: setup.snapshot, separation: 3)
            let first = RadioMetrics.separationViolations(Array(picks.prefix(12)), snapshot: setup.snapshot, separation: 3)
            firstRound += first
            violations += all - first
            albums += RadioMetrics.albumBackToBack(picks)
        }
        F.line("12 tracks, 4 artists, 6 stations x 120 picks: every song before a repeat \(firstCycle)/6; shortest gap between two plays of a song \(shortest); separation violations \(firstRound) in the first round of 12, \(violations) after; album back to back \(albums)")
        XCTAssertEqual(firstCycle, 6)
        XCTAssertGreaterThanOrEqual(shortest, 8, "a song waits for most of the library")
        // In the first round every song once comes before separation: the
        // last few new songs may be by two artists.
        XCTAssertLessThanOrEqual(firstRound, 12)
        XCTAssertEqual(violations, 0, "four artists keep three songs apart after the first round")
    }

    /// One artist, three albums: separation cannot hold, the album rule can.
    func testOneArtistOnly() {
        let tracks = F.library(artists: 1, albums: 3, perAlbum: 10)
        let setup = F.Setup(tracks)
        var albums = 0, firstRound = 0, shortest = Int.max, firstCycle = 0, order = 0.0
        for seed in 0..<4 {
            var session = setup.session(seed % 2 == 0 ? setup.artistSeed("Artist 0") : .personal, randomSeed: UInt64(seed))
            let picks = session.next(90)
            XCTAssertEqual(picks.count, 90)
            let ids = picks.map(\.track.id)
            firstCycle += Set(ids.prefix(30)).count == 30 ? 1 : 0
            shortest = min(shortest, F.shortestRepeat(ids))
            let first = RadioMetrics.albumBackToBack(Array(picks.prefix(30)))
            firstRound += first
            albums += RadioMetrics.albumBackToBack(picks) - first
            order += F.albumOrderShare(Array(picks.prefix(30)))
        }
        F.line(String(format: "one artist, 3 albums of 10, 4 stations x 90 picks: every song before a repeat %d/4; shortest gap %d; album back to back %d in the first round of 30, %d after; album order kept %.2f (0.5 is none)",
                      firstCycle, shortest, firstRound, albums, order / 4))
        XCTAssertEqual(firstCycle, 4)
        XCTAssertLessThanOrEqual(firstRound, 4, "the last new songs of the first round may be of one album")
        XCTAssertEqual(albums, 0, "three albums are enough never to play one twice in a row")
        XCTAssertGreaterThanOrEqual(shortest, 20)
    }

    // MARK: Flat libraries

    /// Every track the same genre, nobody heard: the station still varies
    /// its artists and follows neither the library's nor an album's order.
    func testEveryTrackTheSameGenre() {
        // One year too: nothing but the library's order could tell the
        // artists apart.
        let tracks = F.library(artists: 20, albums: 2, perAlbum: 10, year: { _ in 2000 })
        let setup = F.Setup(tracks)
        var distinct = 0.0, order = 0.0, firstHalf = 0.0, skippedBack = 0.0, control = 0.0
        let runs = 6
        for run in 0..<runs {
            var session = setup.session(setup.artistSeed("Artist 3"), randomSeed: UInt64(run))
            var twin = setup.session(setup.artistSeed("Artist 3"), randomSeed: UInt64(run))
            let picks = session.next(60)
            _ = twin.next(60)
            distinct += Double(RadioMetrics.distinctArtists(picks, snapshot: setup.snapshot))
            order += F.albumOrderShare(picks)
            firstHalf += Double(picks.filter { (setup.snapshot.position(of: $0.track.id) ?? 0) < tracks.count / 2 }.count) / 60
            // A skip of an artist on a library where genre says nothing.
            let victim = picks[1]
            let artist = setup.snapshot.primaryArtistKey(of: victim.track)
            session.record(.skipped(victim.track.id, after: 5))
            twin.record(.finished(victim.track.id))
            skippedBack += Double(session.next(20).filter { setup.snapshot.primaryArtistKey(of: $0.track) == artist }.count)
            control += Double(twin.next(20).filter { setup.snapshot.primaryArtistKey(of: $0.track) == artist }.count)
        }
        let r = Double(runs)
        F.line(String(format: "20 artists all Rock, nobody heard, 6 x 60 picks: distinct artists %.1f; album order kept %.2f; picks from the first half of the library %.2f; the skipped artist in the next 20 %.2f (without the skip %.2f)",
                      distinct / r, order / r, firstHalf / r, skippedBack / r, control / r))
        XCTAssertGreaterThanOrEqual(distinct / r, 10)
        XCTAssertLessThan(order / r, 0.7, "an album's songs not in track order")
        XCTAssertLessThan(skippedBack, control)
    }

    /// No genre and no year anywhere: an artist station plays the artist and
    /// then the library at random, not the library from the top.
    func testNoGenreNoYear() {
        let tracks = F.library(artists: 20, albums: 2, perAlbum: 8, genres: { _ in [] }, year: { _ in nil })
        let setup = F.Setup(tracks)
        var firstHalf = 0.0, order = 0.0, seedShare = 0.0, distinct = 0.0
        let runs = 6
        for run in 0..<runs {
            var session = setup.session(run % 2 == 0 ? setup.artistSeed("Artist 12") : .personal, randomSeed: UInt64(run))
            let picks = session.next(40)
            XCTAssertEqual(picks.count, 40)
            XCTAssertTrue(picks.allSatisfy { $0.score.isFinite && $0.score > 0 })
            firstHalf += Double(picks.filter { (setup.snapshot.position(of: $0.track.id) ?? 0) < tracks.count / 2 }.count) / 40
            order += F.albumOrderShare(picks)
            if run % 2 == 0 { seedShare += Double(picks.filter { $0.track.albumArtist?.name == "Artist 12" }.count) / 40 }
            distinct += Double(RadioMetrics.distinctArtists(picks, snapshot: setup.snapshot))
            XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: setup.snapshot, separation: 3), 0)
        }
        let r = Double(runs)
        F.line(String(format: "no genre, no year, 20 artists, 6 x 40 picks: from the first half of the library %.2f (0.5 is fair); album order kept %.2f; Artist 12 on their own station %.2f; distinct artists %.1f",
                      firstHalf / r, order / r, seedShare / (r / 2), distinct / r))
        XCTAssertLessThan(abs(firstHalf / r - 0.5), 0.15, "the library's order does not decide")
        XCTAssertLessThan(order / r, 0.7)
    }

    /// A new listener's Artist Radio opens with one of the artist's songs —
    /// not always one of the first three on the first album.
    func testFirstTrackOfANewListenersStation() {
        let tracks = RadioRealLibraryFixture.tracks
        let setup = F.Setup(tracks)
        var firsts = Set<ItemID>()
        var genreFirsts = Set<ItemID>()
        for seed in 0..<20 {
            var session = setup.session(setup.artistSeed("The Lanterns"), randomSeed: UInt64(seed))
            firsts.insert(session.next(1)[0].track.id)
            var jazz = setup.session(.genre(key: "jazz", name: "Jazz"), randomSeed: UInt64(seed))
            genreFirsts.insert(jazz.next(1)[0].track.id)
        }
        let own = setup.snapshot.ownTracks(artistKey: NameKey.artist("The Lanterns")).count
        F.line("test server, nothing heard, 20 random seeds: The Lanterns Radio opens with \(firsts.count) different songs of \(own); Jazz Radio with \(genreFirsts.count)")
        XCTAssertGreaterThanOrEqual(firsts.count, 8)
        XCTAssertGreaterThanOrEqual(genreFirsts.count, 8)
    }

    /// On the test server, nothing heard: Your Station and Jazz Radio do not
    /// walk through albums in track order.
    func testNewListenerDoesNotFollowAlbumOrder() {
        let setup = F.Setup(RadioRealLibraryFixture.tracks)
        var order = 0.0, runs = 0.0
        for seed in 0..<6 {
            for station in [StationSeed.personal, .genre(key: "jazz", name: "Jazz"), setup.artistSeed("Velvet Static")] {
                var session = setup.session(station, randomSeed: UInt64(seed))
                order += F.albumOrderShare(session.next(40))
                runs += 1
            }
        }
        F.line(String(format: "test server, nothing heard, 18 stations x 40: album order kept %.2f (0.5 is none)", order / runs))
        XCTAssertLessThan(order / runs, 0.65)
    }

    // MARK: Sparse artists

    /// An artist with one song: their station starts with it and then plays
    /// their genre.
    func testArtistWithOneTrack() {
        var tracks = F.library(artists: 12, albums: 2, perAlbum: 8, genres: { $0 < 6 ? ["Jazz", "Bebop"] : ["Metal"] })
        tracks.append(F.track("solo", artist: "Lone Player", album: "Only", number: 1, genres: ["Jazz", "Bebop"], year: 1992))
        let setup = F.Setup(tracks)
        var jazz = 0.0, again = 0
        for seed in 0..<5 {
            var session = setup.session(setup.artistSeed("Lone Player"), randomSeed: UInt64(seed))
            let picks = session.next(30)
            XCTAssertEqual(picks.first?.track.id, "solo")
            again += picks.dropFirst().filter { $0.track.id == "solo" }.count
            jazz += Double(picks.filter { $0.track.genres.contains("Jazz") }.count) / 30
        }
        F.line(String(format: "an artist with one song: their station starts with it 5/5, plays it again %d times in 30, jazz %.2f", again, jazz / 5))
        XCTAssertEqual(again, 0)
        XCTAssertGreaterThan(jazz / 5, 0.9)
    }

    // MARK: Listening hard

    /// Fifty skips in a row: the station keeps going, never brings a skipped
    /// song back, never repeats, and moves on to other artists.
    func testFiftySkipsInARow() {
        let w = RadioEvaluationTests.shared
        var repeats = 0, skippedBack = 0, zero = 0, distinct = 0.0, sameCluster = 0.0, afterCluster = 0.0
        let runs = 4
        for run in 0..<runs {
            let seedArtist = w.library.artists[run * 3]
            var session = w.session(w.artistSeed(seedArtist), randomSeed: UInt64(300 + run))
            var skipped: [ItemID] = []
            for _ in 0..<50 {
                guard let pick = session.next(1).first else { break }
                if !(pick.score.isFinite && pick.score > 0) { zero += 1 }
                session.record(.skipped(pick.track.id, after: 4))
                skipped.append(pick.track.id)
            }
            repeats += RadioMetrics.repeats(skipped.map { RadioPick(track: w.snapshot.track(id: $0)!, reason: .seed, score: 1) })
            distinct += Double(Set(skipped.compactMap { w.snapshot.track(id: $0).flatMap(w.snapshot.primaryArtistKey) }).count)
            sameCluster += Double(skipped.suffix(20).filter {
                w.clusterOf(RadioPick(track: w.snapshot.track(id: $0)!, reason: .seed, score: 1)) == seedArtist.cluster
            }.count) / 20
            let after = session.next(30)
            XCTAssertEqual(after.count, 30)
            skippedBack += after.filter { skipped.contains($0.track.id) }.count
            zero += after.filter { !($0.score.isFinite && $0.score > 0) }.count
            afterCluster += Double(after.filter { w.clusterOf($0) == seedArtist.cluster }.count) / 30
        }
        let r = Double(runs)
        F.line(String(format: "50 skips in a row, 4 artist stations: repeats %d; skipped songs back in the next 30 %d; zero scores %d; distinct artists in the 50 %.1f; seed's cluster in skips 31-50 %.2f, in the next 30 %.2f",
                      repeats, skippedBack, zero, distinct / r, sameCluster / r, afterCluster / r))
        XCTAssertEqual(repeats, 0)
        XCTAssertEqual(skippedBack, 0)
        XCTAssertEqual(zero, 0, "a score that underflows to 0 is a station that has lost its order")
    }

    /// Fifty thumbs down in a row: never one of them again, never a repeat,
    /// and the station still plays.
    func testFiftyThumbsDownInARow() {
        let w = RadioEvaluationTests.shared
        var back = 0, repeats = 0, short = 0, artists = 0.0
        for run in 0..<3 {
            var session = w.session(w.artistSeed(w.library.artists[run * 5]), randomSeed: UInt64(800 + run))
            var down: [ItemID] = []
            for _ in 0..<50 {
                guard let pick = session.next(1).first else { break }
                session.record(.disliked(pick.track.id))
                down.append(pick.track.id)
            }
            let after = session.next(40)
            short += 40 - after.count
            back += after.filter { down.contains($0.track.id) }.count
            repeats += RadioMetrics.repeats(after) + down.count - Set(down).count
            artists += Double(Set(down.compactMap { w.snapshot.track(id: $0).flatMap(w.snapshot.primaryArtistKey) }).count)
        }
        F.line(String(format: "50 thumbs down in a row, 3 artist stations: thumbed-down songs back in the next 40 %d; repeats %d; fewer than asked %d; distinct artists among the 50 %.1f",
                      back, repeats, short, artists / 3))
        XCTAssertEqual(back, 0)
        XCTAssertEqual(repeats, 0)
        XCTAssertEqual(short, 0)
    }

    /// A thumbs down on the seed artist's own song, on their own station: the
    /// song is gone and the artist plays less, but it is still their station
    /// — neither the artist nor everyone who sounds like them disappears.
    func testDislikeOfTheSeedArtistOnTheirStation() {
        let w = RadioEvaluationTests.shared
        var seedBefore = 0.0, seedAfter = 0.0, nearBefore = 0.0, nearAfter = 0.0, clusterBefore = 0.0, clusterAfter = 0.0
        var runs = 0.0
        for seedArtist in w.library.artists.prefix(16) {
            for run in 0..<2 {
                var session = w.session(w.artistSeed(seedArtist), randomSeed: UInt64(40 + run))
                var control = w.session(w.artistSeed(seedArtist), randomSeed: UInt64(40 + run))
                let first = session.next(1)[0]
                _ = control.next(1)
                guard w.snapshot.primaryArtistKey(of: first.track) == seedArtist.key else { continue }
                session.record(.disliked(first.track.id))
                control.record(.finished(first.track.id))
                let next = session.next(30), baseline = control.next(30)
                XCTAssertFalse(next.contains { $0.track.id == first.track.id })
                let isSeed = { (p: RadioPick) in w.snapshot.primaryArtistKey(of: p.track) == seedArtist.key }
                let isNear = { (p: RadioPick) in
                    w.snapshot.artistKeys(of: p.track).contains { w.graph.weight(seedArtist.key, $0) >= 0.3 }
                }
                seedBefore += Double(baseline.filter(isSeed).count)
                seedAfter += Double(next.filter(isSeed).count)
                nearBefore += Double(baseline.filter(isNear).count) / 30
                nearAfter += Double(next.filter(isNear).count) / 30
                clusterBefore += Double(baseline.filter { w.clusterOf($0) == seedArtist.cluster }.count) / 30
                clusterAfter += Double(next.filter { w.clusterOf($0) == seedArtist.cluster }.count) / 30
                runs += 1
            }
        }
        F.line(String(format: "thumbs down on the seed artist's song on their station (%d stations), next 30: the seed artist %.2f → %.2f songs; their close neighbours (edge >= 0.3) %.2f → %.2f; in cluster %.2f → %.2f",
                      Int(runs), seedBefore / runs, seedAfter / runs, nearBefore / runs, nearAfter / runs, clusterBefore / runs, clusterAfter / runs))
        XCTAssertGreaterThan(runs, 10)
        XCTAssertLessThan(seedAfter, seedBefore, "less of the artist")
        XCTAssertGreaterThan(seedAfter / runs, 1, "but still their station")
        XCTAssertGreaterThan(nearAfter, nearBefore * 0.8, "who sounds like them stays")
    }

    /// The dial turned back and forth while the station plays: the rules
    /// hold, and each turn acts on the next picks.
    func testDialFlippedMidSession() {
        let w = RadioEvaluationTests.shared
        var session = w.session(w.artistSeed(w.library.artists[2]), adventurousness: 0, randomSeed: 61)
        var all: [RadioPick] = []
        var unheardCalm = 0, unheardBold = 0, calm = 0, bold = 0
        for round in 0..<40 {
            session.settings.adventurousness = round % 2 == 0 ? 0 : 1
            let picks = session.next(5)
            XCTAssertEqual(picks.count, 5)
            all += picks
            if round % 2 == 0 {
                unheardCalm += picks.filter(w.unheard).count
                calm += 5
            } else {
                unheardBold += picks.filter(w.unheard).count
                bold += 5
            }
        }
        let violations = RadioMetrics.separationViolations(all, snapshot: w.snapshot, separation: 3)
        F.line(String(format: "the dial flipped 0 ↔ 1 every 5 picks, 200 picks: unheard %.2f at 0, %.2f at 1; repeats %d; separation violations %d; album back to back %d",
                      Double(unheardCalm) / Double(calm), Double(unheardBold) / Double(bold), RadioMetrics.repeats(all), violations,
                      RadioMetrics.albumBackToBack(all)))
        XCTAssertGreaterThanOrEqual(F.leastMusicBetweenPlays(all), 12 * 3600)
        XCTAssertEqual(violations, 0)
        XCTAssertGreaterThan(unheardBold, unheardCalm)
    }

    /// A thumbs down given yesterday (in the history) is still a thumbs down
    /// today, on any station but the song's own.
    func testYesterdaysThumbsDown() {
        let w = RadioEvaluationTests.shared
        let seedArtist = w.library.artists[0]
        let own = w.snapshot.ownTracks(artistKey: seedArtist.key)
        var history = w.library.history
        let hated = Array(own.prefix(4))
        for t in hated {
            history.append(PlayEvent(track: t, date: w.library.now.addingTimeInterval(-86_400), listened: 20, outcome: .disliked))
        }
        let taste = TasteProfile(snapshot: w.snapshot, history: history, now: w.library.now)
        var back = 0
        for seed in 0..<10 {
            var session = RadioSession(station: Station(seed: w.artistSeed(seedArtist), snapshot: w.snapshot), snapshot: w.snapshot,
                                       taste: taste, graph: w.graph, randomSeed: UInt64(seed))
            back += session.next(60).filter { pick in hated.contains { $0.id == pick.track.id } }.count
        }
        F.line("4 songs thumbed down yesterday, their artist's station 10 x 60 picks: played \(back) times")
        XCTAssertEqual(back, 0)
        // The song's own station still starts with it: the listener chose it.
        var songStation = RadioSession(station: Station(seed: .track(hated[0].id), snapshot: w.snapshot), snapshot: w.snapshot,
                                       taste: taste, graph: w.graph, randomSeed: 1)
        XCTAssertEqual(songStation.next(1).first?.track.id, hated[0].id)
    }

    // MARK: Long sessions

    /// A thousand picks (about three days of music): how far from the seed,
    /// how many artists, and none of them taking over.
    func testAThousandPicks() {
        let w = RadioEvaluationTests.shared
        var windows = [Double](repeating: 0, count: 10)
        var distinct = [Double](repeating: 0, count: 10)
        var topShare = [Double](repeating: 0, count: 10)
        var repeatShare = [Double](repeating: 0, count: 10)
        var leastGap = Double.infinity
        var violations = 0, count = 0
        let seeds = [w.library.artists[0], w.library.artists[2], w.library.artists[9]]
        for (k, seedArtist) in seeds.enumerated() {
            var session = w.session(w.artistSeed(seedArtist), randomSeed: UInt64(700 + k))
            var picks: [RadioPick] = []
            while picks.count < 1000 {
                let batch = session.next(5)
                guard !batch.isEmpty else { break }
                for pick in batch { session.record(.finished(pick.track.id)) }
                picks += batch
            }
            count = picks.count
            leastGap = min(leastGap, RadioCriticFixtures.leastMusicBetweenPlays(picks))
            var seen = Set<ItemID>()
            for (k, pick) in picks.enumerated() where !seen.insert(pick.track.id).inserted {
                repeatShare[k / 100] += 0.01
            }
            violations += RadioMetrics.separationViolations(picks, snapshot: w.snapshot, separation: 3)
            for window in 0..<10 {
                let part = Array(picks[(window * 100)..<min(picks.count, (window + 1) * 100)])
                windows[window] += Double(part.filter { w.clusterOf($0) == seedArtist.cluster }.count) / Double(part.count)
                let fifty = Array(part.prefix(50))
                distinct[window] += Double(RadioMetrics.distinctArtists(fifty, snapshot: w.snapshot))
                var counts: [String: Int] = [:]
                for p in fifty { if let a = w.snapshot.primaryArtistKey(of: p.track) { counts[a, default: 0] += 1 } }
                topShare[window] += Double(counts.values.max() ?? 0) / Double(fifty.count)
            }
        }
        let s = Double(seeds.count)
        F.line("1 000 picks heard to the end, 3 artist stations on 1 819 tracks; by hundreds:")
        F.line("  in the seed's cluster: " + windows.map { String(format: "%.2f", $0 / s) }.joined(separator: " "))
        F.line("  distinct artists in 50: " + distinct.map { String(format: "%.1f", $0 / s) }.joined(separator: " "))
        F.line("  the most-played artist's share of 50: " + topShare.map { String(format: "%.2f", $0 / s) }.joined(separator: " "))
        F.line("  repeats in each hundred: " + repeatShare.map { String(format: "%.2f", $0 / s) }.joined(separator: " "))
        F.line(String(format: "  picks %d, separation violations %d, least music between two plays of a song %.1f h", count, violations, leastGap / 3600))
        XCTAssertEqual(count, 1000)
        XCTAssertEqual(violations, 0)
        XCTAssertGreaterThanOrEqual(leastGap, 12 * 3600, "noRepeatHours of music between two plays")
        for window in 0..<10 { XCTAssertGreaterThan(windows[window] / s, 0.55, "still near the seed in hundred \(window + 1)") }
        XCTAssertLessThan(repeatShare.reduce(0, +) / s / 10, 0.6)
    }

    // MARK: Names

    /// Diacritics, slashes, "The The", guests joined with ";": one artist is
    /// one artist, two are two.
    func testNames() {
        let tracks = [
            F.track("b1", artist: "Beyoncé", album: "Lemonade", number: 1, genres: ["R&B"]),
            F.track("b2", artist: "Beyonce", album: "4", number: 1, genres: ["R&B"]),
            F.track("b3", artist: "BEYONCÉ", album: "Renaissance", number: 1, genres: ["R&B"]),
            F.track("s1", artist: "Sigur Rós", album: "Takk", number: 1, genres: ["Post-Rock"]),
            F.track("s2", artist: "Sigur Ros", album: "( )", number: 1, genres: ["Post-Rock"]),
            F.track("ac1", artist: "AC/DC", album: "Back in Black", number: 1, genres: ["Hard Rock"]),
            F.track("ac2", artist: "AC/DC", album: "Highway to Hell", number: 1, genres: ["Hard Rock"]),
            F.track("tt1", artist: "The The", album: "Soul Mining", number: 1, genres: ["New Wave"]),
            F.track("tt2", artist: "The The", album: "Infected", number: 1, genres: ["New Wave"]),
            F.track("duet", artist: "Björk", album: "Vespertine", number: 1, genres: ["Electronic"], performers: ["Björk; Thom Yorke"]),
            F.track("bj2", artist: "Björk", album: "Homogenic", number: 1, genres: ["Electronic"]),
            F.track("ty", artist: "Thom Yorke", album: "The Eraser", number: 1, genres: ["Electronic"]),
            F.track("sg1", artist: "Simon & Garfunkel", album: "Bookends", number: 1, genres: ["Folk"]),
            F.track("sg2", artist: "Simon and Garfunkel", album: "Bridge", number: 1, genres: ["Folk"]),
        ]
        let setup = F.Setup(tracks)
        let s = setup.snapshot
        XCTAssertEqual(Set(s.tracks(artistKey: NameKey.artist("Beyonce")).map(\.id)), ["b1", "b2", "b3"])
        XCTAssertEqual(Set(s.tracks(artistKey: NameKey.artist("Sigur Rós")).map(\.id)), ["s1", "s2"])
        XCTAssertEqual(s.artistKeys(of: tracks[5]), ["acdc"], "AC/DC is one artist")
        XCTAssertEqual(Set(s.tracks(artistKey: NameKey.artist("The The")).map(\.id)), ["tt1", "tt2"])
        XCTAssertEqual(s.artistKeys(of: tracks[9]), ["bjork", "thomyorke"])
        XCTAssertEqual(Set(s.tracks(artistKey: "thomyorke").map(\.id)), ["duet", "ty"])
        XCTAssertEqual(Set(s.tracks(artistKey: NameKey.artist("Simon & Garfunkel")).map(\.id)), ["sg1", "sg2"])
        XCTAssertEqual(s.matchArtist("Beyonce"), "beyonce")
        XCTAssertEqual(s.matchArtist("Sigur Ros"), "sigurros")
        XCTAssertEqual(s.matchArtist("the the"), NameKey.artist("The The"))

        // A station from the plain spelling finds the library's own.
        var beyonce = setup.session(.artist(key: NameKey.artist("Beyonce"), name: "Beyonce", id: nil))
        XCTAssertEqual(beyonce.station.title, "Beyoncé Radio")
        XCTAssertTrue(["b1", "b2", "b3"].contains(beyonce.next(1)[0].track.id))
        var theThe = setup.session(setup.artistSeed("The The"))
        XCTAssertEqual(theThe.station.title, "The The Radio")
        XCTAssertTrue(["tt1", "tt2"].contains(theThe.next(1)[0].track.id))
        // Thom Yorke's station: a guest spot is his too, and keeps him apart.
        // (Ten of the fourteen: a radio does not plan the whole library, so
        // the last few of a tiny one may come closer.)
        var yorke = setup.session(setup.artistSeed("Thom Yorke"), randomSeed: 2)
        let picks = yorke.next(10)
        XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: s, separation: 3), 0)
        F.line("names: Beyoncé/Beyonce/BEYONCÉ one artist, Sigur Rós/Sigur Ros one, AC/DC one, The The one, \"Björk; Thom Yorke\" two; Thom Yorke Radio's first: \(picks[0].track.id)")
    }

    /// A guest named only in "A; B" strings — never on a record of their
    /// own — still has a station.
    func testAGuestWithoutRecordsOfTheirOwn() {
        var tracks = F.library(artists: 8, albums: 1, perAlbum: 6, genres: { $0 < 4 ? ["Soul"] : ["Punk"] })
        tracks[2] = F.track("g1", artist: "Artist 0", album: "Album 0-0", number: 3, genres: ["Soul"], performers: ["Artist 0; Guest Singer"])
        tracks[14] = F.track("g2", artist: "Artist 2", album: "Album 2-0", number: 3, genres: ["Soul"], performers: ["Artist 2 feat. Guest Singer"])
        let setup = F.Setup(tracks)
        XCTAssertEqual(Set(setup.snapshot.tracks(artistKey: "guestsinger").map(\.id)), ["g1", "g2"])
        var session = setup.session(setup.artistSeed("Guest Singer"), randomSeed: 3)
        let picks = session.next(20)
        XCTAssertEqual(session.station.title, "Guest Singer Radio")
        XCTAssertTrue(["g1", "g2"].contains(picks[0].track.id))
        let soul = picks.filter { $0.track.genres == ["Soul"] }.count
        F.line("a guest only in \"A; B\" and \"A feat. B\": their station opens with \(picks[0].track.id), soul \(soul) of 20")
        XCTAssertGreaterThanOrEqual(soul, 16)
        XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: setup.snapshot, separation: 3), 0)
    }

    /// Names that NameKey folds to nothing ("!!!", "†‡†"): still an artist,
    /// kept apart from themselves, with a station of their own.
    func testNamesWithoutLettersOrDigits() {
        var tracks = F.library(artists: 6, albums: 1, perAlbum: 5, genres: { _ in ["Dance-Punk"] })
        for k in 1...5 {
            tracks.append(F.track("chk\(k)", artist: "!!!", album: "Myth Takes", number: k, genres: ["Dance-Punk"]))
            tracks.append(F.track("x\(k)", artist: "†‡†", album: "Crosses", number: k, genres: ["Dance-Punk"]))
        }
        let setup = F.Setup(tracks)
        let s = setup.snapshot
        let chk = s.artistKeys(of: tracks.first { $0.id == "chk1" }!)
        let crosses = s.artistKeys(of: tracks.first { $0.id == "x1" }!)
        XCTAssertEqual(chk.count, 1, "!!! is an artist")
        XCTAssertEqual(crosses.count, 1)
        XCTAssertNotEqual(chk, crosses, "and not the same one as †‡†")
        var session = setup.session(.artist(key: NameKey.artist("!!!"), name: "!!!", id: nil), randomSeed: 4)
        XCTAssertEqual(session.station.title, "!!! Radio")
        let picks = session.next(20)
        XCTAssertTrue(picks[0].track.id.hasPrefix("chk"), "their station starts with them")
        let violations = RadioMetrics.separationViolations(picks, snapshot: s, separation: 3)
        F.line("\"!!!\" and \"†‡†\": artists \(chk) and \(crosses); !!! Radio opens with \(picks[0].track.id); separation violations in 20: \(violations)")
        XCTAssertEqual(violations, 0)
    }

    /// The same song on its album and on a compilation (or a single, a
    /// deluxe edition): two tracks, one song. A station plays it once.
    func testTheSameSongOnTwoAlbums() {
        var tracks: [Track] = []
        for a in 0..<10 {
            for t in 1...8 {
                tracks.append(F.track("a\(a)-\(t)", artist: "Artist \(a)", album: "Album \(a)", number: t, year: 1990 + a))
                tracks[tracks.count - 1].name = "Song \(a)-\(t)"
                if t <= 4 {
                    // On the artist's best-of, and (for some) remastered.
                    var copy = F.track("h\(a)-\(t)", artist: "Artist \(a)", album: "Greatest Hits \(a)", number: t, year: 2005)
                    copy.name = t % 2 == 0 ? "Song \(a)-\(t) (Remastered 2005)" : "Song \(a)-\(t)"
                    tracks.append(copy)
                }
            }
        }
        let setup = F.Setup(tracks)
        var twice = 0, runs = 0
        for seed in 0..<6 {
            var session = setup.session(seed % 2 == 0 ? .personal : setup.artistSeed("Artist 4"), randomSeed: UInt64(seed))
            let picks = session.next(60)
            var songs: [String: Int] = [:]
            for pick in picks { songs[NameKey.title(pick.track.name) + "|" + (pick.track.albumArtist?.name ?? ""), default: 0] += 1 }
            twice += songs.values.filter { $0 > 1 }.count
            runs += 1
        }
        F.line("the same song on its album and a best-of (40 of 120 tracks, 80 songs), 6 stations x 60 picks: songs played twice \(twice)")
        XCTAssertEqual(twice, 0)
    }

    /// What makes one song of two tracks, and what does not.
    func testSongKeys() {
        let s = LibrarySnapshot(tracks: [
            F.track("1", artist: "Radiohead", album: "OK Computer", number: 6, genres: ["Rock"]),
            F.track("2", artist: "Radiohead", album: "Best Of", number: 3, genres: ["Rock"]),
            F.track("3", artist: "Radiohead", album: "Live", number: 1, genres: ["Rock"]),
            F.track("4", artist: "Radiohead", album: "Single", number: 1, genres: ["Rock"]),
            F.track("5", artist: "Radiohead", album: "Remixes", number: 1, genres: ["Rock"]),
            F.track("6", artist: "Portishead", album: "Dummy", number: 1, genres: ["Trip-Hop"]),
            F.track("7", artist: "Orchestra", album: "Fifth", number: 1, genres: ["Classical"]),
            F.track("8", artist: "Orchestra", album: "Fifth", number: 2, genres: ["Classical"]),
            F.track("9", artist: "Orchestra", album: "Fifth", number: 3, genres: ["Classical"]),
            F.track("10", artist: "Orchestra", album: "Fifth", number: 4, genres: ["Classical"]),
        ].enumerated().map { k, track in
            var t = track
            t.name = ["Karma Police", "Karma Police (Remastered 2011)", "Karma Police [Live]", "Karma Police - Single Version",
                      "Karma Police (Four Tet Remix)", "Karma Police", "Symphony No. 5 - I. Allegro con brio",
                      "Symphony No. 5 - II. Andante con moto", "…", "!!!"][k]
            return t
        })
        let song = { (id: String) in s.index.trackSong[s.position(of: id)!] }
        XCTAssertEqual(Set(["1", "2", "3", "4"].map(song)).count, 1, "remastered, live and single versions are one song")
        XCTAssertNotEqual(song("1"), song("5"), "a remix is a song of its own")
        XCTAssertNotEqual(song("1"), song("6"), "another artist's is another song")
        XCTAssertNotEqual(song("7"), song("8"), "two movements are two")
        XCTAssertNotEqual(song("9"), song("10"), "titles of punctuation only are each their own")
        let real = LibrarySnapshot(tracks: RadioRealLibraryFixture.tracks)
        F.line("songs: the test server's \(real.tracks.count) tracks are \(real.index.songCount) songs")
    }

    /// The mixes on the same awkward libraries: nothing breaks, no track
    /// twice in a mix, and a song on two albums is in a mix once.
    func testMixesOnAwkwardLibraries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var bestOf = RadioSyntheticLibrary().tracks
        // The loved artists' best-ofs: their first ten songs again, unplayed.
        var copies: [Track] = []
        for track in bestOf where (track.playCount > 3 || track.isFavorite) && copies.count < 300 {
            var copy = track
            copy = Track(id: "best-" + track.id, name: track.name + " (Remastered)", albumID: "best-" + (track.albumArtist?.id ?? ""),
                         albumName: "Greatest Hits", artists: track.artists, albumArtist: track.albumArtist, genres: track.genres,
                         year: 2015, trackNumber: copies.count % 20 + 1, discNumber: 1, duration: track.duration)
            copies.append(copy)
        }
        bestOf += copies
        let libraries: [(String, [Track])] = [
            ("12 tracks", F.library(artists: 4, albums: 1, perAlbum: 3)),
            ("one artist", F.library(artists: 1, albums: 3, perAlbum: 10)),
            ("all Rock, one year", F.library(artists: 20, albums: 2, perAlbum: 10, year: { _ in 2000 })),
            ("no genre, no year", F.library(artists: 20, albums: 2, perAlbum: 8, genres: { _ in [] }, year: { _ in nil })),
            ("best-ofs", bestOf),
        ]
        for (name, tracks) in libraries {
            let snapshot = LibrarySnapshot(tracks: tracks)
            let history = name == "best-ofs" ? RadioSyntheticLibrary().history : ListeningHistory()
            let now = name == "best-ofs" ? RadioSyntheticLibrary().now : F.now
            let generator = MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: history, now: now),
                                         history: history, graph: .fromLibrary(snapshot), now: now, calendar: calendar)
            let mixes = generator.mixes()
            var trackTwice = 0, songTwice = 0
            for mix in mixes {
                trackTwice += mix.tracks.count - Set(mix.tracks.map(\.id)).count
                let songs = mix.tracks.compactMap { snapshot.position(of: $0.id).map { snapshot.index.trackSong[$0] } }
                songTwice += songs.count - Set(songs).count
            }
            let stations = generator.suggestedStations()
            F.line("mixes, \(name): \(mixes.count) mixes (\(mixes.map(\.title).joined(separator: ", "))), \(stations.count) stations; a track twice in a mix \(trackTwice), a song twice \(songTwice)")
            XCTAssertEqual(trackTwice, 0, name)
            XCTAssertEqual(songTwice, 0, name)
        }
    }

    // MARK: Size

    /// Fifty thousand tracks: what each step takes (debug build here; the
    /// release numbers are in docs/RADIO.md).
    func testFiftyThousandTracks() {
        let library = RadioSyntheticLibrary(artistCount: 4000, albumsPerArtist: 1...3, tracksPerAlbum: 5...10,
                                            targetTracks: 50_000, styleTags: 400, seed: 13)
        var events: [PlayEvent] = []
        var rng = SplitMix64(seed: 9)
        for k in 0..<ListeningHistory.limit {
            let t = library.tracks[Int(rng.next() % UInt64(library.tracks.count))]
            events.append(PlayEvent(track: t, date: library.now.addingTimeInterval(-Double(ListeningHistory.limit - k) * 1500),
                                    listened: t.duration, outcome: rng.nextUnit() < 0.8 ? .completed : .skipped))
        }
        let history = ListeningHistory(events: events)
        let (snapshot, snapshotMS) = RadioPerformanceTests.time { LibrarySnapshot(tracks: library.tracks) }
        let (taste, tasteMS) = RadioPerformanceTests.time { TasteProfile(snapshot: snapshot, history: history, now: library.now) }
        let (graph, graphMS) = RadioPerformanceTests.time { SimilarityGraph.fromLibrary(snapshot) }
        var firstMS: [Double] = [], nextMS: [Double] = [], feedbackMS: [Double] = []
        let seeds: [StationSeed] = [
            .artist(key: library.artists[5].key, name: library.artists[5].name, id: nil), .personal, .discovery,
            .genre(key: "rock", name: "Rock"), .track(library.tracks[777].id), .decade(2000),
        ]
        for (k, seed) in seeds.enumerated() {
            let station = Station(seed: seed, snapshot: snapshot)
            let (made, ms) = RadioPerformanceTests.time { () -> RadioSession in
                var session = RadioSession(station: station, snapshot: snapshot, taste: taste, graph: graph, randomSeed: UInt64(k))
                XCTAssertEqual(session.next(5).count, 5)
                return session
            }
            firstMS.append(ms)
            var session = made
            for round in 0..<6 {
                let (picks, nms) = RadioPerformanceTests.time { session.next(5) }
                nextMS.append(nms)
                let (_, fms) = RadioPerformanceTests.time { () -> Int in
                    session.record(round % 2 == 0 ? .skipped(picks[0].track.id, after: 3) : .disliked(picks[0].track.id))
                    session.returnUnplayed(Array(picks.dropFirst().map(\.track.id)))
                    return session.next(5).count
                }
                feedbackMS.append(fms)
            }
        }
        func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        F.line(String(format: "50 000 tracks (%@), %d artists, %d genres: snapshot %.0f ms, taste %.0f ms, graph %.0f ms; session + first 5 median %.1f ms (max %.1f); next(5) median %.1f ms (max %.1f); feedback + next(5) median %.1f ms (max %.1f)",
                      RadioPerformanceTests.build, snapshot.artistTrackCounts.count, snapshot.genreTrackCounts.count,
                      snapshotMS, tasteMS, graphMS, median(firstMS), firstMS.max() ?? 0, median(nextMS), nextMS.max() ?? 0,
                      median(feedbackMS), feedbackMS.max() ?? 0))
        XCTAssertLessThan(snapshotMS, 1250 * RadioPerformanceTests.slack)
        XCTAssertLessThan(firstMS.max() ?? 0, 300 * RadioPerformanceTests.slack)
        XCTAssertLessThan(median(nextMS), 50 * RadioPerformanceTests.slack)
    }
}
