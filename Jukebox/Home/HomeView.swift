// Home: the two things the photographer asked for most, first — "op de
// homepage wil ik dat de app zelf leuke playlists verzint en of een goede
// radio functie heeft" (8 November 2026). Their own station on top, one tap
// from playing; the mixes Jukebox made up today; then, as Feishin's Home and
// Music's have them ("Ik vind feishin een fijne desktop app op Linux voor
// context"), what they played lately and when, what they play most, albums
// to explore today, and what is new. Explore needs no history, so Home is
// full on day one too.
//
// Sketch D, approved the same day — "Ja nice
// dit, maak dit maar dan refinen we later wel": the title in the serif, by
// the hour ("Tonight"); Your Station as a flat arch beside its name, one
// fact and the one Play, on the ground rather than on a card; the mixes'
// collages peeking off the right edge with their artists under them;
// Played lately as a list on hairlines, each with when it played.

import JukeboxKit
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @Environment(RadioController.self) private var radio
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isWide) private var isWide

    @State private var isShowingSettings = false

    init() {}

    var body: some View {
        // A ZStack, not a Group: a Group hands its modifiers to whichever
        // branch shows, so Settings, opened during the first load, would
        // close and open again (losing what was typed) when the load ends.
        ZStack {
            if library.tracks.isEmpty {
                HomeLibraryStatus()
            } else {
                HomeFeed()
            }
        }
        .background(Theme.ground)
        // What part of the day it is, in the serif (Theme.styleNavigationBars):
        // sketch D's "Tonight" in the evening. The tab is still Home. On a
        // wide page the title is the page's own (WidePage), and the bar's
        // once that has scrolled away.
        .homeTitle(RelativeDay.partOfDay())
        .toolbar {
            // A wide window's Settings are in the sidebar's menu, as on
            // Linux, and the Mac's behind ⌘,.
            if !isWide {
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "person.crop.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        // When Home appears, and again whenever the library has loaded:
        // the first build may have found nothing to make mixes from.
        .task(id: library.lastLoaded) {
            await mixes.rebuildIfStale(library: library, history: history, settings: settings)
        }
        // Your Station's fact is the hour's: worked out again as Home shows.
        .onAppear { radio.refreshYourStationFact() }
        // Back from the background the next morning: today's mixes.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await mixes.rebuildIfStale(library: library, history: history, settings: settings) }
        }
    }
}

/// Home with music: each section its own view, so a change in one (the
/// station that plays, a play count) redraws only that one.
private struct HomeFeed: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @Environment(HandoffStore.self) private var handoff
    @Environment(\.isWide) private var isWide

    init() {}

    var body: some View {
        Group {
            if isWide {
                // As Linux's: the part of the day 24 under the bar, as every
                // wide page's title, and Your Station 32 under it, not a
                // section's 40 (spec §5).
                WidePage(title: RelativeDay.partOfDay()) { page, _ in
                    PageTitle(RelativeDay.partOfDay())
                        .padding(.horizontal, page.side)
                    sections(HomeMeasures(page: page))
                        .padding(.top, Theme.Space.xxl)
                }
            } else {
                ScrollView {
                    sections(HomeMeasures(page: nil))
                        .padding(.top, Theme.Space.s)
                        .padding(.bottom, Theme.Space.xxl)
                }
            }
        }
        .refreshable {
            await library.refresh()
            await mixes.rebuild(library: library, history: history, settings: settings)
        }
    }

    private func sections(_ measures: HomeMeasures) -> some View {
        VStack(alignment: .leading, spacing: measures.betweenSections) {
            HomeOfflineNotice(margin: measures.margin)
            if measures.pairsHomeCards, handoff.offer != nil {
                // Side by side where the page has room, each as tall as
                // the other: "kunnen die twee tegels ook op dezelfde rij
                // naast elkaar" (the photographer, 18 November 2026).
                // Linux's HomePage.appendCards.
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    HomeHandoffNotice(margin: 0, isPaired: true)
                    HomeStationHero(measures: measures, isPaired: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, measures.margin)
            } else {
                HomeHandoffNotice(margin: measures.margin)
                HomeStationHero(measures: measures)
                    .padding(.horizontal, measures.margin)
            }
            // Its own ground parts it from the mixes, on every client.
            HomeMixesSection(measures: measures)
            HomePlayedLatelySection(measures: measures)
            HomeMostPlayedSection(measures: measures)
            HomeExploreSection(measures: measures)
            HomeRecentlyAddedSection(measures: measures)
        }
    }
}

/// What a card of Home's does, at its foot: a word in the accent with a
/// small glyph, no ground of its own, for the whole card is the button.
/// The photographer, 18 November 2026: "ik denk dat je die button weg moet
/// halen en de spacing van eerder moet laten staan, en dan er een soort
/// link button van maken en het hele ding gewoon klikbaar maken".
struct HomeCardLink: View {
    let title: String
    let systemImage: String
    var isTrailing = false
    var isWorking = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if !isTrailing { glyph }
            Text(title)
            if isTrailing { glyph }
        }
        .desktopFont(15, phone: .subheadline)
        .foregroundStyle(Theme.accent)
    }

    @ViewBuilder
    private var glyph: some View {
        if isWorking {
            ProgressView()
                .controlSize(.mini)
                .tint(Theme.accent)
        } else {
            // The word says it; VoiceOver need not read "play" twice.
            Image(systemName: systemImage)
                .imageScale(.small)
                .accessibilityHidden(true)
        }
    }
}

/// A card of Home's pressed: the whole of it dims a little.
struct HomeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A record peeking out from behind a card's art, as Now Playing's slides
/// out of its sleeve: the same drawing (VinylDisc), small and still, its
/// label Copper. "met misschien een kleine 'plaat' graphic" (the
/// photographer, 18 November 2026). Linux's Draw.cardRecord.
struct HomeCardRecord<Art: View>: View {
    let side: CGFloat
    @ViewBuilder let art: Art

    /// How much of the record shows beside the art, of its side.
    static var peek: CGFloat { 0.14 }

    var body: some View {
        ZStack(alignment: .leading) {
            VinylDisc(diameter: side * 0.92, bands: [], label: nil,
                      tone: AverageColor(red: 0xA8 / 255, green: 0x4A / 255, blue: 0x17 / 255))
                .drawingGroup()
                .offset(x: side * (1 + Self.peek - 0.92))
                .accessibilityHidden(true)
            art
        }
        .frame(width: side * (1 + Self.peek), height: side, alignment: .leading)
    }
}

extension View {
    /// Your Station and the music to go on with, each on a ground one step
    /// up from the page (Theme.raised), flat, with no line or shadow, its
    /// corners concentric with the art's 6 at 12 in. The photographer, 18
    /// November 2026: "kan je van 'doorgaan waar je was' iets beter
    /// afkaderen, hoeft niet extreem, hetzelfde geldt voor your station;
    /// beide staan zo in het niets met deze opmaak". Linux's home-card.
    func homeCard(_ ground: Color = Theme.raised) -> some View {
        // The words' side gets as much air as the words have above and
        // below: "Geef ze beide ff wat meer padding aan de rechterkant,
        // zodat het meer in balans is met boven en onder" (the photographer,
        // 18 November 2026).
        padding(Theme.Space.m)
            .padding(.trailing, Theme.Space.xl)
            .background(ground, in: .rect(cornerRadius: Theme.Radius.artwork + Theme.Space.m))
    }

    /// A card's content, inside its ground: in the row of two
    /// (`isPaired`), DesktopMeasures.homeCard wide and as tall as the row,
    /// in the middle of it; else as wide as its words, at most heroWidth,
    /// and on a wide page no wider (Linux's).
    @ViewBuilder
    func homeCardFrame(isPaired: Bool, isWide: Bool) -> some View {
        if isPaired {
            frame(width: CGFloat(DesktopMeasures.homeCard) - 2 * Theme.Space.m - Theme.Space.xl, alignment: .leading)
                .frame(maxHeight: .infinity)
        } else {
            frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
                .fixedSize(horizontal: isWide, vertical: false)
        }
    }
}

enum HomeLayout {
    /// The widest Your Station gets: on the iPad, and an iPhone on its side,
    /// the art and its words across the whole screen would leave the Play
    /// half a screen from the name.
    static let heroWidth: CGFloat = 560
    /// Your Station's arch, beside its name.
    static let heroArt: CGFloat = 132
    /// A shelf's tile: two and a part of the third on an iPhone, so the
    /// shelf is seen to go on.
    static let tileWidth: CGFloat = 136
}

// MARK: - The server out of reach

/// The library from last time, while the server does not answer or there is
/// no network: said once, small, above the music, with a way to try again.
/// With songs on the phone it says those still play (OfflineStore): offline,
/// only they do. Only when there is a library on screen; without one
/// HomeLibraryStatus says it full size.
/// Music on another device, or this one's from last time, and the one
/// thing to do about it: go on with it here (HandoffStore). The
/// photographer, 13 November 2026: "zodat ik verder kan waar ik gebleven was
/// als ik wegga van mijn pc". A card as Your Station under it (homeCard,
/// HomeCardButtonStyle): the whole card goes on with it, Continue a word
/// at its foot.
private struct HomeHandoffNotice: View {
    let margin: CGFloat
    /// Beside Your Station, in the row of two.
    var isPaired = false

    @Environment(HandoffStore.self) private var handoff
    @Environment(\.isWide) private var isWide

    init(margin: CGFloat, isPaired: Bool = false) {
        self.margin = margin
        self.isPaired = isPaired
    }

    var body: some View {
        if let offer = handoff.offer {
            let action = offer.isOwn ? String(localized: "Continue") : String(localized: "Continue Here")
            let line = "\(offer.track.name) · \(offer.track.artistLine)"
            Button {
                handoff.continueHere()
            } label: {
                if isWide {
                    wide(offer, action: action)
                } else {
                    // The iPhone's, as it was: words alone, on raised.
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(offer.heading)
                            .desktopFont(15, phone: .subheadline)
                            .foregroundStyle(.secondary)
                        Text(line)
                            .desktopFont(15, phone: nil)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        HomeCardLink(title: action, systemImage: "chevron.forward", isTrailing: true)
                            .padding(.top, Theme.Space.s)
                    }
                    .frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
                    .homeCard()
                }
            }
            .buttonStyle(HomeCardButtonStyle())
            .accessibilityLabel(Text(verbatim: "\(offer.heading), \(line), \(action)"))
            .padding(.horizontal, margin)
        }
    }

    /// On a wide page in Your Station's form, as Linux's handoffCard
    /// ("beide met een soortgelijke opmaak", 18 November 2026): the song's
    /// cover 120 with the record behind it, 24, then the heading, the song
    /// in the serif, its artist 8 under it and Continue 12 under that, in
    /// the middle of the art's height; a step lighter than Your Station.
    private func wide(_ offer: HandoffStore.Offer, action: String) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.xl) {
            HomeCardRecord(side: 120) {
                ArtworkView(offer.track.artwork, size: 120, sleeve: TitleSleeve.Words(track: offer.track))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(offer.heading)
                    .desktopFont(13)
                    .foregroundStyle(.secondary)
                Text(offer.track.name)
                    .desktopFont(24, design: .serif)
                    .foregroundStyle(.primary)
                Text(offer.track.artistLine)
                    .desktopFont(13)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.s)
                HomeCardLink(title: action, systemImage: "chevron.forward", isTrailing: true)
                    .padding(.top, Theme.Space.m)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .homeCardFrame(isPaired: isPaired, isWide: true)
        .homeCard(Theme.raisedLighter)
    }
}

private struct HomeOfflineNotice: View {
    let margin: CGFloat

    @Environment(LibraryStore.self) private var library
    @Environment(OfflineStore.self) private var offline

    init(margin: CGFloat) {
        self.margin = margin
    }

    var body: some View {
        if isFailed || offline.isOffline {
            // On a soft amber ground of its own (Theme.notice), shaped as
            // Home's cards: a warning, but a quiet one, in the Arch's
            // colours, with the glyph in the accent.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Image(systemName: offline.hasNetwork ? "wifi.exclamationmark" : "wifi.slash")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(message)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") {
                        offline.checkServer()
                        Task { await library.refresh() }
                    }
                    .buttonStyle(.secondary)
                }
            }
            .desktopFont(15, phone: .subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeCard(Theme.notice)
            .frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
            .accessibilityElement(children: .contain)
            .padding(.horizontal, margin)
        }
    }

    /// The load failed; the library on screen is the cached one (HomeFeed
    /// shows only while there are tracks). A refresh under way is
    /// `.loading`, so the notice goes while it tries and comes back if it fails.
    private var isFailed: Bool {
        if case .failed = library.state { return true }
        return false
    }

    /// Why first — no network at all, or no server on it — then what still
    /// works: the songs on the phone, else the library from last time.
    private var message: String {
        let why = offline.hasNetwork
            ? String(localized: "Can’t reach \(serverName).")
            : String(localized: "You’re offline.")
        let still = offline.songCount > 0
            ? String(localized: "The songs on this \(Device.model) still play.")
            : String(localized: "Showing your library from last time.")
        return "\(why) \(still)"
    }

    private var serverName: String {
        library.serverName ?? String(localized: "your server")
    }
}

// MARK: - Your Station

/// Your Station on top, on a ground of its own (homeCard): its arch beside
/// its name in the serif, one fact — when it last played — and the screen's
/// one filled button, which plays it at once. Flat, as every station is
/// that is not on the air. A tap elsewhere opens Your Station's page, to see what it would
/// play first, as every station's tile does. While a station plays it shows
/// that station instead, lit, under the one small label, "On air", with
/// the song; a tap then opens Now Playing. The Radio tab shows it too, while
/// nothing is on the air. On a wide page as Linux has it (spec §5): the art
/// 120, 24, and beside it the name in the serif, the fact and Play, 12
/// under it, the words in the middle of the art's height (the iPhone's too).
struct HomeStationHero: View {
    let measures: HomeMeasures
    /// Beside the music to go on with, in the row of two.
    var isPaired = false

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(HistoryStore.self) private var history
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(measures: HomeMeasures, isPaired: Bool = false) {
        self.measures = measures
        self.isPaired = isPaired
    }

    var body: some View {
        // On a wide page always Your Station, lit while it is the one on
        // the air, as Linux's Home: another station on air is Radio's.
        let onAir = radio.stationOnAir(player: player).flatMap { station in
            !measures.isWide || station.seed == .personal ? station : nil
        }
        let shown = onAir ?? yourStation
        let isWide = measures.isWide
        let gap = isWide ? Theme.Space.xl : Theme.Space.l
        // Side by side; the art above the words at the largest text sizes,
        // where side by side leaves the words no room.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: gap))
            : AnyLayout(HStackLayout(alignment: isWide ? .center : .top, spacing: gap))
        let side = isWide ? Self.wideArt : HomeLayout.heroArt
        // The whole card is the button: Play, or on the air Pause and
        // Play, as its filled button did.
        Button {
            act(onAir)
        } label: {
            layout {
                HomeCardRecord(side: side) {
                    StationArtwork(station: shown, size: side)
                }
                words(onAir)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isWide ? .leading : .topLeading)
            }
            // As tall as the art, so the name starts at its top and the
            // word ends at its foot; taller when the words need it.
            .fixedSize(horizontal: false, vertical: true)
            // Wide, as wide as the art and its words, as Linux's; in the
            // row of two, the row's width.
            .homeCardFrame(isPaired: isPaired, isWide: isWide)
            .homeCard()
        }
        .buttonStyle(HomeCardButtonStyle())
        // Play now, or its page: on a long press as on every station's tile.
        .contextMenu {
            StationMenu(station: shown)
        }
        .animation(reduceMotion ? nil : .default, value: onAir?.id)
        .accessibilityLabel(Text(verbatim: "\(shown.title), \(actionWord(onAir))"))
        .accessibilityHint(onAir == nil ? Text("Starts Your Station") : Text(verbatim: ""))
        // Its page, as the long press offers it.
        .accessibilityAction(named: Text("Show Station")) {
            navigator.open(.station(onAir ?? yourStation))
        }
    }

    /// The art on a wide page (spec §8).
    private static let wideArt: CGFloat = 120

    /// Your Station as the mixes built it, with the listener's covers.
    private var personal: Station? {
        mixes.stations.first { $0.seed == .personal }
    }

    /// Your Station for its page: as the mixes built it, else as the radio
    /// names it now (the mixes are made a moment after the library).
    private var yourStation: Station {
        personal ?? radio.station(for: .personal)
    }

    private func words(_ onAir: Station?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let onAir {
                Eyebrow("On air")
                name(onAir.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                // Wide, when it started and 8 under the name, as Linux's.
                Group {
                    if radio.isStarting {
                        Text("Choosing the first songs…")
                    } else if measures.isWide, let started = StationClock.shared.started(onAir) {
                        Text(verbatim: started)
                    } else if let track = player.currentTrack {
                        Text("\(track.name) · \(track.artistLine)")
                    }
                }
                .desktopFont(13, phone: .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.top, measures.isWide ? Theme.Space.xs : 0)
            } else {
                name(String(localized: "Your Station"))
                    .foregroundStyle(.primary)
                // A fact, not a slogan: what the listener plays at this hour
                // (RadioController.yourStationFact), else when it last
                // played on this device. Wide, 8 under the name, as Linux's.
                Text(radio.yourStationFact?.text
                     ?? RelativeDay.lastPlayed(HomeShelves.stationDates(events: history.history.events)[yourStation.id]))
                    .desktopFont(13, phone: .subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, measures.isWide ? Theme.Space.xs : 0)
            }
            // At the art's foot; on a wide page 12 under the words, which
            // stand in the middle of the art.
            if measures.isWide {
                Color.clear.frame(height: Theme.Space.s)
            } else {
                Spacer(minLength: Theme.Space.m)
            }
            HomeCardLink(title: actionWord(onAir),
                         systemImage: onAir != nil && player.isPlaying ? "pause.fill" : "play.fill",
                         isWorking: radio.isStarting)
        }
    }

    /// The station's name in the serif: the title style's on the iPhone,
    /// a section's 24 on a wide page.
    @ViewBuilder
    private func name(_ title: String) -> some View {
        if measures.isWide {
            Text(title).desktopFont(24, design: .serif)
        } else {
            Text(title).font(.serif(.title2))
        }
    }

    /// What the card does: Play, or Pause while it plays on the air.
    private func actionWord(_ onAir: Station?) -> String {
        if radio.isStarting { return String(localized: "Starting") }
        return onAir != nil && player.isPlaying ? String(localized: "Pause") : String(localized: "Play")
    }

    private func act(_ onAir: Station?) {
        // The first songs are being chosen; a second tap would only start
        // choosing again.
        guard !radio.isStarting else { return }
        if onAir != nil {
            player.togglePlayPause()
        } else {
            Stats.track(.stationStarted, ["seed": "personal", "from": "hero"])
            radio.start(.personal)
        }
    }
}

// MARK: - Mixes

private struct HomeMixesSection: View {
    let measures: HomeMeasures

    @Environment(MixStore.self) private var mixes

    init(measures: HomeMeasures) {
        self.measures = measures
    }

    var body: some View {
        // Each under its own name, as the kit names the moods after their
        // songs: never "Daily Mix 1" to 6 (MixesRuleTests).
        if !mixes.mixes.isEmpty {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle("Mixes", fact: madeAt, measures: measures)
                Shelf(items: mixes.mixes, width: measures.tile, margin: measures.margin) { mix in
                    HomeMixLink(mix: mix)
                }
            }
        } else if isMaking {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle("Mixes", measures: measures)
                HomePlaceholderShelf(kind: .mix, width: measures.tile, margin: measures.margin)
            }
        }
    }

    /// Being made, or about to be (Home's task has not started it yet).
    private var isMaking: Bool { mixes.isBuilding || mixes.builtAt == nil }

    /// "Made at 06:00": when today's mixes were made, a fact in the place
    /// of "Made for You".
    private var madeAt: String? {
        guard let builtAt = mixes.builtAt else { return nil }
        let time = builtAt.formatted(date: .omitted, time: .shortened)
        return String(localized: "Made at \(time)")
    }
}

// MARK: - Played lately

/// One thing played lately: an album the listener chose, or a station.
private struct HomePlayedItem: Identifiable {
    enum Kind {
        case album(Album)
        case station(Station)
    }

    let kind: Kind
    let date: Date

    var id: String {
        switch kind {
        case let .album(album): "album-\(album.id)"
        case let .station(station): "station-\(station.id)"
        }
    }
}

/// What the listener played lately, newest first, each with when: the
/// albums they chose (HomeShelves.recentlyPlayedDated: not a station's
/// songs) and the stations they listened to, as one list on hairlines. On
/// a wide page in the page's columns, 24 apart, as Linux has it.
private struct HomePlayedLatelySection: View {
    let measures: HomeMeasures

    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(RadioController.self) private var radio

    init(measures: HomeMeasures) {
        self.measures = measures
    }

    /// Six on the iPhone; on a wide page twelve, as Linux shows, in two or
    /// three columns.
    private var limit: Int { measures.isWide ? 12 : 6 }

    var body: some View {
        let items = played
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: measures.isWide ? Theme.Space.s : Theme.Space.xs) {
                HomeSectionTitle("Played lately", measures: measures)
                if measures.isWide {
                    let column = GridItem(.flexible(), spacing: Theme.Space.xl, alignment: .top)
                    LazyVGrid(columns: Array(repeating: column, count: measures.columns), spacing: 0) {
                        ForEach(items) { item in
                            HomePlayedRow(item: item, isWide: true)
                        }
                    }
                    .padding(.horizontal, measures.margin)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HomePlayedRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private var played: [HomePlayedItem] {
        let events = history.history.events
        let albums = HomeShelves.recentlyPlayedDated(events: events, tracks: library.tracks,
                                                     albums: library.albums,
                                                     track: { library.track(id: $0) },
                                                     album: { library.album(id: $0) },
                                                     limit: limit)
        var items = albums.map { HomePlayedItem(kind: .album($0.album), date: $0.date) }
        // The albums alone on a wide page, as Linux's; the stations are
        // Radio's tiles there.
        if measures.isWide { return items }
        // A station is in the list once it has played a song here (the
        // history knows its songs by the station's id).
        let dates = HomeShelves.stationDates(events: events)
        for station in radio.recentStations {
            if let date = dates[station.id] {
                items.append(HomePlayedItem(kind: .station(station), date: date))
            }
        }
        items.sort { $0.date > $1.date }
        return Array(items.prefix(limit))
    }
}

/// A row of Played lately: the cover or the station's arch, the name, what
/// it is, and when, with a hairline under it from the words to the edge.
/// It opens the album or the station's page; a long press plays it.
private struct HomePlayedRow: View {
    let item: HomePlayedItem
    /// In a wide page's column: when it played after what it is ("Artist ·
    /// Today"), the hairline the column's width; the grid gives the margin.
    var isWide = false

    var body: some View {
        switch item.kind {
        case let .album(album):
            NavigationLink(value: Route.album(album)) {
                row(title: album.name, detail: album.artistLine) {
                    ArtworkView(album.artwork, size: Self.artSide, sleeve: TitleSleeve.Words(album: album))
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                HomeAlbumMenu(album: album)
            }
        case let .station(station):
            NavigationLink(value: Route.station(station)) {
                row(title: station.title, detail: String(localized: "Station")) {
                    StationArtwork(station: station, size: Self.artSide)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                StationMenu(station: station)
            }
        }
    }

    private static let artSide: CGFloat = 48

    private func row<Art: View>(title: String, detail: String, @ViewBuilder art: () -> Art) -> some View {
        let when = RelativeDay.standalone(item.date)
        let line = isWide ? [detail, when].filter { !$0.isEmpty }.joined(separator: " · ") : detail
        return HStack(spacing: isWide ? Theme.Space.l : Theme.Space.m) {
            art()
            VStack(alignment: .leading, spacing: isWide ? 0 : Theme.Space.xs) {
                Text(title)
                    .desktopFont(15, phone: nil, wide: isWide)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !line.isEmpty {
                    Text(line)
                        .desktopFont(13, phone: .subheadline, wide: isWide)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if !isWide {
                Text(when)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .padding(.trailing, isWide ? 0 : Theme.margin)
        .overlay(alignment: .bottom) {
            Hairline(inset: isWide ? 0 : Self.artSide + Theme.Space.m)
        }
        .padding(.leading, isWide ? 0 : Theme.margin)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Albums

/// The albums played most, by the plays of their songs on every device.
private struct HomeMostPlayedSection: View {
    let measures: HomeMeasures

    @Environment(LibraryStore.self) private var library

    init(measures: HomeMeasures) {
        self.measures = measures
    }

    var body: some View {
        let albums = HomeShelves.mostPlayed(tracks: library.tracks, album: { library.album(id: $0) })
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle("Most played", measures: measures)
                Shelf(items: albums, width: measures.tile, margin: measures.margin) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}

/// Twenty albums from anywhere in the library, in an order that holds for
/// the day, as Feishin's "Explore from your library".
private struct HomeExploreSection: View {
    let measures: HomeMeasures

    @Environment(LibraryStore.self) private var library
    @Environment(MixStore.self) private var mixes

    init(measures: HomeMeasures) {
        self.measures = measures
    }

    var body: some View {
        // The mixes' day, so the shelf turns over with them the next morning
        // (Home rebuilds them when it comes back to the front), rather than
        // only when the library next changes.
        let day = HomeShelves.dayNumber(of: mixes.builtAt ?? Date())
        let albums = HomeShelves.explore(albums: library.albums, day: day)
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle("Explore", measures: measures)
                Shelf(items: albums, width: measures.tile, margin: measures.margin) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}

private struct HomeRecentlyAddedSection: View {
    let measures: HomeMeasures

    @Environment(LibraryStore.self) private var library

    init(measures: HomeMeasures) {
        self.measures = measures
    }

    var body: some View {
        let albums = Array(library.recentlyAddedAlbums.prefix(20))
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle("Recently added", route: .recentlyAdded, measures: measures)
                Shelf(items: albums, width: measures.tile, margin: measures.margin) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}
