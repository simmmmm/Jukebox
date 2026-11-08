// Now Playing's still ground, sketch D1, "the wall": the photographer, 8
// November 2026, of sketch E's variants: "Dus ik denk dat d1 en d2 vooral d2
// het best gaan werken. D1 is reduced motion/batterij besparing d2 normaal."
// So when nothing may move — Reduce Motion, Low Power Mode, Spin the Record
// off — the page is two flat fields from the cover's own colours: a wall
// above the sleeve's foot, on whose edge the sleeve stands, and a floor
// below it, which the title and the controls are on.
//
// The wall is the cover's colour that stands out from the sleeve, so the
// sleeve reads on it: a dark cover's light (the window in a dark room), a
// light cover's ink (the rust on cream). The floor is the cover's own dark:
// a dark cover's main colour, or a light cover's most coloured hue, held
// dark — as the sketches' olive under the window and brown under the rust.
//
//   1. The cover small (32 by 32, as CoverAccent takes it), each pixel that
//      shows in Oklab.
//   2. Four colours by k-means, lightness counted double, seeded at the
//      quarters of the lightness so the same cover always gives the same
//      four. The largest is the cover's bulk.
//   3. The wall: of the other three, each 6% of the cover or more, the one
//      furthest from the bulk — in lightness, and half as much in colour —
//      weighed by the root of its share, so a large field beats a speck of
//      the same distance. None far enough (0.12 in lightness or 0.06 in
//      colour): the cover is one tone, and the wall is its own hue, 0.32
//      darker or 0.38 lighter.
//   4. The wall held between lightness 0.36 and 0.88 — never black, never
//      paper white — and its chroma to 0.12: a wall, not a poster.
//   5. The floor: a dark bulk (under 0.45, with a hue of its own) as it is,
//      at most 0.30 light and 0.05 in chroma; otherwise the more coloured of
//      the bulk and the wall, at 0.27 and 0.4 of its chroma (at most 0.05).
//   6. The floor then darkened, 0.01 at a time, until the accent on it is
//      4.5:1 or more (text needs 4.5) and white on it 7:1 or more: the
//      title, the times and the station's name stand on it.
//   7. `whiteOnWall` (the iPad sideways, where the status bar runs over the
//      wall on the left and the floor on the right, and one colour must do
//      for both): the wall darkened until white reads on it, 4.5:1.
//   8. Light or not: whichever of Ink and white has more contrast on the
//      wall. A light wall gets dark glyphs and a dark status bar.
//   9. The sleeve's shadow on the wall: the wall's hue, deep (saturation
//      0.55, brightness 0.10), as a shadow falls on coloured paper.
//
// Tried on the sketches' covers and the test library's (sketch E's D1 drew
// #C2BD97 over #2F3020 for Quiet Rooms and #A15841 over #331B13 for Night
// Machines; these steps give #B7B38E over #2E2F1F and #A7614A over #372018),
// and on every hue round the wheel in CoverWallTests.

import Foundation

/// D1's two fields, from a cover.
public struct CoverWall: Hashable, Sendable {
    /// Above the sleeve's foot: the cover's colour that stands out from it.
    public var wall: AccentColor
    /// Below it, under the title and the controls: the cover's own dark.
    public var floor: AccentColor
    /// The sleeve's shadow on the wall: the wall's hue, deep.
    public var shadow: AccentColor
    /// A light wall: Ink, not white, over it, and a dark status bar.
    public var isLight: Bool

    public init(wall: AccentColor, floor: AccentColor, shadow: AccentColor, isLight: Bool) {
        self.wall = wall
        self.floor = floor
        self.shadow = shadow
        self.isLight = isLight
    }

    static let clusters = 4
    static let rounds = 12
    static let leastShare = 0.06
    static let wallLightness: ClosedRange<Double> = 0.36...0.88
    static let wallChroma = 0.12
    static let floorLightness = 0.27
    static let darkBulk = 0.45
    static let floorChroma = 0.05
    /// The least contrast of the accent on the floor (text), and of white.
    static let accentOnFloor = 4.5
    static let whiteOnFloor = 7.0
    /// White on a wall that must take white glyphs (`whiteOnWall`).
    static let whiteOnDarkWall = 4.5

    /// Ink, #2A1505: the brand's dark for words on light grounds.
    static let ink = AccentColor(red: 0x2A / 255.0, green: 0x15 / 255.0, blue: 0x05 / 255.0)
    static let white = AccentColor(red: 1, green: 1, blue: 1)

    /// The wall and floor of a cover drawn into `width` by `height` pixels,
    /// RGBA, 8 bits each, premultiplied (as CoverAccent takes it). `accent`
    /// is the accent Now Playing will draw on the floor (CoverAccent's, or
    /// Glow). Nil when nothing of the cover shows.
    public static func of(rgba pixels: [UInt8], width: Int, height: Int, accent: AccentColor,
                          whiteOnWall: Bool = false) -> CoverWall? {
        let lab = colours(rgba: pixels, count: width * height)
        guard !lab.isEmpty else { return nil }
        let (centres, shares) = kMeans(lab)
        // The largest; on a tie the first, as NumPy's argmax.
        var bulk = 0
        for j in shares.indices where shares[j] > shares[bulk] {
            bulk = j
        }
        let b = centres[bulk]

        // 3. The cluster that stands apart from the bulk most.
        var standing: Int?
        var best = 0.0
        for j in centres.indices where j != bulk && shares[j] >= leastShare {
            let lightness = abs(centres[j].lightness - b.lightness)
            let colour = distance(centres[j], b)
            let score = (lightness + 0.5 * colour) * shares[j].squareRoot()
            if score > best {
                best = score
                standing = j
            }
        }
        var wall: Oklch
        if let standing, abs(centres[standing].lightness - b.lightness) >= 0.12 || distance(centres[standing], b) >= 0.06 {
            wall = Oklch(centres[standing])
        } else {
            // One tone: its own hue, well away from it in lightness.
            let bulkColour = Oklch(b)
            let lightness = b.lightness > 0.55 ? b.lightness - 0.32 : b.lightness + 0.38
            wall = Oklch(lightness: lightness, chroma: bulkColour.chroma, hue: bulkColour.hue)
        }
        // 4.
        wall.lightness = min(wallLightness.upperBound, max(wallLightness.lowerBound, wall.lightness))
        wall.chroma = min(wall.chroma, wallChroma)

        // 5. The floor.
        let bulkColour = Oklch(b)
        var floor: Oklch
        if b.lightness < darkBulk && bulkColour.chroma >= 0.015 {
            floor = Oklch(lightness: min(b.lightness, 0.30), chroma: min(bulkColour.chroma, floorChroma),
                          hue: bulkColour.hue)
        } else {
            var source = bulkColour
            if let standing {
                let other = Oklch(centres[standing])
                if other.chroma > source.chroma { source = other }
            }
            floor = Oklch(lightness: floorLightness, chroma: min(source.chroma * 0.4, floorChroma), hue: source.hue)
        }
        // 6. Dark enough for the accent and for white.
        var floorColour = floor.rgb
        while floor.lightness > 0.05,
              accent.contrast(with: floorColour) < accentOnFloor || white.contrast(with: floorColour) < whiteOnFloor {
            floor.lightness -= 0.01
            floorColour = floor.rgb
        }

        // 7. A wall that takes white glyphs, where it must.
        var wallColour = wall.rgb
        while whiteOnWall, wall.lightness > 0.05, white.contrast(with: wallColour) < whiteOnDarkWall {
            wall.lightness -= 0.01
            wallColour = wall.rgb
        }

        // 8, 9.
        let isLight = ink.contrast(with: wallColour) > white.contrast(with: wallColour)
        return CoverWall(wall: wallColour, floor: floorColour, shadow: shadow(of: wallColour), isLight: isLight)
    }

    // MARK: The cover's colours

    /// A colour in Oklab.
    struct Lab: Hashable, Sendable {
        var lightness: Double
        var a: Double
        var b: Double
    }

    /// Oklab as lightness, chroma and hue (degrees), and back to sRGB.
    struct Oklch: Hashable, Sendable {
        var lightness: Double
        var chroma: Double
        var hue: Double

        init(lightness: Double, chroma: Double, hue: Double) {
            self.lightness = lightness
            self.chroma = chroma
            self.hue = hue
        }

        init(_ lab: Lab) {
            lightness = lab.lightness
            chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            hue = CoverAccent.degrees(atan2(lab.b, lab.a))
        }

        /// In sRGB: the chroma held to what the hue has at this lightness,
        /// so the colour is one the screen can show and keeps its hue.
        var rgb: AccentColor {
            let held = min(chroma, CoverAccent.mostChroma(lightness: lightness, hue: hue))
            let radians = hue * .pi / 180
            let linear = CoverAccent.linearRGB(lightness: lightness, a: held * cos(radians), b: held * sin(radians))
            return AccentColor(red: CoverAccent.encoded(linear.red), green: CoverAccent.encoded(linear.green),
                               blue: CoverAccent.encoded(linear.blue))
        }
    }

    /// Every pixel that shows (alpha 128 or more), in Oklab.
    static func colours(rgba pixels: [UInt8], count: Int) -> [Lab] {
        guard count > 0, pixels.count >= count * 4 else { return [] }
        var lab: [Lab] = []
        lab.reserveCapacity(count)
        for i in 0..<count {
            let alpha = Double(pixels[i * 4 + 3])
            guard alpha >= 128 else { continue }
            let red = CoverAccent.linear(Double(pixels[i * 4]) / alpha)
            let green = CoverAccent.linear(Double(pixels[i * 4 + 1]) / alpha)
            let blue = CoverAccent.linear(Double(pixels[i * 4 + 2]) / alpha)
            let found = CoverAccent.oklab(red: red, green: green, blue: blue)
            lab.append(Lab(lightness: found.lightness, a: found.a, b: found.b))
        }
        return lab
    }

    /// Four colours by k-means: the centres and the share of the cover each
    /// has. Seeded at the middles of the lightness's quarters, lightness
    /// counted double in the distance (the eye sorts a cover into light and
    /// dark before it sorts it by hue).
    static func kMeans(_ lab: [Lab]) -> (centres: [Lab], shares: [Double]) {
        let order = lab.indices.sorted { lab[$0].lightness < lab[$1].lightness }
        var centres: [Lab] = (0..<clusters).map { j in
            let place = (Double(j) + 0.5) / Double(clusters) * Double(lab.count - 1)
            return lab[order[Int(place)]]
        }
        var member = [Int](repeating: 0, count: lab.count)
        for _ in 0..<rounds {
            for i in lab.indices {
                var nearest = 0
                var least = Double.infinity
                for j in centres.indices {
                    let d = weighed(lab[i], centres[j])
                    if d < least {
                        least = d
                        nearest = j
                    }
                }
                member[i] = nearest
            }
            for j in centres.indices {
                var sum = Lab(lightness: 0, a: 0, b: 0)
                var n = 0.0
                for i in lab.indices where member[i] == j {
                    sum.lightness += lab[i].lightness
                    sum.a += lab[i].a
                    sum.b += lab[i].b
                    n += 1
                }
                if n > 0 {
                    centres[j] = Lab(lightness: sum.lightness / n, a: sum.a / n, b: sum.b / n)
                }
            }
        }
        // The shares of the last assignment, as the centres were made from it.
        var counts = [Double](repeating: 0, count: clusters)
        for j in member {
            counts[j] += 1
        }
        return (centres, counts.map { $0 / Double(lab.count) })
    }

    /// The squared distance, lightness counted double.
    static func weighed(_ x: Lab, _ y: Lab) -> Double {
        let l = 2 * (x.lightness - y.lightness)
        let a = x.a - y.a
        let b = x.b - y.b
        return l * l + a * a + b * b
    }

    /// How far apart two colours are in hue and chroma (a and b).
    static func distance(_ x: Lab, _ y: Lab) -> Double {
        let a = x.a - y.a
        let b = x.b - y.b
        return (a * a + b * b).squareRoot()
    }

    /// The wall's hue at saturation 0.55 and brightness 0.10 (HSV), as
    /// sketch E drew the sleeve's shadow on a coloured wall; less saturated
    /// for a wall that is nearly grey.
    static func shadow(of wall: AccentColor) -> AccentColor {
        let high = max(wall.red, wall.green, wall.blue)
        let low = min(wall.red, wall.green, wall.blue)
        let range = high - low
        var hue = 0.0
        if range > 0 {
            if high == wall.red {
                hue = (wall.green - wall.blue) / range
            } else if high == wall.green {
                hue = 2 + (wall.blue - wall.red) / range
            } else {
                hue = 4 + (wall.red - wall.green) / range
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        // A grey wall has no hue to give: its shadow grey too, and a wall
        // with little colour gives a shadow with little (0.55 from a wall
        // of saturation 0.1 up).
        let saturation = high > 0 ? min(0.55, 5.5 * range / high) : 0
        let value = 0.10
        let sector = hue * 6
        let i = Int(sector.rounded(.down)) % 6
        let f = sector - sector.rounded(.down)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (value, t, p)
        case 1: (q, value, p)
        case 2: (p, value, t)
        case 3: (p, q, value)
        case 4: (t, p, value)
        default: (value, p, q)
        }
        return AccentColor(red: r, green: g, blue: b)
    }
}
