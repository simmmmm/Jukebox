// What is coming on a station, seen and taken out before it plays: the
// photographer, 20 November 2026, "dat ik bijvoorbeeld harde metal uit een
// verder hele rustige kantoor approved radio kan halen zonder dat iedereen
// zich de tering schrikt". A removal teaches the station; a queue held
// fifteen ahead keeps skips as strong as four did; and a calm station
// keeps a loud song out in the first place, at Familiar most of all ("Als
// in het past niet bij het volume van de rest", of Bring Me The Horizon on
// his calm Your Station). Lines starting RADIO-QUEUE are in docs/RADIO.md.

import Foundation
import JukeboxKit
import XCTest

final class RadioQueueTests: XCTestCase {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func line(_ text: String) { print("RADIO-QUEUE " + text) }

    /// An office library as his: eight calm artists (folk, indie, ambient,
    /// post-punk at its quietest), each played often, and one metalcore
    /// band played now and then. Calm songs at −14 … −11 LUFS (gain −4 …
    /// −7 dB), the band's at −7 (gain −11), as their records are mastered;
    /// with `gains` false the server gave none (Jellyfin's LUFS scan off).
    struct Office {
        let tracks: [Track]
        let history: ListeningHistory
        let snapshot: LibrarySnapshot
        let taste: TasteProfile
        let graph: SimilarityGraph
        static let loudArtist = "Loud Horizon"

        init(gains: Bool = true, loudPlays: Int = 3, broad: Bool = false) {
            let calm: [(String, [String])] = [
                ("Fontaine Rows", broad ? ["Post-Punk", "Rock"] : ["Post-Punk", "Indie"]),
                ("Apparatus", ["Electronic", "Ambient"]),
                ("June Hollow", ["Folk", "Indie"]),
                ("Old Mill Road", ["Folk"]),
                ("Paper Harbour", ["Indie", "Alternative"]),
                ("Glass Rooms", ["Ambient"]),
                ("Saskia Sings", ["Singer-Songwriter", "Folk"]),
                ("Low Lanterns", ["Indie", "Dream Pop"]),
            ]
            var tracks: [Track] = []
            var history = ListeningHistory()
            for (a, (name, genres)) in calm.enumerated() {
                for k in 0..<12 {
                    var t = RadioTestTracks.track("c\(a)-\(k)", name, album: "\(name) \(k / 6)", genres: genres,
                                                  year: 2010 + a, number: k % 6 + 1, plays: 6, lastPlayed: now.addingTimeInterval(-86_400 * 3))
                    if gains { t.normalizationGain = -4 - Double((a + k) % 4) }
                    tracks.append(t)
                    for d in 0..<4 {
                        history.append(PlayEvent(track: t, date: now.addingTimeInterval(-86_400 * Double(2 + d + k % 5)),
                                                 listened: 200, outcome: .completed))
                    }
                }
            }
            for k in 0..<12 {
                var t = RadioTestTracks.track("m\(k)", Self.loudArtist, album: "Loud \(k / 6)", genres: broad ? ["Rock"] : ["Metalcore", "Rock"],
                                              year: 2015, number: k % 6 + 1, plays: k < 4 ? loudPlays : 0,
                                              lastPlayed: k < 4 ? now.addingTimeInterval(-86_400 * 20) : nil)
                if gains { t.normalizationGain = -11 }
                tracks.append(t)
                if k < 4 {
                    for d in 0..<loudPlays {
                        history.append(PlayEvent(track: t, date: now.addingTimeInterval(-86_400 * Double(10 + d)),
                                                 listened: 200, outcome: .completed))
                    }
                }
            }
            self.tracks = tracks
            self.history = history
            snapshot = LibrarySnapshot(tracks: tracks)
            taste = TasteProfile(snapshot: snapshot, history: history, now: now)
            graph = .fromLibrary(snapshot)
        }

        func session(_ seed: StationSeed = .personal, adventurousness: Double, randomSeed: UInt64) -> RadioSession {
            RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot, taste: taste, graph: graph,
                         settings: RadioSettings(adventurousness: adventurousness), randomSeed: randomSeed)
        }

        func isLoud(_ id: ItemID) -> Bool { id.hasPrefix("m") }
    }

    /// Your Station at Familiar, on a calm history with one loud band in it:
    /// the band's share of the first 40, over 12 stations.
    func loudShare(_ office: Office, adventurousness: Double) -> Double {
        var loud = 0, all = 0
        for run in 0..<12 {
            var session = office.session(adventurousness: adventurousness, randomSeed: UInt64(900 + run))
            let picks = session.next(40)
            loud += picks.filter { office.isLoud($0.id) }.count
            all += picks.count
        }
        return Double(loud) / Double(max(1, all))
    }

    func testACalmStationKeepsALoudSongOut() {
        let withGains = Office(gains: true)
        let without = Office(gains: false)
        for adv in [0.0, 0.35, 1.0] {
            Self.line(String(format: "Your Station, calm history and one loud band (12 songs of 108): the band's share of 40 at %.2f: %.3f with the server's loudness, %.3f without",
                             adv, loudShare(withGains, adventurousness: adv), loudShare(without, adventurousness: adv)))
        }
        // Familiar: what is played, and as loud as the rest.
        XCTAssertLessThan(loudShare(withGains, adventurousness: 0), 0.01)
        XCTAssertLessThan(loudShare(without, adventurousness: 0), 0.03)
        // Adventurous: the band is his too, and may come.
        XCTAssertGreaterThan(loudShare(withGains, adventurousness: 1), 0)
    }

    /// Never right after a calm song at Familiar, whatever the station
    /// chose before: the step from one song to the next.
    func testNoLoudStepAtFamiliar() {
        let office = Office(gains: true)
        var steps = 0
        for run in 0..<12 {
            var session = office.session(adventurousness: 0, randomSeed: UInt64(1300 + run))
            let picks = session.next(40)
            for (a, b) in zip(picks, picks.dropFirst()) where !office.isLoud(a.id) && office.isLoud(b.id) { steps += 1 }
        }
        Self.line("calm to loud at Familiar, 12 × 40 picks: \(steps)")
        XCTAssertEqual(steps, 0)
    }

    // MARK: - Fifteen ahead, and taking one out

    static let rock = StationSeed.genre(key: NameKey.genre("Rock"), name: "Rock")
    static let shoegaze = NameKey.genre("Shoegaze")

    func isShoegaze(_ id: ItemID, _ w: RadioEvaluationTests.World) -> Bool {
        w.snapshot.track(id: id).map { w.snapshot.genreKeys(of: $0).contains(Self.shoegaze) } ?? false
    }

    /// The app's loop (RadioController): `ahead` queued; a song heard to
    /// the end makes room for one more; a skip puts back all that is queued
    /// and chooses them again. Rock Radio, every Shoegaze song skipped
    /// until three are: Shoegaze's share of the 30 after.
    func shoegazeAfterSkips(ahead: Int, _ w: RadioEvaluationTests.World) -> Double {
        var share = 0.0, runs = 0.0
        for run in 0..<48 {
            var session = w.session(Self.rock, randomSeed: UInt64(500 + run))
            var queue = session.next(ahead).map(\.id)
            var skips = 0, steps = 0
            while skips < 3, steps < 80, !queue.isEmpty {
                let playing = queue.removeFirst()
                steps += 1
                if isShoegaze(playing, w) {
                    // As RadioController: what is queued goes back first, so
                    // the skip is marked where the station then stands.
                    session.returnUnplayed(queue)
                    session.record(.skipped(playing, after: 8))
                    skips += 1
                    queue = session.next(ahead).map(\.id)
                } else {
                    session.record(.finished(playing))
                    queue += session.next(ahead - queue.count).map(\.id)
                }
            }
            guard skips == 3 else { continue }
            let next = Array((queue + session.next(30).map(\.id)).prefix(30))
            share += Double(next.filter { isShoegaze($0, w) }.count) / 30
            runs += 1
        }
        return share / max(1, runs)
    }

    func testFifteenAheadKeepsSkipsAsStrong() {
        let w = RadioEvaluationTests.shared
        let one = shoegazeAfterSkips(ahead: 1, w)
        let four = shoegazeAfterSkips(ahead: 4, w), fifteen = shoegazeAfterSkips(ahead: 15, w)
        Self.line(String(format: "three Shoegaze skips on Rock Radio, the app's loop, 48 runs: its share of the next 30 %.3f with 1 ahead, %.3f with 4, %.3f with 15", one, four, fifteen))
        XCTAssertLessThanOrEqual(fifteen, four + 0.02)
    }

    /// Rock Radio, fifteen ahead; the listener takes the first Shoegaze song
    /// out of Up Next. The Shoegaze songs queued after it that this rules
    /// out, the others it leaves, and Shoegaze's share of the 30 after.
    func testRemovingASongTeachesTheStation() {
        let w = RadioEvaluationTests.shared
        var before = 0.0, after = 0.0, runs = 0.0
        var outLike = 0, like = 0, outOther = 0, other = 0
        for run in 0..<24 {
            var control = w.session(Self.rock, randomSeed: UInt64(700 + run))
            var session = w.session(Self.rock, randomSeed: UInt64(700 + run))
            var queue = session.next(15).map(\.id)
            _ = control.next(15)
            guard let victim = queue.first(where: { isShoegaze($0, w) }) else { continue }
            queue.removeAll { $0 == victim }
            session.record(.removed(victim))
            session.returnUnplayed([victim])
            control.returnUnplayed([victim])
            let out = Set(session.ruledOut(queue))
            for id in queue {
                if isShoegaze(id, w) {
                    like += 1
                    if out.contains(id) { outLike += 1 }
                } else {
                    other += 1
                    if out.contains(id) { outOther += 1 }
                }
            }
            XCTAssertFalse(out.contains(victim))
            session.returnUnplayed(Array(out))
            queue.removeAll { out.contains($0) }
            let kept = control.handedOut.filter { $0 != victim }
            let next = Array((queue + session.next(30).map(\.id)).prefix(30))
            let baseline = Array((kept + control.next(30).map(\.id)).prefix(30))
            XCTAssertFalse(next.contains(victim), "a song taken out does not come back on its station")
            after += Double(next.filter { isShoegaze($0, w) }.count) / 30
            before += Double(baseline.filter { isShoegaze($0, w) }.count) / 30
            runs += 1
        }
        Self.line(String(format: "one Shoegaze song taken out of Rock Radio's 15 ahead: Shoegaze's share of the next 30 %.3f without, %.3f after (%d runs); ruled out with it %d of %d Shoegaze songs queued, %d of %d others",
                         before / runs, after / runs, Int(runs), outLike, like, outOther, other))
        XCTAssertGreaterThan(runs, 10)
        // Half of Rock Radio is Shoegaze here: one song taken out says less
        // than it does of a genre that stands out (the loud test below).
        XCTAssertLessThan(after, before * 0.8)
        XCTAssertLessThan(Double(outOther), Double(other) * 0.1)
    }

    /// A loud song taken out of a calm Your Station at the default dial:
    /// the loud band's share of what follows.
    func testRemovingALoudSongNarrowsTheLoudSide() {
        for gains in [true, false] { removeALoudSong(Office(gains: gains), gains: gains) }
    }

    func removeALoudSong(_ office: Office, gains: Bool) {
        var before = 0.0, after = 0.0, runs = 0.0
        for run in 0..<24 {
            var control = office.session(adventurousness: 1, randomSeed: UInt64(1500 + run))
            var session = office.session(adventurousness: 1, randomSeed: UInt64(1500 + run))
            let queue = session.next(15).map(\.id)
            _ = control.next(15)
            guard let victim = queue.first(where: office.isLoud) else { continue }
            session.record(.removed(victim))
            session.returnUnplayed(queue)
            control.returnUnplayed(queue)
            after += Double(session.next(40).filter { office.isLoud($0.id) }.count) / 40
            before += Double(control.next(40).filter { office.isLoud($0.id) }.count) / 40
            runs += 1
        }
        Self.line(String(format: "a loud song taken out of a calm Your Station at Adventurous, %@: the loud band's share of the next 40 %.3f without, %.3f after (%d runs)",
                         gains ? "with the server's loudness" : "without", before / runs, after / runs, Int(runs)))
        XCTAssertGreaterThan(runs, 3)
        XCTAssertLessThan(after, before * (gains ? 0.5 : 0.6))
    }

    func testRemovingAnArtist() {
        let w = RadioEvaluationTests.shared
        var left = 0, runs = 0
        for run in 0..<12 {
            var session = w.session(Self.rock, randomSeed: UInt64(1900 + run))
            let queue = session.next(15).map(\.id)
            guard let victim = queue.dropFirst(2).first,
                  let artist = w.snapshot.track(id: victim).flatMap({ w.snapshot.primaryArtistKey(of: $0) }) else { continue }
            session.record(.removedArtist(victim))
            session.returnUnplayed(Array(queue.dropFirst(2)))
            left += session.next(40).filter { w.snapshot.track(id: $0.id).flatMap { w.snapshot.primaryArtistKey(of: $0) } == artist }.count
            runs += 1
        }
        Self.line("Don't Play This Artist on Rock Radio: their songs in the next 40, \(left) in \(runs) stations")
        XCTAssertLessThanOrEqual(left, runs / 4)
    }

    // MARK: - What else the loudness and the flow move

    /// The band tagged only "Rock", which one calm artist shares, and no
    /// gains: what the tags alone can still do.
    func testABroadlyTaggedLoudBand() {
        let office = Office(gains: false, broad: true)
        let familiar = loudShare(office, adventurousness: 0), standard = loudShare(office, adventurousness: 0.35)
        Self.line(String(format: "the band tagged only Rock (shared with one calm artist), no gains: its share of 40 at 0 %.3f, at 0.35 %.3f", familiar, standard))
        XCTAssertLessThan(familiar, 0.05)
    }

    /// Your Station at Familiar on Office: the flow keeps the calm songs
    /// together; how many artists of the eight still come in 40.
    func testFlowKeepsVariety() {
        let office = Office(gains: true)
        var artists = 0.0
        for run in 0..<12 {
            var session = office.session(adventurousness: 0, randomSeed: UInt64(2100 + run))
            artists += Double(RadioMetrics.distinctArtists(session.next(40), snapshot: office.snapshot))
        }
        Self.line(String(format: "Your Station on Office at 0: distinct artists in 40, %.1f of 8 calm", artists / 12))
        XCTAssertGreaterThan(artists / 12, 6)
    }

    /// The made-up library with gains as records have them, by album and
    /// unrelated to the genre (the loudness war is by year and label, not
    /// by style): artist stations at 0 and 0.35, against the same without
    /// gains. The bell must not take the station's variety or its rules.
    func testGainsDoNotNarrowStations() {
        let library = RadioSyntheticLibrary()
        for spread in [3.0, 8.0] {
            var tracks = library.tracks
            for k in tracks.indices {
                var rng = SplitMix64(seed: SplitMix64.stableSeed(tracks[k].albumID ?? tracks[k].id))
                tracks[k].normalizationGain = -7 + spread * (rng.nextUnit() - 0.5)
            }
            for adv in [0.0, 0.35] {
                let plain = measure(library.tracks, library, adv)
                let loud = measure(tracks, library, adv)
                Self.line(String(format: "gains %.0f dB apart by album, artist stations at %.2f: in cluster %.3f -> %.3f, distinct artists in 50 %.1f -> %.1f, separation violations %d -> %d",
                                 spread, adv, plain.cluster, loud.cluster, plain.artists, loud.artists, plain.violations, loud.violations))
                XCTAssertEqual(loud.violations, 0)
                XCTAssertGreaterThan(loud.artists, plain.artists * 0.85)
                XCTAssertGreaterThan(loud.cluster, plain.cluster - 0.05)
            }
        }
    }

    func measure(_ tracks: [Track], _ library: RadioSyntheticLibrary, _ adv: Double)
        -> (cluster: Double, artists: Double, violations: Int) {
        let snapshot = LibrarySnapshot(tracks: tracks)
        let taste = TasteProfile(snapshot: snapshot, history: library.history, now: library.now)
        let graph = SimilarityGraph.fromLibrary(snapshot)
        var inCluster = 0.0, picksSeen = 0.0, artists = 0.0, stations = 0.0, violations = 0
        for info in library.artists.prefix(16) {
            for run in 0..<3 {
                let seed = StationSeed.artist(key: info.key, name: info.name, id: info.id)
                var session = RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot, taste: taste,
                                           graph: graph, settings: RadioSettings(adventurousness: adv), randomSeed: UInt64(40 + run))
                let picks = session.next(50)
                for pick in picks {
                    picksSeen += 1
                    if let key = snapshot.primaryArtistKey(of: pick.track), library.clusterOfArtist[key] == info.cluster { inCluster += 1 }
                }
                artists += Double(RadioMetrics.distinctArtists(picks, snapshot: snapshot))
                violations += RadioMetrics.separationViolations(picks, snapshot: snapshot, separation: 3)
                stations += 1
            }
        }
        return (inCluster / picksSeen, artists / stations, violations)
    }
}
