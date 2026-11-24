// The pieces Home and Radio share (which station is on the air is
// RadioController.stationOnAir, shared with Linux): what a tab
// shows while the library loads or when it has nothing, a station's tile
// that opens its page and its long-press menu, a station's kind in words,
// the grey placeholders a shelf shows while the mixes are being made, and a
// mix's tile and menu.
// Named Home… or Station… so they cannot clash with another part's helpers.

import JukeboxKit
import SwiftUI

extension AudioPlayer {
    /// A mix from `index`, named after the mix in Now Playing ("Playing
    /// from 1990s Rock").
    func playMix(_ mix: Mix, from index: Int = 0, shuffled: Bool = false) {
        // Which kind of mix is played (Stats): its kind, never its title.
        Stats.track(.mixPlayed, ["kind": mix.kind.rawValue])
        play(mix.tracks, startingAt: index, context: QueueContext(.mix(mix.id), title: mix.title), shuffled: shuffled)
    }
}

enum HomeText {
    /// "1 song", "25 songs".
    static func songs(_ count: Int) -> String {
        count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
    }

    /// "25 songs, 1 hour, 42 minutes"; the songs alone under a minute.
    static func summary(count: Int, duration: TimeInterval) -> String {
        let spoken = duration.spoken
        return duration >= 60 && !spoken.isEmpty ? "\(songs(count)), \(spoken)" : songs(count)
    }
}

// MARK: - A wide page's measures

/// How Home, Radio and a mix's or a station's page lay out: the iPhone by
/// its own numbers, as before; a wide page (the iPad, the Mac) by the
/// designer's table, by the page's own width (DesktopMeasures.page, spec
/// §5), so the panel opened beside it leaves the page its proportions. The
/// wide page's parts themselves are WidePage.swift's, every page's.
struct HomeMeasures {
    /// The table's row; nil on the iPhone.
    let page: DesktopMeasures.Page?

    init(page: DesktopMeasures.Page?) {
        self.page = page
    }

    init(isWide: Bool, width: CGFloat) {
        page = isWide ? DesktopMeasures.page(width: Int(width)) : nil
    }

    var isWide: Bool { page != nil }
    var margin: CGFloat { page?.side ?? Theme.margin }
    var tile: CGFloat { page.map { CGFloat($0.tile) } ?? HomeLayout.tileWidth }
    /// Played lately's columns.
    var columns: Int { page?.columns ?? 1 }
    /// From a section's heading to what it heads.
    var belowHeading: CGFloat { isWide ? Theme.Space.l : Theme.Space.m }
    /// From one section to the next: 40 on a wide page (spec §5).
    var betweenSections: CGFloat { isWide ? Theme.Space.xxl + Theme.Space.s : Theme.Space.xl }

    /// A page's head in its List: none of its own on a wide page, where
    /// PageHead keeps its own measures; as the iPhone's has it otherwise.
    var headInsets: EdgeInsets {
        isWide
            ? EdgeInsets()
            : EdgeInsets(top: Theme.Space.l, leading: Theme.margin, bottom: Theme.Space.l, trailing: Theme.margin)
    }
}

extension View {
    /// The iPhone's large title, as before. A wide page's title is its own
    /// (WidePage), in the serif in the content.
    func homeTitle(_ title: String) -> some View {
        modifier(HomeTitled(title: title))
    }
}

private struct HomeTitled: ViewModifier {
    let title: String

    @Environment(\.isWide) private var isWide

    @ViewBuilder
    func body(content: Content) -> some View {
        if isWide {
            content
        } else {
            content
                .navigationTitle(title)
                .largeTitle()
        }
    }
}

/// A section's heading: on a wide page Linux's (PageSectionTitle), at the
/// page's margin, the space around it the page's own; on the iPhone
/// SectionHeader, as before.
struct HomeSectionTitle: View {
    let title: String
    var fact: String?
    var route: Route?
    let measures: HomeMeasures

    init(_ title: String, fact: String? = nil, route: Route? = nil, measures: HomeMeasures) {
        self.title = title
        self.fact = fact
        self.route = route
        self.measures = measures
    }

    var body: some View {
        if measures.isWide {
            PageSectionTitle(title, fact: fact, above: 0, below: 0)
                .padding(.horizontal, measures.margin)
        } else {
            SectionHeader(title, fact: fact, route: route)
        }
    }
}

// MARK: - The library's state, where a tab has nothing to show yet

/// Home's and Radio's page before there is music: the first load with its
/// progress, the error with a way to try again, or a server with no music.
struct HomeLibraryStatus: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch library.state {
        case .empty:
            // Signed in a moment ago: the load is about to start.
            HomeLoadingView(progress: nil)
        case let .loading(progress):
            HomeLoadingView(progress: progress)
        case let .failed(message):
            ContentUnavailableView {
                Label("Could not load your music", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await library.refresh() }
                }
                .buttonStyle(.prominent)
                .fixedSize()
            }
        case .loaded:
            ContentUnavailableView {
                Label("No music yet", systemImage: "music.note")
            } description: {
                Text("Your \(library.serverKind) server has no music in its libraries yet. Add some there, then check again.")
            } actions: {
                Button("Check Again") {
                    Task { await library.refresh() }
                }
                .buttonStyle(.secondary)
                .fixedSize()
            }
        }
    }
}

/// The first load: the mark, flat, the words, and the bar when the server
/// has said how much there is.
struct HomeLoadingView: View {
    let progress: Double?

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ArchMark(size: 48)
            VStack(spacing: Theme.Space.xs) {
                Text("Loading your library…")
                    .desktopFont(Tokens.Size.body17.size, weight: .semibold, phone: .headline)
                Text("The first time takes a moment. After that, Jukebox opens at once.")
                    .desktopFont(Tokens.Size.body15.size, phone: .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let progress {
                VStack(spacing: Theme.Space.s) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .padding(Theme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stations

/// What kind of station it is, as a fact under a station's name on its
/// page: "Artist station", "Your Station" says what it is by its name.
enum StationText {
    static func kind(_ station: Station) -> String {
        switch station.seed {
        case .track: String(localized: "Song station")
        case .artist: String(localized: "Artist station")
        case .album: String(localized: "Album station")
        case .genre: String(localized: "Genre station")
        case .decade: String(localized: "Decade station")
        case .collection: String(localized: "Playlist station")
        case .personal: String(localized: "From your listening")
        case .discovery: String(localized: "New to you")
        case .favorites: String(localized: "From your favorites")
        }
    }
}

/// A station's tile: it opens the station's page, where what the radio
/// made of it can be seen before it plays. The photographer, 8 November
/// 2026: "Als je nu klikt op een tegel van radio begint er meteen van alles
/// te spelen ipv dat je kan zien wat je van de playlist gemaakt hebt." A
/// long press plays it at once. The one on the air opens its page too,
/// which then shows what plays and what comes next; its art is the one lit.
struct StationTileLink: View {
    let station: Station
    /// A fact under its name ("Played Thursday"): Radio's Stations on a
    /// wide page, as Linux's tiles have it.
    let fact: String?

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player

    init(station: Station, fact: String? = nil) {
        self.station = station
        self.fact = fact
    }

    var body: some View {
        let onAir = radio.stationOnAir(player: player)?.seed == station.seed
        NavigationLink(value: Route.station(station)) {
            // The fact under the name in the tile itself, as Linux's.
            StationCard(station: station, fact: fact)
        }
        .buttonStyle(.plain)
        .contextMenu {
            StationMenu(station: station)
        }
        .accessibilityAddTraits(onAir ? .isSelected : [])
        .accessibilityHint(Text("Shows the station and what it would play"))
    }
}

/// A station's long press, on its tile and its card: play it now, without
/// looking first, or see its page. The station on the air offers Now
/// Playing instead of Play: playing it again would start it over.
struct StationMenu: View {
    let station: Station

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator

    init(station: Station) {
        self.station = station
    }

    var body: some View {
        items
            .menuIcons()
    }

    @ViewBuilder private var items: some View {
        Section {
            if radio.stationOnAir(player: player)?.seed == station.seed {
                // Full Player in the wide window, where the panel is Now
                // Playing (the photographer, 15 November 2026); the iPhone's
                // screen keeps its name.
                Button(navigator.isWide ? String(localized: "Show Full Player") : String(localized: "Show Now Playing"), systemImage: "play.circle") {
                    navigator.isNowPlayingPresented = true
                }
            } else {
                Button("Play Station", systemImage: "play.fill") {
                    Stats.track(.stationStarted, ["seed": Stats.seed(station.seed), "from": "tile_menu"])
                    radio.start(station)
                }
            }
        }
        Section {
            // "Go to", as Go to Album and Linux's card.
            Button("Go to Station", systemImage: "dot.radiowaves.left.and.right") {
                navigator.open(.station(station))
            }
        }
    }
}

// MARK: - Placeholders

struct HomePlaceholder: Identifiable {
    let id: Int
}

/// A shelf of grey tiles while the mixes and stations are being made, so
/// Home does not jump when they arrive.
struct HomePlaceholderShelf: View {
    enum Kind {
        case mix
        case station
    }

    let kind: Kind
    var width: CGFloat = 160
    var margin: CGFloat = Theme.margin

    var body: some View {
        Shelf(items: Self.items, width: width, margin: margin) { _ in
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                Text("1990s Rock")
                    .desktopFont(Tokens.Size.body15.size, weight: .medium, phone: .subheadline.weight(.medium))
                Text("Artists you love and more")
                    .desktopFont(Tokens.Size.fact13.size, phone: .subheadline)
            }
            .redacted(reason: .placeholder)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .mix ? Text("Making your mixes") : Text("Finding your stations"))
    }

    private static let items = (0..<5).map { HomePlaceholder(id: $0) }
}

// MARK: - Mixes and albums on a shelf

/// A mix's card that opens it, with what can be done with it on a long press.
struct HomeMixLink: View {
    let mix: Mix

    var body: some View {
        NavigationLink(value: Route.mix(mix)) {
            MixCard(mix: mix)
        }
        .buttonStyle(.plain)
        .contextMenu {
            HomeMixMenu(mix: mix)
        }
    }
}

/// What can be done with a mix, in a song's sections (SYSTEM.md, Menus),
/// as Linux's: Play and Shuffle first, as a tile has no buttons for them.
struct HomeMixMenu: View {
    let mix: Mix

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator

    init(mix: Mix) {
        self.mix = mix
    }

    var body: some View {
        items
            .menuIcons()
    }

    @ViewBuilder private var items: some View {
        Section {
            Button("Play", systemImage: "play.fill") {
                player.playMix(mix)
            }
            Button("Shuffle", systemImage: "shuffle") {
                player.playMix(mix, shuffled: true)
            }
        }
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(mix.tracks)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.addToQueue(mix.tracks)
            }
        }
        Section {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: mix.tracks)
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": Stats.seed(mix.stationSeed), "from": "menu"])
                radio.start(mix.stationSeed)
            }
        }
    }
}

/// An album's tile that opens it; a long press has the album's menu.
struct HomeAlbumLink: View {
    let album: Album

    init(album: Album) {
        self.album = album
    }

    var body: some View {
        NavigationLink(value: Route.album(album)) {
            AlbumTile(album: album)
        }
        .buttonStyle(.plain)
        .contextMenu {
            HomeAlbumMenu(album: album)
        }
    }
}

/// An album's long press, on a shelf's tile and on Played lately's row:
/// the one album menu every tile and row has (LibraryAlbumMenu), as
/// Linux's albumMenu everywhere.
struct HomeAlbumMenu: View {
    let album: Album

    init(album: Album) {
        self.album = album
    }

    var body: some View {
        LibraryAlbumMenu(album: album)
    }
}
