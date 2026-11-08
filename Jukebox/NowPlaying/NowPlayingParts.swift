// The pieces Now Playing is made of: the blurred cover behind everything,
// the scrubber (Numa's slim slider), the small round buttons beside the
// title and the transport's buttons. Named NowPlaying… so they cannot clash
// with another part's own helpers.

import JukeboxKit
import SwiftUI
import UIKit

// MARK: - Backdrop

/// The current cover, large and blurred past recognition, under a dark
/// scrim: Now Playing takes its colours from what plays, as Music does,
/// and white text stays legible over a white cover. A new cover fades in
/// over the old one, settling from a little larger; under Reduce Motion
/// it only fades.
struct NowPlayingBackdrop: View {
    let artwork: Artwork?

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    /// Which cover `image` is. A new one is a new view, so the old one
    /// fades out while the new one fades in.
    @State private var shown: Artwork?

    init(artwork: Artwork?) {
        self.artwork = artwork
    }

    var body: some View {
        ZStack {
            Theme.page
            if let image {
                NowPlayingBlurredImage(image: image)
                    .id(shown)
                    .transition(coverTransition)
            }
            LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.6)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: artwork) {
            await load()
        }
    }

    private var coverTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.2))
    }

    private func load() async {
        guard let artwork, let client = app.client else {
            show(nil, for: nil)
            return
        }
        // Small on purpose: it is blurred past recognition, a blur of a
        // small image is cheap, and this is the size Up Next's rows fetch
        // (48 points at 3x falls in ImagePipeline's 240 bucket), so it is
        // usually in memory already.
        let url = client.imageURL(artwork, maxPixelSize: 240)
        let loaded: UIImage?
        if let cached = ImagePipeline.shared.cached(url) {
            loaded = cached
        } else {
            loaded = await ImagePipeline.shared.image(for: url)
        }
        guard !Task.isCancelled else { return }
        show(loaded, for: artwork)
    }

    private func show(_ new: UIImage?, for artwork: Artwork?) {
        guard new != nil || image != nil else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.4 : 0.9)) {
            image = new
            shown = artwork
        }
    }
}

private struct NowPlayingBlurredImage: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .saturation(1.3)
                // Opaque: the edges stay filled instead of fading to the
                // ground behind.
                .blur(radius: 60, opaque: true)
        }
    }
}

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

/// A small round button's face beside the title (favourite, "…") and in the
/// station's row (the thumbs): a glyph in a faint white circle, brighter
/// when it is on.
struct NowPlayingRoundGlyph: View {
    let systemName: String
    let isOn: Bool

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 34

    init(systemName: String, isOn: Bool = false) {
        self.systemName = systemName
        self.isOn = isOn
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(isOn ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
            .frame(width: min(side, 48), height: min(side, 48))
            .background(Color.white.opacity(isOn ? 0.24 : 0.12), in: .circle)
            .contentShape(.circle)
    }
}

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
