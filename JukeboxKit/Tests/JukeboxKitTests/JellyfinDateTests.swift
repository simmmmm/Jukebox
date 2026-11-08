// Jellyfin's dates (seven fractional digits, fewer, or none) and ticks.
// The expected times were worked out apart from the parser, with Python's
// datetime.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Jellyfin: dates and ticks")
struct JellyfinDateTests {
    @Test("Every number of fractional digits", arguments: [
        ("2026-11-08T01:26:04.5283094Z", 1_794_101_164.5283094),
        ("2026-11-08T01:26:04.446321Z", 1_794_101_164.446321),
        ("2026-11-08T01:26:04.123Z", 1_794_101_164.123),
        ("2026-11-08T01:26:04.5Z", 1_794_101_164.5),
        ("2026-11-08T01:26:04Z", 1_794_101_164),
        ("2026-11-08T01:26:04.000000000123Z", 1_794_101_164),
        // No zone: UTC, as Jellyfin stores it.
        ("2026-11-08T01:26:04.5283094", 1_794_101_164.5283094),
        ("2026-11-08T01:26:04", 1_794_101_164),
        ("2026-11-08T01:26", 1_794_101_160),
        ("2026-11-08 01:26:04", 1_794_101_164),
        // Zones.
        ("2026-11-08T01:26:04+01:00", 1_794_097_564),
        ("2026-11-08T01:26:04.0000000+01:00", 1_794_097_564),
        ("2026-11-08T01:26:04+0100", 1_794_097_564),
        ("2026-11-08T01:26:04+01", 1_794_097_564),
        ("2026-11-08T00:26:04-01:00", 1_794_101_164),
        // A date alone, a leap day, before 1970.
        ("2016-01-01", 1_451_606_400),
        ("2016-01-01T00:00:00.0000000Z", 1_451_606_400),
        ("2024-02-29T23:59:59Z", 1_709_251_199),
        ("1957-06-01T12:00:00Z", -397_137_600),
        ("2000-03-01T00:00:00Z", 951_868_800),
    ])
    func parses(_ text: String, _ expected: Double) throws {
        let date = try #require(JellyfinDate.parse(text))
        #expect(abs(date.timeIntervalSince1970 - expected) < 0.000_001, "\(text)")
    }

    @Test("Not a date, or Jellyfin's 'never'", arguments: [
        "", "yesterday", "2026-13-01", "2026-02-30T00:00:00Z", "2023-02-29", "2026-11-08T25:00:00Z",
        "2026-11-08T01:60:00Z", "2026-11-08T01:26:04.Z", "2026-11-08T01:26:04ZZ", "2026-11-8",
        "26-11-08", "2026-11-08T01", "2026-11-08T01:26:04+25:00",
        "0001-01-01T00:00:00.0000000Z", "0001-01-01T00:00:00",
    ])
    func rejects(_ text: String) {
        #expect(JellyfinDate.parse(text) == nil, "\(text)")
    }

    @Test("The same as Foundation's calendar, for many dates")
    func agreesWithCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var generator = JellyfinSeededGenerator(seed: 42)
        for _ in 0..<2000 {
            let c = DateComponents(year: Int.random(in: 1900...2100, using: &generator),
                                   month: Int.random(in: 1...12, using: &generator),
                                   day: Int.random(in: 1...28, using: &generator),
                                   hour: Int.random(in: 0...23, using: &generator),
                                   minute: Int.random(in: 0...59, using: &generator),
                                   second: Int.random(in: 0...59, using: &generator))
            let expected = try #require(calendar.date(from: c))
            let text = String(format: "%04ld-%02ld-%02ldT%02ld:%02ld:%02ld.1234567Z",
                              c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
            let parsed = try #require(JellyfinDate.parse(text))
            #expect(abs(parsed.timeIntervalSince1970 - expected.timeIntervalSince1970 - 0.1234567) < 0.000_01, "\(text)")
        }
    }

    @Test("Ticks are 10 000 000 a second")
    func ticks() {
        #expect(JellyfinTicks.seconds(60_000_000) == 6)
        #expect(JellyfinTicks.seconds(2_345_678_901) == 234.5678901)
        #expect(JellyfinTicks.seconds(nil) == nil)
        #expect(JellyfinTicks.seconds(-1) == nil)
        #expect(JellyfinTicks.ticks(seconds: 6) == 60_000_000)
        #expect(JellyfinTicks.ticks(seconds: 0.000_000_15) == 2)
        #expect(JellyfinTicks.ticks(seconds: 187.25) == 1_872_500_000)
        #expect(JellyfinTicks.ticks(seconds: -3) == 0)
        #expect(JellyfinTicks.ticks(seconds: .nan) == 0)
        #expect(JellyfinTicks.ticks(seconds: .infinity) == 0)
    }

    @Test("Parsing is fast enough for a big library")
    func speed() throws {
        let text = "2026-11-08T01:26:04.5283094Z"
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            for _ in 0..<150_000 where JellyfinDate.parse(text) != nil { count += 1 }
        }
        #expect(count == 150_000)
        // 50 000 tracks × 3 dates. Debug build; printed for the report.
        print("JellyfinDate: 150 000 dates parsed in \(elapsed)")
        #expect(elapsed < .seconds(5))
    }
}

/// A small deterministic generator (SplitMix64), so the comparison is the
/// same on every run.
struct JellyfinSeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
