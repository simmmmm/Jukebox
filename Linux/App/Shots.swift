// The screenshot walk, Linux's own (the iPhone's is JukeboxUITests): with
// JUKEBOX_SHOTS=<folder> the app walks its main screens by itself, saves a
// picture of each at the window's true size, and quits. dev/linux-screens.sh
// runs it without a desktop (Xvfb) against the demo library.
//
// It is here because of a player's bar nobody had seen at its real width:
// "ook klopt er geen fuck van deze verhoudingen" (the photographer, 14
// November 2026). A screen is judged from its picture, not from its code.

import CAdw
import Foundation
import JukeboxKit

enum Shots {
    static var folder: String? { ProcessInfo.processInfo.environment["JUKEBOX_SHOTS"] }

    /// "1440x900" in JUKEBOX_WINDOW: the window's size for the walk.
    static var windowSize: (Int32, Int32)? {
        guard let text = ProcessInfo.processInfo.environment["JUKEBOX_WINDOW"] else { return nil }
        let parts = text.split(separator: "x").compactMap { Int32($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    static func walk() {
        guard let folder else { return }
        // The walk opens and closes the panel: the listener's choice stays
        // the listener's. Before the first step, which closes it.
        app.panel.remembers = false
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        Task {
            // The panel as a listener first finds it: closed.
            app.panel.isOpen = false
            // The library, the mixes and the first covers.
            for _ in 0..<80 where app.library.tracks.isEmpty || app.mixes.mixes.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            await step("01-home", wait: 3)
            // The pointer over Mixes: its first tile lit, › at its right
            // edge; then moved on once, ‹ at its left too.
            if let mixes = find(visiblePage(), { gtk_widget_has_css_class($0, "shelf") != 0 }) {
                let tile = find(mixes, { gtk_widget_has_css_class($0, "tile") != 0 })
                await hovering([mixes, tile], "01b-home-shelf-hover")
                if let next = find(mixes, { gtk_widget_has_css_class($0, "shelf-arrow") != 0 && gtk_widget_get_halign($0) == GTK_ALIGN_END }) {
                    gtk_widget_activate(next)
                    try? await Task.sleep(for: .seconds(0.5))
                    await hovering([mixes], "01c-home-shelf-moved")
                }
            }
            MainWindow.select(1)
            await step("02-radio", wait: 2)
            Pages.open(app.radio.station(for: .personal))
            await step("03-station", wait: 2)
            MainWindow.select(3)
            await step("04-albums", wait: 3)
            await hovering([gridCell()], "04b-albums-hover")
            let albums = app.library.albums(sortedBy: .artist)
            if let album = albums.first {
                Pages.open(album)
                await step("05-album", wait: 2)
            }
            if let artist = app.library.artistsByName.first {
                MainWindow.select(4)
                try? await Task.sleep(for: .seconds(2))
                await hovering([gridCell()], "06a-artists-hover")
                Pages.open(artist)
                await step("06-artist", wait: 2)
            }
            MainWindow.select(5)
            await step("07-songs", wait: 2)
            MainWindow.select(6)
            await step("08-playlists", wait: 2)
            await hovering([find(visiblePage(), { gtk_widget_has_css_class($0, "tile") != 0 })], "08a-playlists-hover")
            // Search, through the header's fields themselves: Ctrl+F with
            // nothing searched yet; typed in Playlists' field, which goes to
            // the Search page; Enter twice; emptied, the searches kept; a
            // kept one chosen.
            SearchField.shared.clearRecents()
            gtk_widget_activate_action_variant(MainWindow.window, "app.search", nil)
            await step("08b-search-empty", wait: 2)
            MainWindow.select(6)
            try? await Task.sleep(for: .seconds(1))
            if let page = adw_navigation_view_get_visible_page(ptr(Nav.view)), let field = Nav.searchField(of: page) {
                gtk_editable_set_text(ptr(field), "blue")
            }
            await step("08c-search-query", wait: 2)
            if let home = SearchField.shared.home {
                enter(home)
                gtk_editable_set_text(ptr(home), "night")
                enter(home)
                gtk_editable_set_text(ptr(home), "")
                await step("08d-search-recents", wait: 2)
                if let kept = find(visiblePage(), { gtk_widget_has_css_class($0, "recent") != 0 }) {
                    gtk_widget_activate(kept)
                    await step("08e-search-again", wait: 2)
                }
                gtk_editable_set_text(ptr(home), "")
            }
            // Music, as the designer's drawings have it (2027/notes.md):
            // Dust Windows on Home, then the panel on Up next over another
            // album's page.
            if let album = albums.first(where: { $0.name == "Dust Windows" }) ?? albums.dropFirst(3).first {
                let tracks = app.library.tracks(inAlbum: album.id)
                app.player.play(tracks, startingAt: 1, context: QueueContext(.album(album.id), title: album.name))
                MainWindow.select(0)
                await step("09-home-playing", wait: 4)
                // Narrow, the places folded away come over the page.
                if MainWindow.showPlaces() {
                    await step("09-places-over", wait: 1)
                    MainWindow.select(0)
                }
                // Two songs queued from elsewhere, as the drawing's "Then".
                let queued = ["Velvet Sky", "Night Drive"].compactMap { name in app.library.tracks.first { $0.name == name } }
                app.player.addToQueue(queued)
                app.panel.toggle(.upNext)
                // Albums made before the panel opened: its tiles follow the
                // narrower page (160 at a margin of 32 at 1440).
                MainWindow.select(3)
                await step("10a-albums-panel", wait: 2)
                Pages.open(albums.first { $0.name == "Quiet Rooms" } ?? album)
                await step("10-album-up-next", wait: 2)
                // Now Playing as the designer drew it: Up next beside it;
                // first as it opens, the first time, from the bar's song.
                await frames("10b-opening") { NowPlayingPage.open() }
                await step("10b-now-playing", wait: 3)
                gtk_widget_activate(NowPlayingPage.more)
                await step("10c-now-playing-menu", wait: 1)
            }
            // The panel on the lyrics: Night Drive's are timed, and a few
            // lines in. dev/demo/lyrics.json's times are ticks (100 ns), so
            // its lines come 0.9 s apart: the fourth starts at 2.7 s.
            if let song = app.library.tracks.first(where: { $0.name == "Night Drive" }),
               let albumID = song.albumID, let album = app.library.album(id: albumID) {
                let tracks = app.library.tracks(inAlbum: albumID)
                app.player.play(tracks, startingAt: tracks.firstIndex { $0.id == song.id } ?? 0,
                                context: QueueContext(.album(albumID), title: album.name))
                app.panel.toggle(.lyrics)
                MainWindow.select(3)
                Pages.open(album)
                try? await Task.sleep(for: .seconds(2))
                app.player.seek(to: 1.5)
                await step("11-album-lyrics", wait: 1.5)
                NowPlayingPage.open()
                await step("12-now-playing-lyrics", wait: 3)
                await frames("12b-closing") { NowPlayingPage.close() }
            }
            // Your Station on the air; then the panel with the radio's reasons.
            app.panel.isOpen = false
            app.radio.start(.personal)
            MainWindow.select(1)
            await step("13-radio-on-air", wait: 4)
            app.panel.toggle(.upNext)
            await step("14-radio-up-next", wait: 2)
            NowPlayingPage.open()
            await step("15-now-playing-station", wait: 3)
            Preferences.present()
            await step("16-preferences", wait: 2)
            if let dialog = adw_application_window_get_visible_dialog(ptr(MainWindow.window)) {
                adw_dialog_force_close(dialog)
            }
            MainWindow.showSignIn()
            await step("17-sign-in", wait: 2)
            gtk_window_close(ptr(MainWindow.window))
            exit(0)
        }
    }

    /// The pointer over `widgets`, as a picture: Xvfb has no pointer, so
    /// they are told they are under it, then told again they are not.
    private static func hovering(_ widgets: [Widget?], _ name: String) async {
        let lit = widgets.compactMap { $0 }
        for widget in lit { gtk_widget_set_state_flags(widget, GTK_STATE_FLAG_PRELIGHT, 0) }
        await step(name, wait: 0.5)
        for widget in lit { gtk_widget_unset_state_flags(widget, GTK_STATE_FLAG_PRELIGHT) }
    }

    /// Enter in a search field: its "activate", as the key sends it.
    private static func enter(_ field: Widget) {
        var instance = GValue()
        g_value_init(&instance, gtk_search_entry_get_type())
        g_value_set_object(&instance, raw(field))
        g_signal_emitv(&instance, g_signal_lookup("activate", gtk_search_entry_get_type()), 0, nil)
        g_value_unset(&instance)
    }

    private static func visiblePage() -> Widget? {
        adw_navigation_view_get_visible_page(ptr(Nav.view)).map { ptr($0) }
    }

    /// The first widget under `root`, in the order drawn, that `test` picks.
    private static func find(_ root: Widget?, _ test: (Widget) -> Bool) -> Widget? {
        guard let root else { return nil }
        if test(root) { return root }
        var child = gtk_widget_get_first_child(root)
        while let widget = child {
            if let found = find(widget, test) { return found }
            child = gtk_widget_get_next_sibling(widget)
        }
        return nil
    }

    /// A grid's second cell (the first has the page's edge beside it).
    private static func gridCell() -> Widget? {
        guard let grid = find(visiblePage(), { String(cString: gtk_widget_get_css_name($0)) == "gridview" }),
              let first = gtk_widget_get_first_child(grid) else { return nil }
        return gtk_widget_get_next_sibling(first) ?? first
    }

    private static func step(_ name: String, wait seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        guard let folder, let node = picture(MainWindow.window) else { return }
        write(node, to: "\(folder)/\(name).png")
    }

    /// A change in motion (Now Playing opening, closing) as pictures: the
    /// window as the click finds it, then 60, 120 and 200 ms after it,
    /// with when each was taken and whether the sleeve was drawn in
    /// frames.txt. A transition is judged from its frames ("de transitie op
    /// linux iig is niet heel nice nu", 14 November 2026).
    private static func frames(_ name: String, _ change: () -> Void) async {
        guard let folder, let before = picture(MainWindow.window) else { return }
        var taken = [(0, before)]
        var log = ""
        let clock = ContinuousClock(), start = clock.now
        change()
        for planned in [60, 120, 200] {
            try? await Task.sleep(until: start + .milliseconds(planned), clock: clock)
            let at = (clock.now - start).components
            guard let node = picture(MainWindow.window) else { continue }
            taken.append((planned, node))
            log += "\(name) \(planned) ms: taken at \(at.seconds * 1000 + at.attoseconds / 1_000_000_000_000_000) ms, "
                + "sleeve drawn: \(NowPlayingPage.isSleeveDrawn)\n"
        }
        // Written after the last, so writing holds none of them up.
        for (planned, node) in taken {
            write(node, to: "\(folder)/\(name)-\(String(format: "%03d", planned))ms.png")
        }
        let file = "\(folder)/frames.txt"
        try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + log).write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// The window as it is drawn now: its render node, quick to take.
    private static func picture(_ window: Widget) -> OpaquePointer? {
        let width = gtk_widget_get_width(window), height = gtk_widget_get_height(window)
        guard width > 0, height > 0, let paintable = gtk_widget_paintable_new(window),
              let snapshot = gtk_snapshot_new() else { return nil }
        // At the screen's own scale (GDK_SCALE=2 under Xvfb): the drawings
        // are made for it, and a 1x picture of them would hide that.
        let scale = Screen.shared.scale
        gtk_snapshot_scale(snapshot, Float(scale), Float(scale))
        gdk_paintable_snapshot(paintable, ptr(snapshot), Double(width), Double(height))
        g_object_unref(raw(paintable))
        return gtk_snapshot_free_to_node(snapshot)
    }

    /// A picture to a PNG, rendered as the window's own are.
    private static func write(_ node: OpaquePointer, to path: String) {
        defer { gsk_render_node_unref(node) }
        guard let native = gtk_widget_get_native(MainWindow.window), let renderer = gtk_native_get_renderer(native),
              let texture = gsk_renderer_render_texture(renderer, node, nil) else { return }
        gdk_texture_save_to_png(texture, path)
        g_object_unref(raw(texture))
    }
}
