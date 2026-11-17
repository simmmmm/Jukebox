// Preferences, as GNOME's apps have them (libadwaita's preferences dialog):
// the same choices as the iPhone's Settings, kept by the same AppSettings,
// less what only a phone has (the mobile network, the record that spins).

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
        let crossfades = AppSettings.crossfades
        let crossfade = combo("Crossfade", crossfades.map { $0 == 0 ? "Off" : "\($0) s" },
                              selected: crossfades.firstIndex(of: settings.crossfade) ?? 0) {
            settings.crossfade = crossfades[$0]
        }
        adw_action_row_set_subtitle(ptr(crossfade), "A song fades out and the next fades in. Songs that follow each other on an album never fade.")
        adw_preferences_group_add(ptr(playing), crossfade)
        adw_preferences_group_add(ptr(playing), toggle(
            "Continue Where You Left Off", "When Jukebox opens, the song you last played, here or on another device, is ready to play.",
            settings.resumeOnLaunch) { settings.resumeOnLaunch = $0 })
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

        // Which places the sidebar shows (AppSettings.hiddenPages), in its
        // order; Home has no switch. The photographer, 15 November 2026:
        // "kan je zelf bepalen hoe minimalistisch je alles wilt hebben".
        let pages = group("Pages", on: page)
        adw_preferences_group_set_description(ptr(pages), "Home is always there. Pages that are off stay reachable from Home and Search.")
        let titles: [AppSettings.Page: String] = [
            .radio: "Radio", .albums: "Albums", .artists: "Artists", .songs: "Songs", .playlists: "Playlists",
            .favorites: "Favorites", .genres: "Genres", .recentlyAdded: "Recently Added", .downloaded: "Downloaded",
            .sidebarPlaylists: "Playlists in the Sidebar",
        ]
        for shown in AppSettings.Page.allCases {
            let row = adw_switch_row_new()!
            adw_preferences_row_set_title(ptr(row), titles[shown] ?? shown.rawValue)
            adw_switch_row_set_active(ptr(row), settings.shows(shown) ? 1 : 0)
            on(row, "notify::active") { settings.setShows(shown, adw_switch_row_get_active(ptr(row)) != 0) }
            adw_preferences_group_add(ptr(pages), row)
        }

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

        downloads(on: page)

        let dialog = adw_preferences_dialog_new()!
        adw_preferences_dialog_add(ptr(dialog), ptr(page))
        on(dialog, "closed") { keepKey() }
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    /// Songs on this computer (OfflineStore), as the Mac's Settings ›
    /// Downloads: Keep Songs I Play, on at 5 GB ("automatisch bewaren wat je
    /// vaak of kort geleden hebt gespeeld, tot een grootte die je kiest" —
    /// "Alle drie", the photographer, 8 November 2026), the quality, the
    /// space each takes, and Remove All Downloads, asked first.
    private static func downloads(on page: Widget) {
        let settings = app.settings
        let offline = app.offline
        let group = group("Downloads", on: page)
        let keep = toggle("Keep Songs I Play", "Songs you play often or lately stay on this computer, to play without a connection",
                          settings.keepSongs) { settings.keepSongs = $0 }
        adw_preferences_group_add(ptr(group), keep)
        let limits = AppSettings.keepLimits
        let upTo = combo("Up To", limits.map { "\($0) GB" }, selected: limits.firstIndex(of: settings.keepLimitGB) ?? 2) {
            settings.keepLimitGB = limits[$0]
        }
        adw_preferences_group_add(ptr(group), upTo)
        // The kit's rate for each quality, so the words and the files agree.
        let qualities = DownloadQuality.allCases
        let names = qualities.map { quality -> String in
            let kilobits = (quality.aacBitrate ?? 0) / 1000
            switch quality {
            case .original: return "Original"
            case .high: return "High (\(kilobits) kbit/s)"
            case .normal: return "Normal (\(kilobits) kbit/s)"
            }
        }
        adw_preferences_group_add(ptr(group), combo("Download Quality", names,
                                                    selected: qualities.firstIndex(of: settings.downloadQuality) ?? 0) {
            settings.downloadQuality = qualities[$0]
        })
        let chosen = fact("Downloaded")
        let kept = fact("Kept")
        let status = fact("Downloading")
        for row in [chosen, kept, status] { adw_preferences_group_add(ptr(group), row) }
        // Under the rows, as GNOME's Settings has its destructive buttons
        // (libadwaita 1.5 has no button row).
        let removeAll = button("Remove All Downloads", "destructive-action") {
            let dialog = adw_alert_dialog_new("Remove all downloads from this computer?",
                                              "Every downloaded album, playlist, mix and kept song goes, and Keep Songs I Play is turned off. They still play from your server.")!
            adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
            adw_alert_dialog_add_response(ptr(dialog), "remove", "Remove All Downloads")
            adw_alert_dialog_set_response_appearance(ptr(dialog), "remove", ADW_RESPONSE_DESTRUCTIVE)
            adw_alert_dialog_set_default_response(ptr(dialog), "cancel")
            adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
            on(raw(dialog), "response", argument: { response in
                guard let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "remove" else { return }
                offline.removeAll()
                // Turned off with it: the switch says so too.
                adw_switch_row_set_active(ptr(keep), 0)
            })
            adw_dialog_present(ptr(dialog), MainWindow.window)
        }.align(horizontal: GTK_ALIGN_START)
        gtk_widget_set_margin_top(removeAll, 12)
        adw_preferences_group_add(ptr(group), removeAll)
        let isSubsonic = app.credentials?.kind.isSubsonic == true
        let server = app.credentials.map { $0.serverName.isEmpty ? ($0.serverURL.host ?? "Your server") : $0.serverName } ?? "Your server"
        observe(group) {
            upTo.isVisible = settings.keepSongs
            let sizes = offline.keptBytes.formatted(.byteCount(style: .file))
            adw_action_row_set_subtitle(ptr(chosen), offline.chosenBytes.formatted(.byteCount(style: .file)))
            adw_action_row_set_subtitle(ptr(kept), settings.keepSongs ? "\(sizes) of \(settings.keepLimitGB) GB" : sizes)
            // What the songs still to come are doing, when there are any.
            status.isVisible = offline.queuedCount > 0
            let doing: String
            switch offline.waiting {
            case .wifi?: doing = "Waiting for Wi-Fi"
            case .network?: doing = "Waiting for a Connection"
            case .notAllowed?: doing = "Paused"
            case nil: doing = offline.isLowPower && !offline.wanted.contains { $0.isChosen } ? "Paused in Power Saver" : "Downloading"
            }
            adw_preferences_row_set_title(ptr(status), doing)
            adw_action_row_set_subtitle(ptr(status), LibraryText.songs(offline.queuedCount))
            gtk_widget_set_sensitive(removeAll, offline.songCount > 0 || offline.queuedCount > 0 ? 1 : 0)
            // What each quality means on this kind of server (the Mac's
            // footer, docs/OFFLINE.md); first, when the server's admin
            // turned downloads off for this account, that, as a fact.
            let quality = isSubsonic
                ? "Original is each file as it is, or MP3 at 320 kbit/s when this computer cannot play it; High and Normal have \(app.library.serverKind) convert songs to MP3 at that rate, so more of them fit. Kept songs wait while the power saver is on."
                : "Original is each file as it is, or AAC at 256 kbit/s when this computer cannot play it; High and Normal have Jellyfin convert songs to AAC at that rate, so more of them fit. Kept songs wait while the power saver is on."
            adw_preferences_group_set_description(ptr(group), offline.downloadsAllowed
                ? quality : "\(server) doesn’t allow downloads for this account. " + quality)
        }
    }

    /// A row of one fact: its name, and what it is under it.
    private static func fact(_ title: String) -> Widget {
        let row = adw_action_row_new()!
        adw_preferences_row_set_title(ptr(row), title)
        gtk_widget_add_css_class(row, "property")
        return row
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
