// How a song sounds, on a station (docs/RADIO.md, "How it sounds"): the
// photographer's Moans Radio (RadioServerMixTests' library in the shape of
// his) with AcousticBrainz's values as his songs have them, before and
// after; and SoundService against a mock of ListenBrainz's lookup and
// AcousticBrainz. Lines starting RADIO-MIX are in docs/RADIO.md.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class RadioSoundTests: XCTestCase {
    static func line(_ text: String) { print("RADIO-MIX " + text) }

    /// Each artist's mean on his library, 23 November 2026 (acoustic,
    /// relaxed, danceable), from AcousticBrainz: the calm artists and the
    /// three as measured; the rest made up for their genre. Hania Rani &
    /// Dobrawa Czocher have none, as on his library.
    static let means: [String: (Double, Double, Double)] = [
        "Hania Rani": (0.97, 1.00, 0.00), "Nils Frahm": (0.87, 0.98, 0.10), "Eydís Evensen": (0.83, 0.99, 0.00),
        "Peter Broderick": (0.86, 0.89, 0.15),
        "Gorillaz": (0.15, 0.45, 0.76), "Angele": (0.47, 0.94, 0.76), "Cocteau Twins": (0.24, 0.41, 0.45),
        "Velvet Static": (0.2, 0.5, 0.3), "Low Lanterns": (0.3, 0.6, 0.3), "Iron Meadow": (0.1, 0.3, 0.4),
        "Concrete Poets": (0.1, 0.4, 0.8), "Loud Horizon": (0.02, 0.05, 0.3), "Fontaine Rows": (0.1, 0.3, 0.5),
        "Nightdrive": (0.05, 0.5, 0.7), "Kalimba Sound System": (0.05, 0.5, 0.8), "Sunny Side": (0.15, 0.5, 0.8),
        "Mira Lux": (0.15, 0.5, 0.75), "Paper Harbour": (0.15, 0.4, 0.5), "June Hollow": (0.7, 0.7, 0.3),
    ]

    /// A profile for three songs in four, around the artist's mean (the
    /// classifiers' values spread wide, so ±0.2), as about a quarter of his
    /// songs have none.
    static func profiles(_ tracks: [Track]) -> [ItemID: SoundProfile] {
        var rng = SplitMix64(seed: 20_261_123)
        var profiles: [ItemID: SoundProfile] = [:]
        for (i, track) in tracks.enumerated() {
            func near(_ x: Double) -> Double { min(1, max(0, x + 0.4 * (Double(rng.next() % 1000) / 1000 - 0.5))) }
            guard let m = means[track.albumArtist?.name ?? ""] else { continue }
            let (a, r, d) = (near(m.0), near(m.1), near(m.2))
            if i % 4 != 3 { profiles[track.id] = SoundProfile(acoustic: a, relaxed: r, danceable: d) }
        }
        return profiles
    }

    struct Count {
        var misfits = 0, calm = 0, unknown = 0, all = 0
        func share(_ n: Int) -> Double { Double(n) / Double(max(1, all)) }
    }

    /// Moans Radio, 12 stations × 30 picks, with or without the profiles.
    static func stations(_ world: RadioServerMixTests.Calm, _ adventurousness: Double,
                         sound: [ItemID: SoundProfile]) -> Count {
        var count = Count()
        let artistsKnown = Set(means.keys).subtracting(["Hania Rani & Dobrawa Czocher"])
        for run in 0..<12 {
            var session = RadioSession(station: Station(seed: .track(world.seed.id), snapshot: world.snapshot), snapshot: world.snapshot,
                                       taste: world.taste, graph: world.graph, settings: RadioSettings(adventurousness: adventurousness),
                                       randomSeed: UInt64(300 + run), sound: sound)
            let picks = session.next(30)
            count.misfits += picks.filter(world.isMisfit).count
            count.calm += picks.filter(world.isCalm).count
            // Neither the song nor its artist known: the bell says nothing.
            count.unknown += picks.filter { !artistsKnown.contains($0.track.albumArtist?.name ?? "") }.count
            count.all += picks.count
        }
        return count
    }

    func testTheSoundKeepsAPianoStationToPiano() {
        for key in [true, false] {
            let world = RadioServerMixTests.Calm(key: key)
            let sound = Self.profiles(world.tracks)
            for adv in [0.0, 0.35, 0.7, 1.0] {
                let before = Self.stations(world, adv, sound: [:])
                let after = Self.stations(world, adv, sound: sound)
                Self.line(String(format: "Moans Radio %@, at %.2f, 12 x 30 picks, with AcousticBrainz: the calm artists %.3f -> %.3f, Gorillaz, Angele and Cocteau Twins %.3f -> %.3f, picks with no sound known %.3f -> %.3f",
                                 key ? "with Last.fm" : "without a key", adv,
                                 before.share(before.calm), after.share(after.calm), before.share(before.misfits),
                                 after.share(after.misfits), before.share(before.unknown), after.share(after.unknown)))
                XCTAssertGreaterThanOrEqual(after.calm, before.calm - 3)
                XCTAssertLessThanOrEqual(after.misfits, before.misfits)
                XCTAssertEqual(after.all, 360)
            }
            // Without a key, where Last.fm cannot place her, the sound does.
            if !key {
                let before = Self.stations(world, 0, sound: [:]), after = Self.stations(world, 0, sound: sound)
                XCTAssertGreaterThan(after.share(after.calm), before.share(before.calm) + 0.2)
                XCTAssertLessThan(after.share(after.misfits), before.share(before.misfits))
            }
        }
    }

    /// No profiles, no change: the same picks as before, one for one.
    func testWithoutProfilesNothingChanges() {
        let world = RadioServerMixTests.Calm(key: false)
        func picks(_ sound: [ItemID: SoundProfile]) -> [ItemID] {
            var session = RadioSession(station: Station(seed: .track(world.seed.id), snapshot: world.snapshot), snapshot: world.snapshot,
                                       taste: world.taste, graph: world.graph, randomSeed: 7, sound: sound)
            return session.next(40).map(\.track.id)
        }
        let none = world.tracks.prefix(3).reduce(into: [ItemID: SoundProfile]()) { $0[$1.id] = SoundProfile(acoustic: 1, relaxed: 1, danceable: 0) }
        XCTAssertEqual(picks([:]), picks([:]))
        // Fewer than five of the station's best known: no centre, no bell.
        XCTAssertEqual(picks(none), picks([:]))
    }

    // MARK: SoundService

    /// ListenBrainz's lookup and AcousticBrainz, as they answer.
    final class Mock: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var asked: [String] = []
        var down = false
        /// By "artist|title": the recording; with the album only when
        /// `albumOnly`.
        let recordings: [String: String]
        let albumOnly: Set<String>
        let sound: [String: (Double, Double, Double)]

        init(recordings: [String: String], albumOnly: Set<String> = [], sound: [String: (Double, Double, Double)]) {
            self.recordings = recordings
            self.albumOnly = albumOnly
            self.sound = sound
        }

        func send(_ request: URLRequest) async throws -> HTTPResponse {
            let url = request.url?.absoluteString ?? ""
            lock.withLock { asked.append(url) }
            if lock.withLock({ down }) { throw URLError(.notConnectedToInternet) }
            if url.contains("listenbrainz") {
                let rows = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [[String: String]] ?? []
                let withAlbum = url.contains("acrr-lookup")
                var answer: [[String: Any]] = []
                for (i, row) in rows.enumerated() {
                    let key = (row["artist_credit_name"] ?? "") + "|" + (row["recording_name"] ?? "")
                    guard let id = recordings[key], withAlbum || !albumOnly.contains(key) else { continue }
                    answer.append(["index": i, "recording_mbid": id, "artist_credit_name": row["artist_credit_name"] ?? ""])
                }
                return HTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: answer))
            }
            let ids = URLComponents(string: url)?.queryItems?.first { $0.name == "recording_ids" }?.value?.split(separator: ";").map(String.init) ?? []
            var answer: [String: Any] = ["mbid_mapping": [String: String]()]
            for id in ids {
                guard let (a, r, d) = sound[id] else { continue }
                answer[id] = ["0": ["highlevel": [
                    "mood_acoustic": ["all": ["acoustic": a, "not_acoustic": 1 - a], "value": "acoustic"],
                    "mood_relaxed": ["all": ["relaxed": r, "not_relaxed": 1 - r]],
                    "danceability": ["all": ["danceable": d, "not_danceable": 1]],
                ]]]
            }
            return HTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: answer))
        }
    }

    func testSoundServiceLooksUpOnceAndKeeps() async throws {
        let her = ArtistRef(id: "h", name: "Hania Rani")
        let tracks = [
            Track(id: "1", name: "Eden", albumID: "a", albumName: "Esja", artists: [her], albumArtist: her),
            Track(id: "2", name: "Eden (Live)", albumID: "b", albumName: "Live", artists: [her], albumArtist: her),
            Track(id: "3", name: "Moans", albumID: "c", albumName: "Ghosts", artists: [her], albumArtist: her),
            Track(id: "4", name: "Glass", albumID: "a", albumName: "Esja", artists: [her], albumArtist: her),
        ]
        let snapshot = LibrarySnapshot(tracks: tracks)
        let mock = Mock(recordings: ["Hania Rani|Eden": "r-eden", "Hania Rani|Glass": "r-glass"], albumOnly: ["Hania Rani|Glass"],
                        sound: ["r-eden": (0.95, 1, 0)])
        let directory = LastFMFixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SoundService(directory: directory, transport: mock)
        await service.setPacing(.milliseconds(1))
        let round = await service.enrich(snapshot: snapshot)
        // "Eden" and its live recording are one song, its sound on both;
        // "Moans" (2023) is not in AcousticBrainz, nor is "Glass".
        XCTAssertEqual(round.profiles["1"], SoundProfile(acoustic: 0.95, relaxed: 1, danceable: 0))
        XCTAssertEqual(round.profiles["2"], round.profiles["1"])
        XCTAssertNil(round.profiles["3"])
        XCTAssertFalse(round.more)
        // With the album first, then without it for the one not found.
        XCTAssertEqual(mock.asked.filter { $0.contains("acrr-lookup") }.count, 1)
        XCTAssertEqual(mock.asked.filter { $0.contains("acr-lookup") }.count, 1)

        // Another launch: from disk, nothing asked, misses too.
        let quiet = Mock(recordings: [:], sound: [:])
        let again = SoundService(directory: directory, transport: quiet)
        let kept = await again.enrich(snapshot: snapshot)
        XCTAssertEqual(kept.profiles, round.profiles)
        XCTAssertTrue(quiet.asked.isEmpty)
    }

    func testSoundServiceStopsQuietlyAndKeepsNothingUnasked() async throws {
        let her = ArtistRef(id: "h", name: "Hania Rani")
        let tracks = [Track(id: "1", name: "Eden", albumID: "a", albumName: "Esja", artists: [her], albumArtist: her)]
        let snapshot = LibrarySnapshot(tracks: tracks)
        let mock = Mock(recordings: ["Hania Rani|Eden": "r-eden"], sound: ["r-eden": (0.95, 1, 0)])
        mock.down = true
        let directory = LastFMFixtures.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = SoundService(directory: directory, transport: mock)
        await service.setPacing(.milliseconds(1))
        let first = await service.enrich(snapshot: snapshot)
        XCTAssertTrue(first.profiles.isEmpty)
        XCTAssertFalse(first.more)
        mock.down = false
        let second = await service.enrich(snapshot: snapshot)
        XCTAssertEqual(second.profiles["1"]?.acoustic, 0.95)
    }
}
