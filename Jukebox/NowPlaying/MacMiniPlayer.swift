// The Mac's mini player: a small window of the song and its transport that
// stays above the others while you work, as Music's MiniPlayer and Amperfy
// 2.1.1's (features.md, "De moeite waard"; "doe alles", 18 November 2026).
// Opened from Window › Mini Player (⌥⌘M), no button anywhere else ("ik wil
// alleen er voor waken dat we niet 10000 knopen krijgen"). Linux's is the
// primary menu's Mini Player (Linux/App/Extras.swift), the same parts. The
// iPhone and the iPad have none: their mini player is the bar.

#if os(macOS)
import JukeboxKit
import SwiftUI

struct MacMiniPlayer: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let track = player.currentTrack
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                ArtworkView(track?.artwork, size: 64, cornerRadius: Theme.Radius.artwork, sleeve: track.map(TitleSleeve.Words.init(track:)))
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(track?.name ?? String(localized: "Nothing playing"))
                        .desktopFont(Tokens.Size.body15.size, weight: .medium)
                        .lineLimit(1)
                    Text(track?.artistLine ?? "")
                        .desktopFont(Tokens.Size.fact13.size)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Space.l) {
                Spacer()
                Button("Previous", systemImage: "backward.fill") { player.previous() }
                Button(player.isPlaying ? "Pause" : "Play",
                       systemImage: player.isPlaying ? "pause.fill" : "play.fill") { player.togglePlayPause() }
                    .font(.title2)
                Button("Next", systemImage: "forward.fill") { player.next() }
                Spacer()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(track == nil)
            ProgressView(value: progress(track))
        }
        .padding(Theme.Space.l)
        .frame(width: 360)
        .background(Theme.ground)
    }

    private func progress(_ track: Track?) -> Double {
        guard let length = track?.duration, length > 0 else { return 0 }
        return min(1, max(0, player.position / length))
    }
}
#endif
