// The station on the air, at the top of the Radio tab, as sketch D draws it
// (docs/design/radio-after.png): the screen's one small label, "On air";
// the station's art, the one lit thing on the page; its name in the serif;
// the song; the dial from Familiar to Adventurous; Pause and Stop as words;
// the thumbs as plain glyphs. On the ground, no card: "a card in a card,
// pill buttons with icon and label, a slogan under every station" were what
// sketch D took away. The dial is AppSettings.adventurousness itself, so it
// is where it was left for the next station too; moving it chooses the
// songs ahead again once it rests (RadioController.adventurousnessChanged),
// never the one playing.

import JukeboxKit
import SwiftUI
import UIKit

struct RadioOnAirCard: View {
    let station: Station

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(station: Station) {
        self.station = station
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button {
                navigator.isNowPlayingPresented = true
            } label: {
                header
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows Now Playing")

            RadioDial()
                .padding(.top, Theme.Space.s)

            HStack(spacing: Theme.Space.xl) {
                Button {
                    player.togglePlayPause()
                } label: {
                    Text(player.isPlaying ? "Pause" : "Play")
                }
                .buttonStyle(.secondary)
                .disabled(radio.isStarting)
                Button {
                    // The station first, so the song that stops is not taken
                    // as a skip; then the music.
                    radio.stop()
                    player.stop()
                } label: {
                    Text("Stop")
                }
                .buttonStyle(.secondary)
                Spacer(minLength: 0)
                if let track = player.currentTrack {
                    RadioThumbs(track: track)
                }
            }
        }
    }

    /// The art and the words beside it; above them at the largest sizes.
    private var header: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.l))
        return layout {
            StationArtwork(station: station, size: 120)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Eyebrow("On air")
                Text(station.title)
                    .font(.serif(.title))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .padding(.bottom, Theme.Space.xs)
                trackLines
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var trackLines: some View {
        if radio.isStarting {
            Text("Choosing the first songs…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let track = player.currentTrack {
            Text(track.name)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !track.artistLine.isEmpty {
                Text(track.artistLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Thumbs down and up for the song on the air, as plain glyphs: a thumbs
/// down skips it and plays less like it, a thumbs up plays more like it
/// (RadioController). The one given is filled, the thumbs up in the accent.
struct RadioThumbs: View {
    let track: Track

    @Environment(RadioController.self) private var radio

    init(track: Track) {
        self.track = track
    }

    var body: some View {
        let liked = radio.liked.contains(track.id)
        let disliked = radio.disliked.contains(track.id)
        HStack(spacing: Theme.Space.s) {
            Button {
                radio.dislike(track)
            } label: {
                Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.title3)
                    .foregroundStyle(disliked ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                    .symbolEffect(.bounce, value: disliked)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dislike")
            .accessibilityHint("Skips this song and plays less like it")
            .accessibilityAddTraits(disliked ? .isSelected : [])

            Button {
                radio.like(track)
            } label: {
                Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.title3)
                    .foregroundStyle(liked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .symbolEffect(.bounce, value: liked)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like")
            .accessibilityHint("Plays more like this song")
            .accessibilityAddTraits(liked ? .isSelected : [])
        }
    }
}

/// The radio's dial, wherever it is (the Radio tab, a station's page, Now
/// Playing): the system Slider in the accent, and under its two ends
/// "Familiar" and "Adventurous" — nothing else. Sketch D took away the
/// dial's ticks, numbers, phrases and caption: the ends say what it does.
/// A drag sends every step; the radio is told when it ends. Steps that come
/// without a drag (VoiceOver's swipes) are told as they come.
struct RadioDial: View {
    /// Told when a drag starts and ends: a station's page waits for the
    /// dial to rest before it chooses its list again.
    private let onDragging: (Bool) -> Void

    @Environment(RadioController.self) private var radio
    @Environment(AppSettings.self) private var settings
    @State private var isDragging = false

    init(onDragging: @escaping (Bool) -> Void = { _ in }) {
        self.onDragging = onDragging
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Slider(value: $settings.adventurousness, in: 0...1, onEditingChanged: { editing in
                isDragging = editing
                onDragging(editing)
                if !editing {
                    radio.adventurousnessChanged()
                    Stats.track(.dialChanged, ["value": Stats.dial(settings.adventurousness)])
                }
            })
            .tint(Theme.accent)
            .accessibilityLabel("Adventurousness")
            .accessibilityValue(Self.spoken(settings.adventurousness))
            HStack {
                Text("Familiar")
                Spacer()
                Text("Adventurous")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .onChange(of: settings.adventurousness) { _, _ in
            if !isDragging { radio.adventurousnessChanged() }
        }
    }

    /// Where it stands, for VoiceOver, which cannot see the thumb: as
    /// Settings' dial says it.
    static func spoken(_ value: Double) -> Text {
        if value < 0.25 { return Text("Familiar") }
        if value < 0.5 { return Text("Mostly familiar") }
        if value < 0.75 { return Text("Somewhat adventurous") }
        return Text("Adventurous")
    }
}
