// Where the app is: which tab, and what is pushed in each tab's stack. One
// object, so anything — a context menu's "Go to Album", Now Playing's
// artist name — can take the listener somewhere without knowing which tab
// it is in. Every screen that can be pushed is a Route; `routeDestinations()`
// is the one place that turns a Route into its view, and so where a pushed
// page is counted (Stats, `screen`), by its kind alone: "album", never the
// album. The tabs are counted where they are drawn (MainTabView), the wide
// window's places likewise (WideShell).

import JukeboxKit
import SwiftUI

enum AppTab: Hashable {
    case home
    case radio
    case library
    case search
}

/// A place in the wide window's sidebar (WideShell), as Linux's sidebar has
/// them: what the page shows before anything is pushed on it.
enum Place: Hashable {
    case home
    case radio
    case search
    /// One of the library's kinds (`.albums`, `.favorites`, …): its page.
    case library(Route)
    /// A playlist under the places, by its id: renamed or grown, it is
    /// still the place chosen.
    case playlist(Playlist.ID)
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
    /// What is on the phone (DownloadedView).
    case downloaded
    /// The year's music (YourYearView): content, so the library's, not
    /// Settings'. No switch in Settings › Pages: always there.
    case yourYear
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
    /// The wide window's place and what is pushed on its page (WideShell).
    /// Kept beside the tabs' paths: an iPad resized between the two finds
    /// each shell where it left it, nothing translated between them.
    var place: Place = .home {
        // Another place starts at its own page.
        didSet { widePath = NavigationPath() }
    }
    var widePath = NavigationPath()
    /// The wide window shows (RootView says so): `open` pushes on its page.
    var isWide = false
    /// Now Playing, full screen over everything (the room, in the wide
    /// window).
    var isNowPlayingPresented = false
    /// "Add to Playlist…" from any menu: the sheet MainTabView shows.
    var addToPlaylist: AddToPlaylistRequest?
    /// Settings over the wide window on an iPad (the sidebar's menu, ⌘,).
    /// The Mac has its Settings window.
    var isSettingsPresented = false
    /// Add Account… from a menu (AccountMenuItems): the sign-in in a sheet
    /// over the window (RootView).
    var isAddingAccount = false
    /// What is typed in the wide window's one search field, in its bar
    /// (WideShell): the Search place shows what it finds (SearchView). It
    /// keeps its text, on any place, until it is cleared.
    var searchQuery = ""
    /// Return in that field: the search is kept as a recent one (SearchView).
    var searchSubmits = 0
    /// ⌘F: the field asked for the keys (JukeboxCommands, WideShell); on
    /// the tabs, Search tapped again (`select`, SearchView).
    var searchRequests = 0

    /// The Search place's own page, over Now Playing: the bar's field was
    /// clicked into or typed in. The Search place has no row in the
    /// sidebar; the field is its way in ("de search pagina mag uit het
    /// menu", the photographer, 14 November 2026).
    func showSearch() {
        if isNowPlayingPresented { isNowPlayingPresented = false }
        // A result opened from it: back to what was found.
        if place != .search || !widePath.isEmpty { place = .search }
    }

    /// Push `route` on the page the listener is on (the wide window's, else
    /// the tab's), closing Now Playing first.
    func open(_ route: Route) {
        isNowPlayingPresented = false
        if isWide {
            widePath.append(route)
            return
        }
        switch tab {
        case .home: homePath.append(route)
        case .radio: radioPath.append(route)
        case .library: libraryPath.append(route)
        case .search: searchPath.append(route)
        }
    }

    /// A tab tapped, in the system's tab bar or Jukebox's own (TabRow).
    /// Another tab: that tab, as it was left; but Search on its first page,
    /// the recent searches and the genres, the keyboard down. The tab
    /// shown, tapped again: back to its first page, and on Search's first
    /// page into the field: "Ook zoeken; een tap opent de recente
    /// zoekopdrachten met daaronder de genres, tweede tap focust het
    /// zoekveld" (the photographer, 20 November 2026).
    func select(_ chosen: AppTab) {
        guard chosen == tab else {
            if chosen == .search { searchPath = NavigationPath() }
            tab = chosen
            return
        }
        let path = path(for: chosen)
        if !path.wrappedValue.isEmpty {
            path.wrappedValue = NavigationPath()
        } else if chosen == .search {
            // SearchView's field, as ⌘F asks the wide window's.
            searchRequests += 1
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
    /// Every Route's screen, for a tab's NavigationStack and the wide
    /// window's page.
    func routeDestinations() -> some View {
        routeDestinations(each: EmptyModifier())
    }

    /// The same, each pushed page in `modifier` too: the wide window's bar
    /// (WideShell's PageBar).
    func routeDestinations(each modifier: some ViewModifier) -> some View {
        navigationDestination(for: Route.self) { route in
            RoutePage(route: route)
                // Once a push, whether by a link or by `open`: not again when
                // the listener comes Back to it.
                .countsScreen(route.statsName)
                .modifier(modifier)
        }
    }
}

/// The screen a Route shows: pushed, or a library place's own page in the
/// wide window's sidebar.
struct RoutePage: View {
    let route: Route

    var body: some View {
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
        case .downloaded: DownloadedView()
        case .yourYear: YourYearView()
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

extension Place {
    /// The place in the usage counts (Stats, `screen`) and in its row's
    /// accessibility id (`place.albums`): its kind, never the playlist.
    var statsName: String {
        switch self {
        case .home: return "home"
        case .radio: return "radio"
        case .search: return "search"
        case let .library(route): return route.statsName
        case .playlist: return "playlist"
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
        case .downloaded: return "downloaded"
        case .yourYear: return "your_year"
        }
    }
}
