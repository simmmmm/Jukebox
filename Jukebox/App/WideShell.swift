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
//
// Over the page, the window's own bar on every place and pushed page, as
// the Playlists page first had it on the Mac ("vind die wel mooier"): Back,
// the page's title once its own has scrolled away, the page's actions, and
// at the trailing end the one search field, which searches the whole
// library on the Search place's page.
//
// Settings › Pages takes rows out of the places (AppSettings.hiddenPages);
// with every one off only Home is left, and the places go altogether: the
// window is Home, the panel and the bar, "dan zijn er uberhaupt geen pages"
// (the photographer, 15 November 2026).

import JukeboxKit
import SwiftUI

extension EnvironmentValues {
    /// Now Playing shown as the wide layout's room, over the places and the
    /// page, with the bar and the panel still beside it: they do its
    /// transport and its panel switch, so it leaves those out.
    @Entry var inRoom = false
}

struct WideShell: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AudioPlayer.self) private var player
    @Environment(PanelState.self) private var panel
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(RadioController.self) private var radio
    /// The folded places, lying over the page.
    @State private var showsPlaces = false
    /// The bar's search field has the keys: the Search place shows.
    @FocusState private var isSearchFocused: Bool

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
                            // No line beside them: their ground one step
                            // up is the edge, as on Linux.
                            if !folds && hasPlaces {
                                Places { showsPlaces = false }
                            }
                            page(folds: folds)
                        }
                        // Under the room, out of VoiceOver's and the
                        // keyboard's reach.
                        .accessibilityHidden(navigator.isNowPlayingPresented)
                        .disabled(navigator.isNowPlayingPresented)
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
                        // Beside the page its ground is the edge; over the
                        // room, where it has none, Linux's faint dark line.
                        // (#0F0E0D: the room's #121110 under black at 17 %,
                        // whatever the window's own appearance.)
                        Rectangle()
                            .fill(navigator.isNowPlayingPresented ? Color(rgb: 0x0F0E0D) : .clear)
                            // grid-ok: a line, as a hairline is
                            .frame(width: 1)
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
                // the page and the panel, as on Linux. Its hairline and its
                // ground (in the room too) are its own.
                if player.hasTrack {
                    PlayerBar()
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
        #if os(macOS)
        // The room has its own head, Close and More, as on Linux: the
        // window's bar steps aside for it.
        .toolbar(navigator.isNowPlayingPresented ? .hidden : .automatic, for: .windowToolbar)
        #endif
        // One thing over the page at a time (spec §1): the panel opened
        // sends the places lying over the page away.
        .onChange(of: panelShown) { _, shown in
            if shown { showsPlaces = false }
        }
        // A page switched off while it shows: Home, which is always there.
        .onChange(of: settings.hiddenPages) { _, _ in
            if !settings.shows(place: navigator.place) { navigator.place = .home }
            if !hasPlaces { showsPlaces = false }
        }
        // When the station on air began, for "Started at" (StationClock).
        .onChange(of: radio.station?.id, initial: true) { _, id in
            StationClock.shared.follow(id)
        }
        // Nothing plays any more: the room closes, as on Linux. The player
        // empties and fills its queue in one go, so a new album does not.
        .onChange(of: player.hasTrack) { _, hasTrack in
            if !hasTrack { navigator.isNowPlayingPresented = false }
        }
        // The usage counts (Stats, `screen`): the place shown first, then
        // each one chosen, as MainTabView counts its tabs. Here, not in
        // Navigator: signing out puts the place back on Home after the
        // window has gone, and that is no visit to Home.
        .countsOnce { Stats.track(.screen, ["name": self.navigator.place.statsName]) }
        .onChange(of: navigator.place) { _, place in
            Stats.track(.screen, ["name": place.statsName])
            // Another place chosen leaves Search: a click in the field
            // again comes back to it. The field keeps its text.
            if place != .search { isSearchFocused = false }
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

    /// Any place but Home in the sidebar (Settings › Pages): else there is
    /// none.
    private var hasPlaces: Bool {
        settings.showsAnyPage
    }

    /// Open as the listener left it, and only with a song: the buttons that
    /// open and close it are in the bar, which is there only with one.
    private var panelShown: Bool {
        panel.isShown && player.hasTrack
    }

    /// The panel, 360 at every width; its ground is its own (PanelView).
    private var panelPane: some View {
        PanelView()
            .frame(width: CGFloat(DesktopMeasures.panel))
            .frame(maxHeight: .infinity)
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
                #if os(iOS)
                .toolbar {
                    if !hasPlaces {
                        // The places' head had Settings: without them it is
                        // here, or the pages could never come back.
                        ToolbarItem(placement: .barLeading) {
                            MainMenu()
                        }
                    } else if folds {
                        ToolbarItem(placement: .barLeading) {
                            placesButton
                        }
                    }
                }
                #endif
                // Outside the place's id: a place chosen while typing keeps
                // the field, and its keys.
                .modifier(PageBar())
                .searchFocused($isSearchFocused)
                .routeDestinations(each: PageBar(isPushed: true))
        }
        .onChange(of: isSearchFocused) { _, focused in
            if focused { navigator.showSearch() }
        }
        .onChange(of: navigator.searchQuery) { _, query in
            // Emptied on another place, it stays there.
            // Typed on a pushed page, which goes: the field stays in the
            // bar with the keys, every letter in it (tried on the Mac, 15
            // November 2026).
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                navigator.showSearch()
            }
        }
        .onChange(of: navigator.searchRequests) { _, _ in
            isSearchFocused = true
        }
        #if os(macOS)
        .toolbar {
            // The places' head beside the traffic lights, in the title
            // bar's row: "kun je ook op mac het jukebox logo naast in het
            // vensterding zetten naast de stoplichten" (the photographer,
            // 14 November 2026). As wide as the places, so Back and the
            // title start over the page.
            BrandHeadItem(overPlaces: hasPlaces)
            if folds && hasPlaces && navigator.widePath.isEmpty {
                ToolbarItem(placement: .navigation) {
                    placesButton
                }
            }
            // The bar's own Back, after the head: the system's comes
            // before every other item, by the traffic lights (PageBar
            // hides it).
            if !navigator.widePath.isEmpty {
                ToolbarItem(placement: .navigation) {
                    Button {
                        navigator.widePath.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .keyboardShortcut("[", modifiers: .command)
                }
            }
        }
        #endif
    }

    /// Folded, the places' button at the start of a place's header lays
    /// them over the page (Linux's sidebarButton).
    private var placesButton: some View {
        Button {
            // One thing over the page at a time.
            if panel.isShown { panel.isOpen = false }
            showsPlaces = true
        } label: {
            Label("Show Sidebar", systemImage: "sidebar.left")
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

/// The sidebar, as Linux's (spec §4): the mark and the name, then Home and
/// Radio; a hair; the library's kinds; a hair; the playlists
/// themselves with their covers. The place chosen has a quiet fill, as
/// GNOME's sidebar, not the accent.
///
/// Its properties are not private, so its memberwise init is not either.
private struct Places: View {
    @Environment(Navigator.self) var navigator
    @Environment(LibraryStore.self) var library
    @Environment(AppSettings.self) var settings
    /// A place chosen: lying over the page, the places go.
    let chosen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The Mac's is in the title bar's row (BrandHead), and its
            // Settings… in the app menu: "op mac mag het more menutje daar
            // weg omdat je op mac de bovenbalk hebt, hier trumpt native de
            // 1:1 requirement" (the photographer, 14 November 2026).
            #if os(iOS)
            head
            #endif
            ScrollView {
                LazyVStack(spacing: 0) {
                    glyphRow(.home, "Home", symbol: "house")
                    // The mark's template cut, as on Linux: the arch means a
                    // station.
                    if settings.shows(.radio) {
                        PlaceRow(place: .radio, title: Text("Radio"), chosen: chosen) {
                            ArchMark(size: 16, style: .template)
                        }
                    }
                    // No Search: the bar's field is its way in. A hair only
                    // before a group with rows: Home's is never empty.
                    if settings.showsLibrary {
                        hair
                    }
                    glyphRow(.library(.albums), "Albums", symbol: "opticaldisc")
                    glyphRow(.library(.artists), "Artists", symbol: "person.fill")
                    glyphRow(.library(.songs), "Songs", symbol: "music.note")
                    glyphRow(.library(.playlists), "Playlists", symbol: "music.note.list")
                    glyphRow(.library(.favorites), "Favorites", symbol: "heart.fill")
                    // Linux has these three too: "Linux erbij" (the
                    // photographer, 15 November 2026).
                    glyphRow(.library(.genres), "Genres", symbol: "guitars")
                    glyphRow(.library(.recentlyAdded), "Recently Added", symbol: "clock")
                    glyphRow(.library(.downloaded), "Downloaded", symbol: "arrow.down.circle")
                    if settings.shows(.sidebarPlaylists) && !library.playlists.isEmpty {
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
        // One step up from the page's (Theme.raised).
        .background(Theme.raised.ignoresSafeArea())
    }

    #if os(iOS)
    /// The flat mark 20 and the name in the serif, the main menu at the end.
    /// The mark stands over the places' icons and the name over their words
    /// ("heb t gevoel dat het logo linksboven in lijn moet staan met het
    /// icoon van de buttons links", 14 November 2026): an icon sits 20 in
    /// (the row's 8 and its padding 12), its word 16 and 12 further, at 48;
    /// the mark 20 in, 20 wide and 8 from the name, at 48 too.
    private var head: some View {
        HStack(spacing: Theme.Space.s) {
            BrandMark()
            Spacer(minLength: 0)
            MainMenu()
        }
        .padding(.leading, 20)
        .padding(.trailing, Theme.Space.s)
        .frame(height: 48)
    }
    #endif

    /// A hair between groups of rows, 16 tall, as wide as the rows' content.
    private var hair: some View {
        Divider()
            .padding(.horizontal, 20)
            .frame(height: Theme.Space.l)
    }

    /// A place's row, unless Settings › Pages has it off.
    @ViewBuilder
    private func glyphRow(_ place: Place, _ title: LocalizedStringKey, symbol: String) -> some View {
        if settings.shows(place: place) {
            PlaceRow(place: place, title: Text(title), chosen: chosen) {
                Image(systemName: symbol)
                    .desktopFont(15)
            }
        }
    }
}

#if os(iOS)
/// GNOME's primary menu, where Linux's Preferences are: in the places' head,
/// or on Home's bar when there are no places.
private struct MainMenu: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Button("Settings…") {
                navigator.isSettingsPresented = true
            }
            PrivateListeningMenu(store: app.player.notCounted)
            Divider()
            AccountMenuItems(app: app)
        } label: {
            Image(systemName: "line.3.horizontal")
                .desktopFont(15)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Main Menu")
    }
}
#endif

extension Place {
    /// The place's switch in Settings › Pages; Home and Search have none.
    var page: AppSettings.Page? {
        switch self {
        case .home, .search: return nil
        case .playlist: return .sidebarPlaylists
        case .radio, .library: return AppSettings.Page(rawValue: statsName)
        }
    }
}

extension AppSettings {
    /// Whether `place` has its row in the sidebar: Home and Search always.
    func shows(place: Place) -> Bool {
        guard let page = place.page else { return true }
        return shows(page)
    }
}

/// The window bar's part of a wide page, the place's own and each pushed
/// one: the one field for the whole library, at the bar's trailing end,
/// "op dezelfde (os native plek)" (the photographer, 14 November 2026).
/// On the page, not the stack: on the stack the Mac's bar showed no field.
private struct PageBar: ViewModifier {
    var isPushed = false

    @Environment(Navigator.self) private var navigator

    func body(content: Content) -> some View {
        @Bindable var navigator = navigator
        content
            .searchable(text: $navigator.searchQuery, placement: .toolbar)
            .onSubmit(of: .search) {
                navigator.showSearch()
                navigator.searchSubmits += 1
            }
            #if os(macOS)
            .navigationBarBackButtonHidden(isPushed)
            #endif
    }
}

/// The mark, flat at 20, and the name in Linux's brand-name: the serif, 18.
private struct BrandMark: View {
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ArchMark(size: 20)
            Text("Jukebox")
                .desktopFont(18, design: .serif)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

#if os(macOS)
/// The places' head in the Mac's title bar, beside the traffic lights: as
/// wide as what is left of the places there, so what follows it in the bar
/// starts over the page.
private struct BrandHead: View {
    /// Over the places; without them (Settings › Pages) as wide as it is.
    let overPlaces: Bool

    var body: some View {
        BrandMark()
            .frame(width: overPlaces ? CGFloat(DesktopMeasures.sidebar) - 92 : nil, alignment: .leading)
    }
}

/// The head as the title bar's first item. macOS 26 puts glass behind each
/// item, and the mark is no button, so its glass goes. Sequoia's title bar
/// draws nothing behind an item: the mark stands on the bar as it is.
private struct BrandHeadItem: ToolbarContent {
    let overPlaces: Bool

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) {
                BrandHead(overPlaces: overPlaces)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                BrandHead(overPlaces: overPlaces)
            }
        }
    }
}
#endif

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
            // Chosen again, the place's own page, as Linux's Nav.show.
            navigator.place = place
            chosen()
        } label: {
            HStack(spacing: Theme.Space.m) {
                icon
                    .frame(minWidth: 16, minHeight: 16)
                    .opacity(dimsIcon && !isChosen ? 0.6 : 1)
                    .accessibilityHidden(true)
                // GNOME's own row label, 15, as Linux's sidebar.
                title
                    .desktopFont(15)
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
