// The app icon, live (ArchAppIcon): the mark lit on Cabinet, shaped as the
// icon is on the Home Screen — on the welcome screen and in Settings' About.
// Always on its own dark ground, in light mode as in dark: a light needs
// the dark around it to be one.
//
// On the welcome screen it warms up, as a jukebox's tubes do when it is
// switched on: the tubes cold glass at first, then the outer one lit, then
// the inner, then the core, in about 1.2 s — fast enough not to keep anyone
// from the sign-in form under it. Under Reduce Motion it is simply lit.

import SwiftUI

struct ShellAppMark: View {
    /// The tile's side.
    var side: CGFloat
    /// Warm the tubes up when it first appears (the welcome screen only).
    var animatesIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the warm-up has come: 0 cold, 1 the outer tube lit, 2 the
    /// inner, 3 the core.
    @State private var stage = 0

    init(side: CGFloat, animatesIn: Bool = false) {
        self.side = side
        self.animatesIn = animatesIn
    }

    var body: some View {
        // At rest from the first frame (About, or Reduce Motion): lit, so
        // nothing flashes in.
        let lit = !animatesIn || reduceMotion
        ArchAppIcon(side: side,
                    outer: lit || stage >= 1 ? 1 : 0,
                    inner: lit || stage >= 2 ? 1 : 0,
                    core: lit || stage >= 3 ? 1 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
            .task {
                guard animatesIn, !reduceMotion, stage == 0 else { return }
                // One part at a time, each lighting over 0.45 s, the next
                // starting before the last has settled: done at 1.25 s.
                for next in 1...3 {
                    try? await Task.sleep(for: .seconds(next == 1 ? 0.2 : 0.3))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.45)) {
                        stage = next
                    }
                }
            }
    }
}
