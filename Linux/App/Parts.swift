// The parts every screen is made of: a page's title and sections, a song's
// row, a cover's tile, a shelf, a row's menu. tells.md's rules live here so
// a screen cannot break them by accident: titles in the serif, facts under
// them, content on the ground, left-aligned.

import CAdw
import CGlue
import Foundation
import JukeboxKit
import Observation

// MARK: Navigation

/// The content pane's stack of pages (libadwaita's navigation view: Back,
/// its swipe and Alt+Left are its own).
enum Nav {
    static var view: Widget!

    /// A page: GNOME's header bar, flat on the page's ground, over the
    /// content. Its title shows only once the page's own serif title has
    /// scrolled under it (spec §5). At the header's end, on every page, the
    /// search field (SearchField): "ik wil die searchbar gewoon bovenin de
    /// vensterbar hebben" (the photographer, 14 November 2026).
    static func page(_ title: String, _ content: Widget, start: [Widget] = [], end: [Widget] = []) -> NavPage {
        let toolbar = adw_toolbar_view_new()!
        let header = adw_header_bar_new()!
        for widget in start { adw_header_bar_pack_start(ptr(header), widget) }
        // The places' main menu, here when there are no places.
        let menu = MainWindow.mainMenu()
        observe(menu) {
            let shown = !app.settings.showsAnyPage
            menu.isVisible = shown
            // F10's only while it shows: the places' has it otherwise.
            gtk_menu_button_set_primary(ptr(menu), shown ? 1 : 0)
        }
        adw_header_bar_pack_end(ptr(header), menu)
        let search = SearchField.entry(typingIn: toolbar)
        adw_header_bar_pack_end(ptr(header), search)
        for widget in end { adw_header_bar_pack_end(ptr(header), widget) }
        adw_header_bar_set_show_title(ptr(header), 0)
        if g_type_check_instance_is_a(ptr(content), gtk_scrolled_window_get_type()) != 0,
           let adjustment = gtk_scrolled_window_get_vadjustment(ptr(content)) {
            // The serif title's foot: 24 under the header, 48 tall.
            on(raw(adjustment), "value-changed") {
                adw_header_bar_set_show_title(ptr(header), gtk_adjustment_get_value(adjustment) > 72 ? 1 : 0)
            }
        }
        adw_toolbar_view_add_top_bar(ptr(toolbar), header)
        adw_toolbar_view_set_content(ptr(toolbar), content)
        let page = adw_navigation_page_new(toolbar, title)!
        g_object_set_data(ptr(raw(page)), "jukebox-search", raw(search))
        return page
    }

    /// The search field in `page`'s header.
    static func searchField(of page: NavPage) -> Widget? {
        g_object_get_data(ptr(raw(page)), "jukebox-search").map { $0.assumingMemoryBound(to: GtkWidget.self) }
    }

    /// A page opened from anywhere, Now Playing too: Now Playing makes way.
    static func push(_ title: String, _ content: Widget, end: [Widget] = []) {
        NowPlayingPage.close()
        adw_navigation_view_push(ptr(view), page(title, content, end: end))
    }

    /// One page alone: a section chosen in the sidebar.
    static func show(_ page: NavPage) {
        NowPlayingPage.close()
        var pages: [NavPage?] = [page]
        adw_navigation_view_replace(ptr(view), &pages, 1)
    }
}

// MARK: The page's measures

/// The page's margin, tile and columns, by the page's own width, not the
/// window's (spec §5): the same 1440 window gives a 1200 page with the panel
/// closed and an 840 one with it open, and each keeps its proportions.
/// MainWindow's AdwBreakpointBin sets them.
@Observable
final class PageMeasure {
    static let shared = PageMeasure()
    private(set) var margin: Int32 = 40
    private(set) var tile: Int32 = 176
    /// Played lately's columns.
    private(set) var columns = 2
    /// An album's cover: 160 under 720.
    var cover: Int32 { margin == 24 ? 160 : 224 }

    func set(_ page: DesktopMeasures.Page) {
        if Int32(page.margin) != margin { margin = Int32(page.margin) }
        if Int32(page.tile) != tile { tile = Int32(page.tile) }
        if page.columns != columns { columns = page.columns }
    }
}

/// A page's column, scrolling: its content from the margin, the shelves
/// running on past the page's right edge so the next tile peeks in.
func pageColumn(_ content: Widget) -> Widget {
    gtk_widget_set_margin_bottom(content, 40)
    observe(content) { measure(content) }
    return scrolled(content).expand(vertical: true)
}

/// The margin on a page's column: at its start, and at the end of all but
/// its shelves. A "group" is a box of the column's parts, measured inside.
/// Called again by a page that fills its column anew.
func measure(_ column: Widget) {
    let margin = PageMeasure.shared.margin
    gtk_widget_set_margin_start(column, margin)
    func ends(_ box: Widget) {
        var child = gtk_widget_get_first_child(box)
        while let widget = child {
            if gtk_widget_has_css_class(widget, "group") != 0 {
                gtk_widget_set_margin_end(widget, 0)
                ends(widget)
            } else {
                // A shelf and Home's row of cards run on to the page's edge.
                let runsOn = gtk_widget_has_css_class(widget, "shelf") != 0 || gtk_widget_has_css_class(widget, "card-row") != 0
                gtk_widget_set_margin_end(widget, runsOn ? 0 : margin)
            }
            child = gtk_widget_get_next_sibling(widget)
        }
    }
    ends(column)
}

// MARK: Headings

/// A page's own title in the serif, 24 under the header, with at most one
/// fact under it.
func pageTitle(_ title: String, fact: String? = nil) -> Widget {
    let column = vbox(spacing: 4, [label(title, "serif", "page-title", lines: 2)])
    if let fact, !fact.isEmpty { append(label(fact, "t13", "fact", lines: 2), to: column) }
    gtk_widget_set_margin_top(column, 24)
    return column
}

/// A section's heading: sentence case, in the serif, a fact beside it; 40
/// above it, `below` (16) to what it heads.
func sectionTitle(_ title: String, fact: String? = nil, below: Int32 = 16) -> Widget {
    let row = hbox(spacing: 12, [label(title, "serif", "section-title").align(vertical: GTK_ALIGN_BASELINE_FILL)])
    if let fact { append(label(fact, "t13", "fact").align(vertical: GTK_ALIGN_BASELINE_FILL), to: row) }
    gtk_widget_set_margin_top(row, 40)
    gtk_widget_set_margin_bottom(row, below)
    return row
}

/// What a page says when it has nothing to show: one plain line of what
/// to do, where its content would start, under the title and on its margin
/// — not a status page in the middle of the page ("favourites heeft een
/// vage empty state", the photographer, 14 November 2026).
func emptyLine(_ text: String) -> Widget {
    let line = label(text, "fact", lines: 0)
    gtk_widget_set_margin_top(line, 24)
    return line
}

/// The library not there yet, or not at all (Home before it has loaded):
/// libadwaita's status page, the whole window's state, with no page under it.
func emptyPage(_ title: String, _ description: String) -> Widget {
    let page = adw_status_page_new()!
    adw_status_page_set_title(ptr(page), title)
    // A status page's description is Pango markup, and an error's words
    // can be the server's: escaped, so they show as they are.
    let escaped = g_markup_escape_text(description, -1)
    adw_status_page_set_description(ptr(page), escaped)
    g_free(escaped)
    return page.expand(vertical: true)
}

// MARK: Menus
// GNOME's own menus (a GMenu shown by GtkPopoverMenu), so they look, move
// and read to a screen reader as every other app's; the items are Swift
// closures, each an action of the menu's own.

/// What a menu's click runs.
private nonisolated final class PointHandler {
    let run: @MainActor (Double, Double) -> Void
    init(_ run: @escaping @MainActor (Double, Double) -> Void) { self.run = run }
}

/// What separates the parts of a choice's title (`submenuChoice`): a
/// control character no menu's words have.
private let submenuMark: Character = "\u{1F}"

/// A choice under a submenu, as a menu's title: `popoverMenu` puts it under
/// `submenu`, ticked when `checked`. Menus stay lists of (title, action),
/// as every caller builds them. Only under a submenu: GTK keeps room for a
/// check mark before every item of the menu page that holds one, so a
/// check in a menu itself puts all of its items in from GNOME's edge
/// (Rating's marks stay on Rating's own page).
func submenuChoice(_ submenu: String, _ title: String, checked: Bool) -> String {
    [submenu, title, checked ? "checked" : ""].joined(separator: String(submenuMark))
}

/// An item under a submenu with no check mark, as a menu's title: Credits'
/// people. `enabled` false greys it (someone not in the library).
func submenuItem(_ submenu: String, _ title: String, enabled: Bool) -> String {
    [submenu, title, "plain", enabled ? "on" : "off"].joined(separator: String(submenuMark))
}

/// Credits › who made the song, by role ("Composer: Clara Schumann"), in a
/// song's menu where the server gave any (Navidrome's contributors,
/// Jellyfin's composer): the sleeve's back, quietly, as the Mac's Credits
/// submenu. One opens the artist's page when the library has them.
func creditItems(_ track: Track) -> [(String, () -> Void)] {
    // The library's copy: Jellyfin's composers are read with the library,
    // not with a playlist's or the queue's songs.
    let known = app.library.track(id: track.id) ?? track
    return LibraryIndex.creditGroups(known).flatMap { group in
        group.credits.map { credit -> (String, () -> Void) in
            let artist = app.library.artist(credit.artist)
            return (submenuItem("Credits", "\(group.role): \(LibraryIndex.creditName(credit))", enabled: artist != nil),
                    { if let artist { Pages.open(artist) } })
        }
    }
}

/// Rating › None and one to five stars, the given one ticked: beside the
/// favourite in a song's and an album's menu, on a server that keeps
/// ratings, as the Mac's RatingMenu. Nothing elsewhere ("ik wil alleen er
/// voor waken dat we niet 10000 knopen krijgen", 17 November 2026).
func ratingItems(_ item: ItemRef) -> [(String, () -> Void)] {
    guard app.library.can(.rating) else { return [] }
    let given = app.library.rating(item) ?? 0
    return (0...5).map { stars -> (String, () -> Void) in
        let title = stars == 0 ? "None" : String(repeating: "★", count: stars)
        return (submenuChoice("Rating", title, checked: stars == given),
                { Task { await app.library.setRating(stars, item: item) } })
    }
}

/// Copy Share Link, on a server that shares (ShareLinks.swift): the server
/// makes the link on the click, it goes to the clipboard, a toast says so.
func shareItems(_ id: ItemID, tracks: [ItemID]) -> [(String, () -> Void)] {
    guard app.library.can(.share) else { return [] }
    return [("Copy Share Link", {
        Task {
            guard let url = await app.library.shareLink(for: id, tracks: tracks),
                  let display = gdk_display_get_default() else {
                MainWindow.toast(String(localized: "The server did not make a link."))
                return
            }
            gdk_clipboard_set_text(gdk_display_get_clipboard(display), url.absoluteString)
            MainWindow.toast(String(localized: "Link copied"))
        }
    })]
}

/// Where a menu's next section starts: GNOME's menus come in groups
/// with a line between them ("en ook bij linux die menutjes ff mooier
/// structureren", the photographer, 20 November 2026). A list of
/// (title, action) still, so every menu is built as before.
let menuBreak: (String, () -> Void) = ("\u{1E}", {})

/// Groups as one menu, a break between each that has something.
func menuSections(_ groups: [(String, () -> Void)]...) -> [(String, () -> Void)] {
    groups.filter { !$0.isEmpty }.enumerated().flatMap { index, group in index == 0 ? group : [menuBreak] + group }
}

/// A menu of `items` as a popover, a section between breaks
/// (`menuBreak`; an empty one is left out).
func popoverMenu(_ items: [(String, () -> Void)]) -> Widget {
    let menu = g_menu_new()!
    let actions = g_simple_action_group_new()!
    var section = g_menu_new()!
    var submenus: [String: OpaquePointer] = [:]
    func close() {
        if g_menu_model_get_n_items(ptr(section)) > 0 { g_menu_append_section(menu, nil, ptr(section)) }
        g_object_unref(raw(section))
    }
    for (index, (title, action)) in items.enumerated() {
        if title == menuBreak.0 {
            guard g_menu_model_get_n_items(ptr(section)) > 0 else { continue }
            close()
            section = g_menu_new()!
            continue
        }
        // A choice (`submenuChoice`) goes under its submenu, made where
        // its first choice is, with a check mark: an action with a state.
        let parts = title.split(separator: submenuMark, omittingEmptySubsequences: false).map(String.init)
        let isChoice = parts.count == 3
        let isUnder = isChoice || parts.count == 4
        let simple = isChoice
            ? g_simple_action_new_stateful("item\(index)", nil, g_variant_new_boolean(parts[2].isEmpty ? 0 : 1))!
            : g_simple_action_new("item\(index)", nil)!
        if parts.count == 4, parts[3] == "off" { g_simple_action_set_enabled(simple, 0) }
        on(raw(simple), "activate") { action() }
        g_action_map_add_action(ptr(actions), ptr(simple))
        guard isUnder, !parts[0].isEmpty else {
            g_menu_append(section, isUnder ? parts[1] : title, "menu.item\(index)")
            continue
        }
        let submenu = submenus[parts[0]] ?? {
            let made = g_menu_new()!
            g_menu_append_submenu(section, parts[0], ptr(made))
            submenus[parts[0]] = made
            return made
        }()
        g_menu_append(submenu, parts[1], "menu.item\(index)")
    }
    close()
    let popover = gtk_popover_menu_new_from_model(ptr(menu))!
    gtk_widget_insert_action_group(popover, "menu", ptr(actions))
    return popover
}

/// A context menu: the secondary button opens it where it was pressed.
func contextMenu(on widget: Widget, _ items: @escaping () -> [(String, () -> Void)]) {
    let handler = PointHandler { x, y in showMenu(at: widget, x: x, y: y, items()) }
    jb_on_secondary_click(widget, { x, y, data in
        guard let data else { return }
        let handler = Unmanaged<PointHandler>.fromOpaque(data).takeUnretainedValue()
        MainActor.assumeIsolated { handler.run(x, y) }
    }, Unmanaged.passRetained(handler).toOpaque(), { data in
        guard let data else { return }
        Unmanaged<PointHandler>.fromOpaque(data).release()
    })
}

func showMenu(at widget: Widget, x: Double, y: Double, _ items: [(String, () -> Void)]) {
    guard items.contains(where: { $0.0 != menuBreak.0 }) else { return }
    let popover = popoverMenu(items)
    gtk_popover_set_has_arrow(ptr(popover), 0)
    jb_popover_point_to(popover, x, y)
    gtk_widget_set_parent(popover, widget)
    // Rightward from the click where the window has room for it, leftward
    // where it has not: a song's menu in Up Next ran past the window's
    // right edge, cut off (SYSTEM.md's audit, 23 November 2026). Not left
    // to the compositor, which may not slide it back in.
    var width: Int32 = 0
    // Its content: a popover not yet shown measures nothing.
    gtk_widget_measure(gtk_popover_get_child(ptr(popover)), GTK_ORIENTATION_HORIZONTAL, -1, nil, &width, nil, nil)
    var point = graphene_point_t(), at = graphene_point_t(x: Float(x), y: Float(y))
    let window = MainWindow.window
    let fits = gtk_widget_compute_point(widget, window, &at, &point) == 0
        || Int32(point.x) + width <= gtk_widget_get_width(window)
    gtk_widget_set_halign(popover, fits ? GTK_ALIGN_START : GTK_ALIGN_END)
    on(popover, "closed") {
        // After its closing has been drawn, and its item has run: GTK
        // warns of a popover taken away while it is still shown.
        Task { gtk_widget_unparent(popover) }
    }
    gtk_popover_popup(ptr(popover))
}

/// What can be done with songs wherever they are listed, in GNOME's
/// groups and the same order in every song's menu (and the Mac's
/// TrackMenu): what the list it is in does with it (`place`: the queue's
/// Move Up, Move Down, Remove from Queue and a station's lessons, a
/// playlist's own), the most used, first; then playing it, keeping it,
/// going to where it is from, and last what is used least.
func trackMenu(_ tracks: [Track], place: [(String, () -> Void)] = []) -> [(String, () -> Void)] {
    guard let first = tracks.first else { return [] }
    let play: [(String, () -> Void)] = [
        ("Play Next", { app.player.playNext(tracks) }),
        ("Add to Queue", { app.player.addToQueue(tracks) }),
    ]
    guard tracks.count == 1 else {
        return menuSections(place, play, [("Add to Playlist…", { Playlists.add(tracks) })])
    }
    let favorite = app.library.isFavorite(first.id)
    let keep: [(String, () -> Void)] = [
        ("Add to Playlist…", { Playlists.add(tracks) }),
        (favorite ? "Remove from Favorites" : "Add to Favorites",
         { Task { await app.library.setFavorite(!favorite, item: .track(first.id)) } }),
    ] + ratingItems(.track(first.id)) + [("Start Radio", { app.radio.start(.track(first.id)) })]
    return menuSections(place, play, keep, goItems(first), rareItems(first))
}

/// Go to Album, Go to Artist and Credits: where a song is from.
func goItems(_ track: Track) -> [(String, () -> Void)] {
    var items: [(String, () -> Void)] = []
    if let albumID = track.albumID, let album = app.library.album(id: albumID) {
        items.append(("Go to Album", { Pages.open(album) }))
    }
    if let ref = track.primaryArtist, let artist = app.library.artist(ref) {
        items.append(("Go to Artist", { Pages.open(artist) }))
    }
    return items + creditItems(track)
}

/// The song's links and Don't Count Plays: used least, so last.
func rareItems(_ track: Track) -> [(String, () -> Void)] {
    shareItems(track.id, tracks: [track.id]) + publicShareItems(.track(track))
        + NotCountedUI.items(.song, track.id, track.name)
}

// MARK: Songs

/// A song's row. Numbered (an album's page, where the cover is the page's
/// own): the number in a column of 32, 16, the title with a guest artist
/// after it, the length; 48 tall. Otherwise the cover 48, the title over the
/// artist, the length; 64 tall. The song that plays is in the accent, and
/// numbered, the bars stand for its number.
final class TrackRow {
    let widget: Widget
    private let number = label("", "t15", "fact", "times")
    private let bars = gtk_image_new_from_icon_name(Glyphs.name("playing"))!.css("playing")
    private let art = Art(48)
    private let title = label("", "t15")
    private let subtitle = label("", "t13", "fact")
    private let time = label("", "t13", "fact", "times")
    private var track: Track?
    private var menuTracks: [Track] = []
    /// The row's place in its list, as the list last filled it (a list
    /// reuses its rows).
    var position = 0
    /// What its list does with the song (Move Up, Move Down, Remove from
    /// Playlist): the menu's first section (`trackMenu`'s `place`).
    var placeItems: [(String, () -> Void)] = []
    /// Its list's picked songs (TrackPicks), where the list has them.
    private let picked: PickedRows?

    init(numbered: Bool = false, picked: PickedRows? = nil) {
        self.picked = picked
        gtk_label_set_xalign(ptr(number), 1)
        gtk_label_set_xalign(ptr(time), 1)
        time.size(width: 40)
        bars.expand(horizontal: true).align(horizontal: GTK_ALIGN_END)
        bars.isVisible = false
        if numbered {
            // Its own 32: the number's expanding stops here.
            let mark = hbox([number.expand(horizontal: true), bars]).size(width: 32)
            gtk_widget_set_hexpand(mark, 0)
            let words = hbox(spacing: 8, [title.align(vertical: GTK_ALIGN_BASELINE_FILL),
                                          subtitle.expand(horizontal: true).align(vertical: GTK_ALIGN_BASELINE_FILL)])
            widget = hbox(spacing: 16, [mark, words.expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER), time])
                .css("track-row")
        } else {
            let words = vbox(spacing: 0, [title, subtitle]).expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER)
            widget = hbox(spacing: 12, [art.widget, words, time]).css("track-row", "covered")
        }
        let widget = self.widget
        contextMenu(on: widget) { [weak self] in self?.menu() ?? [] }
        observe(widget) { [weak self] in
            let playing = app.player.currentTrack?.id
            self?.mark(playing)
        }
        if let picked {
            onRowClick(widget) { [weak self] toggle, extend in
                guard let self else { return }
                if toggle { picked.picks.click(self.position, .toggle) }
                else if extend { picked.picks.click(self.position, .extend) }
                else { picked.picks.plain(self.position) }
            }
            observe(widget) { [weak self] in
                _ = picked.picks
                self?.markPicked()
            }
        }
    }

    /// The song's own menu; on one of two or more picked, the picks' own:
    /// what the list does with them all, then Play Next, Add to Queue and
    /// Add to Playlist… (trackMenu for several).
    func menu() -> [(String, () -> Void)] {
        if let picked {
            let tracks = picked.picks.tracks(at: position, in: picked.items())
            if tracks.count > 1 { return trackMenu(tracks, place: picked.place(picked.picks)) }
        }
        return trackMenu(menuTracks, place: placeItems)
    }

    /// Picked: the list's own row (its padding included) lit as
    /// libadwaita's selected rows are.
    func markPicked() {
        guard let picked, let row = gtk_widget_get_parent(widget) else { return }
        if picked.picks.contains(position) { gtk_widget_add_css_class(row, "picked") }
        else { gtk_widget_remove_css_class(row, "picked") }
    }

    private func mark(_ playing: ItemID?) {
        let isPlaying = track != nil && playing == track?.id
        if isPlaying { gtk_widget_add_css_class(title, "playing") } else { gtk_widget_remove_css_class(title, "playing") }
        bars.isVisible = isPlaying
        number.isVisible = !isPlaying
    }

    /// `place`: the number a numbered row shows.
    /// `name` in place of the song's title: under a chosen version, the
    /// title without the marker every row would say.
    func show(_ track: Track, subtitle words: String? = nil, place: Int? = nil, name: String? = nil) {
        self.track = track
        menuTracks = [track]
        setText(number, place.map(String.init) ?? "")
        art.show(track.artwork, sleeve: TitleSleeve.Words(track: track))
        setText(title, name ?? track.name)
        setText(subtitle, words ?? track.artistLine)
        subtitle.isVisible = !(words ?? track.artistLine).isEmpty
        setText(time, clock(track.duration))
        mark(app.player.currentTrack?.id)
    }
}

/// The artists of a song that are not its album's ("MC Polder" on a Blue
/// Room Trio album): what follows the title in a numbered row. Names that
/// share one tag ("Blue Room Trio; MC Polder") count apart.
func guests(_ track: Track, besides albumArtist: String? = nil) -> String {
    let own = Set((albumArtist ?? track.albumArtist?.name ?? "").components(separatedBy: "; "))
    return track.artists.flatMap { $0.name.components(separatedBy: "; ") }.filter { !own.contains($0) }.joined(separator: ", ")
}

/// Songs as a list that plays from the song clicked, as `context`.
/// Shift+F10 or the Menu key opens the focused song's menu, as a click with
/// the secondary button does.
///
/// A playlist of the listener's own passes what edits it, by the songs'
/// places: `remove` puts Remove from Playlist in a song's menu and on the
/// Delete key, GNOME's key for removing the item with the focus, for all
/// the picked songs on one of them; `move` puts Move Up and Move Down in
/// it, for the keyboard, and lets a song be dragged onto another to take
/// its place, while `canMove` says so (not under a chosen version: a place
/// among some songs is none in the playlist); `movePicked` puts Move to
/// Top and Move to Bottom in the menu on several picked (true: the top).
/// `name` is what a row's title says, when not the song's own. `numbers`
/// numbers the rows (an album's, AlbumNumbers); `queue` is what plays from
/// a row when the list is one disc of it (the whole album).
func trackList(_ tracks: [Track], numbers: ((Track) -> Int?)? = nil, queue: (() -> [Track])? = nil,
               context: @escaping () -> QueueContext,
               subtitle: ((Track) -> String)? = nil, name: ((Track) -> String?)? = nil,
               remove: (([Int]) -> Void)? = nil, move: ((Int, Int) -> Void)? = nil,
               movePicked: ((TrackPicks, Bool) -> Void)? = nil,
               canMove: @escaping () -> Bool = { true }) -> ItemList<Track, TrackRow> {
    weak var made: ItemList<Track, TrackRow>?
    let picked = PickedRows { made?.items ?? [] }
    // In the order of one song's: Move first, then Remove.
    picked.place = { picks in
        var items: [(String, () -> Void)] = []
        if let movePicked, canMove() {
            items += [("Move to Top", { movePicked(picks, true) }), ("Move to Bottom", { movePicked(picks, false) })]
        }
        if let remove { items.append(("Remove from Playlist", { remove(picks.rows.sorted()) })) }
        return items
    }
    let list = ItemList<Track, TrackRow>(
        make: {
            let row = TrackRow(numbered: numbers != nil, picked: picked)
            if let move { reorderable(row) { if canMove() { move($0, $1) } } }
            return (row.widget, row)
        },
        fill: { row, track, index in
            row.position = index
            // An album's own numbers (AlbumNumbers), from the whole album.
            row.show(track, subtitle: subtitle?(track),
                     place: numbers?(track),
                     name: name?(track))
            row.placeItems = []
            if let move, canMove() {
                if index > 0 { row.placeItems.append(("Move Up", { move(index, index - 1) })) }
                if index < (made?.items.count ?? 0) - 1 { row.placeItems.append(("Move Down", { move(index, index + 1) })) }
            }
            if let remove { row.placeItems.append(("Remove from Playlist", { remove([index]) })) }
            row.markPicked()
        },
        activate: { _, index, items in
            // One disc's list of an album's: the whole album plays on from it.
            if let queue {
                let whole = queue()
                let at = whole.firstIndex { $0.id == items[index].id } ?? 0
                app.player.play(whole, startingAt: at, context: context())
            } else {
                app.player.play(items, startingAt: index, context: context())
            }
        })
    made = list
    list.willSet = { picked.picks.clear() }
    keep(picked, on: raw(list.widget), as: "picked")
    list.widget.css("rows")
    onFocusedRow(of: list.widget, "<Shift>F10|Menu") { row in
        showMenu(at: row.widget, x: 0, y: Double(gtk_widget_get_height(row.widget)), row.menu())
    }
    if let remove {
        onFocusedRow(of: list.widget, "Delete|KP_Delete") { row in
            let picks = picked.picks
            remove(picks.rows.count > 1 && picks.contains(row.position) ? picks.rows.sorted() : [row.position])
        }
    }
    onFocusedRow(of: list.widget, "Escape") { _ in picked.picks.clear() }
    list.set(tracks)
    return list
}

/// A list's picked songs (TrackPicks): Ctrl-click and Shift-click on a
/// desktop, for Play Next, Add to Queue and Add to Playlist… on all of them,
/// and what the list does with them all (`place`: Move to Top, Move to
/// Bottom, Remove from Playlist), first.
@Observable final class PickedRows {
    var picks = TrackPicks()
    let items: () -> [Track]
    @ObservationIgnored var place: (TrackPicks) -> [(String, () -> Void)] = { _ in [] }
    init(_ items: @escaping () -> [Track]) { self.items = items }
}

/// What a click with Ctrl or Shift, or none, does on a row (CGlue's
/// jb_on_row_click claims the first two from the list).
private nonisolated final class RowClick {
    let run: @MainActor (Bool, Bool) -> Void
    init(_ run: @escaping @MainActor (Bool, Bool) -> Void) { self.run = run }
}

func onRowClick(_ widget: Widget, _ body: @escaping (Bool, Bool) -> Void) {
    jb_on_row_click(widget, { toggle, extend, data in
        guard let data else { return }
        let click = Unmanaged<RowClick>.fromOpaque(data).takeUnretainedValue()
        MainActor.assumeIsolated { click.run(toggle != 0, extend != 0) }
    }, Unmanaged.passRetained(RowClick(body)).toOpaque(), { data in
        guard let data else { return }
        Unmanaged<RowClick>.fromOpaque(data).release()
    })
}

/// What a key runs on the row with the focus, kept by the list's widget.
private nonisolated final class RowKey {
    let run: @MainActor (TrackRow) -> Void
    init(_ run: @escaping @MainActor (TrackRow) -> Void) { self.run = run }
}

/// `keys` (a GTK trigger, "<Shift>F10|Menu") pressed in `list` run `body`
/// on the row with the focus: GTK focuses the list's own item, whose child
/// is the row.
private func onFocusedRow(of list: Widget, _ keys: String, _ body: @escaping (TrackRow) -> Void) {
    let controller = gtk_shortcut_controller_new()!
    let action = gtk_callback_action_new({ list, _, data in
        guard let list, let data, let item = gtk_widget_get_focus_child(list),
              let child = gtk_widget_get_first_child(item),
              let row: TrackRow = kept(on: raw(child)) else { return 0 }
        let key = Unmanaged<RowKey>.fromOpaque(data).takeUnretainedValue()
        MainActor.assumeIsolated { key.run(row) }
        return 1
    }, Unmanaged.passRetained(RowKey(body)).toOpaque(), { data in
        guard let data else { return }
        Unmanaged<RowKey>.fromOpaque(data).release()
    })
    gtk_shortcut_controller_add_shortcut(ptr(controller), gtk_shortcut_new(gtk_shortcut_trigger_parse_string(keys), action))
    gtk_widget_add_controller(list, ptr(controller))
}

/// A dragged row's place and the drop on another, kept by the row's widget.
private nonisolated final class RowMoves {
    let place: @MainActor () -> Int
    let moved: @MainActor (Int, Int) -> Void
    init(place: @escaping @MainActor () -> Int, moved: @escaping @MainActor (Int, Int) -> Void) {
        self.place = place
        self.moved = moved
    }
}

/// A row dragged onto another row of its list takes that row's place
/// (CGlue's jb_reorderable_row).
private func reorderable(_ row: TrackRow, _ move: @escaping (Int, Int) -> Void) {
    let moves = RowMoves(place: { [weak row] in row?.position ?? 0 },
                         moved: { from, to in if from != to { move(from, to) } })
    jb_reorderable_row(row.widget, { data in
        guard let data else { return 0 }
        let moves = Unmanaged<RowMoves>.fromOpaque(data).takeUnretainedValue()
        return MainActor.assumeIsolated { Int32(moves.place()) }
    }, { from, to, data in
        guard let data else { return }
        let moves = Unmanaged<RowMoves>.fromOpaque(data).takeUnretainedValue()
        MainActor.assumeIsolated { moves.moved(Int(from), Int(to)) }
    }, Unmanaged.passRetained(moves).toOpaque(), { data in
        guard let data else { return }
        Unmanaged<RowMoves>.fromOpaque(data).release()
    })
}

// MARK: Covers

/// A cover with its name 8 under it and a line under that, in a shelf or a
/// grid: the page's tile size (192, 176 or 160), following the page. Its
/// own size in a grid's wider cell, so the hover is the tile's, not the
/// cell's ("hover op linux gaat nog fout, op mac niet", 14 November 2026).
/// `round`: an artist's, in a circle.
final class Tile {
    let widget: Widget
    private let art: Art
    private let title = label("", "t15", "medium")
    private let subtitle = label("", "t13", "fact")

    init(round: Bool = false, emptyIcon: String? = nil) {
        let size = PageMeasure.shared.tile
        art = Art(size)
        if let emptyIcon { art.emptyIcon = emptyIcon }
        if round { art.widget.css("round") }
        widget = vbox(spacing: 0, [art.widget, title, subtitle]).size(width: size).css("grid-tile")
            .align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_START)
        gtk_label_set_max_width_chars(ptr(title), 1)
        gtk_label_set_max_width_chars(ptr(subtitle), 1)
        title.expand(horizontal: true)
        subtitle.expand(horizontal: true)
        gtk_widget_set_margin_top(title, 8)
        // Kept by its widget: a shelf's tile is not kept anywhere else.
        keep(self, on: raw(widget), as: "tile")
        observe(widget) { [weak self] in
            let size = PageMeasure.shared.tile
            guard let self else { return }
            self.art.resize(size)
            self.widget.size(width: size)
        }
    }

    /// `sleeve`: an album's words, for its title sleeve when it has no cover.
    func show(_ artwork: Artwork?, _ name: String, _ line: String, sleeve: TitleSleeve.Words? = nil) {
        art.show(artwork, sleeve: sleeve)
        setText(title, name)
        setText(subtitle, line)
        subtitle.isVisible = !line.isEmpty
    }

    /// A mix's: its four covers as a collage (CollageArtwork).
    func show(collage artworks: [Artwork], _ name: String, _ line: String) {
        show(nil, name, line)
        art.show(collage: artworks)
    }
}

func albumTile(_ album: Album, fact: String? = nil) -> Widget {
    let tile = Tile()
    tile.show(album.artwork, album.name, fact ?? album.artistLine, sleeve: TitleSleeve.Words(album: album))
    let button = tileButton(tile.widget) { Pages.open(album) }
    contextMenu(on: button) { albumMenu(album) }
    return button
}

/// What can be done with an album from its tile or row, in a song's
/// order (`trackMenu`); `play` false on its own page, which has Play,
/// and `heart` false there too, as the heart sits beside its ⋮.
func albumMenu(_ album: Album, play: Bool = true, heart: Bool = true) -> [(String, () -> Void)] {
    let tracks = app.library.tracks(inAlbum: album.id)
    let artist = album.primaryArtist.flatMap { app.library.artist($0) }
    let playItems: [(String, () -> Void)] = play
        ? [("Play", { app.player.play(tracks, context: QueueContext(.album(album.id), title: album.name)) })] : []
    // The heart where a song's menu has it: the same order on every client
    // ("Los ze op", the photographer, 20 November 2026).
    let favorite = app.library.isFavorite(album.id)
    let heartItems: [(String, () -> Void)] = heart
        ? [(favorite ? "Remove from Favorites" : "Add to Favorites",
            { Task { await app.library.setFavorite(!favorite, item: .album(album.id)) } })] : []
    return menuSections(
        playItems + [("Play Next", { app.player.playNext(tracks) }),
                     ("Add to Queue", { app.player.addToQueue(tracks) })],
        [("Add to Playlist…", { Playlists.add(tracks) })] + heartItems + ratingItems(.album(album.id))
            + [("Start Radio", { app.radio.start(.album(album.id)) })],
        artist.map { artist in [("Go to Artist", { Pages.open(artist) })] } ?? [],
        shareItems(album.id, tracks: tracks.map(\.id)) + publicShareItems(.album(album))
            + NotCountedUI.items(.album, album.id, album.name))
}

/// A station's tile: the arch at the page's tile size, its name and a fact.
/// It opens the station's page — what it would play, before it plays ("Als
/// je nu klikt op een tegel van radio begint er meteen van alles te spelen
/// ipv dat je kan zien wat je van de playlist gemaakt hebt", 8 November
/// 2026).
func stationTile(_ station: Station, fact: String) -> Widget {
    let size = PageMeasure.shared.tile
    let art = StationArt(size)
    art.show(station)
    let name = label(station.title, "t15", "medium")
    let line = label(fact, "t13", "fact")
    for words in [name, line] {
        gtk_label_set_max_width_chars(ptr(words), 1)
        words.expand(horizontal: true)
    }
    gtk_widget_set_margin_top(name, 8)
    line.isVisible = !fact.isEmpty
    let column = vbox(spacing: 0, [art.widget, name, line]).size(width: size)
    keep(art, on: raw(column), as: "art")
    let button = tileButton(column) { Pages.open(station) }
    contextMenu(on: button) { stationMenu(station) }
    return button
}

/// A station's tile's and Your Station's menu: Play Station, or on the air
/// Show Full Player, as the bar opens it; then its page. The same on every
/// client ("Los ze op", the photographer, 20 November 2026).
func stationMenu(_ station: Station) -> [(String, () -> Void)] {
    let onAir = app.radio.stationOnAir(player: app.player)?.id == station.id
    return menuSections([onAir ? ("Show Full Player", { NowPlayingPage.open() })
                               : ("Play Station", { app.radio.start(station) })],
                        [("Go to Station", { Pages.open(station) })])
}

/// A tile that can be clicked, and reached with Tab.
func tileButton(_ content: Widget, action: @escaping @MainActor () -> Void) -> Widget {
    let button = gtk_button_new()!
    gtk_button_set_child(ptr(button), content)
    button.css("tile", "flat")
    // As wide as its tile: a shelf of three does not spread them out.
    gtk_widget_set_hexpand(button, 0)
    on(button, "clicked", action)
    return button.align(vertical: GTK_ALIGN_START)
}

/// Tiles 24 apart in a row that runs on past the page's edge (tells.md 8).
/// No scrollbar: it crossed the tiles' words ("kun je hier een mooiere
/// oplossing vinden voor de scrollbar", 14 November 2026). The wheel, the
/// touchpad and a drag scroll it; under the pointer, ‹ and › at its edges,
/// each only while there is more that way, as on the Mac.
func shelf(_ tiles: [Widget]) -> Widget {
    // Room for the tiles' hover, which reaches 8 past them; the shelf's
    // CSS gives it back, so the tiles sit on the page's grid.
    let row = hbox(spacing: 24, tiles).margins(horizontal: 8, vertical: 8)
    let scroller = scrolled(row, horizontal: true)
    gtk_scrolled_window_set_policy(ptr(scroller), GTK_POLICY_EXTERNAL, GTK_POLICY_NEVER)
    // Grab and drag it sideways with the mouse (CGlue's jb_drag_to_scroll).
    jb_drag_to_scroll(scroller)
    let adjustment = gtk_scrolled_window_get_hadjustment(ptr(scroller))!
    // A click moves on by what shows less one tile, in 300 ms, easing out
    // (at once where the desktop asks for no animations), to a tile's edge
    // at the page's margin, as the Mac's shelf snaps to its tiles.
    let glide = adw_timed_animation_new(scroller, 0, 0, 300, adw_property_animation_target_new(ptr(adjustment), "value"))!
    adw_timed_animation_set_easing(ptr(glide), ADW_EASE_OUT_CUBIC)
    func arrow(_ icon: String, _ way: Double) -> Widget {
        let button = gtk_button_new_from_icon_name(icon)!.css("shelf-arrow")
        // The tiles are the keys' way along a shelf; the arrows the pointer's.
        gtk_widget_set_focusable(button, 0)
        on(button, "clicked") {
            let value = gtk_adjustment_get_value(adjustment), page = gtk_adjustment_get_page_size(adjustment)
            // Tile n sits at the margin at n steps of a tile and its 24.
            let tile = Double(PageMeasure.shared.tile), step = tile + 24
            let index = way > 0 ? max(((value + page - tile) / step).rounded(.down), (value / step).rounded(.down) + 1)
                : min(((value - page + tile) / step).rounded(.up), (value / step).rounded(.up) - 1)
            adw_timed_animation_set_value_from(ptr(glide), value)
            adw_timed_animation_set_value_to(ptr(glide), min(max(0, index * step), gtk_adjustment_get_upper(adjustment) - page))
            adw_animation_play(glide)
        }
        return button
    }
    let back = arrow("go-previous-symbolic", -1).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_START)
    let next = arrow("go-next-symbolic", 1).align(horizontal: GTK_ALIGN_END, vertical: GTK_ALIGN_START)
    // 8 in from the shelf's edges: the art's own edge at the page's margin.
    gtk_widget_set_margin_start(back, 8)
    gtk_widget_set_margin_end(next, 8)
    let shelf = gtk_overlay_new()!.css("shelf")
    gtk_overlay_set_child(ptr(shelf), scroller)
    gtk_overlay_add_overlay(ptr(shelf), back)
    gtk_overlay_add_overlay(ptr(shelf), next)
    // Shown (CSS fades it in under the pointer) and clickable only while
    // there is more that way.
    func follow() {
        let value = gtk_adjustment_get_value(adjustment)
        let end = gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment)
        for (button, more) in [(back, value > 0.5), (next, value < end - 0.5)] {
            if more { gtk_widget_add_css_class(button, "more") } else { gtk_widget_remove_css_class(button, "more") }
            gtk_widget_set_can_target(button, more ? 1 : 0)
        }
    }
    on(raw(adjustment), "value-changed") { follow() }
    on(raw(adjustment), "changed") { follow() }
    // Centred on the art (its top 8 into the shelf), not on the words.
    observe(shelf) {
        let top = 8 + (PageMeasure.shared.tile - 32) / 2
        gtk_widget_set_margin_top(back, top)
        gtk_widget_set_margin_top(next, top)
    }
    return shelf
}

/// The one filled button a screen may have, 36 tall.
func playButton(_ title: String = "Play", action: @escaping @MainActor () -> Void) -> Widget {
    button(title, "suggested-action", "page-button", action: action).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
}

/// The one beside Play, its size, on a faint ground of the accent: Shuffle,
/// New Picks, Stop, Continue (the Mac's ActionButtonStyle, quiet). The
/// photographer, 18 November 2026: "bij de artiest en op meerdere plekken
/// de buttons allemaal een beetje gek".
func quietButton(_ title: String, action: @escaping @MainActor () -> Void) -> Widget {
    button(title, "quiet", "page-button", action: action).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
}

/// The version filter over an album's or a playlist's songs: one glyph in
/// the page's actions, beside the heart and the more button (Apple's
/// LibraryVersionMenu, `line.3.horizontal.decrease.circle`), filled and in
/// the accent while a kind is off. Its popover lists each kind they hold
/// (TrackVersion: Original first), each with a check at the row's end, on
/// or off on its own, the last one on staying on; then Show All. Drawn as
/// Play On's list (PlayerBar), not a GMenu: GTK keeps a check's room before
/// every item of a menu page that has one (SYSTEM.md, Menu checks), and
/// this one stays open while kinds are turned. "kun je er misschien een
/// icon knopje van maken met uit of aan togglen?" (the photographer, 22
/// November 2026, of the row of toggle buttons it was).
func versionFilter(_ kinds: [TrackVersion], off start: Set<TrackVersion> = [],
                   changed: @escaping @MainActor (Set<TrackVersion>) -> Void) -> Widget {
    var off = start
    let rows = gtk_list_box_new()!
    gtk_list_box_set_selection_mode(ptr(rows), GTK_SELECTION_NONE)
    // grid-ok: libadwaita's menu measures (6 around, rows 12 in), as Play On's.
    let heading = label("Versions", "heading").align(horizontal: GTK_ALIGN_START).margins(horizontal: 12, vertical: 6)
    // Show All in a list of its own under a line, as a menu's next section.
    let all = gtk_list_box_new()!
    gtk_list_box_set_selection_mode(ptr(all), GTK_SELECTION_NONE)
    // grid-ok: a menu section's line, 6 above and below, as libadwaita's.
    let line = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL)!.margins(vertical: 6)
    let popover = gtk_popover_new()!.css("menu")
    // grid-ok: the menu's own 6 around.
    gtk_popover_set_child(ptr(popover), vbox([heading, rows, line, all]).margins(6))
    // A square of Shuffle's kind after it, as the iPhone's: quiet while all
    // show, filled while a kind is off ("behalve dat hier het filterknopje
    // nog niet klopt met ios", the photographer, 24 November 2026).
    let button = gtk_menu_button_new()!.css("square").named("Versions")
    gtk_menu_button_set_popover(ptr(button), popover)
    var checks: [Widget] = []
    for kind in kinds {
        let check = gtk_image_new_from_icon_name("object-select-symbolic")!
        checks.append(check)
        let row = gtk_list_box_row_new()!
        gtk_list_box_row_set_child(ptr(row), hbox(spacing: 12, [
            label(kind.name).align(horizontal: GTK_ALIGN_START).expand(horizontal: true), check,
        ]))
        gtk_list_box_append(ptr(rows), row)
    }
    let showAll = gtk_list_box_row_new()!
    gtk_list_box_row_set_child(ptr(showAll), label("Show All").align(horizontal: GTK_ALIGN_START))
    gtk_list_box_append(ptr(all), showAll)
    func show() {
        for (kind, check) in zip(kinds, checks) { gtk_widget_set_opacity(check, off.contains(kind) ? 0 : 1) }
        gtk_widget_set_sensitive(showAll, off.isEmpty ? 0 : 1)
        gtk_menu_button_set_icon_name(ptr(button), Glyphs.name("filter-lines"))
        if off.isEmpty { gtk_widget_remove_css_class(button, "on") } else { gtk_widget_add_css_class(button, "on") }
    }
    on(raw(rows), "row-activated", argument: { row in
        guard let row else { return }
        let index = Int(gtk_list_box_row_get_index(ptr(row)))
        guard kinds.indices.contains(index) else { return }
        off = TrackVersion.toggle(kinds[index], in: off, of: kinds)
        show()
        changed(off)
    })
    on(raw(all), "row-activated", argument: { _ in
        off = []
        show()
        changed(off)
    })
    show()
    return button.align(vertical: GTK_ALIGN_CENTER)
}

/// Every other action: a word in the accent.
func wordButton(_ title: String, action: @escaping @MainActor () -> Void) -> Widget {
    button(title, "flat", "accent", "word", action: action).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
}

/// ⋮: the rest of what can be done with what the page shows. `square`: in
/// a page's head, one of its quiet squares after Play and Shuffle (Style's
/// `square`), not a glyph alone: "ik wil niet zo'n icoontje alleen zo
/// dunnig" (the photographer, 24 November 2026).
func moreButton(_ items: [(String, () -> Void)], square: Bool = false) -> Widget {
    let more = gtk_menu_button_new()!.css(square ? "square" : "flat").named("More")
    gtk_menu_button_set_icon_name(ptr(more), "view-more-symbolic")
    gtk_menu_button_set_popover(ptr(more), popoverMenu(items))
    return more.align(vertical: GTK_ALIGN_CENTER)
}

/// The heart: given, it is filled and in the accent. `square`: a page
/// head's quiet square, as the ⋮'s.
func heartButton(square: Bool = false, _ item: @escaping () -> ItemRef?) -> Widget {
    let heart = iconButton(Glyphs.name("heart-outline"), "Add to Favorites", square ? "square" : "flat") {
        guard let item = item() else { return }
        Task { await app.library.toggleFavorite(item) }
    }
    observe(heart) {
        let given = item().map { app.library.isFavorite($0.id) } ?? false
        setIcon(heart, Glyphs.name(given ? "heart" : "heart-outline"))
        if given { gtk_widget_add_css_class(heart, "given") } else { gtk_widget_remove_css_class(heart, "given") }
        heart.named(given ? "Remove from Favorites" : "Add to Favorites")
    }
    return heart.align(vertical: GTK_ALIGN_CENTER)
}
