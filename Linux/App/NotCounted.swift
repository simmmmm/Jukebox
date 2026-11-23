// Don't Count Plays and Private Listening on Linux, as the Mac's
// (Jukebox/Library/NotCountedViews.swift; the store is the shared
// NotCountedStore). "kun je het ook mogelijk maken om nummers/albums/
// playlists niet te scrobblen? of mee te laten tellen voor die stats bijv
// voor kerstmuziek oid?", and "een soort prive modus overall" (19 November
// 2026). An item in the song's, album's and playlist's menus (Don't Count
// Plays, or Count Plays Again while marked); Private
// Listening as radio items in the primary menu and a row in Preferences;
// one quiet glyph in the bar while it is on.

import CAdw
import Foundation
import JukeboxKit

enum NotCountedUI {
    static let modes: [(PrivateListening, String)] = [
        (.off, "Off"), (.on, "On"), (.untilRestart, "Until Jukebox Restarts"),
    ]

    /// The menus' item, a plain one whose words say what it does: Don't
    /// Count Plays, and Count Plays Again while marked, as Preferences'
    /// Count Again. Not a check: one check item in a GNOME menu keeps room
    /// for its mark before every item of that menu, so the whole menu stood
    /// in from the edge ("het lijkt wel of je rekening hebt gehouden met
    /// meer iconen qua padding", the photographer, 21 November 2026).
    static func items(_ kind: NotCounted.Kind, _ id: ItemID, _ name: String) -> [(String, () -> Void)] {
        let store = app.player.notCounted
        return [(store.isMarked(kind, id) ? "Count Plays Again" : "Don't Count Plays",
                 { store.toggle(kind, id: id, name: name) })]
    }

    /// The primary menu's Private Listening: three radio items of one
    /// action with the mode as its state, followed as the store changes.
    /// The action is the window's own, in a group of its own on `owner`,
    /// not the application's: those GApplication offers on the session's
    /// bus, where any program could turn the counting back on unseen.
    static func install(owner: Widget, in menu: OpaquePointer) {
        let store = app.player.notCounted
        let action = g_simple_action_new_stateful("private-listening", g_variant_type_new("s"),
                                                  g_variant_new_string(store.privateListening.rawValue))!
        on(raw(action), "activate", argument: { parameter in
            guard let parameter,
                  let mode = PrivateListening(rawValue: String(cString: g_variant_get_string(OpaquePointer(parameter), nil)))
            else { return }
            store.privateListening = mode
        })
        let group = g_simple_action_group_new()!
        g_action_map_add_action(ptr(group), ptr(action))
        gtk_widget_insert_action_group(owner, "listening", ptr(group))
        let choices = g_menu_new()!
        for (mode, title) in modes {
            let item = g_menu_item_new(title, nil)!
            g_menu_item_set_action_and_target_value(item, "listening.private-listening", g_variant_new_string(mode.rawValue))
            g_menu_append_item(choices, item)
            g_object_unref(raw(item))
        }
        let section = g_menu_new()!
        g_menu_append_submenu(section, "Private Listening", ptr(choices))
        g_menu_prepend_section(menu, nil, ptr(section))
        observe(owner) {
            g_simple_action_set_state(action, g_variant_new_string(store.privateListening.rawValue))
        }
    }

    /// The bar's sign while Private Listening is on: a flat glyph that
    /// turns it off.
    static func sign() -> Widget {
        let store = app.player.notCounted
        let button = iconButton("view-conceal-symbolic", "Private Listening is on", "flat") {
            store.privateListening = .off
        }
        button.tooltip("Private Listening is on: plays are not counted. Click to turn it off.")
        gtk_widget_add_css_class(button, "dim-label")
        observe(button) { button.isVisible = store.isPrivate }
        return button
    }

    /// Preferences' group: Private Listening, then what is marked, each
    /// with Count Again.
    static func group(on page: Widget) {
        let store = app.player.notCounted
        let group = adw_preferences_group_new()!
        adw_preferences_group_set_title(ptr(group), "Not Counted")
        adw_preferences_group_set_description(
            ptr(group), "Plays without a count: your server is not told, so no play count and no scrobble, and Jukebox does not learn from them for the radio, the mixes or Your Year. Mark a song, an album or a playlist with Don't Count Plays in its menu.")
        adw_preferences_page_add(ptr(page), ptr(group))

        let mode = adw_combo_row_new()!
        adw_preferences_row_set_title(ptr(mode), "Private Listening")
        var strings: [UnsafePointer<CChar>?] = modes.map { UnsafePointer(strdup($0.1)) }
        strings.append(nil)
        adw_combo_row_set_model(ptr(mode), ptr(gtk_string_list_new(strings)))
        for string in strings { free(UnsafeMutablePointer(mutating: string)) }
        on(mode, "notify::selected") {
            let index = Int(adw_combo_row_get_selected(ptr(mode)))
            if modes.indices.contains(index), store.privateListening != modes[index].0 {
                store.privateListening = modes[index].0
            }
        }
        adw_preferences_group_add(ptr(group), mode)

        var rows: [Widget] = []
        observe(group) {
            let selected = modes.firstIndex { $0.0 == store.privateListening } ?? 0
            if Int(adw_combo_row_get_selected(ptr(mode))) != selected { adw_combo_row_set_selected(ptr(mode), guint(selected)) }
            for row in rows { adw_preferences_group_remove(ptr(group), row) }
            rows = []
            for item in store.marks.items {
                let row = adw_action_row_new()!
                // The server's name for it, not markup.
                adw_preferences_row_set_use_markup(ptr(row), 0)
                adw_preferences_row_set_title(ptr(row), item.name)
                adw_action_row_set_subtitle(ptr(row), kindName(item.kind))
                let again = button("Count Again", "flat") {
                    store.set(item.kind, id: item.id, name: item.name, counted: true)
                }.align(vertical: GTK_ALIGN_CENTER)
                adw_action_row_add_suffix(ptr(row), again)
                adw_preferences_group_add(ptr(group), row)
                rows.append(row)
            }
        }
    }

    static func kindName(_ kind: NotCounted.Kind) -> String {
        switch kind {
        case .song: String(localized: "Song")
        case .album: String(localized: "Album")
        case .playlist: String(localized: "Playlist")
        }
    }
}
