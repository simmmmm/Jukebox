// The mark on its own tile, as the app icon has it (dev/make-icon.py: each
// disc half the tile's side, on Numa's page grey, a little lighter at the
// top). The light disc is a white glow that clears toward its centre: on a
// light page it would all but vanish, so here it always sits on its own dark
// ground, in light mode as in dark — the way it looks on the Home Screen.
//
// On the welcome screen the two discs slide in and settle into the eclipse,
// as Numa's intro does (Numa-mac's PhoneIntro: the light disc from the left
// out of a blur, the dark one from the right, the same ease-out curve), in
// 1.2 s rather than Numa's 1.6, because here it opens a sign-in form rather
// than the app. Under Reduce Motion the mark is simply there.

import SwiftUI

struct ShellAppMark: View {
    /// One disc's diameter; the tile is twice that.
    var diameter: CGFloat
    /// Slide the discs in when it first appears (the welcome screen only).
    var animatesIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasArrived = false

    init(diameter: CGFloat, animatesIn: Bool = false) {
        self.diameter = diameter
        self.animatesIn = animatesIn
    }

    var body: some View {
        let side = diameter * 2
        let corner = side * 0.2237
        Group {
            if animatesIn && !reduceMotion {
                arrivingMark
            } else {
                // At rest from the first frame (About, or Reduce Motion): the
                // shared mark itself, so nothing flashes in.
                JukeboxMark(diameter: diameter)
            }
        }
        .frame(width: side, height: side)
        .background {
            LinearGradient(colors: [Color(white: 0x1c / 255), Color(white: 0x10 / 255)],
                           startPoint: .top, endPoint: .bottom)
        }
        // The discs start outside the tile: clipped, they enter from its edges.
        .clipShape(.rect(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task {
            guard animatesIn, !reduceMotion, !hasArrived else { return }
            // Numa's intro curve: fast in, a long gentle settle.
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.2).delay(0.2)) {
                hasArrived = true
            }
        }
    }

    /// JukeboxMark's two discs, drawn apart until they have arrived: the
    /// record a tile's width to the right, the glow a tile's width to the
    /// left and blurred, as if coming into focus.
    private var arrivingMark: some View {
        let away = diameter * 2
        return ZStack(alignment: .topLeading) {
            RecordDisc()
                .frame(width: diameter, height: diameter)
                .offset(x: diameter * Eclipse.spacing + (hasArrived ? 0 : away))
            GlowDisc()
                .frame(width: diameter, height: diameter)
                .blur(radius: hasArrived ? 0 : diameter * 0.15)
                .offset(x: hasArrived ? 0 : -away)
        }
        .frame(width: diameter * (1 + Eclipse.spacing), height: diameter, alignment: .topLeading)
    }
}
