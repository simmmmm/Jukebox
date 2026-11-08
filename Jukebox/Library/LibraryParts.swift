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
    let emptyMessage: LocalizedStringKey

    @Environment(LibraryStore.self) private var library

    init(emptyTitle: LocalizedStringKey = "No Music", emptySymbol: String = "music.note",
         emptyMessage: LocalizedStringKey = "Your Jellyfin server has no music in its libraries yet.") {
        self.emptyTitle = emptyTitle
        self.emptySymbol = emptySymbol
        self.emptyMessage = emptyMessage
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
                Text(emptyMessage)
            }
        }
    }
}

/// A list's empty state: nothing found for the filter, or the library's status.
struct LibraryEmptyState: View {
    let query: String
    var emptyTitle: LocalizedStringKey = "No Music"
    var emptySymbol = "music.note"
    var emptyMessage: LocalizedStringKey = "Your Jellyfin server has no music in its libraries yet."

    var body: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LibraryStatusView(emptyTitle: emptyTitle, emptySymbol: emptySymbol, emptyMessage: emptyMessage)
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

/// Albums as Music's grid: as many columns of at least 150 points as fit.
struct LibraryAlbumGrid: View {
    let albums: [Album]
    var showsArtist = true

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.l, alignment: .top)],
                  alignment: .leading, spacing: Theme.Space.xl) {
            ForEach(albums) { album in
                LibraryAlbumLink(album: album, showsArtist: showsArtist)
            }
        }
        .padding(.horizontal, Theme.margin)
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
                Task { await library.toggleFavorite(album.id) }
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

/// The station button under a page's Play and Shuffle: grey, beside the one
/// filled button, with the radio's symbol.
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
            Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
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
            ArtworkView(playlist.artwork, size: 56, cornerRadius: Theme.Radius.thumbnail,
                        placeholder: "music.note.list")
            VStack(alignment: .leading, spacing: 2) {
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
            .navigationBarTitleDisplayMode(.inline)
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

    static func totalDuration(_ tracks: [Track]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
}
