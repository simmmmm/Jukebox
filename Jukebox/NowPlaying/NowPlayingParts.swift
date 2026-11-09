// The pieces Now Playing is made of: the scrubber (Numa's slim slider) and
// the transport's buttons. The sleeve and its record are SleeveRecord.swift,
// the ground under them NowPlayingGround.swift. Named NowPlaying…
// so they cannot clash with another part's own helpers.

import JukeboxKit
import SwiftUI
import UIKit

// MARK: - Scrubber

/// Numa's slim slider as a scrubber: a thin line that thickens while it is
/// held, the time heard and the time left under it in digits that do not
/// jump. A drag moves the playhead from where it was, as Music's does,
/// rather than jumping to the finger; the track seeks when the finger lifts,
/// so a drag across a whole song is one seek, not a hundred.
struct NowPlayingScrubber: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// While held: where the playhead is, 0 … 1. Nil otherwise.
    @State private var dragFraction: Double?
    /// The playhead when the drag began.
    @State private var dragStart: Double = 0
    /// True while a finger is down. SwiftUI resets it when the system
    /// cancels the drag (a call, Siri), which never reaches onEnded.
    @GestureState private var isHeld = false

    var body: some View {
        let duration = player.duration
        let canSeek = player.hasTrack && duration > 0
        let playing = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        let fraction = dragFraction ?? playing
        let isDragging = dragFraction != nil
        let position = fraction * duration
        let spokenPosition: String = canSeek ? String(localized: "\(position.clock) of \(duration.clock)") : ""

        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                    // What has been heard, in the accent: the tint, which
                    // Now Playing sets to its cover's colour.
                    Capsule()
                        .fill(.tint)
                        .frame(width: width * CGFloat(fraction))
                }
                .frame(height: isDragging ? 10 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The whole height is the target, not the 5 points drawn.
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isHeld) { _, held, _ in
                            held = true
                        }
                        .onChanged { value in
                            guard canSeek else { return }
                            if dragFraction == nil { dragStart = playing }
                            let moved = Double(value.translation.width / width)
                            dragFraction = min(1, max(0, dragStart + moved))
                        }
                        .onEnded { value in
                            let target = dragFraction
                            dragFraction = nil
                            // A touch without a drag only showed the line thick.
                            guard canSeek, let target, abs(value.translation.width) >= 1 else { return }
                            player.seek(to: target * duration)
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(canSeek ? position.clock : "--:--")
                Spacer()
                Text(canSeek ? "-" + max(0, duration - position).clock : "--:--")
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(isDragging ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
        .onChange(of: isHeld) { _, held in
            // A cancelled drag would leave the line thick and the times
            // stopped. Let go after this update, when an onEnded that did
            // run has already seeked.
            guard !held else { return }
            Task { dragFraction = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(spokenPosition)
        .accessibilityAdjustableAction { direction in
            guard canSeek else { return }
            // A twentieth of the song, at least five seconds, a swipe.
            let step = max(5, duration / 20)
            switch direction {
            case .increment:
                player.seek(to: player.elapsed + step)
            case .decrement:
                player.seek(to: player.elapsed - step)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Buttons

/// The transport's buttons: the glyph alone, and a faint circle behind it
/// while it is pressed, as Music draws them. They shrink a little when
/// pressed, unless Reduce Motion is on.
struct NowPlayingTransportStyle: ButtonStyle {
    let diameter: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(diameter: CGFloat) {
        self.diameter = diameter
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0))
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(.circle)
    }
}

// MARK: - A title that scrolls

/// One line that does not fit scrolls by now and then rather than being cut
/// off, as Music's title does: it rests three seconds at its start, moves
/// left at 30 points a second until a second copy behind it stands where it
/// began, and rests again. A line that fits stands still. With Reduce Motion
/// it does not move: it wraps onto a second line instead. The photographer,
/// 9 November 2026: "Titel van het nummer past soms niet helemaal en dan kap
/// je die af. Dat is niet zo Nice. … laat je de titel af en toe voorbij
/// scrollen?"
struct NowPlayingMarquee: View {
    let text: String
    let font: Font

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The line's own width, measured; 0 until it is.
    @State private var lineWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Between the line and its copy: wide enough to see where it ends.
    private static let gap: CGFloat = 48
    private static let pointsPerSecond: CGFloat = 30
    private static let restSeconds: Double = 3
    /// The fade at the trailing edge while the line overflows, in points.
    private static let fade: CGFloat = 24

    var body: some View {
        if reduceMotion {
            Text(text)
                .font(font)
                .lineLimit(2)
        } else {
            // One line's height and the width offered, from a hidden copy;
            // the moving line is drawn over it.
            Text(text)
                .font(font)
                .lineLimit(1)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        moving(width: proxy.size.width)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(text))
        }
    }

    private func moving(width: CGFloat) -> some View {
        let overflows = lineWidth > width + 0.5
        return HStack(spacing: Self.gap) {
            line
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { measured in
                    lineWidth = measured
                }
            if overflows {
                line
            }
        }
        .offset(x: overflows ? offset : 0)
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask {
            if overflows {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.fade)
                }
            } else {
                Color.black
            }
        }
        .task(id: MarqueeRun(text: text, overflows: overflows)) {
            await run(overflows: overflows)
        }
    }

    private var line: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
    }

    /// Rest, scroll one length, jump back unseen (the copy stands where the
    /// line began), again; until the song or the room changes.
    private func run(overflows: Bool) async {
        offset = 0
        guard overflows else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.restSeconds))
            if Task.isCancelled { return }
            let distance = lineWidth + Self.gap
            let seconds = Double(distance / Self.pointsPerSecond)
            withAnimation(.linear(duration: seconds)) {
                offset = -distance
            }
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            offset = 0
        }
    }
}

/// What a marquee's scrolling depends on: a new title, or a title that has
/// come to fit (or stopped fitting), starts it over.
nonisolated private struct MarqueeRun: Hashable {
    let text: String
    let overflows: Bool
}
