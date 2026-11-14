// Jukebox's mark, the Arch (docs/BRAND.md): two bands and a core,
// concentric — a jukebox cabinet's arch, and nothing more of a real cabinet
// (no bubble tubes, no chrome). The photographer, 8 November 2026, of the
// four directions drawn: "Die arch is leuk."
//
// The arch only ever means a station: the mark, a station's artwork
// (StationArtwork.swift), the station's name in Now Playing and the mini
// player. And light means on air (docs/design/tells.md, 1): the mark is
// drawn flat — Copper outside, Glow inside, a flat core, no blur, no bloom.
// Only a station's artwork, while that station is on the air, is lit.
//
// The geometry is dev/brand/geom.py's, number for number (ArchCut, in
// ArtMeasures.swift): change both together. Drawn with Path so it can tint,
// template and fade — the bands come on one by one on the welcome screen.

import SwiftUI

// MARK: - Geometry

// ArchCut and ArchSquare, the numbers, are in ArtMeasures.swift: Linux
// draws the mark from them too.

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
/// `.flat`: the outer band Copper, the inner Glow, the core a warm white by
/// night and amber by day — the loading screen, the welcome's icon.
/// `.template`: every part in the foreground style, for a line of text or a
/// glyph's place (Now Playing's and the mini player's station, in the accent).
struct ArchMark: View {
    enum Style {
        case flat
        case template
    }

    let size: CGFloat
    let style: Style

    init(size: CGFloat, style: Style = .flat) {
        self.size = size
        self.style = style
    }

    var body: some View {
        ArchMarkFace(size: size, style: style)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The mark drawn once, each part at its own level: 1 on, 0 cold glass.
/// What ArchMark draws, and the welcome's icon as its bands come on.
struct ArchMarkFace: View {
    let size: CGFloat
    let style: ArchMark.Style
    var outer: Double = 1
    var inner: Double = 1
    var core: Double = 1

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
            ArchLine(tube: 0, cut: cut).stroke(paint(Theme.Arch.copper), style: line)
                .opacity(level(outer))
            ArchLine(tube: 1, cut: cut).stroke(paint(Theme.Arch.glow), style: line)
                .opacity(level(inner))
            ArchCore(cut: cut).fill(paint(Theme.Arch.markCore))
                .opacity(level(core))
        }
        .frame(width: size, height: size)
    }

    /// Off, a part is still there, as cold glass.
    private func level(_ value: Double) -> Double {
        0.16 + 0.84 * value
    }

    private func paint(_ flat: Color) -> AnyShapeStyle {
        style == .flat ? AnyShapeStyle(flat) : AnyShapeStyle(ForegroundStyle())
    }
}
