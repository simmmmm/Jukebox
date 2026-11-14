// The pieces the library's screens share: what a screen shows while the
// library loads or when it has nothing, the album grid, an album's menu,
// the Start Radio button, a detail page's title that appears once its
// header has scrolled away, and the words for "12 songs, 48 minutes".
// Named Library… so they cannot clash with another part's own helpers.

import JukeboxKit
import SwiftUI

/// What a library screen shows when it has nothing to list: the first
/// load with its progress, the error with a way to try again, or that the
/// server has nothing of this kind.
struct LibraryStatusView: View {
    let emptyTitle: LocalizedStringKey
    let emptySymbol: String
    /// Nil: that the server has no music yet, naming its kind.
    let emptyMessage: LocalizedStringKey?

    @Environment(LibraryStore.self) private var library

    init(emptyTitle: LocalizedStringKey = "No Music", emptySymbol: String = "music.note",
         emptyMessage: LocalizedStringKey? = nil) {
        self.emptyTitle = emptyTitle
        self.emptySymbol = emptySymbol
        self.emptyMessage = emptyMessage
    }

    private var message: LocalizedStringKey {
        if let emptyMessage { return emptyMessage }
        return "Your \(library.serverKind) server has no music in its libraries yet."
    }

    var body: some View {
        switch library.state {
        case let .loading(progress):
            ContentUnavailableView {
                Label("Loading Your Library", systemImage: "square.stack")
            } description: {
                if let name = library.serverName {
                    Text("Reading the music on \(name). Next time the library opens at once.")
                } else {
                    Text("Next time the library opens at once.")
                }
            } actions: {
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
        case .empty, .loaded:
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(message)
            }
        }
    }
}

/// A list's empty state: nothing found for the filter, or the library's status.
struct LibraryEmptyState: View {
    let query: String
    var emptyTitle: LocalizedStringKey = "No Music"
    var emptySymbol = "music.note"
    var emptyMessage: LocalizedStringKey?

    var body: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LibraryStatusView(emptyTitle: emptyTitle, emptySymbol: emptySymbol, emptyMessage: emptyMessage)
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

/// Albums as Music's grid: as many columns of at least 150 points as fit.
/// On a wide page (`page`), the page's tiles (LibraryTileGrid).
struct LibraryAlbumGrid: View {
    let albums: [Album]
    var showsArtist = true
    var page: DesktopMeasures.Page?
    var width: CGFloat = 0

    var body: some View {
        if let page {
            LibraryTileGrid(items: albums, page: page, width: width) { album in
                LibraryAlbumLink(album: album, showsArtist: showsArtist)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.l, alignment: .top)],
                      alignment: .leading, spacing: Theme.Space.xl) {
                ForEach(albums) { album in
                    LibraryAlbumLink(album: album, showsArtist: showsArtist)
                }
            }
            .padding(.horizontal, Theme.margin)
        }
    }
}

/// An album's tile that opens it, with its menu on a long press.
struct LibraryAlbumLink: View {
    let album: Album
    var showsArtist = true

    var body: some View {
        NavigationLink(value: Route.album(album)) {
            AlbumTile(album: album, showsArtist: showsArtist)
        }
        .buttonStyle(.plain)
        .contextMenu {
            LibraryAlbumMenu(album: album)
        }
    }
}

/// What can be done with an album, in its long press and behind its "…".
/// `tracks`: the album's songs when the caller has them (an album the
/// library has not indexed); else the library's.
struct LibraryAlbumMenu: View {
    let album: Album
    let tracks: [Track]?
    let includesGoToArtist: Bool

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator

    init(album: Album, tracks: [Track]? = nil, includesGoToArtist: Bool = true) {
        self.album = album
        self.tracks = tracks
        self.includesGoToArtist = includesGoToArtist
    }

    var body: some View {
        let songs = tracks ?? library.tracks(inAlbum: album.id)
        let favorite = library.isFavorite(album.id)
        Section {
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "album", "from": "menu"])
                radio.start(.album(album.id))
            }
        }
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(songs)
            }
            .disabled(songs.isEmpty)
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.addToQueue(songs)
            }
            .disabled(songs.isEmpty)
        }
        Section {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: songs)
            }
            .disabled(songs.isEmpty)
            Button(favorite ? "Undo Favorite" : "Favorite", systemImage: favorite ? "heart.slash" : "heart") {
                Task { await library.toggleFavorite(.album(album.id)) }
            }
        }
        if includesGoToArtist, let artist = albumArtist {
            Section {
                Button("Go to Artist", systemImage: "music.mic") {
                    navigator.open(.artist(artist))
                }
            }
        }
    }

    private var albumArtist: Artist? {
        guard let ref = album.primaryArtist else { return nil }
        return library.artist(ref)
    }
}

/// The station button under a page's Play and Shuffle: a word in the
/// accent, beside the one filled button.
struct LibraryRadioButton: View {
    let seed: StationSeed

    @Environment(RadioController.self) private var radio

    init(seed: StationSeed) {
        self.seed = seed
    }

    var body: some View {
        Button {
            // "menu" too: a Start Radio of an album, artist, playlist or genre.
            Stats.track(.stationStarted, ["seed": Stats.seed(seed), "from": "menu"])
            radio.start(seed)
        } label: {
            Text("Start Radio")
        }
        .buttonStyle(.secondary)
    }
}

/// An artist in a list: their photo or initials, their name.
struct LibraryArtistRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ArtistAvatar(artist: artist, size: 44)
            Text(artist.name)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A playlist in a list: its cover, its name, how many songs.
struct LibraryPlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ArtworkView(playlist.artwork, size: 56, cornerRadius: Theme.Radius.artwork,
                        placeholder: "music.note.list")
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(playlist.name)
                    .lineLimit(1)
                if let count = playlist.trackCount {
                    Text(LibraryText.songs(count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A detail page's name in the navigation bar only once its own header
/// (which shows the name large) has scrolled away, as Music's album pages do.
struct LibraryScrolledTitle: ViewModifier {
    let title: String
    var threshold: CGFloat = 300

    @State private var isShown = false

    func body(content: Content) -> some View {
        let limit = threshold
        return content
            .navigationTitle(isShown ? title : "")
            .inlineTitle()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > limit
            } action: { _, isPast in
                isShown = isPast
            }
    }
}

extension View {
    func libraryScrolledTitle(_ title: String, after threshold: CGFloat = 300) -> some View {
        modifier(LibraryScrolledTitle(title: title, threshold: threshold))
    }
}

// MARK: - The wide page (the iPad's, the Mac's)
// As Linux's pages, 1:1 ("ik wil dat de linux app en de apple app 1:1 op
// elkaar lijken", the photographer, 14 November 2026): Linux/App/Pages.swift
// and Parts.swift, spec §5.

extension DesktopMeasures.Page {
    /// The page's margin, in points.
    var side: CGFloat { CGFloat(margin) }
    /// An album's, an artist's or a playlist's cover at the head of its
    /// page: 224, and 160 on a page under 720 (spec §5, Album).
    var cover: CGFloat { margin == 24 ? 160 : 224 }
}

extension View {
    /// The page's own width, for DesktopMeasures.page(width:): by the
    /// page's width, not the window's, the panel opened beside a page keeps
    /// its proportions (spec §5).
    func libraryPageWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { measured in
            width.wrappedValue = measured
        }
    }
}

/// A wide page: one scrolling column on the page's flat ground, and the
/// bar's title once the page's own has scrolled under it. Every library page
/// starts here, its title or head 24 under the bar at the page's margin, so
/// each starts where the others do (Linux's Artists once had a container of
/// its own and sat 24 higher: "artists heeft opeens een andere pagina
/// container als de andere?", 14 November 2026). `content` gets the page's
/// measures and its width.
struct LibraryWidePage<Content: View>: View {
    /// The bar's title, once the page's own has scrolled away.
    let title: String
    /// The page opens with a head (a cover, the title at its foot) rather
    /// than a title alone.
    var hasHead = false
    let content: (DesktopMeasures.Page, CGFloat) -> Content

    /// The default row of the table until the page has been measured.
    @State private var width: CGFloat = 1000

    // Spelled out: the private state would make the memberwise one private.
    init(title: String, hasHead: Bool = false,
         @ViewBuilder content: @escaping (DesktopMeasures.Page, CGFloat) -> Content) {
        self.title = title
        self.hasHead = hasHead
        self.content = content
    }

    var body: some View {
        let page = DesktopMeasures.page(width: Int(width))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content(page, width)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 40)
        }
        .pageGround()
        .libraryPageWidth($width)
        // The title's foot: 24 under the bar and 48 tall, or the cover's.
        .libraryScrolledTitle(title, after: hasHead ? page.cover + Theme.Space.xl : 72)
    }
}

/// A wide page's title in the serif, 40, 24 under the bar; at most one fact
/// under it, 4 below. The caller puts it on the page's margin.
struct LibraryPageTitle: View {
    let title: String
    var fact: String?

    init(_ title: String, fact: String? = nil) {
        self.title = title
        self.fact = fact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .libraryFont(40, design: .serif)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let fact, !fact.isEmpty {
                Text(fact)
                    .libraryFont(13)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Theme.Space.xl)
    }
}

/// A section's heading on a wide page: sentence case in the serif, 24, a
/// fact beside it; 40 above it and 16 to what it heads (8 to rows).
struct LibrarySectionTitle: View {
    let title: String
    var above: CGFloat = 40
    var below: CGFloat = Theme.Space.l

    init(_ title: String, above: CGFloat = 40, below: CGFloat = Theme.Space.l) {
        self.title = title
        self.above = above
        self.below = below
    }

    var body: some View {
        Text(title)
            .libraryFont(24, design: .serif)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, above)
            .padding(.bottom, below)
    }
}

/// What a wide page says when it has nothing: one plain line of what to
/// do, 24 under the title, on the margin, not a status page in the middle
/// ("favourites heeft een vage empty state", the photographer, 14 November
/// 2026). While the library is still loading, or could not, its status in
/// place of the line: the progress, Try Again.
struct LibraryEmptyLine: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch library.state {
        case .loading, .failed:
            LibraryStatusView()
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
        case .empty, .loaded:
            LibraryPlainLine(text)
        }
    }
}

/// One plain line in 15 at 60%, 24 under what is above it.
struct LibraryPlainLine: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .libraryFont(15)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.Space.xl)
    }
}

/// Tiles as Linux's grid (GtkGridView): as many columns as the page's tile
/// and its 24 of gap fit, sharing the width evenly, each tile at its
/// column's start, from the page's margin. Each tile carries its gap at its
/// end, so the last column's sits in the right margin.
struct LibraryTileGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let page: DesktopMeasures.Page
    let width: CGFloat
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        let size = CGFloat(page.tile)
        let gap = Theme.Space.xl
        // At least one: the first pass may measure nothing.
        let count = max(1, Int((width - 2 * page.side + gap) / (size + gap)))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .topLeading), count: count),
                  alignment: .leading, spacing: gap) {
            ForEach(items) { item in
                tile(item)
                    .frame(width: size)
            }
        }
        .padding(.leading, page.side)
        .padding(.trailing, page.side - gap)
    }
}

/// The head of an album's, an artist's, a playlist's or a genre's page
/// (spec §5, Album; Linux's Pages.heading): the cover at the left, and 32
/// beside it, at its foot, the title in the serif 40, the lead (an album's
/// artist) in 17, the facts in 13, and 24 under them the one Play and the
/// rest, 16 apart. 24 under the bar, on the page's margin.
struct LibraryHead<Art: View, Actions: View>: View {
    let page: DesktopMeasures.Page
    let title: String
    var lead: String?
    /// The lead as a link: an album's artist opens their page.
    var leadAction: (() -> Void)?
    let facts: String
    @ViewBuilder let art: (CGFloat) -> Art
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xxl) {
            art(page.cover)
                .frame(width: page.cover, height: page.cover)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .libraryFont(40, design: .serif)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                if let lead, !lead.isEmpty {
                    Group {
                        if let leadAction {
                            Button(action: leadAction) {
                                Text(lead)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows the artist")
                        } else {
                            Text(lead)
                        }
                    }
                    .libraryFont(17)
                    .lineLimit(1)
                    .padding(.top, Theme.Space.xs)
                }
                if !facts.isEmpty {
                    Text(facts)
                        .libraryFont(13)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, Theme.Space.xs)
                }
                HStack(spacing: Theme.Space.l) {
                    actions
                }
                .padding(.top, Theme.Space.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Theme.Space.xl)
        .padding(.horizontal, page.side)
    }
}

/// The hairline 32 under a head and 24 over its rows.
struct LibraryRule: View {
    let page: DesktopMeasures.Page

    var body: some View {
        Hairline(inset: 0)
            .padding(.top, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.xl)
            .padding(.horizontal, page.side)
    }
}

/// A head's Play, the page's one filled button, and Shuffle, a word in the
/// accent beside it (Linux's playButton and wordButton): 15 bold.
struct LibraryPlayButtons: View {
    let play: () -> Void
    var shuffle: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Button(action: play) {
                Text("Play")
                    .libraryFont(15, weight: .bold)
            }
            .buttonStyle(.prominent)
            .fixedSize()
            if let shuffle {
                LibraryWordButton("Shuffle", action: shuffle)
            }
        }
    }
}

/// Every other action on a wide page: a word in the accent, 15 bold.
struct LibraryWordButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .libraryFont(15, weight: .bold)
        }
        .buttonStyle(.secondary)
        .fixedSize()
    }
}

/// A head's heart, 32: filled and in the accent when given.
struct LibraryHeartButton: View {
    let item: ItemRef

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let given = library.isFavorite(item.id)
        Button {
            Task { await library.toggleFavorite(item) }
        } label: {
            Image(systemName: given ? "heart.fill" : "heart")
                .libraryFont(15)
                .foregroundStyle(given ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(given ? Text("Undo Favorite") : Text("Favorite"))
    }
}

/// A head's "…", 32: the rest of what can be done with what the page shows.
/// A plain glyph, without the Mac's pop-up button around it.
struct LibraryMoreMenu<Items: View>: View {
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis")
                .libraryFont(15, weight: .semibold)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }
}

/// Songs as rows on a wide page (TrackRow's wide form), on the margin the
/// caller gives; a click plays from that song.
struct LibraryTrackRows: View {
    let tracks: [Track]
    var numbered = false
    var subtitle: (Track) -> String? = { $0.artistLine }
    let play: (Track) -> Void

    @Environment(AudioPlayer.self) private var player

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(tracks) { track in
                Button {
                    // Offline, a song not on the device says why rather than play.
                    guard !player.refusesOffline(track) else { return }
                    play(track)
                } label: {
                    TrackRow(track, leading: numbered ? .number(track.trackNumber) : .artwork,
                             subtitle: subtitle(track))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

enum LibraryText {
    /// "1 song", "12 songs".
    static func songs(_ count: Int) -> String {
        count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
    }

    /// "12 songs, 48 minutes".
    static func summary(count: Int, duration: TimeInterval) -> String {
        let spoken = duration.spoken
        return duration >= 60 && !spoken.isEmpty ? "\(songs(count)), \(spoken)" : songs(count)
    }

    static func totalDuration(_ tracks: [Track]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
}
