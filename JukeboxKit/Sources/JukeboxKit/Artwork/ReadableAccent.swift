// The cover's accent as the whole app's, readable on every ground it lands
// on — the photographer, 24 November 2026: "ik wil het wel even zien dat het
// overal is doorgevoerd, zolang de gekozen kleur voldoet aan wcag contrast".
//
// CoverAccent gives a colour at Glow's lightness, made for Cabinet and the
// night. By day the app's grounds are paper: there it is too light to read,
// as Glow is, which is why the brand has Copper. So, for each appearance:
//
//   1. The accent's hue and chroma in Oklab kept; only its lightness moves,
//      darker by day, lighter by night, in steps of 0.005, the chroma
//      narrowed only where sRGB has no room for it at that lightness.
//   2. The first lightness where it reads 4.5:1 (WCAG 2.2's least for text)
//      on every ground of that appearance and with the words on it (white
//      on it by day, Ink by night: Play's label). 4.5 covers the 3:1 that
//      the progress, the icons and the filled squares need.
//   3. The quiet buttons' word (Shuffle's, the squares' glyphs) on the
//      accent's own faint tint over the ground: the same, a step further,
//      until it reads 4.5:1 on the tint at rest, hovered and pressed.
//   4. Its character lost — less than half its chroma left, or so little
//      that it reads grey — and the app keeps Copper and Glow (nil).
//
// A yellow by day goes to mustard, a teal to a deep teal: they keep 0.6 of
// their chroma and stay theirs. What falls back is a colour that was all
// but grey to begin with.

import Foundation

/// What the accent stands on in one appearance.
public struct AccentGrounds: Sendable {
    /// Every ground the accent's words and marks are drawn on.
    public var grounds: [AccentColor]
    /// The words and glyphs drawn on the accent (Play's label).
    public var onAccent: AccentColor
    /// The ground under a quiet button, its faint tint of the accent laid on it.
    public var quietGround: AccentColor
    /// The tint's opacities: at rest, hovered, pressed.
    public var quietTints: [Double]

    public init(grounds: [AccentColor], onAccent: AccentColor, quietGround: AccentColor, quietTints: [Double]) {
        self.grounds = grounds
        self.onAccent = onAccent
        self.quietGround = quietGround
        self.quietTints = quietTints
    }
}

/// The accent of one appearance, and the quiet buttons' word in it.
public struct ReadableAccent: Hashable, Sendable {
    public var accent: AccentColor
    public var quietInk: AccentColor

    public init(accent: AccentColor, quietInk: AccentColor) {
        self.accent = accent
        self.quietInk = quietInk
    }
}

extension AccentColor {
    /// "#A84A17"'s number, 0xA84A17.
    public var hex: UInt32 {
        let channels = [red, green, blue].map { UInt32((min(1, max(0, $0)) * 255).rounded()) }
        return channels[0] << 16 | channels[1] << 8 | channels[2]
    }

    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// This colour laid at `opacity` over `ground`, as CSS's alpha and
    /// SwiftUI's opacity draw it: in sRGB's own numbers.
    func over(_ ground: AccentColor, opacity: Double) -> AccentColor {
        AccentColor(red: red * opacity + ground.red * (1 - opacity),
                    green: green * opacity + ground.green * (1 - opacity),
                    blue: blue * opacity + ground.blue * (1 - opacity))
    }
}

extension CoverAccent {
    /// The least of WCAG 2.2 for text, which the accent is (links, the
    /// playing row's title, Play's label).
    public static let leastContrast = 4.5
    /// Less of its chroma left than this, and it is no longer the cover's
    /// colour.
    static let leastKept = 0.5
    /// Less chroma than this reads as grey (CoverAccent's own floor for a
    /// pixel that has a hue).
    static let leastReadableChroma = minimumChroma
    static let lightnessStep = 0.005

    /// The accent made readable on `grounds`, or nil when it cannot be
    /// without losing its character: then the app keeps the brand's.
    public static func readable(_ accent: AccentColor, on grounds: AccentGrounds) -> ReadableAccent? {
        let lab = oklab(red: linear(accent.red), green: linear(accent.green), blue: linear(accent.blue))
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        let hue = degrees(atan2(lab.b, lab.a))
        // Away from the grounds: darker on light ones, lighter on dark.
        let meanGround = grounds.grounds.map(\.luminance).reduce(0, +) / Double(max(1, grounds.grounds.count))
        let step = meanGround > 0.18 ? -lightnessStep : lightnessStep

        guard let found = first(from: lab.lightness, step: step, hue: hue, chroma: chroma, passing: { color in
            (grounds.grounds + [grounds.onAccent]).allSatisfy { color.contrast(with: $0) >= leastContrast }
        }) else { return nil }
        guard found.chroma >= chroma * leastKept, found.chroma >= leastReadableChroma else { return nil }

        let tints = grounds.quietTints.map { found.color.over(grounds.quietGround, opacity: $0) }
        guard let quiet = first(from: found.lightness, step: step, hue: hue, chroma: chroma, passing: { color in
            tints.allSatisfy { color.contrast(with: $0) >= leastContrast }
        }) else { return nil }
        return ReadableAccent(accent: found.color, quietInk: quiet.color)
    }

    /// From `lightness` on by `step`, the first colour of the hue that
    /// passes, with as much of `chroma` as sRGB has room for there.
    private static func first(from lightness: Double, step: Double, hue: Double, chroma: Double,
                              passing: (AccentColor) -> Bool)
        -> (color: AccentColor, lightness: Double, chroma: Double)? {
        let radians = hue * .pi / 180
        var lightness = lightness
        while lightness >= 0, lightness <= 1 {
            let kept = min(chroma, mostChroma(lightness: lightness, hue: hue))
            let rgb = linearRGB(lightness: lightness, a: kept * cos(radians), b: kept * sin(radians))
            // Rounded to 8 bits as the app will draw it, so what passes here
            // is what is shown.
            let color = AccentColor(hex: AccentColor(red: encoded(rgb.red), green: encoded(rgb.green), blue: encoded(rgb.blue)).hex)
            if passing(color) { return (color, lightness, kept) }
            lightness += step
        }
        return nil
    }
}
