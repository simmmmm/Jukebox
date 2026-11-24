import SwiftUI

/// What lights under the pointer, on the Mac and on the iPad with one, as
/// Linux's rows and tiles light under GNOME's: "ik mis de hover states
/// hier" (the photographer, 24 November 2026, of Home's Played lately and
/// the songs under the panel's head). One fill of the text's own colour,
/// never the accent, which means on air. A finger has no pointer, so on
/// the iPhone nothing happens. The iPad gets this same fill rather than
/// its own hover effect: the platter that one draws is not Linux's look.
enum PointerHover {
    /// A song's row (TrackRow, Up Next's), Search's recent searches: lit
    /// 8 past its ends, corners of 8.
    case row
    /// A tile (WideTile), and Played lately's rows, which are tiles on
    /// Linux (Pages.latelyRows' tileButton): lit 8 past it on every side,
    /// corners concentric with the art's, 6 + 8.
    case tile
    /// Home's cards: their raised ground a little darker, as Linux's
    /// `button.home-card:hover` (shade 0.97), nothing past them.
    case card
}

extension View {
    /// The pointer's light (PointerHover). `picked`: a row picked with ⌘ or
    /// ⇧, lit a little more, as a selected row is, whether under the
    /// pointer or not; one fill, so picked and hover never stack.
    func pointerHover(_ kind: PointerHover, picked: Bool = false) -> some View {
        modifier(PointerHoverLight(kind: kind, picked: picked))
    }
}

extension EnvironmentValues {
    /// Where the pointer is taken to be, in the window's points: the Mac's
    /// snapshots (JukeboxSnapshots), drawn offscreen where no pointer
    /// comes, light what lies under these. Empty in the app.
    @Entry var pointerAt: [CGPoint] = []
}

private struct PointerHoverLight: ViewModifier {
    let kind: PointerHover
    let picked: Bool

    @Environment(\.pointerAt) private var pointerAt
    @State private var isHovered = false
    @State private var isUnderSnapshotPointer = false

    func body(content: Content) -> some View {
        let lit = isHovered || isUnderSnapshotPointer
        lighted(content, lit: lit)
            .onHover { isHovered = $0 }
            .modifier(SnapshotPointer(points: pointerAt, isUnder: $isUnderSnapshotPointer))
    }

    @ViewBuilder private func lighted(_ content: Content, lit: Bool) -> some View {
        switch kind {
        case .row:
            content.background {
                RoundedRectangle(cornerRadius: Theme.Space.s)
                    .fill(Color.primary.opacity(picked ? 0.1 : lit ? 0.07 : 0))
                    .padding(.horizontal, -Theme.Space.s)
            }
        case .tile:
            content.background {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork + Theme.Space.s)
                    .fill(Color.primary.opacity(lit ? 0.07 : 0))
                    .padding(-Theme.Space.s)
            }
        case .card:
            content.overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork + Theme.Space.m)
                    .fill(Color.black.opacity(lit ? 0.03 : 0))
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Watches the view's place only while the snapshots give a pointer, so
/// the app's rows do not measure themselves on every scroll.
private struct SnapshotPointer: ViewModifier {
    let points: [CGPoint]
    @Binding var isUnder: Bool

    func body(content: Content) -> some View {
        let points = points
        if points.isEmpty {
            content
        } else {
            content.onGeometryChange(for: Bool.self) { proxy in
                let frame = proxy.frame(in: .global)
                return points.contains { frame.contains($0) }
            } action: { isUnder = $0 }
        }
    }
}
