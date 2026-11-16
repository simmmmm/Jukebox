// Genres: every genre in the library's tags, and a genre's page — Play and
// Shuffle of its songs, its station, its albums. A tag that joins several
// ("Rock; Shoegaze") is listed as each of them, as the radio counts them
// (LibraryIndex), so there is one Rock and one Shoegaze. Counts are the
// library's own songs in the genre, not the server's.
//
// A genre's page reads only the library, never the server by the genre's
// id: a genre the server has no item of exactly that name for has an id
// of the app's own ("genre:shoegaze").
//
// In a wide window, as the other library pages and as Linux's: the
// genres as a grid of tiles, each the covers of its first four albums, and
// a genre's page with that collage as its head's cover, the albums in tiles.

import JukeboxKit
import SwiftUI

struct GenresView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.isWide) private var isWide
    @State private var query = ""

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    private var wide: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let genres = term.isEmpty ? library.genres : library.genres.filter { $0.name.localizedStandardContains(term) }
        return WidePage(title: "Genres") { page, width in
            PageTitle("Genres")
                .padding(.horizontal, page.side)
            if genres.isEmpty {
                Group {
                    if term.isEmpty {
                        PageEmptyLine("The genres in your music’s tags appear here.")
                    } else {
                        PagePlainLine("Nothing in Genres matches “\(term)”.")
                    }
                }
                .padding(.horizontal, page.side)
            } else {
                TileGrid(items: genres, page: page, width: width) { genre in
                    NavigationLink(value: Route.genre(genre)) {
                        WideTile(name: genre.name, line: LibraryText.songs(count(of: genre))) {
                            LibraryGenreArt(genre: genre)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, Theme.Space.xl)
            }
        }
        // No find field when wide: Linux's pages have none, Search is a place.
        .refreshable { await library.refresh() }
    }

    private var compact: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let genres = term.isEmpty ? library.genres : library.genres.filter { $0.name.localizedStandardContains(term) }
        return List {
            ForEach(genres) { genre in
                NavigationLink(value: Route.genre(genre)) {
                    LabeledContent {
                        Text(LibraryText.songs(count(of: genre)))
                    } label: {
                        Text(genre.name)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Genres")
        .searchable(text: $query, prompt: "Find in Genres")
        .overlay {
            if genres.isEmpty {
                LibraryEmptyState(query: query, emptyTitle: "No Genres", emptySymbol: "guitars",
                                  emptyMessage: "The genres in your music’s tags appear here.")
            }
        }
        .refreshable { await library.refresh() }
    }

    private func count(of genre: Genre) -> Int {
        let own = library.trackCount(inGenre: genre)
        return own > 0 ? own : (genre.songCount ?? 0)
    }
}

struct GenreDetailView: View {
    let genre: Genre

    init(genre: Genre) {
        self.genre = genre
    }

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    /// As an album's page: the collage, the name at its foot, how many songs
    /// and how long, Play, Shuffle and "…" (Start Radio); then its albums.
    private var wide: some View {
        let tracks = library.tracks(inGenre: genre)
        let albums = library.albums(inGenre: genre)
        return WidePage(title: genre.name, hasHead: true) { page, width in
            PageHead(page: page, title: genre.name,
                     facts: tracks.isEmpty ? String(localized: "No songs in the library carry this genre.")
                         : LibraryText.length(count: tracks.count, duration: LibraryText.totalDuration(tracks))) { _ in
                LibraryGenreArt(genre: genre)
            } actions: {
                PagePlayButtons(play: { play(tracks, shuffled: false) },
                                shuffle: { play(tracks, shuffled: true) })
                    .disabled(tracks.isEmpty)
                MoreMenu {
                    Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                        let seed = StationSeed.genre(key: genre.key, name: genre.name)
                        Stats.track(.stationStarted, ["seed": Stats.seed(seed), "from": "menu"])
                        radio.start(seed)
                    }
                }
                .disabled(tracks.isEmpty)
            }
            if !albums.isEmpty {
                PageSectionTitle(String(localized: "Albums"))
                    .padding(.horizontal, page.side)
                LibraryAlbumGrid(albums: albums, page: page, width: width)
            }
        }
    }

    private var compact: some View {
        let tracks = library.tracks(inGenre: genre)
        let albums = library.albums(inGenre: genre)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text(LibraryText.summary(count: tracks.count, duration: LibraryText.totalDuration(tracks)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    PlayShuffleButtons(play: { play(tracks, shuffled: false) },
                                       shuffle: { play(tracks, shuffled: true) })
                    LibraryRadioButton(seed: .genre(key: genre.key, name: genre.name))
                }
                .disabled(tracks.isEmpty)
                .padding(.horizontal, Theme.margin)

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader("Albums")
                        LibraryAlbumGrid(albums: albums)
                    }
                }
            }
            .padding(.vertical, Theme.Space.l)
        }
        .navigationTitle(genre.name)
        .overlay {
            if tracks.isEmpty && albums.isEmpty {
                LibraryStatusView(emptyTitle: "Nothing in \(genre.name)", emptySymbol: "guitars",
                                  emptyMessage: "No songs in the library carry this genre.")
            }
        }
    }

    private func play(_ tracks: [Track], shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        player.play(tracks, context: QueueContext(.genre(genre.name), title: genre.name), shuffled: shuffled)
    }
}

/// A genre's art on a wide page: the covers of its first four albums.
struct LibraryGenreArt: View {
    let genre: Genre

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let covers = Array(library.albums(inGenre: genre).lazy.compactMap(\.artwork).prefix(4))
        if covers.isEmpty {
            ArtworkView(nil, placeholder: "guitars")
        } else {
            CollageArtwork(artworks: covers)
        }
    }
}
