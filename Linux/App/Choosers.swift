// What the Mac and the iPad ask in a sheet, asked in GNOME's dialogs: Start
// a Station (RadioStationPicker), Add to Playlist… (AddToPlaylistSheet), Add
// Songs (AddSongsSheet), a playlist's name and Delete Playlist. "Linux
// erbij" (the photographer, 15 November 2026): what one side has, the other
// gets. The choosing is the shared stores' (LibraryStore's playlists and
// search, the radio's stations), the same as there.

import CAdw
import Foundation
import JukeboxKit
import Observation

// MARK: - A dialog of rows

/// One line of a chooser: a heading, or something to choose.
struct Pick {
    enum Look {
        case cover(Artwork?, empty: String = "folder-music-symbolic")
        case round(Artwork?)
        case station(Station)
        case glyph(String)
    }

    var heading: String?
    var title = ""
    var subtitle = ""
    var look = Look.glyph("folder-music-symbolic")
    /// The glyph at the line's end and its class ("accent", "fact"), read
    /// again whenever what it reads changes: Add Songs' + becoming a tick.
    var mark: () -> (icon: String, style: String)? = { nil }
    var run: () -> Void = {}

    static func heading(_ text: String) -> Pick { Pick(heading: text) }
}

/// A chooser's line: the picture 40 with the one radius (round for an
/// artist, the arch for a station), 12, the name over a fact, the mark at
/// the end; a heading in the serif, 16 over its rows.
final class PickRow {
    let widget: Widget
    private let heading = label("", "serif", "t17")
    private let art = Art(40)
    private let station = StationArt(40)
    private let title = label("", "t15")
    private let subtitle = label("", "t13", "fact")
    private let mark = gtk_image_new()!
    private let line: Widget
    /// What the row shows, watched with what its mark reads: a row given
    /// another pick, or its pick's song added, shows the mark anew.
    private let bound = Bound()

    @Observable
    final class Bound {
        var pick: Pick?
    }

    init() {
        let words = vbox(spacing: 0, [title, subtitle]).expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER)
        line = hbox(spacing: 12, [art.widget, station.widget, words, mark.align(vertical: GTK_ALIGN_CENTER)])
        gtk_widget_set_margin_top(heading, 16)
        gtk_widget_set_margin_bottom(heading, 4)
        widget = vbox([heading, line])
        keep(art, on: raw(widget), as: "art")
        observe(widget) { [weak self] in self?.showMark() }
    }

    func show(_ pick: Pick) {
        bound.pick = pick
        heading.isVisible = pick.heading != nil
        line.isVisible = pick.heading == nil
        if let text = pick.heading {
            setText(heading, text)
            return
        }
        setText(title, pick.title)
        setText(subtitle, pick.subtitle)
        subtitle.isVisible = !pick.subtitle.isEmpty
        art.widget.isVisible = true
        station.widget.isVisible = false
        gtk_widget_remove_css_class(art.widget, "round")
        switch pick.look {
        case let .cover(artwork, empty):
            art.emptyIcon = empty
            art.show(artwork)
        case let .round(artwork):
            art.widget.css("round")
            art.emptyIcon = "avatar-default-symbolic"
            art.show(artwork)
        case let .station(chosen):
            art.widget.isVisible = false
            station.widget.isVisible = true
            station.show(chosen)
        case let .glyph(icon):
            art.emptyIcon = icon
            art.show(nil)
        }
        showMark()
    }

    private func showMark() {
        let shown = bound.pick?.mark()
        mark.isVisible = shown != nil
        guard let shown else { return }
        gtk_image_set_from_icon_name(ptr(mark), shown.icon)
        for style in ["accent", "fact"] where style != shown.style { gtk_widget_remove_css_class(mark, style) }
        mark.css(shown.style)
    }
}

/// A dialog to choose from, as the Mac's sheets: its title in the header,
/// with GNOME's own close; the search field under it when it has one; the
/// rows (a list that makes only the ones on screen: Add Songs lists the
/// whole library); 480 by 560, the Mac's sheet.
final class Chooser {
    let dialog: Widget
    let list: ItemList<Pick, PickRow>
    private(set) var field: Widget?
    private let empty = emptyLine("")
    /// The search field's words, trimmed, whenever they change.
    var searched: ((String) -> Void)?

    init(_ title: String, search placeholder: String? = nil) {
        dialog = ptr(adw_dialog_new()!)
        adw_dialog_set_title(ptr(dialog), title)
        adw_dialog_set_content_width(ptr(dialog), 480)
        adw_dialog_set_content_height(ptr(dialog), 560)
        list = ItemList<Pick, PickRow>(
            make: {
                let row = PickRow()
                return (row.widget, row)
            },
            fill: { row, pick, _ in row.show(pick) },
            activate: { pick, _, _ in pick.run() })
        list.activatable = { $0.heading == nil }
        list.widget.css("picks")
        let toolbar = adw_toolbar_view_new()!
        adw_toolbar_view_add_top_bar(ptr(toolbar), adw_header_bar_new())
        if let placeholder {
            let entry = gtk_search_entry_new()!
            gtk_search_entry_set_placeholder_text(ptr(entry), placeholder)
            // Typing anywhere in the dialog types here.
            gtk_search_entry_set_key_capture_widget(ptr(entry), dialog)
            on(entry, "search-changed") { [weak self] in
                self?.searched?(String(cString: gtk_editable_get_text(ptr(entry))).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let bar = entry.expand(horizontal: true).margins(horizontal: 16)
            gtk_widget_set_margin_bottom(bar, 8)
            adw_toolbar_view_add_top_bar(ptr(toolbar), bar)
            field = entry
        }
        empty.isVisible = false
        empty.margins(horizontal: 16)
        gtk_widget_set_margin_top(empty, 16)
        adw_toolbar_view_set_content(ptr(toolbar), vbox([empty, scrolled(list.widget).expand(vertical: true)]))
        adw_dialog_set_child(ptr(dialog), toolbar)
        // The chooser lives as long as its dialog.
        keep(self, on: raw(dialog), as: "chooser")
    }

    /// One plain line where the rows would be: nothing found.
    func say(_ text: String?) {
        setText(empty, text ?? "")
        empty.isVisible = text != nil
    }

    func present() {
        adw_dialog_present(ptr(dialog), MainWindow.window)
        if let field { gtk_widget_grab_focus(field) }
    }

    func close() { adw_dialog_close(ptr(dialog)) }
}

// MARK: - Start a Station

/// Radio's +: any artist, song, album or genre in the library as a
/// station's seed, found as one types (the library is in memory); before
/// anything is typed, the stations Jukebox suggests and every genre. The
/// one chosen opens its page, to see what it would play before it plays,
/// as from every station's tile.
enum StationPicker {
    static func present() {
        let chooser = Chooser("Start a Station", search: "Artists, Songs, Albums, Genres")
        let dialog = chooser.dialog
        func show(_ station: Station) {
            adw_dialog_close(ptr(dialog))
            Pages.open(station)
        }
        func seed(_ seed: StationSeed) { show(app.radio.station(for: seed)) }
        let guitar = Glyphs.name("genres")
        let radio: () -> (icon: String, style: String)? = { (Glyphs.name("radio"), "fact") }
        func genres(_ list: [Genre]) -> [Pick] {
            list.map { genre in
                Pick(title: genre.name, look: .glyph(guitar), mark: radio, run: { seed(.genre(key: genre.key, name: genre.name)) })
            }
        }
        chooser.searched = { [weak chooser] term in
            guard let chooser else { return }
            var picks: [Pick] = []
            if term.isEmpty {
                // Your Station, Discovery and Loved are on Radio itself.
                let suggested = app.mixes.stations.filter {
                    switch $0.seed {
                    case .personal, .discovery, .favorites: false
                    default: true
                    }
                }.prefix(12)
                if !suggested.isEmpty {
                    picks.append(.heading("Suggested"))
                    picks += suggested.map { station in
                        Pick(title: station.title, subtitle: station.subtitle ?? "", look: .station(station), mark: radio, run: { show(station) })
                    }
                }
                if !app.library.genres.isEmpty {
                    picks.append(.heading("Genres"))
                    picks += genres(app.library.genres)
                }
            } else {
                let found = app.library.search(term, limit: 6)
                // The library's search has no genres; a plain match is
                // enough for a few hundred.
                let matching = app.library.genres.filter { $0.name.localizedStandardContains(term) }.prefix(6)
                if !found.artists.isEmpty {
                    picks.append(.heading("Artists"))
                    picks += found.artists.map { artist in
                        Pick(title: artist.name, look: .round(artist.artwork), mark: radio, run: {
                            seed(.artist(key: artist.key, name: artist.name, id: artist.id))
                        })
                    }
                }
                if !found.tracks.isEmpty {
                    picks.append(.heading("Songs"))
                    picks += found.tracks.map { track in
                        Pick(title: track.name, subtitle: track.artistLine, look: .cover(track.artwork), mark: radio, run: { seed(.track(track.id)) })
                    }
                }
                if !found.albums.isEmpty {
                    picks.append(.heading("Albums"))
                    picks += found.albums.map { album in
                        Pick(title: album.name, subtitle: album.artistLine, look: .cover(album.artwork), mark: radio, run: { seed(.album(album.id)) })
                    }
                }
                if !matching.isEmpty {
                    picks.append(.heading("Genres"))
                    picks += genres(Array(matching))
                }
            }
            chooser.list.set(picks)
            chooser.say(!term.isEmpty && picks.isEmpty ? "Nothing found for “\(term)”." : nil)
        }
        chooser.searched?("")
        chooser.present()
    }
}

// MARK: - Playlists

enum Playlists {
    /// "Add to Playlist…" from any menu: a new playlist with these songs, or
    /// one of the listener's own (only those the server lets them change);
    /// a click adds and closes.
    static func add(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        let chooser = Chooser("Add to Playlist")
        // Weak: closed while the server answers, the dialog is gone, and its
        // chooser with it.
        var picks = [Pick(title: "New Playlist…", look: .glyph("list-add-symbolic"), run: { [weak chooser] in
            askName("New Playlist", "It starts with \(LibraryText.songs(tracks.count)).", action: "Create") { typed in
                Task {
                    do {
                        let playlist = try await app.library.createPlaylist(named: typed.isEmpty ? "New Playlist" : typed, with: tracks)
                        Stats.track(.playlistCreated, ["from": "add_to_playlist"])
                        chooser?.close()
                        MainWindow.toast("Added to “\(playlist.name)”")
                    } catch {
                        MainWindow.toast(error.localizedDescription)
                    }
                }
            }
        })]
        let own = app.library.playlists.filter { !$0.isReadOnly }
        if !own.isEmpty {
            picks.append(.heading("Playlists"))
            picks += own.map { playlist in
                Pick(title: playlist.name, subtitle: playlist.trackCount.map(LibraryText.songs) ?? "",
                     look: .cover(playlist.artwork, empty: Glyphs.name("playlists")), run: { [weak chooser] in
                    Task {
                        do {
                            try await app.library.add(tracks, to: playlist)
                            Stats.track(.playlistSongsAdded, ["from": "add_to_playlist"])
                            chooser?.close()
                            MainWindow.toast("Added to “\(playlist.name)”")
                        } catch {
                            MainWindow.toast(error.localizedDescription)
                        }
                    }
                })
            }
        }
        chooser.list.set(picks)
        chooser.present()
    }

    /// Playlists' New Playlist…: named, made on the server, and opened, as
    /// Music does: the next thing is filling it.
    static func create() {
        askName("New Playlist", "Then add songs with Add Songs on its page, or from any song’s or album’s menu.", action: "Create") { typed in
            Task {
                do {
                    let playlist = try await app.library.createPlaylist(named: typed.isEmpty ? "New Playlist" : typed, with: [])
                    Stats.track(.playlistCreated, ["from": "library"])
                    Pages.open(playlist)
                } catch {
                    MainWindow.toast(error.localizedDescription)
                }
            }
        }
    }

    /// Delete Playlist, asked first: it goes from the server, for every app.
    static func delete(_ playlist: Playlist, then done: @escaping () -> Void = {}) {
        let dialog = adw_alert_dialog_new("Delete “\(playlist.name)”?",
                                          "It is deleted from your \(app.library.serverKind) server, for every app. Its songs stay in your library.")!
        adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
        adw_alert_dialog_add_response(ptr(dialog), "delete", "Delete Playlist")
        adw_alert_dialog_set_response_appearance(ptr(dialog), "delete", ADW_RESPONSE_DESTRUCTIVE)
        adw_alert_dialog_set_default_response(ptr(dialog), "cancel")
        adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
        on(raw(dialog), "response", argument: { response in
            guard let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "delete" else { return }
            Task {
                do {
                    try await app.library.delete(playlist)
                    done()
                } catch {
                    MainWindow.toast(error.localizedDescription)
                }
            }
        })
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    /// Add Songs, from a playlist's page: the library's songs by title, or
    /// what the search finds; a click adds the song at the end and turns its
    /// + into a tick. The songs it has are ticked from the start: Jellyfin
    /// keeps a song added twice. `closed`: the page reads its songs again.
    static func addSongs(to playlist: Playlist, has: Set<ItemID>, closed: @escaping () -> Void) {
        let chooser = Chooser("Add Songs", search: "Find in Songs")
        let state = AddedSongs(has)
        on(chooser.dialog, "closed") { closed() }
        func mark(_ track: Track) -> () -> (icon: String, style: String)? {
            {
                if state.added.contains(track.id) { return ("object-select-symbolic", "accent") }
                return ("list-add-symbolic", state.adding.contains(track.id) ? "fact" : "accent")
            }
        }
        chooser.searched = { [weak chooser] term in
            guard let chooser else { return }
            let shown = term.isEmpty ? app.library.songsByTitle : app.library.matchingTracks(term)
            chooser.list.set(shown.map { track in
                Pick(title: track.name, subtitle: track.artistLine, look: .cover(track.artwork), mark: mark(track), run: {
                    guard !state.added.contains(track.id), !state.adding.contains(track.id) else { return }
                    state.adding.insert(track.id)
                    Task {
                        do {
                            try await app.library.add([track], to: playlist)
                            state.added.insert(track.id)
                            Stats.track(.playlistSongsAdded, ["from": "add_songs"])
                        } catch {
                            MainWindow.toast(error.localizedDescription)
                        }
                        state.adding.remove(track.id)
                    }
                })
            })
            chooser.say(shown.isEmpty ? (term.isEmpty ? "Songs on your \(app.library.serverKind) server appear here."
                                                      : "Nothing found for “\(term)”.") : nil)
        }
        chooser.searched?("")
        chooser.present()
    }
}

/// Add Songs' songs: the ones the playlist has or was given, and the ones
/// on their way to the server; the rows' marks follow them.
@Observable
private final class AddedSongs {
    var added: Set<ItemID>
    var adding: Set<ItemID> = []
    init(_ added: Set<ItemID>) { self.added = added }
}

/// A name asked for, as the Mac's alert with its field: GNOME's alert with
/// an entry under its words, Enter its `action`. `text`: a name to change
/// if the listener likes (Save as Playlist's).
func askName(_ heading: String, _ body: String, placeholder: String = "Name", text: String = "",
             action: String, _ done: @escaping (String) -> Void) {
    let dialog = adw_alert_dialog_new(heading, body)!
    let entry = gtk_entry_new()!
    gtk_entry_set_placeholder_text(ptr(entry), placeholder)
    gtk_editable_set_text(ptr(entry), text)
    adw_alert_dialog_set_extra_child(ptr(dialog), entry)
    // Enter is `action`, here rather than through the window's default
    // button, which a dialog inside the window does not always have.
    on(entry, "activate") {
        done(String(cString: gtk_editable_get_text(ptr(entry))).trimmingCharacters(in: .whitespacesAndNewlines))
        adw_dialog_close(ptr(dialog))
    }
    adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
    adw_alert_dialog_add_response(ptr(dialog), "done", action)
    adw_alert_dialog_set_response_appearance(ptr(dialog), "done", ADW_RESPONSE_SUGGESTED)
    adw_alert_dialog_set_default_response(ptr(dialog), "done")
    adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
    on(raw(dialog), "response", argument: { response in
        guard let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "done" else { return }
        done(String(cString: gtk_editable_get_text(ptr(entry))).trimmingCharacters(in: .whitespacesAndNewlines))
    })
    adw_dialog_present(ptr(dialog), MainWindow.window)
    gtk_widget_grab_focus(entry)
    gtk_editable_select_region(ptr(entry), 0, -1)
}
