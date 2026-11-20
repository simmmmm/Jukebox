// Glas, the player bar he chose of the three in the test build
// (MiniPlayer.swift), and the default.
//
// The player and the tabs as one piece of glass, the player on top and the
// tabs under it, as Claude's box to type in holds its buttons: "Kan je nog
// 1x iets met glas proberen waarbij je het een soort inline boven de
// buttons zet? Net als zoals de box waar ik min of meer nu in typ in ios
// claude code?", and "Het moet er wel uitzien alsof het samen één object
// is he" (the photographer, 20 November 2026). The system's tab bar cannot
// share our glass, so it is hidden (MainTabView) and the tabs are ours
// (GlassTabFoot, TabRow).
//
// Then, tried on his phone the same day, Glas it was, with notes:
//
//   - "De glas voelt nog niet helemaal apples design maar dat kunnen we
//     vast tweaken": so the system's own glass, untinted, in the shape and
//     at the place of iOS 26's tab bar, which it stands in for, and in it
//     the system's words: dark by day, white by night, what is chosen or on
//     air in the accent.
//   - The Plaat's soul, small: on the left a record, the cover as its
//     label, turning while it plays as Now Playing's label turns.
//   - "ik mis misschien ook nog vorige volgende knopjes": Next, at the
//     right of play and pause, as Apple Music's player above its tabs.
//     On a station the thumb keeps its place before them: on the radio it
//     is what the hand wants, and Next only skips, where the thumb also
//     teaches. Previous stays in Now Playing: a fourth button would leave
//     the title some 100 points, a word or two, and going back is rarer
//     than going on.
//
// A tap anywhere but the buttons opens Now Playing; a long press, the
// song's menu.
//
// The player's error ("Could not play …", a station that finds nothing)
// takes the second line for the five seconds the player keeps it: Now
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
struct GlassMiniPlayer: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator

    /// Taps on Next, for its bounce.
    @State private var nextTaps = 0

    var body: some View {
        HStack(spacing: 0) {
            Button {
                openNowPlaying()
            } label: {
                HStack(spacing: Theme.Space.m) {
                    GlassRecord()
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
                // In the words' colour, never white on the light glass: "het
                // icoontje wit is van AirPlay" (the photographer, 20
                // November 2026).
                RoutePicker(followsAppearance: true)
                    .frame(width: 44, height: 44)
            }
            playPauseButton
            nextButton
        }
        .frame(minHeight: GlassRecord.side)
        // The gaps between the buttons open Now Playing too.
        .contentShape(.rect)
        .onTapGesture {
            openNowPlaying()
        }
        // Past this size the two lines no longer fit the glass.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: GlassRecord.side / 2, style: .continuous))
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
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Private Listening is on")
                        }
                    }
                    if let shownError {
                        errorLine(shownError)
                    } else if let station = player.context?.station {
                        // The station after its mark, in the accent, so the
                        // listener knows it is the radio and that the thumb
                        // teaches it: Glow by night, Copper by day.
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
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // Nothing plays: a station that found nothing to play ends
                // here, and says so under "Not Playing".
                VStack(alignment: .leading, spacing: 1) {
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
        .foregroundStyle(.secondary)
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

    /// The next song, as Now Playing's Next (AudioPlayer.next): on a station
    /// the next it chose.
    private var nextButton: some View {
        Button {
            nextTaps += 1
            player.next()
        } label: {
            Image(systemName: "forward.fill")
                .font(.title3)
                .foregroundStyle(Color.primary.opacity(player.hasTrack ? 1 : 0.4))
                .symbolEffect(.bounce, value: nextTaps)
                .frame(width: 44, height: 44)
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

/// The record in the glass's corner, the Plaat's soul small: black vinyl,
/// the cover as its label (MiniPlayerCover: a station's or a mix's own
/// artwork for a song without one), the spindle's hole. While it plays the
/// label turns, a turn in 10 seconds as Now Playing's (RecordMotion), 20
/// frames a second and only the label redrawn; paused, and with Reduce
/// Motion, it stands. It picks up where it stopped, not where the clock is.
private struct GlassRecord: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let side: CGFloat = 44
    /// The cover on it, as on Plaat's (36 on 64).
    static let label: CGFloat = 24
    static let spindle: CGFloat = 5

    /// The label's angle when it last stopped, and since when it turns.
    @State private var turned: Double = 0
    @State private var since: Date?

    private var turns: Bool {
        player.isPlaying && !reduceMotion
    }

    var body: some View {
        ZStack {
            VinylDisc(diameter: Self.side, bands: [], label: nil, tone: nil)
                .drawingGroup()
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !turns)) { context in
                MiniPlayerCover(size: Self.label, cornerRadius: 0)
                    .clipShape(.circle)
                    .rotationEffect(.degrees(angle(at: context.date)))
            }
            .frame(width: Self.label, height: Self.label)
            Circle()
                .fill(VinylDisc.vinyl)
                .frame(width: Self.spindle, height: Self.spindle)
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
        .onAppear {
            if turns { since = .now }
        }
        .onChange(of: turns) { _, nowTurns in
            if nowTurns {
                since = .now
            } else {
                turned = angle(at: .now)
                since = nil
            }
        }
    }

    private func angle(at date: Date) -> Double {
        guard let since else { return turned }
        let degrees = turned + date.timeIntervalSince(since) * RecordMotion.labelDegreesPerSecond
        return degrees.truncatingRemainder(dividingBy: 360)
    }
}

/// Where the song is: a line of 2 points between the player and the tabs,
/// the words' colour on itself at 15%. Apart from the player, as the clock
/// ticks twice a second and the rest changes only with the song. Not for
/// VoiceOver: Now Playing has the position, to be read and moved.
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

/// Each tab's foot, on iOS 18 and 26 alike: one piece of glass where iOS
/// 26's tab bar would float, the player on top (while something plays or
/// starts), the line of where the song is between, the tabs under it.
/// Nothing playing, the glass holds the tabs alone, and is then the
/// system's tab bar to the eye. Not iOS 26's bottom accessory: its glass
/// is a second object above the bar's.
struct GlassTabFoot: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio

    /// The keyboard up (Search): the tabs go, as the system's bar went
    /// behind it, and the player alone rides on it. Watched by MiniBarFoot,
    /// which stays when this is gone (the keyboard up, nothing playing).
    let isKeyboardUp: Bool

    /// iOS 26's tab bar on the iPhone: 21 from the screen's sides (measured
    /// on the iPhone 17 Pro), and as far from its foot, round as the
    /// display's corners are; 62 tall, a capsule. The height and the foot
    /// are by eye from Apple's, not measured: to be checked on the phone.
    static let inset: CGFloat = 21
    static let tabsHeight: CGFloat = 62
    /// The glass's round: the tab bar's, whatever the glass holds, so with
    /// the player in it the corners are still the bar's.
    static let radius: CGFloat = tabsHeight / 2
    /// The record as far from the glass's top and left as makes it
    /// concentric with the corner: the glass's round less the record's.
    static let recordInset: CGFloat = radius - GlassRecord.side / 2
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
                    .padding(.leading, Self.recordInset)
                    .padding(.trailing, Theme.Space.xs)
                    .padding(.top, Self.recordInset)
                    .padding(.bottom, Theme.Space.s)
                // Where the song is, between the player and the tabs, the
                // whole width inside the corners' round.
                GlassMiniPlayerProgress()
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, isKeyboardUp ? Self.recordInset : 0)
            }
            if !isKeyboardUp {
                TabRow(onGlass: true)
            }
        }
        .modifier(GlassGround(shape: Self.shape))
        .padding(.horizontal, Self.inset)
        // Its foot as far from the screen's as its sides, into the home
        // indicator's room as the system's bar goes; on the keyboard, just
        // above it.
        .padding(.bottom, isKeyboardUp ? Theme.Space.s : max(0, Self.inset - Self.homeIndicator))
        .offset(y: isKeyboardUp ? 0 : max(0, Self.homeIndicator - Self.inset))
        .animation(.easeInOut(duration: 0.25), value: showsPlayer)
    }

    /// The room under the safe area at the screen's foot: 34 on an iPhone
    /// without a home button, none with one.
    private static var homeIndicator: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.keyWindow?.safeAreaInsets.bottom ?? 0
    }
}

/// iOS 26: the system's regular glass, interactive, with no tint of our
/// own, light by day and dark by night as the system's tab bar is; one
/// shape, so one object. iOS 18: the system's material and a soft shadow
/// to lift it off the page.
private struct GlassGround: ViewModifier {
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background {
                    shape
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
        }
    }
}
#endif
