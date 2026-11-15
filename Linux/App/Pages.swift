// The places and their pages. Each is made once from the stores and then
// follows them (`observe`); the choosing behind them — what Home's shelves
// hold, what a station would play — is the shared code's, the same as on
// the iPhone.

import CAdw
import Foundation
import JukeboxKit
import Observation

// MARK: - Home

/// Home, as sketch D has it: the part of the day in the serif, Your Station
/// with the one Play, the mixes made up today, then what was played lately,
/// most, what to explore and what is new.
enum HomePage {
    /// The designer's Home (spec §5): the part of the day, Your Station, the
    /// mixes, what was played lately in columns of rows, then shelves of
    /// tiles, each section 40 under the last.
    static func make() -> Widget {
        let column = vbox()
        observe(column) {
            let library = app.library
            clear(column)
            defer { measure(column) }
            guard !library.tracks.isEmpty else {
                append(libraryStatus(), to: column)
                return
            }
            append(pageTitle(RelativeDay.partOfDay()), to: column)
            if let notice = offlineNotice() { append(notice, to: column) }
            if let offer = app.handoff.offer { append(handoffNotice(offer), to: column) }
            append(yourStation(), to: column)

            let mixes = app.mixes.mixes
            if !mixes.isEmpty {
                let made = app.mixes.builtAt.map { "Made at \($0.formatted(date: .omitted, time: .shortened))" }
                append(sectionTitle("Mixes", fact: made), to: column)
                append(shelf(mixes.map(mixTile)), to: column)
            }

            let events = app.history.history.events
            let lately = HomeShelves.recentlyPlayedDated(events: events, tracks: library.tracks, albums: library.albums,
                                                         track: library.track(id:), album: library.album(id:), limit: 12)
            if !lately.isEmpty {
                append(sectionTitle("Played lately", below: 8), to: column)
                append(latelyRows(lately), to: column)
            }
            let most = HomeShelves.mostPlayed(tracks: library.tracks, album: library.album(id:))
            if !most.isEmpty {
                append(sectionTitle("Most played"), to: column)
                append(shelf(most.map { albumTile($0) }), to: column)
            }
            let explore = HomeShelves.explore(albums: library.albums, day: HomeShelves.dayNumber(of: Date()))
            if !explore.isEmpty {
                append(sectionTitle("Explore"), to: column)
                append(shelf(explore.map { albumTile($0) }), to: column)
            }
            let new = Array(library.recentlyAddedAlbums.prefix(20))
            if !new.isEmpty {
                append(sectionTitle("Recently added"), to: column)
                append(shelf(new.map { albumTile($0) }), to: column)
            }
        }
        // Made in the morning, opened in the evening: the day's own mixes.
        Task { await app.mixes.rebuildIfStale(library: app.library, history: app.history, settings: app.settings) }
        return pageColumn(column)
    }

    /// Played lately: rows of 64 (cover 48, 16, the album over "Artist ·
    /// Today") on hairlines, in the page's columns, 24 apart.
    private static func latelyRows(_ lately: [(album: Album, date: Date)]) -> Widget {
        let grid = gtk_grid_new()!
        gtk_grid_set_column_spacing(ptr(grid), 24)
        gtk_grid_set_column_homogeneous(ptr(grid), 1)
        let columns = PageMeasure.shared.columns
        for (index, (album, date)) in lately.enumerated() {
            let art = Art(48)
            art.show(album.artwork)
            let words = vbox(spacing: 0, [label(album.name, "t15"),
                                          label([album.artistLine, RelativeDay.standalone(date)].filter { !$0.isEmpty }.joined(separator: " · "), "t13", "fact")])
            let row = hbox(spacing: 16, [art.widget, words.expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER)]).size(height: 64)
            keep(art, on: raw(row), as: "art")
            let button = tileButton(row) { Pages.open(album) }.align(horizontal: GTK_ALIGN_FILL)
            contextMenu(on: button) { albumMenu(album) }
            gtk_grid_attach(ptr(grid), vbox([button, hairline()]), Int32(index % columns), Int32(index / columns), 1, 1)
        }
        return grid
    }

    /// Before the library is in: that it is loading, or why it is not.
    static func libraryStatus() -> Widget {
        switch app.library.state {
        case let .failed(message):
            let page = emptyPage("Could not load your music", message)
            adw_status_page_set_child(ptr(page), button("Try Again", "suggested-action") {
                Task { await app.library.refresh() }
            }.align(horizontal: GTK_ALIGN_CENTER))
            return page
        case .loaded:
            return emptyPage("No music yet", "Music on your \(app.library.serverKind) server appears here.")
        case .empty, .loading:
            let name = app.library.serverName.map { "Loading the music on \($0)" } ?? "Loading your music"
            let page = emptyPage(name, "")
            let spinner = gtk_spinner_new()!.size(width: 32, height: 32).align(horizontal: GTK_ALIGN_CENTER)
            gtk_spinner_start(ptr(spinner))
            adw_status_page_set_child(ptr(page), spinner)
            return page
        }
    }

    /// Offline, or the library could not be read: why first — no network at
    /// all, or no server on it — then what still works, and Try Again (the
    /// iPhone's HomeOfflineNotice, in the handoff's form beside it).
    private static func offlineNotice() -> Widget? {
        let offline = app.offline
        let failed = if case .failed = app.library.state { true } else { false }
        guard failed || offline.isOffline else { return nil }
        let why = offline.hasNetwork ? "Can’t reach \(app.library.serverName ?? "your server")." : "You’re offline."
        let still = offline.songCount > 0 ? "The songs on this \(Device.model) still play." : "Showing your library from last time."
        let again = wordButton("Try Again") {
            offline.checkServer()
            Task { await app.library.refresh() }
        }
        return vbox(spacing: 4, [label("\(why) \(still)", lines: 0).margins(horizontal: 8), again]).margins(horizontal: 4, vertical: 8)
    }

    /// Music on another device, or this one's from last time, and the one
    /// thing to do about it (HandoffStore): words on Home's ground, as on
    /// the iPhone, and nowhere near the player's controls — "ik wil die
    /// melding echt niet over de controls hebben" (the photographer, 14
    /// November 2026, of a banner over the player's bar).
    private static func handoffNotice(_ offer: HandoffStore.Offer) -> Widget {
        let go = wordButton(offer.isOwn ? "Continue" : "Continue Here") { app.handoff.continueHere() }
        let words = vbox(spacing: 4, [
            label(offer.heading, "fact").margins(horizontal: 8),
            label("\(offer.track.name) · \(offer.track.artistLine)").margins(horizontal: 8),
            go,
        ])
        return words.margins(horizontal: 4, vertical: 8)
    }

    /// Your Station: its arch 120, 24, the name in the serif, one fact, the
    /// one Play; "On air" over the name while it plays.
    private static func yourStation() -> Widget {
        let station = app.radio.station(for: .personal)
        let art = StationArt(120)
        art.show(station)
        let onAir = app.radio.station?.id == station.id
        let dates = HomeShelves.stationDates(events: app.history.history.events)
        let fact = onAir ? RadioPage.started(station) ?? "" : RelativeDay.lastPlayed(dates[station.id])
        let name = button("Your Station", "flat", "plain") { Pages.open(station) }.align(horizontal: GTK_ALIGN_START)
        gtk_widget_add_css_class(gtk_button_get_child(ptr(name)), "serif")
        gtk_widget_add_css_class(gtk_button_get_child(ptr(name)), "section-title")
        let words = vbox()
        if onAir { append(label("On air", "t13", "accent"), to: words) }
        append(name, to: words)
        let line = label(fact, "t13", "fact")
        gtk_widget_set_margin_top(line, 8)
        append(line, to: words)
        let play = playButton(onAir && app.player.isPlaying ? "Pause" : "Play") {
            if app.radio.station?.id == station.id { app.player.togglePlayPause() } else { app.radio.start(station) }
        }
        gtk_widget_set_margin_top(play, 16)
        append(play, to: words)
        let row = hbox(spacing: 24, [art.widget, words.align(vertical: GTK_ALIGN_CENTER)])
        gtk_widget_set_margin_top(row, 32)
        keep(art, on: raw(row), as: "art")
        return row
    }

    private static func mixTile(_ mix: Mix) -> Widget {
        let tile = Tile()
        tile.show(collage: mix.artwork, mix.title, mix.subtitle)
        let button = tileButton(tile.widget) { Pages.open(mix) }
        contextMenu(on: button) {
            [("Play", { app.player.play(mix.tracks, context: QueueContext(.mix(mix.id), title: mix.title)) }),
             ("Start Radio", { app.radio.start(mix.stationSeed) })]
        }
        return button
    }
}

// MARK: - Radio

/// Radio: the station on the air, the stations made from the
/// listener's own taste and the ones played lately, then stations by
/// artist, genre and decade.
enum RadioPage {
    /// The designer's Radio (spec §5): the station on air, lit, then the
    /// stations and the ones by genre and decade in tiles, every arch flat
    /// but the one on air. The dial is in Up next.
    static func make() -> Widget {
        let stations = vbox().css("group")
        let column = vbox(spacing: 0, [pageTitle("Radio"), onAir(), stations])
        observe(stations) {
            clear(stations)
            defer { measure(column) }
            guard !app.library.tracks.isEmpty else {
                append(HomePage.libraryStatus(), to: stations)
                return
            }
            _ = PageMeasure.shared.tile
            let dates = HomeShelves.stationDates(events: app.history.history.events)
            let suggested = app.mixes.stations
            var listed = [StationSeed.personal, .discovery, .favorites].map { app.radio.station(for: $0) }
            for station in app.radio.recentStations + suggested.filter({ if case .artist = $0.seed { true } else { false } })
            where !listed.contains(where: { $0.id == station.id }) {
                listed.append(station)
            }
            // The one on air is the hero above.
            listed.removeAll { $0.id == app.radio.station?.id }
            append(sectionTitle("Stations"), to: stations)
            append(shelf(listed.prefix(12).map { stationTile($0, fact: RelativeDay.played(dates[$0.id])) }), to: stations)
            let kinds = suggested.filter {
                switch $0.seed {
                case .genre, .decade: true
                default: false
                }
            }
            if !kinds.isEmpty {
                append(sectionTitle("By genre and decade"), to: stations)
                append(shelf(kinds.map { stationTile($0, fact: $0.subtitle ?? "") }), to: stations)
            }
        }
        return pageColumn(column)
    }

    /// When the station on air started, as this window saw it.
    /// ponytail: kept in memory from the first time it is seen on air; one
    /// restored at launch has started at the launch.
    private static var startedAt: (id: String, date: Date)?

    /// Follows the radio from the window's start, so the time is the start's.
    static func follow(_ owner: Widget) {
        observe(owner) {
            let id = app.radio.station?.id
            if id != startedAt?.id { startedAt = id.map { ($0, Date()) } }
        }
    }

    static func started(_ station: Station) -> String? {
        guard let startedAt, startedAt.id == station.id else { return nil }
        return "Started at \(startedAt.date.formatted(date: .omitted, time: .shortened))"
    }

    /// The station on air: its art 176, lit; "On air" (the screen's one
    /// small label, tells.md 4), its name in the serif 32/40, when it
    /// started, Pause and Stop. Made once and filled as the radio moves.
    private static func onAir() -> Widget {
        let art = StationArt(176)
        let name = label("", "serif", "hero-title")
        let since = label("", "t13", "fact")
        gtk_widget_set_margin_top(name, 4)
        gtk_widget_set_margin_top(since, 4)
        let pause = playButton("Pause") { app.player.togglePlayPause() }
        let stop = wordButton("Stop") {
            app.radio.stop()
            app.player.stop()
        }
        let buttons = hbox(spacing: 16, [pause, stop])
        gtk_widget_set_margin_top(buttons, 16)
        let words = vbox(spacing: 0, [label("On air", "t13", "accent"), name, since, buttons])
        let row = hbox(spacing: 24, [art.widget, words.align(vertical: GTK_ALIGN_CENTER)])
        gtk_widget_set_margin_top(row, 32)
        keep(art, on: raw(row), as: "art")
        observe(row) {
            let station = app.radio.station
            row.isVisible = station != nil
            guard let station else { return }
            art.show(station)
            setText(name, station.title)
            setText(since, started(station) ?? app.player.currentTrack.map { "\($0.name) · \($0.artistLine)" } ?? "")
            gtk_button_set_label(ptr(pause), app.player.isPlaying ? "Pause" : "Play")
        }
        return row
    }
}

// MARK: - Search

/// The search field at the end of every page's header bar, the Mac's
/// toolbar field in GNOME's form: one text for all of them, which the
/// Search page's results follow. A field always there rather than GNOME's
/// usual button and search bar under the header: search is one of the
/// app's main ways in, the HIG lets such a search stay in sight, and a bar
/// under the header would be a second bar ("ik wil die searchbar gewoon
/// bovenin de vensterbar hebben", the photographer, 14 November 2026).
///
/// The Search page is reached only through it: a click in a field (or
/// Ctrl+F, or typing on a page) shows the Search page with its own field
/// ready, the recent searches under it until something is typed.
@Observable
final class SearchField {
    static let shared = SearchField()
    /// What every page's field says.
    var text = ""
    /// The last eight searches, newest first: what was typed, not what it
    /// found, so one typed again finds what the library has now.
    private(set) var recents: [String] = []
    /// The Search page's own field, the one typed in.
    @ObservationIgnored var home: Widget?

    /// A page's field. `page`: typing there, outside a field, goes into it.
    static func entry(typingIn page: Widget) -> Widget {
        let entry = gtk_search_entry_new()!
        gtk_search_entry_set_placeholder_text(ptr(entry), "Search")
        // As wide as 24 characters where the header has room; it gives way
        // to the header's least in a narrow window.
        gtk_editable_set_width_chars(ptr(entry), 4)
        gtk_editable_set_max_width_chars(ptr(entry), 24)
        gtk_search_entry_set_key_capture_widget(ptr(entry), page)
        gtk_widget_set_valign(entry, GTK_ALIGN_CENTER)
        // Being told: setting the text empties it first, and an empty
        // field says so at once, which is not the listener's doing.
        var isTold = false
        observe(entry) {
            let text = shared.text
            guard String(cString: gtk_editable_get_text(ptr(entry))) != text else { return }
            isTold = true
            gtk_editable_set_text(ptr(entry), text)
            isTold = false
            gtk_editable_set_position(ptr(entry), -1)
        }
        /// What this field says, for every field and the Search page.
        func take() {
            let typed = String(cString: gtk_editable_get_text(ptr(entry)))
            guard typed != shared.text else { return }
            shared.text = typed
            if entry != shared.home && !typed.isEmpty { MainWindow.showSearch() }
        }
        // Only the field that shows is listened to: the others are being
        // told the text, not typed in.
        on(entry, "search-changed") { if gtk_widget_get_mapped(entry) != 0 && !isTold { take() } }
        // Enter keeps the search among the recent ones, with the text as it
        // is (the typing may not have rested yet); Escape clears it.
        on(entry, "activate") {
            take()
            shared.remember()
        }
        on(entry, "stop-search") { gtk_editable_set_text(ptr(entry), "") }
        // A click in another page's field is a click in the Search page's;
        // the field's own ✕ (its last part) still clears it where it is.
        let click = gtk_gesture_click_new()!
        gtk_event_controller_set_propagation_phase(ptr(click), GTK_PHASE_CAPTURE)
        on(raw(click), "pressed") {
            guard entry != shared.home else { return }
            var x = 0.0, y = 0.0
            gtk_gesture_get_point(ptr(click), gtk_gesture_single_get_current_sequence(ptr(click)), &x, &y)
            if let picked = gtk_widget_pick(entry, x, y, GTK_PICK_DEFAULT), picked == gtk_widget_get_last_child(entry) { return }
            gtk_gesture_set_state(ptr(click), GTK_EVENT_SEQUENCE_CLAIMED)
            // After the click: its page may be the one replaced.
            Task { MainWindow.showSearch() }
        }
        gtk_widget_add_controller(entry, ptr(click))
        return entry
    }

    /// The Search page's field, with the keys and the text's end.
    func focus() {
        guard let home else { return }
        gtk_widget_grab_focus(home)
        gtk_editable_set_position(ptr(home), -1)
    }

    // The recent searches as the iPhone keeps them (SearchView's
    // SearchRecents): one list per user, in UserDefaults, which Linux
    // keeps in its settings file (DefaultsFile).
    private var key: String { "recentSearches." + (app.credentials?.userID ?? "") }

    func loadRecents() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        if saved != recents { recents = saved }
    }

    /// The text, on top: a result opened from it, or Enter. The same
    /// search typed differently ("radiohead", "Radiohead") is kept once.
    func remember() {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        var terms = recents.filter { $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        terms.insert(term, at: 0)
        recents = Array(terms.prefix(8))
        UserDefaults.standard.set(recents, forKey: key)
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Search in the library in memory (LibraryStore.search), following the
/// header's field; the same page as the Mac's and the iPad's. Nothing
/// typed: the recent searches. Typed: artists, albums, playlists and
/// songs, each only when something matches.
enum SearchPage {
    static func make() -> Widget {
        let content = vbox().css("group")
        let column = vbox([pageTitle("Search"), content])
        // Counted once a search, when the typing first rests (docs/STATS.md);
        // a field emptied is the next search.
        var isCounted = false
        var counting: Task<Void, Never>?
        observe(content) {
            let term = SearchField.shared.text.trimmingCharacters(in: .whitespaces)
            clear(content)
            defer { measure(column) }
            counting?.cancel()
            guard !term.isEmpty else {
                isCounted = false
                recents(in: content)
                return
            }
            // Not the recents here: keeping one would make the results
            // again under the click that kept it.
            let found = app.library.search(term, limit: 20)
            let count = found.artists.count + found.albums.count + found.tracks.count + found.playlists.count
            if !isCounted {
                counting = Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    isCounted = true
                    Stats.track(.searchUsed, ["results": Stats.resultCount(count)])
                }
            }
            if found.isEmpty {
                append(emptyLine("Nothing found for “\(term)”."), to: content)
                return
            }
            // A result opened keeps the search among the recent ones.
            func remembering(_ tile: Widget) -> Widget {
                on(tile, "clicked") { SearchField.shared.remember() }
                return tile
            }
            if !found.artists.isEmpty {
                append(sectionTitle("Artists"), to: content)
                append(shelf(found.artists.map { remembering(LibraryPages.artistTile($0, round: true)) }), to: content)
            }
            if !found.albums.isEmpty {
                append(sectionTitle("Albums"), to: content)
                append(shelf(found.albums.map { remembering(albumTile($0)) }), to: content)
            }
            if !found.playlists.isEmpty {
                append(sectionTitle("Playlists"), to: content)
                append(shelf(found.playlists.map { remembering(LibraryPages.playlistTile($0)) }), to: content)
            }
            if !found.tracks.isEmpty {
                append(sectionTitle("Songs", below: 8), to: content)
                let list = trackList(Array(found.tracks.prefix(20)), context: { QueueContext(.search, title: "Search") },
                                     subtitle: { [$0.artistLine, $0.albumName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") })
                on(list.widget, "activate") { SearchField.shared.remember() }
                append(list.widget, to: content)
            }
        }
        return pageColumn(column)
    }

    /// The recent searches, newest first, each a plain row that searches
    /// it again; Clear at their heading's end. None yet: what to search.
    private static func recents(in content: Widget) {
        let recents = SearchField.shared.recents
        guard !recents.isEmpty else {
            append(emptyLine("Search your artists, albums, songs and playlists."), to: content)
            return
        }
        let heading = sectionTitle("Recent searches", below: 8)
        let clear = button("Clear", "flat", "plain", "t15", "fact") { SearchField.shared.clearRecents() }
        append(clear.expand(horizontal: true).align(horizontal: GTK_ALIGN_END, vertical: GTK_ALIGN_CENTER), to: heading)
        append(heading, to: content)
        for term in recents {
            let row = gtk_button_new()!.css("flat", "recent")
            gtk_button_set_child(ptr(row), label(term, "t15"))
            on(row, "clicked") {
                SearchField.shared.text = term
                SearchField.shared.focus()
            }
            append(row, to: content)
        }
    }
}

// MARK: - The library

enum LibraryPages {
    /// Every album, as a grid of covers that makes only the ones on screen.
    static func albums() -> Widget {
        let grid = ItemList<Album, Tile>(
            grid: true,
            make: {
                let tile = Tile()
                return (tile.widget, tile)
            },
            fill: { tile, album, _ in tile.show(album.artwork, album.name, album.artistLine) },
            activate: { album, _, _ in Pages.open(album) })
        let sorts: [(String, LibraryAlbumSort)] = [("Title", .title), ("Artist", .artist), ("Year", .year), ("Recently Added", .recentlyAdded)]
        var sort = LibraryAlbumSort.artist
        let names = sorts.map { $0.0 }
        let choice = dropDown(names, selected: 1) { index in
            sort = sorts[index].1
            grid.set(app.library.albums(sortedBy: sort))
        }
        let top = hbox(spacing: 12, [pageTitle("Albums").expand(horizontal: true), choice.align(vertical: GTK_ALIGN_END)])
        observe(grid.widget) {
            let albums = app.library.albums(sortedBy: sort)
            if albums != grid.items { grid.set(albums) }
        }
        return listPage(top, grid.widget, grid: true)
    }

    static func artists() -> Widget {
        let grid = ItemList<Artist, Tile>(
            grid: true,
            make: {
                let tile = Tile()
                return (tile.widget, tile)
            },
            fill: { tile, artist, _ in
                tile.show(artist.artwork, artist.name, artist.albumCount.map { $0 == 1 ? "1 album" : "\($0) albums" } ?? "")
            },
            activate: { artist, _, _ in Pages.open(artist) })
        observe(grid.widget) {
            let artists = app.library.artistsByName
            if artists != grid.items { grid.set(artists) }
        }
        return listPage(pageTitle("Artists"), grid.widget, grid: true)
    }

    static func songs() -> Widget {
        let list = trackList([], context: { QueueContext(.songs, title: "Songs") })
        let fact = label("", "t13", "fact")
        observe(list.widget) {
            let songs = app.library.songsByTitle
            if songs.map(\.id) != list.items.map(\.id) { list.set(songs) }
            setText(fact, songs.count == 1 ? "1 song" : "\(songs.count) songs")
        }
        let shuffle = wordButton("Shuffle") {
            app.player.play(app.library.songsByTitle, context: QueueContext(.songs, title: "Songs"), shuffled: true)
        }
        let top = vbox(spacing: 4, [pageTitle("Songs"), fact, shuffle])
        return listPage(top, list.widget, grid: false)
    }

    static func playlists() -> Widget {
        let tiles = vbox().css("group")
        let column = vbox([pageTitle("Playlists"), tiles])
        observe(tiles) {
            clear(tiles)
            defer { measure(column) }
            let playlists = app.library.playlists
            if playlists.isEmpty {
                append(emptyLine("Make a playlist on your \(app.library.serverKind) server and it appears here."), to: tiles)
            } else {
                let flow = flow(playlists.map(playlistTile))
                gtk_widget_set_margin_top(flow, 24)
                append(flow, to: tiles)
            }
        }
        return pageColumn(column)
    }

    static func favorites() -> Widget {
        let content = vbox().css("group")
        let column = vbox([pageTitle("Favorites"), content])
        observe(content) {
            clear(content)
            defer { measure(column) }
            let library = app.library
            let artists = library.favoriteArtists, albums = library.favoriteAlbums, tracks = library.favoriteTracks
            if artists.isEmpty && albums.isEmpty && tracks.isEmpty {
                append(emptyLine("Mark a song, album or artist with ♡ and it appears here."), to: content)
                return
            }
            if !artists.isEmpty {
                append(sectionTitle("Artists"), to: content)
                append(shelf(artists.map { artistTile($0) }), to: content)
            }
            if !albums.isEmpty {
                append(sectionTitle("Albums"), to: content)
                append(shelf(albums.map { albumTile($0) }), to: content)
            }
            if !tracks.isEmpty {
                append(sectionTitle("Songs"), to: content)
                append(trackList(tracks, context: { QueueContext(.favorites, title: "Favorites") }).widget, to: content)
            }
        }
        return pageColumn(column)
    }

    /// Every album, the newest first, as the Mac's Recently Added: the
    /// page's tiles, as Albums.
    static func recentlyAdded() -> Widget {
        let grid = ItemList<Album, Tile>(
            grid: true,
            make: {
                let tile = Tile()
                return (tile.widget, tile)
            },
            fill: { tile, album, _ in tile.show(album.artwork, album.name, album.artistLine) },
            activate: { album, _, _ in Pages.open(album) })
        let empty = emptyLine("")
        observe(grid.widget) {
            let albums = app.library.recentlyAddedAlbums
            if albums != grid.items { grid.set(albums) }
            setText(empty, "Albums added to your \(app.library.serverKind) server appear here.")
            empty.isVisible = albums.isEmpty && !app.library.tracks.isEmpty
        }
        return listPage(vbox([pageTitle("Recently Added"), empty]), grid.widget, grid: true)
    }

    /// Every genre in the library's tags, as the Mac's Genres (GenresView):
    /// tiles, each the covers of the genre's first four albums, the songs
    /// the library has in it under its name. A tag that joins several
    /// ("Rock; Shoegaze") is each of them, as the radio counts them.
    static func genres() -> Widget {
        let grid = ItemList<Genre, Tile>(
            grid: true,
            make: {
                let tile = Tile(emptyIcon: Glyphs.name("genres"))
                return (tile.widget, tile)
            },
            fill: { tile, genre, _ in
                tile.show(collage: genreCovers(genre), genre.name, LibraryText.songs(songCount(of: genre)))
            },
            activate: { genre, _, _ in Pages.open(genre) })
        let empty = emptyLine("The genres in your music’s tags appear here.")
        observe(grid.widget) {
            let genres = app.library.genres
            if genres != grid.items { grid.set(genres) }
            empty.isVisible = genres.isEmpty && !app.library.tracks.isEmpty
        }
        return listPage(vbox([pageTitle("Genres"), empty]), grid.widget, grid: true)
    }

    /// The covers of a genre's first four albums: its tile's and its page's
    /// art (the Mac's LibraryGenreArt).
    static func genreCovers(_ genre: Genre) -> [Artwork] {
        Array(app.library.albums(inGenre: genre).lazy.compactMap(\.artwork).prefix(4))
    }

    /// The library's own songs in the genre, else the server's count.
    private static func songCount(of genre: Genre) -> Int {
        let own = app.library.trackCount(inGenre: genre)
        return own > 0 ? own : (genre.songCount ?? 0)
    }

    static func artistTile(_ artist: Artist, round: Bool = false) -> Widget {
        let tile = Tile(round: round)
        tile.show(artist.artwork, artist.name, "")
        let button = tileButton(tile.widget) { Pages.open(artist) }
        contextMenu(on: button) {
            [("Start Radio", { app.radio.start(.artist(key: artist.key, name: artist.name, id: artist.id)) })]
        }
        return button
    }

    static func playlistTile(_ playlist: Playlist) -> Widget {
        let tile = Tile()
        tile.show(playlist.artwork, playlist.name, playlist.trackCount.map { $0 == 1 ? "1 song" : "\($0) songs" } ?? "")
        return tileButton(tile.widget) { Pages.open(playlist) }
    }

    /// A long list under a heading: the heading stays, the list scrolls
    /// (it makes only the rows on screen, so it must be the scroller's own).
    /// A grid's tiles carry their 24 of gap at their end. The heading on the
    /// page's margin and no other: `margins(horizontal:)` set its top to 0
    /// as well, and Artists' title (pageTitle alone, not in a row) sat 24
    /// higher than every other page's — "artists heeft opeens een andere
    /// pagina container als de andere?" (14 November 2026).
    /// A grid's tiles light 8 past their art inside their cells (Style's
    /// `.grid-tile`), so the grid starts 8 sooner, left and top, and its
    /// cells' 16 past the art end in the margin at the right.
    private static func listPage(_ heading: Widget, _ list: Widget, grid: Bool) -> Widget {
        let scroller = scrolled(list).expand(vertical: true)
        gtk_widget_set_margin_top(scroller, grid ? 16 : 24)
        let column = vbox([heading, scroller])
        observe(column) {
            let margin = PageMeasure.shared.margin
            gtk_widget_set_margin_start(heading, margin)
            gtk_widget_set_margin_end(heading, margin)
            gtk_widget_set_margin_start(list, grid ? margin - 8 : margin)
            gtk_widget_set_margin_end(list, grid ? margin - 16 : margin)
        }
        return column
    }

    /// Tiles that wrap to the window's width.
    static func flow(_ tiles: [Widget]) -> Widget {
        let box = gtk_flow_box_new()!
        gtk_flow_box_set_column_spacing(ptr(box), 24)
        gtk_flow_box_set_row_spacing(ptr(box), 24)
        gtk_flow_box_set_selection_mode(ptr(box), GTK_SELECTION_NONE)
        gtk_flow_box_set_max_children_per_line(ptr(box), 12)
        gtk_flow_box_set_homogeneous(ptr(box), 0)
        gtk_widget_set_valign(box, GTK_ALIGN_START)
        for tile in tiles {
            gtk_flow_box_append(ptr(box), tile)
            // The tile is the button: its wrapper need not take the keys too.
            if let child = gtk_widget_get_parent(tile) { gtk_widget_set_focusable(child, 0) }
        }
        return box
    }

    private static func dropDown(_ names: [String], selected: Int, _ chosen: @escaping (Int) -> Void) -> Widget {
        var strings: [UnsafePointer<CChar>?] = names.map { UnsafePointer(strdup($0)) }
        strings.append(nil)
        let drop = gtk_drop_down_new_from_strings(strings)!
        for string in strings { free(UnsafeMutablePointer(mutating: string)) }
        gtk_drop_down_set_selected(ptr(drop), guint(selected))
        on(drop, "notify::selected") { chosen(Int(gtk_drop_down_get_selected(ptr(drop)))) }
        return drop.tooltip("Sort albums by")
    }
}

// MARK: - One album, artist, playlist, mix or station

enum Pages {
    /// The top of such a page (spec §5, Album): the cover, 32, and at its
    /// foot the title in the serif 40/48, the artist 17/24, the facts, and
    /// 24 under them the one Play and the rest.
    private static func heading(art: Widget, title: String, lead: String? = nil, facts: Widget, actions: [Widget]) -> Widget {
        let words = vbox(spacing: 0, [label(title, "serif", "page-title", lines: 3)])
        if let lead, !lead.isEmpty {
            let line = label(lead, "t17")
            gtk_widget_set_margin_top(line, 4)
            append(line, to: words)
        }
        gtk_widget_set_margin_top(facts, 4)
        append(facts, to: words)
        let buttons = hbox(spacing: 16, actions)
        gtk_widget_set_margin_top(buttons, 24)
        append(buttons, to: words)
        let top = hbox(spacing: 32, [art, words.expand(horizontal: true).align(vertical: GTK_ALIGN_END)])
        gtk_widget_set_margin_top(top, 24)
        return top
    }

    private static func facts(_ parts: [String?]) -> Widget {
        label(parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), "t13", "fact", lines: 2)
    }

    /// The cover follows the page: 224, 160 under 720.
    private static func cover() -> Art {
        let art = Art(PageMeasure.shared.cover)
        observe(art.widget) { art.resize(PageMeasure.shared.cover) }
        return art
    }

    /// The hairline 32 under the heading, 24 over the rows.
    private static func rule() -> Widget {
        let line = hairline()
        gtk_widget_set_margin_top(line, 32)
        gtk_widget_set_margin_bottom(line, 24)
        return line
    }

    static func open(_ album: Album) {
        let tracks = app.library.tracks(inAlbum: album.id)
        let context = QueueContext(.album(album.id), title: album.name)
        let art = cover()
        art.show(album.artwork)
        let artist = album.primaryArtist.flatMap { app.library.artist($0) }
        var more: [(String, () -> Void)] = [("Start a Station", { app.radio.start(.album(album.id)) }),
                                             ("Play Next", { app.player.playNext(tracks) }),
                                             ("Add to Queue", { app.player.addToQueue(tracks) })]
        if let artist { more.append(("Go to Artist", { open(artist) })) }
        let top = heading(art: art.widget, title: album.name, lead: album.artistLine,
                          facts: facts([album.year.map(String.init), album.genres.first,
                                        length(songs: tracks.count, seconds: tracks.reduce(0) { $0 + $1.duration })]),
                          actions: [
            playButton { app.player.play(tracks, context: context) },
            wordButton("Shuffle") { app.player.play(tracks, context: context, shuffled: true) },
            hbox(spacing: 8, [heartButton { .album(album.id) }, moreButton(more)]),
        ])
        keep(art, on: raw(top), as: "art")
        // On an album every song is the album artist's unless it says so.
        let list = trackList(tracks, numbered: true, context: { context },
                             subtitle: { guests($0, besides: album.artistLine) })
        let column = vbox([top, rule(), list.widget])
        if let artist {
            let others = app.library.albums(by: artist).filter { $0.id != album.id }
            if !others.isEmpty {
                append(sectionTitle("More by \(artist.name)"), to: column)
                append(shelf(others.map { albumTile($0, fact: $0.year.map(String.init) ?? "") }), to: column)
            }
        }
        Stats.track(.screen, ["name": "album"])
        // At the header's end, where the Mac's bar has it.
        let download = downloadControl(.album(album.id), name: album.name) { OfflineCollection(album: album, tracks: tracks) }
        Nav.push(album.name, pageColumn(column), end: [download])
    }

    static func open(_ artist: Artist) {
        let seed = StationSeed.artist(key: artist.key, name: artist.name, id: artist.id)
        let all = app.library.tracks(by: artist)
        let context = QueueContext(.artist(artist.id), title: artist.name)
        let art = cover()
        art.show(artist.artwork)
        let albums = app.library.albums(by: artist)
        let top = heading(art: art.widget, title: artist.name,
                          facts: facts([albums.isEmpty ? nil : albums.count == 1 ? "1 album" : "\(albums.count) albums",
                                        length(songs: all.count, seconds: 0)]),
                          actions: [
            playButton { app.player.play(all, context: context, shuffled: true) },
            hbox(spacing: 8, [heartButton { .artist(artist.id) }, moreButton([("Start a Station", { app.radio.start(seed) })])]),
        ])
        keep(art, on: raw(top), as: "art")
        let column = vbox([top])
        let topSongs = app.library.topTracks(by: artist, limit: 5)
        if !topSongs.isEmpty {
            // Until something was played they are only the newest album's.
            append(sectionTitle(app.library.hasPlaysOrFavorites(by: artist) ? "Top songs" : "Songs", below: 8), to: column)
            append(trackList(topSongs, context: { context }, subtitle: { $0.albumName ?? "" }).widget, to: column)
        }
        if !albums.isEmpty {
            append(sectionTitle("Albums"), to: column)
            append(shelf(albums.map { albumTile($0, fact: $0.year.map(String.init) ?? "") }), to: column)
        }
        let guest = app.library.appearances(of: artist)
        if !guest.isEmpty {
            append(sectionTitle("Appears on"), to: column)
            append(shelf(guest.map { albumTile($0) }), to: column)
        }
        Stats.track(.screen, ["name": "artist"])
        Nav.push(artist.name, pageColumn(column))
    }

    /// A playlist, pushed; or as a place of its own, chosen in the sidebar,
    /// with the sidebar's button at its start.
    static func open(_ playlist: Playlist, place start: [Widget]? = nil) {
        let context = QueueContext(.playlist(playlist.id), title: playlist.name)
        let art = cover()
        art.show(playlist.artwork)
        let fact = facts([])
        let list = trackList([], context: { context })
        let top = heading(art: art.widget, title: playlist.name, facts: fact, actions: [
            playButton { app.player.play(list.items, context: context) },
            wordButton("Shuffle") { app.player.play(list.items, context: context, shuffled: true) },
        ])
        keep(art, on: raw(top), as: "art")
        let column = vbox([top, rule(), list.widget])
        func show(_ tracks: [Track]) {
            list.set(tracks)
            // Without an image of its own, the covers of its first
            // albums, as on the iPhone.
            if playlist.artwork == nil { art.show(collage: firstCovers(tracks)) }
            setText(fact, length(songs: tracks.count, seconds: tracks.reduce(0) { $0 + $1.duration }))
        }
        // A playlist's songs are the server's to say: it changes elsewhere
        // too. Offline, or the server away, the songs it was downloaded with.
        Task {
            let saved = app.offline.collection(for: .playlist(playlist.id))?.tracks
            if app.offline.isOffline, let saved {
                show(saved)
                return
            }
            do {
                let tracks = try await app.library.tracks(in: playlist)
                show(tracks)
                // Downloaded: what came in or went out on the server follows.
                let shown = app.library.playlists.first { $0.id == playlist.id } ?? playlist
                app.offline.playlistLoaded(shown, tracks: tracks)
            } catch {
                if let saved { show(saved) } else { setText(fact, error.localizedDescription) }
            }
        }
        Stats.track(.screen, ["name": "playlist"])
        let download = downloadControl(.playlist(playlist.id), name: playlist.name) {
            OfflineCollection(playlist: app.library.playlists.first { $0.id == playlist.id } ?? playlist, tracks: list.items)
        }
        if let start {
            Nav.show(Nav.page(playlist.name, pageColumn(column), start: start, end: [download]))
        } else {
            Nav.push(playlist.name, pageColumn(column), end: [download])
        }
    }

    /// A genre's page, as the Mac's (GenreDetailView): its collage as the
    /// head's cover, how many songs and how long, Play, Shuffle and ⋮ with
    /// Start Radio; then its albums in tiles. Only the library is read: a
    /// genre the server has no item of that name for has an id of the
    /// app's own.
    static func open(_ genre: Genre) {
        let tracks = app.library.tracks(inGenre: genre)
        let albums = app.library.albums(inGenre: genre)
        let context = QueueContext(.genre(genre.name), title: genre.name)
        let art = cover()
        art.emptyIcon = Glyphs.name("genres")
        art.show(collage: LibraryPages.genreCovers(genre))
        let seed = StationSeed.genre(key: genre.key, name: genre.name)
        let actions = [
            playButton { app.player.play(tracks, context: context) },
            wordButton("Shuffle") { app.player.play(tracks, context: context, shuffled: true) },
            moreButton([("Start Radio", {
                Stats.track(.stationStarted, ["seed": Stats.seed(seed), "from": "menu"])
                app.radio.start(seed)
            })]),
        ]
        for action in actions where tracks.isEmpty { gtk_widget_set_sensitive(action, 0) }
        let top = heading(art: art.widget, title: genre.name,
                          facts: facts([tracks.isEmpty ? "No songs in the library carry this genre."
                                                       : length(songs: tracks.count, seconds: tracks.reduce(0) { $0 + $1.duration })]),
                          actions: actions)
        keep(art, on: raw(top), as: "art")
        let column = vbox([top])
        if !albums.isEmpty {
            append(sectionTitle("Albums"), to: column)
            append(LibraryPages.flow(albums.map { albumTile($0) }), to: column)
        }
        Stats.track(.screen, ["name": "genre"])
        Nav.push(genre.name, pageColumn(column))
    }

    /// The covers of the first four albums among `tracks`: a playlist's
    /// collage when it has no image of its own.
    static func firstCovers(_ tracks: [Track]) -> [Artwork] {
        var covers: [Artwork] = []
        for cover in tracks.compactMap(\.artwork) where !covers.contains(cover) && covers.count < 4 {
            covers.append(cover)
        }
        return covers
    }

    static func open(_ mix: Mix) {
        let context = QueueContext(.mix(mix.id), title: mix.title)
        let art = cover()
        art.show(collage: mix.artwork)
        let top = heading(art: art.widget, title: mix.title, lead: mix.subtitle,
                          facts: facts([length(songs: mix.tracks.count, seconds: mix.duration)]), actions: [
            playButton {
                Stats.track(.mixPlayed)
                app.player.play(mix.tracks, context: context)
            },
            wordButton("Shuffle") { app.player.play(mix.tracks, context: context, shuffled: true) },
            moreButton([("Start a Station", { app.radio.start(mix.stationSeed) })]),
        ])
        keep(art, on: raw(top), as: "art")
        let list = trackList(mix.tracks, context: { context })
        let column = vbox([top, rule(), list.widget])
        Stats.track(.mixOpened)
        Nav.push(mix.title, pageColumn(column), end: [downloadControl(.mix(mix.id), name: mix.title) { OfflineCollection(mix: mix) }])
    }

    /// A station's page: what it would play, before it plays. Play plays
    /// the list shown (RadioController keeps the session that chose it);
    /// New Picks draws another.
    static func open(_ station: Station) {
        let art = StationArt(224)
        art.show(station)
        var picks: [RadioPick] = []
        let list = ItemList<RadioPick, TrackRow>(
            make: {
                let row = TrackRow()
                return (row.widget, row)
            },
            fill: { row, pick, _ in row.show(pick.track) },
            activate: { _, index, items in app.radio.start(station, preview: items, from: index) })
        list.widget.css("rows")
        let fact = facts([station.subtitle, "Choosing songs…"])
        func choose(_ seed: UInt64) {
            Task {
                let chosen = await app.radio.preview(station, randomSeed: seed)
                picks = chosen
                list.set(chosen)
                setText(fact, [station.subtitle, chosen.isEmpty ? "Nothing in your library for this station yet." : "Starts with these, then plays on."]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
        let top = heading(art: art.widget, title: station.title, facts: fact, actions: [
            playButton { app.radio.start(station, preview: picks) },
            wordButton("New Picks") { choose(app.radio.drawPageSeed(for: station)) },
        ])
        keep(art, on: raw(top), as: "art")
        let column = vbox([top, rule(), list.widget])
        // The library, the graph or the dial moved: the list shown would no
        // longer be the one played, so it is chosen again, by the same draw.
        observe(column) {
            _ = app.radio.previewInputs
            choose(app.radio.pageSeed(for: station))
        }
        Stats.track(.stationPage, ["seed": Stats.seed(station.seed)])
        Nav.push(station.title, pageColumn(column))
    }
}
