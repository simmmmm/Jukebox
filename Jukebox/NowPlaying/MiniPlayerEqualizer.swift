// Equalizer's meter, behind its row (RecordMiniPlayer, `.equalizer`): the
// music's levels, low to high, as an 80s hi-fi's or jukebox's level meter:
// "ik had eerder horizontale balkjes verwacht voor meer dat jaren 80
// jukebox gevoel zoals in mijn voorbeeld", and "houd t wel lekker rustig"
// (the photographer, 21 November 2026). So:
//
//   - 16 columns of short wide segments, from the tab bar's shoulder up
//     behind the whole row to the arch's crown: the meter is the bar's
//     ground. The segments not lit stay faintly there, the display at rest;
//   - flat, no bloom: light means on air (tells.md, 1), and this is the
//     song on air, quietly. Copper at the foot to Glow at the top, the same
//     in every column, the lit ones a touch brighter going up, so no colour
//     jumps with the level;
//   - at most 16 % by night and 8 % by day over the page's own solid
//     ground, so the words keep 4.5:1 over a lit segment: by night white
//     about 13:1, Glow 7.9:1, the artist's grey 4.5:1; by day Copper 4.5:1
//     and black about 15:1 (the artist's grey is the system's, near 3:1 on
//     the plain page too);
//   - they rise in about a fifth of a second and fall at 0.4 of their
//     height a second, so a beat lifts them and they settle, never flicker;
//   - paused they fall and rest low; with Reduce Motion they stand still at
//     a calm level, whatever plays.
//
// The levels are the meter's (LevelMeter.swift) where this device plays the
// sound; where it does not (HLS, Play On, AirPlay) a slow envelope of their
// own, a beat at 112 a minute in the low columns and a drift over all of
// them. 30 frames a second while it plays, none while paused and settled,
// off screen, under Now Playing or in the background.

import SwiftUI

#if os(iOS)
struct EqualizerBars: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var motion = BarMotion()
    @State private var isOnScreen = false
    /// Paused a moment ago: the bars still falling to rest.
    @State private var isFalling = false

    static let columns = 16
    /// A segment's height and the gap over it, points.
    static let segment: CGFloat = 4
    static let gap: CGFloat = 3
    /// The gap between columns, points.
    static let gutter: CGFloat = 5
    /// An unlit segment's part of a lit one's strength: the grid at rest.
    static let unlit = 0.2
    /// Where they rest, paused.
    static let rest: Float = 0.04
    /// The brightest lit segment's strength, over the solid ground.
    static let nightOpacity = 0.16
    static let dayOpacity = 0.08
    /// The screenshot walk's `-equalizerStill YES` only: Reduce Motion's
    /// calm level whatever plays, as the walk's songs stall in the
    /// simulator and the bars would only rest.
    private static let walkStill = UserDefaults.standard.bool(forKey: "equalizerStill")

    private var standsStill: Bool { reduceMotion || Self.walkStill }

    /// Seen, and the app in front: only then is anything worked out.
    private var isSeen: Bool {
        isOnScreen && scenePhase == .active && !navigator.isNowPlayingPresented
    }

    private var moves: Bool {
        isSeen && !standsStill && (player.isPlaying || isFalling)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !moves)) { context in
            Canvas { graphics, size in
                let levels = standsStill ? Self.still : motion.step(to: target(at: context.date), at: context.date)
                draw(levels, in: &graphics, size: size)
            }
        }
        .opacity(colorScheme == .dark ? Self.nightOpacity : Self.dayOpacity)
        .accessibilityHidden(true)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        // The meter copies samples only while some bar wants them.
        .onChange(of: isSeen && !standsStill) { _, wants in
            LevelMeter.shared.watch(wants)
        }
        .task(id: player.isPlaying) {
            guard !player.isPlaying else { return }
            isFalling = true
            try? await Task.sleep(for: .seconds(2.5))
            isFalling = false
        }
    }

    /// What the bars go towards now.
    private func target(at date: Date) -> [Float] {
        guard player.isPlaying else { return Array(repeating: Self.rest, count: Self.columns) }
        // AirPlay: the tap is ahead of the room by the receiver's delay.
        if !SystemRoute.shared.isAirPlay, let real = LevelMeter.shared.bands(Self.columns) {
            return real
        }
        return Self.envelope(at: date.timeIntervalSinceReferenceDate)
    }

    /// The fallback: a shape like music's (the low bars higher), drifting
    /// slowly, and a soft beat in the low third.
    static func envelope(at time: Double) -> [Float] {
        let beat = Float(exp(-4 * (time * 112 / 60).truncatingRemainder(dividingBy: 1)))
        return (0 ..< columns).map { column in
            let x = Float(column) / Float(columns - 1)
            let shape = 0.5 - 0.26 * x
            let drift = Float(sin(time * 0.9 + Double(column) * 0.7) * sin(time * 0.37 + Double(column) * 1.3))
            let pulse = x < 0.34 ? 0.14 * beat * (1 - x * 2) : 0
            return min(1, max(Self.rest, shape * (0.8 + 0.2 * drift) + pulse))
        }
    }

    /// Reduce Motion's, and the walk's: a moment of music, standing, the
    /// low end fuller, at about half height.
    static let still: [Float] = [0.56, 0.7, 0.62, 0.74, 0.6, 0.5, 0.62, 0.46,
                                 0.54, 0.42, 0.5, 0.38, 0.44, 0.32, 0.36, 0.26]

    private func draw(_ levels: [Float], in graphics: inout GraphicsContext, size: CGSize) {
        let pitch = Self.segment + Self.gap
        let rows = max(1, Int((size.height + Self.gap) / pitch))
        let column = size.width / CGFloat(levels.count)
        let width = column - Self.gutter
        for (index, level) in levels.enumerated() {
            let lit = Int((CGFloat(level) * CGFloat(rows)).rounded())
            let x = column * CGFloat(index) + Self.gutter / 2
            for row in 0 ..< rows {
                let up = Double(row) / Double(max(1, rows - 1))
                let y = size.height - CGFloat(row + 1) * pitch + Self.gap
                let segment = Path(CGRect(x: x, y: y, width: width, height: Self.segment))
                let colour = Self.colour(at: up)
                let strength = row < lit ? 0.75 + 0.25 * up : Self.unlit
                graphics.fill(segment, with: .color(colour.opacity(strength)))
            }
        }
    }

    /// Copper at the foot to Glow at the top.
    private static func colour(at up: Double) -> Color {
        let copper = Tokens.Arch.copper, glow = Tokens.Arch.glow
        func part(_ shift: UInt32) -> Double {
            let a = Double((copper >> shift) & 0xFF), b = Double((glow >> shift) & 0xFF)
            return (a + (b - a) * up) / 255
        }
        return Color(red: part(16), green: part(8), blue: part(0))
    }
}

/// The bars' heights between frames: up quickly, down slowly, by the time
/// between frames, so 30 or 60 a second look the same.
private final class BarMotion {
    private var levels: [Float] = []
    private var last: Date?

    /// Rise: the part of the way closed each second. Fall: height a second.
    static let rise: Float = 5
    static let fall: Float = 0.4

    func step(to target: [Float], at date: Date) -> [Float] {
        let seconds = Float(min(0.1, max(0, date.timeIntervalSince(last ?? date))))
        last = date
        if levels.count != target.count { levels = Array(repeating: EqualizerBars.rest, count: target.count) }
        for index in levels.indices {
            let goal = target[index]
            if goal > levels[index] {
                levels[index] += (goal - levels[index]) * min(1, seconds * Self.rise)
            } else {
                levels[index] = max(goal, levels[index] - seconds * Self.fall)
            }
        }
        return levels
    }
}
#endif
