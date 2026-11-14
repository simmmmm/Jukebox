// Favorites: the songs, albums and artists the listener has hearted, in
// Jellyfin (so every Jellyfin app shares them), one kind at a time. Spelled
// as Apple's Music spells it, "Favorite", in every string the listener sees.
//
// In a wide window, as Linux's: one page, the artists and the albums in
// shelves of tiles and the songs in rows, under one title.

import JukeboxKit
import SwiftUI

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @AppStorage("library.favoritesKind") private var kind: LibraryFavoritesKind = .songs
    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    /// Linux's Favorites: Artists, Albums and Songs, each under its heading
    /// when there is any; one line when there is none.
    private var wide: some View {
        let artists = library.favoriteArtists
        let albums = library.favoriteAlbums
        let tracks = library.favoriteTracks
        return WidePage(title: "Favorites") { page, _ in
            PageTitle("Favorites")
                .padding(.horizontal, page.side)
            if artists.isEmpty && albums.isEmpty && tracks.isEmpty {
                PageEmptyLine("Choose Favorite in a song’s, album’s or artist’s menu, and it appears here.")
                    .padding(.horizontal, page.side)
            }
            if !artists.isEmpty {
                PageSectionTitle(String(localized: "Artists"))
                    .padding(.horizontal, page.side)
                Shelf(items: artists, width: CGFloat(page.tile), margin: page.side) { artist in
                    NavigationLink(value: Route.artist(artist)) {
                        ArtistTile(artist: artist)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !albums.isEmpty {
                PageSectionTitle(String(localized: "Albums"))
                    .padding(.horizontal, page.side)
                Shelf(items: albums, width: CGFloat(page.tile), margin: page.side) { album in
                    LibraryAlbumLink(album: album)
                }
            }
            if !tracks.isEmpty {
                Group {
                    PageSectionTitle(String(localized: "Songs"), below: Theme.Space.s)
                    LibraryTrackRows(tracks: tracks, play: { track in
                        let i = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
                        player.play(tracks, startingAt: i, context: context)
                    })
                }
                .padding(.horizontal, page.side)
            }
        }
        .refreshable { await library.refresh() }
    }

    private var compact: some View {
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
