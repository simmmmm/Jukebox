// Spotify, one of the three player bars in the test build (MiniPlayer.swift).
//
// The mini player: what plays, in a block of the cover's colour just above
// the tabs. The photographer, 19 November 2026: "Die mag van mij qua vorm
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
// Then glass, and the tabs under it Jukebox's own, on the page's ground fading up:
// "ik bedoelde ipv glas menu onderaan waar home radio library en search
// staat. kan je daar niet een lichte of donkere gradient van veel naar
// minder naar boven maken en dan de player van glas met de linker
// vierkantere versie en het play balkje eronder WEL over de hele breedte"
// (the photographer, 19 November 2026). So the block keeps the sketch's 8
// pt corners and 8 in from the edges, glass on iOS 26, and its line runs
// from corner to corner; the tabs are SpotifyTabFoot's.
//
// The tabs' alone (the iPhone, a narrow iPad window). The wide window, the
// iPad's and the Mac's, has the player's bar across its foot instead, as
// Linux's (PlayerBar), so this is never there.

import JukeboxKit
import SwiftUI

#if os(iOS)
struct SpotifyMiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The block's colour as last worked out, with the cover it is from:
    /// kept while the next cover's loads, so the bar never flashes neutral
    /// between two songs.
    @State private var shown: (url: URL?, color: Color)?

    /// The block's corners: 8, as the sketch he chose has them. Not the
    /// concentric 14 that tells.md's rule would give a block holding 6 pt
    /// art 8 in: on a bar this low that reads as a pill.
    static let radius: CGFloat = 8

    /// The sketch's 8 on glass too: "de linker vierkantere versie" (19
    /// November 2026), not the capsule there is no glass tab bar to echo.
    static let shape = RoundedRectangle(cornerRadius: radius)

    /// What the block stands on. On iOS 26 Liquid Glass tinted with the
    /// cover's colour (the same darkened colour as the flat block, so Glow
    /// and white keep their contrast), always the dark glass: by day the
    /// light glass would wash the colour out under white words. "Kan het
    /// niet gemaakt worden dan in glazen vorm?" (the photographer, of the
    /// flat block, 19 November 2026). On iOS 18 the flat colour.
    @ViewBuilder private var ground: some View {
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(.regular.tint(blockColor).interactive(), in: Self.shape)
                .environment(\.colorScheme, .dark)
        } else {
            Self.shape.fill(blockColor)
        }
    }

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
                RoutePicker()
                    .frame(width: 44, height: 44)
            }
            playPauseButton
        }
        // 9: the 40 pt cover as far from the left edge as from the top and
        // the foot of the 58 pt block.
        .padding(.leading, 9)
        .padding(.trailing, Theme.Space.xs)
        .frame(minHeight: 58)
        .background { ground }
        .overlay {
            // The whole width, "WEL over de hele breedte": its ends cut by
            // the block's corners, the line itself, not the glass, clipped.
            SpotifyMiniPlayerProgress()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(Self.shape)
        }
        // The gaps between the buttons open Now Playing too.
        .contentShape(Self.shape)
        .onTapGesture {
            openNowPlaying()
        }
        // Past this size the two lines no longer fit the block.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(.contextMenuPreview, Self.shape)
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
            StationArtwork(station: station, size: 40, cornerRadius: Theme.Radius.artwork)
        } else {
            ArtworkView(player.currentTrack?.artwork, size: 40, cornerRadius: Theme.Radius.artwork,
                        sleeve: player.currentTrack.map(TitleSleeve.Words.init(track:)))
        }
    }

    @ViewBuilder private var titles: some View {
        Group {
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Space.xs) {
                        Text(track.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
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
                        // B: the station after its mark, in Glow, so the
                        // listener knows it is the radio and that the thumb
                        // teaches it. Glow, not the accent: the block is
                        // dark by day too, where the accent is Copper.
                        HStack(spacing: Theme.Space.xs) {
                            ArchMark(size: 11, style: .template)
                            Text(station.title)
                                .font(.footnote)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.Arch.glow)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
                .foregroundStyle(.white.opacity(player.hasTrack ? 1 : 0.4))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    // MARK: The colour

    /// The artist, the error, "Tuning in…": white at 70%, as the sketch.
    /// Explicit, not `.secondary`, which is a dark grey by day.
    static let quiet = Color.white.opacity(0.7)

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

    /// The cover's colour as the block: Now Playing's accent (CoverAccent,
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

/// Where the song is: a line of 2 points along the block's foot, white on
/// white at 25%. Apart from the block, as the clock ticks twice a second and
/// the rest changes only with the song. Not for VoiceOver: Now Playing has
/// the position, to be read and moved.
private struct SpotifyMiniPlayerProgress: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let duration = player.duration
        let part = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        Rectangle()
            .fill(.white.opacity(0.25))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.white)
                        .frame(width: proxy.size.width * part)
                }
            }
            .frame(height: 2)
            .accessibilityHidden(true)
    }
}

/// Each tab's foot, on iOS 18 and 26 alike: the block, and under it the
/// tabs (TabRow), on no bar at all: the page's own ground rises from the
/// screen's foot and thins out well above the block, with a blur that thins
/// out with it, so pages scroll away soft under the tabs. "ik wil is dat je
/// vanuit onder een gradient naar boven trekt die sterk genoeg is om ervoor
/// te zorgen dat de icons altijd goed zichtbaar blijven, misschien gepaard
/// met een verloop background blur" (the photographer, 19 November 2026),
/// of a flat ground behind the tabs that looked "onwijs google material".
/// iOS 26's tab bar is the system's glass and cannot be made flat;
/// MainTabView hides it, the TabView stays for each tab's stack. Not iOS
/// 26's bottom accessory either: its glass, its height and its layout are
/// the system's, and the cover's colour cannot tint it; the block's own
/// glass can. Tapped, Now Playing.
struct SpotifyTabFoot: View {
    /// The keyboard up (Search): the tabs go, as the system's bar went
    /// behind it, and the block alone rides on it. Watched by MiniBarFoot.
    let isKeyboardUp: Bool

    /// How far the fade reaches above the block.
    private static let reach: CGFloat = 72

    /// The fade, top to bottom, eased so no band shows where it starts:
    /// nothing above the block, most of it by the tabs' symbols, so a
    /// white cover under them still leaves their names readable.
    private static func fade(_ color: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(0), location: 0),
            .init(color: color.opacity(0.05), location: 0.15),
            .init(color: color.opacity(0.18), location: 0.3),
            .init(color: color.opacity(0.42), location: 0.45),
            .init(color: color.opacity(0.72), location: 0.58),
            .init(color: color.opacity(0.9), location: 0.7),
            .init(color: color.opacity(0.96), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            SpotifyMiniPlayer()
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, Theme.Space.xs)
            if !isKeyboardUp {
                TabRow()
            }
        }
        .background {
            ZStack {
                // The blur, strongest at the foot, gone where the
                // ground's fade is.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(Self.fade(.black))
                Self.fade(Theme.ground)
            }
            .padding(.top, -Self.reach)
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}
#endif
