// Favorites: the songs, albums and artists the listener has hearted, in
// Jellyfin (so every Jellyfin app shares them), one kind at a time. Spelled
// as Apple's Music spells it, "Favorite", in every string the listener sees.

import JukeboxKit
import SwiftUI

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @AppStorage("library.favoritesKind") private var kind: LibraryFavoritesKind = .songs

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $kind) {
                    Text("Songs").tag(LibraryFavoritesKind.songs)
                    Text("Albums").tag(LibraryFavoritesKind.albums)
                    Text("Artists").tag(LibraryFavoritesKind.artists)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.Space.s)
                .background(.bar)
            }
            .navigationTitle("Favorites")
            .refreshable { await library.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .songs: songs
        case .albums: albums
        case .artists: artists
        }
    }

    private var songs: some View {
        let favorites = library.favoriteTracks
        return List {
            if !favorites.isEmpty {
                Button {
                    player.play(favorites, context: context, shuffled: true)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.body.weight(.semibold))
                }
            }
            ForEach(favorites) { track in
                Button {
                    guard !player.refusesOffline(track) else { return }
                    let i = favorites.firstIndex(where: { $0.id == track.id }) ?? 0
                    player.play(favorites, startingAt: i, context: context)
                } label: {
                    TrackRow.standard(track)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .overlay {
            if favorites.isEmpty {
                ContentUnavailableView("No Favorite Songs", systemImage: "heart",
                                       description: Text("Touch and hold a song, then choose Favorite."))
            }
        }
    }

    private var albums: some View {
        let favorites = library.favoriteAlbums
        return ScrollView {
            LibraryAlbumGrid(albums: favorites)
                .padding(.vertical, Theme.Space.l)
        }
        .overlay {
            if favorites.isEmpty {
                ContentUnavailableView("No Favorite Albums", systemImage: "heart",
                                       description: Text("Touch and hold an album, then choose Favorite."))
            }
        }
    }

    private var artists: some View {
        let favorites = library.favoriteArtists
        return List {
            ForEach(favorites) { artist in
                NavigationLink(value: Route.artist(artist)) {
                    LibraryArtistRow(artist: artist)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if favorites.isEmpty {
                ContentUnavailableView("No Favorite Artists", systemImage: "heart",
                                       description: Text("On an artist’s page, choose Favorite in the … menu."))
            }
        }
    }

    private var context: QueueContext {
        QueueContext(.favorites, title: String(localized: "Favorite Songs"))
    }
}

/// Which favourites are shown, kept between launches.
nonisolated enum LibraryFavoritesKind: String, CaseIterable, Sendable {
    case songs
    case albums
    case artists
}
