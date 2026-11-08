// The automatic keep on made-up histories: the order, the limit, the songs
// someone chose left alone, the margin for what is kept, an empty history.
// What it does over months of listening and on the test server's library:
// KeepPolicySimulationTests.swift.

import Foundation
import Testing
@testable import JukeboxKit

enum KeepFixtures {
    static let now = Date(timeIntervalSinceReferenceDate: 815_800_000)
    /// A 4-minute song at .normal: (128 000 + 3 000) × 240 / 8.
    static let normalSong: Int64 = 3_930_000

    static func track(_ id: ItemID, seconds: TimeInterval = 240, favorite: Bool = false,
                      playCount: Int = 0, lastPlayedDaysAgo: Double? = nil) -> Track {
        Track(id: id, name: id, duration: seconds, isFavorite: favorite, playCount: playCount,
              lastPlayed: lastPlayedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) })
    }

    static func event(_ id: ItemID, _ outcome: PlayOutcome, daysAgo: Double = 0) -> PlayEvent {
        PlayEvent(trackID: id, date: now.addingTimeInterval(-daysAgo * 86_400), listened: 200,
                  duration: 240, outcome: outcome)
    }

    /// `count` events of one outcome, a minute apart, `daysAgo` days back.
    static func events(_ id: ItemID, _ outcome: PlayOutcome, _ count: Int, daysAgo: Double = 0) -> [PlayEvent] {
        (0..<count).map { event(id, outcome, daysAgo: daysAgo + Double($0) / 1_440) }
    }

    static func history(_ events: [PlayEvent]) -> ListeningHistory {
        ListeningHistory(events: events.sorted { $0.date < $1.date })
    }

    static func manifest(kept: [ItemID: Int64] = [:], chosen: [ItemID: (Set<OfflineReason>, Int64)] = [:]) -> OfflineManifest {
        var manifest = OfflineManifest()
        for (id, bytes) in kept {
            manifest.add(OfflineFile(trackID: id, fileName: "\(id).m4a", bytes: bytes, savedAt: now,
                                     quality: .normal, reasons: [.kept]))
        }
        for (id, (reasons, bytes)) in chosen {
            manifest.add(OfflineFile(trackID: id, fileName: "\(id).m4a", bytes: bytes, savedAt: now,
                                     quality: .normal, reasons: reasons))
        }
        return manifest
    }

    static func plan(_ tracks: [Track], _ events: [PlayEvent] = [], manifest: OfflineManifest = OfflineManifest(),
                     limit: Int64 = 1_000_000_000, quality: DownloadQuality = .normal) -> KeepPlan {
        KeepPolicy.plan(tracks: tracks, history: history(events), manifest: manifest, limitBytes: limit,
                        quality: quality, now: now)
    }
}

@Suite("Keep: the automatic keep")
struct KeepPolicyTests {
    typealias F = KeepFixtures

    @Test("Ranked by listening: completed most, partial some; skipped and never-heard songs not fetched")
    func order() {
        let tracks = ["a", "b", "c", "d", "e"].map { F.track($0) }
        let events = F.events("b", .completed, 2, daysAgo: 1) + F.events("a", .completed, 5, daysAgo: 1)
            + F.events("c", .partial, 1, daysAgo: 1) + F.events("d", .skipped, 3, daysAgo: 1)
        let plan = F.plan(tracks, events)
        #expect(plan.download == ["a", "b", "c"])
        #expect(plan.remove.isEmpty)
    }

    @Test("Two weeks' half-life: ten plays four weeks ago beat two today; three then do not beat one today")
    func decay() {
        let tracks = ["x", "y", "z", "w"].map { F.track($0) }
        let events = F.events("x", .completed, 10, daysAgo: 28) + F.events("y", .completed, 2)
            + F.events("z", .completed, 3, daysAgo: 28) + F.events("w", .completed, 1)
        #expect(F.plan(tracks, events).download == ["x", "y", "w", "z"])
        let scores = KeepPolicy.scores(tracks: tracks, history: F.history(events), now: F.now)
        #expect(abs((scores["x"] ?? 0) - 2.5) < 0.01)
        #expect(abs((scores["z"] ?? 0) - 0.75) < 0.01)
    }

    @Test("The limit: estimated sizes for new songs, the real bytes of kept ones")
    func limit() {
        let tracks = ["a", "b", "c", "d"].map { F.track($0) }
        let events = F.events("a", .completed, 4) + F.events("b", .completed, 3)
            + F.events("c", .completed, 2) + F.events("d", .completed, 1)
        // Two 4-minute songs at .normal are 7.86 MB; a third does not fit in 10.
        #expect(F.plan(tracks, events, limit: 10_000_000).download == ["a", "b"])
        // "a" came as its own small file (1 MB): room for two more.
        let held = F.manifest(kept: ["a": 1_000_000])
        let plan = F.plan(tracks, events, manifest: held, limit: 10_000_000)
        #expect(plan.download == ["b", "c"])
        #expect(plan.remove.isEmpty)
    }

    @Test("A long song that does not fit leaves its room to shorter ones")
    func longSong() {
        let tracks = [F.track("suite", seconds: 3_600), F.track("song")]
        let events = F.events("suite", .completed, 5) + F.events("song", .completed, 1)
        #expect(F.plan(tracks, events, limit: 10_000_000).download == ["song"])
    }

    @Test("Chosen songs: in neither list, not counted against the limit")
    func chosen() {
        let tracks = ["a", "b", "c", "d"].map { F.track($0) }
        let events = F.events("a", .completed, 9) + F.events("b", .completed, 8) + F.events("d", .completed, 1)
        let manifest = F.manifest(kept: ["c": F.normalSong],
                                  chosen: ["a": ([.album("al1")], 1_000_000_000),
                                           "b": ([.playlist("p1"), .kept], 900_000_000)])
        let plan = F.plan(tracks, events, manifest: manifest, limit: 5_000_000)
        // "a" and "b" are the most played, and 1.9 GB, but they are the
        // listener's: the 5 MB is for "d"; "c", never heard, goes.
        #expect(plan.download == ["d"])
        #expect(plan.remove == ["c"])
    }

    @Test("The margin: a kept song stays unless one wanted half as much again needs its room")
    func hysteresis() {
        let tracks = [F.track("held"), F.track("new")]
        let held = F.manifest(kept: ["held": F.normalSong])
        let heldPlays = F.events("held", .completed, 2)
        // Room for one. "new" at 2.9 against "held" at 2: not enough.
        let close = heldPlays + F.events("new", .completed, 2) + F.events("new", .partial, 3)
        #expect(F.plan(tracks, close, manifest: held, limit: 4_000_000) == KeepPlan(download: [], remove: []))
        // Without the margin it would trade them.
        let bare = KeepPolicy.plan(tracks: tracks, history: F.history(close), manifest: held, limitBytes: 4_000_000,
                                   quality: .normal, now: F.now, tuning: .init(incumbentBonus: 1))
        #expect(bare == KeepPlan(download: ["new"], remove: ["held"]))
        // At 3.3 it is clearly better: traded.
        let clear = heldPlays + F.events("new", .completed, 3) + F.events("new", .partial, 1)
        #expect(F.plan(tracks, clear, manifest: held, limit: 4_000_000) == KeepPlan(download: ["new"], remove: ["held"]))
    }

    @Test("An empty history: favourites and the server's play counts, a song never played not fetched")
    func serverOnly() {
        let tracks = [
            F.track("once-a-year-ago", playCount: 1, lastPlayedDaysAgo: 365),
            F.track("unplayed"),
            F.track("favourite", favorite: true),
            F.track("ten-plays", playCount: 10, lastPlayedDaysAgo: 1),
            // Played with no count: a play reported without its start.
            F.track("played-no-count", lastPlayedDaysAgo: 3),
        ]
        let plan = F.plan(tracks)
        #expect(plan.download == ["ten-plays", "favourite", "played-no-count", "once-a-year-ago"])
        let scores = KeepPolicy.scores(tracks: tracks, history: ListeningHistory(), now: F.now)
        #expect(abs((scores["ten-plays"] ?? 0) - 2.063) < 0.01)
        #expect(abs((scores["once-a-year-ago"] ?? 0) - 0.177) < 0.01)
        #expect(scores["unplayed"] == 0)
    }

    @Test("A thumbs down left in: let go; a thumbs up after it, or half a year: back")
    func thumbs() {
        let tracks = [F.track("a", favorite: true, playCount: 40, lastPlayedDaysAgo: 10)]
        let held = F.manifest(kept: ["a": F.normalSong])
        let plays = F.events("a", .completed, 6, daysAgo: 20)
        let down = plays + [F.event("a", .disliked, daysAgo: 10)]
        #expect(F.plan(tracks, down, manifest: held) == KeepPlan(download: [], remove: ["a"]))
        #expect(F.plan(tracks, down).download.isEmpty)
        let upAgain = down + [F.event("a", .liked, daysAgo: 2)]
        #expect(F.plan(tracks, upAgain, manifest: held) == KeepPlan(download: [], remove: []))
        let longAgo = F.events("a", .completed, 6, daysAgo: 220) + [F.event("a", .disliked, daysAgo: 200)]
        #expect(F.plan(tracks, longAgo).download == ["a"])
    }

    @Test("Songs that left the library are let go; no library, no plan")
    func library() {
        let held = F.manifest(kept: ["gone": F.normalSong, "here": F.normalSong])
        let tracks = [F.track("here", playCount: 3, lastPlayedDaysAgo: 1)]
        #expect(F.plan(tracks, manifest: held) == KeepPlan(download: [], remove: ["gone"]))
        #expect(F.plan([], F.events("here", .completed, 3), manifest: held) == KeepPlan(download: [], remove: []))
    }

    @Test("No room: every song only the keep holds is let go, the chosen stay")
    func noRoom() {
        let tracks = ["a", "b", "c"].map { F.track($0, playCount: 5, lastPlayedDaysAgo: 1) }
        let held = F.manifest(kept: ["a": 1, "b": 1], chosen: ["c": ([.mix("daily")], 1)])
        #expect(F.plan(tracks, manifest: held, limit: 0) == KeepPlan(download: [], remove: ["a", "b"]))
    }

    @Test("Stable: the same inputs give the same plan, whatever the library's order; ties by id")
    func stable() {
        var random = SplitMix64(seed: 7)
        let tracks = (0..<200).map { i in
            F.track(String(format: "t%03d", i), seconds: 150 + random.nextUnit() * 200,
                    favorite: random.nextUnit() < 0.1, playCount: Int(random.nextUnit() * 6),
                    lastPlayedDaysAgo: random.nextUnit() * 200)
        }
        var events: [PlayEvent] = []
        for _ in 0..<600 {
            let id = tracks[Int(random.nextUnit() * 60)].id
            let outcome: PlayOutcome = [.completed, .completed, .completed, .partial, .skipped, .liked][Int(random.nextUnit() * 6)]
            events.append(F.event(id, outcome, daysAgo: random.nextUnit() * 90))
        }
        let held = F.manifest(kept: Dictionary(uniqueKeysWithValues: tracks.prefix(40).map { ($0.id, Int64(4_000_000)) }))
        let first = F.plan(tracks, events, manifest: held, limit: 200_000_000)
        #expect(!first.download.isEmpty && !first.remove.isEmpty)
        #expect(F.plan(tracks, events, manifest: held, limit: 200_000_000) == first)
        #expect(F.plan(Array(tracks.reversed()), events, manifest: held, limit: 200_000_000) == first)
        var shuffler = SplitMix64(seed: 99)
        #expect(F.plan(tracks.shuffled(using: &shuffler), events, manifest: held, limit: 200_000_000) == first)

        let twins = [F.track("b", playCount: 2, lastPlayedDaysAgo: 1), F.track("a", playCount: 2, lastPlayedDaysAgo: 1)]
        #expect(F.plan(twins, limit: 4_000_000).download == ["a"])
    }

    @Test("Estimated sizes: the quality's rate and 3 kbit/s for the m4a; 900 kbit/s for the original; no length is 4 minutes")
    func estimates() {
        let song = F.track("s")
        #expect(KeepPolicy.estimatedBytes(of: song, quality: .high) == 7_770_000)
        #expect(KeepPolicy.estimatedBytes(of: song, quality: .normal) == 3_930_000)
        #expect(KeepPolicy.estimatedBytes(of: song, quality: .original) == 27_000_000)
        #expect(KeepPolicy.estimatedBytes(of: F.track("n", seconds: 0), quality: .normal) == 3_930_000)
        #expect(KeepPolicy.estimatedBytes(of: F.track("n", seconds: .nan), quality: .high) == 7_770_000)
        // Measured on 12.4: a 240.05 s song came as 7 765 392 bytes at
        // .high and 3 924 627 at .normal; the estimate is within 0.1%.
        let measured = F.track("m", seconds: 240.046)
        #expect(abs(Double(KeepPolicy.estimatedBytes(of: measured, quality: .high)) / 7_765_392 - 1) < 0.001)
        #expect(abs(Double(KeepPolicy.estimatedBytes(of: measured, quality: .normal)) / 3_924_627 - 1) < 0.002)
    }
}
