// The mini player: what plays, in iOS 26's bottom accessory above the tab
// bar, as Music has it — the cover, the title (and the artist while the tab
// bar is full width), play or pause, and next. A tap anywhere else opens
// Now Playing. When the tab bar is minimised (scrolling down) the accessory
// sits inline beside it and is narrow: the title and play or pause only.
//
// The player's error ("Could not play …", a station that finds nothing)
// takes the artist's line for the five seconds the player keeps it: Now
// Playing shows it as a banner, but most of the time Now Playing is closed,
// and a song that silently does not play, or a station that silently does
// not start, reads as a broken button.

import JukeboxKit
import SwiftUI
import UIKit

struct MiniPlayer: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    init() {}

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
        .onChange(of: player.errorMessage) { _, message in
            // Shown on this line silently; VoiceOver is told. Not while Now
            // Playing is open: it tells VoiceOver itself, and once is enough.
            if let message, !navigator.isNowPlayingPresented {
                UIAccessibility.post(notification: .announcement, argument: message)
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
        Group {
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
                    if let shownError {
                        errorLine(shownError)
                    } else if showsArtist {
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
                    if let shownError {
                        errorLine(shownError)
                    } else if !isInline {
                        Text("Tuning in…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // Nothing plays: a station that found nothing to play ends
                // here, and says so under "Not Playing".
                VStack(alignment: .leading, spacing: 0) {
                    Text("Not Playing")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let shownError {
                        errorLine(shownError)
                    }
                }
            }
        }
        // The error comes and goes, after five seconds, as a crossfade.
        .animation(.easeInOut(duration: 0.25), value: shownError)
    }

    /// The error in the artist's place: as quiet as the artist, with the
    /// warning sign Now Playing's banner has, so it does not read as a name.
    private func errorLine(_ message: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
            Text(verbatim: message)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
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

    /// The player's error while it keeps it, on the second line. Not beside
    /// the minimised tab bar, which has room for the title alone.
    private var shownError: String? {
        guard !isInline else { return nil }
        return player.errorMessage
    }

    /// The station being started, when the radio is choosing its first
    /// tracks.
    private var startingStation: Station? {
        radio.isStarting ? radio.station : nil
    }

    private var accessibilityTitle: String {
        guard let track = player.currentTrack else {
            let notPlaying = String(localized: "Not Playing")
            if let error = player.errorMessage {
                return "\(notPlaying), \(error)"
            }
            return notPlaying
        }
        // What the eyes read on the second line, the ears hear second.
        if let error = player.errorMessage {
            return "\(track.name), \(error)"
        }
        let artist = track.artistLine
        return artist.isEmpty ? track.name : "\(track.name), \(artist)"
    }

    private func openNowPlaying() {
        guard player.hasTrack else { return }
        navigator.isNowPlayingPresented = true
    }
}
