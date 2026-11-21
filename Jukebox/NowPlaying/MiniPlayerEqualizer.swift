// Equalizer's bars, behind its row (RecordMiniPlayer, `.equalizer`): the
// music's levels, low to high, as a hi-fi's meter seen through frosted
// glass. "houd t wel lekker rustig", and no neon (the photographer, 21
// November 2026). So:
//
//   - 18 plain thin bars, no segments, no bloom: light means on air
//     (tells.md, 1), and this is the song on air, quietly;
//   - Copper at the foot to Glow at the top, the same in every bar, so no
//     colour jumps with the level; by night at 24 %, by day 14 %, over the
//     page's own ground, so the words keep their contrast: white on the
//     brightest by night about 11:1 and Glow 6:1, Copper by day 4.9:1;
//   - they rise in about a fifth of a second and fall at half their height
//     a second, so a beat lifts them and they settle, never flicker;
//   - paused they fall and rest low; with Reduce Motion they stand still at
//     a calm level, whatever plays.
//
// The levels are the meter's (LevelMeter.swift) where this device plays the
// sound; where it does not (HLS, Play On, AirPlay) a slow envelope of their
// own, a beat at 112 a minute in the low bars and a drift over all of them.
// 30 frames a second while it plays, none while paused and settled, off
// screen, under Now Playing or in the background.

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

    static let columns = 18
    /// The tallest bar's part of its frame: the row and the crown over it.
    static let reach: CGFloat = 1
    /// Where they rest, paused.
    static let rest: Float = 0.04
    static let nightOpacity = 0.24
    /// The screenshot walk's `-equalizerStill YES` only: Reduce Motion's
    /// calm level whatever plays, as the walk's songs stall in the
    /// simulator and the bars would only rest.
    private static let walkStill = UserDefaults.standard.bool(forKey: "equalizerStill")

    private var standsStill: Bool { reduceMotion || Self.walkStill }
    static let dayOpacity = 0.14

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

    /// Reduce Motion's: the envelope's shape, standing.
    static let still: [Float] = (0 ..< columns).map { 0.32 - 0.14 * Float($0) / Float(columns - 1) }

    private func draw(_ levels: [Float], in graphics: inout GraphicsContext, size: CGSize) {
        let column = size.width / CGFloat(levels.count)
        let width = min(6, max(3, column * 0.28))
        let tallest = size.height * Self.reach
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [Theme.Arch.copper, Theme.Arch.glow]),
            startPoint: CGPoint(x: 0, y: size.height),
            endPoint: CGPoint(x: 0, y: size.height - tallest))
        for (index, level) in levels.enumerated() {
            let height = max(width, tallest * CGFloat(level))
            let x = column * (CGFloat(index) + 0.5) - width / 2
            let bar = CGRect(x: x, y: size.height - height, width: width, height: height)
            graphics.fill(Path(roundedRect: bar, cornerRadius: width / 2), with: shading)
        }
    }
}

/// The bars' heights between frames: up quickly, down slowly, by the time
/// between frames, so 30 or 60 a second look the same.
private final class BarMotion {
    private var levels: [Float] = []
    private var last: Date?

    /// Rise: the part of the way closed each second. Fall: height a second.
    static let rise: Float = 5
    static let fall: Float = 0.5

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
