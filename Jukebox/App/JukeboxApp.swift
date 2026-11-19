// Jukebox: the music of a Jellyfin, Navidrome or other Subsonic server on
// the iPhone, the iPad and the Mac — artists, albums, songs and playlists,
// playlists it makes up itself, and a radio that plays on from anything and
// listens to what is skipped.

import JukeboxKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct JukeboxApp: App {
    /// For the downloads' news while the app is in the background or not
    /// running (Offline/OfflineDownloader.swift): UIKit's alone. A Mac app
    /// is not woken for them: its downloads go on while it runs.
    #if os(iOS)
    @UIApplicationDelegateAdaptor(JukeboxAppDelegate.self) private var appDelegate
    #endif
    @State private var app = AppModel.shared
    /// The wide window's panel, open or closed and on what: one for the app.
    @State private var panel = PanelState()

    init() {
        // `app_open` (Stats) is counted by AppModel.restore, once a launch,
        // when the keychain has said which kind of server it is.
        // The bars' titles in the serif, before the first bar is made.
        Theme.styleNavigationBars()
        #if os(iOS)
        // The widget follows from the first moment, a launch in the
        // background for its own button too (App/WidgetDoors.swift).
        WidgetDoors.follow(AppModel.shared)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(app, panel: panel)
                .task { await app.restore() }
                // Siri's phrases follow the library (Intents/Voice.swift).
                .task(id: app.library.lastLoaded) { await Voice.libraryShown(app) }
                #if os(macOS)
                .task { await WalkWindow.apply() }
                #endif
        }
        .commands { JukeboxCommands(app: app) }
        #if os(macOS)
        // ⌘, opens Settings in a window of its own, as every Mac app's.
        Settings {
            SettingsView(asWindow: true)
                .appEnvironment(app, panel: panel)
        }
        #endif
    }
}

#if os(macOS)
/// The window of the Mac's screenshot walk (JukeboxUITests/
/// MacScreenshotTests.swift). The App Store takes a Mac's picture at 1440 by
/// 900 exactly and the picture is the window, so the walk launches with
/// `-windowWidth 1440 -windowHeight 900 -darkWindow YES` in the argument
/// domain, as its other arguments. Here and not from the test: XCTest cannot
/// give a window a size, only drag its corner, which lands a point off. The
/// size is the frame's, title bar and all, at the screen's top left, clear of
/// what the system shows at its right. A screen too small for it gets a
/// smaller window, and the walk's log says how large each picture was.
/// Without the arguments this does nothing.
private enum WalkWindow {
    static func apply() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "darkWindow") {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        let width = CGFloat(defaults.integer(forKey: "windowWidth"))
        let height = CGFloat(defaults.integer(forKey: "windowHeight"))
        guard width > 0, height > 0 else { return }
        // After SwiftUI has placed the window itself: its own size, coming
        // later, would undo this one.
        try? await Task.sleep(for: .milliseconds(500))
        for window in NSApplication.shared.windows where window.styleMask.contains(.titled) {
            guard let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { continue }
            window.setFrame(NSRect(x: screen.minX, y: screen.maxY - height, width: width, height: height),
                            display: true)
        }
    }
}
#endif

private extension View {
    /// The app's stores and its tint, for each of its windows: a scene does
    /// not inherit another's.
    func appEnvironment(_ app: AppModel, panel: PanelState) -> some View {
        environment(app)
            .environment(app.navigator)
            .environment(app.settings)
            .environment(app.library)
            .environment(app.history)
            .environment(app.player)
            .environment(app.radio)
            .environment(app.mixes)
            .environment(app.offline)
            .environment(app.handoff)
            .environment(panel)
            // Every control's tint (toggles, sliders, links, the tab
            // bar's selection) in Copper or Glow, not the system's blue.
            .tint(Theme.accent)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isWide) private var isWide

    var body: some View {
        content
            // In front again: is the server there (or gone), and do the
            // downloads that waited go on.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                app.offline.appBecameActive()
                // Music added on the server since, without a relaunch
                // (LibraryStore.refreshIfStale): the Mac has no pull to refresh.
                if !app.offline.isOffline { Task { await app.library.refreshIfStale() } }
                // What the computer was playing, there when the phone is
                // picked up, not a quarter of a minute later.
                Task { await app.handoff.refresh() }
                // The speaker's socket, which the system may have closed
                // while the app slept (RemoteControl).
                app.remote.wake()
            }
            #if os(macOS)
            // A Mac's window stays .active while another app is in front, so
            // coming back from the Finder with new music is AppKit's news.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if !app.offline.isOffline { Task { await app.library.refreshIfStale() } }
            }
            #endif
            // Which page `open` pushes on: the wide window's or the tab's.
            .onChange(of: isWide, initial: true) { _, wide in
                app.navigator.isWide = wide
            }
            // Signed out, as AppModel puts the tabs back on Home: the next
            // sign-in, perhaps to another server, starts on Home in the
            // wide window too, not on the last account's playlist.
            .onChange(of: app.phase) { _, phase in
                guard phase == .signedOut else { return }
                app.navigator.place = .home
                app.navigator.isSettingsPresented = false
                app.navigator.searchQuery = ""
            }
            // Add Account… from the ≡ menu or the Mac's Account menu, and
            // why a switch from there did not happen (AccountMenu.swift).
            .sheet(isPresented: Bindable(app.navigator).isAddingAccount) {
                OnboardingView(isAdding: true)
            }
            .alert("Still on This Account",
                   isPresented: Binding(get: { app.switchProblem != nil }, set: { if !$0 { app.switchProblem = nil } })) {
                Button("OK") {}
            } message: {
                Text(app.switchProblem ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        switch app.phase {
        case .launching:
            // The launch screen's own ground (white, or Cabinet in dark
            // mode), so restoring the session shows no second ground
            // between it and the app.
            Color("LaunchBackground").ignoresSafeArea()
        case .signedOut:
            OnboardingView()
        case .signedIn:
            // The iPad at regular width and the Mac: Linux's window, the
            // places, the page, the panel and the bar. The iPhone, and an
            // iPad window made narrow: the tabs.
            #if os(iOS)
            if isWide {
                WideShell()
            } else {
                MainTabView()
            }
            #else
            WideShell()
            #endif
        }
    }
}

#if os(iOS)
/// The four tabs, Music's: Home, Radio, Library, Search. What plays sits
/// above the tab bar; tapped, Now Playing covers everything. The iPhone's,
/// and an iPad window's when it is narrow; the Mac's window is always wide.
struct MainTabView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: navigator.path(for: .home)) {
                    HomeView().routeDestinations()
                }
            }
            // Settings › Pages: Radio off, its tab goes; every library kind
            // off, the Library's. The tab shown stays until another is
            // chosen: Settings is a sheet from Radio, and would go with it.
            if settings.shows(.radio) || navigator.tab == .radio {
                Tab("Radio", systemImage: "dot.radiowaves.left.and.right", value: AppTab.radio) {
                    NavigationStack(path: navigator.path(for: .radio)) {
                        RadioView().routeDestinations()
                    }
                }
            }
            if settings.showsLibrary || navigator.tab == .library {
                Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                    NavigationStack(path: navigator.path(for: .library)) {
                        LibraryView().routeDestinations()
                    }
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: navigator.path(for: .search)) {
                    SearchView().routeDestinations()
                }
            }
        }
        // The tab bar; a narrow iPad window has it too.
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
#endif
