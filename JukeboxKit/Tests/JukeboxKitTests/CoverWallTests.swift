// CoverWall on made-up covers of 32 by 32: D1's wall is the cover's colour
// that stands out from it (a dark room's window, a light sleeve's ink), its
// floor the cover's own dark, and on every cover the floor keeps the accent
// readable (4.5:1) and white text (7:1). A light wall says so, for dark
// glyphs over it; a wall that must take white glyphs does.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Artwork: the wall and the floor from a cover")
struct CoverWallTests {
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

    /// The wall with the accent the app would draw: the cover's own, or Glow.
    func wall(_ pixel: (Int, Int) -> (Int, Int, Int), whiteOnWall: Bool = false) -> (CoverWall?, AccentColor) {
        let bytes = cover(pixel)
        let accent = CoverAccent.accent(rgba: bytes, width: 32, height: 32) ?? .glow
        return (CoverWall.of(rgba: bytes, width: 32, height: 32, accent: accent, whiteOnWall: whiteOnWall), accent)
    }

    func oklch(_ color: AccentColor) -> CoverWall.Oklch {
        let lab = CoverAccent.oklab(red: CoverAccent.linear(color.red), green: CoverAccent.linear(color.green),
                                    blue: CoverAccent.linear(color.blue))
        return CoverWall.Oklch(CoverWall.Lab(lightness: lab.lightness, a: lab.a, b: lab.b))
    }

    func oklch(_ r: Int, _ g: Int, _ b: Int) -> CoverWall.Oklch {
        oklch(AccentColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255))
    }

    func hex(_ color: AccentColor) -> String {
        [color.red, color.green, color.blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    /// The floor's two promises.
    func readable(_ found: CoverWall, accent: AccentColor) -> Bool {
        accent.contrast(with: found.floor) >= 4.5 && CoverWall.white.contrast(with: found.floor) >= 7
    }

    @Test("A dark room with a light window: the window's light is the wall, light; the room's olive the floor")
    func darkCover() throws {
        // Sketch E's Quiet Rooms, in two colours: dark olive, a cream window.
        let (found, accent) = wall { x, y in (8..<24).contains(x) && (4..<20).contains(y) ? (194, 189, 151) : (47, 48, 32) }
        let result = try #require(found)
        let window = oklch(194, 189, 151), olive = oklch(47, 48, 32)
        let wallColour = oklch(result.wall), floorColour = oklch(result.floor)
        #expect(result.isLight, "wall \(hex(result.wall))")
        #expect(abs(wallColour.lightness - window.lightness) < 0.03, "wall \(hex(result.wall))")
        #expect(CoverAccent.angle(wallColour.hue, from: window.hue) < 10, "wall \(hex(result.wall))")
        #expect(floorColour.lightness <= 0.30 + 0.001, "floor \(hex(result.floor))")
        #expect(CoverAccent.angle(floorColour.hue, from: olive.hue) < 15, "floor \(hex(result.floor))")
        #expect(readable(result, accent: accent), "floor \(hex(result.floor)) under \(hex(accent))")
    }

    @Test("Rust on cream: the rust is the wall, dark enough for white; the floor is the rust held dark")
    func lightCover() throws {
        // Sketch E's Night Machines: a cream sleeve printed in rust.
        let (found, accent) = wall { x, y in (x - 16) * (x - 16) + (y - 18) * (y - 18) < 80 || y % 8 == 0 ? (161, 88, 65) : (233, 222, 202) }
        let result = try #require(found)
        let rust = oklch(161, 88, 65)
        let wallColour = oklch(result.wall), floorColour = oklch(result.floor)
        #expect(!result.isLight, "wall \(hex(result.wall))")
        #expect(CoverAccent.angle(wallColour.hue, from: rust.hue) < 10, "wall \(hex(result.wall))")
        #expect(abs(wallColour.lightness - rust.lightness) < 0.05, "wall \(hex(result.wall))")
        #expect(CoverAccent.angle(floorColour.hue, from: rust.hue) < 10, "floor \(hex(result.floor))")
        #expect(floorColour.lightness <= 0.27 + 0.001, "floor \(hex(result.floor))")
        #expect(readable(result, accent: accent), "floor \(hex(result.floor)) under \(hex(accent))")
    }

    @Test("One colour all over: a wall of its own hue, well away from it in lightness")
    func oneTone() throws {
        let (found, accent) = wall { _, _ in (176, 58, 46) }
        let result = try #require(found)
        let red = oklch(176, 58, 46), wallColour = oklch(result.wall)
        #expect(abs(wallColour.lightness - red.lightness) >= 0.3, "wall \(hex(result.wall))")
        #expect(CoverAccent.angle(wallColour.hue, from: red.hue) < 10, "wall \(hex(result.wall))")
        #expect(readable(result, accent: accent))
    }

    @Test("Black to white: a grey wall and a grey floor, Glow readable on it")
    func grey() throws {
        let (found, accent) = wall { x, _ in (x * 8, x * 8, x * 8) }
        let result = try #require(found)
        #expect(accent == .glow)
        for colour in [result.wall, result.floor, result.shadow] {
            let channels = [colour.red, colour.green, colour.blue]
            #expect((channels.max() ?? 0) - (channels.min() ?? 0) < 0.01, "\(hex(colour)) is not grey")
        }
        #expect(readable(result, accent: accent), "floor \(hex(result.floor))")
    }

    @Test("Every hue round the wheel, on light and on dark sleeves: the floor keeps the accent and white readable")
    func everyHue() {
        for step in 0..<36 {
            let hue = Double(step) * 10
            let vivid = CoverAccentTests.rgb(hue: hue, saturation: 0.8, value: 0.8)
            let deep = CoverAccentTests.rgb(hue: hue, saturation: 0.6, value: 0.25)
            let covers: [(String, (Int, Int) -> (Int, Int, Int))] = [
                ("on cream", { x, _ in x < 12 ? vivid : (236, 230, 218) }),
                ("on its own dark", { x, y in x > 20 && y < 12 ? vivid : deep }),
                ("alone", { _, _ in vivid }),
            ]
            for (name, pixel) in covers {
                let (found, accent) = wall(pixel)
                guard let found else {
                    Issue.record("hue \(hue) \(name): nil")
                    continue
                }
                #expect(readable(found, accent: accent),
                        "hue \(hue) \(name): floor \(hex(found.floor)), accent \(hex(accent)) \(accent.contrast(with: found.floor))")
                let wallColour = oklch(found.wall)
                #expect(CoverWall.wallLightness.contains(wallColour.lightness - 0.0001)
                        || CoverWall.wallLightness.contains(wallColour.lightness + 0.0001),
                        "hue \(hue) \(name): wall \(hex(found.wall))")
                // Light means Ink over it reads better than white, and so on.
                let ink = CoverWall.ink.contrast(with: found.wall), white = CoverWall.white.contrast(with: found.wall)
                #expect(found.isLight == (ink > white), "hue \(hue) \(name)")
            }
        }
    }

    @Test("A wall under white glyphs (the iPad sideways) is dark enough for them")
    func whiteOnWall() throws {
        let (found, _) = wall({ x, y in (8..<24).contains(x) && (4..<20).contains(y) ? (194, 189, 151) : (47, 48, 32) },
                              whiteOnWall: true)
        let result = try #require(found)
        #expect(CoverWall.white.contrast(with: result.wall) >= 4.5, "wall \(hex(result.wall))")
        #expect(!result.isLight)
    }

    @Test("The sleeve's shadow is the wall's hue, deep")
    func shadow() throws {
        let (found, _) = wall { x, y in (x - 16) * (x - 16) + (y - 18) * (y - 18) < 80 || y % 8 == 0 ? (161, 88, 65) : (233, 222, 202) }
        let result = try #require(found)
        #expect(result.shadow.luminance < 0.02, "shadow \(hex(result.shadow))")
        #expect(CoverAccent.angle(oklch(result.shadow).hue, from: oklch(result.wall).hue) < 20,
                "shadow \(hex(result.shadow)), wall \(hex(result.wall))")
    }

    @Test("A see-through cover has no wall: nil, and the app keeps Cabinet")
    func seeThrough() {
        let bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        #expect(CoverWall.of(rgba: bytes, width: 32, height: 32, accent: .glow) == nil)
        #expect(CoverWall.of(rgba: [], width: 32, height: 32, accent: .glow) == nil)
    }

    @Test("The same cover gives the same wall, every time")
    func steady() {
        let bytes = cover { x, y in ((x * 7 + y * 3) % 256, (x * y) % 256, (200 - x * 5) % 256) }
        let first = CoverWall.of(rgba: bytes, width: 32, height: 32, accent: .glow)
        for _ in 0..<3 {
            #expect(CoverWall.of(rgba: bytes, width: 32, height: 32, accent: .glow) == first)
        }
    }
}
