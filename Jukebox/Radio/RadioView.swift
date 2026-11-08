// The Radio tab: the photographer's favourite part ("ik vind vooral de
// radiofunctie echt belangrijk", 8 November 2026), so it is a page of its
// own as in Music. As sketch D draws it (docs/design/radio-after.png): on
// top the station on the air — its art, the one lit thing on the page, the
// dial, Pause and Stop — or, while nothing is on the air, Your Station with
// the tab's one filled button, as on Home; then "Stations", the three made
// from the listener's own taste (Your Station, Discovery, Loved) and the
// ones played lately, as a list on hairlines with when each last played;
// then the stations Jukebox suggests by artist, genre and decade. Start a
// Station is the toolbar's "+". A station's row or tile opens its page, to
// see what it would play before it plays ("ipv dat je kan zien wat je van
// de playlist gemaakt hebt"); Your Station's Play, and every long press's
// Play Station, play at once.

import JukeboxKit
import SwiftUI

struct RadioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @Environment(Navigator.self) private var navigator

    @State private var isPicking = false
    @State private var isShowingSettings = false
    /// The station chosen in Start a Station, opened once its sheet has gone.
    @State private var picked: Station?

    init() {}

    var body: some View {
        // A ZStack, as Home's: the sheets sit on one view whatever it shows.
        ZStack {
            if library.tracks.isEmpty {
                HomeLibraryStatus()
            } else {
                RadioFeed(isShowingSettings: $isShowingSettings)
            }
        }
        .background(Theme.ground)
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPicking = true
                } label: {
                    Label("Start a Station", systemImage: "plus")
                }
                .disabled(library.tracks.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "person.crop.circle")
                }
            }
        }
        // The page is pushed after the sheet has gone: pushed while it was
        // closing (CI's screenshot walk, build 15), the sheet stayed up and
        // the page never came.
        .sheet(isPresented: $isPicking, onDismiss: openPicked) {
            RadioStationPicker(onPick: { picked = $0 })
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

    private func openPicked() {
        guard let station = picked else { return }
        picked = nil
        navigator.radioPath.append(Route.station(station))
    }
}

private struct RadioFeed: View {
    @Binding var isShowingSettings: Bool

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isShowingSettings: Binding<Bool>) {
        _isShowingSettings = isShowingSettings
    }

    var body: some View {
        let onAir = radio.stationOnAir(player: player)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Group {
                    if let onAir {
                        RadioOnAirCard(station: onAir)
                    } else {
                        HomeStationHero()
                    }
                }
                .frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
                .padding(.horizontal, Theme.margin)
                .transition(.opacity)

                Hairline()
                // Your Station is on top while nothing is on the air: the
                // list has it again once a station plays.
                RadioStationList(hidesYourStation: onAir == nil)
                RadioStationShelf(title: "Artist stations", stations: artistStations)
                RadioStationShelf(title: "Genre stations", stations: genreStations)
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

    /// Quiet, at the foot: the radio works without Last.fm, from the
    /// library alone, and knows more with it. What it does, not a promise.
    private var lastFMFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("With a Last.fm API key, the radio also knows which artists and songs sound alike.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") {
                isShowingSettings = true
            }
            .font(.footnote)
            .foregroundStyle(Theme.accent)
            .padding(.top, Theme.Space.xs)
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

// MARK: - Stations

/// "Stations": the three made from the listener's own taste — Your Station,
/// Discovery, Loved — then the ones played lately, newest first, each once,
/// as rows on hairlines with when each last played on this device
/// ("Played Thursday", "Not played yet"). Each row opens the station's page;
/// a long press plays it.
private struct RadioStationList: View {
    let hidesYourStation: Bool

    @Environment(RadioController.self) private var radio
    @Environment(MixStore.self) private var mixes
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history

    init(hidesYourStation: Bool) {
        self.hidesYourStation = hidesYourStation
    }

    var body: some View {
        let stations = listed
        let dates = HomeShelves.stationDates(events: history.history.events)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader("Stations")
            VStack(spacing: 0) {
                ForEach(stations) { station in
                    RadioStationRow(station: station, fact: RelativeDay.played(dates[station.id]))
                }
            }
        }
    }

    private var listed: [Station] {
        var stations: [Station] = []
        if !hidesYourStation {
            stations.append(own(.personal))
        }
        stations.append(own(.discovery))
        // Loved needs favourites to start from: the mixes leave it out when
        // there are none; before they are built, the library says.
        if let loved = built(.favorites) {
            stations.append(loved)
        } else if mixes.builtAt == nil && !library.favoriteTracks.isEmpty {
            stations.append(radio.station(for: .favorites))
        }
        var seen = Set(stations.map(\.id))
        // Your Station on top while nothing is on the air: not again here.
        if hidesYourStation { seen.insert(Station.id(for: .personal)) }
        for station in radio.recentStations where seen.insert(station.id).inserted {
            stations.append(station)
        }
        return stations
    }

    /// As the mixes built it (its covers), else as the radio names it now,
    /// with its own id: a made-up one would be remembered as a station of
    /// its own.
    private func own(_ seed: StationSeed) -> Station {
        built(seed) ?? radio.station(for: seed)
    }

    private func built(_ seed: StationSeed) -> Station? {
        mixes.stations.first { $0.seed == seed }
    }
}

/// A station's row: its arch (lit only while it is on the air), its name,
/// when it last played, a hairline under it from the words to the edge.
private struct RadioStationRow: View {
    let station: Station
    let fact: String

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player

    init(station: Station, fact: String) {
        self.station = station
        self.fact = fact
    }

    private static let art: CGFloat = 52

    var body: some View {
        let onAir = radio.stationOnAir(player: player)?.id == station.id
        NavigationLink(value: Route.station(station)) {
            HStack(spacing: Theme.Space.m) {
                StationArtwork(station: station, size: Self.art)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(fact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.s)
            .padding(.trailing, Theme.margin)
            .overlay(alignment: .bottom) {
                Hairline(inset: Self.art + Theme.Space.m)
            }
            .padding(.leading, Theme.margin)
            .contentShape(.rect)
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

// MARK: - Shelves

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
                Shelf(items: stations, width: HomeLayout.tileWidth) { station in
                    StationTileLink(station: station)
                }
            }
        } else if mixes.stations.isEmpty && (mixes.isBuilding || mixes.builtAt == nil) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title)
                HomePlaceholderShelf(kind: .station, width: HomeLayout.tileWidth)
            }
        }
    }
}
