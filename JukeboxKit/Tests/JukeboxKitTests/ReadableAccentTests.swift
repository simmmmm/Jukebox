// CoverAccent.readable on the app's own grounds (Tokens.swift's, by day and
// by night): every accent it gives reads 4.5:1 on each and with its words
// on it, keeps its hue, and what cannot keeps the brand's.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Artwork: the cover's accent, readable everywhere")
struct ReadableAccentTests {
    // Tokens.swift's grounds: ground, raised, raisedLighter, lifted, notice,
    // field; by night Cabinet too (the room).
    static let dayGrounds: [UInt32] = [0xF6F3EE, 0xECE7DF, 0xF1EDE6, 0xFBF9F5, 0xF6E6D1, 0xFFFFFF]
    static let nightGrounds: [UInt32] = [0x121110, 0x1B1918, 0x242120, 0x242120, 0x2E2517, 0x252423, 0x1E0A07]

    static let day = AccentGrounds(grounds: dayGrounds.map(AccentColor.init(hex:)), onAccent: AccentColor(hex: 0xFFFFFF),
                                   quietGround: AccentColor(hex: 0xECE7DF), quietTints: [0.12, 0.18, 0.24])
    static let night = AccentGrounds(grounds: nightGrounds.map(AccentColor.init(hex:)), onAccent: AccentColor(hex: 0x2A1505),
                                     quietGround: AccentColor(hex: 0x2E2517), quietTints: [0.12, 0.18, 0.24])

    func hue(_ color: AccentColor) -> Double {
        let lab = CoverAccent.oklab(red: CoverAccent.linear(color.red), green: CoverAccent.linear(color.green),
                                    blue: CoverAccent.linear(color.blue))
        return CoverAccent.degrees(atan2(lab.b, lab.a))
    }

    /// Every promise: 4.5:1 on each ground and with its words, the quiet
    /// word 4.5:1 on its tint at rest, hovered and pressed, the hue kept.
    func check(_ name: String, _ cover: AccentColor) -> (day: ReadableAccent, night: ReadableAccent)? {
        guard let day = CoverAccent.readable(cover, on: Self.day), let night = CoverAccent.readable(cover, on: Self.night) else {
            return nil
        }
        for (found, grounds) in [(day, Self.day), (night, Self.night)] {
            for ground in grounds.grounds + [grounds.onAccent] {
                #expect(found.accent.contrast(with: ground) >= 4.5, "\(name): \(String(found.accent.hex, radix: 16)) on \(String(ground.hex, radix: 16))")
            }
            for tint in grounds.quietTints {
                let under = found.accent.over(grounds.quietGround, opacity: tint)
                #expect(found.quietInk.contrast(with: under) >= 4.5, "\(name): quiet \(String(found.quietInk.hex, radix: 16)) at \(tint)")
            }
            #expect(CoverAccent.angle(hue(found.accent), from: hue(cover)) < 4, "\(name): hue moved")
        }
        return (day, night)
    }

    func accent(_ rgb: (Int, Int, Int)) -> AccentColor? {
        var bytes: [UInt8] = []
        for _ in 0..<(32 * 32) { bytes += [UInt8(rgb.0), UInt8(rgb.1), UInt8(rgb.2), 255] }
        return CoverAccent.accent(rgba: bytes, width: 32, height: 32)
    }

    @Test("Copper and Glow are the brand's: by day Copper as it is, by night Glow as it is")
    func brand() throws {
        let day = try #require(CoverAccent.readable(AccentColor(hex: 0xA84A17), on: Self.day))
        #expect(day.accent.hex == 0xA84A17)
        let night = try #require(CoverAccent.readable(.glow, on: Self.night))
        #expect(night.accent.hex == 0xFFB54D)
        #expect(night.quietInk.hex == 0xFFB54D)
    }

    @Test("Real covers: yellow, orange, teal, purple, navy, a pale pastel, CoverAccent's own")
    func covers() throws {
        let cases: [(String, (Int, Int, Int))] = [
            ("yellow", (240, 200, 20)),
            ("orange", (230, 120, 30)),
            ("teal", (20, 140, 140)),
            ("purple", (110, 50, 160)),
            ("navy", (20, 30, 90)),
            ("pale pastel", (225, 185, 210)),
            ("red", (176, 58, 46)),
            ("green", (70, 150, 80)),
        ]
        for (name, rgb) in cases {
            let cover = try #require(accent(rgb), "\(name): no accent")
            let found = try #require(check(name, cover), "\(name): fell back")
            // By night CoverAccent's own already reads: it stays.
            #expect(found.night.accent.hex == cover.hex, "\(name): night moved")
        }
    }

    @Test("Every hue round the wheel keeps its own, made readable")
    func wheel() {
        for step in 0..<36 {
            let (r, g, b) = CoverAccentTests.rgb(hue: Double(step) * 10, saturation: 0.8, value: 0.8)
            guard let cover = accent((r, g, b)) else {
                Issue.record("hue \(step * 10): nil")
                continue
            }
            #expect(check("hue \(step * 10)", cover) != nil, "hue \(step * 10) fell back")
        }
    }

    @Test("Yellow by day is mustard, still yellow's hue and more than half its chroma")
    func yellow() throws {
        let cover = try #require(accent((240, 200, 20)))
        let found = try #require(check("yellow", cover))
        // Darker, so it reads on paper: under Copper's 0.2 luminance.
        #expect(found.day.accent.luminance < 0.2)
        let channels = [found.day.accent.red, found.day.accent.green, found.day.accent.blue]
        #expect(found.day.accent.red > found.day.accent.blue + 0.2, "\(channels)")
    }

    @Test("Mid grey-ish and a pale pastel as they are, with all but no chroma: the brand's (nil)")
    func fallsBack() {
        #expect(CoverAccent.readable(AccentColor(hex: 0x8A8F86), on: Self.day) == nil)
        #expect(CoverAccent.readable(AccentColor(hex: 0xF4ECEE), on: Self.day) == nil)
    }
}
