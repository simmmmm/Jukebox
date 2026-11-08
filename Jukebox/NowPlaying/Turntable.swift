// Now Playing's record player, in the cover's place. The photographer, 8
// November 2026: "Ik vind de platenspeler ideeen leuk maar dan zou ik ook de
// plaat willen zien draaien met de album art er op het liefst in een soort
// perspectief van licht erboven." So the song's cover is a picture disc that
// turns while the music plays, on a deck seen from a little above, lit from
// above. Then, the same day: "Kun je de platenspeler iets leuker maken, de
// hoes er achter zetten en de naald zetten op welk nummer het is van het
// album". So the album's sleeve stands behind the deck; the record shows the
// album's songs as bands, as a record does; the needle sits in the playing
// song's band; and when the song changes the arm cues: it lifts, swings to
// the new song's band and drops.
//
// Drawn, not rendered (docs/design/tells.md, 7: "A glossy 3D render: chrome
// arm, specular streaks, a spotlight" was a tell): a matte plinth with one
// soft falloff of the light from above; the sleeve, upright behind it, with
// a hard shadow on the plinth; a matte platter; the picture disc — the
// cover cut round, the grooves and the bands between the songs over the
// art, a label in the cover's own colour with the album's title and artist
// printed straight on it, its hole; one faint pair of sheen wedges that
// stay where the light is while the record turns under them; and the arm, a
// flat two-tone shape with a pivot and a hard, unblurred shadow. Playing, it
// is down on the record; paused, it is lifted (a small rise and a longer
// shadow); with nothing to play it rests beside the platter. The measures —
// the deck's geometry, where the sleeve goes, where the song is on its
// album — are plain arithmetic in TurntableMeasures.swift.
//
// Battery first ("Als batterij een zorg wordt moeten we ook ff kijken wat we
// daar aan kunnen doen"). Every choice below that costs or saves power says
// so where it is made. In short: the record — cover, grooves, bands, label —
// is drawn once and only its rotation changes; it turns at most 20 times a
// second; it turns only while it can be seen and the music plays, never in
// Low Power Mode or under Reduce Motion, and not when Settings' Spin the
// Record is off; at rest nothing about it is redrawn at all. The sleeve is
// an image, drawn once. The arm's cue is three animations set off by the
// change of song, not a timeline.
//
// The deck is decoration: VoiceOver skips it, and every control around it
// is Apple's.

import Combine
import Foundation
import JukeboxKit
import SwiftUI
import UIKit

// MARK: - The deck

/// The record player for Now Playing: the deck, tipped back, and the
/// album's sleeve standing behind it where there is room (TurntableLayout).
/// Its record turns while the song plays (see `spins` for when, exactly);
/// its arm sits where the song is on its album (`side`).
struct Turntable: View {
    let artwork: Artwork?
    let isPlaying: Bool
    /// Where the playing song lies on its album: the bands on the record
    /// and the song's own band. Nil: the arm goes by the song alone, and
    /// the record has no bands.
    let side: TurntableSide?
    /// The words on the record's label; nil: a plain label.
    let label: TurntableLabel?

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// On the screen: Now Playing is open and shows the record, not the
    /// lyrics or the queue (which take its place, and so remove it).
    @State private var isOnScreen = false
    /// Low Power Mode, kept up to date by the system's notification.
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Where the record rests, or where it was when it last began to turn,
    /// in degrees.
    @State private var restAngle: Double = 0
    /// When the record began to turn; nil while it rests or coasts.
    @State private var spunSince: Date?
    /// The short coast-down after the music stops.
    @State private var coast: TurntableCoast?
    /// The cover's colour, for the label, once worked out (ImagePipeline
    /// keeps it), and which cover it is of: a reused view must not print
    /// the last album's label.
    @State private var tone: (url: URL, color: AverageColor)?

    init(artwork: Artwork?, isPlaying: Bool, side: TurntableSide? = nil, label: TurntableLabel? = nil) {
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.side = side
        self.label = label
    }

    /// A turn in 10 s, far slower than a real 33⅓ (1.8 s a turn): the
    /// photographer, on the first build with the deck, "mag ie nog veel
    /// zachter draaien hoor". Slower also needs fewer frames (`frameRate`).
    static let degreesPerSecond: Double = 36
    /// 20 frames a second: at 36° a second a frame turns the record 1.8°,
    /// which still reads as smooth, for a third fewer frames than 30.
    static let frameRate: Double = 20
    /// How long the record takes to come to rest when the music stops: a
    /// real platter's few tenths of a second, no more.
    static let coastSeconds: Double = 0.8

    /// The record turns only when all of these hold, and each is a reason
    /// to save the battery when it does not:
    /// - it is on the screen (Now Playing open, the record shown): nobody
    ///   sees a record turn behind the lyrics or with Now Playing closed;
    /// - the music plays: a paused record stands still, as a real one does;
    /// - the app is active: in the background, or behind Control Centre,
    ///   no frame is wanted at all;
    /// - Reduce Motion is off: the listener asked for less movement;
    /// - Low Power Mode is off: the phone asked for less work;
    /// - Settings' Spin the Record is on (AppSettings.spinRecord).
    private var spins: Bool {
        isOnScreen && isPlaying && scenePhase == .active && !reduceMotion && !isLowPower && settings.spinRecord
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = TurntableLayout(fitting: proxy.size)
            // A sleeve only with a cover to put on it. The deck keeps its
            // place either way, so a song without a cover does not move it.
            let sleeve: CGRect? = artwork == nil ? nil : layout.sleeve
            ZStack(alignment: .topLeading) {
                // Behind the deck, which is drawn over its lower part: the
                // sleeve stands behind the plinth's far edge.
                if let sleeve {
                    TurntableSleeve(artwork: artwork, side: sleeve.width)
                        .position(x: sleeve.midX, y: sleeve.midY)
                }
                deck(layout.deck, shadow: sleeve == nil ? nil : layout.shadow)
                    // Tipped back, the near edge toward the listener, the
                    // far edge away: the deck seen from a little above.
                    .rotation3DEffect(.degrees(TurntableGeometry.tilt), axis: (x: 1, y: 0, z: 0),
                                      anchor: .center, perspective: TurntableGeometry.perspective)
                    .position(x: layout.deckCenter.x, y: layout.deckCenter.y)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        // The system says when Low Power Mode changes, on a thread of its
        // own; the state is changed on the main one.
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: spins, initial: true) { _, spinning in
            if spinning {
                startSpinning()
            } else {
                stopSpinning()
            }
        }
        // The label's colour, once per cover (ImagePipeline keeps it). The
        // record is drawn again once when it arrives, not animated: an
        // animated change would redraw the drawn-once record every frame.
        // Kept here even when ImagePipeline already had it, as it may have
        // come there after this body last looked.
        .task(id: toneURL) {
            guard let url = toneURL else { return }
            guard let found = await ImagePipeline.shared.averageColor(for: url) else { return }
            // A newer cover has its own task; this colour is not its.
            guard !Task.isCancelled, tone?.url != url else { return }
            tone = (url: url, color: found)
        }
    }

    private func deck(_ g: TurntableGeometry, shadow: TurntableSleeveShadow?) -> some View {
        let disc = g.discRadius * 2
        let platter = g.platterRadius * 2
        // Taken out here, before the timeline: each of its frames then hands
        // the record the very same values, and the record is not drawn again.
        let labelTone = knownTone
        let bands = side?.bands ?? []
        return ZStack(alignment: .topLeading) {
            // The plinth: matte, with one soft falloff of the light from
            // above — on the plinth only, not a spotlight on the room.
            RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                .fill(LinearGradient(colors: [Self.plinthLit, Self.plinthShade], startPoint: .top, endPoint: .bottom))
                .frame(width: g.width, height: g.depth)

            // The sleeve's shadow: hard, no blur, cast forward onto the
            // plinth by the light above and behind, as the arm's is. Drawn
            // once, with the plinth.
            if let shadow {
                TurntableSleeveShadowShape(shadow: shadow)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: g.width, height: g.depth)
            }

            // The platter, matte, a little wider than the record.
            Circle()
                .fill(Self.platter)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
                .frame(width: platter, height: platter)
                .offset(x: g.center.x - g.platterRadius, y: g.center.y - g.platterRadius)

            // The record. Battery: `drawingGroup` draws the cover, the
            // grooves, the bands between the songs and the label once into
            // a single layer; turning it is then a change of that layer's
            // rotation, not a redraw of fifty circles, an image and the
            // label's words. The timeline asks for at most 20 frames a
            // second (`frameRate`), and none at all while the record rests:
            // paused, it wakes nothing, and the body is not evaluated again
            // until something else changes.
            TimelineView(.animation(minimumInterval: 1.0 / Self.frameRate, paused: spunSince == nil && coast == nil)) { timeline in
                TurntableDisc(artwork: artwork, geometry: g, bands: bands, label: label, tone: labelTone)
                    .drawingGroup()
                    .rotationEffect(.degrees(angle(at: timeline.date)))
            }
            .frame(width: disc, height: disc)
            .offset(x: g.center.x - g.discRadius, y: g.center.y - g.discRadius)

            // The light on the record: two faint wedges that stay where the
            // light is while the record turns under them, as a sheen does.
            // Outside the turning layer, so it is drawn once and holds still.
            TurntableSheen()
                .frame(width: disc, height: disc)
                .offset(x: g.center.x - g.discRadius, y: g.center.y - g.discRadius)

            TurntableArm(geometry: g, side: side)
        }
        .frame(width: g.width, height: g.depth, alignment: .topLeading)
    }

    // MARK: The label's colour

    /// The cover, small, for its colour: 120 pixels, as a station's room
    /// takes its colour (StationArtwork), and the size the mini player's
    /// cover already fetched.
    private var toneURL: URL? {
        guard let artwork, let client = app.client else { return nil }
        return client.imageURL(artwork, maxPixelSize: 120)
    }

    /// The cover's colour when it is known: kept by ImagePipeline, or
    /// worked out here for this very cover.
    private var knownTone: AverageColor? {
        guard let url = toneURL else { return nil }
        return ImagePipeline.shared.cachedAverageColor(url) ?? (tone?.url == url ? tone?.color : nil)
    }

    // MARK: Turning

    /// The record's angle at `date`: turning from where it began, slowing
    /// to a stop over the coast, or at rest where it stopped.
    private func angle(at date: Date) -> Double {
        if let spunSince {
            return restAngle + max(0, date.timeIntervalSince(spunSince)) * Self.degreesPerSecond
        }
        if let coast {
            // Even deceleration from full speed to none: half the distance
            // full speed would have gone.
            let t = min(max(0, date.timeIntervalSince(coast.start)), Self.coastSeconds)
            return coast.from + Self.degreesPerSecond * (t - t * t / (2 * Self.coastSeconds))
        }
        return restAngle
    }

    private func startSpinning() {
        let now = Date()
        // From wherever it is: at rest, or still coasting.
        restAngle = angle(at: now).truncatingRemainder(dividingBy: 360)
        coast = nil
        spunSince = now
    }

    private func stopSpinning() {
        let now = Date()
        let wasSpinning = spunSince != nil
        let current = angle(at: now).truncatingRemainder(dividingBy: 360)
        spunSince = nil
        // A pause coasts to a stop; anything else stops it where it is: in
        // the background, in Low Power Mode, under Reduce Motion or with
        // the switch off, a coast would be frames nobody wants.
        let mayCoast = wasSpinning && isOnScreen && scenePhase == .active && !reduceMotion && !isLowPower
            && settings.spinRecord
        guard mayCoast else {
            coast = nil
            restAngle = current
            return
        }
        let started = TurntableCoast(start: now, from: current)
        coast = started
        restAngle = current + Self.degreesPerSecond * Self.coastSeconds / 2
        Task {
            try? await Task.sleep(for: .seconds(Self.coastSeconds))
            // Still this coast (not a newer one, not turning again): at rest
            // now, and the timeline pauses.
            if coast == started { coast = nil }
        }
    }

    // MARK: Colours

    /// The plinth's top, where the light falls, and its foot: a warm dark
    /// wood, matte.
    private static let plinthLit = Color(rgb: 0x3B3129)
    private static let plinthShade = Color(rgb: 0x221B16)
    private static let platter = Color(rgb: 0x151110)
}

/// The words on the record's label: the album's title, its artist, and its
/// disc's number when the album has more than one ("Disc 2").
nonisolated struct TurntableLabel: Equatable, Sendable {
    let title: String
    let artist: String
    let disc: Int?

    init(title: String, artist: String, disc: Int?) {
        self.title = title
        self.artist = artist
        self.disc = disc
    }
}

/// A coast-down: when it began, and the record's angle then.
nonisolated private struct TurntableCoast: Equatable, Sendable {
    let start: Date
    let from: Double
}

// MARK: - The sleeve

/// The album's sleeve, upright behind the deck, as if the record had just
/// come out of it: the cover, square, at the one radius artwork has
/// (Theme.Radius.artwork, 6 pt; a sleeve's own sharper corner would be a
/// second radius, which the brand does not have). A little in the shade: it
/// stands further from the light than the record, and should not outshine
/// the record turning in front of it. An image, drawn once; nothing about
/// it moves.
private struct TurntableSleeve: View {
    let artwork: Artwork?
    let side: CGFloat

    init(artwork: Artwork?, side: CGFloat) {
        self.artwork = artwork
        self.side = side
    }

    var body: some View {
        ArtworkView(artwork, size: side)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                    .fill(Color.black.opacity(0.14))
            }
    }
}

/// The sleeve's shadow on the plinth (TurntableSleeveShadow), in the deck's
/// own points: from the far edge, where the sleeve stands, forward and a
/// little to the right.
nonisolated struct TurntableSleeveShadowShape: Shape {
    let shadow: TurntableSleeveShadow

    init(shadow: TurntableSleeveShadow) {
        self.shadow = shadow
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: shadow.left, y: 0))
        path.addLine(to: CGPoint(x: shadow.right, y: 0))
        path.addLine(to: CGPoint(x: shadow.right + shadow.lean, y: shadow.length))
        path.addLine(to: CGPoint(x: shadow.left + shadow.lean, y: shadow.length))
        path.closeSubpath()
        return path
    }
}

// MARK: - The record

/// The picture disc: the cover on vinyl, cut round, the grooves over it,
/// the bands between the album's songs, the label with its words and its
/// hole. Drawn once (Turntable's `drawingGroup`) and turned as a whole.
///
/// Every value here comes from the deck as it is, not made afresh: the
/// timeline builds this view anew every frame, and an equal record is not
/// drawn again. `tone` is the cover's colour as three numbers, and the
/// label's Color is made from it in the body, which runs only when the
/// record changes.
private struct TurntableDisc: View {
    let artwork: Artwork?
    let geometry: TurntableGeometry
    let bands: [Double]
    let label: TurntableLabel?
    let tone: AverageColor?

    init(artwork: Artwork?, geometry: TurntableGeometry, bands: [Double], label: TurntableLabel?, tone: AverageColor?) {
        self.artwork = artwork
        self.geometry = geometry
        self.bands = bands
        self.label = label
        self.tone = tone
    }

    var body: some View {
        let radius = geometry.discRadius
        let labelRadius = geometry.labelRadius
        let side = radius * 2
        let pictureSide = side * 0.97
        ZStack {
            // The vinyl, seen as a rim round the picture.
            Circle()
                .fill(Color(rgb: 0x0D0A09))
            if artwork != nil {
                ArtworkView(artwork, size: pictureSide, cornerRadius: 0)
                    .clipShape(Circle())
            }
            TurntableGrooves(outer: pictureSide / 2, inner: labelRadius * 1.04)
            TurntableBands(radii: bands.map { geometry.grooveRadius(at: $0) },
                           width: max(1, radius * 0.012))
            TurntableLabelFace(label: label, color: labelColor, radius: labelRadius,
                               holeRadius: geometry.holeRadius, lineWidth: max(0.5, radius * 0.005))
        }
        .frame(width: side, height: side)
    }

    /// The label: a flat colour from the cover — its hue, its saturation
    /// held to 0.45, at brightness 0.3, dark enough that the words on it
    /// read in paper white (the title 6.8:1 at the least, over every hue,
    /// the artist 4.7:1) — or, until the cover's colour is known, the dark
    /// brown the label always was.
    private var labelColor: Color {
        guard let tone else { return Color(rgb: 0x1A1411) }
        let hsb = tone.hueSaturationBrightness
        return Color(hue: hsb.hue, saturation: min(hsb.saturation, 0.45), brightness: 0.3)
    }
}

/// Fine grooves over the picture, a few dozen thin rings, dark and light
/// by turns, each at its own faint strength, as grooves catch the light
/// unevenly. The gaps between the songs are the album's own (TurntableBands).
private struct TurntableGrooves: View {
    let outer: CGFloat
    let inner: CGFloat

    init(outer: CGFloat, inner: CGFloat) {
        self.outer = outer
        self.inner = inner
    }

    private static let count = 40

    var body: some View {
        ZStack {
            ForEach(0..<Self.count, id: \.self) { i in
                let r = inner + (outer - inner) * CGFloat(i) / CGFloat(Self.count - 1)
                Circle()
                    .stroke(Self.color(i), lineWidth: 0.5)
                    .frame(width: r * 2, height: r * 2)
            }
        }
        .frame(width: outer * 2, height: outer * 2)
    }

    private static func color(_ i: Int) -> Color {
        // Steps of the golden angle: no two neighbours alike, no pattern.
        let wobble = 0.5 + 0.5 * sin(Double(i) * 2.39996)
        return i.isMultiple(of: 2)
            ? Color.black.opacity(0.08 + 0.1 * wobble)
            : Color.white.opacity(0.03 + 0.05 * wobble)
    }
}

/// The gaps between the album's songs, where a record's groove runs smooth
/// from one song to the next: a darker ring at each, with a faint light
/// edge where the smooth vinyl catches the light. At the radii the arm goes
/// to (TurntableGeometry.grooveRadius), so the needle is seen in its song's
/// band.
private struct TurntableBands: View {
    let radii: [CGFloat]
    let width: CGFloat

    init(radii: [CGFloat], width: CGFloat) {
        self.radii = radii
        self.width = width
    }

    var body: some View {
        ZStack {
            ForEach(0..<radii.count, id: \.self) { i in
                let r = radii[i]
                Circle()
                    .stroke(Color.black.opacity(0.38), lineWidth: width)
                    .frame(width: r * 2, height: r * 2)
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    .frame(width: r * 2 + width + 0.5, height: r * 2 + width + 0.5)
            }
        }
    }
}

/// The label: its colour, a fine printed ring near its edge, the album's
/// title in the serif above the hole and its artist below, straight and
/// small, as a label is printed, and "Disc 2" under them when the album has
/// discs. Drawn to the record's size, not the reader's text size: it is a
/// picture, and VoiceOver skips it with the rest of the deck. The words'
/// ink is paper white, and the ring's with them, as a label is printed in
/// one ink; the ring was Glow, which on Now Playing marks only what is the
/// radio's or what is on (NowPlayingView).
private struct TurntableLabelFace: View {
    let label: TurntableLabel?
    let color: Color
    let radius: CGFloat
    let holeRadius: CGFloat
    let lineWidth: CGFloat

    init(label: TurntableLabel?, color: Color, radius: CGFloat, holeRadius: CGFloat, lineWidth: CGFloat) {
        self.label = label
        self.color = color
        self.radius = radius
        self.holeRadius = holeRadius
        self.lineWidth = lineWidth
    }

    var body: some View {
        let side = radius * 2
        ZStack {
            Circle()
                .fill(color)
            Circle()
                .stroke(Self.ink.opacity(0.3), lineWidth: lineWidth)
                .frame(width: radius * 1.8, height: radius * 1.8)
            // No words on a label too small to print them (and none while
            // the room offered is still nothing).
            if let label, radius >= 10 {
                words(label)
            }
            Circle()
                .fill(Color(rgb: 0x050404))
                .frame(width: holeRadius * 2, height: holeRadius * 2)
        }
        .frame(width: side, height: side)
    }

    /// Placed by the label's radius, inside the ring: the title's line
    /// centred 0.38 of the radius above the hole, the artist's 0.36 below,
    /// the disc's 0.62 below, each narrow enough that its corners stay
    /// within the ring (at most 0.83 of the radius from the middle). One
    /// line each; a long title is made a little smaller, then cut short.
    private func words(_ label: TurntableLabel) -> some View {
        ZStack {
            if !label.title.isEmpty {
                Text(label.title)
                    .font(.system(size: radius * 0.22, weight: .regular, design: .serif))
                    .foregroundStyle(Self.ink.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: radius * 1.3)
                    .position(x: radius, y: radius * 0.62)
            }
            if !label.artist.isEmpty {
                Text(label.artist)
                    .font(.system(size: radius * 0.16))
                    .foregroundStyle(Self.ink.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: radius * 1.3)
                    .position(x: radius, y: radius * 1.36)
            }
            if let disc = label.disc {
                Text("Disc \(disc)")
                    .font(.system(size: radius * 0.14))
                    .foregroundStyle(Self.ink.opacity(0.55))
                    .lineLimit(1)
                    .frame(width: radius * 0.8)
                    .position(x: radius, y: radius * 1.62)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    /// The label's ink: paper white, Theme.ground's by day.
    private static let ink = Color(rgb: 0xF6F3EE)
}

/// One faint pair of sheen wedges, half a turn apart: the light from above
/// caught by the grooves. White at a tenth at its brightest.
private struct TurntableSheen: View {
    var body: some View {
        Circle()
            .fill(AngularGradient(gradient: Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: 0.09),
                .init(color: .white.opacity(0.1), location: 0.12),
                .init(color: .white.opacity(0), location: 0.15),
                .init(color: .white.opacity(0), location: 0.59),
                .init(color: .white.opacity(0.1), location: 0.62),
                .init(color: .white.opacity(0), location: 0.65),
                .init(color: .white.opacity(0), location: 1),
            ]), center: .center, angle: .degrees(-40)))
            .allowsHitTesting(false)
    }
}

// MARK: - The arm

/// Where the arm is.
nonisolated enum TonearmState: Hashable, Sendable {
    /// Nothing to play: on its rest, beside the platter.
    case parked
    /// Playing: down on the record.
    case lowered
    /// Paused: lifted where it was.
    case lifted
}

/// The tonearm, following the song. It reads the player's position itself,
/// so that only it is evaluated as the song goes on (AudioPlayer's tick,
/// twice a second), not the record. Battery: its place is taken in steps of
/// a 400th of the way from the outer groove to the label, a twentieth of a
/// degree of the arm, so most ticks change nothing and redraw nothing — on
/// an album's side of forty minutes the arm moves once in six seconds.
///
/// When the song changes it cues, as a hand does: up off the record, across
/// to the new song's band, and down, in 0.6 s. Three animations set off by
/// the change of song (`cue`), no timeline. With Reduce Motion it fades to
/// its new place instead.
private struct TurntableArm: View {
    let geometry: TurntableGeometry
    let side: TurntableSide?

    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Up for a cue: the song has changed and the arm is on its way to the
    /// new song's band.
    @State private var isCueing = false
    /// The cues so far, so that only the last one sets the arm down.
    @State private var cues = 0

    init(geometry: TurntableGeometry, side: TurntableSide?) {
        self.geometry = geometry
        self.side = side
    }

    /// The cue: up, across, down; 0.6 s in all.
    static let liftSeconds: Double = 0.14
    static let swingSeconds: Double = 0.32
    static let dropSeconds: Double = 0.14

    var body: some View {
        // The queue's entry, not the track: the same song again later in
        // the queue is a new song for the arm.
        let song = player.current?.id
        let state: TonearmState = !player.hasTrack ? .parked : (player.isPlaying ? .lowered : .lifted)
        let duration = player.duration
        // Up for a cue, the arm heads for where the new song begins and does
        // not read the clock: a tick that moved it without an animation
        // would cut its swing short.
        let progress = isCueing || duration <= 0 ? 0 : min(1, max(0, player.elapsed / duration))
        let angle = state == .parked ? TurntableGeometry.parkedAngle : geometry.armAngle(place: place(progress))
        TonearmView(geometry: geometry, angle: angle, state: state,
                    isLifted: state == .lifted || (isCueing && state != .parked), song: song, fades: reduceMotion)
            // Lowered, lifted, parked: the arm swings and rises in a little
            // over half a second; with Reduce Motion it only fades. Inside
            // the song's animation, so that when both change at once (the
            // first song, from the rest) this one is the arm's.
            .animation(.easeInOut(duration: reduceMotion ? 0.25 : 0.6), value: state)
            // A new song: the cue's swing, once the arm is up (`cue`); with
            // Reduce Motion, a fade to the new place (TonearmView).
            .animation(reduceMotion
                       ? Animation.easeInOut(duration: 0.25)
                       : Animation.easeInOut(duration: Self.swingSeconds).delay(Self.liftSeconds),
                       value: song)
            .onChange(of: song) { old, new in
                cue(from: old, to: new)
            }
    }

    /// The needle's place, 0 … 1 from the outer groove to the label, with
    /// the song `progress` of the way through: in the song's band on its
    /// album's side, or across the whole record when the song plays alone.
    /// In steps of a 400th of the way (see the battery note above), kept
    /// within the song's band so a step never puts the needle in the song
    /// before.
    private func place(_ progress: Double) -> Double {
        guard let side else { return (progress * 400).rounded() / 400 }
        let step = (side.place(progress: progress) * 400).rounded() / 400
        return min(side.end, max(side.start, step))
    }

    /// The song changed: up, then (by the animation on `song`, which waits
    /// for this) across, then down. Not from the rest or back to it, which
    /// is the state's own swing; not under Reduce Motion, where the arm
    /// fades instead.
    private func cue(from old: UUID?, to new: UUID?) {
        guard old != nil, new != nil, !reduceMotion else { return }
        cues += 1
        let ticket = cues
        withAnimation(.easeOut(duration: Self.liftSeconds)) {
            isCueing = true
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.liftSeconds + Self.swingSeconds))
            // A newer cue keeps the arm up until its own swing is done.
            guard ticket == cues else { return }
            withAnimation(.easeIn(duration: Self.dropSeconds)) {
                isCueing = false
            }
        }
    }
}

/// What a fading arm (Reduce Motion) fades between: a change of either is a
/// new pose.
nonisolated private struct TonearmFace: Hashable, Sendable {
    let state: TonearmState
    let song: UUID?
}

/// The arm drawn at `angle`: a flat two-tone shape — a pale tube, a dark
/// headshell and counterweight, a pivot — and its hard shadow on the deck,
/// cast by the light above, longer when the arm is lifted.
private struct TonearmView: View {
    let geometry: TurntableGeometry
    let angle: Double
    let state: TonearmState
    /// Up off the record: paused, or cueing to another song.
    let isLifted: Bool
    /// The song the arm is on: with Reduce Motion a new one fades the arm
    /// to its new place.
    let song: UUID?
    /// Reduce Motion: a change of state or of song fades from the one pose
    /// to the other instead of moving the arm.
    let fades: Bool

    init(geometry: TurntableGeometry, angle: Double, state: TonearmState, isLifted: Bool, song: UUID?, fades: Bool) {
        self.geometry = geometry
        self.angle = angle
        self.state = state
        self.isLifted = isLifted
        self.song = song
        self.fades = fades
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pivotBase
            if fades {
                pose
                    .id(TonearmFace(state: state, song: song))
                    .transition(.opacity)
            } else {
                pose
            }
        }
        .frame(width: geometry.width, height: geometry.depth, alignment: .topLeading)
    }

    private var pose: some View {
        let w = geometry.width
        let lift: CGFloat = isLifted ? 1 : 0
        let anchor = UnitPoint(x: geometry.pivot.x / geometry.width, y: geometry.pivot.y / geometry.depth)
        return ZStack(alignment: .topLeading) {
            // The shadow: the arm's own shape, hard, no blur, cast down the
            // deck from the light above it.
            TonearmShape(geometry: geometry, part: .all)
                .fill(Color.black.opacity(isLifted ? 0.3 : 0.45))
                .rotationEffect(.degrees(angle), anchor: anchor)
                .offset(x: w * (0.01 + 0.014 * lift), y: w * (0.016 + 0.028 * lift))
            ZStack(alignment: .topLeading) {
                TonearmShape(geometry: geometry, part: .tube)
                    .fill(Self.pale)
                TonearmShape(geometry: geometry, part: .head)
                    .fill(Self.dark)
                TonearmShape(geometry: geometry, part: .weight)
                    .fill(Self.dark)
            }
            .rotationEffect(.degrees(angle), anchor: anchor)
            // Lifted: up off the record, toward the light.
            .offset(y: -w * 0.012 * lift)
            // The pivot's cap, which turns with the arm but is round.
            Circle()
                .fill(Self.pale)
                .frame(width: w * 0.04, height: w * 0.04)
                .offset(x: geometry.pivot.x - w * 0.02, y: geometry.pivot.y - w * 0.02 - w * 0.012 * lift)
        }
        .frame(width: geometry.width, height: geometry.depth, alignment: .topLeading)
    }

    /// The pivot's base, flat on the deck: it does not move.
    private var pivotBase: some View {
        let w = geometry.width
        return Circle()
            .fill(Self.dark)
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .frame(width: w * 0.1, height: w * 0.1)
            .offset(x: geometry.pivot.x - w * 0.05, y: geometry.pivot.y - w * 0.05)
    }

    /// The arm's two tones: bone, and near black.
    private static let pale = Color(rgb: 0xE6DCCB)
    private static let dark = Color(rgb: 0x120E0C)
}

/// A part of the arm.
nonisolated enum TonearmPart: Sendable {
    case tube
    case head
    case weight
    /// All three, for the shadow.
    case all
}

/// A part of the arm, drawn pointing straight down from the pivot (the
/// angle is TonearmView's rotation), in the deck's points.
nonisolated struct TonearmShape: Shape {
    let geometry: TurntableGeometry
    let part: TonearmPart

    init(geometry: TurntableGeometry, part: TonearmPart) {
        self.geometry = geometry
        self.part = part
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .tube:
            path.addRect(tube)
        case .head:
            path.addPath(head)
        case .weight:
            path.addRect(weight)
        case .all:
            path.addRect(tube)
            path.addPath(head)
            path.addRect(weight)
        }
        return path
    }

    /// The tube, from just behind the pivot to the headshell.
    private var tube: CGRect {
        let w = geometry.width
        let p = geometry.pivot
        return CGRect(x: p.x - w * 0.008, y: p.y - w * 0.03, width: w * 0.016,
                      height: geometry.armLength - w * 0.05)
    }

    /// The headshell at the stylus, turned a little toward the record's
    /// centre, as a real one is offset.
    private var head: Path {
        let w = geometry.width
        let p = geometry.pivot
        let stylus = CGPoint(x: p.x, y: p.y + geometry.armLength)
        let shell = CGRect(x: stylus.x - w * 0.022, y: stylus.y - w * 0.09, width: w * 0.044, height: w * 0.1)
        let turn = CGAffineTransform(translationX: stylus.x, y: stylus.y)
            .rotated(by: 16 * CGFloat.pi / 180)
            .translatedBy(x: -stylus.x, y: -stylus.y)
        return Path(shell).applying(turn)
    }

    /// The counterweight, behind the pivot.
    private var weight: CGRect {
        let w = geometry.width
        let p = geometry.pivot
        return CGRect(x: p.x - w * 0.03, y: p.y - w * 0.115, width: w * 0.06, height: w * 0.065)
    }
}
