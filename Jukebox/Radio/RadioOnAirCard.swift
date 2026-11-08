// The station on the air, at the top of the Radio tab: what plays, the dial
// from familiar to adventurous, and a way to stop. The dial is
// AppSettings.adventurousness itself, so it is where it was left for the
// next station too; moving it chooses the songs ahead again once it rests
// (RadioController.adventurousnessChanged), never the one playing.

import JukeboxKit
import SwiftUI
import UIKit

struct RadioOnAirCard: View {
    let station: Station

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator

    /// A drag sends every step; the radio is told when it ends. Steps that
    /// come without a drag (VoiceOver's swipes) are told as they come.
    @State private var isDragging = false

    init(station: Station) {
        self.station = station
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Button {
                navigator.isNowPlayingPresented = true
            } label: {
                HStack(spacing: Theme.Space.m) {
                    StationArtwork(station: station, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow("Now Playing")
                        Text(station.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        trackLine
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows Now Playing")

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Slider(value: $settings.adventurousness, in: 0...1, onEditingChanged: { editing in
                    isDragging = editing
                    if !editing { radio.adventurousnessChanged() }
                })
                .accessibilityLabel("Adventurousness")
                .accessibilityValue(dialValue)
                HStack {
                    Text("Familiar")
                    Spacer()
                    Text("Adventurous")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .onChange(of: settings.adventurousness) { _, _ in
                if !isDragging { radio.adventurousnessChanged() }
            }

            HStack(spacing: Theme.Space.m) {
                Button {
                    player.togglePlayPause()
                } label: {
                    if player.isPlaying {
                        Label("Pause", systemImage: "pause.fill")
                    } else {
                        Label("Play", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.secondary)
                .disabled(radio.isStarting)
                Button {
                    // The station first, so the song that stops is not taken
                    // as a skip; then the music.
                    radio.stop()
                    player.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.secondary)
            }
        }
        .padding(Theme.Space.l)
        // The system's grouped-card grey, as Settings' own cards: a step
        // up from the page in light and in dark.
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder
    private var trackLine: some View {
        if radio.isStarting {
            Text("Choosing the first songs…")
        } else if let track = player.currentTrack {
            Text("\(track.name) · \(track.artistLine)")
        } else {
            // Keeps the line's height, so the card does not jump.
            Text(verbatim: " ")
        }
    }

    /// "Familiar, 20%", for VoiceOver: the words at the dial's ends and
    /// where it is between them.
    private var dialValue: Text {
        let value = settings.adventurousness
        let percent = value.formatted(.percent.precision(.fractionLength(0)))
        if value < 0.34 { return Text("Familiar, \(percent)") }
        if value < 0.67 { return Text("Balanced, \(percent)") }
        return Text("Adventurous, \(percent)")
    }
}
