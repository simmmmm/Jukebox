// A station's artwork, the Arch's way (docs/BRAND.md; the numbers are
// StationArtCut's, which Linux draws with too): the arch's window with the
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

// StationArtCut, StationRoom, AverageColor and the cores' colours
// (StationCore) are in ArtMeasures.swift: Linux draws from them too.

/// A station's artwork, square, its corners the one radius. `size` nil: as
/// wide as offered. Lit only while its station is on the air.
struct StationArtwork: View {
    let station: Station
    var size: CGFloat?
    var cornerRadius: CGFloat

    @Environment(AppModel.self) private var app
    @Environment(LibraryStore.self) private var library
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
            StationArtworkFace(station: station, covers: covers, core: core, side: side,
                               room: core != nil ? nil : known.map(StationRoom.init), isOnAir: onAir)
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
            guard let toneURL, core == nil else { return }
            if ImagePipeline.shared.cachedAverageColor(toneURL) != nil { return }
            guard let found = await ImagePipeline.shared.averageColor(for: toneURL) else { return }
            // A newer station has its own task; this colour is not its.
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: Tokens.Motion.glide)) {
                average = (url: toneURL, color: found)
            }
        }
    }

    /// The stations made from taste alone (Your Station, Discovery, Loved)
    /// show the music they draw from, not the mark's core: "de muziek gaat
    /// voor" (the photographer, 14 November 2026). Your Station what is
    /// played most, Loved the favourite albums, Discovery today's albums to
    /// explore; the core stays only while the library has none to show.
    private var ownCovers: [Artwork] {
        let albums: [Album]
        switch station.seed {
        case .personal:
            albums = HomeShelves.mostPlayed(tracks: library.tracks, album: library.album(id:), minimumPlays: 1, limit: 4)
        case .favorites:
            albums = Array(library.favoriteAlbums.prefix(4))
        case .discovery:
            albums = HomeShelves.explore(albums: library.albums, day: HomeShelves.dayNumber(of: Date()), limit: 4)
        default:
            return []
        }
        return albums.compactMap(\.artwork)
    }

    private var covers: [Artwork] {
        let own = ownCovers
        return own.isEmpty ? station.artwork : own
    }

    /// The core, for a taste station with no music to show yet.
    private var core: StationArtworkFace.Core? {
        ownCovers.isEmpty ? StationArtworkFace.core(for: station) : nil
    }

    /// The first cover, small: its colour is all that is wanted of it, and
    /// 120 pixels is the size a shelf's panes and a row's thumbnail fetch.
    private var toneURL: URL? {
        guard let cover = covers.first, let server = app.server else { return nil }
        return server.artworkURL(cover, maxPixelSize: 120)
    }
}

/// The art at one size.
private struct StationArtworkFace: View {
    let station: Station
    /// What the window shows: the station's covers, or for a taste station
    /// the music it draws from (StationArtwork.covers).
    let covers: [Artwork]
    /// The core, for a taste station with nothing to show; nil otherwise.
    let core: Core?
    let side: CGFloat
    /// The covers' room; nil: Cabinet.
    let room: StationRoom?
    /// The station plays: lit. Otherwise flat.
    let isOnAir: Bool

    init(station: Station, covers: [Artwork], core: Core?, side: CGFloat, room: StationRoom?, isOnAir: Bool) {
        self.station = station
        self.covers = covers
        self.core = core
        self.side = side
        self.room = room
        self.isOnAir = isOnAir
    }

    /// The core in the window of a station made from the listener's own
    /// taste, in StationCore's colours (ArtMeasures.swift). `flat` is the
    /// core at rest; `top` and `foot` the core lit, on the air.
    struct Core {
        let flat: Color
        let top: Color
        let foot: Color

        init(_ core: StationCore) {
            let colors = core.colors
            flat = Color(rgb: colors.flat)
            top = Color(rgb: colors.top)
            foot = Color(rgb: colors.foot)
        }
    }

    static func core(for station: Station) -> Core? {
        StationCore.of(station).map { Core($0) }
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
            // Flat at half strength, so the covers lead; full on the air.
            .opacity(isOnAir ? 1 : 0.55)
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
        if let core {
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
        } else if let first = covers.first {
            // One cover as tall as the window, its middle seen through it.
            pane(first, side: height, width: width, height: height)
        } else {
            // An empty place, as a cover's is before it comes.
            Color.white.opacity(0.08)
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
            Color(rgb: Tokens.Art.stationRoom)
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
