// Songs kept on this computer, on screen: the download control of an
// album's, a playlist's and a mix's page, and Downloaded, as the Mac's
// (OfflineControls.swift, DownloadedView.swift's wide page). The keeping
// itself is the shared OfflineStore's, the same as on the iPhone and the Mac.

import CAdw
import Foundation
import JukeboxKit

/// The download control at the end of a page's header, where the Mac has
/// it in its bar: the arrow to download; while the songs come, a ring in
/// the accent around a stop square, filling; once they are all here, the
/// tick. The ring and the tick are menus with Remove Download, asked first.
/// None where the server does not let this account download, unless it is
/// here already, to remove it.
func downloadControl(_ reason: OfflineReason, name: String, collection: @escaping () -> OfflineCollection) -> Widget {
    let download = iconButton(Glyphs.name("download"), "Download", "flat") {
        let chosen = collection()
        guard !chosen.tracks.isEmpty else { return }
        app.offline.download(chosen)
    }
    let image = gtk_image_new()!
    gtk_image_set_pixel_size(ptr(image), 16)
    let menu = gtk_menu_button_new()!.css("flat")
    gtk_menu_button_set_child(ptr(menu), image)
    let control = hbox([download, menu]).align(vertical: GTK_ALIGN_CENTER)
    // The menu made again only when what it says changes, not with the
    // ring twice a second: an open menu would close under the pointer.
    var said: String?
    var ring: Int?
    observe(control) {
        let offline = app.offline
        control.isVisible = offline.offersDownload(for: reason)
        let state = offline.state(of: reason)
        download.isVisible = state == .notDownloaded
        menu.isVisible = state != .notDownloaded
        switch state {
        case .notDownloaded:
            said = nil
            ring = nil
        case let .downloading(fraction: fraction, waiting: waiting):
            let words = waiting.map(OfflineText.waiting) ?? "Downloading, \(OfflineText.percent(fraction))"
            menu.tooltip(words)
            if said != (waiting.map(OfflineText.waiting) ?? "") {
                said = waiting.map(OfflineText.waiting) ?? ""
                gtk_menu_button_set_popover(ptr(menu), removalMenu(waiting: waiting.map(OfflineText.waiting), name: name, reason: reason))
            }
            // Never quite empty: a ring at nothing reads as no download.
            let percent = Int((min(1, max(0.03, fraction)) * 100).rounded())
            guard percent != ring else { return }
            ring = percent
            // Drawn a moment later: by then the tick may be there.
            showRing(percent, in: image) { ring == percent }
        case .downloaded:
            ring = nil
            menu.tooltip("Downloaded")
            gtk_image_set_from_icon_name(ptr(image), Glyphs.name("downloaded"))
            if said != "downloaded" {
                said = "downloaded"
                gtk_menu_button_set_popover(ptr(menu), removalMenu(waiting: nil, name: name, reason: reason))
            }
        }
    }
    return control
}

/// The ring and the tick's menu: what it waits for, when it waits, and
/// Remove Download.
private func removalMenu(waiting: String?, name: String, reason: OfflineReason) -> Widget {
    let menu = g_menu_new()!
    let actions = g_simple_action_group_new()!
    // An item without an action is shown as words, not as something to click.
    if let waiting { g_menu_append(menu, waiting, "menu.none") }
    let remove = g_simple_action_new("remove", nil)!
    on(raw(remove), "activate") {
        confirmRemoval("Remove “\(name)” from this \(Device.model)?", "Remove Download") { app.offline.remove(reason) }
    }
    g_action_map_add_action(ptr(actions), ptr(remove))
    g_menu_append(menu, "Remove Download", "menu.remove")
    let popover = gtk_popover_menu_new_from_model(ptr(menu))!
    gtk_widget_insert_action_group(popover, "menu", ptr(actions))
    return popover
}

/// How much is here, as the Mac's OfflineProgressRing: a thin ring in the
/// accent on a quiet one, around a stop square, 16 as the icons beside it.
private func showRing(_ percent: Int, in image: Widget, if wanted: @escaping () -> Bool) {
    let dark = adw_style_manager_get_dark(adw_style_manager_get_default()) != 0
    let accent: UInt32 = dark ? 0xFFB54D : 0xA84A17
    let track: UInt32 = dark ? 0xFFFFFF : 0x000000
    let scale = Screen.shared.scale
    Task {
        guard let texture = await drawn("download ring \(percent) \(dark)", width: 16, height: 16, scale: scale, { cr, _ in
            cairo_set_line_width(cr, 1.4)
            Draw.color(cr, track, 0.2)
            cairo_arc(cr, 8, 8, 6.3, 0, 2 * .pi)
            cairo_stroke(cr)
            Draw.color(cr, accent)
            cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
            cairo_arc(cr, 8, 8, 6.3, -.pi / 2, -.pi / 2 + 2 * .pi * Double(percent) / 100)
            cairo_stroke(cr)
            cairo_rectangle(cr, 6, 6, 4, 4)
            cairo_fill(cr)
        }), wanted() else { return }
        gtk_image_set_from_paintable(ptr(image), texture.pointer)
    }
}

/// Asked before a download goes, as GNOME asks before what a click cannot
/// take back: what goes, and what stays.
func confirmRemoval(_ heading: String, _ action: String, _ remove: @escaping @MainActor () -> Void) {
    let dialog = adw_alert_dialog_new(heading, "It still plays from your server. Songs another download holds stay.")!
    adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
    adw_alert_dialog_add_response(ptr(dialog), "remove", action)
    adw_alert_dialog_set_response_appearance(ptr(dialog), "remove", ADW_RESPONSE_DESTRUCTIVE)
    adw_alert_dialog_set_default_response(ptr(dialog), "cancel")
    adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
    on(raw(dialog), "response", argument: { response in
        guard let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "remove" else { return }
        remove()
    })
    adw_dialog_present(ptr(dialog), MainWindow.window)
}

/// Downloaded, as the Mac's wide page: the title; Shuffle All, the page's
/// one filled button; the albums, playlists and mixes chosen, newest
/// first, as tiles with their one fact (how far, what they wait for, or
/// their songs and size); then "Songs you play", the ones Keep Songs I Play
/// holds. Nothing here: one plain line of what to do.
enum DownloadedPage {
    /// What the page's top shows, to make it again only when that changes
    /// (the tiles' facts follow the downloads by themselves, the songs'
    /// list its songs).
    private struct Shown: Equatable {
        var collections: [OfflineCollection]
        var hasSongs: Bool
        var hasKept: Bool
    }

    static func make() -> Widget {
        let content = vbox().css("group")
        // The keep's songs, a list of its own: it grows a song at a time
        // while the keep fetches, and the page above stays as it is.
        let songsTitle = sectionTitle("Songs you play", below: 8)
        let songs = trackList([], context: { QueueContext(.other, title: "Downloaded") })
        let column = vbox([pageTitle("Downloaded"), content, songsTitle, songs.widget])
        observe(songs.widget) {
            let kept = keptTracks()
            if kept.map(\.id) != songs.items.map(\.id) { songs.set(kept) }
            songsTitle.isVisible = !kept.isEmpty
            songs.widget.isVisible = !kept.isEmpty
        }
        var shown: Shown?
        observe(content) {
            let offline = app.offline
            let now = Shown(collections: offline.collections, hasSongs: offline.songCount > 0,
                            hasKept: !offline.keptTrackIDs.isEmpty)
            guard now != shown else { return }
            shown = now
            clear(content)
            defer { measure(column) }
            if now.collections.isEmpty && !now.hasKept { append(hint(), to: content) }
            if now.hasSongs {
                let shuffle = playButton("Shuffle All") { shuffleAll() }
                gtk_widget_set_margin_top(shuffle, 24)
                append(shuffle, to: content)
            }
            let kinds: [(String, (OfflineItem) -> Bool)] = [
                ("Albums", { if case .album = $0 { true } else { false } }),
                ("Playlists", { if case .playlist = $0 { true } else { false } }),
                ("Mixes", { if case .mix = $0 { true } else { false } }),
            ]
            for (title, isKind) in kinds {
                let group = now.collections.filter { isKind($0.item) }
                guard !group.isEmpty else { continue }
                append(sectionTitle(title), to: content)
                append(LibraryPages.flow(group.map(tile)), to: content)
            }
        }
        return pageColumn(column)
    }

    /// The Mac's line, its arrow drawn in it.
    private static func hint() -> Widget {
        let arrow = gtk_image_new_from_icon_name(Glyphs.name("download"))!.css("fact")
        let row = hbox(spacing: 4, [label("Download an album, a playlist or a mix with", "fact"), arrow,
                                    label("on its page. Keep Songs I Play, in Preferences, keeps what you play often.", "fact", lines: 0)
                                        .expand(horizontal: true)])
        gtk_widget_set_margin_top(row, 24)
        return row
    }

    /// A download's tile: an album's cover, a playlist's (or its first
    /// song's), a mix's collage; its name, and its fact as it changes.
    private static func tile(_ collection: OfflineCollection) -> Widget {
        let isPlaylist = if case .playlist = collection.item { true } else { false }
        let tile = Tile(emptyIcon: isPlaylist ? Glyphs.name("playlists") : nil)
        observe(tile.widget) {
            let fact = app.offline.fact(of: collection)
            switch collection.item {
            case let .album(album): tile.show(album.artwork, collection.title, fact)
            case let .playlist(playlist): tile.show(playlist.artwork ?? collection.tracks.first?.artwork, collection.title, fact)
            case let .mix(mix): tile.show(collage: mix.artwork, collection.title, fact)
            }
        }
        let button = tileButton(tile.widget) {
            switch collection.item {
            case let .album(album): Pages.open(app.library.album(id: album.id) ?? album)
            case let .playlist(playlist): Pages.open(playlist)
            case let .mix(mix): Pages.open(mix.mix(tracks: collection.tracks))
            }
        }
        contextMenu(on: button) {
            [("Remove Download", {
                confirmRemoval("Remove from this \(Device.model)?", "Remove “\(collection.title)”") {
                    app.offline.remove(collection.reason)
                }
            })]
        }
        return button
    }

    /// The songs the keep holds, by title; those the library no longer has
    /// are left out.
    private static func keptTracks() -> [Track] {
        app.offline.keptTrackIDs.compactMap { app.library.track(id: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Everything here, once each, shuffled.
    private static func shuffleAll() {
        var seen = Set<ItemID>()
        var tracks: [Track] = []
        for track in app.offline.collections.flatMap(\.tracks) + keptTracks() where app.offline.has(track.id) {
            if seen.insert(track.id).inserted { tracks.append(track) }
        }
        app.player.play(tracks, context: QueueContext(.other, title: "Downloaded"), shuffled: true)
    }
}
