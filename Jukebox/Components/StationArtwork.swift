// A station's artwork, the Arch's way (docs/BRAND.md, dev/brand/station.py,
// which draws the same with these same numbers): the arch's window with the
// seed's music in it — one cover for a song or an album, four as panes for
// an artist, a genre, a decade or a playlist — two tubes of light around
// it, and as the room the first cover's own colour, darkened. Every station
// is recognisably Jukebox's, and recognisably its seed's. The stations made
// from the listener's own taste (Your Station, Discovery, Loved) have no
// one seed to show: their window holds the mark's core, lit.
//
// Only stations are drawn so: lit means endless. A mix, an album or a
// playlist stays a square cover.

import JukeboxKit
import SwiftUI
import UIKit

/// The art's measures in a 300-unit square (station.py's `Cut`). `t` the
/// tube's stroke, `g` the gaps, `rw` the window's half width, `top` the
/// outer tube's top edge, `base` where the window, the legs and the core end.
nonisolated struct StationArtCut: Equatable, Sendable {
    let t: CGFloat
    let g: CGFloat
    let rw: CGFloat
    let top: CGFloat
    let base: CGFloat

    /// The inner and the outer tube's centre lines.
    var innerRadius: CGFloat { rw + g + t / 2 }
    var outerRadius: CGFloat { innerRadius + t + g }
    /// Where the arcs spring from.
    var spring: CGFloat { top + t / 2 + outerRadius }
    var leg: CGFloat { base - t / 2 }
    var windowTop: CGFloat { spring - rw }
    /// The lit core's radius, in proportion to the window as on the board.
    var coreRadius: CGFloat { rw * 25 / 70 }

    /// From 200 points: the station's name is drawn under the window. A
    /// shelf's tile has its name as real Text under it, which follows the
    /// reader's text size; art this large stands alone (a station's page).
    static let named = StationArtCut(t: 4.4, g: 5.6, rw: 70, top: 22, base: 228)
    /// A tile: the window takes the room the name would have had.
    static let tile = StationArtCut(t: 6, g: 6.5, rw: 82, top: 26, base: 274)
    /// Under 60 points (a row's thumbnail, the mini player): heavier tubes,
    /// and one cover, as four would be specks.
    static let small = StationArtCut(t: 9, g: 8, rw: 80, top: 22, base: 280)

    static func forSide(_ side: CGFloat) -> StationArtCut {
        side >= 200 ? .named : (side >= 60 ? .tile : .small)
    }
}

/// The room a station's art stands in: the first cover's hue, its
/// saturation held to 0.5 so the room is never louder than the music in the
/// window, at brightness 0.14 for the ground and 0.28 where the tubes light
/// it. Until the cover's colour is known, Cabinet.
nonisolated struct StationRoom: Hashable, Sendable {
    var hue: Double
    var saturation: Double

    init(_ average: AverageColor) {
        let hsb = average.hueSaturationBrightness
        hue = hsb.hue
        saturation = min(hsb.saturation, 0.5)
    }

    static let groundBrightness = 0.14
    static let hazeBrightness = 0.28
}

/// A cover's average colour, each 0 … 1 (ImagePipeline.averageColor).
nonisolated struct AverageColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Hue 0 … 1 (a turn), saturation and brightness 0 … 1, as Color(hue:
    /// saturation:brightness:) takes them.
    var hueSaturationBrightness: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let range = high - low
        let saturation = high > 0 ? range / high : 0
        guard range > 0 else { return (0, saturation, high) }
        var hue: Double
        if high == red {
            hue = (green - blue) / range
        } else if high == green {
            hue = 2 + (blue - red) / range
        } else {
            hue = 4 + (red - green) / range
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, high)
    }
}

/// A station's artwork, square. `size` nil: as wide as offered.
struct StationArtwork: View {
    let station: Station
    var size: CGFloat?
    var cornerRadius: CGFloat

    @Environment(AppModel.self) private var app
    /// The first cover's colour, once worked out (ImagePipeline keeps it),
    /// and which cover it is of: a reused view must not show the room of
    /// the station it showed before.
    @State private var average: (url: URL, color: AverageColor)?

    init(station: Station, size: CGFloat? = nil, cornerRadius: CGFloat = Theme.Radius.artwork) {
        self.station = station
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        // The kept colour first, as ArtworkView takes a kept cover: a tile
        // scrolled back into view has its room from the first frame.
        let known = toneURL.flatMap { url in
            ImagePipeline.shared.cachedAverageColor(url) ?? (average?.url == url ? average?.color : nil)
        }
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            StationArtworkFace(station: station, side: side, room: lit ? nil : known.map(StationRoom.init))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        // Always the dark of a lit room, and the placeholders in its
        // window drawn for it, in light mode as in dark.
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
        .task(id: toneURL) {
            guard let toneURL, !lit else { return }
            if ImagePipeline.shared.cachedAverageColor(toneURL) != nil { return }
            guard let found = await ImagePipeline.shared.averageColor(for: toneURL) else { return }
            // A newer station has its own task; this colour is not its.
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                average = (url: toneURL, color: found)
            }
        }
    }

    /// The stations of the listener's own taste: the lit core, not covers.
    private var lit: Bool {
        StationArtworkFace.litCore(for: station) != nil
    }

    /// The first cover, small: its colour is all that is wanted of it, and
    /// 120 pixels is the size a shelf's panes and a row's thumbnail fetch.
    private var toneURL: URL? {
        guard let cover = station.artwork.first, let client = app.client else { return nil }
        return client.imageURL(cover, maxPixelSize: 120)
    }
}

/// The art at one size.
private struct StationArtworkFace: View {
    let station: Station
    let side: CGFloat
    /// The covers' room; nil: Cabinet.
    let room: StationRoom?

    init(station: Station, side: CGFloat, room: StationRoom?) {
        self.station = station
        self.side = side
        self.room = room
    }

    /// The light in the window of a station made from the listener's own
    /// taste: Your Station's is the filament itself; Discovery's a paler,
    /// newer light; Loved's a warmer, rosier one. Calm differences, one
    /// family. Any station whose covers are not known yet has Your
    /// Station's, rather than an empty window.
    struct LitCore {
        let top: Color
        let foot: Color
        let bloom: Color

        static let yours = LitCore(top: Theme.Arch.coreTop, foot: Theme.Arch.coreFoot, bloom: Theme.Arch.coreBloom)
        static let discovery = LitCore(top: .white, foot: Color(rgb: 0xFFE9B8), bloom: Color(rgb: 0xFFE08A))
        static let loved = LitCore(top: Color(rgb: 0xFFF1EA), foot: Color(rgb: 0xFFB58E), bloom: Color(rgb: 0xFF9A6A))
    }

    static func litCore(for station: Station) -> LitCore? {
        switch station.seed {
        case .personal: return .yours
        case .discovery: return .discovery
        case .favorites: return .loved
        default: return station.artwork.isEmpty ? .yours : nil
        }
    }

    var body: some View {
        let cut = StationArtCut.forSide(side)
        let u = side / 300
        let windowWidth = cut.rw * 2 * u
        let windowHeight = (cut.base - cut.windowTop) * u
        let outer = ArchLine(box: 300, centerX: 150, radius: cut.outerRadius, spring: cut.spring, foot: cut.leg)
        let inner = ArchLine(box: 300, centerX: 150, radius: cut.innerRadius, spring: cut.spring, foot: cut.leg)
        let tubeLine = StrokeStyle(lineWidth: cut.t * u, lineCap: .round)
        ZStack(alignment: .topLeading) {
            ground

            // The light the tubes throw on the room.
            ZStack {
                outer.stroke(Theme.Arch.outerTube, style: StrokeStyle(lineWidth: cut.t * 2.2 * u, lineCap: .round))
                inner.stroke(Theme.Arch.innerTube, style: StrokeStyle(lineWidth: cut.t * 2.2 * u, lineCap: .round))
            }
            .frame(width: side, height: side)
            .blur(radius: 7 * u)
            .opacity(0.42)

            window(cut: cut, u: u, width: windowWidth, height: windowHeight)
                .frame(width: windowWidth, height: windowHeight)
                .clipShape(ArchWindow())
                .overlay {
                    ArchWindow().stroke(Color.black.opacity(0.18), lineWidth: max(0.5, u))
                }
                .offset(x: (150 - cut.rw) * u, y: cut.windowTop * u)

            ZStack {
                outer.stroke(Theme.Arch.outerTube, style: tubeLine)
                inner.stroke(Theme.Arch.innerTube, style: tubeLine)
            }
            .frame(width: side, height: side)

            // The hot line down each tube; too fine to see in a thumbnail.
            if cut != .small {
                ZStack {
                    outer.stroke(Theme.Arch.outerTubeHeart, style: StrokeStyle(lineWidth: cut.t * 0.4 * u, lineCap: .round))
                    inner.stroke(Theme.Arch.innerTubeHeart, style: StrokeStyle(lineWidth: cut.t * 0.4 * u, lineCap: .round))
                }
                .frame(width: side, height: side)
                .blur(radius: 2 * u)
                .opacity(0.45)
            }

            if cut == .named {
                name(u: u)
                    .frame(width: side, height: side, alignment: .bottom)
            }
        }
        .frame(width: side, height: side)
    }

    // MARK: The room

    private var ground: some View {
        let colors: [Color]
        if let room {
            colors = [Color(hue: room.hue, saturation: room.saturation, brightness: StationRoom.hazeBrightness),
                      Color(hue: room.hue, saturation: room.saturation, brightness: StationRoom.groundBrightness)]
        } else {
            colors = [Theme.Arch.cabinetHaze, Theme.Arch.cabinet]
        }
        return RadialGradient(colors: colors, center: UnitPoint(x: 0.5, y: 0.4),
                              startRadius: 0, endRadius: side * 230 / 300)
            .frame(width: side, height: side)
    }

    // MARK: The window

    @ViewBuilder
    private func window(cut: StationArtCut, u: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let covers = station.artwork
        if let core = Self.litCore(for: station) {
            litWindow(core, cut: cut, u: u, width: width, height: height)
        } else if covers.count >= 4 && cut != .small && showsPanes {
            // Four covers as panes, two by two, each cover square and cut to
            // its pane, its middle shown.
            let gap = 3 * u
            let paneWidth = (width - gap) / 2
            let paneHeight = (height - gap) / 2
            let coverSide = max(paneWidth, paneHeight)
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    pane(covers[0], side: coverSide, width: paneWidth, height: paneHeight)
                    pane(covers[1], side: coverSide, width: paneWidth, height: paneHeight)
                }
                HStack(spacing: gap) {
                    pane(covers[2], side: coverSide, width: paneWidth, height: paneHeight)
                    pane(covers[3], side: coverSide, width: paneWidth, height: paneHeight)
                }
            }
            .frame(width: width, height: height)
            .background(Color.black.opacity(0.5))
        } else {
            // One cover as tall as the window, its middle seen through it.
            pane(covers[0], side: height, width: width, height: height)
        }
    }

    /// Panes for what has many records (an artist, a genre, a decade, a
    /// playlist); a song's or an album's station shows its one cover.
    private var showsPanes: Bool {
        switch station.seed {
        case .track, .album: return false
        default: return true
        }
    }

    private func pane(_ cover: Artwork, side coverSide: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        ArtworkView(cover, size: coverSide, cornerRadius: 0)
            .frame(width: width, height: height)
            .clipped()
    }

    /// The core, lit, in a window glowing with it.
    private func litWindow(_ core: LitCore, cut: StationArtCut, u: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let coreWidth = cut.coreRadius * 2 * u
        // From the top of its half circle about the spring line to the sill.
        let coreHeight = (cut.base - cut.spring + cut.coreRadius) * u
        // The window's light is brightest half way down from the spring line.
        let lightY = ((cut.spring + cut.base) / 2 - cut.windowTop) / (cut.base - cut.windowTop)
        return ZStack(alignment: .bottom) {
            RadialGradient(stops: [
                .init(color: Color(rgb: 0x8A3A14), location: 0),
                .init(color: Color(rgb: 0x3A150B), location: 0.6),
                .init(color: Color(rgb: 0x220C07), location: 1),
            ], center: UnitPoint(x: 0.5, y: lightY), startRadius: 0, endRadius: cut.rw * 1.7 * u)
            Capsule(style: .circular)
                .fill(core.bloom)
                .frame(width: coreWidth, height: coreHeight)
                .blur(radius: 9 * u)
                .opacity(0.75)
            Capsule(style: .circular)
                .fill(LinearGradient(colors: [core.top, core.foot], startPoint: .top, endPoint: .bottom))
                .frame(width: coreWidth, height: coreHeight)
        }
        .frame(width: width, height: height)
    }

    // MARK: The name

    /// The station's name and what kind it is, under the window, from 200
    /// points: "Velvet Static", "ARTIST STATION". Fixed sizes: it is part of
    /// the picture (hidden from VoiceOver, which reads the page's own title).
    private func name(u: CGFloat) -> some View {
        VStack(spacing: 2 * u) {
            Text(verbatim: artTitle)
                .font(.system(size: 23 * u, weight: .semibold))
                .tracking(-0.2 * u)
                .foregroundStyle(.white)
            Text(kindLabel.uppercased())
                .font(.system(size: 9.5 * u, weight: .semibold))
                .tracking(1.5 * u)
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: 264 * u)
        .padding(.bottom, 12 * u)
    }

    /// The title without "Radio": the art says it is a station already.
    private var artTitle: String {
        let title = station.title
        let suffix = " Radio"
        return title.hasSuffix(suffix) && title.count > suffix.count ? String(title.dropLast(suffix.count)) : title
    }

    private var kindLabel: String {
        switch station.seed {
        case .track: String(localized: "Song Station")
        case .artist: String(localized: "Artist Station")
        case .album: String(localized: "Album Station")
        case .genre: String(localized: "Genre Station")
        case .decade: String(localized: "Decade Station")
        case .collection: String(localized: "Playlist Station")
        case .personal: String(localized: "From Your Listening")
        case .discovery: String(localized: "New to You")
        case .favorites: String(localized: "Your Favorites")
        }
    }
}
