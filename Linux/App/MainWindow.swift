// The window, as the designer's spec (build/design-round/2027/spec.md, §1)
// has it: a sidebar of places, the place chosen beside it with its own
// Back, the panel of Up next or the lyrics at the right when it is open,
// and the player's bar under all of them. Now Playing is a room over places
// and page; the bar and the panel stay. Narrower, the panel lies over the
// page, then the places fold away and lie over it when asked for
// (libadwaita's overlay split views). Until someone is signed in, the
// sign-in page alone.
//
// Preferences › Pages takes places out of the sidebar
// (AppSettings.hiddenPages), as on the Mac and the iPad; with every one off
// only Home is left and the sidebar goes altogether — the window is Home,
// the panel and the bar: "dan zijn er uberhaupt geen pages" (the
// photographer, 15 November 2026).

import CAdw
import CGlue
import Foundation
import JukeboxKit
import Observation

enum MainWindow {
    private(set) static var window: Widget!
    private static var toasts: Widget!
    private static var split: Widget!
    private static var panel: Widget!
    private static var places: Widget!
    private static var stack: Widget!
    private static var pages: [Int: NavPage] = [:]
    /// The playlists listed under the places, in their rows' order.
    private static var playlists: [Playlist] = []
    private static var playlistRows: [Widget] = []
    /// The hair between Home and Radio and the library's places.
    private static var libraryGap: Widget!
    /// The places' main menu, F10's while there are places.
    private static var placesMenu: Widget!
    /// The place shown, by its row; nil on Search.
    private static var current: Int?
    /// Whether the places are folded away, for the buttons that show them.
    private static let fold = Fold()
    /// The account whose pages are made (OfflinePaths.account's name): when
    /// another is signed in, its Home comes afresh.
    private static var shownAccount: String?
    /// The sign-in page shows over the signed-in window, for Add Account.
    private static var isAddingAccount = false
    /// The primary menu's accounts, one radio item each while there are two
    /// or more: GNOME's quick switch, as in its apps with accounts.
    private static let accountItems = g_menu_new()!

    /// The Search page, reached through the header's field alone (SearchField):
    /// "de search pagina mag uit het menu" (14 November 2026).
    private static var searchPage: NavPage?

    /// The sidebar's places with their icons (spec §4), in order; nil is a
    /// gap between the two groups. Radio's is the mark's template cut. The
    /// Mac's sidebar, 1:1 (WideShell.swift): "Linux erbij", the
    /// photographer, 15 November 2026, of its three more rows.
    private static let sections: [(String, String, AppSettings.Page?, () -> Widget)?] = [
        ("Home", "go-home-symbolic", nil, HomePage.make),
        ("Radio", Glyphs.name("radio"), .radio, RadioPage.make),
        nil,
        ("Albums", "media-optical-symbolic", .albums, LibraryPages.albums),
        ("Artists", "avatar-default-symbolic", .artists, LibraryPages.artists),
        ("Songs", "audio-x-generic-symbolic", .songs, LibraryPages.songs),
        ("Playlists", Glyphs.name("playlists"), .playlists, LibraryPages.playlists),
        ("Favorites", Glyphs.name("heart"), .favorites, LibraryPages.favorites),
        ("Genres", Glyphs.name("genres"), .genres, LibraryPages.genres),
        ("Recently Added", Glyphs.name("clock"), .recentlyAdded, LibraryPages.recentlyAdded),
        // What is on this computer: what plays without a connection.
        ("Downloaded", Glyphs.name("download"), .downloaded, DownloadedPage.make),
    ]

    static func present(in application: UnsafeMutablePointer<AdwApplication>) {
        // A second launch shows the window there is.
        if let window {
            gtk_window_present(ptr(window))
            return
        }
        Style.install()
        window = adw_application_window_new(ptr(application))!
        gtk_window_set_title(ptr(window), "Jukebox")
        // The designer's default and GNOME's least (spec §1): 1440 wide, so
        // the panel opens beside the page, not over it.
        let size = Shots.windowSize ?? (1440, 900)
        gtk_window_set_default_size(ptr(window), size.0, size.1)
        gtk_widget_set_size_request(window, 360, 294)

        stack = gtk_stack_new()!
        let stack = stack!
        gtk_stack_add_named(ptr(stack), adw_bin_new(), "launching")
        gtk_stack_add_named(ptr(stack), SignInPage.make(), "signin")
        gtk_stack_add_named(ptr(stack), main(), "main")
        adw_application_window_set_content(ptr(window), stack)

        observe(stack) {
            switch app.phase {
            case .launching: gtk_stack_set_visible_child_name(ptr(stack), "launching")
            case .signedOut:
                // Signed out of the last account: the pages made for it go.
                if shownAccount != nil { forgetPages() }
                shownAccount = nil
                isAddingAccount = false
                gtk_stack_set_visible_child_name(ptr(stack), "signin")
            case .signedIn:
                // Another account (switched to, added, or the next after a
                // sign-out; nil a moment between two): Home, afresh, and
                // nothing of the last one's pages.
                let account = app.credentials.map { OfflinePaths.account(for: $0) }
                if let account, account != shownAccount {
                    if shownAccount != nil { forgetPages() }
                    shownAccount = account
                    isAddingAccount = false
                }
                guard !isAddingAccount else { return }
                gtk_stack_set_visible_child_name(ptr(stack), "main")
                if pages.isEmpty, account != nil { select(0) }
            }
        }
        followAccounts(application)
        // The player's errors, for a moment, as GNOME shows such things.
        observe(toasts) {
            if let message = app.player.errorMessage { toast(message) }
        }
        action(application, "quit", "<Control>q") { gtk_window_close(ptr(window)) }
        action(application, "search", "<Control>f") { showSearch() }
        action(application, "play", "<Control>space") { app.player.togglePlayPause() }
        action(application, "next", "<Control>Right") { app.player.next() }
        action(application, "previous", "<Control>Left") { app.player.previous() }
        action(application, "preferences", "<Control>comma") { Preferences.present() }
        action(application, "about", nil) { About.present() }
        action(application, "now-playing", "<Control><Shift>n") { if app.player.currentTrack != nil { NowPlayingPage.open() } }
        action(application, "close-now-playing", nil) { NowPlayingPage.close() }
        // Folded, the places come over the page (GNOME's F9).
        action(application, "sidebar", "F9") {
            guard adw_overlay_split_view_get_collapsed(ptr(split)) != 0, app.settings.showsAnyPage else { return }
            adw_overlay_split_view_set_show_sidebar(ptr(split), adw_overlay_split_view_get_show_sidebar(ptr(split)) == 0 ? 1 : 0)
        }
        action(application, "sign-out", nil) { if let account = app.credentials { confirmSignOut(of: account) } }
        action(application, "add-account", nil) { addAccount() }
        // Space plays and pauses wherever the focus is ("op de desktop
        // varianten zou spatie altijd play/pause moeten zijn", 16 November
        // 2026): seen first, in the capture phase, so the button, tile or
        // row with the focus is not pressed by it.
        let space = gtk_shortcut_controller_new()!
        gtk_event_controller_set_propagation_phase(ptr(space), GTK_PHASE_CAPTURE)
        gtk_shortcut_controller_add_shortcut(ptr(space), gtk_shortcut_new(gtk_shortcut_trigger_parse_string("space"),
                                                                      gtk_callback_action_new(spacePlays, nil, nil)))
        gtk_widget_add_controller(window, ptr(space))
        // The window of keys (Ctrl+?), which GTK opens for the window's
        // "show-help-overlay" once it has one.
        gtk_application_window_set_help_overlay(ptr(window), ptr(Shortcuts.window()))
        Mpris.start()
        RadioPage.follow(window)
        Task { await app.restore() }
        gtk_window_present(ptr(window))
        // The drawings are made at the scale of the window's screen.
        Screen.follow(window)
        Shots.walk()
    }

    /// The places over the page where they are folded, for the screenshot
    /// walk; false where they are not folded.
    static func showPlaces() -> Bool {
        guard adw_overlay_split_view_get_collapsed(ptr(split)) != 0 else { return false }
        adw_overlay_split_view_set_show_sidebar(ptr(split), 1)
        return true
    }

    /// The sign-in page whatever the session, for the screenshot walk.
    static func showSignIn() {
        gtk_stack_set_visible_child_name(ptr(stack), "signin")
    }

    /// Add Account (the primary menu, Preferences): the sign-in page over
    /// the window, with Cancel; signed in there, the new account is the
    /// one signed in (AppModel.signIn) and the window comes back on its Home.
    static func addAccount() {
        guard app.phase == .signedIn else { return }
        NowPlayingPage.close()
        isAddingAccount = true
        SignInPage.prepareForAnother()
        gtk_stack_set_visible_child_name(ptr(stack), "signin")
    }

    /// Cancel on the sign-in page over the window.
    static func cancelAddAccount() {
        isAddingAccount = false
        gtk_stack_set_visible_child_name(ptr(stack), "main")
    }

    /// Another saved account: its Home once its server has answered, or a
    /// toast saying why the one signed in stays.
    static func switchAccount(to account: ServerCredentials) {
        Task {
            if let problem = await app.switchAccount(to: account) { toast(problem) }
        }
    }

    static func toast(_ message: String) {
        adw_toast_overlay_add_toast(ptr(toasts), adw_toast_new(message))
    }

    /// The same with the one thing to do about it (Show Playlist).
    static func toast(_ message: String, button: String, _ action: @escaping @MainActor () -> Void) {
        let toast = adw_toast_new(message)!
        adw_toast_set_button_label(toast, button)
        on(toast, "button-clicked", action)
        adw_toast_overlay_add_toast(ptr(toasts), toast)
    }

    /// Signed out: the pages made for that account go.
    static func forgetPages() {
        for page in pages.values + [searchPage].compactMap({ $0 }) { g_object_unref(raw(page)) }
        pages = [:]
        searchPage = nil
        SearchField.shared.home = nil
        SearchField.shared.text = ""
    }

    /// The Search page, with its field's keys: a click in any page's field,
    /// Ctrl+F, or typing on a page. Made once and kept, as a place is.
    static func showSearch() {
        guard app.phase == .signedIn else { return }
        // Over the Search page too, Now Playing makes way.
        NowPlayingPage.close()
        SearchField.shared.loadRecents()
        if searchPage == nil {
            let page = Nav.page("Search", SearchPage.make(), start: [sidebarButton()])
            g_object_ref_sink(raw(page))
            searchPage = page
            SearchField.shared.home = Nav.searchField(of: page)
        }
        if adw_navigation_view_get_visible_page(ptr(Nav.view)) != searchPage {
            Nav.show(searchPage!)
            // No place in the sidebar is the one shown.
            gtk_list_box_unselect_all(ptr(places))
            current = nil
            if adw_overlay_split_view_get_collapsed(ptr(split)) != 0 { adw_overlay_split_view_set_show_sidebar(ptr(split), 0) }
            Stats.track(.screen, ["name": "search"])
        }
        SearchField.shared.focus()
    }

    static func select(_ index: Int) {
        guard let row = gtk_list_box_get_row_at_index(ptr(places), Int32(index)) else { return }
        gtk_list_box_select_row(ptr(places), row)
        show(index)
    }

    private static func show(_ index: Int) {
        // A playlist under the places, after their gap: a place of its own.
        if index > sections.count, playlists.indices.contains(index - sections.count - 1) {
            current = index
            Pages.open(playlists[index - sections.count - 1], place: [sidebarButton()])
            if adw_overlay_split_view_get_collapsed(ptr(split)) != 0 { adw_overlay_split_view_set_show_sidebar(ptr(split), 0) }
            return
        }
        guard sections.indices.contains(index), let (title, _, kind, make) = sections[index] else { return }
        current = index
        // A place is made when first chosen and kept: going back to Albums
        // finds it where it was left.
        if pages[index] == nil {
            let page = Nav.page(title, make(), start: [sidebarButton()], end: ends(of: kind))
            g_object_ref_sink(raw(page))
            pages[index] = page
        }
        Nav.show(pages[index]!)
        // Chosen from the places lying over the page: the page.
        if adw_overlay_split_view_get_collapsed(ptr(split)) != 0 { adw_overlay_split_view_set_show_sidebar(ptr(split), 0) }
        // Which places are used (docs/STATS.md, `screen`): its kind, in the
        // list's own words.
        Stats.track(.screen, ["name": title.lowercased().replacingOccurrences(of: " ", with: "_")])
    }

    private static func main() -> Widget {
        places = gtk_list_box_new()!.css("navigation-sidebar")
        for section in sections {
            if let (title, icon, _, _) = section {
                // The icon 16 at 60 % (full when chosen), 12, the place.
                let image = gtk_image_new_from_icon_name(icon)!.css("place-icon")
                let row = gtk_list_box_row_new()!
                gtk_list_box_row_set_child(ptr(row), hbox(spacing: 12, [image, label(title, "t15")]))
                gtk_list_box_append(ptr(places), row)
            } else {
                libraryGap = gapRow()
                gtk_list_box_append(ptr(places), libraryGap)
            }
        }
        on(raw(places), "row-activated", argument: { row in
            guard let row else { return }
            show(Int(gtk_list_box_row_get_index(ptr(row))))
        })
        // The playlists themselves under a gap, each with its cover 32 (a
        // collage of its first albums' when it has none of its own).
        observe(places) {
            let listed = app.library.playlists
            // Preferences › Pages' Playlists in the Sidebar: the hair and
            // the rows, made or not.
            let shown = app.settings.shows(.sidebarPlaylists)
            defer { for row in playlistRows { row.isVisible = shown } }
            guard listed.map(\.id) != playlists.map(\.id) else { return }
            for row in playlistRows { gtk_list_box_remove(ptr(places), row) }
            playlistRows = []
            playlists = listed
            guard !listed.isEmpty else { return }
            playlistRows.append(gapRow())
            for playlist in listed {
                let art = Art(32)
                art.emptyIcon = Glyphs.name("playlists")
                art.show(playlist.artwork)
                if playlist.artwork == nil {
                    Task { if let tracks = try? await app.library.tracks(in: playlist) { art.show(collage: Pages.firstCovers(tracks)) } }
                }
                let row = gtk_list_box_row_new()!.css("playlist")
                gtk_list_box_row_set_child(ptr(row), hbox(spacing: 12, [art.widget, label(playlist.name, "t15")]))
                keep(art, on: raw(row), as: "art")
                playlistRows.append(row)
            }
            for row in playlistRows { gtk_list_box_append(ptr(places), row) }
        }

        let menu = mainMenu()
        placesMenu = menu
        let sidebar = adw_toolbar_view_new()!
        let header = adw_header_bar_new()!
        // The flat mark 20 and the name in the serif, where the title was.
        adw_header_bar_set_show_title(ptr(header), 0)
        // The mark stands over the places' icons and the name over their
        // words ("heb t gevoel dat het logo linksboven in lijn moet staan
        // met het icoon van de buttons links", 14 November 2026): an icon
        // sits 20 in (row margin 8, padding 12), the header's own start 8.
        let brand = hbox(spacing: 8, [brandMark(), label("Jukebox", "serif", "brand-name")])
        gtk_widget_set_margin_start(brand, 12)
        adw_header_bar_pack_start(ptr(header), brand)
        adw_header_bar_pack_end(ptr(header), menu)
        adw_toolbar_view_add_top_bar(ptr(sidebar), header)
        adw_toolbar_view_set_content(ptr(sidebar), scrolled(places))

        Nav.view = adw_navigation_view_new()!
        // The places beside the pages, 240 at every width (spec §4). Not a
        // navigation split view: folded, that one turns the places into a
        // page behind Back, which is wrong for places switched all the
        // time; this one lays them over the page when asked for.
        split = adw_overlay_split_view_new()!
        adw_overlay_split_view_set_sidebar(ptr(split), sidebar)
        adw_overlay_split_view_set_content(ptr(split), pageBin())
        adw_overlay_split_view_set_min_sidebar_width(ptr(split), Double(DesktopMeasures.sidebar))
        adw_overlay_split_view_set_max_sidebar_width(ptr(split), Double(DesktopMeasures.sidebar))
        on(raw(split), "notify::collapsed") { fold.isCollapsed = adw_overlay_split_view_get_collapsed(ptr(split)) != 0 }
        followPages()

        // The panel around places, pages and Now Playing, so it stays where
        // it was in each (spec §6).
        panel = adw_overlay_split_view_new()!.css("panel-split")
        adw_overlay_split_view_set_sidebar_position(ptr(panel), GTK_PACK_END)
        adw_overlay_split_view_set_content(ptr(panel), NowPlayingPage.room(over: split))
        adw_overlay_split_view_set_sidebar(ptr(panel), Panel.make())
        // 360 at every width, so it stays on the grid (the designer's spec,
        // §3: min = max, the fraction never applies).
        adw_overlay_split_view_set_min_sidebar_width(ptr(panel), Double(DesktopMeasures.panel))
        adw_overlay_split_view_set_max_sidebar_width(ptr(panel), Double(DesktopMeasures.panel))
        // Open or closed is the listener's (PanelState), not libadwaita's.
        adw_overlay_split_view_set_pin_sidebar(ptr(panel), 1)
        followPanel()

        let whole = adw_toolbar_view_new()!
        // Toasts over the content only, never over the player's controls
        // ("ik wil die melding echt niet over de controls hebben").
        toasts = adw_toast_overlay_new()!
        adw_toast_overlay_set_child(ptr(toasts), panel)
        adw_toolbar_view_set_content(ptr(whole), toasts)
        adw_toolbar_view_add_bottom_bar(ptr(whole), PlayerBar.make())
        adw_toolbar_view_set_bottom_bar_style(ptr(whole), ADW_TOOLBAR_RAISED)
        breakpoints()
        return whole
    }

    /// GNOME's primary menu: F10 opens it; its items are the app's actions,
    /// so their keys show beside them. In the places' header; with none
    /// (Preferences › Pages, every page off) at the end of every page's,
    /// or Preferences could never be reached to bring them back.
    static func mainMenu() -> Widget {
        let menu = gtk_menu_button_new()!.tooltip("Main Menu")
        gtk_menu_button_set_icon_name(ptr(menu), "open-menu-symbolic")
        gtk_menu_button_set_menu_model(ptr(menu), ptr(menuItems))
        gtk_menu_button_set_primary(ptr(menu), 1)
        return menu
    }

    private static let menuItems: OpaquePointer = {
        let items = g_menu_new()!
        g_menu_append(items, "Preferences", "app.preferences")
        g_menu_append(items, "Keyboard Shortcuts", "win.show-help-overlay")
        g_menu_append(items, "About Jukebox", "app.about")
        g_menu_append_section(items, nil, ptr(accountItems))
        return items
    }()

    /// The primary menu's accounts: with two or more, each a radio item
    /// (its server and user), the one signed in chosen, a click switches;
    /// then Add Account… and Sign Out… (of the one signed in).
    private static func followAccounts(_ application: UnsafeMutablePointer<AdwApplication>) {
        let chosen = g_simple_action_new_stateful("account", g_variant_type_new("s"), g_variant_new_string(""))!
        on(raw(chosen), "activate", argument: { parameter in
            guard let parameter else { return }
            let key = String(cString: g_variant_get_string(OpaquePointer(parameter), nil))
            guard let account = app.accounts.saved.first(where: { OfflinePaths.account(for: $0) == key }) else { return }
            switchAccount(to: account)
        })
        g_action_map_add_action(ptr(application), ptr(chosen))
        observe(stack) {
            let saved = app.accounts.saved
            let active = app.credentials
            g_menu_remove_all(accountItems)
            if saved.count > 1 {
                for account in saved {
                    let item = g_menu_item_new("\(ServerWords.name(of: account)) · \(account.userName)", nil)!
                    g_menu_item_set_action_and_target_value(item, "app.account",
                                                            g_variant_new_string(OfflinePaths.account(for: account)))
                    g_menu_append_item(accountItems, item)
                    g_object_unref(raw(item))
                }
            }
            g_menu_append(accountItems, "Add Account…", "app.add-account")
            // Of the account chosen above; its dialog names it.
            g_menu_append(accountItems, "Sign Out…", "app.sign-out")
            g_simple_action_set_state(chosen, g_variant_new_string(active.map { OfflinePaths.account(for: $0) } ?? ""))
        }
    }

    /// Preferences › Pages, as the Mac's sidebar follows it: a place off
    /// leaves the sidebar; the hair before the library's places only while
    /// one of them is there (the playlists' follows their own switch); the
    /// place shown switched off, Home. Every one off: no sidebar at all,
    /// folded or not, and nothing that brings it back but Preferences.
    private static func followPages() {
        observe(places) {
            let settings = app.settings
            for (index, section) in sections.enumerated() {
                guard let section, let page = section.2,
                      let row = gtk_list_box_get_row_at_index(ptr(places), Int32(index)) else { continue }
                ptr(row).isVisible = settings.shows(page)
            }
            libraryGap.isVisible = settings.showsLibrary
            let hasPlaces = settings.showsAnyPage
            // F10 is one menu's: the places', or with none the page's.
            gtk_menu_button_set_primary(ptr(placesMenu), hasPlaces ? 1 : 0)
            // Nor does a swipe from the edge bring them.
            adw_overlay_split_view_set_enable_show_gesture(ptr(split), hasPlaces ? 1 : 0)
            if !hasPlaces {
                adw_overlay_split_view_set_show_sidebar(ptr(split), 0)
            } else if !fold.isCollapsed {
                // Unfolded the places show, as libadwaita shows them itself
                // when a window widens: again after a switch made them go.
                adw_overlay_split_view_set_show_sidebar(ptr(split), 1)
            }
            guard let current, !shows(current, settings) else { return }
            select(0)
        }
    }

    /// A place's own button beside the search field, where the Mac's bar
    /// has it: Radio's Start a Station, Playlists' New Playlist….
    private static func ends(of page: AppSettings.Page?) -> [Widget] {
        switch page {
        case .radio?:
            let start = iconButton("list-add-symbolic", "Start a Station", "flat") { StationPicker.present() }
            observe(start) { start.isSensitive = !app.library.tracks.isEmpty }
            return [start.align(vertical: GTK_ALIGN_CENTER)]
        case .playlists?:
            return [iconButton("list-add-symbolic", "New Playlist…", "flat") { Playlists.create() }.align(vertical: GTK_ALIGN_CENTER)]
        default:
            return []
        }
    }

    /// Whether the place at `index` has its row (Home's always).
    private static func shows(_ index: Int, _ settings: AppSettings) -> Bool {
        if index > sections.count { return settings.shows(.sidebarPlaylists) }
        guard sections.indices.contains(index), let page = sections[index]?.2 else { return true }
        return settings.shows(page)
    }

    /// A hair between groups of rows, 16 tall, neither chosen nor played.
    private static func gapRow() -> Widget {
        let row = gtk_list_box_row_new()!.css("gap")
        gtk_list_box_row_set_child(ptr(row), hairline().align(vertical: GTK_ALIGN_CENTER))
        gtk_list_box_row_set_activatable(ptr(row), 0)
        gtk_list_box_row_set_selectable(ptr(row), 0)
        return row
    }

    /// The flat mark, 20: Copper outside, Glow inside, the core light.
    private static func brandMark() -> Widget {
        let mark = gtk_image_new()!
        gtk_image_set_pixel_size(ptr(mark), 20)
        observe(mark) {
            let scale = Screen.shared.scale
            Task {
                guard let texture = await drawn("flat mark 20", width: 20, height: 20, scale: scale, { cr, _ in
                    Draw.mark(cr, size: 20, outer: 0xA84A17, inner: 0xFFB54D, core: 0xFFF1D6)
                }) else { return }
                gtk_image_set_from_paintable(ptr(mark), texture.pointer)
            }
        }
        return mark
    }

    /// The pages in an AdwBreakpointBin, so their measures follow the page's
    /// own width, not the window's (spec §5): the panel opened beside a
    /// page keeps its proportions. Each breakpoint is a row of the spec's
    /// table (DesktopMeasures.pages), from the width it starts at.
    private static func pageBin() -> Widget {
        let bin = adw_breakpoint_bin_new()!
        // Without these it has no least size at all (spec §5).
        gtk_widget_set_size_request(bin, 360, 294)
        adw_breakpoint_bin_set_child(ptr(bin), Nav.view)
        // Narrowest first: of those that match, the last added applies. The
        // narrowest row has one too (from 0), so one always applies and
        // tells PageMeasure, at every width.
        let rows = DesktopMeasures.pages
        let breakpoints = rows.map { row in
            let breakpoint = adw_breakpoint_new(adw_breakpoint_condition_parse("min-width: \(row.from)px"))!
            adw_breakpoint_bin_add_breakpoint(ptr(bin), breakpoint)
            return breakpoint
        }
        on(raw(bin), "notify::current-breakpoint") {
            let current = adw_breakpoint_bin_get_current_breakpoint(ptr(bin))
            guard let page = zip(breakpoints, rows).first(where: { $0.0 == current })?.1.page else { return }
            // Told while the bin is allocated: the pages change after it.
            Task { PageMeasure.shared.set(margin: Int32(page.margin), tile: Int32(page.tile), columns: page.columns) }
        }
        return bin
    }

    /// The places' button at the start of a place's header: shown while
    /// they are folded away, it lays them over the page.
    private static func sidebarButton() -> Widget {
        let button = gtk_toggle_button_new()!.tooltip("Show Sidebar")
        gtk_button_set_icon_name(ptr(button), "sidebar-show-symbolic")
        // Only while they are folded away, and only while there are any.
        observe(button) { button.isVisible = fold.isCollapsed && app.settings.showsAnyPage }
        g_object_bind_property(raw(split), "show-sidebar", raw(button), "active",
                               GBindingFlags(G_BINDING_SYNC_CREATE.rawValue | G_BINDING_BIDIRECTIONAL.rawValue))
        return button
    }

    /// The panel shows as PanelState says, with a song loaded (its buttons
    /// are in the player's bar, hidden without one). Lying over the page,
    /// it is closed by a click beside it or Escape, as the listener's own
    /// closing.
    private static func followPanel() {
        var isSetting = false
        observe(panel) {
            let shown = app.panel.isShown && app.player.currentTrack != nil
            isSetting = true
            adw_overlay_split_view_set_show_sidebar(ptr(panel), shown ? 1 : 0)
            isSetting = false
        }
        on(raw(panel), "notify::show-sidebar") {
            guard !isSetting else { return }
            if adw_overlay_split_view_get_show_sidebar(ptr(panel)) == 0 && app.panel.isOpen { app.panel.isOpen = false }
        }
        on(raw(panel), "notify::collapsed") {
            app.panel.isOverlaid = adw_overlay_split_view_get_collapsed(ptr(panel)) != 0
        }
    }

    /// The designer's breakpoints (spec §1, §2), by the window's width: below
    /// 1280 the panel lies over the page; below 900 the sidebar folds and
    /// the volume becomes a button. Below 600 the spec has the iPhone's mini
    /// player, not built yet: until then the bar's times and volume go. One
    /// breakpoint applies at a time (the last that matches), so each repeats
    /// the wider ones'.
    private static func breakpoints() {
        let overlaid: [(Widget, String, Bool)] = [(panel!, "collapsed", true)]
        // Below 900 the heart and Not This go into the song's menu.
        let narrow = overlaid + [(split!, "collapsed", true), (PlayerBar.volume!, "visible", false),
                                 (PlayerBar.volumeButton!, "visible", true), (PlayerBar.songActions!, "visible", false)]
        // ponytail: below 600 the bar only loses its times and the volume
        // (the desktop's own volume remains), so it fits the window's least
        // 360; the spec's mini player there is a later round.
        let least = overlaid + [(split!, "collapsed", true), (PlayerBar.volume!, "visible", false),
                                (PlayerBar.songActions!, "visible", false)]
            + PlayerBar.times.map { ($0, "visible", false) }
        // grid-ok: conditions, not distances (the spec's 1279, 899, 599)
        for (condition, setters) in [("max-width: 1279px", overlaid), ("max-width: 899px", narrow),
                                     ("max-width: 599px", least)] { // grid-ok: a condition
            let breakpoint = jb_breakpoint(window, condition)
            for (object, property, value) in setters {
                jb_breakpoint_set(breakpoint, raw(object), property, value ? 1 : 0)
            }
        }
    }

    /// Signing out forgets that account's library on this computer: asked
    /// first, as GNOME asks before what cannot be taken back at a click.
    /// With more than one account it says which, and what stays: the others,
    /// and the one Jukebox goes on with.
    static func confirmSignOut(of account: ServerCredentials) {
        guard app.phase == .signedIn, let active = app.credentials else { return }
        let name = ServerWords.name(of: account)
        let others = app.accounts.saved.filter { !$0.isSameAccount(as: account) }
        let body: String
        if others.isEmpty {
            body = "The library and the songs downloaded to this computer are removed. Your music and playlists stay on your server."
        } else if account.isSameAccount(as: active), let next = others.first {
            body = "Its library and the songs downloaded for it are removed from this computer, and Jukebox goes on with \(ServerWords.name(of: next)). Your music and playlists stay on the server."
        } else {
            body = "Its library and the songs downloaded for it are removed from this computer. Your music and playlists stay on the server."
        }
        let dialog = adw_alert_dialog_new(others.isEmpty ? "Sign Out?" : "Sign Out of \(name) as \(account.userName)?", body)!
        adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
        adw_alert_dialog_add_response(ptr(dialog), "sign-out", "Sign Out")
        adw_alert_dialog_set_response_appearance(ptr(dialog), "sign-out", ADW_RESPONSE_DESTRUCTIVE)
        adw_alert_dialog_set_default_response(ptr(dialog), "cancel")
        adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
        on(raw(dialog), "response", argument: { response in
            guard let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "sign-out" else { return }
            // The pages follow the account signed in (`present`'s observer).
            Task { await app.signOut(account) }
        })
        adw_dialog_present(ptr(dialog), window)
    }

    /// An action of the application's, with its key when it has one
    /// (GNOME's shortcuts are actions with accelerators, and its menus
    /// show them).
    private static func action(_ application: UnsafeMutablePointer<AdwApplication>, _ name: String,
                               _ key: String?, _ run: @escaping @MainActor () -> Void) {
        let simple = g_simple_action_new(name, nil)!
        on(raw(simple), "activate", run)
        g_action_map_add_action(ptr(application), ptr(simple))
        guard let key else { return }
        key.withCString { key in
            var keys: [UnsafePointer<CChar>?] = [key, nil]
            gtk_application_set_accels_for_action(ptr(application), "app.\(name)", &keys)
        }
    }
}

/// Space's play or pause. A field typed in (Search, the sign-in's, a
/// playlist's name, a dialog's) keeps its space: unhandled, the key goes on
/// to it.
private let spacePlays: GtkShortcutFunc = { window, _, _ in
    if let window, let focus = gtk_root_get_focus(ptr(window)),
       g_type_check_instance_is_a(ptr(focus), gtk_editable_get_type()) != 0 { return 0 }
    MainActor.assumeIsolated { app.player.togglePlayPause() }
    return 1
}

/// The keys, as GNOME shows an app's (Main Menu › Keyboard Shortcuts, Ctrl+?).
enum Shortcuts {
    static func window() -> Widget {
        func shortcut(_ title: String, _ key: String) -> String {
            "<child><object class='GtkShortcutsShortcut'><property name='title'>\(title)</property>"
                + "<property name='accelerator'>\(key)</property></object></child>"
        }
        func group(_ title: String, _ shortcuts: [String]) -> String {
            "<child><object class='GtkShortcutsGroup'><property name='title'>\(title)</property>"
                + shortcuts.joined() + "</object></child>"
        }
        let xml = "<interface><object class='GtkShortcutsWindow' id='shortcuts'><property name='modal'>1</property>"
            + "<child><object class='GtkShortcutsSection'><property name='section-name'>shortcuts</property>"
            + group("Playing", [shortcut("Play or Pause", "space &lt;Control&gt;space"),
                                shortcut("Next Song", "&lt;Control&gt;Right"),
                                shortcut("Previous Song", "&lt;Control&gt;Left")])
            // The screen is Full Player (the photographer, 15 November 2026).
            + group("Places", [shortcut("Full Player", "&lt;Control&gt;&lt;Shift&gt;n"),
                               shortcut("Show Sidebar", "F9")])
            + group("General", [shortcut("Search", "&lt;Control&gt;f"),
                                shortcut("Preferences", "&lt;Control&gt;comma"),
                                shortcut("Main Menu", "F10"),
                                shortcut("Keyboard Shortcuts", "&lt;Control&gt;question"),
                                shortcut("Back", "&lt;Alt&gt;Left"),
                                shortcut("Quit", "&lt;Control&gt;q")])
            + "</object></child></object></interface>"
        let builder = gtk_builder_new_from_string(xml, -1)
        let window: Widget = ptr(raw(gtk_builder_get_object(builder, "shortcuts")))
        // The builder goes; the window is then the application window's.
        g_object_ref(raw(window))
        g_object_unref(raw(builder!))
        return window
    }
}

enum About {
    static func present() {
        let dialog = adw_about_dialog_new()!
        adw_about_dialog_set_application_name(ptr(dialog), "Jukebox")
        adw_about_dialog_set_version(ptr(dialog), "1.1")
        adw_about_dialog_set_application_icon(ptr(dialog), "com.tijmen.Jukebox")
        adw_about_dialog_set_developer_name(ptr(dialog), "Tijmen")
        adw_about_dialog_set_comments(ptr(dialog), "Music from your Jellyfin, Navidrome or other Subsonic server, with a radio that plays on from anything.")
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }
}

/// Whether the places are folded away (libadwaita's `collapsed`), where the
/// buttons that show them, and Preferences › Pages, can follow it.
@Observable
private final class Fold {
    var isCollapsed = false
}
