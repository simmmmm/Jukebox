// Numa's eclipse, Jukebox's way. The mark is Numa-mac's NumaMark (two discs
// of one diameter, centres 0.505 diameters apart, the light one on the left
// and on top: a glow white at its rim that clears toward its centre, so the
// dark disc shows through), with the dark disc a record — the app icon
// (dev/make-icon.py) drawn live. A station's artwork is the same eclipse
// with the seed's cover as the dark disc: every station is recognisably
// Jukebox's, and recognisably its seed's.

import JukeboxKit
import SwiftUI

enum Eclipse {
    /// Centre to centre, in diameters (NumaMark.spacing).
    static let spacing: CGFloat = 0.505

    /// NumaMark's light disc, sampled from Numa's mark.png.
    static let glow = EllipticalGradient(stops: [
        .init(color: Color(white: 0.500, opacity: 0.22), location: 0),
        .init(color: Color(white: 0.543, opacity: 0.24), location: 0.1),
        .init(color: Color(white: 0.745, opacity: 0.266), location: 0.2),
        .init(color: Color(white: 0.803, opacity: 0.35), location: 0.3),
        .init(color: Color(white: 0.846, opacity: 0.443), location: 0.4),
        .init(color: Color(white: 0.878, opacity: 0.539), location: 0.5),
        .init(color: Color(white: 0.909, opacity: 0.633), location: 0.6),
        .init(color: Color(white: 0.938, opacity: 0.727), location: 0.7),
        .init(color: Color(white: 0.968, opacity: 0.818), location: 0.8),
        .init(color: Color(white: 0.999, opacity: 0.907), location: 0.9),
        .init(color: Color(white: 1, opacity: 0.96), location: 0.97),
        .init(color: Color(white: 1, opacity: 0.97), location: 1),
    ], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
}

/// The light disc, with the rim's slight bloom.
struct GlowDisc: View {
    var body: some View {
        Circle()
            .fill(Eclipse.glow)
            .shadow(color: .white.opacity(0.3), radius: 1)
    }
}

/// A record: #444 at the upper-left rim to #080808 at the lower right, fine
/// grooves, a label and the spindle hole.
struct RecordDisc: View {
    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0x4c / 255), Color(white: 0x06 / 255)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                ForEach(0..<14, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.white.opacity(i % 5 == 0 ? 0.09 : 0.045), lineWidth: max(0.5, d * 0.002))
                        .padding(d * (0.02 + CGFloat(i) * 0.024))
                }
                Circle()
                    .fill(Color(white: 0x30 / 255))
                    .overlay(Circle().strokeBorder(Color(white: 0x48 / 255), lineWidth: max(0.5, d * 0.004)))
                    .frame(width: d * 0.3, height: d * 0.3)
                Circle()
                    .fill(Color(white: 0x10 / 255))
                    .frame(width: d * 0.035, height: d * 0.035)
            }
            .frame(width: d, height: d)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The mark: glow over record. `diameter` is one disc's; the mark is
/// 1.505 diameters wide.
struct JukeboxMark: View {
    var diameter: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RecordDisc()
                .frame(width: diameter, height: diameter)
                .offset(x: diameter * Eclipse.spacing)
            GlowDisc()
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter * (1 + Eclipse.spacing), height: diameter, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// A station's artwork: the glow over the seed's cover, in a square of
/// Numa's page grey. `size` nil: as wide as offered.
struct StationArtwork: View {
    let station: Station
    var size: CGFloat?
    var cornerRadius: CGFloat = Theme.Radius.artwork

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let d = side / (1 + Eclipse.spacing) * 0.86
            ZStack {
                Theme.page
                ZStack(alignment: .topLeading) {
                    Group {
                        if let cover = station.artwork.first {
                            ArtworkView(cover, size: d, cornerRadius: d / 2)
                        } else {
                            RecordDisc()
                        }
                    }
                    .frame(width: d, height: d)
                    .clipShape(.circle)
                    .offset(x: d * Eclipse.spacing)
                    GlowDisc()
                        .frame(width: d, height: d)
                }
                .frame(width: d * (1 + Eclipse.spacing), height: d, alignment: .topLeading)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}
