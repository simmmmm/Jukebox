// The Arch's shapes: a tube's centre line, the core, the window a station's
// covers are seen through. A file of their own, SwiftUI and ArchCut only, so
// the widget (JukeboxWidget/) draws the mark from the same lines as the app;
// ArchMark.swift and StationArtwork.swift paint them.

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
