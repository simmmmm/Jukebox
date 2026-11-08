// The app's mark on its own ground, shaped as the icon is on the Home
// Screen — on the welcome screen and in Settings' About: the mark flat on
// Cabinet, Copper outside, Glow inside, a warm white core. No halo, no
// room lit around it: light means on air (docs/design/tells.md, 1), and the
// welcome plays nothing.
//
// On the welcome screen it warms up, as a jukebox does when it is switched
// on: the bands start as cold glass, then the outer one comes on, then the
// inner, then the core, in about 1.2 s, as a fade — fast enough not to keep
// anyone from the sign-in form under it. Under Reduce Motion it is simply on.

import SwiftUI

struct ShellAppMark: View {
    /// The tile's side.
    var side: CGFloat
    /// Warm the bands up when it first appears (the welcome screen only).
    var animatesIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the warm-up has come: 0 cold, 1 the outer band on, 2 the
    /// inner, 3 the core.
    @State private var stage = 0

    init(side: CGFloat, animatesIn: Bool = false) {
        self.side = side
        self.animatesIn = animatesIn
    }

    var body: some View {
        // At rest from the first frame (About, or Reduce Motion): on, so
        // nothing flashes in.
        let on = !animatesIn || reduceMotion
        // dev/brand/icon.py: the mark's 32-unit box at 22.4 units to 1024,
        // a little below the middle.
        ArchMarkFace(size: side * 0.7, style: .flat,
                     outer: on || stage >= 1 ? 1 : 0,
                     inner: on || stage >= 2 ? 1 : 0,
                     core: on || stage >= 3 ? 1 : 0)
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
            .task {
                guard animatesIn, !reduceMotion, stage == 0 else { return }
                // One part at a time, each fading on over 0.45 s, the next
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
