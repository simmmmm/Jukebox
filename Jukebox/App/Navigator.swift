// Where the app is: which tab, and what is pushed in each tab's stack. One
// object, so anything — a context menu's "Go to Album", Now Playing's
// artist name — can take the listener somewhere without knowing which tab
// it is in. Every screen that can be pushed is a Route; `routeDestinations()`
// is the one place that turns a Route into its view.

import JukeboxKit
import SwiftUI

enum AppTab: Hashable {
    case home
    case radio
    case library
    case search
}

enum Route: Hashable {
    case album(Album)
    case artist(Artist)
    case playlist(Playlist)
    case genre(Genre)
    case mix(Mix)
    case artists
    case albums
    case songs
    case playlists
    case genres
    case favorites
    case recentlyAdded
}

struct AddToPlaylistRequest: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

@Observable
final class Navigator {
    var tab: AppTab = .home
    var homePath = NavigationPath()
    var radioPath = NavigationPath()
    var libraryPath = NavigationPath()
    var searchPath = NavigationPath()
    /// Now Playing, full screen over everything.
    var isNowPlayingPresented = false
    /// "Add to Playlist…" from any menu: the sheet MainTabView shows.
    var addToPlaylist: AddToPlaylistRequest?

    /// Push `route` on the tab the listener is in, closing Now Playing first.
    func open(_ route: Route) {
        isNowPlayingPresented = false
        switch tab {
        case .home: homePath.append(route)
        case .radio: radioPath.append(route)
        case .library: libraryPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    /// The path of `tab`, for its NavigationStack.
    func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: {
                switch tab {
                case .home: self.homePath
                case .radio: self.radioPath
                case .library: self.libraryPath
                case .search: self.searchPath
                }
            },
            set: { newValue in
                switch tab {
                case .home: self.homePath = newValue
                case .radio: self.radioPath = newValue
                case .library: self.libraryPath = newValue
                case .search: self.searchPath = newValue
                }
            }
        )
    }
}

extension View {
    /// Every Route's screen, for a tab's NavigationStack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .album(album): AlbumDetailView(album: album)
            case let .artist(artist): ArtistDetailView(artist: artist)
            case let .playlist(playlist): PlaylistDetailView(playlist: playlist)
            case let .genre(genre): GenreDetailView(genre: genre)
            case let .mix(mix): MixDetailView(mix: mix)
            case .artists: ArtistsView()
            case .albums: AlbumsView()
            case .songs: SongsView()
            case .playlists: PlaylistsView()
            case .genres: GenresView()
            case .favorites: FavoritesView()
            case .recentlyAdded: RecentlyAddedView()
            }
        }
    }
}
