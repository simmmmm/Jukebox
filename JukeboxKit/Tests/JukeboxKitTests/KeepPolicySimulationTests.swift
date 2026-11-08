// The keep measured (docs/OFFLINE.md, "Half-life and margin", "On the test
// server"): a made-up listener over four months to choose the half-life and
// the margin by what they cost (downloads a day) and give (the share of the
// next day's plays already on the phone); one more play and one more day,
// to see how many songs a small change trades; the test server's library at
// 1 GB; and the time a plan takes for a large library. Lines starting
// "KEEP-MEASURE" are the measurements in the doc.
//
// The listener is a model, not a person: what it shows is how the choices
// compare, not what a real phone will hold.

import Foundation
import Testing
@testable import JukeboxKit

struct KeepSimulation {
    struct Result {
        var downloadsPerDay = 0.0
        var mostDownloads = 0
        var hitRate = 0.0
        var oracleHitRate = 0.0
    }

    /// Where a run ended: the library as the server then had it, the
    /// history, what the phone held.
    struct State {
        var tracks: [Track]
        var history: ListeningHistory
        var manifest: OfflineManifest
        var now: Date
    }

    static let start = Date(timeIntervalSinceReferenceDate: 815_800_000)
    static let limit: Int64 = 1_000_000_000

    /// 2 000 songs of 150–330 s. The listener has a core of 30 songs that
    /// stay (favourites on the server) and a rotation of 150 that turns
    /// over, two songs a day; 30 plays a day, three in four from the core
    /// and rotation (by rank, Zipf 0.8), the rest anywhere in the library
    /// (the radio, shuffle). The keep runs at the end of each day, at
    /// .high, 1 GB (about 128 songs of 4 minutes). The first 30 days are
    /// not counted.
    static func run(_ tuning: KeepPolicy.Tuning, seed: UInt64, days: Int = 120, warmUp: Int = 30) -> (Result, State) {
        var random = SplitMix64(seed: seed)
        let count = 2_000
        var tracks = (0..<count).map { i in
            Track(id: String(format: "s%04d", i), name: "Song \(i)", duration: 150 + random.nextUnit() * 180)
        }
        var order = Array(0..<count)
        order.shuffle(using: &random)
        let core = Array(order[0..<30])
        var rotation = Array(order[30..<180])
        for i in core { tracks[i].isFavorite = true }
        var history = ListeningHistory()
        var manifest = OfflineManifest()
        var result = Result()
        var downloads: [Int] = []
        var plays = 0, hits = 0, oracleHits = 0

        func weight(rank: Int) -> Double { 1 / pow(Double(rank + 1), 0.8) }

        for day in 0..<days {
            let dayStart = start.addingTimeInterval(Double(day) * 86_400)
            // The listener's songs by how much they are played: the core and
            // the rotation, interleaved so the core is near the top.
            var ranked: [Int] = []
            var c = 0, r = 0
            while c < core.count || r < rotation.count {
                if c < core.count { ranked.append(core[c]); c += 1 }
                for _ in 0..<5 where r < rotation.count { ranked.append(rotation[r]); r += 1 }
            }
            let weights = ranked.indices.map { weight(rank: $0) }
            let total = weights.reduce(0, +)

            // What a phone that knew the listener would hold: their top songs
            // that fit. The ceiling.
            var oracle = Set<Int>()
            var room = limit
            for i in ranked {
                let bytes = KeepPolicy.estimatedBytes(of: tracks[i], quality: .high)
                if bytes <= room { oracle.insert(i); room -= bytes }
            }

            for k in 0..<30 {
                let date = dayStart.addingTimeInterval(Double(k) * 1_800 + 8 * 3_600)
                let fromRotation = random.nextUnit() < 0.75
                let i: Int
                if fromRotation {
                    var x = random.nextUnit() * total
                    var pick = ranked.last!
                    for (n, w) in weights.enumerated() {
                        x -= w
                        if x <= 0 { pick = ranked[n]; break }
                    }
                    i = pick
                } else {
                    i = Int(random.nextUnit() * Double(count)) % count
                }
                let u = random.nextUnit()
                let outcome: PlayOutcome = fromRotation
                    ? (u < 0.85 ? .completed : u < 0.95 ? .partial : .skipped)
                    : (u < 0.4 ? .completed : u < 0.6 ? .partial : .skipped)
                if day >= warmUp {
                    plays += 1
                    if manifest.has(tracks[i].id) { hits += 1 }
                    if oracle.contains(i) { oracleHits += 1 }
                }
                history.append(PlayEvent(trackID: tracks[i].id, date: date, listened: 200,
                                         duration: tracks[i].duration, outcome: outcome))
                if outcome != .skipped {
                    tracks[i].playCount += 1
                    tracks[i].lastPlayed = date
                }
                if fromRotation, outcome == .completed, random.nextUnit() < 0.03 {
                    history.append(PlayEvent(trackID: tracks[i].id, date: date.addingTimeInterval(60), listened: 0,
                                             duration: tracks[i].duration, outcome: .liked))
                }
            }

            // The rotation turns over: two songs leave, two come in.
            for _ in 0..<2 {
                rotation.remove(at: Int(random.nextUnit() * Double(rotation.count)) % rotation.count)
                var fresh = Int(random.nextUnit() * Double(count)) % count
                while core.contains(fresh) || rotation.contains(fresh) { fresh = (fresh + 1) % count }
                rotation.insert(fresh, at: Int(random.nextUnit() * Double(rotation.count + 1)) % (rotation.count + 1))
            }

            // The keep, at the end of the day.
            let now = dayStart.addingTimeInterval(23 * 3_600)
            let plan = KeepPolicy.plan(tracks: tracks, history: history, manifest: manifest, limitBytes: limit,
                                       quality: .high, now: now, tuning: tuning)
            _ = manifest.removeReason(.kept, from: plan.remove)
            let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            for id in plan.download {
                manifest.add(OfflineFile(trackID: id, fileName: "\(id).m4a",
                                         bytes: KeepPolicy.estimatedBytes(of: byID[id]!, quality: .high),
                                         savedAt: now, quality: .high, reasons: [.kept]))
            }
            if day >= warmUp { downloads.append(plan.download.count) }
        }
        result.downloadsPerDay = Double(downloads.reduce(0, +)) / Double(max(1, downloads.count))
        result.mostDownloads = downloads.max() ?? 0
        result.hitRate = Double(hits) / Double(max(1, plays))
        result.oracleHitRate = Double(oracleHits) / Double(max(1, plays))
        let state = State(tracks: tracks, history: history, manifest: manifest,
                          now: start.addingTimeInterval(Double(days) * 86_400 - 3_600))
        return (result, state)
    }

    /// The mean of three listeners.
    static func mean(_ tuning: KeepPolicy.Tuning) -> Result {
        let runs = (UInt64(1)...3).map { run(tuning, seed: $0).0 }
        var mean = Result()
        mean.downloadsPerDay = runs.map(\.downloadsPerDay).reduce(0, +) / 3
        mean.mostDownloads = runs.map(\.mostDownloads).max() ?? 0
        mean.hitRate = runs.map(\.hitRate).reduce(0, +) / 3
        mean.oracleHitRate = runs.map(\.oracleHitRate).reduce(0, +) / 3
        return mean
    }
}

@Suite("Keep: measured", .serialized)
struct KeepPolicySimulationTests {
    static func measure(_ line: String) { print("KEEP-MEASURE \(line)") }

    static func row(_ label: String, _ r: KeepSimulation.Result) -> String {
        String(format: "%@: %.1f downloads a day (most %ld), %.1f%% of plays on the phone (a phone that knew: %.1f%%)",
               label, r.downloadsPerDay, r.mostDownloads, r.hitRate * 100, r.oracleHitRate * 100)
    }

    @Test("Half-life and margin: downloads a day against plays already on the phone")
    func halfLifeAndMargin() {
        var grid: [(days: Double, bonus: Double, result: KeepSimulation.Result)] = []
        for days in [7.0, 14, 21, 30] {
            for bonus in [1.0, 1.5, 2.0, 3.0] {
                let r = KeepSimulation.mean(.init(halfLifeDays: days, incumbentBonus: bonus))
                grid.append((days, bonus, r))
                Self.measure(Self.row(String(format: "half-life %2.0f days, margin %.1f", days, bonus), r))
            }
        }
        let chosen = KeepPolicy.Tuning.standard
        let standard = grid.first { $0.days == chosen.halfLifeDays && $0.bonus == chosen.incumbentBonus }!.result
        // Nothing in the grid holds more of the next day's plays with
        // fewer downloads.
        for point in grid {
            #expect(!(point.result.hitRate > standard.hitRate && point.result.downloadsPerDay < standard.downloadsPerDay),
                    "\(point.days) days, margin \(point.bonus)")
        }
        // The margin is cheap: against none at the same half-life, it
        // fetches at most 60% as much for at most a point and a half fewer
        // plays held (measured: 49%, 1.0 points).
        let none = grid.first { $0.days == chosen.halfLifeDays && $0.bonus == 1 }!.result
        #expect(standard.downloadsPerDay < none.downloadsPerDay * 0.6)
        #expect(standard.hitRate > none.hitRate - 0.015)
    }

    @Test("A small change trades few songs: one more play, one more day")
    func smallChanges() {
        for bonus in [1.0, KeepPolicy.Tuning.standard.incumbentBonus, 2.0] {
            var tuning = KeepPolicy.Tuning.standard
            tuning.incumbentBonus = bonus
            let (_, state) = KeepSimulation.run(tuning, seed: 4, days: 90)
            func plan(_ history: ListeningHistory, _ tracks: [Track], now: Date) -> KeepPlan {
                KeepPolicy.plan(tracks: tracks, history: history, manifest: state.manifest,
                                limitBytes: KeepSimulation.limit, quality: .high, now: now, tuning: tuning)
            }
            // A day with nothing played: only time moves.
            let quiet = plan(state.history, state.tracks, now: state.now.addingTimeInterval(86_400))
            let nextDay = quiet.download.count + quiet.remove.count
            // One more completed play of a song the phone does not have.
            var random = SplitMix64(seed: 11)
            var total = 0, changed = 0, most = (fetched: 0, letGo: 0)
            let tries = 200
            let outside = state.tracks.indices.filter { !state.manifest.has(state.tracks[$0].id) }
            for _ in 0..<tries {
                let i = outside[Int(random.nextUnit() * Double(outside.count)) % outside.count]
                var history = state.history
                var tracks = state.tracks
                let date = state.now.addingTimeInterval(600)
                history.append(PlayEvent(trackID: tracks[i].id, date: date, listened: 200,
                                         duration: tracks[i].duration, outcome: .completed))
                tracks[i].playCount += 1
                tracks[i].lastPlayed = date
                let p = plan(history, tracks, now: date)
                let n = p.download.count + p.remove.count
                total += n
                if n > 0 { changed += 1 }
                if n > most.fetched + most.letGo { most = (p.download.count, p.remove.count) }
            }
            Self.measure(String(format: "margin %.1f: after 90 days, a day with no plays trades %ld songs; one more play of a song not kept changes the keep in %ld of %ld tries, %.2f songs on average, at most %ld fetched and %ld let go",
                                bonus, nextDay, changed, tries, Double(total) / Double(tries), most.fetched, most.letGo))
            if bonus == KeepPolicy.Tuning.standard.incumbentBonus {
                // Measured at most 2 fetched and 1 let go: the song played
                // comes in, the room it needs lets go of one, and what is left
                // over takes a shorter one from further down. Four allows a
                // long song to push out two.
                #expect(most.fetched + most.letGo <= 4)
                #expect(nextDay <= 2)
            }
        }
    }

    @Test("The test server's library at 1 GB: what the keep holds, from the server alone and after a month")
    func realLibrary() throws {
        let tracks = RadioRealLibraryFixture.tracks
        #expect(tracks.count == 358)
        let now = Date(timeIntervalSinceReferenceDate: 815_800_000)
        let gb: Int64 = 1_000_000_000
        let whole = tracks.reduce(Int64(0)) { $0 + KeepPolicy.estimatedBytes(of: $1, quality: .high) }
        let seconds = tracks.reduce(0) { $0 + $1.duration }
        Self.measure(String(format: "test library: %ld songs, %.0f s, %.1f MB at .high estimated — 1 GB holds every one",
                            tracks.count, seconds, Double(whole) / 1e6))

        // From the server alone: its play counts (10 songs) and favourites (none).
        let fromServer = KeepPolicy.plan(tracks: tracks, history: ListeningHistory(), manifest: OfflineManifest(),
                                         limitBytes: gb, quality: .high, now: now)
        let played = tracks.filter { $0.playCount > 0 || $0.lastPlayed != nil }.count
        Self.measure("test library, empty history, 1 GB at .high: \(fromServer.download.count) songs (the \(played) the server has a play of)")
        #expect(fromServer.download.count == played)
        #expect(fromServer.remove.isEmpty)

        // A month of listening: 20 songs a day, 70% from three artists the
        // listener loves, the rest anywhere, skipped half the time.
        let loved = Set(["Velvet Static", "The Lanterns", "Hexagon Lights"].map(NameKey.artist))
        let theirs = tracks.filter { track in track.primaryArtist.map { loved.contains($0.key) } ?? false }
        var random = SplitMix64(seed: 2026)
        var events: [PlayEvent] = []
        for day in 0..<30 {
            for k in 0..<20 {
                let date = now.addingTimeInterval(Double(day - 30) * 86_400 + Double(k) * 900)
                let mine = random.nextUnit() < 0.7
                let pool = mine ? theirs : tracks
                let track = pool[Int(random.nextUnit() * Double(pool.count)) % pool.count]
                let outcome: PlayOutcome = mine ? (random.nextUnit() < 0.9 ? .completed : .partial)
                    : (random.nextUnit() < 0.5 ? .skipped : .completed)
                events.append(PlayEvent(track: track, date: date, listened: track.duration, outcome: outcome))
            }
        }
        let history = ListeningHistory(events: events)
        let month = KeepPolicy.plan(tracks: tracks, history: history, manifest: OfflineManifest(),
                                    limitBytes: gb, quality: .high, now: now)
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let bytes = month.download.reduce(Int64(0)) { $0 + KeepPolicy.estimatedBytes(of: byID[$1]!, quality: .high) }
        let heard = Set(events.map(\.trackID)).count
        let lovedKept = month.download.filter { id in byID[id]?.primaryArtist.map { loved.contains($0.key) } ?? false }.count
        // The songs heard and not kept: how many were skipped as often as
        // they were heard to the end or partly.
        let kept = Set(month.download)
        let left = Set(events.map(\.trackID)).subtracting(kept)
        let skippedMost = left.filter { id in
            let mine = events.filter { $0.trackID == id }
            return mine.filter { $0.outcome == .skipped }.count >= mine.filter { $0.outcome != .skipped }.count
        }.count
        Self.measure(String(format: "test library, a month (600 plays of %ld songs), 1 GB at .high: %ld songs, %.1f MB; %ld of the %ld by the three loved artists; of the %ld heard and not kept, %ld were skipped at least as often as heard",
                            heard, month.download.count, Double(bytes) / 1e6, lovedKept, theirs.count, left.count, skippedMost))
        // Every loved song the month played is kept, but one skipped more
        // than it was heard (from the 30% heard anywhere).
        let heardLoved = theirs.filter { t in events.contains { $0.trackID == t.id } }.count
        #expect(Double(lovedKept) >= Double(heardLoved) * 0.9)

        // A limit that binds: 2 MB, about ten of these short songs.
        let tight = KeepPolicy.plan(tracks: tracks, history: history, manifest: OfflineManifest(),
                                    limitBytes: 2_000_000, quality: .high, now: now)
        let scores = KeepPolicy.scores(tracks: tracks, history: history, now: now)
        let listing = tight.download.enumerated().map { n, id in
            String(format: "%ld. %@ — %@ (%.2f)", n + 1, byID[id]!.name, byID[id]!.artistLine, scores[id] ?? 0)
        }
        Self.measure("test library, a month, 2 MB at .high: \(listing.joined(separator: "; "))")
        #expect(tight.download.allSatisfy { id in byID[id]?.primaryArtist.map { loved.contains($0.key) } ?? false })

        // What 1 GB holds of real songs, 4 minutes each.
        let song = Track(id: "s", name: "s", duration: 240)
        let perGB = DownloadQuality.allCases.map { q in
            "\(q.rawValue) \(gb / KeepPolicy.estimatedBytes(of: song, quality: q))"
        }
        Self.measure("1 GB holds, of 4-minute songs: \(perGB.joined(separator: ", "))")
    }

    @Test("A large library: 20 000 songs and a full history, planned in well under a second")
    func large() {
        var random = SplitMix64(seed: 5)
        let tracks = (0..<20_000).map { i in
            Track(id: String(format: "t%05d", i), name: "\(i)", duration: 150 + random.nextUnit() * 200,
                  isFavorite: random.nextUnit() < 0.02, playCount: random.nextUnit() < 0.3 ? Int(random.nextUnit() * 40) : 0,
                  lastPlayed: KeepSimulation.start.addingTimeInterval(-random.nextUnit() * 400 * 86_400))
        }
        let events = (0..<ListeningHistory.limit).map { k in
            PlayEvent(trackID: tracks[Int(random.nextUnit() * 3_000)].id,
                      date: KeepSimulation.start.addingTimeInterval(Double(k - ListeningHistory.limit) * 1_200),
                      listened: 200, duration: 240, outcome: random.nextUnit() < 0.8 ? .completed : .skipped)
        }
        let history = ListeningHistory(events: events)
        var manifest = OfflineManifest()
        for track in tracks.prefix(300) {
            manifest.add(OfflineFile(trackID: track.id, fileName: track.id, bytes: 7_000_000, savedAt: KeepSimulation.start,
                                     quality: .high, reasons: [.kept]))
        }
        let clock = ContinuousClock()
        var plan = KeepPlan(download: [], remove: [])
        let took = clock.measure {
            plan = KeepPolicy.plan(tracks: tracks, history: history, manifest: manifest, limitBytes: 4_000_000_000,
                                   quality: .high, now: KeepSimulation.start)
        }
        Self.measure("20 000 songs, 20 000 events, 4 GB: planned in \(took) (\(plan.download.count) to fetch, \(plan.remove.count) to let go)")
        #expect(took < .seconds(1))
    }
}
