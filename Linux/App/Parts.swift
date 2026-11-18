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
    /// Home's two cards side by side (DesktopMeasures.Page.pairsHomeCards).
    private(set) var pairsHomeCards = true
    /// An album's cover: 160 under 720.
    var cover: Int32 { margin == 24 ? 160 : 224 }

    func set(_ page: DesktopMeasures.Page) {
        if Int32(page.margin) != margin { margin = Int32(page.margin) }
        if Int32(page.tile) != tile { tile = Int32(page.tile) }
        if page.columns != columns { columns = page.columns }
        if page.pairsHomeCards != pairsHomeCards { pairsHomeCards = page.pairsHomeCards }
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
                gtk_widget_set_margin_end(widget, gtk_widget_has_css_class(widget, "shelf") != 0 ? 0 : margin)
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
    adw_status_page_set_description(ptr(page), description)
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
/// as every caller builds them.
func submenuChoice(_ submenu: String, _ title: String, checked: Bool) -> String {
    [submenu, title, checked ? "checked" : ""].joined(separator: String(submenuMark))
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

/// A menu of `items` as a popover; `prefix` names its actions apart from
/// another menu's on the same widget.
func popoverMenu(_ items: [(String, () -> Void)]) -> Widget {
    let menu = g_menu_new()!
    let actions = g_simple_action_group_new()!
    var submenus: [String: OpaquePointer] = [:]
    for (index, (title, action)) in items.enumerated() {
        // A choice (`submenuChoice`) goes under its submenu, made where
        // its first choice is, with a check mark: an action with a state.
        let parts = title.split(separator: submenuMark, omittingEmptySubsequences: false).map(String.init)
        let isChoice = parts.count == 3
        let simple = isChoice
            ? g_simple_action_new_stateful("item\(index)", nil, g_variant_new_boolean(parts[2].isEmpty ? 0 : 1))!
            : g_simple_action_new("item\(index)", nil)!
        on(raw(simple), "activate") { action() }
        g_action_map_add_action(ptr(actions), ptr(simple))
        guard isChoice else {
            g_menu_append(menu, title, "menu.item\(index)")
            continue
        }
        let submenu = submenus[parts[0]] ?? {
            let made = g_menu_new()!
            g_menu_append_submenu(menu, parts[0], ptr(made))
            submenus[parts[0]] = made
            return made
        }()
        g_menu_append(submenu, parts[1], "menu.item\(index)")
    }
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
    guard !items.isEmpty else { return }
    let popover = popoverMenu(items)
    gtk_popover_set_has_arrow(ptr(popover), 0)
    gtk_widget_set_halign(popover, GTK_ALIGN_START)
    jb_popover_point_to(popover, x, y)
    gtk_widget_set_parent(popover, widget)
    on(popover, "closed") {
        // After its closing has been drawn, and its item has run: GTK
        // warns of a popover taken away while it is still shown.
        Task { gtk_widget_unparent(popover) }
    }
    gtk_popover_popup(ptr(popover))
}

/// What can be done with songs wherever they are listed.
func trackMenu(_ tracks: [Track]) -> [(String, () -> Void)] {
    guard let first = tracks.first else { return [] }
    var items: [(String, () -> Void)] = [
        ("Play Next", { app.player.playNext(tracks) }),
        ("Add to Queue", { app.player.addToQueue(tracks) }),
        ("Add to Playlist…", { Playlists.add(tracks) }),
    ]
    if tracks.count == 1 {
        items.append(("Start Radio", { app.radio.start(.track(first.id)) }))
        let favorite = app.library.isFavorite(first.id)
        items.append((favorite ? "Remove from Favorites" : "Add to Favorites",
                      { Task { await app.library.setFavorite(!favorite, item: .track(first.id)) } }))
        items += ratingItems(.track(first.id))
        if let albumID = first.albumID, let album = app.library.album(id: albumID) {
            items.append(("Go to Album", { Pages.open(album) }))
        }
        if let ref = first.primaryArtist, let artist = app.library.artist(ref) {
            items.append(("Go to Artist", { Pages.open(artist) }))
        }
    }
    return items
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
    /// What a list adds to the song's own menu: before it (Move Up, Move
    /// Down), and after it (Remove from Playlist, last, as on the Mac).
    var firstItems: [(String, () -> Void)] = []
    var lastItems: [(String, () -> Void)] = []

    init(numbered: Bool = false) {
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
    }

    func menu() -> [(String, () -> Void)] { firstItems + trackMenu(menuTracks) + lastItems }

    private func mark(_ playing: ItemID?) {
        let isPlaying = track != nil && playing == track?.id
        if isPlaying { gtk_widget_add_css_class(title, "playing") } else { gtk_widget_remove_css_class(title, "playing") }
        bars.isVisible = isPlaying
        number.isVisible = !isPlaying
    }

    func show(_ track: Track, subtitle words: String? = nil) {
        self.track = track
        menuTracks = [track]
        setText(number, track.trackNumber.map(String.init) ?? "")
        art.show(track.artwork)
        setText(title, track.name)
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
/// A playlist of the listener's own passes what edits it, by the song's
/// place: `remove` puts Remove from Playlist in a song's menu and on the
/// Delete key, GNOME's key for removing the item with the focus; `move`
/// puts Move Up and Move Down in it, for the keyboard, and lets a song be
/// dragged onto another to take its place.
func trackList(_ tracks: [Track], numbered: Bool = false, context: @escaping () -> QueueContext,
               subtitle: ((Track) -> String)? = nil,
               remove: ((Int) -> Void)? = nil, move: ((Int, Int) -> Void)? = nil) -> ItemList<Track, TrackRow> {
    weak var made: ItemList<Track, TrackRow>?
    let list = ItemList<Track, TrackRow>(
        make: {
            let row = TrackRow(numbered: numbered)
            if let move { reorderable(row, move) }
            return (row.widget, row)
        },
        fill: { row, track, index in
            row.position = index
            row.show(track, subtitle: subtitle?(track))
            row.firstItems = []
            if let move {
                if index > 0 { row.firstItems.append(("Move Up", { move(index, index - 1) })) }
                if index < (made?.items.count ?? 0) - 1 { row.firstItems.append(("Move Down", { move(index, index + 1) })) }
            }
            row.lastItems = remove.map { remove in [("Remove from Playlist", { remove(index) })] } ?? []
        },
        activate: { _, index, items in
            app.player.play(items, startingAt: index, context: context())
        })
    made = list
    list.widget.css("rows")
    onFocusedRow(of: list.widget, "<Shift>F10|Menu") { row in
        showMenu(at: row.widget, x: 0, y: Double(gtk_widget_get_height(row.widget)), row.menu())
    }
    if let remove { onFocusedRow(of: list.widget, "Delete|KP_Delete") { remove($0.position) } }
    list.set(tracks)
    return list
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

    func show(_ artwork: Artwork?, _ name: String, _ line: String) {
        art.show(artwork)
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
    tile.show(album.artwork, album.name, fact ?? album.artistLine)
    let button = tileButton(tile.widget) { Pages.open(album) }
    contextMenu(on: button) { albumMenu(album) }
    return button
}

/// What can be done with an album from its tile or row.
func albumMenu(_ album: Album) -> [(String, () -> Void)] {
    let tracks = app.library.tracks(inAlbum: album.id)
    return [("Play", { app.player.play(tracks, context: QueueContext(.album(album.id), title: album.name)) }),
            ("Play Next", { app.player.playNext(tracks) }),
            ("Add to Queue", { app.player.addToQueue(tracks) }),
            ("Add to Playlist…", { Playlists.add(tracks) }),
            ("Start a Station", { app.radio.start(.album(album.id)) })]
        + ratingItems(.album(album.id))
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
    contextMenu(on: button) { [("Play Station", { app.radio.start(station) })] }
    return button
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

/// Every other action: a word in the accent.
func wordButton(_ title: String, action: @escaping @MainActor () -> Void) -> Widget {
    button(title, "flat", "accent", "word", action: action).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
}

/// ⋮: the rest of what can be done with what the page shows.
func moreButton(_ items: [(String, () -> Void)]) -> Widget {
    let more = gtk_menu_button_new()!.css("flat").tooltip("More")
    gtk_menu_button_set_icon_name(ptr(more), "view-more-symbolic")
    gtk_menu_button_set_popover(ptr(more), popoverMenu(items))
    return more.align(vertical: GTK_ALIGN_CENTER)
}

/// The heart: given, it is filled and in the accent.
func heartButton(_ item: @escaping () -> ItemRef?) -> Widget {
    let heart = iconButton(Glyphs.name("heart-outline"), "Add to Favorites", "flat") {
        guard let item = item() else { return }
        Task { await app.library.toggleFavorite(item) }
    }
    observe(heart) {
        let given = item().map { app.library.isFavorite($0.id) } ?? false
        setIcon(heart, Glyphs.name(given ? "heart" : "heart-outline"))
        if given { gtk_widget_add_css_class(heart, "given") } else { gtk_widget_remove_css_class(heart, "given") }
        heart.tooltip(given ? "Remove from Favorites" : "Add to Favorites")
    }
    return heart.align(vertical: GTK_ALIGN_CENTER)
}
