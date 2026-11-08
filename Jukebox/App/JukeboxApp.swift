// Jukebox: Jellyfin's music on the iPhone and the iPad — artists, albums,
// songs and playlists, playlists it makes up itself, and a radio that plays
// on from anything and listens to what is skipped.

import JukeboxKit
import SwiftUI

@main
struct JukeboxApp: App {
    @State private var app = AppModel()

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
            Color(uiColor: .systemBackground).ignoresSafeArea()
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
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            MiniPlayer()
        }
        .fullScreenCover(isPresented: $navigator.isNowPlayingPresented) {
            NowPlayingView()
        }
        .sheet(item: $navigator.addToPlaylist) { request in
            AddToPlaylistSheet(tracks: request.tracks)
        }
    }
}
