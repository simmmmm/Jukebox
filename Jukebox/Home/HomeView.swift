// Home: the two things the photographer asked for most, first — "op de
// homepage wil ik dat de app zelf leuke playlists verzint en of een goede
// radio functie heeft" (8 November 2026). Their own station on top, one tap
// from playing; the mixes Jukebox made up today; then, as Feishin's Home and
// Music's have them ("Ik vind feishin een fijne desktop app op Linux voor
// context"), what they played lately and when, what they play most, albums
// to explore today, and what is new. Explore needs no history, so Home is
// full on day one too.
//
// Sketch D (docs/design/home-after.png), approved the same day — "Ja nice
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isWide) private var isWide

    @State private var isShowingSettings = false
    /// The page's own width, for its measures on a wide page.
    @State private var pageWidth = 1200
    /// A wide page's own title has scrolled under the bar.
    @State private var isTitleScrolled = false

    init() {}

    var body: some View {
        let measures = HomeMeasures(isWide: isWide, width: pageWidth)
        // A ZStack, not a Group: a Group hands its modifiers to whichever
        // branch shows, so Settings, opened during the first load, would
        // close and open again (losing what was typed) when the load ends.
        ZStack {
            if library.tracks.isEmpty {
                HomeLibraryStatus()
            } else {
                HomeFeed(measures: measures, isTitleScrolled: $isTitleScrolled)
            }
        }
        .background(Theme.ground)
        .homePageWidth($pageWidth)
        // What part of the day it is, in the serif (Theme.styleNavigationBars):
        // sketch D's "Tonight" in the evening. The tab is still Home. On a
        // wide page the title is the page's own, and the bar's once that
        // has scrolled away.
        .homeTitle(RelativeDay.partOfDay(), isScrolled: isTitleScrolled)
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
    let measures: HomeMeasures
    @Binding var isTitleScrolled: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes

    init(measures: HomeMeasures, isTitleScrolled: Binding<Bool>) {
        self.measures = measures
        _isTitleScrolled = isTitleScrolled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: measures.betweenSections) {
                if measures.isWide {
                    // As Linux's: the part of the day 24 under the bar, and
                    // Your Station 32 under it, not a section's 40 (spec §5).
                    HomePageTitle(RelativeDay.partOfDay(), measures: measures)
                        .padding(.bottom, -Theme.Space.s)
                }
                HomeOfflineNotice(margin: measures.margin)
                HomeHandoffNotice(margin: measures.margin)
                HomeStationHero(measures: measures)
                    .padding(.horizontal, measures.margin)
                // On a wide page the space alone parts them, as on Linux.
                if !measures.isWide {
                    Hairline()
                }
                HomeMixesSection(measures: measures)
                HomePlayedLatelySection(measures: measures)
                HomeMostPlayedSection(measures: measures)
                HomeExploreSection(measures: measures)
                HomeRecentlyAddedSection(measures: measures)
            }
            .padding(.top, measures.isWide ? Theme.Space.xl : Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > HomePageTitle.scrolledPast
        } action: { _, isPast in
            isTitleScrolled = measures.isWide && isPast
        }
        .refreshable {
            await library.refresh()
            await mixes.rebuild(library: library, history: history, settings: settings)
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
/// als ik wegga van mijn pc". Words on the ground, as the notice above it.
private struct HomeHandoffNotice: View {
    let margin: CGFloat

    @Environment(HandoffStore.self) private var handoff

    init(margin: CGFloat) {
        self.margin = margin
    }

    var body: some View {
        if let offer = handoff.offer {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(offer.heading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(offer.track.name) · \(offer.track.artistLine)")
                    .lineLimit(2)
                Button(offer.isOwn ? String(localized: "Continue") : String(localized: "Continue Here")) {
                    handoff.continueHere()
                }
                .buttonStyle(.secondary)
            }
            .frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
            .accessibilityElement(children: .contain)
            .padding(.horizontal, margin)
        }
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
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Label {
                    Text(message)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: offline.hasNetwork ? "wifi.exclamationmark" : "wifi.slash")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                Button("Try Again") {
                    offline.checkServer()
                    Task { await library.refresh() }
                }
                .buttonStyle(.secondary)
            }
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

/// Your Station on top, on the page's ground: its arch beside its name in
/// the serif, one fact — when it last played — and the screen's one filled
/// button, which plays it at once. Flat, as every station is that is not on
/// the air. A tap elsewhere opens Your Station's page, to see what it would
/// play first, as every station's tile does. While a station plays it shows
/// that station instead, lit, under the one small label, "On air", with
/// the song; a tap then opens Now Playing. The Radio tab shows it too, while
/// nothing is on the air. On a wide page as Linux has it (spec §5): the art
/// 120, 24, and beside it the name in the serif, the fact and Play, 16
/// under it, the words in the middle of the art's height.
struct HomeStationHero: View {
    let measures: HomeMeasures

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(HistoryStore.self) private var history
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(measures: HomeMeasures) {
        self.measures = measures
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
        layout {
            StationArtwork(station: shown, size: isWide ? Self.wideArt : HomeLayout.heroArt)
            words(onAir)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isWide ? .leading : .topLeading)
        }
        // As tall as the art, so the name starts at its top and Play ends
        // at its foot; taller when the words need it.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture {
            if onAir != nil {
                navigator.isNowPlayingPresented = true
            } else {
                navigator.open(.station(yourStation))
            }
        }
        // Play now, or its page: on a long press as on every station's tile.
        .contextMenu {
            StationMenu(station: shown)
        }
        .animation(reduceMotion ? nil : .default, value: onAir?.id)
        .accessibilityElement(children: .contain)
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
                Group {
                    if radio.isStarting {
                        Text("Choosing the first songs…")
                    } else if let track = player.currentTrack {
                        Text("\(track.name) · \(track.artistLine)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            } else {
                name(String(localized: "Your Station"))
                    .foregroundStyle(.primary)
                // A fact, not a slogan: when it last played on this device.
                Text(RelativeDay.lastPlayed(HomeShelves.stationDates(events: history.history.events)[yourStation.id]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Play at the art's foot; on a wide page 16 under the words,
            // which stand in the middle of the art.
            if measures.isWide {
                Color.clear.frame(height: Theme.Space.m)
            } else {
                Spacer(minLength: Theme.Space.m)
            }
            playButton(onAir)
        }
    }

    /// The station's name in the serif: the title style's on the iPhone,
    /// a section's 24 on a wide page.
    @ViewBuilder
    private func name(_ title: String) -> some View {
        if measures.isWide {
            Text(title).homeSerif(24)
        } else {
            Text(title).font(.serif(.title2))
        }
    }

    private func playButton(_ onAir: Station?) -> some View {
        Button {
            // The first songs are being chosen; a second tap would only
            // start choosing again.
            guard !radio.isStarting else { return }
            if onAir != nil {
                player.togglePlayPause()
            } else {
                Stats.track(.stationStarted, ["seed": "personal", "from": "hero"])
                radio.start(.personal)
            }
        } label: {
            Group {
                if radio.isStarting {
                    ProgressView()
                        .tint(Theme.onAccent)
                        .accessibilityLabel("Starting")
                } else if onAir != nil && player.isPlaying {
                    Text("Pause")
                } else {
                    Text("Play")
                }
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.prominent)
        .fixedSize()
        .accessibilityHint(onAir == nil ? Text("Starts Your Station") : Text(verbatim: ""))
        // The words around it open the station's page on a tap (while
        // nothing plays) or a long press; VoiceOver gives a container
        // neither, so the page is offered here, as the long press offers it.
        .accessibilityAction(named: Text("Show Station")) {
            navigator.open(.station(onAir ?? yourStation))
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
                    ArtworkView(album.artwork, size: Self.artSide)
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
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !line.isEmpty {
                    Text(line)
                        .font(.subheadline)
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
