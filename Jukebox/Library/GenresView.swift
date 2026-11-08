// Genres: every music genre on the server, and a genre's page — Play and
// Shuffle of its songs, its station, its albums. Counts are the library's
// own songs in the genre (a track's tags and its album's), not the server's.

import JukeboxKit
import SwiftUI

struct GenresView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let genres = term.isEmpty ? library.genres : library.genres.filter { $0.name.localizedStandardContains(term) }
        List {
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

    var body: some View {
        let tracks = library.tracks(inGenre: genre)
        let albums = library.albums(inGenre: genre)
        ScrollView {
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
