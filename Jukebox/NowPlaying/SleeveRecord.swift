// The album's sleeve and its record, in the cover's place on Now Playing:
// sketch E's variant D, the sleeve as it is — "Maak ook even een hele andere
// abstractere variant waarbij de hoes de hoes is maar de achtergrond helemaal
// anders" — chosen by the photographer, 8 November 2026: "Dus ik denk dat d1
// en d2 vooral d2 het best gaan werken. D1 is reduced motion/batterij
// besparing d2 normaal." Before it, of the record player: "de hoes er achter
// zetten" — the sleeve is now the thing itself, and the record comes out of
// it — and "Het moet minder een los object zijn en meer verweven zitten met
// de pagina": the deck, its plinth and its arm went, and the page's own
// ground became the record (NowPlayingGround: D2's land, D1's wall).
//
// The sleeve is printed card: the cover, a thickness at its foot and a
// hair of its open edge, paper grain, faint ring wear where a record has
// pressed it for years, a little light on its top edge, and a soft shadow
// from a light above — black on the land, the wall's own dark on a wall, as
// a shadow falls on coloured paper. The black record comes half out of its
// open (right) edge: grooves, the album's songs as bands, the label in the
// cover's colour with the album and its artist printed on it. Only the label
// shows the record turning (its grooves are round), a turn in 10 s; the
// light on the grooves stays where it is.
//
// Battery: the record is drawn once into one layer (`drawingGroup`) and
// turning it changes only that layer's rotation, on NowPlayingGround's one
// timeline, which runs only while it turns (RecordMotion). The sleeve, the
// grain, the shadows and the sheen are drawn once and hold still. The
// sleeve and its record are decoration: VoiceOver skips them; every control
// around them is Apple's.

import JukeboxKit
import SwiftUI
import UIKit

/// The words on the record's label: the album's title, its artist, and its
/// disc's number when the album has more than one ("Disc 2").
nonisolated struct RecordLabel: Equatable, Sendable {
    let title: String
    let artist: String
    let disc: Int?

    init(title: String, artist: String, disc: Int?) {
        self.title = title
        self.artist = artist
        self.disc = disc
    }
}

// MARK: - The sleeve

/// The album's sleeve as printed card, `side` points square, at the one
/// radius artwork has (Theme.Radius.artwork). Its thickness and its
/// shadows are drawn behind it, below and to the right, so the view's frame
/// is the face's.
struct SleeveCard: View {
    let artwork: Artwork?
    let side: CGFloat
    /// The card's edge: the cover's own colour, darker (sketch E: its
    /// average mixed with 45% black), so a cream sleeve has a light edge
    /// and a black one a black edge.
    let edge: Color
    /// The colour the shadows are cast in, and how strong they are: black
    /// at 1.5 on D2's dark land, the wall's own dark at 0.95 on D1's wall.
    let shadow: Color
    let strength: Double

    init(artwork: Artwork?, side: CGFloat, edge: Color, shadow: Color, strength: Double) {
        self.artwork = artwork
        self.side = side
        self.edge = edge
        self.shadow = shadow
        self.strength = strength
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            thickness
            face
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }

    /// The card's thickness: its edge colour showing at the foot and the
    /// open side, and the shadows it casts. Four shadows, as sketch E has
    /// them (a contact shadow, two soft ones down from the light above, a
    /// faint one to the left), each on its own copy of the card so that
    /// none is the shadow of another. Drawn once.
    private var thickness: some View {
        let k = strength
        return ZStack(alignment: .topLeading) {
            card.shadow(color: shadow.opacity(min(1, 0.45 * k)), radius: 1, x: 0, y: 1)
            card.shadow(color: shadow.opacity(min(1, 0.34 * k)), radius: 13, x: 0, y: 12)
            card.shadow(color: shadow.opacity(min(1, 0.22 * k)), radius: 35, x: 0, y: 34)
            card.shadow(color: shadow.opacity(min(1, 0.10 * k)), radius: 7, x: -6, y: 0)
        }
        .offset(x: 0.6, y: 2.6)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.artwork)
            .fill(edge)
            .frame(width: side, height: side)
    }

    /// The printed face: the cover, ring wear, grain, the light on its top
    /// edge, the open edge a little in shade.
    private var face: some View {
        ArtworkView(artwork, size: side)
            .overlay {
                wear
            }
            .overlay {
                grain
            }
            .overlay(alignment: .top) {
                // The light from above on the card's top edge.
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 1)
            }
            .overlay(alignment: .trailing) {
                // The open edge, where the record comes out, a little in shade.
                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.18)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
            }
            .clipShape(.rect(cornerRadius: Theme.Radius.artwork))
    }

    /// Ring wear: the record's rim and its label pressed into the card over
    /// the years, white at 4%, softened. Barely there, as on a real sleeve.
    private var wear: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: side * 0.014)
                .frame(width: side * 0.916, height: side * 0.916)
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: side * 0.006)
                .frame(width: side * 0.33, height: side * 0.33)
        }
        .offset(x: -side * 0.01)
        .blur(radius: side * 0.006)
        .opacity(0.04)
        .allowsHitTesting(false)
    }

    /// Paper grain over the print (SleeveGrain), tiled.
    @ViewBuilder private var grain: some View {
        if let image = SleeveGrain.image {
            Image(decorative: image, scale: 2)
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
        }
    }
}

/// Paper grain: 128 pixels of noise, each a little lighter or darker than
/// the print under it (white or black at up to 15%), so the cover reads as
/// ink on card, not as a screen. Made once, the same every time (its
/// numbers come from a fixed seed), and tiled.
enum SleeveGrain {
    static let image: CGImage? = make()

    private static func make() -> CGImage? {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt64 = 7
        for i in 0..<(side * side) {
            // Three uniforms summed: near enough a bell, around 1.5.
            var sum = 0.0
            for _ in 0..<3 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                sum += Double(seed >> 11) / 9_007_199_254_740_992
            }
            let deviation = (sum - 1.5) / 1.5
            let alpha = UInt8((min(1, abs(deviation)) * 0.15 * 255).rounded())
            // Premultiplied: white at `alpha` is (alpha, alpha, alpha, alpha).
            let ink: UInt8 = deviation > 0 ? alpha : 0
            bytes[i * 4] = ink
            bytes[i * 4 + 1] = ink
            bytes[i * 4 + 2] = ink
            bytes[i * 4 + 3] = alpha
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - The record

/// The black record, `diameter` across: grooves, the album's songs as
/// bands, the run-out, the label with its words, the hole. Drawn once
/// (NowPlayingGround gives it `drawingGroup`) and turned as a whole.
///
/// Every value here is the stage's as it is, not made afresh: the timeline
/// builds this view anew every frame, and a record with the same values is
/// not drawn again. `tone` is the cover's colour as three numbers; the
/// label's Color is made from it in the body, which runs only when the
/// record changes.
struct VinylDisc: View {
    let diameter: CGFloat
    /// Where one song ends and the next begins, 0 … 1 from the outer groove
    /// to the run-out (TurntableSide.bands).
    let bands: [Double]
    let label: RecordLabel?
    let tone: AverageColor?

    init(diameter: CGFloat, bands: [Double], label: RecordLabel?, tone: AverageColor?) {
        self.diameter = diameter
        self.bands = bands
        self.label = label
        self.tone = tone
    }

    var body: some View {
        let radius = diameter / 2
        let outer = radius * 0.955
        let inner = radius * 0.40
        ZStack {
            Circle()
                .fill(Self.vinyl)
            // The lead-in at the rim: smooth, catching a little more light.
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: radius * 0.02)
                .frame(width: radius * 1.97, height: radius * 1.97)
            VinylRings(radii: grooves(from: outer, to: inner, strong: false))
                .stroke(Color.white.opacity(0.045), lineWidth: 0.5)
            VinylRings(radii: grooves(from: outer, to: inner, strong: true))
                .stroke(Color.white.opacity(0.075), lineWidth: 0.5)
            songBands(outer: outer, inner: inner, radius: radius)
            // The run-out: smooth to the label.
            Circle()
                .fill(Self.runOut)
                .frame(width: inner * 2, height: inner * 2)
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                .frame(width: radius * 0.74, height: radius * 0.74)
            VinylLabelFace(label: label, color: labelColor, radius: radius * 0.33,
                           holeRadius: max(1.6, radius * 0.016))
        }
        .frame(width: diameter, height: diameter)
    }

    /// The grooves: fine rings a little over a point apart, every third a
    /// little stronger, so the surface has a grain.
    private func grooves(from outer: CGFloat, to inner: CGFloat, strong: Bool) -> [CGFloat] {
        let step = max(1.1, diameter / 240)
        var radii: [CGFloat] = []
        var r = outer
        var k = 0
        while r > inner {
            if k.isMultiple(of: 3) == strong {
                radii.append(r)
            }
            r -= step
            k += 1
        }
        return radii
    }

    /// Where one song ends and the next begins: the smooth, darker vinyl
    /// between them, with a faint light edge where it catches the light.
    private func songBands(outer: CGFloat, inner: CGFloat, radius: CGFloat) -> some View {
        let width = max(2.2, radius * 0.022)
        let radii = bands.map { outer - (outer - inner) * CGFloat($0) }
        return ZStack {
            VinylRings(radii: radii)
                .stroke(Self.land, lineWidth: width)
            VinylRings(radii: radii.map { $0 + width / 2 })
                .stroke(Color.white.opacity(0.16), lineWidth: 0.6)
        }
    }

    /// The label: a flat colour from the cover — its hue, its saturation
    /// held to 0.45, at brightness 0.3, dark enough that the words on it
    /// read in paper white — or, until the cover's colour is known, a dark
    /// brown.
    private var labelColor: Color {
        guard let tone else { return Color(rgb: 0x1A1411) }
        let hsb = tone.hueSaturationBrightness
        return Color(hue: hsb.hue, saturation: min(hsb.saturation, 0.45), brightness: 0.3)
    }

    /// Black vinyl, the smooth land between songs, the run-out.
    static let vinyl = Color(rgb: 0x100D0C)
    private static let land = Color(rgb: 0x070505)
    private static let runOut = Color(rgb: 0x0C0A09)
}

/// Circles about the middle of the frame, `radii` points out: the
/// record's grooves and bands, one path for many.
nonisolated struct VinylRings: Shape {
    let radii: [CGFloat]

    init(radii: [CGFloat]) {
        self.radii = radii
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for r in radii where r > 0 {
            path.addEllipse(in: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

/// A ring between two radii about the middle of the frame, filled
/// even-odd: the sheen on the grooves, and the land's played grooves.
nonisolated struct RingShape: Shape {
    let outer: CGFloat
    let inner: CGFloat

    init(outer: CGFloat, inner: CGFloat) {
        self.outer = outer
        self.inner = inner
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.midX - outer, y: rect.midY - outer, width: outer * 2, height: outer * 2))
        if inner > 0 {
            path.addEllipse(in: CGRect(x: rect.midX - inner, y: rect.midY - inner, width: inner * 2, height: inner * 2))
        }
        return path
    }
}

/// The label: its colour, a fine printed ring near its edge, the album's
/// title in the serif above the hole and its artist below, straight and
/// small as a label is printed, "Disc 2" under them when the album has
/// discs. Drawn to the record's size, not the reader's text size: it is a
/// picture, and VoiceOver skips it. One ink, paper white.
private struct VinylLabelFace: View {
    let label: RecordLabel?
    let color: Color
    let radius: CGFloat
    let holeRadius: CGFloat

    init(label: RecordLabel?, color: Color, radius: CGFloat, holeRadius: CGFloat) {
        self.label = label
        self.color = color
        self.radius = radius
        self.holeRadius = holeRadius
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
            Circle()
                .stroke(Self.ink.opacity(0.28), lineWidth: 0.6)
                .frame(width: radius * 1.84, height: radius * 1.84)
            // No words on a label too small to print them.
            if let label, radius >= 10 {
                words(label)
            }
            Circle()
                .fill(Color(rgb: 0x0A0807))
                .frame(width: holeRadius * 2, height: holeRadius * 2)
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    /// As sketch E prints them: the title at 0.17 of the label's radius,
    /// its line 0.35 of the radius above the hole; the artist at 0.12, 0.38
    /// below; the disc under it. Each narrow enough to stay inside the
    /// ring; a long title is made a little smaller, then cut short.
    private func words(_ label: RecordLabel) -> some View {
        let titleSize = max(5.5, radius * 0.17)
        let artistSize = max(4.5, radius * 0.122)
        return ZStack {
            if !label.title.isEmpty {
                Text(label.title)
                    .font(.system(size: titleSize, weight: .regular, design: .serif))
                    .foregroundStyle(Self.ink.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: radius * 1.3)
                    .position(x: radius, y: radius * 0.65)
            }
            if !label.artist.isEmpty {
                Text(label.artist)
                    .font(.system(size: artistSize))
                    .foregroundStyle(Self.ink.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: radius * 1.3)
                    .position(x: radius, y: radius * 1.38)
            }
            if let disc = label.disc {
                Text("Disc \(disc)")
                    .font(.system(size: artistSize))
                    .foregroundStyle(Self.ink.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: radius * 0.8)
                    .position(x: radius, y: radius * 1.62)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    /// Paper white, Theme.ground's by day.
    private static let ink = Color(rgb: 0xF6F3EE)
}

/// The light on the grooves: two soft wedges half a turn apart, white at a
/// tenth at their brightest, on the grooves only (not the label). They do
/// not turn: the record turns under them, as under a lamp.
struct VinylSheen: View {
    let diameter: CGFloat

    init(diameter: CGFloat) {
        self.diameter = diameter
    }

    var body: some View {
        let radius = diameter / 2
        let light = Color(red: 1, green: 244 / 255, blue: 228 / 255)
        let gradient = Gradient(stops: [
            .init(color: light.opacity(0), location: 0),
            .init(color: light.opacity(0.12), location: 14.0 / 360),
            .init(color: light.opacity(0), location: 30.0 / 360),
            .init(color: light.opacity(0), location: 0.5),
            .init(color: light.opacity(0.09), location: 194.0 / 360),
            .init(color: light.opacity(0), location: 210.0 / 360),
            .init(color: light.opacity(0), location: 1),
        ])
        // Sketch E's wedges start at −28° from straight up; SwiftUI counts
        // from the right, so 90° less.
        return RingShape(outer: radius, inner: radius * 0.34)
            .fill(AngularGradient(gradient: gradient, center: .center,
                                  startAngle: .degrees(-118), endAngle: .degrees(242)),
                  style: FillStyle(eoFill: true))
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
    }
}

/// The record's shadow on the ground: a circle, so it need not turn. Three
/// shadows, as sketch E has them — a contact shadow and two soft ones down
/// from the light above — each on its own disc. Drawn once.
struct VinylShadow: View {
    let diameter: CGFloat
    let color: Color
    let strength: Double

    init(diameter: CGFloat, color: Color, strength: Double) {
        self.diameter = diameter
        self.color = color
        self.strength = strength
    }

    var body: some View {
        let k = strength
        return ZStack {
            disc.shadow(color: color.opacity(min(1, 0.40 * k)), radius: 1.5, x: 0, y: 2)
            disc.shadow(color: color.opacity(min(1, 0.32 * k)), radius: 14, x: 0, y: 14)
            disc.shadow(color: color.opacity(min(1, 0.16 * k)), radius: 30, x: 0, y: 30)
        }
        .allowsHitTesting(false)
    }

    private var disc: some View {
        Circle()
            .fill(VinylDisc.vinyl)
            .frame(width: diameter, height: diameter)
    }
}
