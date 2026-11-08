// Home: the two things the photographer asked for most, first — "op de
// homepage wil ik dat de app zelf leuke playlists verzint en of een goede
// radio functie heeft" (8 November 2026). Their own station on top, one tap
// from playing; the mixes Jukebox made up today; stations to start; then, as
// Feishin's Home and Music's have them ("Ik vind feishin een fijne desktop
// app op Linux voor context"), what they chose to play lately, what they
// play most, albums to explore today, and what is new. Explore needs no
// history, so Home is full on day one too.

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
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // The mark only, not a button: whose app this is, as a
                // signature, lit.
                ArchMark(size: 16)
            }
            .sharedBackgroundVisibility(.hidden)
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
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                HomeOfflineNotice()
                HomeStationHero()
                    .padding(.horizontal, Theme.margin)
                HomeMixesSection()
                HomeStationsSection()
                HomeRecentlyPlayedSection()
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

private enum HomeLayout {
    /// The widest the cards on top get: on the iPad, and an iPhone on its
    /// side, a card across the whole screen leaves the artwork half a
    /// screen from its words. At 560 the words keep about 400 points beside
    /// it, room for "Endless music from everything you love" on one line.
    static let cardWidth: CGFloat = 560
}

// MARK: - The server out of reach

/// The library from last time, while the server does not answer: said once,
/// small, above the music, with a way to try again. Only when there is a
/// library on screen; without one HomeLibraryStatus says it full size.
private struct HomeOfflineNotice: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if isFailed {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Label {
                    Text("Can’t reach \(serverName). Showing your library from last time.")
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                Button("Try Again") {
                    Task { await library.refresh() }
                }
                .buttonStyle(.secondary)
                .fixedSize()
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: HomeLayout.cardWidth, alignment: .leading)
            // The system's grouped-card grey, as the Radio tab's card on the air.
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: Theme.Radius.card))
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

    private var serverName: String {
        library.serverName ?? String(localized: "your server")
    }
}

// MARK: - Your Station

/// The card on top: the listener's own station on Cabinet, its window with
/// the core lit (lit means endless: the radio), and the screen's one filled
/// button, which plays it at once. A tap elsewhere on the card opens Your
/// Station's page, to see what it would play first, as every station's
/// tile does. While a station plays it shows that station instead, and a
/// tap opens Now Playing.
private struct HomeStationHero: View {
    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(Navigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let onAir = radio.stationOnAir(player: player)
        // Side by side as a wide card; the art above the words at the
        // largest text sizes, where side by side leaves the words no room.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Space.l))
        // 104: on a 375-point iPhone the words keep about 175 points.
        let art = StationArtwork(station: onAir ?? yourStation, size: 104, cornerRadius: Theme.Radius.artwork)
        layout {
            if isStacked { art }
            words(onAir)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isStacked { art }
        }
        .padding(Theme.margin)
        // About 16:9 on an iPhone; taller when the text is larger; no wider
        // than HomeLayout.cardWidth on the iPad.
        .frame(maxWidth: HomeLayout.cardWidth, minHeight: 196, alignment: .leading)
        .background(Theme.Arch.cabinet, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
        .onTapGesture {
            if onAir != nil {
                navigator.isNowPlayingPresented = true
            } else {
                navigator.open(.station(yourStation))
            }
        }
        // Play now, or its page: on a long press as on every station's tile.
        .contextMenu {
            StationMenu(station: onAir ?? yourStation)
        }
        // Always Cabinet, the dark the light stands in: its words light and
        // its accent Glow here in light mode too.
        .environment(\.colorScheme, .dark)
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
                Eyebrow("Now Playing")
                Text(onAir.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Group {
                    if radio.isStarting {
                        Text("Choosing the first songs…")
                    } else if let track = player.currentTrack {
                        Text("\(track.name) · \(track.artistLine)")
                    } else {
                        Text("Endless music from everything you love")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            } else {
                Eyebrow("Radio")
                Text("Your Station")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Endless music from everything you love")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            playButton(onAir)
                .padding(.top, Theme.Space.m)
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
                radio.start(.personal)
            }
        } label: {
            Group {
                if radio.isStarting {
                    ProgressView()
                        .tint(Theme.onAccent)
                        .accessibilityLabel("Starting")
                } else if onAir != nil && player.isPlaying {
                    Label("Pause", systemImage: "pause.fill")
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .frame(minWidth: 88)
        }
        .buttonStyle(.prominent)
        .fixedSize()
        .accessibilityHint(onAir == nil ? Text("Starts Your Station") : Text(verbatim: ""))
        // The card around it opens the station's page on a tap (while
        // nothing plays) or a long press; VoiceOver gives a container
        // neither, so the page is offered here, as the long press offers it.
        .accessibilityAction(named: Text("Show Station")) {
            navigator.open(.station(onAir ?? yourStation))
        }
    }
}

// MARK: - Shelves

private struct HomeMixesSection: View {
    @Environment(MixStore.self) private var mixes

    var body: some View {
        if !mixes.mixes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Made for You", eyebrow: "Mixes")
                Shelf(items: mixes.mixes, width: 170) { mix in
                    HomeMixLink(mix: mix)
                }
            }
        } else if isMaking {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Made for You", eyebrow: "Mixes")
                HomePlaceholderShelf(kind: .mix, width: 170)
            }
        }
    }

    /// Being made, or about to be (Home's task has not started it yet).
    private var isMaking: Bool { mixes.isBuilding || mixes.builtAt == nil }
}

private struct HomeStationsSection: View {
    @Environment(MixStore.self) private var mixes

    var body: some View {
        // Your Station is the card on top; the shelf has the others.
        let stations = mixes.stations.filter { $0.seed != .personal }
        if !stations.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Stations for You")
                Shelf(items: stations, width: 150) { station in
                    StationTileLink(station: station)
                }
            }
        } else if mixes.isBuilding || mixes.builtAt == nil {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Stations for You")
                HomePlaceholderShelf(kind: .station, width: 150)
            }
        }
    }
}

/// What the listener chose to play, from this device's history: a station's
/// songs are not in it, so a night of radio does not fill it
/// (HomeShelves.recentlyPlayed).
private struct HomeRecentlyPlayedSection: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history

    var body: some View {
        let albums = HomeShelves.recentlyPlayed(events: history.history.events, tracks: library.tracks,
                                                albums: library.albums,
                                                track: { library.track(id: $0) },
                                                album: { library.album(id: $0) })
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Recently Played")
                Shelf(items: albums, width: 150) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}

/// The albums played most, by the plays of their songs on every device.
private struct HomeMostPlayedSection: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let albums = HomeShelves.mostPlayed(tracks: library.tracks, album: { library.album(id: $0) })
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Most Played")
                Shelf(items: albums, width: 150) { album in
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
                Shelf(items: albums, width: 150) { album in
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
                SectionHeader("Recently Added", route: .recentlyAdded)
                Shelf(items: albums, width: 150) { album in
                    HomeAlbumLink(album: album)
                }
            }
        }
    }
}
