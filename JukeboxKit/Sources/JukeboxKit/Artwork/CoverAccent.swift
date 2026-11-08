// The accent of Now Playing, from the cover of what plays — the
// photographer, 8 November 2026: "kan je de kleur uit de albumhoes pakken
// voor de steunkleur?"
//
// Not the cover's average (ImagePipeline.averageColor, which a turntable's
// label and a station's room take): an average of red stripes on cream is a
// pinkish beige no one sees in it. The accent is the hue the eye picks out:
//
//   1. The cover small (32 by 32: the app draws it so), each pixel in Oklab,
//      as lightness, chroma and hue.
//   2. Near-grey (chroma under 0.035), near-black and near-white pixels
//      dropped: their hue is noise.
//   3. A histogram of hue in 36 steps of 10°, each pixel weighed by its
//      chroma squared, so a vivid part counts far more than a dull one of
//      the same size; each step with half of its two neighbours, so a hue
//      on a step's edge is not split in two.
//   4. The best step's pixels, within 20° of its middle, must cover 4% of
//      the cover; less, and the cover has no colour of its own (a black and
//      white photo, a grey sleeve): nil, and the app keeps Glow.
//   5. Their hue (the mean of the angles, weighed by chroma), and how vivid
//      they are (the 75th percentile of their chroma, at least 0.10 so the
//      accent never reads as grey).
//   6. That hue at Glow's own lightness, so it weighs on Cabinet what Glow
//      weighs, and only the hue changes from album to album; a little
//      darker where the hue has no room for its chroma there (a red at
//      Glow's lightness is salmon), but never under 0.70, which keeps it at
//      6.7:1 or more on Cabinet, where text needs 4.5.
//
// The steps and their numbers were tried on the test library's 19 covers
// (docs/design/accent.png): every cover with a colour got one a person
// would point at, and the black and white one got Glow.
// `dev/accent.py` is the same in Python, for sketches.

import Foundation

/// A colour in sRGB, each 0 … 1, as SwiftUI's Color(red:green:blue:) takes it.
public struct AccentColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Glow, #FFB54D: the accent of a cover with no colour of its own.
    public static let glow = AccentColor(red: 255 / 255, green: 181 / 255, blue: 77 / 255)
    /// Cabinet, #1E0A07: Now Playing's ground.
    public static let cabinet = AccentColor(red: 30 / 255, green: 10 / 255, blue: 7 / 255)

    /// WCAG's relative luminance.
    public var luminance: Double {
        0.2126 * CoverAccent.linear(red) + 0.7152 * CoverAccent.linear(green) + 0.0722 * CoverAccent.linear(blue)
    }

    /// WCAG's contrast ratio, 1 … 21.
    public func contrast(with other: AccentColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public enum CoverAccent {
    /// The side of the square the app draws a cover into before it asks.
    public static let side = 32

    static let minimumChroma = 0.035
    static let minimumShare = 0.04
    static let leastAccentChroma = 0.10
    static let lowestLightness = 0.70
    static let steps = 36
    /// Glow's lightness in Oklab, 0.825.
    static let glowLightness = oklab(red: linear(AccentColor.glow.red), green: linear(AccentColor.glow.green),
                                     blue: linear(AccentColor.glow.blue)).lightness

    /// The accent of a cover drawn into `width` by `height` pixels, RGBA, 8
    /// bits each, premultiplied by alpha (as Core Graphics draws). Nil: the
    /// cover has too little colour of its own.
    public static func accent(rgba pixels: [UInt8], width: Int, height: Int) -> AccentColor? {
        let count = width * height
        guard count > 0, pixels.count >= count * 4 else { return nil }

        // Lightness, chroma and hue of every pixel that shows; nil for one
        // that does not count.
        var samples: [(chroma: Double, hue: Double)?] = []
        samples.reserveCapacity(count)
        var histogram = [Double](repeating: 0, count: steps)
        for i in 0..<count {
            let alpha = Double(pixels[i * 4 + 3])
            // Mostly see-through: not the cover's colour but what is behind it.
            guard alpha >= 128 else {
                samples.append(nil)
                continue
            }
            let lab = oklab(red: linear(Double(pixels[i * 4]) / alpha),
                            green: linear(Double(pixels[i * 4 + 1]) / alpha),
                            blue: linear(Double(pixels[i * 4 + 2]) / alpha))
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            guard chroma >= minimumChroma, lab.lightness > 0.25, lab.lightness < 0.97 else {
                samples.append(nil)
                continue
            }
            let hue = degrees(atan2(lab.b, lab.a))
            samples.append((chroma, hue))
            histogram[Int(hue / (360 / Double(steps))) % steps] += chroma * chroma
        }

        var best = -1
        var bestScore = 0.0
        for step in 0..<steps {
            let score = histogram[step] + 0.5 * (histogram[(step + steps - 1) % steps] + histogram[(step + 1) % steps])
            if score > bestScore {
                bestScore = score
                best = step
            }
        }
        guard best >= 0 else { return nil }

        let middle = (Double(best) + 0.5) * 360 / Double(steps)
        var near: [Double] = []
        var sine = 0.0, cosine = 0.0
        for case let (chroma, hue)? in samples where angle(hue, from: middle) <= 20 {
            near.append(chroma)
            sine += chroma * sin(hue * .pi / 180)
            cosine += chroma * cos(hue * .pi / 180)
        }
        guard Double(near.count) / Double(count) >= minimumShare else { return nil }

        let hue = degrees(atan2(sine, cosine))
        let wanted = max(percentile(near.sorted(), 0.75), leastAccentChroma)

        // From Glow's lightness down: the lightest that comes within 0.01 of
        // the most chroma the hue can have.
        var chosen = (lightness: glowLightness, chroma: -1.0)
        for lightness in stride(from: glowLightness, through: lowestLightness, by: -0.01) {
            let chroma = min(wanted, mostChroma(lightness: lightness, hue: hue))
            if chosen.chroma < 0 || chroma > chosen.chroma + 0.01 {
                chosen = (lightness, chroma)
            }
        }
        let radians = hue * .pi / 180
        let rgb = linearRGB(lightness: chosen.lightness, a: chosen.chroma * cos(radians), b: chosen.chroma * sin(radians))
        return AccentColor(red: encoded(rgb.red), green: encoded(rgb.green), blue: encoded(rgb.blue))
    }

    // MARK: Colour

    /// sRGB's curve undone: 0 … 1 in, light 0 … 1 out.
    static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// sRGB's curve, clamped to 0 … 1.
    static func encoded(_ value: Double) -> Double {
        let value = min(1, max(0, value))
        return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    /// Björn Ottosson's Oklab, from linear sRGB.
    static func oklab(red: Double, green: Double, blue: Double) -> (lightness: Double, a: Double, b: Double) {
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Back from Oklab to linear sRGB, which can fall outside 0 … 1.
    static func linearRGB(lightness: Double, a: Double, b: Double) -> (red: Double, green: Double, blue: Double) {
        let l = cube(lightness + 0.3963377774 * a + 0.2158037573 * b)
        let m = cube(lightness - 0.1055613458 * a - 0.0638541728 * b)
        let s = cube(lightness - 0.0894841775 * a - 1.2914855480 * b)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// The most chroma a hue has at a lightness and is still an sRGB colour.
    static func mostChroma(lightness: Double, hue: Double) -> Double {
        let radians = hue * .pi / 180
        var low = 0.0, high = 0.4
        for _ in 0..<30 {
            let middle = (low + high) / 2
            let rgb = linearRGB(lightness: lightness, a: middle * cos(radians), b: middle * sin(radians))
            if [rgb.red, rgb.green, rgb.blue].allSatisfy({ $0 >= 0 && $0 <= 1 }) {
                low = middle
            } else {
                high = middle
            }
        }
        return low
    }

    // MARK: Numbers

    static func cube(_ value: Double) -> Double {
        value * value * value
    }

    /// An angle in radians as degrees, 0 ..< 360.
    static func degrees(_ radians: Double) -> Double {
        let degrees = radians * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// How far apart two hues are, 0 … 180.
    static func angle(_ hue: Double, from other: Double) -> Double {
        let difference = abs(hue - other).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    /// A percentile of sorted values, between the two nearest as NumPy
    /// takes it, so the sketches' Python gives the same colour.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard let first = sorted.first else { return 0 }
        let place = fraction * Double(sorted.count - 1)
        let below = Int(place.rounded(.down))
        let above = min(below + 1, sorted.count - 1)
        guard below < sorted.count - 1 else { return sorted.last ?? first }
        return sorted[below] + (sorted[above] - sorted[below]) * (place - Double(below))
    }
}
