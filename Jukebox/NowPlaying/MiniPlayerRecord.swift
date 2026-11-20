// Plaat, one of the three player bars in the test build (MiniPlayer.swift).
//
// The mini player: what plays, as the page's last lines just above the tab
// bar, and its record on the tab bar's shoulder. Not a bar: no glass, no
// block, no capsule. The photographer, 19 November 2026, of the bars that
// were tried: "je mag het ook omdraaien maar dan moet je ff een manier
// vinden - ga los met het design dan - om te kijken hoe we die wel kunnen
// houden en het huidige nummer zonder glas/balkje". So the tab bar is the
// system's own (iOS 26's glass, iOS 18's bar), and of the sketches
// (build/minibar-compare/free-sketches) he chose B, the record on the
// shoulder: "ik vind die 2e versie best vet!"
//
//   - the title in the serif, as on the sleeve and in Now Playing, and under
//     it the artist, or the station after its mark in the accent;
//   - the heart, Play On and next, plain glyphs. The heart on a station too,
//     where the thumb was: "ipv thumbs down het hartje" (the photographer,
//     20 November 2026); the station's thumb is Now Playing's and the
//     song's menu's;
//   - at the right, over the tab bar's end, the record itself, the cover as
//     its label, turning while it plays: tapped, play or pause; around it a
//     ring in the accent for where the song is;
//   - under it all the page's own ground, a touch of the cover's colour in
//     it: "een lichtere achtergrond … van de albumcover bij dark mode en
//     donker bij light mode? of niet echt donker en licht maar een beetje
//     contrast" (the same day). Its top is the Arch, very wide and flat,
//     coming in soft, the page blurring under it: "kun je de gradient/blur zo
//     afronden?" with an arc drawn over the screen's foot, and "misschien
//     ietsje meer" (20 November 2026). So the words read over any cover
//     scrolling under them.
//
// A tap on the words opens Now Playing; a long press, the song's menu; a
// swipe to the left the next song, to the right the one before, as Apple
// Music's mini player: "sowieso swipe naar links rechts voor vorige
// volgende" (the photographer, 20 November 2026).
// Nothing playing, nothing is there: the page runs to the tab bar.
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
struct RecordMiniPlayer: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(LibraryStore.self) private var library

    /// The row's width, for whether next fits (showsNext).
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

    /// The cover's colour as last worked out, with the cover it is from:
    /// kept while the next cover's loads, so the ground never flashes
    /// between two songs. nil inside: a cover with no colour of its own.
    @State private var shown: (url: URL?, accent: AccentColor?)?

    /// The record's side, and the ring's around it: the ring is what a
    /// thumb hits, 72, all of it above the tab bar so it never takes a tap
    /// meant for Search. "misschien moet B iets hoger/groter om het
    /// aanraakvlak groot te houden" (the photographer, 19 November 2026).
    static let record: CGFloat = 64
    static let ring: CGFloat = 72
    /// The cover on the record, and the dot in its centre for the glyph.
    static let labelSide: CGFloat = 36
    static let spindle: CGFloat = 16
    /// How far the ground reaches above the row: room for the arch's
    /// crown and its soft edge, the wider blur clear of the top: the crown
    /// (RecordGroundArch) `crown` above the row, and 56 above that.
    static let lift: CGFloat = crown + 56
    /// The arch's crown above the row, and its fall to the screen's edges:
    /// low and flat, so it hugs the words and the record rather than rising
    /// in the middle. "Denk dat de ronding ook iets minder mag waardoor het
    /// rond de randen wat beter uitkomt waar de content staat en in het
    /// midden niet zo hoog wordt" (the photographer, 20 November 2026); it
    /// was 40 and 48, the edges then under the title's top.
    static let crown: CGFloat = 28
    static let fall: CGFloat = 22
    /// The arch's soft edge, its blur's radius.
    static let softness: CGFloat = 24
    /// The room a page's end needs above the row to come out from under the
    /// ground: the crown and the soft edge over it. In the bar's inset
    /// (RecordMiniPlayerBar), so every page scrolls its last row clear:
    /// "Hou ook rekening met de offset dat je onderaan ook kan zien" (the
    /// photographer, 20 November 2026, of Home's last shelf under it).
    static let clearance: CGFloat = crown + softness
    /// A swipe skips once the words have gone this far, or once a quick
    /// flick would carry them past `fling`: Apple Music's mini player asks
    /// about as much, a deliberate sideways stroke rather than a nudge.
    static let swipe: CGFloat = 56
    static let fling: CGFloat = 140
    /// The words follow the finger at this part of its way, and no further
    /// than `slide`: they lean the way the song goes, and come back.
    static let follow: CGFloat = 0.4
    static let slide: CGFloat = 36
    /// The glyphs' side, each: the heart, AirPlay, next.
    static let glyph: CGFloat = 44
    /// The least the title keeps before next gives way. At 375 points (the
    /// iPhone SE, the 13 mini) the heart, AirPlay and the record leave the
    /// words 167; next takes 44 of it, leaving 123, some fifteen letters of
    /// the serif at the default size: still a title. Previous too would
    /// leave 79, a word and a half, so previous is the swipe's and the
    /// song's own, not a button (Now Playing has it). Past Large type next
    /// goes as well: the letters grow and the 123 would hold eight or nine.
    static let titleLeast: CGFloat = 120
    /// The tint at its fullest, over the material: the page always a little
    /// seen through it, "altijd net een beetje doorheen" (20 November 2026).
    static let fullest: Double = 0.85

    var body: some View {
        HStack(spacing: 0) {
            Button {
                openNowPlaying()
            } label: {
                titles
                    .offset(x: wordsOffset)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
            // The words' colour, dark by day and white by night, on the
            // page's own ground: "het icoontje wit is van AirPlay" (the
            // photographer, 20 November 2026), white on paper by day.
            RoutePicker(followsAppearance: true)
                .frame(width: Self.glyph, height: Self.glyph)
            if showsNext {
                nextButton
            }
            recordButton
                .padding(.leading, Theme.Space.s)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
        }
        .padding(.leading, Theme.margin)
        // The ring's right edge on the tab bar's, 20 from the screen's.
        .padding(.trailing, Theme.margin)
        // The ring is the row's height; a little air above and below it.
        .padding(.vertical, Theme.Space.xs)
        // Past this size the two lines crowd the page more than they tell.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.Radius.artwork + Theme.Space.s))
        .contextMenu {
            if let track = player.currentTrack {
                TrackMenu(track: track)
            }
        }
        // Beside the buttons' taps, not over them: a drag that goes up or
        // down is not a swipe, and the bar has no scroll of its own to
        // fight; the tab bar under it is the system's, apart.
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
        .background { ground }
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
                setAccent(nil, for: nil)
                return
            }
            let found = await ImagePipeline.shared.accent(for: url)
            guard !Task.isCancelled else { return }
            setAccent(found, for: url)
        }
    }

    // MARK: Parts

    /// The page's ground with a touch of the cover in it, under the words
    /// and the record and on down behind the tab bar, never quite opaque:
    /// the page shows through it, blurred, everywhere. Its top is an arch (the
    /// brand's own shape, here as wide as the screen and more), soft over
    /// some 48 to 56 points, so the page turns into the song's ground
    /// rather than a bar beginning. It takes no taps: the rows under its edge stay the
    /// page's.
    private var ground: some View {
        ZStack {
            // Under the tint the page blurs, so what scrolls in under the
            // arch melts away rather than being cut: an opaque arch sliced
            // the shelves' words mid-letter, and read as a fault.
            // A thin material, not the ultra thin: "B met een iets zachtere
            // gradiënt en background blur" (the photographer, 20 November
            // 2026), the page under it more blurred than seen.
            Rectangle()
                .fill(.thinMaterial)
            // The tint barely there near the arch and at its fullest from
            // the row down, so the words and the record keep their
            // contrast; never whole, so the page is always just seen
            // through it: "Met zachter bedoel ik dat je er altijd net een
            // beetje doorheen kan kijken" (the photographer, 20 November
            // 2026).
            Rectangle()
                .fill(tint.opacity(Self.fullest))
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.25), .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.lift)
                        Color.black
                    }
                }
        }
        // The arch, coming in over some 48 to 56 points along its curve.
        // Drawn past the ground's own edges, so its blur fades only along
        // the arch and never at the sides or the foot.
        .mask {
            RecordGroundArch(crown: Self.lift - Self.crown, fall: Self.fall)
                .fill(.black)
                .padding(-RecordGroundArch.overhang)
                .blur(radius: Self.softness)
        }
        .padding(.top, -Self.lift)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    /// The record, still, the cover as its label and play or pause on it;
    /// the ring round it fills with the song. A station starting has its
    /// arch on the label, which means a station.
    private var recordButton: some View {
        Button {
            guard !isSwiping else { return }
            player.togglePlayPause()
        } label: {
            ZStack {
                RecordMiniPlayerRing()
                VinylDisc(diameter: Self.record, bands: [], label: nil, tone: nil)
                    .drawingGroup()
                recordLabel
                    .frame(width: Self.labelSide, height: Self.labelSide)
                    .clipShape(.circle)
                // The glyph small in the label's centre, where the spindle
                // hole is, on a dot of the vinyl's black: the cover stays
                // seen round it.
                Circle()
                    .fill(.black.opacity(0.72))
                    .frame(width: Self.spindle, height: Self.spindle)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(player.hasTrack ? 1 : 0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: Self.ring, height: Self.ring)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
    }

    @ViewBuilder private var recordLabel: some View {
        // The station's or the mix's own artwork for a song without a cover
        // (MiniPlayerCover), turning with the song; the ring and its
        // hairline stand.
        TurningMiniPlayerCover(size: Self.labelSide)
    }

    @ViewBuilder private var titles: some View {
        Group {
            if let track = player.currentTrack {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Theme.Space.xs) {
                        // The serif, as the song's title in Now Playing and
                        // on its sleeve (tells.md, 3).
                        Text(track.name)
                            .font(.serif(.body))
                            .foregroundStyle(.primary)
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
                    } else if let station = player.context?.station {
                        // The station after its mark, in the accent (Glow by
                        // night, Copper by day, where Glow could not be
                        // read), so the listener knows it is the radio and
                        // that the heart teaches it.
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
                VStack(alignment: .leading, spacing: 0) {
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
                VStack(alignment: .leading, spacing: 0) {
                    Text("Not Playing")
                        .font(.serif(.body))
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

    /// The heart, as Now Playing's: the song a favourite, filled in the
    /// accent when it is one. Loved on a station it teaches the station too
    /// (RadioController.like), the clearest "more like this" there is.
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
                .foregroundStyle(favorite ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
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
                .foregroundStyle(.primary)
                .symbolEffect(.bounce, value: skips)
                .frame(width: Self.glyph, height: Self.glyph)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!player.hasTrack)
        .accessibilityLabel("Next")
    }

    // MARK: The swipe

    /// What the words have left with next in the row: the row (measured
    /// inside the margins) less the record and its gap, and the three
    /// glyphs.
    private var showsNext: Bool {
        guard dynamicTypeSize <= .large, rowWidth > 0 else { return false }
        let taken = Self.ring + Theme.Space.s + 3 * Self.glyph
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

    // MARK: The ground's colour

    /// The cover, small, for its colour: the 120 pixels Now Playing takes
    /// its accent from, so the ground, the record's label and Now Playing
    /// are one download and one colour.
    private var toneURL: URL? {
        guard let artwork = player.currentTrack?.artwork, let server = app.server else { return nil }
        return server.artworkURL(artwork, maxPixelSize: 120)
    }

    /// The cover's accent shown: the one worked out last, or, on a tab that
    /// has not worked one out yet (each tab has its own), the one kept for
    /// this cover, so a new tab opens in the colour the last one had.
    private var accent: AccentColor? {
        if let shown { return shown.accent }
        if let url = toneURL, case let .some(kept) = ImagePipeline.shared.cachedAccent(url) {
            return kept
        }
        return nil
    }

    private var tint: Color {
        let ground = Self.ground(for: accent, dark: colorScheme == .dark)
        return Color(red: ground.red, green: ground.green, blue: ground.blue)
    }

    private func setAccent(_ found: AccentColor?, for url: URL?) {
        let first = shown == nil
        withAnimation(first || reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            shown = (url: url, accent: found)
        }
    }

    // The page's grounds and the words that must read on the song's.
    private static let night = AccentColor(red: 0x12 / 255, green: 0x11 / 255, blue: 0x10 / 255)
    private static let paper = AccentColor(red: 0xF6 / 255, green: 0xF3 / 255, blue: 0xEE / 255)
    private static let copper = AccentColor(red: 0xA8 / 255, green: 0x4A / 255, blue: 0x17 / 255)
    private static let white = AccentColor(red: 1, green: 1, blue: 1)
    /// Theme.raised: the ground one step up, for a cover with no colour.
    private static let raisedNight = AccentColor(red: 0x1B / 255, green: 0x19 / 255, blue: 0x18 / 255)
    private static let raisedPaper = AccentColor(red: 0xEC / 255, green: 0xE7 / 255, blue: 0xDF / 255)

    /// The song's ground: the page's, a step towards the cover. By night a
    /// little lighter than Night, the cover lifted towards white first so a
    /// dark cover lifts too; by day a little darker than Paper, the cover
    /// darkened first so a pale one still shows. Just enough to set the
    /// song apart, never so much that the words lose: by night white
    /// stays 12:1 and Glow 7:1 or more, by day Copper 5:1 or more, WCAG's
    /// 4.5 for text with room for the page that shows through the tint
    /// (`fullest`). A cover with no colour of its own: the raised
    /// ground, the brand's step up.
    static func ground(for accent: AccentColor?, dark: Bool) -> AccentColor {
        guard let accent else { return dark ? raisedNight : raisedPaper }
        let page = dark ? night : paper
        let toward = dark ? mix(accent, white, 0.25) : mix(accent, AccentColor(red: 0, green: 0, blue: 0), 0.3)
        var amount = dark ? 0.2 : 0.14
        var ground = mix(page, toward, amount)
        while amount > 0.02, !reads(on: ground, dark: dark) {
            amount -= 0.02
            ground = mix(page, toward, amount)
        }
        return ground
    }

    private static func reads(on ground: AccentColor, dark: Bool) -> Bool {
        dark ? ground.contrast(with: white) >= 12 && ground.contrast(with: .glow) >= 7
            : ground.contrast(with: copper) >= 5
    }

    private static func mix(_ a: AccentColor, _ b: AccentColor, _ t: Double) -> AccentColor {
        AccentColor(red: a.red + (b.red - a.red) * t, green: a.green + (b.green - a.green) * t,
                    blue: a.blue + (b.blue - a.blue) * t)
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

/// The ground's arched top: a flat parabola, its crown 56 below the top
/// of the ground (RecordMiniPlayer.crown, 28, above the row) in the
/// middle, falling `fall`, 22, to either edge of the screen, so it comes
/// down near the title and the record and runs on past both edges. Drawn
/// in a frame `overhang` larger on every side than the ground, so the blur
/// that softens it has shape to blur beyond the ground's edges.
private struct RecordGroundArch: Shape {
    static let overhang: CGFloat = 64

    /// The crown below the ground's top, and the fall to the edges: handed
    /// in from RecordMiniPlayer's measures, as a Shape draws off the main
    /// actor.
    let crown: CGFloat
    let fall: CGFloat

    func path(in rect: CGRect) -> Path {
        let ground = rect.insetBy(dx: Self.overhang, dy: Self.overhang)
        let middle = ground.midX
        let half = max(ground.width / 2, 1)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX {
            let t = (x - middle) / half
            path.addLine(to: CGPoint(x: x, y: ground.minY + crown + fall * t * t))
            x += 4
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Where the song is: a ring round the record, a hairline filling in the
/// accent from the top, clockwise. Apart from the rest, as the clock ticks
/// twice a second and the rest changes only with the song. Not for
/// VoiceOver: Now Playing has the position, to be read and moved.
private struct RecordMiniPlayerRing: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let duration = player.duration
        let part = duration > 0 ? min(1, max(0, player.elapsed / duration)) : 0
        ZStack {
            Circle()
                .inset(by: 1)
                // Stronger than a hairline: by night on a tinted ground the
                // system's separator all but vanished.
                .stroke(Color.primary.opacity(0.22), lineWidth: 1)
            Circle()
                .inset(by: 1)
                .trim(from: 0, to: part)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// The song at each tab's foot, just above the tab bar, on iOS 18 and 26
/// alike: in the page's safe area, so nothing of the page is under it.
/// Not iOS 26's bottom accessory: that is the glass capsule he did not want.
/// The inset itself, and its ease in and out, are MiniBarFoot's.
struct RecordMiniPlayerBar: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio

    /// Something to show: a song, a station being started, or the error of
    /// one that would not play. Else the page runs to the tab bar.
    static func isShown(player: AudioPlayer, radio: RadioController) -> Bool {
        player.hasTrack || player.currentTrack != nil || radio.isStarting || player.errorMessage != nil
    }

    var body: some View {
        if Self.isShown(player: player, radio: radio) {
            VStack(spacing: 0) {
                // Room in the inset for the arch over the row, so a page's
                // last row scrolls clear of it; the page still runs on under
                // it while it scrolls, and the room takes no taps.
                Color.clear
                    .frame(height: RecordMiniPlayer.clearance)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                RecordMiniPlayer()
            }
            .transition(.opacity)
        }
    }
}
#endif
