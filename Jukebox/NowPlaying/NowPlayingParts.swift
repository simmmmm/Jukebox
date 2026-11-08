// The pieces Now Playing is made of: the scrubber (Numa's slim slider) and
// the transport's buttons. The record is Turntable.swift. Named NowPlaying…
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
                    // What has been heard, in the accent: Glow, as Now
                    // Playing is always dark.
                    Capsule()
                        .fill(Theme.accent)
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
