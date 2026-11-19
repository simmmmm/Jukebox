// The Radio tab: the photographer's favourite part ("ik vind vooral de
// radiofunctie echt belangrijk", 8 November 2026), so it is a page of its
// own as in Music. As sketch D drew it: on
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
//
// On a wide page (the iPad, the Mac) as Linux's Radio, 1:1 ("ik wil dat de
// linux app en de apple app 1:1 op elkaar lijken", the photographer, 14
// November 2026): the title in the serif; the station on air, lit, only
// while one is; then "Stations" and "By genre and decade" as shelves of
// tiles, every arch flat but the one on air. The dial is in Up next.

import JukeboxKit
import SwiftUI

struct RadioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @Environment(Navigator.self) private var navigator
    @Environment(\.isWide) private var isWide

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
        .homeTitle(String(localized: "Radio"))
        .toolbar {
            ToolbarItem(placement: .barTrailing) {
                Button {
                    isPicking = true
                } label: {
                    Label("Start a Station", systemImage: "plus")
                }
                .disabled(library.tracks.isEmpty)
            }
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
        // The sheet is only shown from Radio: on the iPhone this is the
        // Radio tab's stack, in a wide window the page's.
        navigator.open(.station(station))
    }
}

private struct RadioFeed: View {
    @Binding var isShowingSettings: Bool

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(MixStore.self) private var mixes
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWide) private var isWide

    init(isShowingSettings: Binding<Bool>) {
        _isShowingSettings = isShowingSettings
    }

    var body: some View {
        let onAir = radio.stationOnAir(player: player)
        if isWide {
            wide(onAir)
        } else {
            compact(onAir)
        }
    }

    /// As Linux's Radio: the title, the station on air while one is, the
    /// stations, then those by genre and decade (spec §5).
    private func wide(_ onAir: Station?) -> some View {
        WidePage(title: String(localized: "Radio")) { page, _ in
            let measures = HomeMeasures(page: page)
            PageTitle(String(localized: "Radio"))
                .padding(.horizontal, page.side)
            VStack(alignment: .leading, spacing: measures.betweenSections) {
                if let onAir {
                    RadioOnAirCard(station: onAir, measures: measures)
                        .padding(.horizontal, measures.margin)
                        .transition(.opacity)
                }
                RadioStationList(hiding: onAir?.id, measures: measures)
                RadioStationShelf(title: "By genre and decade", stations: genreAndDecadeStations,
                                  measures: measures)
            }
            // The station on air 32 under the title, as Home's Your
            // Station; nothing on air, "Stations" a section's 40.
            .padding(.top, onAir == nil ? measures.betweenSections : Theme.Space.xxl)
            .animation(reduceMotion ? nil : .default, value: onAir?.id)
        }
    }

    private func compact(_ onAir: Station?) -> some View {
        let measures = HomeMeasures(page: nil)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Group {
                    if let onAir {
                        RadioOnAirCard(station: onAir, measures: measures)
                    } else {
                        HomeStationHero(measures: measures)
                    }
                }
                .frame(maxWidth: HomeLayout.heroWidth, alignment: .leading)
                .padding(.horizontal, Theme.margin)
                .transition(.opacity)

                Hairline()
                // Your Station is on top while nothing is on the air: the
                // list has it again once a station plays.
                RadioStationList(hiding: onAir == nil ? Station.id(for: .personal) : nil, measures: measures)
                RadioStationShelf(title: "Artist stations", stations: artistStations, measures: measures)
                RadioStationShelf(title: "Genre stations", stations: genreStations, measures: measures)
                RadioStationShelf(title: "Decades", stations: decadeStations, measures: measures)
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
    /// One shelf on a wide page, as Linux's.
    private var genreAndDecadeStations: [Station] {
        mixes.stations.filter { Self.isGenre($0.seed) || Self.isDecade($0.seed) }
    }

    static func isArtist(_ seed: StationSeed) -> Bool {
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
/// a long press plays it. On a wide page tiles with the same facts, as
/// Linux's, the artists' stations among them, twelve at most.
private struct RadioStationList: View {
    /// The station shown above, not again here: Your Station while nothing
    /// is on the air (the iPhone's hero), the one on the air on a wide page.
    let hiding: String?
    let measures: HomeMeasures

    @Environment(RadioController.self) private var radio
    @Environment(MixStore.self) private var mixes
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history

    init(hiding: String?, measures: HomeMeasures) {
        self.hiding = hiding
        self.measures = measures
    }

    var body: some View {
        let stations = listed
        let dates = HomeShelves.stationDates(events: history.history.events)
        if measures.isWide {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle("Stations", measures: measures)
                Shelf(items: stations, width: measures.tile, margin: measures.margin) { station in
                    StationTileLink(station: station, fact: fact(station, dates))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader("Stations")
                VStack(spacing: 0) {
                    ForEach(stations) { station in
                        RadioStationRow(station: station, fact: fact(station, dates))
                    }
                }
            }
        }
    }

    /// Your Station off the air says what is played at this hour, as on
    /// Home; every station otherwise when it last played.
    private func fact(_ station: Station, _ dates: [String: Date]) -> String {
        if station.seed == .personal, radio.station?.id != station.id, let fact = radio.yourStationFact {
            return fact.text
        }
        return RelativeDay.played(dates[station.id])
    }

    private var listed: [Station] {
        var stations: [Station] = []
        stations.append(own(.personal))
        stations.append(own(.discovery))
        // Loved needs favourites to start from: the mixes leave it out when
        // there are none; before they are built, the library says.
        if let loved = built(.favorites) {
            stations.append(loved)
        } else if mixes.builtAt == nil && !library.favoriteTracks.isEmpty {
            stations.append(radio.station(for: .favorites))
        }
        var seen: Set<String> = []
        // The station shown above: not again here.
        if let hiding { seen.insert(hiding) }
        stations = stations.filter { seen.insert($0.id).inserted }
        for station in radio.recentStations where seen.insert(station.id).inserted {
            stations.append(station)
        }
        if measures.isWide {
            for station in mixes.stations where RadioFeed.isArtist(station.seed) && seen.insert(station.id).inserted {
                stations.append(station)
            }
            return Array(stations.prefix(12))
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
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
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
    let measures: HomeMeasures

    @Environment(MixStore.self) private var mixes

    init(title: String, stations: [Station], measures: HomeMeasures) {
        self.title = title
        self.stations = stations
        self.measures = measures
    }

    var body: some View {
        if !stations.isEmpty {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle(title, measures: measures)
                Shelf(items: stations, width: measures.tile, margin: measures.margin) { station in
                    // On a wide page what it draws from under its name, as
                    // Linux's tiles ("Rock from your library").
                    StationTileLink(station: station, fact: measures.isWide ? station.subtitle : nil)
                }
            }
        } else if mixes.stations.isEmpty && (mixes.isBuilding || mixes.builtAt == nil) {
            VStack(alignment: .leading, spacing: measures.belowHeading) {
                HomeSectionTitle(title, measures: measures)
                HomePlaceholderShelf(kind: .station, width: measures.tile, margin: measures.margin)
            }
        }
    }
}
