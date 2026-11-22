// The mini player: what plays, in a block of the cover's colour just above
// Jukebox's own tabs, on the iPhone (and a narrow iPad window). Spotify's
// structure with Jukebox's soul.
//
// Of the three bars tried on the phone (Spotify, Glas, Plaat), Spotify's
// layout won, without the system's glass tab bar under it: "ja maar dan
// doen we niet het glas eronder dan krijg je zo twee dezelfde soort dingen
// dus bouw dit maar in de spotify versie en dan kunnen we die test items
// ook gewoon uit het menu halen" (the photographer, 21 November 2026). What
// was good in the other two came along:
//
//   - the block 8 in from the screen's edges, 8 pt corners, on the cover's
//     colour darkened until Glow on it reads (block(from:)): "meer zoals die
//     van spotify maar dan in de kleur van de albumhoes" (19 November 2026);
//   - on the left a small record, the cover as its label, turning while it
//     plays: Glas's and Plaat's record, "En de album art draait niet rond"
//     (20 November 2026, of Plaat's, before it did);
//   - the title in the serif, as on the sleeve (tells.md, 3), and under it
//     the artist, or on a station the arch and the station's name in Glow;
//   - on the right the heart, next and play or pause. The heart where
//     Dislike was: "ipv thumbs down het hartje" (20 November 2026). No
//     AirPlay: "eigenlijk mag van mij het airplay icoontje hier er uit"
//     (the same day); Now Playing has it;
//   - a line of 2 points in Glow along the block's foot for where the song
//     is, "WEL over de hele breedte" (19 November 2026);
//   - a swipe to the left the next song, to the right the one before:
//     "sowieso swipe naar links rechts voor vorige volgende" (20 November
//     2026).
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
// The tabs under it are Jukebox's own (TabRow) on a fade and a blur from
// the screen's foot; the system's tab bar is hidden (MainTabView).
//
// The tabs' alone. The wide window, the iPad's and the Mac's, has the
// player's bar across its foot instead, as Linux's (PlayerBar), so this is
// never there.

import JukeboxKit
import SwiftUI

#if os(iOS)
/// Each tab's foot: the block and the tabs, in the page's safe area, so a
/// page's last row scrolls clear of them.
struct MiniBarFoot: ViewModifier {
    /// The keyboard up (Search): the tabs go, as the system's bar went
    /// behind it, and the block alone rides on it.
    @State private var isKeyboardUp = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MiniPlayerTabFoot(isKeyboardUp: isKeyboardUp)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardUp = false
            }
    }
}

/// The block, and under it the tabs (TabRow), on no bar at all: the page's
/// own ground rises from the screen's foot and thins out well above the
/// block, with a blur that thins out with it, so pages scroll away soft
/// under the tabs. "ik wil is dat je vanuit onder een gradient naar boven
/// trekt die sterk genoeg is om ervoor te zorgen dat de icons altijd goed
/// zichtbaar blijven, misschien gepaard met een verloop background blur"
/// (the photographer, 19 November 2026), of a flat ground behind the tabs
/// that looked "onwijs google material". iOS 26's tab bar is the system's
/// glass and cannot be made flat; MainTabView hides it, the TabView stays
/// for each tab's stack. Not iOS 26's bottom accessory either: its glass,
/// its height and its layout are the system's, and the cover's colour
/// cannot tint it; the block's own glass can.
struct MiniPlayerTabFoot: View {
    let isKeyboardUp: Bool

    /// How far the fade reaches above the block.
    private static let reach: CGFloat = 72

    /// The fade, top to bottom, eased so no band shows where it starts:
    /// nothing above the block, whole by the tabs, so no page shows
    /// through under their names ("Lights Minors" did, 21 November 2026).
    private static func fade(_ color: Color) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(0), location: 0),
            .init(color: color.opacity(0.08), location: 0.12),
            .init(color: color.opacity(0.3), location: 0.25),
            .init(color: color.opacity(0.65), location: 0.38),
            .init(color: color.opacity(0.9), location: 0.5),
            .init(color: color.opacity(0.98), location: 0.6),
            .init(color: color, location: 0.7),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The fade's reach in the inset too, so a page's last row and
            // its footer scroll clear of the fade and the blur, not only of
            // the block: without it the inset ended at the block's top and
            // the last 72 points of every page stayed under the fade ("Je
            // houd niet genoeg ruimte onderaan dus ik kan steeds een deel
            // niet zien", 22 November 2026). The page runs on under it while
            // it scrolls, and it takes no taps.
            Color.clear
                .frame(height: Self.reach)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            MiniPlayer()
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
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}

struct MiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The block's colour as last worked out, with the cover it is from:
    /// kept while the next cover's loads, so the bar never flashes neutral
    /// between two songs.
    @State private var shown: (url: URL?, color: Color)?

    /// The row's width inside the block's padding, for whether next fits
    /// (showsNext).
    @State private var rowWidth: CGFloat = 0
    /// The words' way along a swipe, nil while the drag is none (it went
    /// up or down first). Gesture state, so a drag the system takes away
    /// (the long press's menu, the app leaving) lets go of it too, and the
    /// words spring back as they come home.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.7)))
    private var swipeAcross: CGFloat?
    /// A swipe under way, kept a moment past its end, so the tap the same
    /// finger makes on its way up opens nothing and presses nothing.
    @State private var isSwiping = false
    /// Counts the songs skipped by a swipe or by next, for the haptic and
    /// the glyph's bounce.
    @State private var skips = 0

    /// The block's corners: 8, as Spotify's and the sketch he chose. Not
    /// the concentric 14 that tells.md's rule would give a block holding
    /// art 8 in: on a bar this low that reads as a pill.
    static let radius: CGFloat = 8
    static let shape = RoundedRectangle(cornerRadius: radius)
    /// The block's height, and the record's inset: the record as far from
    /// the left edge as from the top and the foot.
    static let height: CGFloat = 58
    static let recordInset: CGFloat = (height - MiniPlayerRecord.side) / 2
    /// The glyphs' side, each: the heart, next, play or pause.
    static let glyph: CGFloat = 44
    /// The least the title keeps before next gives way. At 375 points (the
    /// iPhone SE, the 13 mini) the record and the three glyphs leave the
    /// words some 160, twenty letters of the serif at the default size; so
    /// next stays there, and goes only on a narrower window or past Large
    /// type, where the letters grow. Previous is the swipe's and Now
    /// Playing's, not a button.
    static let titleLeast: CGFloat = 120
    /// A swipe skips once the words have gone this far, or once a quick
    /// flick would carry them past `fling`: Apple Music's mini player asks
    /// about as much, a deliberate sideways stroke rather than a nudge.
    static let swipe: CGFloat = 56
    static let fling: CGFloat = 140
    /// The words follow the finger at this part of its way, and no further
    /// than `slide`: they lean the way the song goes, and come back.
    static let follow: CGFloat = 0.4
    static let slide: CGFloat = 36

    /// What the block stands on: the cover's colour, darkened. On iOS 26
    /// Liquid Glass tinted with it (the same darkened colour, so Glow and
    /// white keep their contrast), always the dark glass: by day the light
    /// glass would wash the colour out under white words. "Kan het niet
    /// gemaakt worden dan in glazen vorm?" (the photographer, of the flat
    /// block, 19 November 2026). On iOS 18 the flat colour. One glass on
    /// the screen: the tabs under it stand on the page's own ground.
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
                    MiniPlayerRecord()
                    titles
                        .offset(x: wordsOffset)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Self.glyph)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!player.hasTrack)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityHint("Opens Now Playing")
            // The swipe's two songs, for VoiceOver: in the actions rotor.
            .accessibilityAction(named: "Next") { skip(forward: true) }
            .accessibilityAction(named: "Previous") { skip(forward: false) }
            // The screenshot walk taps it by this (JukeboxUITests).
            .accessibilityIdentifier("mini-player")

            if let track = player.currentTrack {
                favoriteButton(track)
            }
            if showsNext {
                nextButton
            }
            playPauseButton
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
        }
        .padding(.leading, Self.recordInset)
        .padding(.trailing, Theme.Space.xs)
        .frame(minHeight: Self.height)
        .background { ground }
        .overlay {
            // The whole width, "WEL over de hele breedte": its ends cut by
            // the block's corners, the line itself, not the glass, clipped.
            MiniPlayerProgress()
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(Self.shape)
        }
        // The gaps between the buttons open Now Playing too.
        .contentShape(Self.shape)
        .onTapGesture {
            openNowPlaying()
        }
        // Beside the buttons' taps, not over them: a drag that goes up or
        // down is not a swipe, and the block has no scroll of its own to
        // fight.
        .simultaneousGesture(swipeGesture)
        .onChange(of: swipeAcross != nil) { _, swiping in
            if swiping {
                isSwiping = true
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    if swipeAcross == nil { isSwiping = false }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: skips)
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

    @ViewBuilder private var titles: some View {
        Group {
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Space.xs) {
                        // The serif, as the song's title in Now Playing and
                        // on its sleeve (tells.md, 3).
                        Text(track.name)
                            .font(.serif(.body))
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
                        // The station after its mark, in Glow, so the
                        // listener knows it is the radio and that the heart
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
                        .font(.serif(.body))
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
                        .font(.serif(.body))
                        .foregroundStyle(Self.quiet)
                        .lineLimit(1)
                    if let shownError {
                        errorLine(shownError)
                    }
                }
            }
        }
        // The error comes and goes, after five seconds, as a crossfade.
        .animation(.easeInOut(duration: Tokens.Motion.move), value: shownError)
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

    /// The heart, as Now Playing's: the song a favourite, filled in Glow
    /// when it is one (Glow, not the accent: the block is dark by day too).
    /// Loved on a station it teaches the station too (RadioController.like),
    /// the clearest "more like this" there is.
    private func favoriteButton(_ track: Track) -> some View {
        let favorite = library.isFavorite(track.id)
        return Button {
            guard !isSwiping else { return }
            let turningOn = !library.isFavorite(track.id)
            // like() toggles: a song already thumbed up would lose its thumb.
            if turningOn, isStation, !radio.liked.contains(track.id) {
                radio.like(track)
            }
            Task { await library.toggleFavorite(.track(track.id)) }
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(favorite ? Theme.Arch.glow : .white)
                .symbolEffect(.bounce, value: favorite)
                .frame(width: Self.glyph, height: Self.glyph)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(favorite ? "Undo Favorite" : "Favorite")
    }

    /// Next, when the title keeps its room (titleLeast); else the swipe
    /// alone has it.
    private var nextButton: some View {
        Button {
            guard !isSwiping else { return }
            skip(forward: true)
        } label: {
            Image(systemName: "forward.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: skips)
                .frame(width: Self.glyph, height: Self.glyph)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel("Next")
    }

    private var playPauseButton: some View {
        Button {
            guard !isSwiping else { return }
            player.togglePlayPause()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(player.hasTrack ? 1 : 0.4))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.glyph, height: Self.glyph)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    // MARK: The swipe

    /// What the words have left with next in the row: the row (measured
    /// inside the block's padding) less the record and its gap, and the
    /// three glyphs. Next gives way first; the heart and play stay.
    private var showsNext: Bool {
        guard dynamicTypeSize <= .large, rowWidth > 0 else { return false }
        let taken = MiniPlayerRecord.side + Theme.Space.m + 3 * Self.glyph
        return rowWidth - taken >= Self.titleLeast
    }

    /// The words lean with the finger, a part of its way and no further
    /// than `slide`, and spring back. With Reduce Motion they stay put;
    /// the song changing and the haptic say it.
    private var wordsOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return max(-Self.slide, min(Self.slide, (swipeAcross ?? 0) * Self.follow))
    }

    /// Sideways only: a drag counts once it has gone half again as far
    /// across as up or down, and from then on follows to its end.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .updating($swipeAcross) { value, across, _ in
                let width = value.translation.width
                if across == nil {
                    guard abs(width) > abs(value.translation.height) * 1.5 else { return }
                }
                across = width
            }
            .onEnded { value in
                let across = value.translation.width
                let sideways = isSwiping || abs(across) > abs(value.translation.height) * 1.5
                guard sideways, player.hasTrack else { return }
                let flung = value.predictedEndTranslation.width
                if across <= -Self.swipe || flung <= -Self.fling {
                    skip(forward: true)
                } else if across >= Self.swipe || flung >= Self.fling {
                    skip(forward: false)
                }
            }
    }

    /// The song after, or the one before: AudioPlayer.previous goes back to
    /// the song's start past its first three seconds, as Now Playing's
    /// button. On a station that is the same: the songs it played stay in
    /// its queue, so before is the last one heard.
    private func skip(forward: Bool) {
        guard player.hasTrack else { return }
        if forward { player.next() } else { player.previous() }
        skips += 1
    }

    // MARK: The colour

    /// The artist, the error, "Tuning in…": white at 70%. Explicit, not
    /// `.secondary`, which is a dark grey by day.
    static let quiet = Color.white.opacity(0.7)

    /// The cover, small, for its colour: the 120 pixels Now Playing takes
    /// its accent from, so the block, the record's label and Now Playing
    /// are one download and one colour.
    private var toneURL: URL? {
        guard let artwork = player.currentTrack?.artwork, let server = app.server else { return nil }
        return server.artworkURL(artwork, maxPixelSize: 120)
    }

    /// The colour shown: the one worked out last, or, on a tab that has not
    /// worked one out yet (each tab has its own block), the one kept for
    /// this cover, so a new tab opens in the colour the last one had.
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
        withAnimation(first || reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.scene)) {
            shown = (url: url, color: color)
        }
    }

    /// The cover's colour as the block: Now Playing's accent (CoverAccent,
    /// the cover's colour a person would point at), darkened step by step,
    /// hue kept, until Glow on it is 4.5:1, the least for text. White, which
    /// is lighter than Glow, then has more: 8:1 or so, and white at 70% for
    /// the artist 4.8:1. The same colour on and off a station, so the Glow
    /// line never changes the block. A cover with no colour of its own
    /// (black and white, grey): Cabinet, the brand's own dark. By day and by
    /// night the same: the cover's, not the system's.
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
        guard player.hasTrack, !isSwiping else { return }
        navigator.isNowPlayingPresented = true
    }
}

/// Where the song is: a line of 2 points along the block's foot, Glow on a
/// faint white track. Glow as the light of what plays, on a block dark
/// enough for Glow to read. Apart from the block, as the clock ticks twice a
/// second and the rest changes only with the song. Not for VoiceOver: Now
/// Playing has the position, to be read and moved.
private struct MiniPlayerProgress: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let duration = player.duration
        let part = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        Rectangle()
            .fill(.white.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Theme.Arch.glow)
                        .frame(width: proxy.size.width * part)
                }
            }
            .frame(height: 2)
            .accessibilityHidden(true)
    }
}

/// The record on the block's left, Now Playing's record small: black vinyl,
/// the cover as its label (MiniPlayerCover: a station's or a mix's own
/// artwork for a song without one), the spindle's hole. While it plays the
/// label turns (TurningMiniPlayerCover).
struct MiniPlayerRecord: View {
    static let side: CGFloat = 44
    /// The cover on it, in Now Playing's proportion (36 on 64 on the bar
    /// tried before).
    static let label: CGFloat = 24
    static let spindle: CGFloat = 5

    var body: some View {
        ZStack {
            VinylDisc(diameter: Self.side, bands: [], label: nil, tone: nil)
                .drawingGroup()
            TurningMiniPlayerCover(size: Self.label)
            Circle()
                .fill(VinylDisc.vinyl)
                .frame(width: Self.spindle, height: Self.spindle)
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }
}

/// The tabs, Jukebox's own: the symbol over its name, the tab shown in the
/// accent (Copper by day, Glow by night), the others quiet (secondary) on
/// the fade. Tapped again, Navigator.select: back to the tab's first page,
/// and on Search's first page into its field.
struct TabRow: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings

    private struct Item {
        let tab: AppTab
        let title: LocalizedStringKey
        let symbol: String
        /// The walk finds the tab by this (JukeboxUITests).
        let id: String
    }

    private var items: [Item] {
        [
            Item(tab: .home, title: "Home", symbol: "house.fill", id: "tab.home"),
            Item(tab: .radio, title: "Radio", symbol: "dot.radiowaves.left.and.right", id: "tab.radio"),
            Item(tab: .library, title: "Library", symbol: "square.stack.fill", id: "tab.library"),
            Item(tab: .search, title: "Search", symbol: "magnifyingglass", id: "tab.search"),
        ]
        .filter { MainTabView.shows($0.tab, settings: settings, navigator: navigator) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                button(item)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        // The two lines fit the row up to here, as the block's.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func button(_ item: Item) -> some View {
        let isShown = navigator.tab == item.tab
        return Button {
            navigator.select(item.tab)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.symbol)
                    .font(.title3)
                    // One height for the four symbols, so the names line up.
                    .frame(height: 26)
                Text(item.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isShown ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .accessibilityIdentifier(item.id)
    }
}

/// The cover as a record's label, turning while the song plays: a turn in
/// 10 seconds as Now Playing's (RecordMotion), 20 frames a second and only
/// the label redrawn, by one TimelineView that pauses while it stands;
/// paused, and with Reduce Motion, it stands. It picks up where it stopped,
/// not where the clock is. "En de album art draait niet rond" (the
/// photographer, 20 November 2026, of the record on a bar tried before).
struct TurningMiniPlayerCover: View {
    let size: CGFloat

    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The label's angle when it last stopped, and since when it turns.
    @State private var turned: Double = 0
    @State private var since: Date?

    private var turns: Bool {
        player.isPlaying && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / RecordMotion.labelFrameRate, paused: !turns)) { context in
            MiniPlayerCover(size: size, cornerRadius: 0)
                .clipShape(.circle)
                .rotationEffect(.degrees(angle(at: context.date)))
        }
        .frame(width: size, height: size)
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

/// The record's label. The song's own cover first; when it has none (no
/// artwork, or the server answered without one) and it plays from a station
/// or a mix, the artwork the app makes for that station or mix, as Home's
/// On air card and Played lately show it; else the album's title sleeve. At
/// 44 points a sleeve is its first letter, and that "S" was all the bar
/// showed of a station: "het zelfgemaakte album art niet zichtbaar" (the
/// photographer, 20 November 2026).
struct MiniPlayerCover: View {
    let size: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.artwork

    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(MixStore.self) private var mixes
    @Environment(\.displayScale) private var displayScale

    /// The url the server had no cover for, once asked.
    @State private var missingURL: URL?

    var body: some View {
        Group {
            if player.currentTrack == nil, radio.isStarting, let station = radio.station {
                // A station chosen while nothing played.
                StationArtwork(station: station, size: size, cornerRadius: cornerRadius)
            } else if hasNoCover, let station = player.context?.station {
                StationArtwork(station: station, size: size, cornerRadius: cornerRadius)
            } else if hasNoCover, let mix {
                CollageArtwork(artworks: mix.artwork, size: size, cornerRadius: cornerRadius)
            } else {
                ArtworkView(player.currentTrack?.artwork, size: size, cornerRadius: cornerRadius,
                            sleeve: player.currentTrack.map(TitleSleeve.Words.init(track:)))
            }
        }
        // The same download as ArtworkView's (ImagePipeline joins the two),
        // to learn whether the server has a cover at all.
        .task(id: url) {
            guard let url else { return }
            let image = await ImagePipeline.shared.image(for: url)
            guard !Task.isCancelled else { return }
            if image == nil, ImagePipeline.shared.isMissing(url) { missingURL = url }
        }
    }

    private var url: URL? {
        guard let artwork = player.currentTrack?.artwork, let server = app.server else { return nil }
        return server.artworkURL(artwork, maxPixelSize: ImagePipeline.bucket(Int(size * displayScale)))
    }

    private var hasNoCover: Bool {
        guard player.currentTrack != nil else { return false }
        guard let url else { return true }
        return missingURL == url || ImagePipeline.shared.isMissing(url)
    }

    private var mix: Mix? {
        guard case let .mix(id)? = player.context?.kind else { return nil }
        return mixes.mixes.first { $0.id == id }
    }
}
#endif
