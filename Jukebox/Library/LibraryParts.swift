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
                Label("Loading your music", systemImage: "square.stack")
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
                            .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }
            }
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
        case .empty, .loaded:
            ContentUnavailableView {
                Label(emptyTitle, systemImage: emptySymbol)
            } description: {
                Text(message)
            }
        }
    }
}

/// The version filter over an album's or a playlist's songs: one glyph in
/// the page's actions, filled while a kind is off, whose menu has each kind
/// they hold (TrackVersion: Original first) as a check, on or off on its
/// own, the last one on staying on, and Show All. Shown only when they hold
/// two or more. "ik wil bijv alle unplugged nummers er uit kunnen filteren
/// of alle remastered als ze er zijn zeg maar?" (21 November 2026); the
/// row of segments it was "valt een beetje uit de boot, kun je er
/// misschien een icon knopje van maken met uit of aan togglen?" (22
/// November 2026). The choice is the page's, not kept. The menu stays open
/// while kinds are turned, as more than one may be.
struct LibraryVersionMenu: View {
    let kinds: [TrackVersion]
    /// The kinds turned off; none is all.
    @Binding var off: Set<TrackVersion>
    /// In a bar (the iPhone's): the bar's own size and ink.
    var inBar = false

    var body: some View {
        Menu {
            ForEach(kinds, id: \.self) { kind in
                Toggle(kind.name, isOn: Binding(get: { !off.contains(kind) },
                                                set: { _ in off = TrackVersion.toggle(kind, in: off, of: kinds) }))
            }
            Divider()
            Button("Show All") { off = [] }
                .disabled(off.isEmpty)
        } label: {
            if inBar {
                Label("Versions", systemImage: symbol)
            } else {
                Image(systemName: symbol)
                    .desktopFont(Tokens.Size.body15.size)
                    .foregroundStyle(off.isEmpty ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.accent))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
        }
        .menuActionDismissBehavior(.disabled)
        .modifier(PlainGlyphMenu(isPlain: !inBar))
        .accessibilityLabel("Versions")
        .accessibilityValue(off.isEmpty ? Text("All") : Text(kinds.filter { !off.contains($0) }.map(\.name).joined(separator: ", ")))
        .accessibilityIdentifier("page.versions")
    }

    private var symbol: String {
        off.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }
}

/// A head's glyph menu as MoreMenu draws it, without the Mac's pop-up
/// button around it; in a bar, the bar's own.
private struct PlainGlyphMenu: ViewModifier {
    let isPlain: Bool

    func body(content: Content) -> some View {
        if isPlain {
            content
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
        } else {
            content
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
/// On a wide page (`page`), the page's tiles (TileGrid).
struct LibraryAlbumGrid: View {
    let albums: [Album]
    var showsArtist = true
    var page: DesktopMeasures.Page?
    var width: CGFloat = 0

    var body: some View {
        if let page {
            TileGrid(items: albums, page: page, width: width) { album in
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

/// What can be done with an album: one menu for its tile and row
/// everywhere (Library, Home, Search) and its page's "…". `tracks`: the
/// album's songs when the caller has them (an album the library has not
/// indexed); else the library's. `onPage`: its page's "…", without Play,
/// which the page has as a button, and wide without Favorite, which is the
/// heart beside it.
struct LibraryAlbumMenu: View {
    let album: Album
    let tracks: [Track]?
    let includesGoToArtist: Bool
    let onPage: Bool

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.isWide) private var isWide

    init(album: Album, tracks: [Track]? = nil, includesGoToArtist: Bool = true, onPage: Bool = false) {
        self.album = album
        self.tracks = tracks
        self.includesGoToArtist = includesGoToArtist
        self.onPage = onPage
    }

    var body: some View {
        let songs = tracks ?? library.tracks(inAlbum: album.id)
        let favorite = library.isFavorite(album.id)
        // A song's groups (TrackMenu), as Linux's albumMenu; Play first on
        // a tile, which has no button for it.
        Section {
            if !onPage {
                Button("Play", systemImage: "play.fill") {
                    player.play(songs, context: QueueContext(.album(album.id), title: album.name))
                }
                .disabled(songs.isEmpty)
            }
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
            if !(onPage && isWide) {
                Button(favorite ? "Undo Favorite" : "Favorite", systemImage: favorite ? "heart.slash" : "heart") {
                    Task { await library.toggleFavorite(.album(album.id)) }
                }
            }
            if library.can(.rating) {
                RatingMenu(item: .album(album.id))
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "album", "from": "menu"])
                radio.start(.album(album.id))
            }
        }
        if includesGoToArtist, let artist = albumArtist {
            Section {
                Button("Go to Artist", systemImage: "music.mic") {
                    navigator.open(.artist(artist))
                }
            }
        }
        Section {
            CopyShareLinkButton(id: album.id, tracks: songs.map(\.id))
            ShareMenuItem(item: .album(album))
            DontCountToggle(kind: .album, id: album.id, name: album.name)
        }
    }

    private var albumArtist: Artist? {
        guard let ref = album.primaryArtist else { return nil }
        return library.artist(ref)
    }
}

/// Start Radio beside Play and Shuffle where a page has no "…" to hold it
/// (a genre's, on the iPhone): a word in the accent at their size.
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
                .font(.subheadline.weight(.semibold))
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

    /// "7 songs, 27 min", "12 songs, 1 hr 5 min": a wide page's head, as
    /// Linux's `length` says it, the minutes rounded.
    static func length(count: Int, duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        guard minutes > 0 else { return songs(count) }
        if minutes < 60 { return String(localized: "\(songs(count)), \(minutes) min") }
        return String(localized: "\(songs(count)), \(minutes / 60) hr \(minutes % 60) min")
    }

    static func totalDuration(_ tracks: [Track]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
}
