// CoverAccent on made-up covers of 32 by 32: the colours dev/accent.py
// gives for the same pixels (so the sketches show what the app will), the
// second colour where a cover has one and not where it is a speck, a cover
// without colour of its own keeping Glow, and every accent readable on
// Cabinet.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Artwork: the accent from a cover")
struct CoverAccentTests {
    /// A cover drawn by a function of x and y, opaque, as RGBA.
    func cover(_ pixel: (Int, Int) -> (Int, Int, Int)) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<32 {
            for x in 0..<32 {
                let (r, g, b) = pixel(x, y)
                bytes += [UInt8(r), UInt8(g), UInt8(b), 255]
            }
        }
        return bytes
    }

    func accent(_ pixel: (Int, Int) -> (Int, Int, Int)) -> AccentColor? {
        CoverAccent.accent(rgba: cover(pixel), width: 32, height: 32)
    }

    /// "#FF8271" as 8-bit channels.
    func hex(_ color: AccentColor) -> String {
        let channels = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        return channels.map { String(format: "%02X", $0) }.joined()
    }

    /// Within one step of 8 bits of the Python's, channel by channel: the
    /// two round at the end in their own way.
    func same(_ color: AccentColor?, _ expected: String) -> Bool {
        guard let color else { return false }
        let mine = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        let theirs = stride(from: 0, to: 6, by: 2).map { offset -> Int in
            let start = expected.index(expected.startIndex, offsetBy: offset)
            return Int(expected[start..<expected.index(start, offsetBy: 2)], radix: 16) ?? -1
        }
        return zip(mine, theirs).allSatisfy { abs($0 - $1) <= 1 }
    }

    @Test("One colour all over: its hue, at Glow's weight")
    func solid() {
        let found = accent { _, _ in (176, 58, 46) }
        #expect(same(found, "FF8271"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("Red stripes on cream and black: the red, not the average's beige")
    func stripes() {
        let found = accent { x, y in
            switch (x + y) % 8 {
            case 0..<2: (200, 40, 30)
            case 2..<5: (235, 228, 215)
            default: (20, 20, 20)
            }
        }
        #expect(same(found, "FF6857"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("A gradient from teal to blue: the blue end, apart from the teal most of it is")
    func gradient() {
        let found = accent { x, y in (40 + x * 5, 90 + y * 3, 160 - x * 2) }
        #expect(same(found, "92C3FF"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("Purple with an orange band: the orange, the cover's second colour")
    func secondColour() {
        let found = accent { x, _ in x < 26 ? (150, 60, 200) : (240, 170, 40) }
        #expect(same(found, "FDB73B"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("Purple with an orange speck: a speck is not a second colour, the purple")
    func speck() {
        let found = accent { x, y in x < 1 && y < 16 ? (240, 170, 40) : (150, 60, 200) }
        #expect(same(found, "C971FF"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("Black to white, no colour: nil, so the app keeps Glow")
    func grey() {
        #expect(accent { x, _ in (x * 8, x * 8, x * 8) } == nil)
    }

    @Test("A blue spot on grey: under 2% of the cover is no colour of its own, over it is")
    func spot() {
        let small = accent { x, y in x < 4 && y < 4 ? (30, 120, 220) : (128, 128, 128) }
        #expect(small == nil)
        let larger = accent { x, y in x < 8 && y < 8 ? (30, 120, 220) : (128, 128, 128) }
        #expect(same(larger, "56A2FF"), "got \(larger.map(hex) ?? "nil")")
    }

    @Test("A small painting on a white sleeve (3% of it): its green, not Glow")
    func smallPainting() {
        // As Lullabies to Violaine's sleeve: white, and a small green
        // painting in it, 6 by 5 of the 32 by 32.
        let found = accent { x, y in (10..<16).contains(x) && (12..<17).contains(y) ? (70, 150, 80) : (238, 236, 232) }
        #expect(same(found, "8BDC92"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("A see-through cover is not its colour: nothing shows, nil")
    func seeThrough() {
        let bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        #expect(CoverAccent.accent(rgba: bytes, width: 32, height: 32) == nil)
        #expect(CoverAccent.accent(rgba: [], width: 32, height: 32) == nil)
    }

    @Test("Premultiplied pixels give the colour, not a darker one")
    func premultiplied() {
        // Half of each channel and alpha 128: (176, 58, 46) at half alpha.
        var bytes: [UInt8] = []
        for _ in 0..<(32 * 32) {
            bytes += [88, 29, 23, 128]
        }
        let found = CoverAccent.accent(rgba: bytes, width: 32, height: 32)
        #expect(same(found, "FF8271"), "got \(found.map(hex) ?? "nil")")
    }

    @Test("Every hue round the wheel: an accent, readable on Cabinet (4.5:1 for text; 6.5 measured)")
    func readable() {
        for step in 0..<36 {
            let hue = Double(step) * 10
            let (r, g, b) = Self.rgb(hue: hue, saturation: 0.8, value: 0.8)
            let found = accent { _, _ in (r, g, b) }
            guard let found else {
                Issue.record("hue \(hue): nil")
                continue
            }
            let ratio = found.contrast(with: .cabinet)
            #expect(ratio >= 6.5, "hue \(hue): \(hex(found)) \(ratio)")
            // An accent, not a grey: some channel well apart from another.
            let channels = [found.red, found.green, found.blue]
            #expect((channels.max() ?? 0) - (channels.min() ?? 0) > 0.15, "hue \(hue): \(hex(found))")
        }
    }

    @Test("Glow on Cabinet: the contrast the brand already has")
    func glow() {
        #expect(AccentColor.glow.contrast(with: .cabinet) > 10)
        #expect(abs(CoverAccent.glowLightness - 0.825) < 0.001)
    }

    /// HSV to 8-bit RGB, for the wheel.
    static func rgb(hue: Double, saturation: Double, value: Double) -> (Int, Int, Int) {
        let c = value * saturation
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        let (r, g, b): (Double, Double, Double) = switch hue {
        case 0..<60: (c, x, 0)
        case 60..<120: (x, c, 0)
        case 120..<180: (0, c, x)
        case 180..<240: (0, x, c)
        case 240..<300: (x, 0, c)
        default: (c, 0, x)
        }
        return (Int(((r + m) * 255).rounded()), Int(((g + m) * 255).rounded()), Int(((b + m) * 255).rounded()))
    }
}
