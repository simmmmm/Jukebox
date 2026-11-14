// Preferences, as GNOME's apps have them (libadwaita's preferences dialog):
// the same choices as the iPhone's Settings, kept by the same AppSettings,
// less what only a phone has (the mobile network, downloads, the record
// that spins).

import CAdw
import Foundation
import JukeboxKit

enum Preferences {
    static func present() {
        let settings = app.settings
        Stats.track(.screen, ["name": "settings"])
        let page = adw_preferences_page_new()!

        let playing = group("Playing", on: page)
        let qualities: [(String, StreamQuality)] = [("Original", .original), ("High (320 kbit/s)", .high),
                                                    ("Normal (256 kbit/s)", .normal), ("Low (128 kbit/s)", .low)]
        adw_preferences_group_add(ptr(playing), combo("Streaming Quality", qualities.map { $0.0 },
                                                      selected: qualities.firstIndex { $0.1 == settings.wifiQuality } ?? 0) {
            settings.wifiQuality = qualities[$0].1
        })
        adw_preferences_group_add(ptr(playing), toggle(
            "Autoplay", "When an album or a playlist ends, play on with a station from its last song.",
            settings.autoplay) { settings.autoplay = $0 })
        if app.can(.replayGain) {
            adw_preferences_group_add(ptr(playing), toggle(
                "Normalize Volume", "Play every song at the loudness your server measured.",
                settings.normalizeVolume) { settings.normalizeVolume = $0 })
        }
        adw_preferences_group_add(ptr(playing), toggle(
            "Find Lyrics Online", "When your server has none for a song, ask LRCLIB (lrclib.net).",
            settings.findLyricsOnline) { settings.findLyricsOnline = $0 })

        let radio = group("Radio", on: page)
        let key = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(key), "Last.fm API Key")
        gtk_editable_set_text(ptr(key), settings.lastFMAPIKey)
        adw_entry_row_set_show_apply_button(ptr(key), 1)
        // Kept on ✓ or Enter, and when the dialog closes with a changed key:
        // a key typed and left without ✓ was lost.
        func keepKey() {
            let typed = String(cString: gtk_editable_get_text(ptr(key))).trimmingCharacters(in: .whitespaces)
            guard typed != settings.lastFMAPIKey else { return }
            settings.lastFMAPIKey = typed
            Stats.track(.lastFMKey, ["set": settings.hasLastFM])
            app.radio.lastFMKeyChanged()
        }
        on(key, "apply") { keepKey() }
        adw_preferences_group_add(ptr(radio), key)
        adw_preferences_group_set_description(
            ptr(radio), "With a Last.fm API key, the radio also knows which artists and songs sound alike.")

        let privacy = group("Privacy", on: page)
        adw_preferences_group_add(ptr(privacy), toggle(
            "Share Anonymous Usage", "Which screens and features are used. Never a title, an artist, a search or a server.",
            settings.shareUsage) { settings.shareUsage = $0 })

        if let credentials = app.credentials {
            let account = group("Server", on: page)
            let row = adw_action_row_new()!
            adw_preferences_row_set_title(ptr(row), credentials.serverName.isEmpty ? credentials.serverURL.host ?? "" : credentials.serverName)
            adw_action_row_set_subtitle(ptr(row), "\(credentials.kind.displayName) \(credentials.serverVersion) · \(credentials.userName)")
            adw_preferences_group_add(ptr(account), row)
        }

        let dialog = adw_preferences_dialog_new()!
        adw_preferences_dialog_add(ptr(dialog), ptr(page))
        on(dialog, "closed") { keepKey() }
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    private static func group(_ title: String, on page: Widget) -> Widget {
        let group = adw_preferences_group_new()!
        adw_preferences_group_set_title(ptr(group), title)
        adw_preferences_page_add(ptr(page), ptr(group))
        return group
    }

    private static func toggle(_ title: String, _ subtitle: String, _ isOn: Bool, _ changed: @escaping (Bool) -> Void) -> Widget {
        let row = adw_switch_row_new()!
        adw_preferences_row_set_title(ptr(row), title)
        adw_action_row_set_subtitle(ptr(row), subtitle)
        adw_switch_row_set_active(ptr(row), isOn ? 1 : 0)
        on(row, "notify::active") { changed(adw_switch_row_get_active(ptr(row)) != 0) }
        return row
    }

    private static func combo(_ title: String, _ names: [String], selected: Int, _ changed: @escaping (Int) -> Void) -> Widget {
        let row = adw_combo_row_new()!
        adw_preferences_row_set_title(ptr(row), title)
        var strings: [UnsafePointer<CChar>?] = names.map { UnsafePointer(strdup($0)) }
        strings.append(nil)
        adw_combo_row_set_model(ptr(row), ptr(gtk_string_list_new(strings)))
        for string in strings { free(UnsafeMutablePointer(mutating: string)) }
        adw_combo_row_set_selected(ptr(row), guint(selected))
        on(row, "notify::selected") { changed(Int(adw_combo_row_get_selected(ptr(row)))) }
        return row
    }
}
