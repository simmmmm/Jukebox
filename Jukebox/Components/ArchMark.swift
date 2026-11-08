// Jukebox's mark, the Arch (docs/BRAND.md): two tubes of light and a core,
// concentric — a jukebox cabinet's arch lit from inside, and nothing more of
// a real cabinet (no bubble tubes, no chrome). The photographer, 8 November
// 2026, of the four directions drawn: "Die arch is leuk."
//
// The arch only ever means a station: the mark, a station's artwork
// (StationArtwork.swift), the station's name in Now Playing. Lit means
// endless: only the radio is drawn lit; finite things (mixes, albums,
// playlists) stay square.
//
// The geometry is dev/brand/geom.py's, number for number: change both
// together. Drawn with Path so it can tint, template and animate — the
// tubes warm up one by one on the welcome screen and breathe while a
// station plays.

import SwiftUI

// MARK: - Geometry

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

/// An arch's centre line, as a tube is drawn: from the foot of the left leg
/// up to where the arc springs, over the top in a half circle, down to the
/// right foot. Measures in units of a `box`-unit square.
nonisolated struct ArchLine: Shape {
    var box: CGFloat
    var centerX: CGFloat
    var radius: CGFloat
    var spring: CGFloat
    var foot: CGFloat

    init(box: CGFloat, centerX: CGFloat, radius: CGFloat, spring: CGFloat, foot: CGFloat) {
        self.box = box
        self.centerX = centerX
        self.radius = radius
        self.spring = spring
        self.foot = foot
    }

    /// One of the mark's two tubes: 0 the outer, 1 the inner.
    init(tube index: Int, cut: ArchCut) {
        self.init(box: 32, centerX: 16, radius: index == 0 ? cut.outerRadius : cut.innerRadius,
                  spring: cut.spring, foot: cut.leg)
    }

    func path(in rect: CGRect) -> Path {
        let square = ArchSquare(rect, box: box)
        let c = square.point(centerX, spring)
        let r = radius * square.unit
        let footY = square.point(0, foot).y
        var path = Path()
        path.move(to: CGPoint(x: c.x - r, y: footY))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        // The half circle over the top as two quarters, each by its corner:
        // the tangent form leaves no doubt about which way round it goes.
        path.addArc(tangent1End: CGPoint(x: c.x - r, y: c.y - r), tangent2End: CGPoint(x: c.x, y: c.y - r), radius: r)
        path.addArc(tangent1End: CGPoint(x: c.x + r, y: c.y - r), tangent2End: CGPoint(x: c.x + r, y: c.y), radius: r)
        path.addLine(to: CGPoint(x: c.x + r, y: footY))
        return path
    }
}

/// The mark's core: a capsule from the top of its own half circle about the
/// spring point down to the baseline.
nonisolated struct ArchCore: Shape {
    var cut: ArchCut

    init(cut: ArchCut) {
        self.cut = cut
    }

    func path(in rect: CGRect) -> Path {
        let square = ArchSquare(rect, box: 32)
        let r = cut.coreRadius
        let top = square.point(16 - r, cut.spring - r)
        let bottom = square.point(16 + r, cut.base)
        let capsule = CGRect(x: top.x, y: top.y, width: bottom.x - top.x, height: bottom.y - top.y)
        return Path(roundedRect: capsule, cornerRadius: r * square.unit, style: .circular)
    }
}

/// A window in the shape of the arch, in its own rect: a flat sill, straight
/// sides, a half circle over the top as wide as the rect. What a station's
/// covers are seen through.
nonisolated struct ArchWindow: Shape {
    init() {}

    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let spring = rect.minY + r
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: spring))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.midX, y: rect.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: spring), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - The mark

/// The mark at `size` points square: 20 and below in the heavy cut.
///
/// `.lit`: the tubes in the accent (Copper by day, Glow by night), the core
/// as light, a soft bloom where it is dark around it — Home's toolbar, Now
/// Playing's station. `.template`: every part in the foreground style, for a
/// line of text or a glyph's place (the mini player's station).
///
/// `breathing`: the tubes dim and brighten one after the other, as a lit
/// sign hums — while a station plays. Never under Reduce Motion.
struct ArchMark: View {
    enum Style {
        case lit
        case template
    }

    let size: CGFloat
    let style: Style
    let breathing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGFloat, style: Style = .lit, breathing: Bool = false) {
        self.size = size
        self.style = style
        self.breathing = breathing
    }

    var body: some View {
        Group {
            if breathing && !reduceMotion {
                PhaseAnimator(ArchBreath.allCases) { phase in
                    ArchMarkFace(size: size, style: style, outer: phase.outer, inner: phase.inner)
                } animation: { _ in
                    .easeInOut(duration: 1.4)
                }
            } else {
                ArchMarkFace(size: size, style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A breath: at rest, the outer tube low, then the inner — each one turn of
/// the cycle, so one tube is always full while the other dims.
nonisolated private enum ArchBreath: CaseIterable, Equatable, Sendable {
    case rest
    case outerLow
    case innerLow

    var outer: Double { self == .outerLow ? 0.5 : 1 }
    var inner: Double { self == .innerLow ? 0.5 : 1 }
}

/// The mark drawn once, each part at its own level: 1 lit, 0 cold glass.
/// What ArchMark draws at rest and through each breath.
struct ArchMarkFace: View {
    let size: CGFloat
    let style: ArchMark.Style
    var outer: Double = 1
    var inner: Double = 1
    var core: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    init(size: CGFloat, style: ArchMark.Style, outer: Double = 1, inner: Double = 1, core: Double = 1) {
        self.size = size
        self.style = style
        self.outer = outer
        self.inner = inner
        self.core = core
    }

    var body: some View {
        let cut = ArchCut.forSize(size)
        let line = StrokeStyle(lineWidth: cut.stroke * size / 32, lineCap: .round)
        ZStack {
            part(ArchLine(tube: 0, cut: cut).stroke(tubeStyle, style: line), level: outer)
            part(ArchLine(tube: 1, cut: cut).stroke(tubeStyle, style: line), level: inner)
            part(ArchCore(cut: cut).fill(coreStyle), level: core)
        }
        .frame(width: size, height: size)
    }

    /// A part at its level, with its bloom when lit in the dark: a light
    /// seen at night glows past its edges; by day it does not.
    private func part<Part: View>(_ drawn: Part, level: Double) -> some View {
        drawn
            .background {
                if style == .lit && colorScheme == .dark {
                    drawn
                        .blur(radius: size * 0.07)
                        .opacity(0.6)
                }
            }
            // Unlit, a tube is still there, as cold glass.
            .opacity(0.16 + 0.84 * level)
    }

    private var tubeStyle: AnyShapeStyle {
        style == .lit ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(ForegroundStyle())
    }

    private var coreStyle: AnyShapeStyle {
        style == .lit ? AnyShapeStyle(Theme.Arch.markCore) : AnyShapeStyle(ForegroundStyle())
    }
}

// MARK: - The app icon, live

/// The app icon drawn live (dev/brand/icon.py, which draws AppIcon.png):
/// the mark lit on Cabinet, its tubes in the art's oranges with their halos
/// and hot lines, the room it lights. Each part at its own level, 0 to 1,
/// for the welcome's warm-up (ShellAppMark). `side`: the tile's.
struct ArchAppIcon: View {
    let side: CGFloat
    var outer: Double = 1
    var inner: Double = 1
    var core: Double = 1

    init(side: CGFloat, outer: Double = 1, inner: Double = 1, core: Double = 1) {
        self.side = side
        self.outer = outer
        self.inner = inner
        self.core = core
    }

    var body: some View {
        // icon.py: the 32-unit box at 22.4 units to 1024, centred 12/1024
        // below the middle; blurs in the icon's own pixels, scaled.
        let k = side / 1024
        let markSide = side * 32 * 22.4 / 1024
        let cut = ArchCut.regular
        let u = markSide / 32
        let line = StrokeStyle(lineWidth: cut.stroke * u, lineCap: .round)
        let outerLine = ArchLine(tube: 0, cut: cut)
        let innerLine = ArchLine(tube: 1, cut: cut)
        let coreShape = ArchCore(cut: cut)
        ZStack {
            RadialGradient(stops: [
                .init(color: Color(rgb: 0x46190F), location: 0),
                .init(color: Color(rgb: 0x260C08), location: 0.55),
                .init(color: Color(rgb: 0x130605), location: 1),
            ], center: UnitPoint(x: 0.5, y: 470 / 1024), startRadius: 0, endRadius: 760 * k)

            ZStack {
                // The room the arch lights: a wide haze round the outer
                // tube, the floor under it, the light through the window.
                outerLine
                    .stroke(Theme.Arch.roomGlow, style: StrokeStyle(lineWidth: cut.stroke * 3 * u, lineCap: .round))
                    .blur(radius: 60 * k)
                    .opacity(0.3 * outer)
                Ellipse()
                    .fill(Theme.Arch.roomGlow)
                    .frame(width: 600 * k, height: 52 * k)
                    .offset(y: (cut.base - 16) * u + 6 * k)
                    .blur(radius: 26 * k)
                    .opacity(0.42 * outer)
                ArchWindow()
                    .fill(Theme.Arch.innerTube)
                    .frame(width: cut.innerRadius * 2 * u, height: (cut.base - cut.spring + cut.innerRadius) * u)
                    .offset(y: (cut.spring - cut.innerRadius + cut.base) / 2 * u - 16 * u)
                    .blur(radius: 60 * k)
                    .opacity(0.27 * inner)

                tube(outerLine, line: line, top: Theme.Arch.outerTube, foot: Theme.Arch.outerTubeFoot,
                     heart: Theme.Arch.outerTubeHeart, from: 2, level: outer, k: k)
                tube(innerLine, line: line, top: Theme.Arch.innerTube, foot: Theme.Arch.innerTubeFoot,
                     heart: Theme.Arch.innerTubeHeart, from: 8, level: inner, k: k)

                ZStack {
                    coreShape.fill(Theme.Arch.coreFoot).blur(radius: 26 * k).opacity(0.75)
                    coreShape.fill(Theme.Arch.coreFoot).blur(radius: 9 * k).opacity(0.5)
                    coreShape.fill(LinearGradient(colors: [Theme.Arch.coreTop, Theme.Arch.coreFoot],
                                                  startPoint: UnitPoint(x: 0.5, y: (cut.spring - cut.coreRadius) / 32),
                                                  endPoint: UnitPoint(x: 0.5, y: cut.base / 32)))
                }
                .opacity(0.1 + 0.9 * core)
            }
            .frame(width: markSide, height: markSide)
            .offset(y: 12 * k)
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side * 0.2237, style: .continuous))
    }

    /// A tube: its halos, its glass in a gradient from `top` to `foot`
    /// (from `from` units down to the base), and the hot line inside it.
    private func tube(_ shape: ArchLine, line: StrokeStyle, top: Color, foot: Color, heart: Color,
                      from: CGFloat, level: Double, k: CGFloat) -> some View {
        let wide = StrokeStyle(lineWidth: line.lineWidth * 1.6, lineCap: .round)
        let thin = StrokeStyle(lineWidth: line.lineWidth * 0.34, lineCap: .round)
        return ZStack {
            shape.stroke(top, style: wide).blur(radius: 26 * k).opacity(0.46 * level)
            shape.stroke(top, style: line).blur(radius: 9 * k).opacity(0.5 * level)
            shape.stroke(LinearGradient(colors: [top, foot],
                                        startPoint: UnitPoint(x: 0.5, y: from / 32),
                                        endPoint: UnitPoint(x: 0.5, y: 30 / 32)),
                         style: line)
                // Unlit: cold glass, a shade of itself.
                .opacity(0.16 + 0.84 * level)
            shape.stroke(heart, style: thin).blur(radius: 2.2 * k).opacity(0.38 * level)
        }
    }
}
