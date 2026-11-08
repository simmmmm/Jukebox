// Where the app is: which tab, and what is pushed in each tab's stack. One
// object, so anything — a context menu's "Go to Album", Now Playing's
// artist name — can take the listener somewhere without knowing which tab
// it is in. Every screen that can be pushed is a Route; `routeDestinations()`
// is the one place that turns a Route into its view, and so where a pushed
// page is counted (Stats, `screen`), by its kind alone: "album", never the
// album. The tabs are counted where they are drawn (MainTabView).

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
    /// A station's page: what it would play, before it plays. Every tile
    /// and card of a station opens it (StationDetailView).
    case station(Station)
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
            Group {
                switch route {
                case let .album(album): AlbumDetailView(album: album)
                case let .artist(artist): ArtistDetailView(artist: artist)
                case let .playlist(playlist): PlaylistDetailView(playlist: playlist)
                case let .genre(genre): GenreDetailView(genre: genre)
                case let .mix(mix): MixDetailView(mix: mix)
                case let .station(station): StationDetailView(station: station)
                case .artists: ArtistsView()
                case .albums: AlbumsView()
                case .songs: SongsView()
                case .playlists: PlaylistsView()
                case .genres: GenresView()
                case .favorites: FavoritesView()
                case .recentlyAdded: RecentlyAddedView()
                }
            }
            // Once a push, whether by a link or by `open`: not again when
            // the listener comes Back to it.
            .countsScreen(route.statsName)
        }
    }
}

extension AppTab {
    /// The tab in the usage counts (Stats, `screen`).
    var statsName: String {
        switch self {
        case .home: return "home"
        case .radio: return "radio"
        case .library: return "library"
        case .search: return "search"
        }
    }
}

extension Route {
    /// The page in the usage counts (Stats, `screen`): its kind, never the
    /// album, artist, playlist, genre, mix or station it shows.
    var statsName: String {
        switch self {
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .genre: return "genre"
        case .mix: return "mix"
        case .station: return "station"
        case .artists: return "artists"
        case .albums: return "albums"
        case .songs: return "songs"
        case .playlists: return "playlists"
        case .genres: return "genres"
        case .favorites: return "favorites"
        case .recentlyAdded: return "recently_added"
        }
    }
}
