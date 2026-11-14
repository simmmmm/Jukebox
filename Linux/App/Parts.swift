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
    /// scrolled under it (spec §5).
    static func page(_ title: String, _ content: Widget, start: [Widget] = [], end: [Widget] = []) -> NavPage {
        let toolbar = adw_toolbar_view_new()!
        let header = adw_header_bar_new()!
        for widget in start { adw_header_bar_pack_start(ptr(header), widget) }
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
        return adw_navigation_page_new(toolbar, title)!
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

    func set(margin: Int32, tile: Int32, columns: Int) {
        if margin != self.margin { self.margin = margin }
        if tile != self.tile { self.tile = tile }
        if columns != self.columns { self.columns = columns }
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

/// What a page says when it has nothing to show (libadwaita's status page).
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

/// A menu of `items` as a popover; `prefix` names its actions apart from
/// another menu's on the same widget.
func popoverMenu(_ items: [(String, () -> Void)]) -> Widget {
    let menu = g_menu_new()!
    let actions = g_simple_action_group_new()!
    for (index, (title, action)) in items.enumerated() {
        let simple = g_simple_action_new("item\(index)", nil)!
        on(raw(simple), "activate") { action() }
        g_action_map_add_action(ptr(actions), ptr(simple))
        g_menu_append(menu, title, "menu.item\(index)")
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
    ]
    if tracks.count == 1 {
        items.append(("Start Radio", { app.radio.start(.track(first.id)) }))
        let favorite = app.library.isFavorite(first.id)
        items.append((favorite ? "Remove from Favorites" : "Add to Favorites",
                      { Task { await app.library.setFavorite(!favorite, item: .track(first.id)) } }))
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
    /// What a list adds before the song's own menu.
    var extraItems: [(String, () -> Void)] = []

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
        contextMenu(on: widget) { [weak self] in (self?.extraItems ?? []) + trackMenu(self?.menuTracks ?? []) }
        observe(widget) { [weak self] in
            let playing = app.player.currentTrack?.id
            self?.mark(playing)
        }
    }

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
func trackList(_ tracks: [Track], numbered: Bool = false, context: @escaping () -> QueueContext,
               subtitle: ((Track) -> String)? = nil) -> ItemList<Track, TrackRow> {
    let list = ItemList<Track, TrackRow>(
        make: {
            let row = TrackRow(numbered: numbered)
            return (row.widget, row)
        },
        fill: { row, track, _ in row.show(track, subtitle: subtitle?(track)) },
        activate: { _, index, items in
            app.player.play(items, startingAt: index, context: context())
        })
    list.widget.css("rows")
    list.set(tracks)
    return list
}

// MARK: Covers

/// A cover with its name 8 under it and a line under that, in a shelf or a
/// grid: the page's tile size (192, 176 or 160), following the page.
final class Tile {
    let widget: Widget
    private let art: Art
    private let title = label("", "t15", "medium")
    private let subtitle = label("", "t13", "fact")

    init() {
        let size = PageMeasure.shared.tile
        art = Art(size)
        widget = vbox(spacing: 0, [art.widget, title, subtitle]).size(width: size).css("grid-tile")
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
            ("Start a Station", { app.radio.start(.album(album.id)) })]
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
func shelf(_ tiles: [Widget]) -> Widget {
    // Room for the tiles' hover, which reaches 8 past them; the shelf's
    // CSS gives it back, so the tiles sit on the page's grid.
    let row = hbox(spacing: 24, tiles).margins(horizontal: 8, vertical: 8)
    let scroller = scrolled(row, horizontal: true).css("shelf")
    gtk_scrolled_window_set_overlay_scrolling(ptr(scroller), 1)
    // Grab and drag it sideways with the mouse (CGlue's jb_drag_to_scroll).
    jb_drag_to_scroll(scroller)
    return scroller
}

/// The one filled button a screen may have, 40 tall.
func playButton(_ title: String = "Play", action: @escaping @MainActor () -> Void) -> Widget {
    button(title, "suggested-action", "page-button", action: action).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
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
