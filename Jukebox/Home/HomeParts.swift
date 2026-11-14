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
/// §5), so the panel opened beside it leaves the page its proportions.
struct HomeMeasures {
    /// The table's row; nil on the iPhone.
    let page: DesktopMeasures.Page?

    init(isWide: Bool, width: Int) {
        page = isWide ? DesktopMeasures.page(width: width) : nil
    }

    var isWide: Bool { page != nil }
    var margin: CGFloat { page.map { CGFloat($0.margin) } ?? Theme.margin }
    var tile: CGFloat { page.map { CGFloat($0.tile) } ?? HomeLayout.tileWidth }
    /// Played lately's columns.
    var columns: Int { page?.columns ?? 1 }
    /// A mix's or a station's art at the head of its page, as an album's
    /// cover (spec §5): 224, and 160 on a page under 720.
    var cover: CGFloat { page?.margin == 24 ? 160 : 224 }
    /// From a section's heading to what it heads.
    var belowHeading: CGFloat { isWide ? Theme.Space.l : Theme.Space.m }
    /// From one section to the next: 40 on a wide page (spec §5).
    var betweenSections: CGFloat { isWide ? Theme.Space.xxl + Theme.Space.s : Theme.Space.xl }

    /// A page's head in its List: 24 under the bar on a wide page, at its
    /// margin; as the iPhone's has it otherwise.
    var headInsets: EdgeInsets {
        isWide
            ? EdgeInsets(top: Theme.Space.xl, leading: margin, bottom: Theme.Space.l, trailing: margin)
            : EdgeInsets(top: Theme.Space.l, leading: Theme.margin, bottom: Theme.Space.l, trailing: Theme.margin)
    }

    /// A song's row in a page's List on a wide page: the page's margin, and
    /// 8 above and below, so a row with its cover of 48 is 64 (spec §8).
    /// nil: the List's own, the iPhone's.
    var rowInsets: EdgeInsets? {
        isWide ? EdgeInsets(top: Theme.Space.s, leading: margin, bottom: Theme.Space.s, trailing: margin) : nil
    }
}

extension View {
    /// The page's own width into `width`, for HomeMeasures: the page's,
    /// not the window's.
    func homePageWidth(_ width: Binding<Int>) -> some View {
        onGeometryChange(for: Int.self) { proxy in
            Int(proxy.size.width)
        } action: { measured in
            width.wrappedValue = measured
        }
    }

    /// A title in the serif at a size of the designer's (spec §7: 40 a
    /// page's, 32 the station on air, 24 a section's), following the
    /// reader's text size as the large title does. The text styles' own
    /// sizes are the iPhone's; the Mac's are far smaller, and the titles
    /// there would no longer read as a sleeve's.
    func homeSerif(_ size: CGFloat) -> some View {
        modifier(HomeSerif(size: size))
    }

    /// A wide page's title is its own, in the serif in the content; the bar
    /// shows it small once that has scrolled away (spec §5). The iPhone's
    /// is the bar's large title, as before.
    func homeTitle(_ title: String, isScrolled: Bool) -> some View {
        modifier(HomeTitled(title: title, isScrolled: isScrolled))
    }
}

private struct HomeSerif: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .regular, design: .serif))
    }
}

private struct HomeTitled: ViewModifier {
    let title: String
    let isScrolled: Bool

    @Environment(\.isWide) private var isWide

    @ViewBuilder
    func body(content: Content) -> some View {
        if isWide {
            content
                .navigationTitle(isScrolled ? title : "")
                .inlineTitle()
        } else {
            content
                .navigationTitle(title)
                .largeTitle()
        }
    }
}

/// A wide page's own title (spec §5): the serif at 40, at the margin. The
/// bar's title takes over once it has scrolled past `scrolledPast`.
struct HomePageTitle: View {
    let title: String
    let measures: HomeMeasures

    /// Its foot: 24 under the bar, 48 tall.
    static let scrolledPast: CGFloat = 72

    init(_ title: String, measures: HomeMeasures) {
        self.title = title
        self.measures = measures
    }

    var body: some View {
        Text(title)
            .homeSerif(40)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, measures.margin)
    }
}

/// A section's heading: on a wide page the serif at 24 with its fact beside
/// it, as Linux has it, at the page's margin; on the iPhone SectionHeader,
/// as before.
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(title)
                    .homeSerif(24)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                if let fact {
                    Text(fact)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let route {
                    NavigationLink(value: route) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("See All \(title)"))
                }
            }
            .padding(.horizontal, measures.margin)
        } else {
            SectionHeader(title, fact: fact, route: route)
        }
    }
}

/// The head of a mix's or a station's page on a wide page, as Linux's
/// album head (spec §5): the art at the left, 32, and at its foot the title
/// in the serif, a line of who, the facts, and 24 under them the one Play
/// and the rest as words, 16 apart. Library's pages have no head of their own to
/// share yet; this one is Home's and Radio's.
struct HomeDetailHead<Art: View, Actions: View>: View {
    let title: String
    let lead: String?
    let facts: String
    let art: Art
    let actions: Actions

    init(title: String, lead: String? = nil, facts: String,
         @ViewBuilder art: () -> Art, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.lead = lead
        self.facts = facts
        self.art = art()
        self.actions = actions()
    }

    var body: some View {
        // The hairline 32 under it, from the margin, under the art too.
        VStack(alignment: .leading, spacing: Theme.Space.xxl) {
            head
            Hairline(inset: 0)
        }
    }

    private var head: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xxl) {
            art
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                    .homeSerif(40)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                if let lead, !lead.isEmpty {
                    Text(lead)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: Theme.Space.l) {
                    actions
                }
                .padding(.top, Theme.Space.xl - Theme.Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Label("Could Not Load Your Library", systemImage: "exclamationmark.triangle")
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
                Label("No Music Yet", systemImage: "music.note")
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
                    .font(.headline)
                Text("The first time takes a moment. After that, Jukebox opens at once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let progress {
                VStack(spacing: Theme.Space.s) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.footnote)
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
            if let fact {
                VStack(alignment: .leading, spacing: 0) {
                    StationCard(station: station)
                    Text(fact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
            } else {
                StationCard(station: station)
            }
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
        Section {
            if radio.stationOnAir(player: player)?.seed == station.seed {
                Button("Show Now Playing", systemImage: "play.circle") {
                    navigator.isNowPlayingPresented = true
                }
            } else {
                Button("Play Station", systemImage: "play.fill") {
                    Stats.track(.stationStarted, ["seed": Stats.seed(station.seed), "from": "tile_menu"])
                    radio.start(station)
                }
            }
            Button("Show Station", systemImage: "dot.radiowaves.left.and.right") {
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
                    .font(.subheadline.weight(.medium))
                Text("Artists you love and more")
                    .font(.subheadline)
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

/// What can be done with a mix, as Music orders it for a playlist.
struct HomeMixMenu: View {
    let mix: Mix

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator

    init(mix: Mix) {
        self.mix = mix
    }

    var body: some View {
        Section {
            Button("Play", systemImage: "play.fill") {
                player.playMix(mix)
            }
            Button("Shuffle", systemImage: "shuffle") {
                player.playMix(mix, shuffled: true)
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": Stats.seed(mix.stationSeed), "from": "menu"])
                radio.start(mix.stationSeed)
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
        }
    }
}

/// An album's tile that opens it; a long press plays it or starts its station.
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
/// play it, shuffle it, or start its station.
struct HomeAlbumMenu: View {
    let album: Album

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library

    init(album: Album) {
        self.album = album
    }

    var body: some View {
        Section {
            Button("Play", systemImage: "play.fill") {
                play(shuffled: false)
            }
            Button("Shuffle", systemImage: "shuffle") {
                play(shuffled: true)
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "album", "from": "menu"])
                radio.start(.album(album.id))
            }
        }
    }

    private func play(shuffled: Bool) {
        let tracks = library.tracks(inAlbum: album.id)
        player.play(tracks, context: QueueContext(.album(album.id), title: album.name), shuffled: shuffled)
    }
}
