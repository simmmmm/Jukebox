// Jukebox: Jellyfin's music on the iPhone and the iPad — artists, albums,
// songs and playlists, playlists it makes up itself, and a radio that plays
// on from anything and listens to what is skipped.

import JukeboxKit
import SwiftUI

@main
struct JukeboxApp: App {
    @State private var app = AppModel()

    init() {
        // Once a launch (Stats): how many starts, on which system and version.
        Stats.track(.appOpen)
        // The bars' titles in the serif, before the first bar is made.
        Theme.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.navigator)
                .environment(app.settings)
                .environment(app.library)
                .environment(app.history)
                .environment(app.player)
                .environment(app.radio)
                .environment(app.mixes)
                .task { await app.restore() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .launching:
            // The launch screen's own ground (white, or Cabinet in dark
            // mode), so restoring the session shows no second ground
            // between it and the app.
            Color("LaunchBackground").ignoresSafeArea()
        case .signedOut:
            OnboardingView()
        case .signedIn:
            MainTabView()
        }
    }
}

/// The four tabs, Music's: Home, Radio, Library, Search. What plays sits
/// above the tab bar; tapped, Now Playing covers everything.
struct MainTabView: View {
    @Environment(Navigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: navigator.path(for: .home)) {
                    HomeView().routeDestinations()
                }
            }
            Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: AppTab.radio) {
                NavigationStack(path: navigator.path(for: .radio)) {
                    RadioView().routeDestinations()
                }
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack(path: navigator.path(for: .library)) {
                    LibraryView().routeDestinations()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: navigator.path(for: .search)) {
                    SearchView().routeDestinations()
                }
            }
        }
        // On the iPad a sidebar, as Music has there; on the iPhone the tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayer()
        }
        .fullScreenCover(isPresented: $navigator.isNowPlayingPresented) {
            NowPlayingView()
        }
        // The usage counts (Stats, `screen`): the tab shown first, then each
        // one chosen, Now Playing's station name to Radio too. Here, with
        // the tabs, rather than in Navigator: signing out puts the tab back
        // on Home after the tabs have gone, and that is no visit to Home.
        .countsOnce { Stats.track(.screen, ["name": self.navigator.tab.statsName]) }
        .onChange(of: navigator.tab) { _, tab in
            Stats.track(.screen, ["name": tab.statsName])
        }
        // While Now Playing covers the tabs it presents this sheet itself
        // (a view already presenting cannot present another); here it
        // waits, so the two never both try.
        .sheet(item: Binding(get: { self.navigator.isNowPlayingPresented ? nil : self.navigator.addToPlaylist },
                             set: { self.navigator.addToPlaylist = $0 })) { request in
            AddToPlaylistSheet(tracks: request.tracks)
        }
    }
}
