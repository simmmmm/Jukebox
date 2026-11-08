// A station's artwork, the Arch's way (docs/BRAND.md, dev/brand/station.py,
// which draws the same with these same numbers): the arch's window with the
// seed's music in it — one cover for a song or an album, four as panes for
// an artist, a genre, a decade or a playlist — two bands around it, and as
// the room the first cover's own colour, darkened. Every station is
// recognisably Jukebox's, and recognisably its seed's. The stations made
// from the listener's own taste (Your Station, Discovery, Loved) have no
// one seed to show: their window holds the mark's core.
//
// Light means on air (docs/design/tells.md, 1). Every station is drawn flat
// — Copper outside, Glow inside, a flat room, a flat core, no blur — except
// the one on the air, which alone is lit: its tubes in their own oranges,
// with one soft glow on the room. The photographer, 8 November 2026: "Kun je
// het design iets minder ai maken?" — and the first of the tells was that
// everything glowed.
//
// Only stations are drawn so: the arch means a station. A mix, an album or
// a playlist stays a square cover.

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

    /// From 60 points: a tile, a row, a station's page. The name is never
    /// drawn into the art: the page's title, in the serif, is right under
    /// it, and a subtitle that repeats a title goes (tells.md, 5).
    static let tile = StationArtCut(t: 6, g: 6.5, rw: 82, top: 26, base: 274)
    /// Under 60 points (a row's thumbnail, the mini player): heavier tubes,
    /// and one cover, as four would be specks.
    static let small = StationArtCut(t: 9, g: 8, rw: 80, top: 22, base: 280)

    static func forSide(_ side: CGFloat) -> StationArtCut {
        side >= 60 ? .tile : .small
    }
}

/// The room a station's art stands in: the first cover's hue, its
/// saturation held to 0.5 so the room is never louder than the music in the
/// window, at brightness 0.14, flat. Until the cover's colour is known,
/// Cabinet.
nonisolated struct StationRoom: Hashable, Sendable {
    var hue: Double
    var saturation: Double

    init(_ average: AverageColor) {
        let hsb = average.hueSaturationBrightness
        hue = hsb.hue
        saturation = min(hsb.saturation, 0.5)
    }

    static let groundBrightness = 0.14
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

/// A station's artwork, square, its corners the one radius. `size` nil: as
/// wide as offered. Lit only while its station is on the air.
struct StationArtwork: View {
    let station: Station
    var size: CGFloat?
    var cornerRadius: CGFloat

    @Environment(AppModel.self) private var app
    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
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
        // By id, as a station's page compares them: the station a tile was
        // built with and the one the radio plays can differ in their covers.
        let onAir = radio.stationOnAir(player: player)?.id == station.id
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            StationArtworkFace(station: station, side: side,
                               room: hasCoreWindow ? nil : known.map(StationRoom.init), isOnAir: onAir)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        // Always the dark of a room, and the placeholders in its window
        // drawn for it, in light mode as in dark.
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
        .task(id: toneURL) {
            guard let toneURL, !hasCoreWindow else { return }
            if ImagePipeline.shared.cachedAverageColor(toneURL) != nil { return }
            guard let found = await ImagePipeline.shared.averageColor(for: toneURL) else { return }
            // A newer station has its own task; this colour is not its.
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                average = (url: toneURL, color: found)
            }
        }
    }

    /// The stations of the listener's own taste: the core, not covers.
    private var hasCoreWindow: Bool {
        StationArtworkFace.core(for: station) != nil
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
    /// The station plays: lit. Otherwise flat.
    let isOnAir: Bool

    init(station: Station, side: CGFloat, room: StationRoom?, isOnAir: Bool) {
        self.station = station
        self.side = side
        self.room = room
        self.isOnAir = isOnAir
    }

    /// The core in the window of a station made from the listener's own
    /// taste: Your Station's a warm white; Discovery's paler, newer; Loved's
    /// warmer, rosier. Calm differences, one family. Any station whose
    /// covers are not known yet has Your Station's, rather than an empty
    /// window. `flat` is the core at rest; `top` and `foot` the core lit,
    /// on the air.
    struct Core {
        let flat: Color
        let top: Color
        let foot: Color

        static let yours = Core(flat: Color(rgb: 0xFFEDCC), top: Color(rgb: 0xFFFBF0), foot: Color(rgb: 0xFFD58E))
        static let discovery = Core(flat: Color(rgb: 0xFAF6EC), top: .white, foot: Color(rgb: 0xFFE9B8))
        static let loved = Core(flat: Color(rgb: 0xFFD3BE), top: Color(rgb: 0xFFF1EA), foot: Color(rgb: 0xFFB58E))
    }

    static func core(for station: Station) -> Core? {
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

            if isOnAir {
                // The one soft glow: the light the tubes throw on the room,
                // while, and only while, the station is on the air.
                ZStack {
                    outer.stroke(Theme.Arch.outerTube, style: StrokeStyle(lineWidth: cut.t * 2.2 * u, lineCap: .round))
                    inner.stroke(Theme.Arch.innerTube, style: StrokeStyle(lineWidth: cut.t * 2.2 * u, lineCap: .round))
                }
                .frame(width: side, height: side)
                .blur(radius: 7 * u)
                .opacity(0.42)
            }

            window(cut: cut, u: u, width: windowWidth, height: windowHeight)
                .frame(width: windowWidth, height: windowHeight)
                .clipShape(ArchWindow())
                .offset(x: (150 - cut.rw) * u, y: cut.windowTop * u)

            ZStack {
                outer.stroke(isOnAir ? Theme.Arch.outerTube : Theme.Arch.copper, style: tubeLine)
                inner.stroke(isOnAir ? Theme.Arch.innerTube : Theme.Arch.glow, style: tubeLine)
            }
            .frame(width: side, height: side)
        }
        .frame(width: side, height: side)
    }

    // MARK: The room

    /// Flat: the cover's colour darkened, or Cabinet.
    private var ground: some View {
        let color = room.map { Color(hue: $0.hue, saturation: $0.saturation, brightness: StationRoom.groundBrightness) }
            ?? Theme.Arch.cabinet
        return color.frame(width: side, height: side)
    }

    // MARK: The window

    @ViewBuilder
    private func window(cut: StationArtCut, u: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let covers = station.artwork
        if let core = Self.core(for: station) {
            coreWindow(core, cut: cut, u: u, width: width, height: height)
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

    /// The core in a dark window: flat at rest; on the air, the core's own
    /// light from its top to its foot (the glow is the tubes').
    private func coreWindow(_ core: Core, cut: StationArtCut, u: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let coreWidth = cut.coreRadius * 2 * u
        // From the top of its half circle about the spring line to the sill.
        let coreHeight = (cut.base - cut.spring + cut.coreRadius) * u
        return ZStack(alignment: .bottom) {
            Color(rgb: 0x220C07)
            if isOnAir {
                Capsule(style: .circular)
                    .fill(LinearGradient(colors: [core.top, core.foot], startPoint: .top, endPoint: .bottom))
                    .frame(width: coreWidth, height: coreHeight)
            } else {
                Capsule(style: .circular)
                    .fill(core.flat)
                    .frame(width: coreWidth, height: coreHeight)
            }
        }
        .frame(width: width, height: height)
    }
}
