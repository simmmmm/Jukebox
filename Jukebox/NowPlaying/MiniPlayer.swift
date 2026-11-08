// The mini player: what plays, in iOS 26's bottom accessory above the tab
// bar, as Music has it — the cover, the title (and the artist while the tab
// bar is full width), play or pause, and next. A tap anywhere else opens
// Now Playing. When the tab bar is minimised (scrolling down) the accessory
// sits inline beside it and is narrow: the title and play or pause only.

import JukeboxKit
import SwiftUI

struct MiniPlayer: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button {
                openNowPlaying()
            } label: {
                HStack(spacing: Theme.Space.m) {
                    cover
                    titles
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!player.hasTrack)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityHint("Opens Now Playing")

            playPauseButton
            if !isInline {
                nextButton
            }
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.xs)
        // The gaps between the buttons open Now Playing too.
        .contentShape(.rect)
        .onTapGesture {
            openNowPlaying()
        }
        // The accessory's height is the system's: past this size the two
        // lines would be cut off.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contextMenu {
            if let track = player.currentTrack {
                TrackMenu(track: track)
            }
        }
    }

    // MARK: Parts

    @ViewBuilder private var cover: some View {
        if player.currentTrack == nil, let station = startingStation {
            StationArtwork(station: station, size: 34, cornerRadius: Theme.Radius.thumbnail)
        } else {
            ArtworkView(player.currentTrack?.artwork, size: 34, cornerRadius: Theme.Radius.thumbnail)
        }
    }

    @ViewBuilder private var titles: some View {
        if let track = player.currentTrack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Space.xs) {
                    if isStation {
                        // A station plays: the radio's glyph, small, so the
                        // listener knows skips and thumbs teach it.
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(track.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                if showsArtist {
                    Text(track.artistLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else if let station = startingStation {
            // A station chosen while nothing played: its first track is a
            // moment away.
            VStack(alignment: .leading, spacing: 0) {
                Text(station.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !isInline {
                    Text("Tuning in…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            Text("Not Playing")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayPause()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button {
            player.next()
        } label: {
            Image(systemName: "forward.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel("Next")
    }

    // MARK: State

    /// Beside the minimised tab bar there is room for the title and one
    /// button only.
    private var isInline: Bool {
        placement == .inline
    }

    private var isStation: Bool {
        player.context?.isRadio == true
    }

    private var showsArtist: Bool {
        guard !isInline, let track = player.currentTrack else { return false }
        return !track.artistLine.isEmpty
    }

    /// The station being started, when the radio is choosing its first
    /// tracks.
    private var startingStation: Station? {
        radio.isStarting ? radio.station : nil
    }

    private var accessibilityTitle: String {
        guard let track = player.currentTrack else {
            return String(localized: "Not Playing")
        }
        let artist = track.artistLine
        return artist.isEmpty ? track.name : "\(track.name), \(artist)"
    }

    private func openNowPlaying() {
        guard player.hasTrack else { return }
        navigator.isNowPlayingPresented = true
    }
}
