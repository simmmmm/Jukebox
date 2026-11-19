// The mini player: what plays, in iOS 26's bottom accessory above the tab
// bar, as Music has it — the cover, the title (and under it the artist, or
// the station after its mark, while the tab bar is full width), play or
// pause, and next. A tap anywhere else opens
// Now Playing. When the tab bar is minimised (scrolling down) the accessory
// sits inline beside it and is narrow: the title and play or pause only.
//
// The player's error ("Could not play …", a station that finds nothing)
// takes the artist's line for the five seconds the player keeps it: Now
// Playing shows it as a banner, but most of the time Now Playing is closed,
// and a song that silently does not play, or a station that silently does
// not start, reads as a broken button.
//
// The tabs' alone (the iPhone, a narrow iPad window). The wide window, the
// iPad's and the Mac's, has the player's bar across its foot instead, as
// Linux's (PlayerBar), so this is never there.

import JukeboxKit
import SwiftUI

#if os(iOS)
struct MiniPlayer: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    /// Beside the minimised tab bar there is room for the title and one
    /// button only (iOS 26's accessory, `AccessoryMiniPlayer`); iOS 18's
    /// bar above the tabs is always full width.
    private let isInline: Bool

    init(isInline: Bool = false) {
        self.isInline = isInline
    }

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
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    // MARK: Parts

    @ViewBuilder private var cover: some View {
        if player.currentTrack == nil, let station = startingStation {
            StationArtwork(station: station, size: 34, cornerRadius: Theme.Radius.artwork)
        } else {
            ArtworkView(player.currentTrack?.artwork, size: 34, cornerRadius: Theme.Radius.artwork)
        }
    }

    @ViewBuilder private var titles: some View {
        Group {
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Theme.Space.xs) {
                        if isStation && isInline {
                            // Beside the minimised tab bar there is no
                            // second line: the mark before the title says
                            // it is the radio.
                            stationMark
                        }
                        Text(track.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        // Private Listening on (NotCountedViews): small, so
                        // a mode kept for days is not forgotten.
                        if player.notCounted.isPrivate {
                            Image(systemName: "eye.slash")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Private Listening is on")
                        }
                    }
                    if let shownError {
                        errorLine(shownError)
                    } else if let station = player.context?.station, !isInline {
                        // A station plays: its mark in the accent and its
                        // name, as sketch D has it, so the listener knows
                        // it is the radio and that skips and thumbs teach it.
                        HStack(spacing: Theme.Space.xs) {
                            stationMark
                            Text(station.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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

    /// The mark, small, flat, in the accent: the arch means a station.
    private var stationMark: some View {
        ArchMark(size: 11, style: .template)
            .foregroundStyle(Theme.accent)
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
        if let station = player.context?.station {
            return "\(track.name), \(station.title)"
        }
        let artist = track.artistLine
        return artist.isEmpty ? track.name : "\(track.name), \(artist)"
    }

    private func openNowPlaying() {
        guard player.hasTrack else { return }
        navigator.isNowPlayingPresented = true
    }
}

/// iOS 26's accessory tells the player where it sits: the environment value
/// is 26's alone, so it is read here and handed on.
@available(iOS 26, *)
struct AccessoryMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayer(isInline: placement == .inline)
    }
}

/// iOS 18 has no bottom accessory: the player sits in a bar of its own on
/// each tab's foot, just above the tab bar, in the bar's own material with a
/// hairline over it, as Music had it before 26. Tapped, Now Playing as on 26.
struct MiniPlayerBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayer()
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: 56)
                    .background(.bar)
                    .overlay(alignment: .top) { Hairline(inset: 0) }
            }
        }
    }
}
#endif
