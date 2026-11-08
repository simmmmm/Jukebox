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
import UIKit

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @Environment(\.scenePhase) private var scenePhase

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
        // sketch D's "Tonight" in the evening. The tab is still Home.
        .navigationTitle(RelativeDay.partOfDay())
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "person.crop.circle")
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
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HomeOfflineNotice()
                HomeStationHero()
                    .padding(.horizontal, Theme.margin)
                Hairline()
                HomeMixesSection()
                HomePlayedLatelySection()
                HomeMostPlayedSection()
                HomeExploreSection()
                HomeRecentlyAddedSection()
            }
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
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
private struct HomeOfflineNotice: View {
    @Environment(LibraryStore.self) private var library
    @Environment(OfflineStore.self) private var offline

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
            .padding(.horizontal, Theme.margin)
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
            ? String(localized: "The songs on this \(UIDevice.current.model) still play.")
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
/// nothing is on the air.
struct HomeStationHero: View {
    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(HistoryStore.self) private var history
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        let onAir = radio.stationOnAir(player: player)
        let shown = onAir ?? yourStation
        // Side by side; the art above the words at the largest text sizes,
        // where side by side leaves the words no room.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.l))
        layout {
            StationArtwork(station: shown, size: HomeLayout.heroArt)
            words(onAir)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                Text(onAir.title)
                    .font(.serif(.title2))
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
                Text("Your Station")
                    .font(.serif(.title2))
                    .foregroundStyle(.primary)
                // A fact, not a slogan: when it last played on this device.
                Text(RelativeDay.lastPlayed(HomeShelves.stationDates(events: history.history.events)[yourStation.id]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.m)
            playButton(onAir)
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
    @Environment(MixStore.self) private var mixes

    var body: some View {
        if !mixes.mixes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Mixes", fact: madeAt)
                Shelf(items: mixes.mixes, width: HomeLayout.tileWidth) { mix in
                    HomeMixLink(mix: mix)
                }
            }
        } else if isMaking {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Mixes")
                HomePlaceholderShelf(kind: .mix, width: HomeLayout.tileWidth)
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
/// songs) and the stations they listened to, as one list on hairlines.
private struct HomePlayedLatelySection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(RadioController.self) private var radio

    private static let limit = 6

    var body: some View {
        let items = played
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader("Played lately")
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HomePlayedRow(item: item)
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
                                                     limit: Self.limit)
        var items = albums.map { HomePlayedItem(kind: .album($0.album), date: $0.date) }
        // A station is in the list once it has played a song here (the
        // history knows its songs by the station's id).
        let dates = HomeShelves.stationDates(events: events)
        for station in radio.recentStations {
            if let date = dates[station.id] {
                items.append(HomePlayedItem(kind: .station(station), date: date))
            }
        }
        items.sort { $0.date > $1.date }
        return Array(items.prefix(Self.limit))
    }
}

/// A row of Played lately: the cover or the station's arch, the name, what
/// it is, and when, with a hairline under it from the words to the edge.
/// It opens the album or the station's page; a long press plays it.
private struct HomePlayedRow: View {
    let item: HomePlayedItem

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
        HStack(spacing: Theme.Space.m) {
            art()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.s)
            Text(RelativeDay.standalone(item.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Space.s)
        .padding(.trailing, Theme.margin)
        .overlay(alignment: .bottom) {
            Hairline(inset: Self.artSide + Theme.Space.m)
        }
        .padding(.leading, Theme.margin)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Albums

/// The albums played most, by the plays of their songs on every device.
private struct HomeMostPlayedSection: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let albums = HomeShelves.mostPlayed(tracks: library.tracks, album: { library.album(id: $0) })
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Most played")
                Shelf(items: albums, width: HomeLayout.tileWidth) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}

/// Twenty albums from anywhere in the library, in an order that holds for
/// the day, as Feishin's "Explore from your library".
private struct HomeExploreSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(MixStore.self) private var mixes

    var body: some View {
        // The mixes' day, so the shelf turns over with them the next morning
        // (Home rebuilds them when it comes back to the front), rather than
        // only when the library next changes.
        let day = HomeShelves.dayNumber(of: mixes.builtAt ?? Date())
        let albums = HomeShelves.explore(albums: library.albums, day: day)
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Explore")
                Shelf(items: albums, width: HomeLayout.tileWidth) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}

private struct HomeRecentlyAddedSection: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let albums = Array(library.recentlyAddedAlbums.prefix(20))
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Recently added", route: .recentlyAdded)
                Shelf(items: albums, width: HomeLayout.tileWidth) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}
