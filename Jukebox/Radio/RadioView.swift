// The Radio tab: the photographer's favourite part ("ik vind vooral de
// radiofunctie echt belangrijk", 8 November 2026), so it is a page of its
// own as in Music. On top what is on the air, with the dial; then the three
// stations made from the listener's own taste — Your Station, Discovery,
// Loved — with the tab's one filled button, Your Station's Play; a way to
// start one from anything; the stations played lately, to go back to; and
// the stations Jukebox suggests by artist, genre and decade. A station's
// card or tile opens its page, to see what it would play before it plays
// ("ipv dat je kan zien wat je van de playlist gemaakt hebt"); Your
// Station's Play, and every long press's Play Station, play at once.

import JukeboxKit
import SwiftUI

struct RadioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes

    @State private var isPicking = false
    @State private var isShowingSettings = false

    init() {}

    var body: some View {
        // A ZStack, as Home's: the sheets sit on one view whatever it shows.
        ZStack {
            if library.tracks.isEmpty {
                HomeLibraryStatus()
            } else {
                RadioFeed(isPicking: $isPicking, isShowingSettings: $isShowingSettings)
            }
        }
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isPicking) {
            RadioStationPicker()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        // The suggested stations are made with the mixes; Radio can be the
        // first tab opened today.
        .task(id: library.lastLoaded) {
            await mixes.rebuildIfStale(library: library, history: history, settings: settings)
        }
    }
}

private struct RadioFeed: View {
    @Binding var isPicking: Bool
    @Binding var isShowingSettings: Bool

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isPicking: Binding<Bool>, isShowingSettings: Binding<Bool>) {
        _isPicking = isPicking
        _isShowingSettings = isShowingSettings
    }

    var body: some View {
        let onAir = radio.stationOnAir(player: player)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                if let onAir {
                    RadioOnAirCard(station: onAir)
                        .padding(.horizontal, Theme.margin)
                        .transition(.opacity)
                }
                RadioFeaturedStations()
                    .padding(.horizontal, Theme.margin)
                startAStation
                    .padding(.horizontal, Theme.margin)
                RadioRecentStationsShelf()
                RadioStationShelf(title: "Artist Stations", stations: artistStations)
                RadioStationShelf(title: "Genre Stations", stations: genreStations)
                RadioStationShelf(title: "Decades", stations: decadeStations)
                if !settings.hasLastFM {
                    lastFMFooter
                        .padding(.horizontal, Theme.margin)
                }
            }
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
            .animation(reduceMotion ? nil : .default, value: onAir?.id)
        }
    }

    private var startAStation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                isPicking = true
            } label: {
                Label("Start a Station", systemImage: "magnifyingglass")
            }
            .buttonStyle(.secondary)
            Text("From any artist, song, album or genre in your library.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Quiet, at the foot: the radio works without Last.fm, from the
    /// library alone, and is better with it.
    private var lastFMFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Stations get smarter with Last.fm. Add a free API key in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                isShowingSettings = true
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The suggested stations, by their seed's kind

    private var artistStations: [Station] { mixes.stations.filter { Self.isArtist($0.seed) } }
    private var genreStations: [Station] { mixes.stations.filter { Self.isGenre($0.seed) } }
    private var decadeStations: [Station] { mixes.stations.filter { Self.isDecade($0.seed) } }

    private static func isArtist(_ seed: StationSeed) -> Bool {
        if case .artist = seed { return true }
        return false
    }

    private static func isGenre(_ seed: StationSeed) -> Bool {
        if case .genre = seed { return true }
        return false
    }

    private static func isDecade(_ seed: StationSeed) -> Bool {
        if case .decade = seed { return true }
        return false
    }
}

// MARK: - Your Station, Discovery, Loved

/// One of the three stations made from the listener's own taste.
private struct RadioFeatured: Identifiable {
    let seed: StationSeed
    let title: String
    let description: String
    /// As the mixes built it (its covers); nil until they have.
    let built: Station?

    var id: String { title }

    /// What the artwork draws: the built station, else the eclipse over a
    /// record until its covers are known.
    var shown: Station { built ?? Station(id: "featured-\(title)", seed: seed, title: title) }

    /// Your Station's card carries the tab's one filled button, as Home's
    /// card on top does: the station the photographer starts most is one
    /// tap from playing on both.
    var carriesPlayButton: Bool { seed == .personal }
}

/// Big cards: on an iPhone Your Station wide on top and the other two side
/// by side under it; on an iPad three in a row.
private struct RadioFeaturedStations: View {
    @Environment(MixStore.self) private var mixes
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let items = featured
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                ForEach(items) { item in
                    RadioFeaturedCard(item: item, isWide: false)
                }
            }
        } else {
            VStack(spacing: Theme.Space.m) {
                if let first = items.first {
                    RadioFeaturedCard(item: first, isWide: true)
                }
                let rest = Array(items.dropFirst())
                if rest.count == 2 {
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        ForEach(rest) { item in
                            RadioFeaturedCard(item: item, isWide: false)
                        }
                    }
                } else {
                    ForEach(rest) { item in
                        RadioFeaturedCard(item: item, isWide: true)
                    }
                }
            }
        }
    }

    private var featured: [RadioFeatured] {
        // Localised here: the cards draw them as plain strings.
        var items = [
            RadioFeatured(seed: .personal, title: String(localized: "Your Station"),
                          description: String(localized: "Endless music from everything you love"),
                          built: built(.personal)),
            RadioFeatured(seed: .discovery, title: String(localized: "Discovery"),
                          description: String(localized: "Songs you rarely or never play, near what you like"),
                          built: built(.discovery)),
        ]
        // Loved needs favourites to start from: the mixes leave it out when
        // there are none; before they are built, the library says.
        let loved = built(.favorites)
        if loved != nil || (mixes.builtAt == nil && !library.favoriteTracks.isEmpty) {
            items.append(RadioFeatured(seed: .favorites, title: String(localized: "Loved"),
                                       description: String(localized: "Your favorites and what sounds like them"),
                                       built: loved))
        }
        return items
    }

    private func built(_ seed: StationSeed) -> Station? {
        mixes.stations.first { $0.seed == seed }
    }
}

private struct RadioFeaturedCard: View {
    let item: RadioFeatured
    let isWide: Bool

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator

    init(item: RadioFeatured, isWide: Bool) {
        self.item = item
        self.isWide = isWide
    }

    var body: some View {
        let onAir = radio.stationOnAir(player: player)?.seed == item.seed
        if item.carriesPlayButton {
            // Not a link itself, so the Play button in it is one of its
            // own (a button in a button's label gets no taps of its own); a
            // tap elsewhere on the card does what the other cards do.
            Group {
                if isWide {
                    wide(onAir: onAir)
                } else {
                    square(onAir: onAir)
                }
            }
            .onTapGesture {
                navigator.open(.station(station))
            }
            .contextMenu {
                StationMenu(station: station)
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(onAir ? .isSelected : [])
        } else {
            NavigationLink(value: Route.station(station)) {
                if isWide {
                    wide(onAir: onAir)
                } else {
                    square(onAir: onAir)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                StationMenu(station: station)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(onAir ? .isSelected : [])
            .accessibilityHint(Text("Shows the station and what it would play"))
        }
    }

    /// The station for its page and its menu: as the mixes built it, else
    /// as the radio names it now, with its own id (the placeholder `shown`
    /// has a made-up one, which would be remembered as a station of its own).
    private var station: Station {
        item.built ?? radio.station(for: item.seed)
    }

    private func start() {
        if let built = item.built {
            radio.start(built)
        } else {
            // Not built yet: the radio names it and finds its covers.
            radio.start(item.seed)
        }
    }

    /// Play, or Pause while the station plays, as on Home's card; the
    /// spinner while its first songs are chosen.
    private func playButton(onAir: Bool) -> some View {
        Button {
            // Its first songs are being chosen; a second tap would only
            // start choosing again. Another station starting is replaced.
            if onAir && radio.isStarting { return }
            if onAir {
                player.togglePlayPause()
            } else {
                start()
            }
        } label: {
            Group {
                if onAir && radio.isStarting {
                    ProgressView()
                        .tint(Theme.onAccent)
                        .accessibilityLabel("Starting")
                } else if onAir && player.isPlaying {
                    Label("Pause", systemImage: "pause.fill")
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .frame(minWidth: 88)
        }
        .buttonStyle(.prominent)
        .fixedSize()
        .accessibilityHint(onAir ? Text(verbatim: "") : Text("Starts Your Station"))
        // The card around it opens the station's page on a tap, which
        // VoiceOver cannot give a container: the page is here for it.
        .accessibilityAction(named: Text("Show Station")) {
            navigator.open(.station(station))
        }
    }

    /// The eclipse on Numa's page grey with the words beside it: the
    /// artwork's own grey runs into the card's, so the two read as one.
    private func wide(onAir: Bool) -> some View {
        HStack(spacing: Theme.Space.l) {
            StationArtwork(station: item.shown, size: 96, cornerRadius: 0)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(item.title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.carriesPlayButton {
                    playButton(onAir: onAir)
                        .padding(.top, Theme.Space.s)
                }
            }
            Spacer(minLength: 0)
            if onAir {
                StationOnAirBadge()
            } else if !item.carriesPlayButton {
                // It opens the station's page now, no longer plays.
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        // With the button the words are taller than the artwork: room above
        // and below them. The artwork's grey is the card's, so the eclipse
        // floats on it rather than stops short.
        .padding(.vertical, item.carriesPlayButton ? Theme.Space.l : 0)
        .padding(.trailing, Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.page, in: .rect(cornerRadius: Theme.Radius.card))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .contentShape(.rect(cornerRadius: Theme.Radius.card))
        // Always Numa's dark page, so its words and accent are light here
        // in light mode too.
        .environment(\.colorScheme, .dark)
    }

    private func square(onAir: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            StationArtwork(station: item.shown, cornerRadius: Theme.Radius.card)
                .overlay(alignment: .topTrailing) {
                    if onAir {
                        StationOnAirBadge()
                            .padding(Theme.Space.s)
                    }
                }
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(item.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            if item.carriesPlayButton {
                playButton(onAir: onAir)
                    .padding(.top, Theme.Space.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

// MARK: - Shelves

/// The stations played lately, newest first, to start again with a tap;
/// nothing until one has played.
private struct RadioRecentStationsShelf: View {
    @Environment(RadioController.self) private var radio

    var body: some View {
        let stations = radio.recentStations
        if !stations.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Recently Played")
                Shelf(items: stations, width: 150) { station in
                    StationTileLink(station: station)
                }
            }
        }
    }
}

/// Suggested stations of one kind; grey placeholders while they are being
/// made, nothing when there are none of the kind.
private struct RadioStationShelf: View {
    let title: String
    let stations: [Station]

    @Environment(MixStore.self) private var mixes

    init(title: String, stations: [Station]) {
        self.title = title
        self.stations = stations
    }

    var body: some View {
        if !stations.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title)
                Shelf(items: stations, width: 150) { station in
                    StationTileLink(station: station)
                }
            }
        } else if mixes.stations.isEmpty && (mixes.isBuilding || mixes.builtAt == nil) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title)
                HomePlaceholderShelf(kind: .station, width: 150)
            }
        }
    }
}
