// Now Playing: what plays, full screen and always dark. Sketch E's variant D,
// as the photographer chose it, 8 November 2026: "Dus ik denk dat d1 en d2
// vooral d2 het best gaan werken. D1 is reduced motion/batterij besparing d2
// normaal. F1 toch net iets te extreem denk".
//
// In the cover's place, the album's sleeve as printed card with its black
// record half out of it, the label in the cover's colour turning a turn in
// 10 s (SleeveRecord.swift) — "de hoes er achter zetten", and of the record
// player before it, "Het moet minder een los object zijn en meer verweven
// zitten met de pagina". So the page's ground is the record's world
// (NowPlayingGround.swift): normally sketch D2, "the side as land" — the
// album's side as a record far larger than the screen, its grooves crossing
// the page as a horizon, one band per song, the playing song's band
// starting under the sleeve and lighter where it has played, moving on one
// band when the song changes; and when nothing may move (Reduce Motion, Low
// Power Mode, Settings' Spin the Record off), sketch D1, "the wall" — two
// flat fields of the cover's own colours (CoverWall), a wall above the
// sleeve's foot and a floor below it, and nothing turns. A light wall gets
// dark glyphs at the top and a dark status bar.
//
// Then, from the margin, the title in the serif, the artist, and the station
// in the accent after its mark; the thumbs as plain glyphs beside the title;
// the slim scrubber; the transport; while a station plays its dial with its
// two ends in the place of the volume; and Lyrics, AirPlay and Up Next at
// the foot. Lyrics and the queue take the sleeve's place at a tap. A pull
// down anywhere on the page, or on the top over the lyrics and the queue,
// closes it.
//
// The controls stay white; the accent marks only what is the radio's or
// what is on: the progress, the thumbs up given, the station's name, the
// dial. It is a colour of the cover that plays (CoverAccent: its second
// colour, apart from its main one) — the photographer, 8 November 2026:
// "kan je de kleur uit de albumhoes pakken voor de steunkleur?" — at
// Glow's weight, so only its hue changes; Glow for a cover with no colour
// of its own. Given as the tint, which every
// part here draws its accent with (.tint), so a part never picks Glow by
// itself. Only here: the rest of the app keeps Copper and Glow, the brand.
//
// Gone with sketch D: the cover's colours blurred behind everything,
// "Playing From", the station as a spaced label in a capsule, round buttons.
// Gone with sketch E: the record player — its deck, plinth and arm.

import Combine
import JukeboxKit
import SwiftUI
import UIKit

/// What the big area shows: the sleeve and its record, or in their place
/// the lyrics or the queue, as Music swaps them.
enum NowPlayingPanel: Hashable {
    case cover
    case lyrics
    case queue
}

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var panel: NowPlayingPanel = .cover
    /// Low Power Mode, kept up to date by the system's notification.
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The iPad sideways (the page's `wide`), for what is decided outside
    /// the page's layout: the status bar.
    @State private var isWide = false
    /// The accent shown, and the cover it is of: nil until the first is
    /// worked out. Kept until the next one is, so a song change eases from
    /// the last cover's colour to this one's rather than flashing Glow
    /// between them.
    @State private var shownAccent: (url: URL, color: AccentColor?)?
    /// D1's wall and floor shown, and the cover they are of; kept as the
    /// accent is, so they ease from one cover's to the next.
    @State private var shownWalls: (url: URL, walls: NowPlayingWalls?)?
    /// How far the view has been pulled down to close it.
    @State private var dragOffset: CGFloat = 0
    /// True while a pull is held. SwiftUI resets it when the system cancels
    /// the pull (a call, Siri), which never reaches onEnded.
    @GestureState private var isPulling = false
    /// Counted, so each tap plays the glyph's bounce once.
    @State private var previousTaps = 0
    @State private var nextTaps = 0

    @ScaledMetric(relativeTo: .title) private var skipGlyph: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var playGlyph: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            // An iPad held sideways: the sleeve on the left, the rest on
            // the right, as Music lays it out. The iPhone is portrait.
            let wide = proxy.size.width > proxy.size.height && proxy.size.width >= 700
            VStack(spacing: 0) {
                header(wide: wide)
                if wide {
                    wideLayout
                } else {
                    tallLayout
                        .frame(maxWidth: 560)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transformPreference(NowPlayingAnchorsKey.self) { anchors in
                anchors.wide = wide
            }
            .onChange(of: wide, initial: true) { _, isNowWide in
                isWide = isNowWide
            }
        }
        // The ground, behind everything and to the screen's edges: D2's
        // land or D1's wall, and the sleeve with its record in the room the
        // page left it (NowPlayingGround). It is told where the sleeve's
        // room and the title are, as the page lays them out.
        .backgroundPreferenceValue(NowPlayingAnchorsKey.self) { anchors in
            GeometryReader { proxy in
                ground(anchors, in: proxy)
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            ZStack {
                errorBanner
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85),
                       value: player.errorMessage)
        }
        // A pull down closes it; over the lyrics and the queue only the top
        // does, so their own scrolling and reordering keep working.
        .contentShape(.rect)
        .gesture(dismissDrag, including: panel == .cover ? .all : .subviews)
        .offset(y: dragOffset)
        .accessibilityAction(.escape) {
            close()
        }
        // The cover's accent as the tint (see the top). Inside the dark
        // environment and before the sheet, which keeps the app's own.
        .tint(accentColor)
        .environment(\.colorScheme, .dark)
        // The cover's own presentation dark too, so the status bar, the
        // menus and the system's volume and AirPlay views are drawn for dark
        // even when the phone is in light mode. A presentation's preference:
        // the app under it keeps its own appearance. Over a light wall (D1)
        // light, so the status bar's time and battery are dark on it.
        .preferredColorScheme(wallIsLight ? ColorScheme.light : ColorScheme.dark)
        // The system says when Low Power Mode changes, on a thread of its
        // own; the state is changed on the main one.
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: player.errorMessage) { _, message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        // The accent, once per cover (ImagePipeline keeps it), and D1's
        // wall and floor with it (their floor keeps the accent readable),
        // eased in over half a second rather than switched: the song
        // changed, and the colours follow it. The first are set at once:
        // Now Playing opens in its colours.
        .task(id: accentURL) {
            guard let url = accentURL else {
                shownAccent = nil
                shownWalls = nil
                return
            }
            let found = await ImagePipeline.shared.accent(for: url)
            let walls = await NowPlayingWallCache.shared.walls(for: url, accent: found)
            // A newer cover has its own task; these colours are not its.
            guard !Task.isCancelled, shownAccent?.url != url else { return }
            let first = shownAccent == nil
            withAnimation(first || reduceMotion ? nil : .easeInOut(duration: 0.5)) {
                shownAccent = (url: url, color: found)
                shownWalls = (url: url, walls: walls)
            }
        }
        .onChange(of: isPulling) { _, pulling in
            // A cancelled pull would leave the view where the finger was.
            // Looked at after this update, when an onEnded that did run has
            // already closed the view or settled it.
            guard !pulling else { return }
            Task {
                guard dragOffset > 0, navigator.isNowPlayingPresented else { return }
                settle()
            }
        }
        // "Add to Playlist…" from the "…" menu, Up Next or History: the tab
        // view's sheet cannot show while this cover is over it, so the
        // sheet is presented from here (MainTabView holds its own back).
        .sheet(item: Binding(get: { navigator.addToPlaylist },
                             set: { navigator.addToPlaylist = $0 })) { request in
            AddToPlaylistSheet(tracks: request.tracks)
        }
        // Once each time it opens (Stats), not again when a sheet over it closes.
        .countsScreen("now_playing")
    }

    // MARK: Layouts

    private var tallLayout: some View {
        VStack(spacing: 0) {
            if panel == .cover {
                // Room enough under the sleeve for the playing song's band
                // to start between its foot and the title (LandGeometry's
                // 28 points above the title).
                sleeveRoom
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, Theme.Space.xxl + Theme.Space.s)
                    .transition(.opacity)
                titleRow
                    .padding(.horizontal, Theme.Space.xl)
                    .transition(.opacity)
            } else {
                compactHeader
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, Theme.Space.m)
                    .transition(.opacity)
                panelContent
                    .frame(maxHeight: .infinity)
            }
            controls
        }
    }

    private var wideLayout: some View {
        HStack(spacing: Theme.Space.xxl * 1.5) {
            Group {
                switch panel {
                case .cover:
                    sleeveRoom
                case .lyrics:
                    LyricsView()
                case .queue:
                    QueueView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                titleRow
                    .padding(.horizontal, Theme.Space.xl)
                controls
                Spacer(minLength: 0)
            }
            .frame(width: 440)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.vertical, Theme.Space.l)
    }

    @ViewBuilder private var panelContent: some View {
        switch panel {
        case .cover:
            EmptyView()
        case .lyrics:
            LyricsView()
                .transition(.opacity)
        case .queue:
            QueueView()
                .transition(.opacity)
        }
    }

    /// The sleeve's room: empty on the page, which tells the ground where it
    /// is. The ground draws the sleeve and its record in it (SleeveLayout),
    /// behind the page, so they stand on the land or the wall as the page's
    /// own ground rather than on a card of their own.
    private var sleeveRoom: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .anchorPreference(key: NowPlayingAnchorsKey.self, value: .bounds) { room in
                NowPlayingAnchors(sleeveRoom: room)
            }
            .accessibilityHidden(true)
    }

    /// The ground behind the page (NowPlayingGround), with where the page
    /// put the sleeve's room and the title, in the ground's own space.
    private func ground(_ anchors: NowPlayingAnchors, in proxy: GeometryProxy) -> some View {
        let side = albumSide
        let room: CGRect? = anchors.sleeveRoom.map { proxy[$0] }
        let titleFrame: CGRect? = anchors.title.map { proxy[$0] }
        return NowPlayingGround(size: proxy.size, sleeveRoom: room, title: titleFrame, wide: anchors.wide,
                                still: isStill, walls: walls, artwork: currentTrack?.artwork,
                                side: side ?? .alone, label: recordLabel(disc: side?.disc),
                                isPlaying: player.isPlaying)
    }

    /// Where the playing song lies on its album (TurntableSide): the songs
    /// of its disc, in disc and track order, from the library — the bands of
    /// the record and of the land. Nil when the song has no album, the
    /// library does not know the album, or the song is its disc's only one:
    /// then the song is alone on its side. Only the song is read here, not
    /// its clock: the land's played grooves read that themselves, so this
    /// view is not evaluated again twice a second.
    private var albumSide: TurntableSide? {
        guard let track = currentTrack, let albumID = track.albumID else { return nil }
        let songs = library.tracks(inAlbum: albumID).map {
            TurntableSong(id: $0.id, disc: $0.discNumber, length: $0.duration)
        }
        return TurntableSide.of(track.id, in: songs)
    }

    /// The words on the record's label: the album's title and its artist,
    /// and "Disc 2" when the album has discs. Nil, a plain label, when the
    /// song has neither album nor artist.
    private func recordLabel(disc: Int?) -> RecordLabel? {
        guard let track = currentTrack else { return nil }
        let title = track.albumName ?? ""
        let artist = track.albumArtist?.name ?? track.artistLine
        guard !title.isEmpty || !artist.isEmpty else { return nil }
        return RecordLabel(title: title, artist: artist, disc: disc)
    }

    // MARK: Top

    /// The grabber, Close and More. White, as every glyph here; Ink over a
    /// light wall (D1), as the status bar is then dark too.
    private func header(wide: Bool) -> some View {
        let ink = topInk(wide: wide)
        return VStack(spacing: Theme.Space.xs) {
            Capsule()
                .fill(ink.opacity(0.35))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack(spacing: Theme.Space.m) {
                Button {
                    close()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Spacer(minLength: 0)

                if let track = currentTrack {
                    Menu {
                        TrackMenu(track: track)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ink)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .padding(.top, Theme.Space.s)
        .padding(.horizontal, Theme.Space.m)
        .contentShape(.rect)
        .gesture(dismissDrag)
    }

    // MARK: The accent

    /// The cover, small, for its colour: the 120 pixels the record's label
    /// already takes its colour from (NowPlayingGround), so it is one
    /// download.
    private var accentURL: URL? {
        guard let artwork = currentTrack?.artwork, let client = app.client else { return nil }
        return client.imageURL(artwork, maxPixelSize: 120)
    }

    /// The accent shown: the last worked out (shownAccent), or before any
    /// is, one ImagePipeline kept for this cover. Glow for a cover without
    /// a colour of its own, a song without a cover, and until the first is
    /// known.
    private var accentColor: Color {
        let color: AccentColor?
        if let shownAccent {
            color = shownAccent.color
        } else if let url = accentURL, case let .some(kept) = ImagePipeline.shared.cachedAccent(url) {
            color = kept
        } else {
            color = nil
        }
        guard let color else { return Theme.Arch.glow }
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    // MARK: Still or moving

    /// D1, the wall, where nothing moves: the photographer's "D1 is reduced
    /// motion/batterij besparing d2 normaal". Reduce Motion asks for less
    /// movement; Low Power Mode for less work; Settings' Spin the Record
    /// off (AppSettings.spinRecord) for a record that stands still.
    private var isStill: Bool {
        reduceMotion || isLowPower || !settings.spinRecord
    }

    /// D1's wall and floor: the last worked out (shownWalls), or before any
    /// is, the ones kept for this cover. Nil — Cabinet, no wall — for a song
    /// without a cover, and until they are known.
    private var walls: NowPlayingWalls? {
        if let shownWalls {
            return shownWalls.walls
        }
        if let url = accentURL, case let .some(kept) = NowPlayingWallCache.shared.cached(url) {
            return kept
        }
        return nil
    }

    /// A light wall at the top of the screen: D1, the sleeve shown, upright
    /// (on the iPad sideways the status bar runs over the floor too, and
    /// the wall there is kept dark enough for white).
    private var wallIsLight: Bool {
        guard isStill, panel == .cover, currentTrack != nil, let walls else { return false }
        return walls.wall(wide: isWide).isLight
    }

    /// The top's glyphs: Ink over a light wall, else white.
    private func topInk(wide: Bool) -> Color {
        wallIsLight && !wide ? Theme.Arch.ink : Color.white
    }

    // MARK: The title

    /// From the margin, as a sleeve's back is set: the title in the serif,
    /// the artist, and where it plays from — the station in the accent
    /// after its mark, or the album, mix or playlist in grey.
    private var titleRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                title(.serif(.title))
                artistLine(.title3)
                source
                    .padding(.top, Theme.Space.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trackButtons
        }
        // Where the title is, for the land: the playing song's band starts
        // just above it.
        .anchorPreference(key: NowPlayingAnchorsKey.self, value: .bounds) { bounds in
            NowPlayingAnchors(title: bounds)
        }
        .padding(.bottom, Theme.Space.xs)
    }

    /// Over the lyrics and the queue: the cover small, the title beside it.
    private var compactHeader: some View {
        HStack(spacing: Theme.Space.m) {
            Button {
                show(.cover)
            } label: {
                ArtworkView(currentTrack?.artwork, size: 60)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Record")

            VStack(alignment: .leading, spacing: 2) {
                title(.serif(.title3))
                artistLine(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trackButtons
        }
        // The land's band starts above this title too, while it is the one.
        .anchorPreference(key: NowPlayingAnchorsKey.self, value: .bounds) { bounds in
            NowPlayingAnchors(title: bounds)
        }
    }

    @ViewBuilder private func title(_ font: Font) -> some View {
        if let track = currentTrack {
            Text(track.name)
                .font(font)
                .lineLimit(1)
        } else {
            Text("Not Playing")
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The artist's name, which goes to the artist when the library knows them.
    @ViewBuilder private func artistLine(_ font: Font) -> some View {
        if let track = currentTrack, !track.artistLine.isEmpty {
            if let found = libraryArtist(for: track) {
                Button {
                    navigator.open(.artist(found))
                } label: {
                    Text(track.artistLine)
                        .font(font)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the artist")
            } else {
                Text(track.artistLine)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Where it plays from. A station: its mark and its name in the
    /// accent, which go to the Radio tab, where its dial is. Anything else:
    /// its name in grey ("From Velvet Songs").
    @ViewBuilder private var source: some View {
        if let station = playingStation {
            Button {
                navigator.tab = .radio
                close()
            } label: {
                HStack(spacing: 6) {
                    ArchMark(size: 16, style: .template)
                    Text(station.title)
                        .lineLimit(1)
                }
                .foregroundStyle(.tint)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Station: \(station.title)")
            .accessibilityHint("Opens Radio")
        } else if let contextTitle {
            Text("From \(contextTitle)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// While a station plays, its thumbs, plain (RadioThumbs); otherwise the
    /// heart.
    @ViewBuilder private var trackButtons: some View {
        if let track = currentTrack {
            if playingStation != nil {
                RadioThumbs(track: track)
            } else {
                favoriteButton(track)
            }
        }
    }

    /// The heart, while no station plays (with one, a song is loved from
    /// the "…" menu, and the thumbs take its place). Loving a song while
    /// the radio plays still teaches it (radioStation): a song loved on a
    /// station is the clearest "more like this" the listener gives.
    private func favoriteButton(_ track: Track) -> some View {
        let favorite = library.isFavorite(track.id)
        return Button {
            let turningOn = !library.isFavorite(track.id)
            // like() toggles: a song already thumbed up would lose its thumb.
            if turningOn, radioStation != nil, !radio.liked.contains(track.id) {
                radio.like(track)
            }
            Task { await library.toggleFavorite(track.id) }
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(favorite ? AnyShapeStyle(.tint) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .symbolEffect(.bounce, value: favorite)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(favorite ? "Undo Favorite" : "Favorite")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            NowPlayingScrubber()
                .padding(.top, Theme.Space.l)
            transport
                .padding(.vertical, Theme.Space.s)
            if playingStation != nil {
                // The station's dial in the volume's place: the system
                // Slider with its two ends (RadioDial), as on the Radio tab.
                // The volume stays on the phone's own buttons.
                RadioDial()
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.m)
            } else {
                volume
            }
            bottomRow
                .padding(.top, Theme.Space.xs)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.bottom, Theme.Space.s)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button {
                previousTaps += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: skipSize))
                    .symbolEffect(.bounce, value: previousTaps)
            }
            .buttonStyle(NowPlayingTransportStyle(diameter: skipSize * 1.9))
            .accessibilityLabel("Previous")

            Spacer(minLength: 0)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playSize))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(NowPlayingTransportStyle(diameter: playSize * 1.7))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Spacer(minLength: 0)

            Button {
                nextTaps += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: skipSize))
                    .symbolEffect(.bounce, value: nextTaps)
            }
            .buttonStyle(NowPlayingTransportStyle(diameter: skipSize * 1.9))
            .accessibilityLabel("Next")
        }
        .padding(.horizontal, Theme.Space.l)
        .disabled(currentTrack == nil)
    }

    private var volume: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            NowPlayingVolumeSlider()
                .frame(height: 30)
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var bottomRow: some View {
        HStack {
            panelToggle(.lyrics, symbol: "quote.bubble", onSymbol: "quote.bubble.fill", label: "Lyrics")
            Spacer()
            NowPlayingAirPlayButton()
                .frame(width: 44, height: 44)
            Spacer()
            panelToggle(.queue, symbol: "list.bullet", onSymbol: "list.bullet", label: "Up Next")
        }
        .padding(.horizontal, Theme.Space.s)
    }

    /// Lyrics and Up Next take the record's place; a second tap gives it
    /// back. Plain glyphs: the one shown is white, the others grey.
    private func panelToggle(_ target: NowPlayingPanel, symbol: String, onSymbol: String,
                             label: LocalizedStringKey) -> some View {
        let isOn = panel == target
        return Button {
            show(isOn ? .cover : target)
        } label: {
            Image(systemName: isOn ? onSymbol : symbol)
                .font(.title3)
                .foregroundStyle(isOn ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(currentTrack == nil && !isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// "Could not play …", for the five seconds the player keeps it.
    @ViewBuilder private var errorBanner: some View {
        if let message = player.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.Space.s)
                .background(Color.black.opacity(0.7))
                .padding(.top, 64)
                .transition(bannerTransition)
        }
    }

    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    // MARK: Closing

    private var dismissDrag: some Gesture {
        // Global: the view moves under the finger, so its own coordinates
        // would move with it.
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .updating($isPulling) { _, pulling, _ in
                pulling = true
            }
            .onChanged { value in
                let down = value.translation.height
                if dragOffset == 0 {
                    // Down, and more down than sideways: a sideways swipe
                    // is not a close.
                    guard down > 0, down > abs(value.translation.width) else { return }
                }
                dragOffset = max(0, down)
            }
            .onEnded { value in
                if dragOffset > 0, value.translation.height > 140 || value.predictedEndTranslation.height > 480 {
                    close()
                } else {
                    settle()
                }
            }
    }

    private func close() {
        navigator.isNowPlayingPresented = false
    }

    /// Back up, for a pull that was not a close.
    private func settle() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.82)) {
            dragOffset = 0
        }
    }

    private func show(_ new: NowPlayingPanel) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)) {
            panel = new
        }
    }

    // MARK: State

    private var currentTrack: Track? {
        player.currentTrack
    }

    private var playingStation: Station? {
        player.context?.station
    }

    /// The radio's station, while it is what plays: the radio has one and
    /// the queue is its. Not while a new station is still being tuned in
    /// over the old one's last song, nor when the radio has stopped and the
    /// queue still carries a station's name: the thumb would teach nothing,
    /// or the wrong station.
    private var radioStation: Station? {
        guard let station = radio.station, player.context?.station?.id == station.id else { return nil }
        return station
    }

    private var contextTitle: String? {
        guard let title = player.context?.title, !title.isEmpty else { return nil }
        return title
    }

    private var skipSize: CGFloat {
        min(skipGlyph, 44)
    }

    private var playSize: CGFloat {
        min(playGlyph, 64)
    }

    private func libraryArtist(for track: Track) -> Artist? {
        guard let ref = track.primaryArtist else { return nil }
        return library.artist(ref)
    }
}
