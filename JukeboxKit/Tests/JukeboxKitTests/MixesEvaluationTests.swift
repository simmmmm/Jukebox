// How good Home's mixes are, measured (lines starting MIXES-EVAL):
// the made-up listener's daily mixes (do they hold one kind of music, are
// they 60% known, are artists kept apart), the other mixes and their order,
// a brand-new listener, the test server's real library, and how much the
// mixes change from one day to the next and within a day of listening.

import Foundation
@testable import JukeboxKit
import XCTest

final class MixesEvaluationTests: XCTestCase {
    func testTheMadeUpListenersMixes() throws {
        let library = MixesLibrary()
        let snapshot = library.snapshot
        let generator = library.generator()
        let mixes = generator.mixes()
        let model = generator.model
        MixesCheck.line("made-up listener (\(library.tracks.count) tracks, \(library.base.artists.count) artists): \(mixes.count) mixes")
        for mix in mixes { MixesCheck.line("  \(MixesCheck.describe(mix, snapshot: snapshot))") }

        let daily = mixes.filter { $0.kind == .daily }
        XCTAssertGreaterThanOrEqual(daily.count, 3)
        XCTAssertLessThanOrEqual(daily.count, 6)
        // Daily mixes first, numbered in order.
        XCTAssertEqual(Array(mixes.prefix(daily.count).map(\.kind)), [MixKind](repeating: .daily, count: daily.count))
        XCTAssertEqual(daily.map(\.title), (1...daily.count).map { "Daily Mix \($0)" })

        var allDaily: [Track] = []
        var purities: [Double] = []
        var familiarShares: [Double] = []
        var separation = 0
        for mix in daily {
            XCTAssertTrue((25...40).contains(mix.tracks.count), "\(mix.title): \(mix.tracks.count) tracks")
            XCTAssertEqual(MixesCheck.duplicates(mix.tracks), 0)
            XCTAssertEqual(MixesCheck.albumBackToBack(mix.tracks), 0, mix.title)
            separation += MixesCheck.separationViolations(mix.tracks, snapshot: snapshot, window: 2)
            allDaily += mix.tracks

            // One kind of music: the share of the mix's most common cluster.
            let clusters = mix.tracks.compactMap { snapshot.primaryArtistKey(of: $0).flatMap { library.base.clusterOfArtist[$0] } }
            let purity = MixesCheck.purity(clusters)
            purities.append(purity.share)
            let known = mix.tracks.filter { t in
                guard let i = snapshot.position(of: t.id) else { return false }
                return model.familiarity[i] >= 0.3 || model.affinity[i] >= 0.25
            }
            familiarShares.append(Double(known.count) / Double(mix.tracks.count))

            // Its station plays on from its own tracks.
            XCTAssertEqual(mix.stationSeed, .collection(id: mix.id, name: mix.title, trackIDs: mix.tracks.map(\.id)))
            // Four covers of four albums, from the mix.
            XCTAssertEqual(mix.artwork.count, 4)
            XCTAssertEqual(Set(mix.artwork).count, mix.artwork.count)
            XCTAssertTrue(Set(mix.artwork).isSubset(of: Set(mix.tracks.compactMap(\.artwork))))
            XCTAssertTrue(mix.subtitle.hasSuffix(" and more"), mix.subtitle)
            let first = String(mix.subtitle.split(separator: ",").first ?? "")
            XCTAssertTrue(mix.tracks.contains { $0.artistLine.contains(first) }, mix.subtitle)
            MixesCheck.line("  \(mix.title): cluster \(MixesRadio.clusterName(purity.value)) \(MixesCheck.fmt(purity.share)), "
                            + "known \(MixesCheck.fmt(familiarShares.last ?? 0)), \(mix.subtitle)")
        }
        XCTAssertEqual(MixesCheck.duplicates(allDaily), 0, "no track in two daily mixes")
        XCTAssertEqual(separation, 0, "two songs between two by one artist")
        let meanPurity = purities.reduce(0, +) / Double(purities.count)
        let meanKnown = familiarShares.reduce(0, +) / Double(familiarShares.count)
        MixesCheck.line("daily mixes: purity \(MixesCheck.fmt(meanPurity)) (min \(MixesCheck.fmt(purities.min() ?? 0))), "
                        + "known \(MixesCheck.fmt(meanKnown)), separation violations \(separation)")
        XCTAssertGreaterThanOrEqual(meanPurity, 0.85)
        XCTAssertEqual(meanKnown, 0.6, accuracy: 0.12)
        // The listener's two loved clusters lead.
        let leading = Set(daily.prefix(2).compactMap { mix in
            MixesCheck.purity(mix.tracks.compactMap { snapshot.primaryArtistKey(of: $0).flatMap { library.base.clusterOfArtist[$0] } }).value
        })
        XCTAssertTrue(leading.isSubset(of: [0, 1]), "Rock and Electronic first, not \(leading)")

        // The others: each kind at most as often as it should be, each with
        // 8 to 50 tracks and no repeats.
        let kinds = mixes.map(\.kind)
        for kind in [MixKind.newArrivals, .rediscover, .deepCuts, .favorites, .onRepeat] {
            XCTAssertEqual(kinds.filter { $0 == kind }.count, 1, "\(kind)")
        }
        XCTAssertTrue((2...3).contains(kinds.filter { $0 == .decade }.count))
        XCTAssertEqual(kinds.filter { $0 == .genre }.count, 3)
        for mix in mixes {
            XCTAssertTrue((8...50).contains(mix.tracks.count), "\(mix.title) \(mix.tracks.count)")
            XCTAssertEqual(MixesCheck.duplicates(mix.tracks), 0, mix.title)
            XCTAssertFalse(mix.artwork.isEmpty, mix.title)
            XCTAssertTrue(mix.id.hasSuffix("2026-10-29"), mix.id)
        }
        XCTAssertEqual(Set(mixes.map(\.id)).count, mixes.count)

        // New Arrivals is the new albums.
        let arrivals = try XCTUnwrap(mixes.first { $0.kind == .newArrivals })
        XCTAssertTrue(arrivals.tracks.allSatisfy { library.newAlbums.contains($0.albumID ?? "") })
        // Loved Tracks is favourites; its station is Loved.
        let loved = try XCTUnwrap(mixes.first { $0.kind == .favorites })
        XCTAssertTrue(loved.tracks.allSatisfy(\.isFavorite))
        XCTAssertEqual(loved.stationSeed, .favorites)
        // Deep Cuts: hardly played, by artists the listener likes.
        let deep = try XCTUnwrap(mixes.first { $0.kind == .deepCuts })
        XCTAssertTrue(deep.tracks.allSatisfy { $0.playCount <= 1 })
        XCTAssertTrue(deep.tracks.allSatisfy { library.base.artist(key: $0.albumArtist?.key ?? "")?.liking ?? 0 >= 1 })
        XCTAssertEqual(deep.stationSeed, .discovery)
        // Rediscover: not heard in 60 days.
        let rediscover = try XCTUnwrap(mixes.first { $0.kind == .rediscover })
        for t in rediscover.tracks {
            let hours = model.hoursSince[try XCTUnwrap(snapshot.position(of: t.id))]
            if hours.isFinite { XCTAssertGreaterThan(hours / 24, 60) }
        }
        // Decade and genre mixes have their stations.
        for mix in mixes where mix.kind == .decade {
            guard case let .decade(year) = mix.stationSeed else { return XCTFail("decade station") }
            XCTAssertEqual(mix.title, "\(year)s Mix")
            XCTAssertTrue(mix.tracks.allSatisfy { ($0.year ?? 0) / 10 * 10 == year })
        }
        for mix in mixes where mix.kind == .genre {
            guard case let .genre(key, name) = mix.stationSeed else { return XCTFail("genre station") }
            XCTAssertEqual(mix.title, "\(name) Mix")
            XCTAssertTrue(mix.tracks.allSatisfy { snapshot.genreKeys(of: $0).contains(key) })
        }
        MixesCheck.line("order: " + mixes.map(\.title).joined(separator: ", "))
    }

    func testTheMadeUpListenersStations() {
        let library = MixesLibrary()
        let snapshot = library.snapshot
        let stations = library.generator().suggestedStations()
        MixesCheck.line("made-up listener's stations: " + stations.map(\.title).joined(separator: ", "))
        XCTAssertEqual(stations.prefix(3).map(\.seed), [.personal, .discovery, .favorites])
        XCTAssertEqual(stations.prefix(3).map(\.title), ["Your Station", "Discovery", "Loved"])
        let artists = stations.compactMap { station -> String? in
            if case let .artist(key, _, _) = station.seed { return key }
            return nil
        }
        XCTAssertEqual(artists.count, 6)
        // All six from what the listener plays: the loved, liked and
        // a-little clusters (0, 1, 2, 5, 6).
        let clusters = artists.compactMap { library.base.clusterOfArtist[$0] }
        XCTAssertTrue(Set(clusters).isSubset(of: [0, 1, 2, 5, 6]), "\(clusters)")
        XCTAssertGreaterThanOrEqual(Set(clusters).count, 2, "not six of one kind")
        XCTAssertEqual(stations.filter { if case .genre = $0.seed { true } else { false } }.count, 4)
        let decades = stations.filter { if case .decade = $0.seed { true } else { false } }
        XCTAssertTrue((1...3).contains(decades.count))
        XCTAssertEqual(Set(stations.map(\.id)).count, stations.count)
        for station in stations {
            XCTAssertEqual(station, Station(seed: station.seed, snapshot: snapshot))
            XCTAssertFalse(station.artwork.isEmpty, station.title)
        }
    }

    func testABrandNewListener() throws {
        // The made-up library with nothing heard, nothing loved, no history.
        let base = RadioSyntheticLibrary()
        let tracks = MixesLibrary(base).tracks.map { track -> Track in
            var t = track
            t.playCount = 0
            t.lastPlayed = nil
            t.isFavorite = false
            return t
        }
        let snapshot = LibrarySnapshot(tracks: tracks)
        let empty = ListeningHistory()
        let generator = MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: empty, now: base.now),
                                     history: empty, graph: .fromLibrary(snapshot), now: base.now, calendar: MixesCheck.calendar)
        let mixes = generator.mixes()
        MixesCheck.line("brand-new listener: " + mixes.map { "\($0.title) (\($0.tracks.count))" }.joined(separator: ", "))
        let kinds = Set(mixes.map(\.kind))
        // By the library's structure: daily mixes of its biggest artists,
        // what is new, decades and genres.
        XCTAssertTrue(kinds.isSuperset(of: [.daily, .newArrivals, .decade, .genre]), "\(kinds)")
        // Nothing that needs a history.
        XCTAssertTrue(kinds.isDisjoint(with: [.onRepeat, .rediscover, .deepCuts, .favorites]), "\(kinds)")
        let daily = mixes.filter { $0.kind == .daily }
        XCTAssertGreaterThanOrEqual(daily.count, 3)
        for mix in daily {
            XCTAssertGreaterThanOrEqual(mix.tracks.count, 25)
            let clusters = mix.tracks.compactMap { snapshot.primaryArtistKey(of: $0).flatMap { base.clusterOfArtist[$0] } }
            XCTAssertGreaterThanOrEqual(MixesCheck.purity(clusters).share, 0.8, mix.subtitle)
        }

        let stations = generator.suggestedStations()
        MixesCheck.line("brand-new listener's stations: " + stations.map(\.title).joined(separator: ", "))
        XCTAssertEqual(stations.prefix(2).map(\.seed), [.personal, .discovery])
        XCTAssertFalse(stations.contains { $0.seed == .favorites }, "no Loved without favourites")
        // The artists are the biggest ones.
        let biggest = snapshot.artistTrackCounts.keys.map { ($0, snapshot.ownTracks(artistKey: $0).count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        let artists = stations.compactMap { station -> String? in
            if case let .artist(key, _, _) = station.seed { return key }
            return nil
        }
        XCTAssertEqual(artists.count, 6)
        let topSize = biggest.prefix(15).last?.1 ?? 0
        XCTAssertTrue(artists.allSatisfy { snapshot.ownTracks(artistKey: $0).count >= topSize })
    }

    func testTheTestServersLibrary() throws {
        // As Jellyfin 12.4 gives it, joined tags and all; everything added
        // the same minute (the server is new), nothing heard.
        let tracks = RadioRealLibraryFixture.tracks
        let snapshot = LibrarySnapshot(tracks: tracks)
        let now = Date(timeIntervalSinceReferenceDate: 815_800_000)
        let empty = ListeningHistory()
        func make(_ history: ListeningHistory, _ tracks: [Track]) -> (MixGenerator, LibrarySnapshot) {
            let snapshot = LibrarySnapshot(tracks: tracks)
            return (MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: history, now: now),
                                 history: history, graph: .fromLibrary(snapshot), now: now, calendar: MixesCheck.calendar), snapshot)
        }
        let (fresh, _) = make(empty, tracks)
        let mixes = fresh.mixes()
        MixesCheck.line("test server, nothing heard: \(mixes.count) mixes")
        for mix in mixes { MixesCheck.line("  \(MixesCheck.describe(mix, snapshot: snapshot))") }
        XCTAssertFalse(mixes.isEmpty)
        for mix in mixes {
            XCTAssertGreaterThanOrEqual(mix.tracks.count, 8)
            XCTAssertEqual(MixesCheck.duplicates(mix.tracks), 0)
            // "MC Polder; Lyric Engine" is two artists, never one in a subtitle.
            XCTAssertFalse(mix.subtitle.contains(";"), mix.subtitle)
        }
        XCTAssertTrue(mixes.contains { $0.kind == .newArrivals }, "the whole library is new")

        // A listener who has played rock and folk for a month: their daily
        // mixes, by cluster.
        var events: [PlayEvent] = []
        var played: [Track] = []
        var rng = SplitMix64(seed: 3)
        let loved: Set<String> = ["Velvet Static", "Iron Meadow", "The Lanterns", "Old Mill Road", "Willow & Pine", "June Hollow"]
        let theirs = tracks.filter { loved.contains($0.albumArtist?.name ?? "") }
        for k in 0..<200 {
            let t = theirs[Int(rng.next() % UInt64(theirs.count))]
            let date = now.addingTimeInterval(-Double(200 - k) * 3 * 3600 - 86_400)
            events.append(PlayEvent(track: t, date: date, listened: t.duration, outcome: .completed))
            played.append(t)
        }
        let history = ListeningHistory(events: events)
        let (listener, listenerSnapshot) = make(history, tracks)
        let theirMixes = listener.mixes()
        MixesCheck.line("test server, a month of rock and folk: \(theirMixes.count) mixes")
        for mix in theirMixes { MixesCheck.line("  \(MixesCheck.describe(mix, snapshot: listenerSnapshot))") }
        let daily = theirMixes.filter { $0.kind == .daily }
        XCTAssertGreaterThanOrEqual(daily.count, 2)
        for mix in daily.prefix(2) {
            let genres = mix.tracks.flatMap { listenerSnapshot.genreKeys(of: $0) }
            let rockOrFolk = mix.tracks.filter { t in
                let g = Set(listenerSnapshot.genreKeys(of: t))
                return !g.isDisjoint(with: ["rock", "folk", "alternative", "indie", "shoegaze", "hardrock", "americana", "acoustic"])
            }
            MixesCheck.line("  \(mix.title): rock or folk \(rockOrFolk.count) of \(mix.tracks.count), genres \(Set(genres).sorted().joined(separator: " "))")
            XCTAssertGreaterThanOrEqual(Double(rockOrFolk.count) / Double(mix.tracks.count), 0.6, mix.subtitle)
        }
        XCTAssertTrue(theirMixes.contains { $0.kind == .onRepeat })
    }

    func testTheSameAllDayAndNewTomorrow() throws {
        let library = MixesLibrary()
        let morning = MixesCheck.date("2026-10-30T07:30:00Z")
        let lunch = MixesCheck.date("2026-10-30T13:15:00Z")
        let tomorrow = MixesCheck.date("2026-10-31T07:30:00Z")

        // Built again at lunch, with nothing else changed: the same, in every
        // way (the taste is made for midnight, whatever `now` is).
        let a = library.generator(at: morning).mixes()
        let b = library.generator(at: lunch).mixes()
        XCTAssertEqual(a, b)
        XCTAssertEqual(library.generator(at: morning).suggestedStations(), library.generator(at: lunch).suggestedStations())

        // The next day: new mixes of the same kinds, the daily ones about
        // the same artists, with other songs.
        let c = library.generator(at: tomorrow).mixes()
        XCTAssertTrue(c.allSatisfy { $0.id.hasSuffix("2026-10-31") })
        var overlaps: [String] = []
        var dailyOverlap: [Double] = []
        for mix in a {
            let key = mix.id.replacingOccurrences(of: "2026-10-30", with: "2026-10-31")
            guard let next = c.first(where: { $0.id == key }) else { continue }
            let j = MixesCheck.jaccard(mix.tracks, next.tracks)
            overlaps.append("\(mix.title) \(MixesCheck.fmt(j))")
            if mix.kind == .daily { dailyOverlap.append(j) }
        }
        MixesCheck.line("day to day, the share of the same songs (Jaccard): " + overlaps.joined(separator: ", "))
        let mean = dailyOverlap.reduce(0, +) / Double(max(1, dailyOverlap.count))
        MixesCheck.line("daily mixes from one day to the next: \(MixesCheck.fmt(mean)) the same")
        XCTAssertLessThan(mean, 0.6, "tomorrow's daily mixes are mostly new songs")
        XCTAssertGreaterThanOrEqual(dailyOverlap.count, 3, "the same clusters tomorrow")
    }

    /// A morning of listening, then the app makes the mixes again at lunch,
    /// as MixStore does every three hours: the mix being listened to should
    /// not change because it is being listened to.
    func testAMorningOfListeningChangesLittle() throws {
        let library = MixesLibrary()
        let morning = MixesCheck.date("2026-10-30T07:30:00Z")
        let lunch = MixesCheck.date("2026-10-30T13:15:00Z")
        let before = library.generator(at: morning).mixes()
        let first = try XCTUnwrap(before.first)

        // The first 20 songs of Daily Mix 1 heard to the end, one of them
        // thumbed down; Jellyfin counts each play.
        var history = library.history
        var tracks = library.tracks
        let disliked = first.tracks[5].id
        for (k, track) in first.tracks.prefix(20).enumerated() {
            let date = morning.addingTimeInterval(Double(k) * 240)
            let outcome: PlayOutcome = track.id == disliked ? .disliked : .completed
            history.append(PlayEvent(track: track, date: date, listened: track.duration, outcome: outcome))
            if let i = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[i].playCount += 1
                tracks[i].lastPlayed = date
            }
        }
        let snapshot = LibrarySnapshot(tracks: tracks)
        let graph = SimilarityGraph.fromLibrary(snapshot)
        let after = MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: history, now: lunch),
                                 history: history, graph: graph, now: lunch, calendar: MixesCheck.calendar).mixes()
        var changes: [String] = []
        var changed = 0
        for mix in before {
            guard let again = after.first(where: { $0.id == mix.id }) else {
                changes.append("\(mix.title) gone")
                continue
            }
            let lost = Set(mix.tracks.map(\.id)).subtracting(again.tracks.map(\.id)).count
            changed += lost
            changes.append("\(mix.title) \(lost)")
        }
        MixesCheck.line("after a morning of Daily Mix 1 (20 songs, one thumbed down), songs changed by lunch: "
                        + changes.joined(separator: ", "))
        let again = try XCTUnwrap(after.first { $0.id == first.id })
        // The thumbed-down song is gone at once; the rest of Daily Mix 1 stays.
        XCTAssertFalse(again.tracks.contains { $0.id == disliked })
        let kept = Set(first.tracks.map(\.id)).intersection(again.tracks.map(\.id)).count
        MixesCheck.line("Daily Mix 1 kept \(kept) of \(first.tracks.count)")
        XCTAssertGreaterThanOrEqual(kept, first.tracks.count - 3)
    }
}

/// Names for the made-up library's clusters, for the listings.
enum MixesRadio {
    static func clusterName(_ cluster: Int?) -> String {
        guard let cluster, RadioSyntheticLibrary.clusters.indices.contains(cluster) else { return "?" }
        return RadioSyntheticLibrary.clusters[cluster].genre
    }
}
