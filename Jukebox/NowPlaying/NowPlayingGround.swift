// Now Playing's ground and what stands on it: the page is not a flat
// colour with a picture on it but the record's own world, as the
// photographer asked of the record player: "Het moet minder een los object
// zijn en meer verweven zitten met de pagina." Sketch E's variant D, and the
// photographer's choice of it, 8 November 2026: "Dus ik denk dat d1 en d2
// vooral d2 het best gaan werken. D1 is reduced motion/batterij besparing d2
// normaal. F1 toch net iets te extreem denk".
//
// - D2, "the side as land" (Now Playing as it normally is): the ground is
//   the album's side as a record far larger than the screen, its centre
//   below the screen and to the right, its grooves in one dark tone
//   sweeping across the whole page as a horizon; one band per song of the
//   album, as wide as the song is long; the playing song's band starts
//   just above its title, under the sleeve, and its grooves played so far
//   are a tone lighter; on a song change the land moves on one band, so the
//   new song's band starts where the last one's did (TurntableMeasures'
//   LandGeometry). On it the sleeve and its record (SleeveRecord.swift),
//   the label turning a turn in 10 s.
// - D1, "the wall" (when nothing may move: Reduce Motion, Low Power Mode,
//   or Settings' Spin the Record off): the same page on two flat fields of
//   the cover's own colours (JukeboxKit's CoverWall), a wall above the
//   sleeve's foot and a floor below it, which the title and the controls
//   are on. Nothing moves; the label does not turn either. Under the lyrics
//   and the queue, where there is no sleeve to stand on it, all floor.
//
// Battery (the photographer: "Als batterij een zorg wordt moeten we ook ff
// kijken wat we daar aan kunnen doen"):
// - The land is one bitmap, drawn once per album and screen off the main
//   thread (LandDrawing), never per frame; the grooves played are the same
//   bitmap again in the lighter tone, clipped to a ring that changes once a
//   groove (every nine seconds or so), not twice a second.
// - One timeline (TimelineView) turns everything that turns, at most 30
//   frames a second (RecordMotion.frameRate: 20 while only the label
//   turns), and only while the record is on the screen, the music plays,
//   the app is active, and neither Reduce Motion, Low Power Mode nor Spin
//   the Record says otherwise; at rest it is paused and the page costs
//   nothing. The land turns on it about a pin that may sit off its true
//   centre, ready for sketch H; round and pinned at its centre, as it is
//   until then, turning it would change no pixel, so it is not turned.
// - The record is drawn once (drawingGroup) and only its rotation changes;
//   the sleeve, the shadows and the sheen are drawn once.
//
// The page lays out the sleeve's room and the title as it always has, and
// tells the ground where they are (NowPlayingAnchorsKey); the ground is
// drawn behind the page, under the status bar and to the screen's edges.

import JukeboxKit
import SwiftUI
import UIKit

// MARK: - Where things are

/// What the ground needs from the page: the room the sleeve may have, and
/// the title, as anchors the ground resolves in its own space; and whether
/// the page is the iPad's sideways layout.
nonisolated struct NowPlayingAnchors {
    var sleeveRoom: Anchor<CGRect>?
    var title: Anchor<CGRect>?
    var wide = false

    init(sleeveRoom: Anchor<CGRect>? = nil, title: Anchor<CGRect>? = nil, wide: Bool = false) {
        self.sleeveRoom = sleeveRoom
        self.title = title
        self.wide = wide
    }
}

nonisolated struct NowPlayingAnchorsKey: PreferenceKey {
    static var defaultValue: NowPlayingAnchors {
        NowPlayingAnchors()
    }

    static func reduce(value: inout NowPlayingAnchors, nextValue: () -> NowPlayingAnchors) {
        let next = nextValue()
        if let room = next.sleeveRoom { value.sleeveRoom = room }
        if let title = next.title { value.title = title }
        if next.wide { value.wide = true }
    }
}

/// D1's colours for one cover: the wall as it is, for the iPhone and the
/// iPad upright, where the top of the screen is all wall; and dark enough
/// for white glyphs, for the iPad sideways, where the status bar runs over
/// the wall and the floor at once.
nonisolated struct NowPlayingWalls: Equatable, Sendable {
    let upright: CoverWall
    let sideways: CoverWall

    init(upright: CoverWall, sideways: CoverWall) {
        self.upright = upright
        self.sideways = sideways
    }

    func wall(wide: Bool) -> CoverWall {
        wide ? sideways : upright
    }
}

/// D1's colours of each cover, by its URL: worked out once a cover, from the
/// same 32 pixels its accent is (CoverAccent.side), with that accent, whose
/// readability on the floor they keep. A few bytes each.
final class NowPlayingWallCache {
    static let shared = NowPlayingWallCache()

    private var known: [URL: NowPlayingWalls?] = [:]

    /// Known, with nil for a cover nothing of which shows; nil outside when
    /// not worked out yet.
    func cached(_ url: URL) -> NowPlayingWalls?? {
        known[url]
    }

    /// The walls of the cover at `url`, with its accent (nil: Glow). Nil
    /// when it did not load (then it is asked again next time) or nothing
    /// of it shows.
    func walls(for url: URL, accent: AccentColor?) async -> NowPlayingWalls? {
        if let kept = known[url] { return kept }
        let side = CoverAccent.side
        guard let image = await ImagePipeline.shared.image(for: url),
              let pixels = ImagePipeline.pixels(of: image, side: side) else { return nil }
        let ink = accent ?? .glow
        var found: NowPlayingWalls?
        if let upright = CoverWall.of(rgba: pixels, width: side, height: side, accent: ink),
           let sideways = CoverWall.of(rgba: pixels, width: side, height: side, accent: ink, whiteOnWall: true) {
            found = NowPlayingWalls(upright: upright, sideways: sideways)
        }
        // updateValue, not a subscript: `known[url] = nil` would remove the
        // key rather than keep "nothing shows".
        known.updateValue(found, forKey: url)
        return found
    }
}

// MARK: - The ground

/// Behind the page, to the screen's edges: D2's land or D1's wall and
/// floor, and the sleeve with its record where the page left it room.
struct NowPlayingGround: View {
    /// The screen, and where the page put the sleeve's room and the title,
    /// in this view's points (nil: not on the page now).
    let size: CGSize
    let sleeveRoom: CGRect?
    let title: CGRect?
    let wide: Bool
    /// D1: nothing moves, and the ground is the wall.
    let still: Bool
    /// D1's colours; nil until the cover's are known, or with no cover.
    let walls: NowPlayingWalls?
    let artwork: Artwork?
    /// Where the playing song lies on its album.
    let side: TurntableSide
    let label: RecordLabel?
    let isPlaying: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    /// On the screen: Now Playing is open.
    @State private var isOnScreen = false
    @State private var clock = RecordClock()
    /// The land as drawn, for one album's side and one screen.
    @State private var land: LandPicture?
    /// The cover's colour, for the label and the sleeve's edge, once worked
    /// out (ImagePipeline keeps it), and which cover it is of.
    @State private var tone: (url: URL, color: AverageColor)?

    init(size: CGSize, sleeveRoom: CGRect?, title: CGRect?, wide: Bool, still: Bool, walls: NowPlayingWalls?,
         artwork: Artwork?, side: TurntableSide, label: RecordLabel?, isPlaying: Bool) {
        self.size = size
        self.sleeveRoom = sleeveRoom
        self.title = title
        self.wide = wide
        self.still = still
        self.walls = walls
        self.artwork = artwork
        self.side = side
        self.label = label
        self.isPlaying = isPlaying
    }

    /// It turns only when all of these hold, and each is a reason to save
    /// the battery when it does not:
    /// - Now Playing is open and shows the sleeve (not the lyrics or the
    ///   queue, which take its place);
    /// - the music plays: a paused record stands still, as a real one does;
    /// - the app is active: in the background, or behind Control Centre,
    ///   no frame is wanted at all;
    /// - not D1: Reduce Motion, Low Power Mode and Spin the Record off each
    ///   make the page still.
    private var turns: Bool {
        mayTurn && isPlaying
    }

    /// Everything but the music playing: when only that changes (a pause)
    /// the record coasts to a stop; otherwise it stops where it is.
    private var mayTurn: Bool {
        isOnScreen && sleeveRoom != nil && scenePhase == .active && !still
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / RecordMotion.frameRate, paused: !clock.isMoving)) { context in
            stage(at: context.date)
        }
        .frame(width: size.width, height: size.height)
        // The land and the record run past the screen's edges; pulled down
        // to close, the page must not show them above its top.
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: still)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .onChange(of: turns, initial: true) { _, turning in
            if turning {
                clock.start(at: Date())
            } else {
                stopTurning()
            }
        }
        // The land, once per album's side and screen, off the main thread.
        // In D1 it is not wanted: let go of it.
        .task(id: landKey) {
            guard let key = landKey else {
                land = nil
                return
            }
            guard land?.key != key else { return }
            let rings = key.geometry.rings(bands: key.bands)
            let geometry = key.geometry
            let drawn = await Task.detached(priority: .userInitiated) {
                LandBitmap(image: LandDrawing.image(rings: rings, geometry: geometry))
            }.value
            guard !Task.isCancelled, let image = drawn.image else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                land = LandPicture(key: key, image: image, start: side.start)
            }
        }
        // The cover's colour, once per cover (ImagePipeline keeps it). The
        // record is drawn again once when it arrives, not animated: an
        // animated change would redraw the drawn-once record every frame.
        .task(id: toneURL) {
            guard let url = toneURL else { return }
            guard let found = await ImagePipeline.shared.averageColor(for: url) else { return }
            guard !Task.isCancelled, tone?.url != url else { return }
            tone = (url: url, color: found)
        }
    }

    /// Everything, as it is at `date`. Built anew each frame while the
    /// record turns; every part but the turning ones is given the same
    /// values each time and is not drawn again.
    @ViewBuilder private func stage(at date: Date) -> some View {
        let placed = placement
        ZStack(alignment: .topLeading) {
            // From one to the other (Low Power Mode comes on, say), a fade.
            if still {
                wallAndFloor(sleeve: placed?.sleeve)
                    .transition(.opacity)
            } else {
                ZStack(alignment: .topLeading) {
                    Self.night
                    landLayer(at: date)
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .transition(.opacity)
            }
            if let placed {
                sleeveAndRecord(placed, at: date)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: D1, the wall

    /// The floor everywhere, and the wall over it from the top of the
    /// screen to a little above the sleeve's foot: across the screen
    /// upright; on the iPad sideways, across the sleeve's side only, to the
    /// controls' column. Cabinet, the brand's Now Playing ground, until the
    /// cover's colours are known; all floor without a sleeve.
    @ViewBuilder private func wallAndFloor(sleeve: CGRect?) -> some View {
        let wall = walls?.wall(wide: wide)
        ZStack(alignment: .topLeading) {
            (wall.map { Self.color($0.floor) } ?? Theme.Arch.cabinet)
            if let wall, let sleeve {
                Rectangle()
                    .fill(Self.color(wall.wall))
                    .frame(width: wallWidth, height: max(0, sleeve.maxY - sleeve.height * Self.floorBehindSleeve))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Where the floor meets the wall, behind the sleeve, as a part of the
    /// sleeve's height above its foot: the sleeve stands on the floor, as a
    /// sleeve set against a wall does, rather than its foot and the floor's
    /// edge being one line. The photographer, 9 November 2026: "zou
    /// eigenlijk net ff moeten beginnen onder de hoes …, nu is het precies
    /// zon harde rand". A tenth: 28 points on an iPhone 17 Pro, enough to
    /// read as the floor going on behind it, not so much that the sleeve
    /// looks to sink into it.
    private static let floorBehindSleeve: CGFloat = 0.1

    /// Upright, the screen's width; sideways, to the controls' column, which
    /// begins a margin before the title.
    private var wallWidth: CGFloat {
        guard wide, let title else { return size.width }
        return max(0, title.minX - Theme.Space.xl)
    }

    // MARK: D2, the land

    @ViewBuilder private func landLayer(at date: Date) -> some View {
        if let land, let title {
            let geometry = land.key.geometry
            let anchor = CGPoint(x: title.midX, y: title.minY - LandGeometry.aboveTitle)
            // This album's land under this song; another album's, while its
            // own is drawn, stays where it was rather than slide to a song
            // it does not have.
            let ownSide = land.key.bands == side.bands
            let start = ownSide ? side.start : land.start
            let end = ownSide ? side.end : land.start
            let centerY = geometry.centerY(anchor: anchor, start: start)
            LandLayer(picture: land, start: start, end: end, played: ownSide,
                      angle: RecordMotion.landTurns ? clock.landAngle(at: date) : 0)
                .position(x: geometry.centerX, y: centerY)
                // The next song: the land moves on one band, eased.
                .animation(.easeInOut(duration: RecordMotion.slideSeconds), value: centerY)
                // Another album: its own land, faded in over the last.
                .id(land.id)
                .transition(.opacity)
        }
    }

    /// The land's bitmap for this side on this screen; nil in D1.
    private var landKey: LandKey? {
        guard !still, size.width > 0, size.height > 0 else { return nil }
        return LandKey(bands: side.bands, geometry: LandGeometry(screen: size, wide: wide))
    }

    // MARK: The sleeve and its record

    /// Where the sleeve and its record are, in this view's points; nil
    /// without room for a sleeve (the lyrics, the queue, a screen too
    /// small).
    private var placement: SleevePlacement? {
        guard let room = sleeveRoom else { return nil }
        let layout = SleeveLayout(room: room.size, wide: wide, margin: Theme.Space.xl)
        guard layout.sleeve.width >= 60 else { return nil }
        let sleeve = layout.sleeve.offsetBy(dx: room.minX, dy: room.minY)
        let center = CGPoint(x: layout.recordCenter.x + room.minX, y: layout.recordCenter.y + room.minY)
        return SleevePlacement(sleeve: sleeve, recordCenter: center, recordDiameter: layout.recordDiameter)
    }

    private func sleeveAndRecord(_ placed: SleevePlacement, at date: Date) -> some View {
        let diameter = placed.recordDiameter
        let center = placed.recordCenter
        // Black on the land; on a wall, the wall's own dark, softer.
        let wall = still ? walls?.wall(wide: wide) : nil
        let shadow = wall.map { Self.color($0.shadow) } ?? Color.black
        let strength = wall == nil ? 1.5 : 0.95
        // Taken out here, before the record: each frame then hands it the
        // very same values, and it is not drawn again.
        let labelTone = knownTone
        let bands = side.bands
        // At rest (D1, paused) the clock holds: the label stays where it
        // stopped.
        let angle = clock.labelAngle(at: date)
        return ZStack(alignment: .topLeading) {
            VinylShadow(diameter: diameter, color: shadow, strength: strength)
                .position(x: center.x, y: center.y)
            VinylDisc(diameter: diameter, bands: bands, label: label, tone: labelTone)
                .drawingGroup()
                .rotationEffect(.degrees(angle))
                .frame(width: diameter, height: diameter)
                .position(x: center.x, y: center.y)
            VinylSheen(diameter: diameter)
                .position(x: center.x, y: center.y)
            SleeveCard(artwork: artwork, side: placed.sleeve.width, edge: edgeColor, shadow: shadow, strength: strength)
                .position(x: placed.sleeve.midX, y: placed.sleeve.midY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The card's edge: the cover's average with 45% black, as sketch E;
    /// a dark brown until it is known.
    private var edgeColor: Color {
        guard let tone = knownTone else { return Color(rgb: 0x16110A) }
        return Color(red: tone.red * 0.55, green: tone.green * 0.55, blue: tone.blue * 0.55)
    }

    // MARK: Turning

    private func stopTurning() {
        let now = Date()
        // A pause coasts to a stop; anything else stops it where it is: in
        // the background, in D1 or with the record gone, a coast would be
        // frames nobody wants.
        clock.stop(at: now, coasts: mayTurn)
        guard clock.isMoving else { return }
        let coasting = clock
        Task {
            try? await Task.sleep(for: .seconds(RecordMotion.coastSeconds))
            // Still this coast (not turning again): at rest, and the
            // timeline pauses.
            if clock == coasting { clock.settle(at: Date()) }
        }
    }

    // MARK: The cover's colour

    /// The cover, small, for its colour: 120 pixels, as a station's room
    /// takes its colour (StationArtwork), and the accent's download.
    private var toneURL: URL? {
        guard let artwork, let client = app.client else { return nil }
        return client.imageURL(artwork, maxPixelSize: 120)
    }

    /// The cover's colour when it is known: kept by ImagePipeline, or worked
    /// out here for this very cover.
    private var knownTone: AverageColor? {
        guard let url = toneURL else { return nil }
        return ImagePipeline.shared.cachedAverageColor(url) ?? (tone?.url == url ? tone?.color : nil)
    }

    // MARK: Colours

    /// D2's ground: a warm near-black, sketch E's #131010 (Night, the
    /// brand's dark ground, is #121110).
    static let night = Color(rgb: 0x131010)

    static func color(_ color: AccentColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }
}

/// The sleeve's square and its record, in the ground's points.
nonisolated struct SleevePlacement: Equatable, Sendable {
    let sleeve: CGRect
    let recordCenter: CGPoint
    let recordDiameter: CGFloat
}

// MARK: - The land, drawn

/// What the land's bitmap is drawn for: an album's side on a screen.
nonisolated struct LandKey: Equatable, Sendable {
    let bands: [Double]
    let geometry: LandGeometry
}

/// The land as drawn: the bitmap, what it was drawn for, and where the song
/// was when it was asked for (where an old land stays while the next is
/// drawn).
struct LandPicture {
    let key: LandKey
    let image: CGImage
    let start: Double
    let id = UUID()
}

/// A drawn bitmap, handed from the drawing thread to the main one; nothing
/// changes it once drawn.
nonisolated struct LandBitmap: @unchecked Sendable {
    let image: CGImage?
}

/// The land's bitmap: every ring of the side, drawn into one image of
/// LandGeometry's size and density, transparent between the grooves (the
/// ground under it is a flat colour). Called off the main thread, once per
/// album's side and screen.
nonisolated enum LandDrawing {
    static func image(rings: [LandRing], geometry: LandGeometry) -> CGImage? {
        let scale = geometry.bitmapScale
        let side = Int((geometry.diameter * scale).rounded(.up))
        guard side > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let middle = CGFloat(side) / 2
        // The grooves in one dark tone a little above the ground: sketch
        // E's #211A17 on #131010 a step lighter, #2B231F, so their dance
        // (RecordMotion) shows — sketch H: more contrast, not more sway,
        // which would only move them faster behind the words. White on it
        // stays above 15:1, the darkest accent (#FF675F) 5.4:1. The light edge
        // between songs and the run-out's edge, white at 7% and 4%.
        let groove = CGColor(srgbRed: 0x2B / 255.0, green: 0x23 / 255.0, blue: 0x1F / 255.0, alpha: 1)
        let edge = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)
        let runOut = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.04)
        // One path a kind, stroked once: a few strokes, not two hundred.
        let kinds: [(LandRing.Kind, CGColor, CGFloat)] = [
            (.groove, groove, 1.5),
            (.strong, groove, 1.9),
            (.edge, edge, 1),
            (.runOut, runOut, 1),
        ]
        for (kind, color, width) in kinds {
            let path = CGMutablePath()
            for ring in rings where ring.kind == kind {
                let r = ring.radius * scale
                path.addEllipse(in: CGRect(x: middle - r, y: middle - r, width: r * 2, height: r * 2))
            }
            context.addPath(path)
            context.setStrokeColor(color)
            context.setLineWidth(width * scale)
            context.strokePath()
        }
        return context.makeImage()
    }
}

/// The land on the screen: the bitmap, and over it the same bitmap in the
/// lighter tone, clipped to the playing song's grooves played so far
/// (LandPlayed). Turned as one about its pin (RecordMotion), and made a
/// little oval first when sketch H says so: the lighter grooves turn and
/// sway with the rest.
private struct LandLayer: View {
    let picture: LandPicture
    let start: Double
    let end: Double
    /// Whether to show the grooves played: not on another album's land.
    let played: Bool
    let angle: Double

    var body: some View {
        let geometry = picture.key.geometry
        let diameter = geometry.diameter
        let scale = geometry.bitmapScale
        let pin = UnitPoint(x: 0.5 + RecordMotion.landPinOffset.x / diameter,
                            y: 0.5 + RecordMotion.landPinOffset.y / diameter)
        let oval = 1 + CGFloat(RecordMotion.landOvalPercent) / 100
        ZStack {
            Image(decorative: picture.image, scale: scale)
                .resizable()
            if played {
                LandPlayed(picture: picture, start: start, end: end)
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(x: oval, y: 1)
        .rotationEffect(.degrees(angle), anchor: pin)
    }
}

/// The playing song's grooves played so far, a tone lighter (sketch E's
/// #3F3127): the land's own bitmap as a template in that tone, clipped to
/// the ring that holds them. It reads the player itself, so that only it is
/// evaluated as the song goes on (twice a second), and counts in whole
/// grooves, so most of those ticks change nothing and redraw nothing.
private struct LandPlayed: View {
    let picture: LandPicture
    let start: Double
    let end: Double

    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let geometry = picture.key.geometry
        let duration = player.duration
        let progress = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        let count = geometry.playedGrooves(from: start, to: end, progress: progress)
        if let ring = geometry.playedRing(from: start, to: end, count: count) {
            Image(decorative: picture.image, scale: geometry.bitmapScale)
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(Self.lit)
                .clipShape(RingShape(outer: ring.outer, inner: ring.inner), style: FillStyle(eoFill: true))
        }
    }

    private static let lit = Color(rgb: 0x3F3127)
}
