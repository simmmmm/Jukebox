// The brand's drawings as numbers: the mark's cut, a station's art, the
// room it stands in, a cover's colour, the record's label, the sleeve's
// grain and the three cores. Foundation only, so both platforms draw from
// the same numbers: SwiftUI on the iPhone (ArchMark.swift,
// StationArtwork.swift, SleeveRecord.swift), cairo on Linux
// (Linux/App/Drawings.swift). Moved here unchanged from those files, 14
// November 2026, as build/design-round/drawings/spec.md lists them.

import Foundation
import JukeboxKit

// MARK: - The mark

/// The mark's measures in its 32-unit box (dev/brand/geom.py's `Cut`).
/// `nonisolated`, as the shapes that read it are: SwiftUI may ask a shape
/// for its path away from the main actor.
nonisolated struct ArchCut: Equatable, Sendable {
    /// A tube's stroke.
    var stroke: CGFloat
    /// The gap between the outer tube, the inner tube and the core.
    var gap: CGFloat
    /// Half the mark's width, to a tube's outer edge.
    var half: CGFloat
    /// Where the arcs spring from: every part is concentric about (16, spring).
    var spring: CGFloat
    /// The baseline the tubes' round caps and the core reach.
    var base: CGFloat

    var outerRadius: CGFloat { half - stroke / 2 }
    var innerRadius: CGFloat { outerRadius - stroke - gap }
    var coreRadius: CGFloat { innerRadius - stroke / 2 - gap }
    /// Where a tube's centre line ends, so that its cap reaches the base.
    var leg: CGFloat { base - stroke / 2 }

    /// Above 20 pt: width 24, height 28, a core 4.8 wide.
    static let regular = ArchCut(stroke: 2.6, gap: 2.2, half: 12, spring: 14, base: 30)
    /// 20 pt and below, as SF Symbols have optical sizes: heavier tubes, a
    /// wider core, tighter gaps and a little more of the box, so that at 16
    /// and 11 points the three parts stay three instead of running together.
    static let heavy = ArchCut(stroke: 3.2, gap: 1.9, half: 13, spring: 14.5, base: 30.5)

    static func forSize(_ size: CGFloat) -> ArchCut {
        size <= 20 ? .heavy : .regular
    }
}

/// A square of `box` units, the largest the rect holds, centred in it.
nonisolated struct ArchSquare: Sendable {
    let origin: CGPoint
    let unit: CGFloat

    init(_ rect: CGRect, box: CGFloat) {
        unit = min(rect.width, rect.height) / box
        origin = CGPoint(x: rect.midX - box / 2 * unit, y: rect.midY - box / 2 * unit)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
    }
}

// MARK: - A station's art

/// The art's measures in a 300-unit square (station.py's `Cut`). `t` the
/// tube's stroke, `g` the gaps, `rw` the window's half width, `top` the
/// outer tube's top edge, `base` where the window, the legs and the core end.
nonisolated struct StationArtCut: Equatable, Sendable {
    let t: CGFloat
    let g: CGFloat
    let rw: CGFloat
    let top: CGFloat
    let base: CGFloat

    /// The inner and the outer tube's centre lines.
    var innerRadius: CGFloat { rw + g + t / 2 }
    var outerRadius: CGFloat { innerRadius + t + g }
    /// Where the arcs spring from.
    var spring: CGFloat { top + t / 2 + outerRadius }
    var leg: CGFloat { base - t / 2 }
    var windowTop: CGFloat { spring - rw }
    /// The lit core's radius, in proportion to the window as on the board.
    var coreRadius: CGFloat { rw * 25 / 70 }

    /// From 60 points: a tile, a row, a station's page. The name is never
    /// drawn into the art: the page's title, in the serif, is right under
    /// it, and a subtitle that repeats a title goes (tells.md, 5).
    /// Thin bands and a wide window, so a station's art is mostly its
    /// music: "kun je deze jukebox iconen wat subtieler maken, de muziek
    /// gaat voor zeg maar" (the photographer, 14 November 2026; it was
    /// t 6, g 6.5, rw 82, top 26, base 274).
    static let tile = StationArtCut(t: 4, g: 4, rw: 104, top: 18, base: 282)
    /// Under 60 points (a row's thumbnail, the mini player): heavier tubes,
    /// and one cover, as four would be specks.
    static let small = StationArtCut(t: 9, g: 8, rw: 80, top: 22, base: 280)

    static func forSide(_ side: CGFloat) -> StationArtCut {
        side >= 60 ? .tile : .small
    }
}

/// The room a station's art stands in: the first cover's hue, its
/// saturation held to 0.5 so the room is never louder than the music in the
/// window, at brightness 0.14, flat. Until the cover's colour is known,
/// Cabinet.
nonisolated struct StationRoom: Hashable, Sendable {
    var hue: Double
    var saturation: Double

    init(_ average: AverageColor) {
        let hsb = average.hueSaturationBrightness
        hue = hsb.hue
        saturation = min(hsb.saturation, 0.5)
    }

    static let groundBrightness = 0.14
}

/// A cover's average colour, each 0 … 1 (ImagePipeline.averageColor).
nonisolated struct AverageColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Hue 0 … 1 (a turn), saturation and brightness 0 … 1, as Color(hue:
    /// saturation:brightness:) takes them.
    var hueSaturationBrightness: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let range = high - low
        let saturation = high > 0 ? range / high : 0
        guard range > 0 else { return (0, saturation, high) }
        var hue: Double
        if high == red {
            hue = (green - blue) / range
        } else if high == green {
            hue = 2 + (blue - red) / range
        } else {
            hue = 4 + (red - green) / range
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, high)
    }
}

/// The core in the window of a station made from the listener's own
/// taste: Your Station's a warm white; Discovery's paler, newer; Loved's
/// warmer, rosier. Calm differences, one family. Any station whose covers
/// are not known yet has Your Station's, rather than an empty window.
/// `flat` is the core at rest; `top` and `foot` the core lit, on the air;
/// each 0xRRGGBB.
nonisolated enum StationCore: Sendable {
    case yours
    case discovery
    case loved

    var colors: (flat: UInt32, top: UInt32, foot: UInt32) {
        switch self {
        case .yours: return (0xFFEDCC, 0xFFFBF0, 0xFFD58E)
        case .discovery: return (0xFAF6EC, 0xFFFFFF, 0xFFE9B8)
        case .loved: return (0xFFD3BE, 0xFFF1EA, 0xFFB58E)
        }
    }

    /// The station's core, or nil when its window holds its covers.
    static func of(_ station: Station) -> StationCore? {
        switch station.seed {
        case .personal: return .yours
        case .discovery: return .discovery
        case .favorites: return .loved
        default: return station.artwork.isEmpty ? .yours : nil
        }
    }
}

// MARK: - The sleeve and its record

/// The words on the record's label: the album's title, its artist, and its
/// disc's number when the album has more than one ("Disc 2").
nonisolated struct RecordLabel: Equatable, Sendable {
    let title: String
    let artist: String
    let disc: Int?

    init(title: String, artist: String, disc: Int?) {
        self.title = title
        self.artist = artist
        self.disc = disc
    }
}

/// Paper grain: 128 pixels of noise, each a little lighter or darker than
/// the print under it (white or black at up to 15%), so the cover reads as
/// ink on card, not as a screen. The same every time (its numbers come from
/// a fixed seed), and tiled.
nonisolated enum SleeveGrain {
    static let side = 128

    /// The tile's pixels, premultiplied, four bytes each: white or black
    /// at `alpha` is (ink, ink, ink, alpha), the same in RGBA as in BGRA.
    static func bytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 7
        for i in 0..<(side * side) {
            // Three uniforms summed: near enough a bell, around 1.5.
            var sum = 0.0
            for _ in 0..<3 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                sum += Double(seed >> 11) / 9_007_199_254_740_992
            }
            let deviation = (sum - 1.5) / 1.5
            let alpha = UInt8((min(1, abs(deviation)) * 0.15 * 255).rounded())
            // Premultiplied: white at `alpha` is (alpha, alpha, alpha, alpha).
            let ink: UInt8 = deviation > 0 ? alpha : 0
            bytes[i * 4] = ink
            bytes[i * 4 + 1] = ink
            bytes[i * 4 + 2] = ink
            bytes[i * 4 + 3] = alpha
        }
        return bytes
    }
}
