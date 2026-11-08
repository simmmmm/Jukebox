// Now Playing's record player, in the cover's place. The photographer, 8
// November 2026: "Ik vind de platenspeler ideeen leuk maar dan zou ik ook de
// plaat willen zien draaien met de album art er op het liefst in een soort
// perspectief van licht erboven." So the song's cover is a picture disc that
// turns at 33⅓ while the music plays, on a deck seen from a little above,
// lit from above.
//
// Drawn, not rendered (docs/design/tells.md, 7: "A glossy 3D render: chrome
// arm, specular streaks, a spotlight" was a tell): a matte plinth with one
// soft falloff of the light from above; a matte platter; the picture disc —
// the cover cut round, a dark label with its hole, fine grooves over the
// art; one faint pair of sheen wedges that stay where the light is while the
// record turns under them; and the arm, a flat two-tone shape with a pivot
// and a hard, unblurred shadow. The arm's angle is the song's position: it
// creeps in from the outer groove to the label as the song plays. Playing,
// it is down on the record; paused, it is lifted (a small rise and a longer
// shadow); with nothing to play it rests beside the platter.
//
// Battery first ("Als batterij een zorg wordt moeten we ook ff kijken wat we
// daar aan kunnen doen"). Every choice below that costs or saves power says
// so where it is made. In short: the record is drawn once and only its
// rotation changes; it turns at most 30 times a second; it turns only while
// it can be seen and the music plays, never in Low Power Mode or under
// Reduce Motion, and not when Settings' Spin the Record is off; at rest
// nothing about it is redrawn at all.
//
// The deck is decoration: VoiceOver skips it, and every control around it
// is Apple's.

import Combine
import Foundation
import JukeboxKit
import SwiftUI
import UIKit

// MARK: - Geometry

/// The deck's measures, in points, for a plinth `width` wide: where the
/// platter, the record and the arm are, and the arm's angle for a place in
/// the song. Plain numbers, `nonisolated`, as the arm's Shape reads them.
nonisolated struct TurntableGeometry: Sendable {
    /// How far the deck is tipped back, in degrees, and the perspective it
    /// is seen in: sketch D's deck, seen from a little above and in front.
    static let tilt: Double = 46
    static let perspective: CGFloat = 0.4
    /// The plinth's depth to its width.
    static let depthRatio: CGFloat = 1.08
    /// The arm at rest beside the platter, off the record: degrees clockwise
    /// from straight down.
    static let parkedAngle: Double = -3

    let width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }

    var depth: CGFloat { width * Self.depthRatio }
    /// The platter's and the record's centre, left of the middle to leave
    /// the arm its room on the right.
    var center: CGPoint { CGPoint(x: width * 0.44, y: depth * 0.5) }
    var platterRadius: CGFloat { width * 0.405 }
    var discRadius: CGFloat { width * 0.385 }
    var labelRadius: CGFloat { discRadius * 0.34 }
    var holeRadius: CGFloat { width * 0.011 }
    /// The arm's pivot, top right, and its length from the pivot to the
    /// stylus: about as far as from the pivot to the spindle, as a real
    /// arm's, so the stylus's arc crosses the record from rim to label.
    var pivot: CGPoint { CGPoint(x: width * 0.885, y: depth * 0.13) }
    var armLength: CGFloat { width * 0.56 }
    /// Where the stylus rides: the outermost groove, and the last one
    /// before the label.
    var outerGroove: CGFloat { discRadius * 0.94 }
    var innerGroove: CGFloat { labelRadius * 1.12 }

    /// The plinth's width that fits `size` once it is tipped back: the near
    /// edge comes out a little wider than the plinth itself, and the deck
    /// shows about three quarters of its depth.
    static func width(fitting size: CGSize) -> CGFloat {
        max(0, min(size.width / 1.16, size.height / (depthRatio * 0.78)))
    }

    /// The arm's angle, degrees clockwise from straight down, with the
    /// stylus `progress` (0 … 1) of the way from the outer groove to the
    /// label. About 12° at the start of a song and 34° at its end.
    func armAngle(progress: Double) -> Double {
        let p = CGFloat(min(1, max(0, progress)))
        let radius = outerGroove + (innerGroove - outerGroove) * p
        return angle(toRadius: radius) ?? (12 + 22 * Double(p))
    }

    /// Where the arm's circle about the pivot crosses the groove of
    /// `radius`: of the two crossings, the one nearer the arm's rest (the
    /// smaller angle). Nil when they do not cross.
    private func angle(toRadius radius: CGFloat) -> Double? {
        let dx = center.x - pivot.x
        let dy = center.y - pivot.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let length = armLength
        guard distance > 0, abs(distance - radius) <= length, length <= distance + radius else { return nil }
        let along = (length * length - radius * radius + distance * distance) / (2 * distance)
        let across = max(0, length * length - along * along).squareRoot()
        let ux = dx / distance
        let uy = dy / distance
        let baseX = pivot.x + along * ux
        let baseY = pivot.y + along * uy
        var best: Double?
        for side in [CGFloat(1), CGFloat(-1)] {
            let x = baseX - side * across * uy
            let y = baseY + side * across * ux
            let degrees = atan2(Double(pivot.x - x), Double(y - pivot.y)) * 180 / Double.pi
            best = min(best ?? degrees, degrees)
        }
        return best
    }
}

// MARK: - The deck

/// The record player for Now Playing: as wide as it is offered, tipped back.
/// Its record turns while the song plays (see `spins` for when, exactly).
struct Turntable: View {
    let artwork: Artwork?
    let isPlaying: Bool

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

    init(artwork: Artwork?, isPlaying: Bool) {
        self.artwork = artwork
        self.isPlaying = isPlaying
    }

    /// 33⅓ turns a minute: 200° a second, a turn in 1.8 s.
    static let degreesPerSecond: Double = 200
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
            let geometry = TurntableGeometry(width: TurntableGeometry.width(fitting: proxy.size))
            deck(geometry)
                // Tipped back, the near edge toward the listener, the far
                // edge away: the deck seen from a little above.
                .rotation3DEffect(.degrees(TurntableGeometry.tilt), axis: (x: 1, y: 0, z: 0),
                                  anchor: .center, perspective: TurntableGeometry.perspective)
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
    }

    private func deck(_ g: TurntableGeometry) -> some View {
        let disc = g.discRadius * 2
        let platter = g.platterRadius * 2
        return ZStack(alignment: .topLeading) {
            // The plinth: matte, with one soft falloff of the light from
            // above — on the plinth only, not a spotlight on the room.
            RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                .fill(LinearGradient(colors: [Self.plinthLit, Self.plinthShade], startPoint: .top, endPoint: .bottom))
                .frame(width: g.width, height: g.depth)

            // The platter, matte, a little wider than the record.
            Circle()
                .fill(Self.platter)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
                .frame(width: platter, height: platter)
                .offset(x: g.center.x - g.platterRadius, y: g.center.y - g.platterRadius)

            // The record. Battery: `drawingGroup` draws the cover, the
            // grooves and the label once into a single layer; turning it is
            // then a change of that layer's rotation, not a redraw of forty
            // circles and an image. The timeline asks for at most 30 frames
            // a second (half the screen's 60), and none at all while the
            // record rests: paused, it wakes nothing, and the body is not
            // evaluated again until something else changes.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: spunSince == nil && coast == nil)) { timeline in
                TurntableDisc(artwork: artwork, radius: g.discRadius, labelRadius: g.labelRadius,
                              holeRadius: g.holeRadius)
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

            TurntableArm(geometry: g)
        }
        .frame(width: g.width, height: g.depth, alignment: .topLeading)
    }

    // MARK: Turning

    /// The record's angle at `date`: turning at 33⅓ from where it began,
    /// slowing to a stop over the coast, or at rest where it stopped.
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

/// A coast-down: when it began, and the record's angle then.
nonisolated private struct TurntableCoast: Equatable, Sendable {
    let start: Date
    let from: Double
}

// MARK: - The record

/// The picture disc: the cover on vinyl, cut round, the grooves over it, a
/// dark label with a ring and its hole. Drawn once (Turntable's
/// `drawingGroup`) and turned as a whole.
private struct TurntableDisc: View {
    let artwork: Artwork?
    let radius: CGFloat
    let labelRadius: CGFloat
    let holeRadius: CGFloat

    init(artwork: Artwork?, radius: CGFloat, labelRadius: CGFloat, holeRadius: CGFloat) {
        self.artwork = artwork
        self.radius = radius
        self.labelRadius = labelRadius
        self.holeRadius = holeRadius
    }

    var body: some View {
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
            Circle()
                .fill(Color(rgb: 0x1A1411))
                .frame(width: labelRadius * 2, height: labelRadius * 2)
            Circle()
                .stroke(Theme.Arch.glow.opacity(0.28), lineWidth: max(0.5, radius * 0.005))
                .frame(width: labelRadius * 1.56, height: labelRadius * 1.56)
            Circle()
                .fill(Color(rgb: 0x050404))
                .frame(width: holeRadius * 2, height: holeRadius * 2)
        }
        .frame(width: side, height: side)
    }
}

/// Fine grooves over the picture, a few dozen thin rings, dark and light
/// by turns, each at its own faint strength, as grooves catch the light
/// unevenly; and three darker gaps between the tracks.
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
                    .stroke(Self.color(i), lineWidth: Self.isGap(i) ? 1.2 : 0.5)
                    .frame(width: r * 2, height: r * 2)
            }
        }
        .frame(width: outer * 2, height: outer * 2)
    }

    private static func isGap(_ i: Int) -> Bool {
        i == 10 || i == 21 || i == 31
    }

    private static func color(_ i: Int) -> Color {
        if isGap(i) { return Color.black.opacity(0.3) }
        // Steps of the golden angle: no two neighbours alike, no pattern.
        let wobble = 0.5 + 0.5 * sin(Double(i) * 2.39996)
        return i.isMultiple(of: 2)
            ? Color.black.opacity(0.08 + 0.1 * wobble)
            : Color.white.opacity(0.03 + 0.05 * wobble)
    }
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
/// twice a second), not the record. Battery: the position is taken in
/// steps of a 400th of the song, a twentieth of a degree of the arm, so
/// most ticks change nothing and redraw nothing.
private struct TurntableArm: View {
    let geometry: TurntableGeometry

    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(geometry: TurntableGeometry) {
        self.geometry = geometry
    }

    var body: some View {
        let state: TonearmState = !player.hasTrack ? .parked : (player.isPlaying ? .lowered : .lifted)
        let duration = player.duration
        let progress = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        let step = (progress * 400).rounded() / 400
        let angle = state == .parked ? TurntableGeometry.parkedAngle : geometry.armAngle(progress: step)
        TonearmView(geometry: geometry, angle: angle, state: state, fades: reduceMotion)
            // Lowered, lifted, parked: the arm swings and rises in a little
            // over half a second; with Reduce Motion it only fades.
            .animation(.easeInOut(duration: reduceMotion ? 0.25 : 0.6), value: state)
    }
}

/// The arm drawn at `angle` in `state`: a flat two-tone shape — a pale tube,
/// a dark headshell and counterweight, a pivot — and its hard shadow on the
/// deck, cast by the light above, longer when the arm is lifted.
private struct TonearmView: View {
    let geometry: TurntableGeometry
    let angle: Double
    let state: TonearmState
    /// Reduce Motion: a change of state fades from the one pose to the
    /// other instead of moving the arm.
    let fades: Bool

    init(geometry: TurntableGeometry, angle: Double, state: TonearmState, fades: Bool) {
        self.geometry = geometry
        self.angle = angle
        self.state = state
        self.fades = fades
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            pivotBase
            if fades {
                pose
                    .id(state)
                    .transition(.opacity)
            } else {
                pose
            }
        }
        .frame(width: geometry.width, height: geometry.depth, alignment: .topLeading)
    }

    private var pose: some View {
        let w = geometry.width
        let lift: CGFloat = state == .lifted ? 1 : 0
        let anchor = UnitPoint(x: geometry.pivot.x / geometry.width, y: geometry.pivot.y / geometry.depth)
        return ZStack(alignment: .topLeading) {
            // The shadow: the arm's own shape, hard, no blur, cast down the
            // deck from the light above it.
            TonearmShape(geometry: geometry, part: .all)
                .fill(Color.black.opacity(state == .lifted ? 0.3 : 0.45))
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
