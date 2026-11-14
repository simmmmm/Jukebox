// The iPad's and the Mac's window, as Linux's is (Linux/App/MainWindow.swift,
// the designer's spec §1): the places at the left, the place's page beside
// them, the panel of Up Next or the lyrics at the right when it is open, and
// the player's bar under all three. Now Playing is a room over places and
// page; the bar and the panel stay. Narrower, the panel lies over the page
// (below 1280), then the places fold away and come over it when asked for
// (below 900). Drawn here rather than by NavigationSplitView and the
// inspector, whose sidebar, selection and columns look and fold their own
// way: "ik wil dat de linux app en de apple app 1:1 op elkaar lijken" (the
// photographer, 14 November 2026). The iPhone keeps its tabs (MainTabView).

import JukeboxKit
import SwiftUI

extension EnvironmentValues {
    /// Now Playing shown as the wide layout's room, over the places and the
    /// page, with the bar and the panel still beside it: they do its
    /// transport and its panel switch, so it leaves those out.
    @Entry var inRoom = false
}

/// The sidebar's and the panel's ground: one step up from the page's (the
/// spec's §1, Linux's Style.swift `raised`).
private let raised = Color(light: 0xECE7DF, dark: 0x1B1918)

struct WideShell: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AudioPlayer.self) private var player
    @Environment(PanelState.self) private var panel
    @Environment(LibraryStore.self) private var library
    /// The folded places, lying over the page.
    @State private var showsPlaces = false

    var body: some View {
        @Bindable var navigator = navigator
        GeometryReader { window in
            // The window's breakpoints, as Linux's (spec §1).
            let folds = window.size.width < 900
            let overlaid = window.size.width < 1280
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ZStack {
                        HStack(spacing: 0) {
                            if !folds {
                                Places { showsPlaces = false }
                                Divider()
                            }
                            page(folds: folds)
                        }
                        .accessibilityHidden(navigator.isNowPlayingPresented)
                        if navigator.isNowPlayingPresented {
                            NowPlayingView()
                                .environment(\.inRoom, true)
                                .transition(.opacity)
                                // Above the page while it fades out too.
                                .zIndex(1)
                        }
                    }
                    // In and out as a crossfade of 200 ms, as on Linux. The
                    // window keeps its own appearance: the room has its own
                    // dark ground.
                    .animation(.easeInOut(duration: 0.2), value: navigator.isNowPlayingPresented)
                    if panelShown && !overlaid {
                        Divider()
                        panelPane
                            .transition(.move(edge: .trailing))
                    }
                }
                // Lying over the page: closed by a click beside it, as the
                // listener's own closing (Linux's followPanel).
                .overlay(alignment: .leading) {
                    if folds && showsPlaces {
                        beside { showsPlaces = false }
                        Places { showsPlaces = false }
                            .shadow(color: .black.opacity(0.2), radius: 8)
                            .transition(.move(edge: .leading))
                    }
                }
                .overlay(alignment: .trailing) {
                    if panelShown && overlaid {
                        beside { panel.isOpen = false }
                        panelPane
                            .shadow(color: .black.opacity(0.2), radius: 8)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: panelShown)
                .animation(.easeInOut(duration: 0.25), value: showsPlaces)

                // The bar across the window's whole foot, under the places,
                // the page and the panel, as on Linux.
                if player.hasTrack {
                    Divider()
                    PlayerBar()
                        // Its ground on to the window's foot, under the
                        // iPad's home indicator.
                        .background(raised.ignoresSafeArea(edges: .bottom))
                }
            }
            .onChange(of: overlaid, initial: true) { _, overlaid in
                panel.isOverlaid = overlaid
            }
            .onChange(of: folds) { _, _ in
                showsPlaces = false
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        // One thing over the page at a time (spec §1): the panel opened
        // sends the places lying over the page away.
        .onChange(of: panelShown) { _, shown in
            if shown { showsPlaces = false }
        }
        // The usage counts (Stats, `screen`): the place shown first, then
        // each one chosen, as MainTabView counts its tabs. Here, not in
        // Navigator: signing out puts the place back on Home after the
        // window has gone, and that is no visit to Home.
        .countsOnce { Stats.track(.screen, ["name": self.navigator.place.statsName]) }
        .onChange(of: navigator.place) { _, place in
            Stats.track(.screen, ["name": place.statsName])
        }
        // While Now Playing is open it presents this sheet itself, as on
        // the iPhone; here it waits, so the two never both try.
        .sheet(item: Binding(get: { self.navigator.isNowPlayingPresented ? nil : self.navigator.addToPlaylist },
                             set: { self.navigator.addToPlaylist = $0 })) { request in
            AddToPlaylistSheet(tracks: request.tracks)
        }
        #if os(iOS)
        .sheet(isPresented: $navigator.isSettingsPresented) {
            SettingsView()
        }
        #endif
    }

    /// Open as the listener left it, and only with a song: the buttons that
    /// open and close it are in the bar, which is there only with one.
    private var panelShown: Bool {
        panel.isShown && player.hasTrack
    }

    private var panelPane: some View {
        PanelView()
            .frame(width: CGFloat(DesktopMeasures.panel))
            .frame(maxHeight: .infinity)
            .background(raised.ignoresSafeArea())
    }

    /// The page beside a pane lying over it: a click there closes the pane.
    private func beside(_ close: @escaping () -> Void) -> some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
    }

    /// The place's page and what is pushed on it, each with its own Back.
    private func page(folds: Bool) -> some View {
        @Bindable var navigator = navigator
        return NavigationStack(path: $navigator.widePath) {
            placePage
                // Another place, another page: not the last one's state with
                // another playlist in it.
                .id(navigator.place)
                .toolbar {
                    // Folded, the places' button at the start of a place's
                    // header lays them over the page (Linux's sidebarButton).
                    if folds {
                        ToolbarItem(placement: .barLeading) {
                            Button {
                                // One thing over the page at a time.
                                if panel.isShown { panel.isOpen = false }
                                showsPlaces = true
                            } label: {
                                Label("Show Sidebar", systemImage: "sidebar.left")
                            }
                        }
                    }
                }
                .routeDestinations()
        }
    }

    @ViewBuilder private var placePage: some View {
        switch navigator.place {
        case .home: HomeView()
        case .radio: RadioView()
        case .search: SearchView()
        case let .library(route): RoutePage(route: route)
        case let .playlist(id):
            if let playlist = library.playlists.first(where: { $0.id == id }) {
                PlaylistDetailView(playlist: playlist)
            }
        }
    }
}

/// The sidebar, as Linux's (spec §4): the mark and the name, then Home,
/// Radio and Search; a hair; the library's kinds; a hair; the playlists
/// themselves with their covers. The place chosen has a quiet fill, as
/// GNOME's sidebar, not the accent.
///
/// Its properties are not private, so its memberwise init is not either.
private struct Places: View {
    @Environment(Navigator.self) var navigator
    @Environment(LibraryStore.self) var library
    /// A place chosen: lying over the page, the places go.
    let chosen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            head
            ScrollView {
                LazyVStack(spacing: 0) {
                    glyphRow(.home, "Home", symbol: "house")
                    // The mark's template cut, as on Linux: the arch means a
                    // station.
                    PlaceRow(place: .radio, title: Text("Radio"), chosen: chosen) {
                        ArchMark(size: 16, style: .template)
                    }
                    glyphRow(.search, "Search", symbol: "magnifyingglass")
                    hair
                    glyphRow(.library(.albums), "Albums", symbol: "opticaldisc")
                    glyphRow(.library(.artists), "Artists", symbol: "person.fill")
                    glyphRow(.library(.songs), "Songs", symbol: "music.note")
                    glyphRow(.library(.playlists), "Playlists", symbol: "music.note.list")
                    glyphRow(.library(.favorites), "Favorites", symbol: "heart.fill")
                    // Not on Linux yet: without a row here these could not be
                    // reached in the wide window at all.
                    glyphRow(.library(.genres), "Genres", symbol: "guitars")
                    glyphRow(.library(.recentlyAdded), "Recently Added", symbol: "clock")
                    glyphRow(.library(.downloaded), "Downloaded", symbol: "arrow.down.circle")
                    if !library.playlists.isEmpty {
                        hair
                        ForEach(library.playlists) { playlist in
                            PlaceRow(place: .playlist(playlist.id), height: 48, dimsIcon: false,
                                     title: Text(verbatim: playlist.name), chosen: chosen) {
                                ArtworkView(playlist.artwork, size: 32, placeholder: "music.note.list")
                            }
                        }
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
        }
        .frame(width: CGFloat(DesktopMeasures.sidebar))
        .frame(maxHeight: .infinity)
        .background(raised.ignoresSafeArea())
    }

    /// The flat mark 20 and the name in the serif, the main menu at the end.
    /// The mark stands over the places' icons and the name over their words
    /// ("heb t gevoel dat het logo linksboven in lijn moet staan met het
    /// icoon van de buttons links", 14 November 2026): an icon sits 20 in
    /// (the row's 8 and its padding 12), its word 16 and 12 further, at 48;
    /// the mark 20 in, 20 wide and 8 from the name, at 48 too.
    private var head: some View {
        HStack(spacing: Theme.Space.s) {
            ArchMark(size: 20)
            Text("Jukebox")
                .font(.serif(.headline))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            // GNOME's primary menu, where Linux's Preferences are.
            Menu {
                #if os(macOS)
                SettingsLink {
                    Text("Settings…")
                }
                #else
                Button("Settings…") {
                    navigator.isSettingsPresented = true
                }
                #endif
            } label: {
                Image(systemName: "line.3.horizontal")
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Main Menu")
        }
        .padding(.leading, 20)
        .padding(.trailing, Theme.Space.s)
        .frame(height: 48)
    }

    /// A hair between groups of rows, 16 tall, as wide as the rows' content.
    private var hair: some View {
        Divider()
            .padding(.horizontal, 20)
            .frame(height: Theme.Space.l)
    }

    private func glyphRow(_ place: Place, _ title: LocalizedStringKey, symbol: String) -> some View {
        PlaceRow(place: place, title: Text(title), chosen: chosen) {
            Image(systemName: symbol)
                .font(.subheadline)
        }
    }
}

/// One place: its icon (16 at 60 %, full when chosen) or a playlist's cover,
/// 12, its name; 40 tall, 48 with a cover; inset 8, padding 12.
private struct PlaceRow<Icon: View>: View {
    @Environment(Navigator.self) var navigator
    let place: Place
    var height: CGFloat = 40
    var dimsIcon = true
    let title: Text
    let chosen: () -> Void
    @ViewBuilder let icon: Icon
    @State var isHovered = false

    var body: some View {
        let isChosen = navigator.place == place
        Button {
            if !isChosen { navigator.place = place }
            chosen()
        } label: {
            HStack(spacing: Theme.Space.m) {
                icon
                    .frame(minWidth: 16, minHeight: 16)
                    .opacity(dimsIcon && !isChosen ? 0.6 : 1)
                    .accessibilityHidden(true)
                title
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(height: height)
            .background(fill(isChosen), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Space.s)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("place.\(place.statsName)")
    }

    /// GNOME's sidebar: a tenth of the text's colour for the place chosen,
    /// less under the pointer.
    private func fill(_ isChosen: Bool) -> Color {
        if isChosen { return Color.primary.opacity(0.1) }
        return isHovered ? Color.primary.opacity(0.05) : .clear
    }
}
