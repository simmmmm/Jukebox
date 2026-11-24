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
            // Better Radio, the step after signing in, then Turn On: the
            // walk's radio is the one most will have.
            if adw_application_window_get_visible_dialog(ptr(MainWindow.window)) != nil, !app.settings.radioChoiceMade {
                await step("00-better-radio", wait: 1)
                // Turn On, as a tap on it: the answer closes the dialog.
                BetterRadio.answer(true)
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
            // The version filter: the demo's album of remastered and
            // unplugged songs without track numbers, as the photographer's
            // Oasis album; all of them, the filter's popover open (alone, a
            // popover being its own surface), then Remastered turned off.
            if let versions = albums.first(where: { $0.name.hasPrefix("Lantern Hours") }) {
                Pages.open(versions)
                await step("05c-album-versions", wait: 2)
                if let filter = find(visiblePage(), { isA($0, gtk_menu_button_get_type()) && tooltip(of: $0) == "Versions" }),
                   let popover = gtk_menu_button_get_popover(ptr(filter)) {
                    gtk_menu_button_popup(ptr(filter))
                    try? await Task.sleep(for: .seconds(1))
                    let shown: Widget = ptr(popover)
                    if let node = picture(shown) { write(node, to: "\(folder)/05d-album-versions-menu.png", of: shown) }
                    // Remastered, the first kind: off.
                    if let list = find(shown, { isA($0, gtk_list_box_get_type()) }),
                       let row = gtk_list_box_get_row_at_index(ptr(list), 0) {
                        gtk_widget_activate(UnsafeMutableRawPointer(row).assumingMemoryBound(to: GtkWidget.self))
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                    if let node = picture(shown) { write(node, to: "\(folder)/05e-album-versions-menu-off.png", of: shown) }
                    gtk_menu_button_popdown(ptr(filter))
                    await step("05f-album-unplugged", wait: 1)
                }
            }
            if let artist = app.library.artistsByName.first {
                MainWindow.select(4)
                try? await Task.sleep(for: .seconds(2))
                await hovering([gridCell()], "06a-artists-hover")
                Pages.open(artist)
                await step("06-artist", wait: 2)
                // Under the fold: Similar artists and About, as the Mac's.
                await scrolled(visiblePage(), to: 1, "06b-artist-end")
            }
            MainWindow.select(5)
            await step("07-songs", wait: 2)
            await picking()
            MainWindow.select(6)
            await step("08-playlists", wait: 2)
            await hovering([find(visiblePage(), { gtk_widget_has_css_class($0, "tile") != 0 })], "08a-playlists-hover")
            await playlistPicked()
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
            await library(albums)
            // Music, as the designer's drawings have it (2027/notes.md):
            // Dust Windows on Home, then the panel on Up next over another
            // album's page.
            if let album = albums.first(where: { $0.name == "Dust Windows" }) ?? albums.dropFirst(3).first {
                let tracks = app.library.tracks(inAlbum: album.id)
                app.player.play(tracks, startingAt: 1, context: QueueContext(.album(album.id), title: album.name))
                MainWindow.select(0)
                await step("09-home-playing", wait: 4)
                await miniPlayer()
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
            // "Lossless" under the title (PlayQueue.playsLossless): the
            // demo's songs are all m4a, so one plays as if it were a FLAC.
            // Streamed: one kept on the machine plays as it was saved (the
            // automatic keep holds the songs played so far, not at Original).
            if var song = app.library.tracks.first(where: { app.offline.localURL(for: $0.id) == nil }) {
                song.container = "flac"
                app.panel.isOpen = false
                app.player.play([song], context: QueueContext(.songs, title: "Songs"))
                NowPlayingPage.open()
                await step("12c-now-playing-lossless", wait: 3)
                NowPlayingPage.close()
            }
            // Your Station on the air; then the panel with the radio's reasons.
            app.panel.isOpen = false
            app.radio.start(.personal)
            MainWindow.select(1)
            await step("13-radio-on-air", wait: 4)
            app.panel.toggle(.upNext)
            await step("14-radio-up-next", wait: 2)
            await queueMenu()
            NowPlayingPage.open()
            await step("15-now-playing-station", wait: 3)
            await parity(albums)
            await primaryMenu()
            Preferences.present()
            await step("16-preferences", wait: 2)
            if let dialog = adw_application_window_get_visible_dialog(ptr(MainWindow.window)) {
                // Preferences is in pages: each picture its page, under the
                // names the pictures had when it was one long one.
                await shown(dialog, .playback, "16a-preferences-playback")
                await shown(dialog, .radio, "16d-preferences-radio")
                await shown(dialog, .library, "16c-preferences-pages")
                await shown(dialog, .downloads, "16b-preferences-downloads")
                await shown(dialog, .privacy, "16e-preferences-privacy")
                adw_dialog_force_close(dialog)
            }
            // About Jukebox, with Help & Feedback's rows (Help.swift).
            About.present()
            await step("16f-about", wait: 1.5)
            if let dialog = adw_application_window_get_visible_dialog(ptr(MainWindow.window)) {
                adw_dialog_force_close(dialog)
            }
            await notCounted(albums)
            await pages()
            await stationClicks()
            MainWindow.showSignIn()
            // The welcome's build-up (SignInPage.markTile): the outer band
            // being drawn, the core on before the draw back, the record
            // sliding out; then at rest.
            await step("17a-welcome-0.6s", wait: 0.6)
            await step("17a-welcome-2.3s", wait: 1.7)
            await step("17a-welcome-3.6s", wait: 1.3)
            await step("17-sign-in", wait: 1.4)
            // Quick Connect shows once the address is left, only where the
            // server says it is on: the fake Jellyfin's is off, so the walk
            // can be pointed at one with it on (the test Jellyfin).
            let quickServer = ProcessInfo.processInfo.environment["JUKEBOX_SHOTS_QUICK_CONNECT"]
            gtk_editable_set_text(ptr(SignInPage.address), quickServer ?? app.credentials?.serverURL.absoluteString ?? "")
            gtk_widget_grab_focus(SignInPage.address)
            try? await Task.sleep(for: .milliseconds(300))
            gtk_widget_grab_focus(SignInPage.user)
            await step("17b-sign-in-address-left", wait: 3)
            if SignInPage.quickConnect.isVisible {
                _ = gtk_widget_activate(SignInPage.quickConnect)
                await step("17c-quick-connect-code", wait: 3)
            }
            // "This Server Isn't Secure", as a sign-in over plain http away
            // from home asks it; the walk ends under it.
            Task { _ = await SignInPage.askInsecure() }
            await step("17d-sign-in-not-secure", wait: 2)
            gtk_window_close(ptr(MainWindow.window))
            exit(0)
        }
    }

    /// The Mac's three more places ("Linux erbij", 15 November 2026):
    /// Genres, a genre, Recently Added; then an album, a playlist and a mix
    /// downloaded from the fake Jellyfin by their pages' own buttons, and
    /// Downloaded. What came is written to frames.txt: the songs, their
    /// files, and the file the player plays.
    private static func library(_ albums: [Album]) async {
        MainWindow.select(8)
        await step("18-genres", wait: 2)
        if let genre = app.library.genres.max(by: { app.library.albums(inGenre: $0).count < app.library.albums(inGenre: $1).count }) {
            Pages.open(genre)
            await step("19-genre", wait: 2)
        }
        MainWindow.select(9)
        await step("20-recently-added", wait: 2)
        var log = ""
        // One the keep has not fetched all of, so its ring shows on the way.
        let whole = { (album: Album) in app.library.tracks(inAlbum: album.id).allSatisfy { app.offline.has($0.id) } }
        if let album = albums.first(where: { !whole($0) }) ?? albums.first {
            Pages.open(album)
            try? await Task.sleep(for: .seconds(1))
            await step("21a-album-download", wait: 0)
            await download("21b-album-downloading", reason: .album(album.id), log: &log)
            await step("21c-album-downloaded", wait: 1)
        }
        if let playlist = app.library.playlists.first {
            Pages.open(playlist)
            try? await Task.sleep(for: .seconds(2))
            await download(nil, reason: .playlist(playlist.id), log: &log)
        }
        if let mix = app.mixes.mixes.first {
            Pages.open(mix)
            try? await Task.sleep(for: .seconds(1))
            await download(nil, reason: .mix(mix.id), log: &log)
        }
        MainWindow.select(10)
        await step("22-downloaded", wait: 3)
        await scrolled(visiblePage(), to: 1, "22b-downloaded-songs")
        // A downloaded song plays from its file.
        let offline = app.offline
        if let collection = offline.collections.last, let first = collection.tracks.first(where: { offline.has($0.id) }) {
            app.player.play([first], context: QueueContext(.other, title: "Downloaded"))
            try? await Task.sleep(for: .seconds(1))
            let file = app.player.currentTrack.flatMap { offline.localURL(for: $0.id) }
            log += "playing \(first.name): from \(file?.path ?? "the server"), "
                + "a file there: \(file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)\n"
            app.player.stop()
        }
        let folder = offline.collections.first.flatMap { offline.localURL(for: $0.trackIDs[0]) }?.deletingLastPathComponent()
        let files = folder.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        log += "downloaded: \(offline.collections.count) collections, \(offline.songCount) songs, "
            + "\(offline.chosenBytes) bytes chosen, \(offline.keptBytes) kept; \(files.count) files in \(folder?.path ?? "none")\n"
        if let shots = Self.folder {
            let file = "\(shots)/frames.txt"
            try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + log).write(toFile: file, atomically: true, encoding: .utf8)
        }
    }

    /// The page's own Download clicked, then waited on until all of it is
    /// here (20 s at most); a picture of the ring on the way, when named.
    private static func download(_ name: String?, reason: OfflineReason, log: inout String) async {
        guard let button = find(visiblePage(), { widget in
            g_type_check_instance_is_a(ptr(widget), gtk_button_get_type()) != 0
                && gtk_button_get_icon_name(ptr(widget)).map { String(cString: $0) } == Glyphs.name("download")
        }) else {
            log += "\(reason): no Download on its page\n"
            return
        }
        gtk_widget_activate(button)
        // A button activated says "clicked" 250 ms later (GTK's press
        // shown); the fake's songs then take 0.4 to 2 s each.
        if let name { await step(name, wait: 1.2) }
        let clock = ContinuousClock(), start = clock.now
        for _ in 0..<80 where app.offline.state(of: reason) != .downloaded {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let took = (clock.now - start).components
        log += "\(reason): \(app.offline.state(of: reason)) after \(took.seconds).\(took.attoseconds / 100_000_000_000_000_000) s, "
            + (app.offline.collection(for: reason).map { app.offline.fact(of: $0) } ?? "not chosen") + "\n"
    }

    /// What the Mac and the iPad had and Linux has now too ("Linux erbij",
    /// 15 November 2026), each by its own button and dialog (a menu is a
    /// surface of its own, not in the window's picture; its items are run by
    /// their actions): Start a Station from Radio's +; a station's ⋮, Save as
    /// Playlist… and Add to Playlist…; a playlist made with New Playlist…,
    /// filled with Add Songs and deleted from its ⋮; an album's joined genre
    /// tag split; a song found in Search starting its station. With the panel
    /// closed, then as it was. What it makes on the fake server it deletes
    /// again, so the next size finds the library as it was.
    private static func parity(_ albums: [Album]) async {
        var log = ""
        let wasOpen = app.panel.isOpen
        app.panel.isOpen = false
        let playlistsBefore = Set(app.library.playlists.map(\.id))

        // Start a Station: the suggestions, "blue" found, the first artist's
        // station's page (the list's first line is its heading).
        MainWindow.select(1)
        try? await Task.sleep(for: .seconds(1))
        if let start = find(visiblePage(), { icon(of: $0) == "list-add-symbolic" }) { gtk_widget_activate(start) }
        await step("02b-start-station", wait: 1.5)
        if let field = find(dialog(), { isA($0, gtk_search_entry_get_type()) }) { gtk_editable_set_text(ptr(field), "blue") }
        await step("02c-start-station-found", wait: 1.5)
        if let picks = find(dialog(), { gtk_widget_has_css_class($0, "picks") != 0 }) {
            gtk_widget_activate_action_variant(picks, "list.activate-item", g_variant_new_uint32(1))
        }
        await step("02d-start-station-page", wait: 2.5)

        // Its ⋮: Save as Playlist… under the name it suggests, then saved;
        // Add to Playlist….
        if let more = find(visiblePage(), { isA($0, gtk_menu_button_get_type()) && tooltip(of: $0) == "More" }),
           let menu = gtk_menu_button_get_popover(ptr(more)) {
            let items: Widget = ptr(menu)
            gtk_widget_activate_action_variant(items, "menu.item0", nil)
            await step("03b-station-save", wait: 1)
            enterInDialog()
            await step("03c-station-saved", wait: 2)
            gtk_widget_activate_action_variant(items, "menu.item1", nil)
            await step("03d-station-add-to-playlist", wait: 1.5)
            closeDialog()
        } else {
            log += "the station's page: no ⋮\n"
        }

        // An album tagged "Electronic; Techno": its head says Electronic.
        if let album = albums.first(where: { $0.genres.contains { $0.contains(";") } }) {
            Pages.open(album)
            await step("05b-album-genre", wait: 2)
            log += "05b-album-genre: \(album.name), tagged \(album.genres), its head says \(LibraryIndex.genreNames(album.genres).first ?? "nothing")\n"
        }

        // New Playlist…, named; its page, empty; Add Songs, two added; the
        // page again, with them; Delete Playlist from its ⋮, asked first.
        MainWindow.select(6)
        try? await Task.sleep(for: .seconds(1))
        if let new = find(visiblePage(), { icon(of: $0) == "list-add-symbolic" }) { gtk_widget_activate(new) }
        try? await Task.sleep(for: .seconds(0.5))
        if let name = find(dialog(), { isA($0, gtk_entry_get_type()) }) { gtk_editable_set_text(ptr(name), "Rainy Afternoon") }
        await step("08f-playlist-new", wait: 1)
        enterInDialog()
        await step("08g-playlist-empty", wait: 2)
        if let add = find(visiblePage(), { icon(of: $0) == "list-add-symbolic" }) { gtk_widget_activate(add) }
        await step("08h-add-songs", wait: 1.5)
        if let picks = find(dialog(), { gtk_widget_has_css_class($0, "picks") != 0 }) {
            for row in [0, 2] { gtk_widget_activate_action_variant(picks, "list.activate-item", g_variant_new_uint32(UInt32(row))) }
        }
        await step("08i-add-songs-added", wait: 1.5)
        closeDialog()
        await step("08j-playlist-filled", wait: 2)
        let made = app.library.playlists.first { $0.name == "Rainy Afternoon" }
        log += "New Playlist…: \(made.map { "“\($0.name)”, \($0.trackCount ?? 0) songs" } ?? "not made")\n"
        if let more = find(visiblePage(), { isA($0, gtk_menu_button_get_type()) && tooltip(of: $0) == "More" }),
           let menu = gtk_menu_button_get_popover(ptr(more)) {
            // Delete Playlist by its words: Don't Count Plays and Choose
            // Picture… come before it, the second only once the server says.
            gtk_widget_activate_action_variant(ptr(menu), menuAction(ptr(menu), "Delete Playlist") ?? "menu.none", nil)
            await step("08k-playlist-delete", wait: 1)
            if let delete = find(dialog(), { isA($0, gtk_button_get_type()) && label(of: $0) == "Delete Playlist" }) {
                gtk_widget_activate(delete)
            }
            await step("08l-playlist-deleted", wait: 2)
        }
        log += "Delete Playlist: \(app.library.playlists.contains { $0.name == "Rainy Afternoon" } ? "still there" : "gone")\n"

        // A song found in Search: its station, not the songs found.
        gtk_widget_activate_action_variant(MainWindow.window, "app.search", nil)
        SearchField.shared.text = "night drive"
        try? await Task.sleep(for: .seconds(1.5))
        if let songs = find(visiblePage(), { gtk_widget_has_css_class($0, "rows") != 0 }) {
            gtk_widget_activate_action_variant(songs, "list.activate-item", g_variant_new_uint32(0))
        }
        await step("08m-search-song", wait: 2.5)
        log += "a song in Search: \(app.player.currentTrack?.name ?? "nothing") plays, on \(app.radio.station?.title ?? "no station"), "
            + "then \(app.player.upNext.prefix(3).map(\.track.name))\n"
        MainWindow.select(1)
        await step("08n-search-song-station", wait: 2)
        SearchField.shared.text = ""

        // What the walk made, gone again.
        for playlist in app.library.playlists where !playlistsBefore.contains(playlist.id) {
            try? await app.library.delete(playlist)
        }
        app.panel.isOpen = wasOpen
        if let shots = Self.folder {
            let file = "\(shots)/frames.txt"
            try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + log).write(toFile: file, atomically: true, encoding: .utf8)
        }
    }

    /// A song on a station's page plays when it is clicked, and the list
    /// after it — also once the list has started its station, and at the
    /// second click of two: such a click once started the station anew
    /// with other songs ("speelt er elke keer een heel ander nummer af",
    /// the photographer, 16 November 2026). In frames.txt, no picture.
    private static func stationClicks() async {
        let station = app.radio.station(for: .personal)
        // The page's own list: the same draw from the same library.
        let picks = await app.radio.preview(station, randomSeed: app.radio.pageSeed(for: station)).map(\.track.name)
        Pages.open(station)
        try? await Task.sleep(for: .seconds(2))
        guard picks.count > 5, let songs = find(visiblePage(), { gtk_widget_has_css_class($0, "rows") != 0 }) else { return }
        var log = ""
        for (row, clicks) in [(2, 1), (4, 2)] {
            for _ in 0..<clicks { gtk_widget_activate_action_variant(songs, "list.activate-item", g_variant_new_uint32(UInt32(row))) }
            try? await Task.sleep(for: .seconds(1.5))
            let plays = [app.player.currentTrack?.name ?? "nothing", app.player.upNext.first?.track.name ?? "nothing"]
            log += "a station's row \(row) clicked \(clicks)x: \(picks[row...(row + 1)]) asked, \(plays) plays: "
                + "\(plays == Array(picks[row...(row + 1)]) ? "ok" : "WRONG")\n"
        }
        guard let shots = folder else { return }
        let file = "\(shots)/frames.txt"
        try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + log).write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// A song's menu in Up next on a station, open (a popover is its own
    /// surface: "14b-ready" in the folder says when, for a picture of the
    /// screen from outside), its titles in frames.txt with "·" where a
    /// section starts.
    private static func queueMenu() async {
        guard let folder else { return }
        var rows: [Widget] = []
        func collect(_ widget: Widget) {
            if gtk_widget_has_css_class(widget, "queue-row") != 0, gtk_widget_has_css_class(widget, "station") != 0,
               gtk_widget_get_mapped(widget) != 0 { rows.append(widget) }
            var child = gtk_widget_get_first_child(widget)
            while let next = child { collect(next); child = gtk_widget_get_next_sibling(next) }
        }
        if let window = MainWindow.window { collect(window) }
        // The second: the first is the song on the air.
        guard rows.count > 1, let owner = gtk_widget_get_parent(rows[1]),
              let row: UpNextRow = kept(on: raw(owner)) else { return }
        let items = row.menu()
        let line = "queue menu: \(items.map { $0.0 == menuBreak.0 ? "·" : $0.0.replacingOccurrences(of: "\u{1F}", with: "|") })\n"
        let file = "\(folder)/frames.txt"
        try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + line).write(toFile: file, atomically: true, encoding: .utf8)
        showMenu(at: owner, x: 120, y: Double(gtk_widget_get_height(owner)) / 2, items)
        try? await Task.sleep(for: .seconds(1))
        FileManager.default.createFile(atPath: "\(folder)/14b-ready", contents: nil)
        try? await Task.sleep(for: .seconds(3))
        try? FileManager.default.removeItem(atPath: "\(folder)/14b-ready")
        var child = gtk_widget_get_first_child(owner)
        while let next = child {
            if isA(next, gtk_popover_get_type()) { gtk_popover_popdown(ptr(next)) }
            child = gtk_widget_get_next_sibling(next)
        }
        try? await Task.sleep(for: .seconds(0.5))
        // Two of the station's songs to come picked: their menu (14c, 14d).
        guard rows.count > 2, let second = gtk_widget_get_parent(rows[2]),
              let list = find(MainWindow.window, { gtk_widget_has_css_class($0, "queue") != 0 }),
              let picked: PickedRows = kept(on: raw(list), as: "picked"),
              let next: UpNextRow = kept(on: raw(second)) else { return }
        picked.picks.click(row.position, .toggle)
        picked.picks.click(next.position, .toggle)
        await step("14c-radio-up-next-picked", wait: 1)
        // Found again: the list may have made its rows anew since.
        rows = []
        if let window = MainWindow.window { collect(window) }
        if let again = rows.compactMap({ gtk_widget_get_parent($0) }).first(where: { widget in
            (kept(on: raw(widget)) as UpNextRow?).map { picked.picks.contains($0.position) } ?? false
        }), let shown: UpNextRow = kept(on: raw(again)) {
            await popped(at: again, shown.menu(), "14d-radio-up-next-picked-menu")
        }
        picked.picks.clear()
    }

    /// A playlist of one's own with three songs picked, and the menu on
    /// them: Move to Top, Move to Bottom, Remove from Playlist first
    /// (07b, 07c). Nothing chosen.
    private static func playlistPicked() async {
        guard let playlist = app.library.playlists.first(where: { !$0.isReadOnly }) else { return }
        Pages.open(playlist)
        try? await Task.sleep(for: .seconds(2))
        guard let rows = find(visiblePage(), { gtk_widget_has_css_class($0, "rows") != 0 }),
              let picked: PickedRows = kept(on: raw(rows), as: "picked") else { return }
        picked.picks.plain(0)
        picked.picks.click(2, .extend)
        await step("07b-playlist-picked", wait: 1)
        var found: [Widget] = []
        func collect(_ widget: Widget) {
            if gtk_widget_has_css_class(widget, "track-row") != 0, gtk_widget_get_mapped(widget) != 0 { found.append(widget) }
            var child = gtk_widget_get_first_child(widget)
            while let next = child { collect(next); child = gtk_widget_get_next_sibling(next) }
        }
        collect(rows)
        if found.count > 1, let row: TrackRow = kept(on: raw(found[1])) {
            await popped(at: found[1], row.menu(), "07c-playlist-picked-menu")
        }
        picked.picks.clear()
        adw_navigation_view_pop(ptr(Nav.view))
    }

    /// The primary menu: the accounts, Add Account…, Sign Out… (16f).
    private static func primaryMenu() async {
        guard let folder else { return }
        gtk_menu_button_popup(ptr(MainWindow.placesMenu))
        try? await Task.sleep(for: .seconds(1))
        FileManager.default.createFile(atPath: "\(folder)/16f-primary-menu-ready", contents: nil)
        try? await Task.sleep(for: .seconds(3))
        try? FileManager.default.removeItem(atPath: "\(folder)/16f-primary-menu-ready")
        gtk_menu_button_popdown(ptr(MainWindow.placesMenu))
        try? await Task.sleep(for: .seconds(0.5))
    }

    /// `items` as a song's menu on `owner`, pictured from outside as
    /// `name`, written to frames.txt, then closed.
    private static func popped(at owner: Widget, _ items: [(String, () -> Void)], _ name: String) async {
        guard let folder else { return }
        let line = "\(name): \(items.map { $0.0 == menuBreak.0 ? "·" : $0.0.replacingOccurrences(of: "\u{1F}", with: "|") })\n"
        let file = "\(folder)/frames.txt"
        try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + line).write(toFile: file, atomically: true, encoding: .utf8)
        showMenu(at: owner, x: 120, y: Double(gtk_widget_get_height(owner)) / 2, items)
        try? await Task.sleep(for: .seconds(1))
        FileManager.default.createFile(atPath: "\(folder)/\(name)-ready", contents: nil)
        try? await Task.sleep(for: .seconds(3))
        try? FileManager.default.removeItem(atPath: "\(folder)/\(name)-ready")
        var child = gtk_widget_get_first_child(owner)
        while let next = child {
            if isA(next, gtk_popover_get_type()) { gtk_popover_popdown(ptr(next)) }
            child = gtk_widget_get_next_sibling(next)
        }
        try? await Task.sleep(for: .seconds(0.5))
    }

    /// The action of a popover menu's item called `title`, in any of its
    /// sections.
    private static func menuAction(_ popover: Widget, _ title: String) -> String? {
        guard let model = gtk_popover_menu_get_menu_model(ptr(popover)) else { return nil }
        return modelAction(model, title)
    }

    private static func modelAction(_ model: UnsafeMutablePointer<GMenuModel>, _ title: String) -> String? {
        for index in 0..<g_menu_model_get_n_items(model) {
            if let section = g_menu_model_get_item_link(model, index, "section") {
                defer { g_object_unref(raw(section)) }
                if let found = modelAction(section, title) { return found }
                continue
            }
            guard let label = g_menu_model_get_item_attribute_value(model, index, "label", nil) else { continue }
            defer { g_variant_unref(label) }
            guard String(cString: g_variant_get_string(label, nil)) == title,
                  let action = g_menu_model_get_item_attribute_value(model, index, "action", nil) else { continue }
            defer { g_variant_unref(action) }
            return String(cString: g_variant_get_string(action, nil))
        }
        return nil
    }

    /// The dialog over the window, if one is up.
    private static func dialog() -> Widget? {
        adw_application_window_get_visible_dialog(ptr(MainWindow.window)).map { ptr($0) }
    }

    private static func closeDialog() {
        if let dialog = dialog() { adw_dialog_close(ptr(dialog)) }
    }

    /// Enter in the dialog's name field, as the key sends it.
    private static func enterInDialog() {
        if let entry = find(dialog(), { isA($0, gtk_entry_get_type()) }) { enter(entry, type: gtk_entry_get_type()) }
    }

    private static func isA(_ widget: Widget, _ type: GType) -> Bool {
        g_type_check_instance_is_a(ptr(widget), type) != 0
    }

    private static func icon(of widget: Widget) -> String? {
        guard isA(widget, gtk_button_get_type()) else { return nil }
        return gtk_button_get_icon_name(ptr(widget)).map { String(cString: $0) }
    }

    private static func label(of widget: Widget) -> String? {
        gtk_button_get_label(ptr(widget)).map { String(cString: $0) }
    }

    private static func tooltip(of widget: Widget) -> String? {
        gtk_widget_get_tooltip_text(widget).map { String(cString: $0) }
    }

    /// `root`'s first scroller `fraction` of the way down, as a picture.
    private static func scrolled(_ root: Widget?, to fraction: Double, _ name: String) async {
        guard let scroller = find(root, { String(cString: gtk_widget_get_css_name($0)) == "scrolledwindow" }),
              let adjustment = gtk_scrolled_window_get_vadjustment(ptr(scroller)) else { return }
        gtk_adjustment_set_value(adjustment, (gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment)) * fraction)
        await step(name, wait: 1)
    }

    /// One of Preferences' pages, chosen as its view switcher would.
    private static func shown(_ dialog: UnsafeMutablePointer<AdwDialog>, _ page: Preferences.Page, _ name: String) async {
        adw_preferences_dialog_set_visible_page_name(ptr(dialog), page.rawValue)
        await step(name, wait: 1)
    }

    /// Preferences › Pages: a sidebar with fewer places, on Albums; then
    /// every page off, from Albums, which goes Home: no sidebar at all,
    /// Home, the panel and the bar. The listener's choice put back after.
    private static func pages() async {
        let settings = app.settings
        let before = settings.hiddenPages
        settings.hiddenPages = [.radio, .songs, .favorites, .genres, .recentlyAdded, .sidebarPlaylists]
        MainWindow.select(3)
        await step("23-pages-trimmed", wait: 2)
        settings.hiddenPages = Set(AppSettings.Page.allCases)
        await step("24-pages-none", wait: 2)
        settings.hiddenPages = before
        // Remove All Downloads, as Preferences does it: Downloaded with
        // nothing, its one line. The keep (turned off with it) on again
        // for the next size.
        app.offline.removeAll()
        MainWindow.select(10)
        await step("25-downloaded-empty", wait: 2)
        settings.keepSongs = true
    }

    /// The pointer over `widgets`, as a picture: Xvfb has no pointer, so
    /// they are told they are under it, then told again they are not.
    private static func hovering(_ widgets: [Widget?], _ name: String) async {
        let lit = widgets.compactMap { $0 }
        for widget in lit { gtk_widget_set_state_flags(widget, GTK_STATE_FLAG_PRELIGHT, 0) }
        await step(name, wait: 0.5)
        for widget in lit { gtk_widget_unset_state_flags(widget, GTK_STATE_FLAG_PRELIGHT) }
    }

    /// Enter in a search field (or another `type` of field): its
    /// "activate", as the key sends it.
    private static func enter(_ field: Widget, type: GType = gtk_search_entry_get_type()) {
        var instance = GValue()
        g_value_init(&instance, type)
        g_value_set_object(&instance, raw(field))
        g_signal_emitv(&instance, g_signal_lookup("activate", type), 0, nil)
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

    /// Songs picked with Ctrl and Shift on Songs (TrackPicks): lit, and the
    /// menu on one of them for all of them; frames.txt says what it held.
    private static func picking() async {
        guard let folder, let rows = find(visiblePage(), { gtk_widget_has_css_class($0, "rows") != 0 }),
              let picked: PickedRows = kept(on: raw(rows), as: "picked") else { return }
        picked.picks.plain(1)
        picked.picks.click(3, .extend)
        picked.picks.click(5, .toggle)
        await step("07a-songs-picked", wait: 1)
        let tracks = picked.picks.tracks(at: 2, in: picked.items())
        let menu = trackMenu(tracks).map(\.0)
        let file = "\(folder)/frames.txt"
        let line = "picked: \(tracks.map(\.name)), menu: \(menu)\n"
        try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + line).write(toFile: file, atomically: true, encoding: .utf8)
        picked.picks.clear()
    }

    /// Don't Count Plays and Private Listening (NotCounted.swift): an album
    /// marked, its page with "Not counted" and the bar's sign, its ⋮ open
    /// (a popover is its own surface: "30b-ready" in the folder says when,
    /// for a picture of the screen from outside), Preferences' group. Then
    /// both as they were.
    private static func notCounted(_ albums: [Album]) async {
        guard let folder, let album = albums.first else { return }
        let store = app.player.notCounted
        store.set(.album, id: album.id, name: album.name, counted: false)
        store.privateListening = .untilRestart
        Pages.open(album)
        await step("30-album-not-counted", wait: 2)
        let menu = albumMenu(album).map(\.0)
        let line = "album menu: \(menu.map { $0.replacingOccurrences(of: "\u{1F}", with: "|") })\n"
        let file = "\(folder)/frames.txt"
        try? (((try? String(contentsOfFile: file, encoding: .utf8)) ?? "") + line).write(toFile: file, atomically: true, encoding: .utf8)
        if let more = find(visiblePage(), { isA($0, gtk_menu_button_get_type()) && tooltip(of: $0) == "More" }) {
            gtk_menu_button_popup(ptr(more))
            FileManager.default.createFile(atPath: "\(folder)/30b-ready", contents: nil)
            try? await Task.sleep(for: .seconds(3))
            gtk_menu_button_popdown(ptr(more))
            try? FileManager.default.removeItem(atPath: "\(folder)/30b-ready")
        }
        Preferences.present()
        try? await Task.sleep(for: .seconds(1))
        if let dialog = dialog() {
            await shown(ptr(dialog), .privacy, "30c-preferences-not-counted")
            adw_dialog_force_close(ptr(dialog))
        }
        store.set(.album, id: album.id, name: album.name, counted: true)
        store.privateListening = .off
        try? await Task.sleep(for: .seconds(1))
    }

    /// Mini Player (Extras.swift): its window alone, then the big one again.
    private static func miniPlayer() async {
        MiniPlayer.open()
        try? await Task.sleep(for: .seconds(2))
        guard let folder, let mini = MiniPlayer.shown, let node = picture(mini) else { return }
        write(node, to: "\(folder)/09m-mini-player.png", of: mini)
        gtk_window_close(ptr(mini))
        try? await Task.sleep(for: .seconds(1))
    }

    /// JUKEBOX_SHOTS_PLAY_ON=<file.png>: the bar's Play On open, as it is
    /// after a few seconds of looking, its popover alone to the file; and
    /// "<file>.ready" while it is open, for a picture of the screen from
    /// outside. Then the app quits.
    static func playOn() {
        guard let path = ProcessInfo.processInfo.environment["JUKEBOX_SHOTS_PLAY_ON"] else { return }
        Task {
            // A song in the bar, paused: the bar shows with something in it.
            for _ in 0..<40 where app.library.tracks.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            app.player.play(Array(app.library.tracks.prefix(5)), context: QueueContext(.other, title: "Shot"))
            app.player.pause()
            try? await Task.sleep(for: .seconds(3))
            guard let button = find(MainWindow.window, { isA($0, gtk_menu_button_get_type()) && tooltip(of: $0) == "Play On" }),
                  let popover = gtk_menu_button_get_popover(ptr(button)) else { exit(1) }
            gtk_menu_button_popup(ptr(button))
            try? await Task.sleep(for: .seconds(5))
            let shown: Widget = ptr(popover)
            // The last row as under the pointer: the menu's own hover.
            if let list = find(shown, { isA($0, gtk_list_box_get_type()) }), let row = gtk_widget_get_last_child(list) {
                gtk_widget_set_state_flags(row, GTK_STATE_FLAG_PRELIGHT, 0)
                try? await Task.sleep(for: .milliseconds(300))
            }
            if let node = picture(shown) { write(node, to: path, of: shown) }
            FileManager.default.createFile(atPath: path + ".ready", contents: nil)
            try? await Task.sleep(for: .seconds(4))
            try? FileManager.default.removeItem(atPath: path + ".ready")
            // JUKEBOX_SHOTS_PLAY_ON_SECONDS: then the fake renderer of
            // JUKEBOX_UPNP_DEVICE chosen (never a speaker in the house: the
            // network is not asked then) and played on for so long, Next
            // pressed 3 s into its first song, the queue's songs printed as
            // they go.
            if let seconds = ProcessInfo.processInfo.environment["JUKEBOX_SHOTS_PLAY_ON_SECONDS"].flatMap(Int.init),
               UPnPFinder.testLocation != nil,
               let device = app.player.playOn.devices.first(where: { $0.kind == .upnp }) {
                app.player.playOn.choose(device)
                // A Subsonic token account's question, answered as a click would.
                if let asked = app.player.playOn.pendingKeyNotice {
                    print("play on: asked about \(asked.name)'s key")
                    app.player.playOn.castAnyway()
                }
                gtk_menu_button_popdown(ptr(button))
                app.player.resume()
                for second in 0..<seconds {
                    if second == 3 { app.player.next() }
                    print("play on: \(app.player.playsOn?.name ?? "here") \(app.player.current?.track.name ?? "-") "
                          + "\(Int(app.player.elapsed)) s \(app.player.isPlaying ? "playing" : "paused")")
                    try? await Task.sleep(for: .seconds(1))
                }
                app.player.playOn.choose(nil)
                try? await Task.sleep(for: .seconds(1))
                print("play on: back \(app.player.playsOn?.name ?? "here") \(app.player.current?.track.name ?? "-")")
            }
            exit(0)
        }
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
    private static func write(_ node: OpaquePointer, to path: String, of window: Widget = MainWindow.window) {
        defer { gsk_render_node_unref(node) }
        guard let native = gtk_widget_get_native(window), let renderer = gtk_native_get_renderer(native),
              let texture = gsk_renderer_render_texture(renderer, node, nil) else { return }
        gdk_texture_save_to_png(texture, path)
        g_object_unref(raw(texture))
    }
}
