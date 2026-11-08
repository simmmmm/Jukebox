// Home: the two things the photographer asked for most, first — "op de
// homepage wil ik dat de app zelf leuke playlists verzint en of een goede
// radio functie heeft" (8 November 2026). Their own station on top, one tap
// from playing; the mixes Jukebox made up today; stations to start; then
// what they played lately and what is new, as Music's Home has them.

import JukeboxKit
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingSettings = false

    init() {}

    var body: some View {
        Group {
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
                // The mark only, not a button, as on Numa's own home.
                JukeboxMark(diameter: 16)
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
                HomeStationHero()
                    .padding(.horizontal, Theme.margin)
                HomeMixesSection()
                HomeStationsSection()
                HomeRecentlyPlayedSection()
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

// MARK: - Your Station

/// The card on top: the listener's own station on Numa's page grey, the
/// eclipse over their covers, and the screen's one filled button. While a
/// station plays it shows that station instead, and a tap opens Now Playing.
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Space.l))
        layout {
            words(onAir)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 76: on a 375-point iPhone the words keep about 170 points.
            HomeEclipseArt(station: onAir ?? personal, diameter: 76)
        }
        .padding(Theme.margin)
        // About 16:9 on an iPhone; taller when the text is larger.
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
        .background(Theme.page, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
        .onTapGesture {
            if onAir != nil { navigator.isNowPlayingPresented = true }
        }
        // Always Numa's dark page, so its accent is white here in light mode too.
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .default, value: onAir?.id)
        .accessibilityElement(children: .contain)
    }

    /// Your Station as the mixes built it, with the listener's covers.
    private var personal: Station? {
        mixes.stations.first { $0.seed == .personal }
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
                    StationTileButton(station: station)
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

private struct HomeRecentlyPlayedSection: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let albums = Array(library.recentlyPlayedAlbums.prefix(20))
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
