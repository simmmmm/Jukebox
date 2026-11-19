// Last.fm's scrobbles for the clock (docs/RADIO.md, "Scrobbles"): the
// answer read (the song playing now, without a date, left out), a username
// checked as Settings checks it, the plays fetched in pages, matched to
// the library, kept on disk and asked again only for what is newer; and
// what weeks of them do for a listener whose device is new. Never the
// network: the mock answers in Last.fm's documented shape. Prints
// RADIO-EVAL lines.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class LastFMScrobblesTests: XCTestCase {
    typealias Listener = RadioClockListener

    static func line(_ text: String) { print("RADIO-EVAL " + text) }

    var directories: [URL] = []

    override func tearDown() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
        super.tearDown()
    }

    func service(_ mock: LastFMMockTransport?, user: String?, directory: URL? = nil,
                 now: Date) async -> (SimilarityService, URL) {
        let directory = directory ?? LastFMFixtures.directory()
        directories.append(directory)
        let service = SimilarityService(directory: directory, lastFM: mock.map { LastFMClient(apiKey: "key", transport: $0) },
                                        user: user)
        await service.setPacing(minimumInterval: .milliseconds(1), backoff: .milliseconds(5))
        await service.setDate { now }
        return (service, directory)
    }

    static let someone = "a-listener"
    static let start = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: The answer, and Settings' check

    func testRecentTracks() async throws {
        let plays = (0..<3).map { k in
            LastFMClient.Scrobble(artist: "Velvet Static", title: "Song \(k)", date: Self.start.addingTimeInterval(Double(k) * 300))
        }
        let body = LastFMFixtures.recentTracks(Self.someone, plays, page: 1, pages: 4, total: 700,
                                               nowPlaying: ("Velvet Static", "Playing Now"))
        let mock = LastFMMockTransport { _ in LastFMFixtures.respond(200, body) }
        let answer = try await LastFMClient(apiKey: "key", transport: mock)
            .recentTracks(user: Self.someone, from: Self.start, page: 2)
        XCTAssertEqual(answer.scrobbles, plays)
        XCTAssertEqual(answer.pages, 4)
        let asked = try XCTUnwrap(mock.requests.first?.asked)
        XCTAssertEqual(asked.method, "user.getrecenttracks")
        XCTAssertEqual(asked.query["user"], Self.someone)
        XCTAssertEqual(asked.query["page"], "2")
        XCTAssertEqual(asked.query["limit"], "200")
        XCTAssertEqual(asked.query["from"], "1790000000")
    }

    func testValidateUser() async {
        func check(_ body: String, status: Int = 200) async -> LastFMClient.UserCheck {
            await LastFMClient(apiKey: "key", transport: LastFMMockTransport { _ in LastFMFixtures.respond(status, body) })
                .validateUser(Self.someone)
        }
        let some = await check(LastFMFixtures.recentTracks(Self.someone, [], page: 1, pages: 1, total: 0))
        XCTAssertEqual(some, .accepted)
        let unknown = await check(LastFMFixtures.userNotFound)
        XCTAssertEqual(unknown, .unknown)
        let hidden = await check(LastFMFixtures.hiddenUser)
        XCTAssertEqual(hidden, .hidden)
        let badKey = await check(LastFMFixtures.invalidKey, status: 403)
        XCTAssertEqual(badKey, .refusedKey)
        let down = await check(LastFMFixtures.operationFailed)
        XCTAssertEqual(down, .unreachable)
        let offline = await LastFMClient(apiKey: "key", transport: LastFMMockTransport { _ in throw URLError(.notConnectedToInternet) })
            .validateUser(Self.someone)
        XCTAssertEqual(offline, .unreachable)
        let blank = await LastFMClient(apiKey: "key", transport: LastFMMockTransport { _ in fatalError("not asked") })
            .validateUser("two words")
        XCTAssertEqual(blank, .unknown)
        XCTAssertEqual(LastFMClient.UserCheck.hidden.problem, "This listener keeps their plays private on Last.fm")
    }

    // MARK: The service

    func testScrobblesFetchedMatchedAndKept() async throws {
        let snapshot = LastFMServiceTests.snapshot
        let mine = Array(snapshot.tracks.prefix(250))
        var knowledge = LastFMKnowledge()
        // 250 library songs, spelt as Last.fm might, and 20 not in the library.
        var plays = mine.enumerated().map { k, t in
            LastFMClient.Scrobble(artist: (t.albumArtist?.name ?? "").lowercased(),
                                  title: k % 5 == 0 ? t.name + " (Remastered 2011)" : t.name,
                                  date: Self.start.addingTimeInterval(Double(k) * 600))
        }
        plays += (0..<20).map { k in
            LastFMClient.Scrobble(artist: "Somebody Else", title: "Song \(k)", date: Self.start.addingTimeInterval(Double(k) * 7))
        }
        knowledge.scrobbles[Self.someone] = plays
        knowledge.nowPlaying[Self.someone] = ("Velvet Static", "Playing Now")
        let now = Self.start.addingTimeInterval(5 * 86_400)
        let mock = LastFMMockTransport(knowledge)
        let (service, directory) = await self.service(mock, user: Self.someone, now: now)

        let history = await service.scrobbles(for: snapshot)
        XCTAssertEqual(mock.count, 2) // 270 plays, 200 a page
        // Every play the library has the song of, however Last.fm spelt it.
        let expected = plays.compactMap { snapshot.match(artist: $0.artist, title: $0.title)?.id }
        XCTAssertGreaterThanOrEqual(expected.count, 200)
        XCTAssertEqual(history.events.map(\.trackID).sorted(), expected.sorted())
        XCTAssertEqual(history.events.map(\.date), history.events.map(\.date).sorted())
        XCTAssertTrue(history.events.allSatisfy { $0.outcome == .completed })

        // Another launch, soon after: from disk, nothing asked.
        let quiet = LastFMMockTransport(knowledge)
        let (again, _) = await self.service(quiet, user: Self.someone, directory: directory, now: now.addingTimeInterval(3600))
        let kept = await again.scrobbles(for: snapshot)
        XCTAssertEqual(quiet.count, 0)
        XCTAssertEqual(kept.events, history.events)

        // Later: only what is newer than the newest kept.
        let later = LastFMMockTransport(knowledge)
        let (third, _) = await self.service(later, user: Self.someone, directory: directory, now: now.addingTimeInterval(86_400))
        let same = await third.scrobbles(for: snapshot)
        XCTAssertEqual(later.count, 1)
        let newest = Int(plays.map(\.date).max()!.timeIntervalSince1970)
        XCTAssertEqual(later.requests.first?.asked.query["from"], String(newest + 1))
        XCTAssertEqual(same.events, history.events)

        // Another name: another listener, asked anew; none known: nothing.
        let other = LastFMMockTransport(knowledge)
        let (fourth, _) = await self.service(other, user: "somebody-new", directory: directory, now: now.addingTimeInterval(3600))
        let nobody = await fourth.scrobbles(for: snapshot)
        XCTAssertEqual(other.count, 1)
        XCTAssertTrue(nobody.events.isEmpty)
    }

    func testWithoutANameNothingChanges() async {
        let snapshot = LastFMServiceTests.snapshot
        let mock = LastFMMockTransport { _ in fatalError("not asked") }
        for user in [nil, "", "  "] as [String?] {
            let (service, _) = await self.service(mock, user: user, now: Self.start)
            let history = await service.scrobbles(for: snapshot)
            XCTAssertTrue(history.events.isEmpty)
        }
        // A key but no Last.fm: nothing either.
        let (keyless, _) = await self.service(nil, user: Self.someone, now: Self.start)
        let none = await keyless.scrobbles(for: snapshot)
        XCTAssertTrue(none.events.isEmpty)
        XCTAssertEqual(mock.count, 0)

        // No scrobbles: the taste exactly as without them.
        let w = RadioClockTests.world
        let listener = Listener(library: w.library, weeks: 2, pattern: true)
        let now = RadioClockTests.tuesdayMorning
        let plain = TasteData(snapshot: w.snapshot, history: listener.history, now: now, calendar: Listener.calendar)
        let empty = TasteData(snapshot: w.snapshot, history: listener.history, scrobbles: ListeningHistory(),
                              now: now, calendar: Listener.calendar)
        XCTAssertEqual(plain.genreLift, empty.genreLift)
        XCTAssertEqual(plain.artistLift, empty.artistLift)
        XCTAssertEqual(plain.trackAffinity, empty.trackAffinity)
        XCTAssertEqual(plain.timeConfidence, empty.timeConfidence)
        // Scrobbles no older than this device's first event: as without.
        let first = listener.history.events[0].date
        let overlapping = ListeningHistory(events: listener.history.events.filter { $0.date >= first })
        let late = TasteData(snapshot: w.snapshot, history: listener.history, scrobbles: overlapping,
                             now: now, calendar: Listener.calendar)
        XCTAssertEqual(plain.genreLift, late.genreLift)
        XCTAssertEqual(plain.timeConfidence, late.timeConfidence)
    }

    // MARK: What it does, measured

    /// The listener of RadioClockTests: the newest `deviceDays` on this
    /// device, the weeks before as Last.fm scrobbled them (what was heard,
    /// not what was skipped), fetched through the service from the mock.
    /// Some titles as a remaster, some plays of songs not in the library.
    func split(_ listener: Listener, deviceDays: Double, now: Date) async -> (device: ListeningHistory, scrobbles: ListeningHistory, matched: Double) {
        let w = RadioClockTests.world
        let cut = Listener.end.addingTimeInterval(-deviceDays * 86_400)
        let device = ListeningHistory(events: listener.history.events.filter { $0.date >= cut })
        var plays: [LastFMClient.Scrobble] = []
        for (k, event) in listener.history.events.enumerated() where event.date < cut && event.outcome == .completed {
            guard let track = w.snapshot.track(id: event.trackID) else { continue }
            let title = k % 7 == 0 ? track.name + " - Remastered" : track.name
            plays.append(.init(artist: track.albumArtist?.name ?? "", title: title,
                               date: Date(timeIntervalSince1970: event.date.timeIntervalSince1970.rounded(.down))))
            if k % 25 == 0 { plays.append(.init(artist: "Not In The Library", title: "Song \(k)", date: event.date.addingTimeInterval(-90))) }
        }
        var knowledge = LastFMKnowledge()
        knowledge.scrobbles[Self.someone] = plays
        let (service, _) = await self.service(LastFMMockTransport(knowledge), user: Self.someone, now: now)
        let scrobbles = await service.scrobbles(for: w.snapshot)
        return (device, scrobbles, Double(scrobbles.events.count) / Double(max(1, plays.count)))
    }

    struct Seen {
        var share = 0.0
        var lambda = 0.0
        var reasons = 0
        var fact = "none"
    }

    static func yourStation(_ device: ListeningHistory, _ scrobbles: ListeningHistory, at now: Date, cluster: Int,
                            clock: Bool = true, weight: Double = TasteData.scrobbleWeight) -> (Seen, RadioClockTests.Shares) {
        let w = RadioClockTests.world
        let data = TasteData(snapshot: w.snapshot, history: device, scrobbles: scrobbles, now: now,
                             calendar: Listener.calendar, timeAware: clock, scrobbleWeight: weight)
        let taste = TasteProfile(data: data)
        var s = RadioClockTests.Shares()
        for run in 0..<20 {
            var session = RadioSession(station: Station(seed: .personal, snapshot: w.snapshot), snapshot: w.snapshot,
                                       taste: taste, graph: w.graph, randomSeed: UInt64(100 + run))
            for pick in session.next(30) {
                s.picks += 1
                if let key = w.snapshot.primaryArtistKey(of: pick.track), let c = w.library.clusterOfArtist[key] { s.cluster[c] += 1 }
                if case .timeOfDay = pick.reason { s.timeReasons += 1 }
            }
        }
        s.cluster = s.cluster.map { $0 / Double(s.picks) }
        return (Seen(share: s.cluster[cluster], lambda: data.timeConfidence, reasons: s.timeReasons,
                     fact: taste.timeFact?.text ?? "none"), s)
    }

    static func describe(_ s: Seen) -> String {
        String(format: "%.3f (λ %.2f, \"Often on\" %d, fact: %@)", s.share, s.lambda, s.reasons, s.fact)
    }

    func testScrobblesAsAColdStart() async {
        let w = RadioClockTests.world
        let listener = Listener(library: w.library, weeks: 8, pattern: true)
        let none = ListeningHistory()
        let cases: [(String, Date, Int)] = [("Tuesday 08:00, Jazz", RadioClockTests.tuesdayMorning, 2),
                                            ("Saturday 23:00, Electronic", RadioClockTests.saturdayNight, 1)]
        for (name, now, cluster) in cases {
            let (device, scrobbles, matched) = await split(listener, deviceDays: 7, now: now)
            let blind = Self.yourStation(device, none, at: now, cluster: cluster, clock: false).0
            let alone = Self.yourStation(device, none, at: now, cluster: cluster).0
            let all = Self.yourStation(listener.history, none, at: now, cluster: cluster).0
            var swept: [String] = []
            var chosen = Seen()
            for weight in [0.25, 0.5, 1.0] {
                let s = Self.yourStation(device, scrobbles, at: now, cluster: cluster, weight: weight).0
                if weight == TasteData.scrobbleWeight { chosen = s }
                swept.append(String(format: "at %.2f ", weight) + Self.describe(s))
            }
            Self.line("scrobbles: \(name): \(scrobbles.events.count) scrobbles matched (\(String(format: "%.2f", matched)) of those sent), 7 days on this device; time-blind \(String(format: "%.3f", blind.share)); the device alone \(Self.describe(alone)); with the scrobbles \(swept.joined(separator: "; ")); all 8 weeks on the device \(Self.describe(all))")
            XCTAssertGreaterThan(chosen.share, alone.share, name)
            XCTAssertGreaterThan(chosen.lambda, alone.lambda, name)
            XCTAssertGreaterThan(matched, 0.9)
        }

        // At an hour with no pattern, the clock with the scrobbles against
        // the station time-blind.
        let now = RadioClockTests.wednesdayAfternoon
        let (device, scrobbles, _) = await split(listener, deviceDays: 7, now: now)
        let blind = Self.yourStation(device, scrobbles, at: now, cluster: 2, clock: false).1
        let timed = Self.yourStation(device, scrobbles, at: now, cluster: 2).1
        let d = RadioClockTests.maxDifference(blind, timed)
        Self.line(String(format: "scrobbles: Wednesday 15:00, 7 days on this device and the scrobbles: largest change of a cluster's share %.3f; \"Often on\" %d", d, timed.timeReasons))
        XCTAssertLessThanOrEqual(d, 0.03)
        XCTAssertEqual(timed.timeReasons, 0)
    }

    func testScrobblesOfAListenerWithNoPattern() async {
        let w = RadioClockTests.world
        let listener = Listener(library: w.library, weeks: 8, pattern: false)
        var worst = 0.0, reasons = 0, facts = 0
        for day in [27, 31] {
            for hour in stride(from: 0, to: 24, by: 3) {
                let now = Listener.at(day: day, hour: Double(hour))
                let (device, scrobbles, _) = await split(listener, deviceDays: 7, now: now)
                let blind = Self.yourStation(device, scrobbles, at: now, cluster: 0, clock: false).1
                let (seen, timed) = Self.yourStation(device, scrobbles, at: now, cluster: 0)
                worst = max(worst, RadioClockTests.maxDifference(blind, timed))
                reasons += timed.timeReasons
                if seen.fact != "none" { facts += 1 }
            }
        }
        Self.line(String(format: "scrobbles: a listener with no pattern, 7 days on this device and 7 weeks of scrobbles, Tuesday and Saturday every 3 hours: worst change of a cluster's share %.3f; \"Often on\" %d; facts %d", worst, reasons, facts))
        XCTAssertLessThanOrEqual(worst, 0.03)
        XCTAssertEqual(reasons, 0)
        XCTAssertEqual(facts, 0)
    }
}
