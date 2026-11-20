// The app's mark on its own ground, shaped as the icon is on the Home
// Screen, in Settings' About: the mark flat on Cabinet, Copper outside, Glow
// inside, a warm white core. No halo, no room lit around it: light means on
// air (docs/design/tells.md, 1).
//
// And the welcome's picture, WelcomeSleeve: that mark on its sleeve, the
// record half out, as Now Playing draws them. It opens close on the sleeve,
// which fills the picture, and the mark comes on as a jukebox does when it
// is switched on: the outer band drawn, then the inner, then the core. Then
// the picture draws back to the whole sleeve and the record slides out.
// The photographer, 17 November 2026: "A is soort ingezoomde B dus ik wil
// eerst die opbouw en dan uitzoomen naar B". About 4 s, beside a form that
// can be typed in all the while. The record does not turn: the welcome
// plays nothing. Under Reduce Motion it simply stands there.

import SwiftUI

struct ShellAppMark: View {
    /// The tile's side.
    var side: CGFloat

    init(side: CGFloat) {
        self.side = side
    }

    var body: some View {
        // As on the app icon: the mark's 32-unit box at 22.4 units to 1024,
        // a little below the middle.
        ArchMarkFace(size: side * 0.7, style: .flat)
            .offset(y: side * 12 / 1024)
            .frame(width: side, height: side)
            .background(Theme.Arch.cabinet)
            // The Home Screen's own shape for an icon.
            .clipShape(.rect(cornerRadius: side * 0.2237, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            // The core's warm white, as on Cabinet in either appearance.
            .environment(\.colorScheme, .dark)
            .accessibilityHidden(true)
    }
}

// MARK: - The welcome's picture

/// The sleeve with its record half out, `width` across and two thirds as
/// tall, drawn in units of a 300th of that: the sleeve 180 square at (20,
/// 10), the record 172 across, its centre 8 beyond the sleeve's open edge as
/// on Now Playing.
struct WelcomeSleeve: View {
    var width: CGFloat
    /// Build the mark up and draw back when it first appears (the welcome;
    /// not Settings' Add Account, which is no first sight).
    var animatesIn = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The page's own appearance, for the core while the arches stand on
    /// the page without their sleeve.
    @Environment(\.colorScheme) private var pageScheme
    /// How far it has come: 1 the outer band drawn, 2 the inner, 3 the core
    /// on, 4 drawn back to the whole sleeve, 5 the record out.
    @State private var stage = 0

    init(width: CGFloat, animatesIn: Bool = true) {
        self.width = width
        self.animatesIn = animatesIn
    }

    /// Each step's wait after the one before it, and how it moves.
    private static let steps: [(wait: Double, animation: Animation)] = [
        (0.2, .easeOut(duration: 0.9)),
        (0.8, .easeOut(duration: 0.8)),
        (0.7, .easeOut(duration: 0.45)),
        (0.7, .easeInOut(duration: 1.1)),
        (0.8, .easeOut(duration: 1.0)),
    ]

    var body: some View {
        let unit = width / 300
        ZStack(alignment: .topLeading) {
            // Its label Copper, as Home's small record; its one word the
            // app's name, where an album's title is printed.
            VinylDisc(diameter: 172 * unit, bands: [],
                      label: RecordLabel(title: "Jukebox", artist: "", disc: nil),
                      tone: AverageColor(red: 0xA8 / 255, green: 0x4A / 255, blue: 0x17 / 255))
                .drawingGroup()
                // Behind the sleeve, wholly, until it slides out; not there
                // before, so it never shows through the sleeve coming on.
                .opacity(reached(5) ? 1 : 0)
                .offset(x: (reached(5) ? 122 : 24) * unit, y: 14 * unit)
            sleeve(side: 180 * unit)
                .offset(x: 20 * unit, y: 10 * unit)
        }
        .frame(width: width, height: 200 * unit, alignment: .topLeading)
        // Close: 2.4 times as large, the mark's crown at the picture's top
        // and its legs running out below, on the page's own ground, with no
        // box round it.
        .scaleEffect(reached(4) ? 1 : 2.4, anchor: UnitPoint(x: 0.2714, y: 0.3536))
        // Close, the legs run on below the picture: they fade out there
        // rather than end on a line, which would read as a box again.
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: reached(4) ? 1 : 0.7),
                                   .init(color: reached(4) ? .black : .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
        .task {
            guard animatesIn, !reduceMotion else { return }
            // From where it was, should the page have been away meanwhile.
            while stage < Self.steps.count {
                let step = Self.steps[stage]
                try? await Task.sleep(for: .seconds(step.wait))
                guard !Task.isCancelled else { return }
                withAnimation(step.animation) {
                    stage += 1
                }
            }
        }
    }

    /// At rest from the first frame (Add Account, or Reduce Motion): all of
    /// it there, so nothing flashes in.
    private func reached(_ step: Int) -> Bool {
        !animatesIn || reduceMotion || stage >= step
    }

    /// The sleeve: Cabinet card with the mark printed on it, at 0.7 of its
    /// side and a little below the middle, as on the app icon.
    private func sleeve(side: CGFloat) -> some View {
        let cut = ArchCut.regular
        let size = side * 0.7
        let line = StrokeStyle(lineWidth: cut.stroke * size / 32, lineCap: .round)
        return ZStack {
            ArchLine(tube: 0, cut: cut)
                .trim(from: 0, to: reached(1) ? 1 : 0)
                .stroke(Theme.Arch.copper, style: line)
            ArchLine(tube: 1, cut: cut)
                .trim(from: 0, to: reached(2) ? 1 : 0)
                .stroke(Theme.Arch.glow, style: line)
            ArchCore(cut: cut)
                .fill(Theme.Arch.markCore)
                .opacity(reached(3) ? 1 : 0)
        }
        .frame(width: size, height: size)
        .offset(y: side * 12 / 1024)
        .frame(width: side, height: side)
        // The sleeve comes only as the mark draws back: first the arches
        // alone on the page, then the sleeve round them, then the record.
        // "Het intro van de app speelt zich nu af in een soort container ik
        // wil eerst die bogen zien dan pas dat er een hoes bijkomt en dan de
        // plaat" (the photographer, 20 November 2026).
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                .fill(Theme.Arch.cabinet)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .opacity(reached(4) ? 1 : 0)
        }
        // On the sleeve the core's warm white, as on Cabinet in either
        // appearance; before it, on the page, the page's own core.
        .environment(\.colorScheme, reached(4) ? .dark : pageScheme)
    }
}
