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
// The geometry is ArchCut's (ArtMeasures.swift), the mark's one source,
// which Linux's Drawings.swift reads too. Drawn with Path so it can tint,
// template and fade — the bands come on one by one on the welcome screen.

import SwiftUI

// ArchLine, ArchCore and ArchWindow, the shapes, are in ArchShapes.swift:
// the widget draws the mark from them too.

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
