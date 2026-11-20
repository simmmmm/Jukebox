// Glas, one of the three player bars in the test build (MiniPlayer.swift).
//
// The mini player: what plays, in a block of the cover's colour just above
// the tab bar. The photographer, 19 November 2026: "Die mag van mij qua vorm
// meer zoals die van spotify maar dan in de kleur van de albumhoes", of
// "dat balkje boven de knoppenbalk"; of the sketches he chose "A!", and
// then "Met b" (build/nowplaying-sketch/minibar.svg):
//
//   A: the block floats 8 points in from the screen's edges, flat in the
//      cover's colour, by day and by night the same (the cover's, not the
//      system's material). The cover small on the left, the title and the
//      artist in white, Play On and play or pause on the right, and a line
//      of 2 points along its foot for where the song is.
//   B: while a station plays, the second line is the station after its
//      mark, in Glow, and Dislike takes Play On's place: on the radio the
//      thumb is what the hand wants.
//
// A tap anywhere but the buttons opens Now Playing.
//
// The player's error ("Could not play …", a station that finds nothing)
// takes the second line for the five seconds the player keeps it: Now
// Playing shows it as a banner, but most of the time Now Playing is closed,
// and a song that silently does not play, or a station that silently does
// not start, reads as a broken button.
//
// Then the player and the tabs as one piece of glass, the player on top and
// the tabs under it, as Claude's box to type in holds its buttons: "Kan je
// nog 1x iets met glas proberen waarbij je het een soort inline boven de
// buttons zet? Net als zoals de box waar ik min of meer nu in typ in ios
// claude code?", and "Het moet er wel uitzien alsof het samen één object
// is he" (the photographer, 20 November 2026). The system's tab bar cannot
// share our glass, so it is hidden (MainTabView) and the tabs are ours
// (GlassTabFoot, TabRow). The glass is the system's by day and by night with a
// breath of the cover's colour, so the words follow the system too: dark by
// day, white by night, the station's line in the accent.
//
// The tabs' alone (the iPhone, a narrow iPad window). The wide window, the
// iPad's and the Mac's, has the player's bar across its foot instead, as
// Linux's (PlayerBar), so this is never there.

import JukeboxKit
import SwiftUI

#if os(iOS)
struct GlassMiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The block's colour as last worked out, with the cover it is from:
    /// kept while the next cover's loads, so the bar never flashes neutral
    /// between two songs.
    @State private var shown: (url: URL?, color: Color)?

    var body: some View {
        HStack(spacing: 0) {
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
            // The screenshot walk taps it by this (JukeboxUITests).
            .accessibilityIdentifier("mini-player")

            if let track = player.currentTrack, isStation {
                dislikeButton(track)
            } else {
                RoutePicker(followsAppearance: true)
                    .frame(width: 44, height: 44)
            }
            playPauseButton
        }
        .padding(.leading, Theme.Space.m)
        .padding(.trailing, Theme.Space.s)
        .frame(minHeight: 64)
        // The gaps between the buttons open Now Playing too.
        .contentShape(.rect)
        .onTapGesture {
            openNowPlaying()
        }
        // Past this size the two lines no longer fit the block.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: GlassTabFoot.radius - Theme.Space.xs,
                                                            style: .continuous))
        // The glass around it takes a breath of this (GlassTabFoot).
        .preference(key: GlassCoverTint.self, value: blockColor)
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
        // The cover's colour, once per cover (ImagePipeline keeps it), eased
        // from the last song's over half a second, as Now Playing's.
        .task(id: toneURL) {
            guard let url = toneURL else {
                setColor(nil, for: nil)
                return
            }
            let found = await ImagePipeline.shared.accent(for: url)
            guard !Task.isCancelled else { return }
            setColor(found, for: url)
        }
    }

    // MARK: Parts

    @ViewBuilder private var cover: some View {
        if player.currentTrack == nil, let station = startingStation {
            StationArtwork(station: station, size: 44, cornerRadius: Theme.Radius.artwork)
        } else {
            ArtworkView(player.currentTrack?.artwork, size: 44, cornerRadius: Theme.Radius.artwork,
                        sleeve: player.currentTrack.map(TitleSleeve.Words.init(track:)))
        }
    }

    @ViewBuilder private var titles: some View {
        Group {
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Space.xs) {
                        // The serif, as a title on a sleeve.
                        Text(track.name)
                            .font(.serif(.body))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        // Private Listening on (NotCountedViews): small, so
                        // a mode kept for days is not forgotten.
                        if player.notCounted.isPrivate {
                            Image(systemName: "eye.slash")
                                .font(.caption2)
                                .foregroundStyle(Self.quiet)
                                .accessibilityLabel("Private Listening is on")
                        }
                    }
                    if let shownError {
                        errorLine(shownError)
                    } else if let station = player.context?.station {
                        // B: the station after its mark, in the accent, so
                        // the listener knows it is the radio and that the
                        // thumb teaches it: Glow by night, Copper on the
                        // light glass by day.
                        HStack(spacing: Theme.Space.xs) {
                            ArchMark(size: 11, style: .template)
                            Text(station.title)
                                .font(.footnote)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.accent)
                    } else if !track.artistLine.isEmpty {
                        Text(track.artistLine)
                            .font(.footnote)
                            .foregroundStyle(Self.quiet)
                            .lineLimit(1)
                    }
                }
            } else if let station = startingStation {
                // A station chosen while nothing played: its first track is a
                // moment away.
                VStack(alignment: .leading, spacing: 1) {
                    Text(station.title)
                        .font(.serif(.body))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let shownError {
                        errorLine(shownError)
                    } else {
                        Text("Tuning in…")
                            .font(.footnote)
                            .foregroundStyle(Self.quiet)
                            .lineLimit(1)
                    }
                }
            } else {
                // Nothing plays: a station that found nothing to play ends
                // here, and says so under "Not Playing".
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not Playing")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Self.quiet)
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

    /// The error in the second line's place: as quiet as the artist, with
    /// the warning sign Now Playing's banner has, so it does not read as a
    /// name.
    private func errorLine(_ message: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
            Text(verbatim: message)
                .font(.footnote)
                .lineLimit(1)
        }
        .foregroundStyle(Self.quiet)
    }

    /// Less like this, as Now Playing's thumb (RadioController.dislike):
    /// skips the song and keeps it, and songs like it, off the station.
    /// Tapped again, taken back.
    private func dislikeButton(_ track: Track) -> some View {
        let disliked = radio.disliked.contains(track.id)
        return Button {
            radio.dislike(track)
        } label: {
            Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                .font(.title3)
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: disliked)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dislike")
        .accessibilityHint("Skips this song and plays less like it")
        .accessibilityAddTraits(disliked ? .isSelected : [])
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayPause()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(Color.primary.opacity(player.hasTrack ? 1 : 0.4))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    // MARK: The colour

    /// The artist, the error, "Tuning in…": the system's second grey, on
    /// glass that follows the system.
    static let quiet = Color.secondary

    /// The cover, small, for its colour: the 120 pixels Now Playing takes
    /// its accent from, so the bar, the record's label and Now Playing are
    /// one download and one colour.
    private var toneURL: URL? {
        guard let artwork = player.currentTrack?.artwork, let server = app.server else { return nil }
        return server.artworkURL(artwork, maxPixelSize: 120)
    }

    /// The colour shown: the one worked out last, or, on a tab that has not
    /// worked one out yet (each tab has its own bar), the one kept for this
    /// cover, so a new tab opens in the colour the last one had.
    private var blockColor: Color {
        if let shown { return shown.color }
        if let url = toneURL, case let .some(kept) = ImagePipeline.shared.cachedAccent(url) {
            return Self.block(from: kept)
        }
        return Theme.Arch.cabinet
    }

    private func setColor(_ accent: AccentColor?, for url: URL?) {
        // No cover at all: the brand's neutral. A cover still loading keeps
        // the last song's colour (the task waits on it).
        let color = url == nil ? Theme.Arch.cabinet : Self.block(from: accent)
        let first = shown == nil
        withAnimation(first || reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            shown = (url: url, color: color)
        }
    }

    /// The cover's colour, of which the glass takes a breath: Now Playing's accent (CoverAccent,
    /// the cover's colour a person would point at), darkened step by step,
    /// hue kept, until Glow on it is 4.5:1, the least for text. White, which
    /// is lighter than Glow, then has more: 8:1 or so, and white at 70% for
    /// the artist 4.8:1. The same colour on and off a station, so B's Glow
    /// line never changes the bar. A cover with no colour of its own (black
    /// and white, grey): Cabinet, the brand's own dark.
    static func block(from accent: AccentColor?) -> Color {
        guard var color = accent else { return Theme.Arch.cabinet }
        while color.contrast(with: .glow) < 4.5, color.luminance > 0.001 {
            color = AccentColor(red: color.red * 0.95, green: color.green * 0.95, blue: color.blue * 0.95)
        }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    // MARK: State

    private var isStation: Bool {
        player.context?.isRadio == true
    }

    /// The player's error while it keeps it, on the second line.
    private var shownError: String? {
        player.errorMessage
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

/// Where the song is: a line of 2 points between the player and the tabs,
/// the text's colour on itself at 15%. Apart from the player, as the clock
/// ticks twice a second and the rest changes only with the song. Not for VoiceOver: Now Playing has
/// the position, to be read and moved.
private struct GlassMiniPlayerProgress: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let duration = player.duration
        let part = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: proxy.size.width * part)
                }
            }
            .frame(height: 2)
            .clipShape(.capsule)
            .accessibilityHidden(true)
    }
}

/// The cover's colour, from the player up to the glass that holds it.
private struct GlassCoverTint: PreferenceKey {
    static var defaultValue: Color? { nil }
    static func reduce(value: inout Color?, nextValue: () -> Color?) {
        value = value ?? nextValue()
    }
}

/// Each tab's foot, on iOS 18 and 26 alike: one piece of glass floating
/// above the home indicator, the player on top (while something plays or
/// starts), the line of where the song is between, the tabs under it.
/// Nothing playing, the glass holds the tabs alone. Not iOS 26's bottom
/// accessory: its glass, its height and its layout are the system's, and the
/// two would be two objects. Tapped, the player opens Now Playing.
struct GlassTabFoot: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio

    /// The keyboard up (Search): the tabs go, as the system's bar went
    /// behind it, and the player alone rides on it. Watched by MiniBarFoot,
    /// which stays when this is gone (the keyboard up, nothing playing).
    let isKeyboardUp: Bool
    /// The cover's colour, from the player inside (GlassCoverTint).
    @State private var tint: Color?

    /// Round as iOS 26's own tab bar, which this stands in for.
    static let radius: CGFloat = 28
    private static let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

    private var showsPlayer: Bool {
        player.hasTrack || radio.isStarting || player.errorMessage != nil
    }

    var body: some View {
        if showsPlayer || !isKeyboardUp {
            object
        }
    }

    private var object: some View {
        VStack(spacing: 0) {
            if showsPlayer {
                GlassMiniPlayer()
                    .padding(.top, Theme.Space.xs)
                // Where the song is, between the player and the tabs, the
                // whole width inside the corners' round.
                GlassMiniPlayerProgress()
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, isKeyboardUp ? Theme.Space.m : 0)
            }
            if !isKeyboardUp {
                TabRow()
                    .padding(.vertical, Theme.Space.xs)
            }
        }
        .onPreferenceChange(GlassCoverTint.self) { tint = $0 }
        .background { ground }
        // The page's margin, so the glass lines up with what is above it.
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, Theme.Space.xs)
        .animation(.easeInOut(duration: 0.25), value: showsPlayer)
    }

    /// iOS 26: the system's regular glass, light by day and dark by night,
    /// with a breath of the cover's colour: more would darken the light
    /// glass under dark words. iOS 18: the system's material, the same
    /// breath over it, and a soft shadow to lift it off the page.
    @ViewBuilder private var ground: some View {
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.regular.tint(tint?.opacity(0.25)), in: Self.shape)
        } else {
            Self.shape
                .fill(.regularMaterial)
                .overlay(Self.shape.fill((tint ?? .clear).opacity(0.15)))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
    }
}
#endif
