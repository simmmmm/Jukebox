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

        let dialog = adw_preferences_dialog_new()!
        let radio = group("Radio", on: page)
        let saveTypedKey = lastFM(on: radio, in: dialog)
        adw_preferences_group_set_description(
            ptr(radio), "With a Last.fm API key, the radio also knows which artists and songs sound alike, and the genres of your artists. With your username, it learns when you play what from your scrobbles. Nothing is written to Last.fm.")

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

        NotCountedUI.group(on: page)
        accounts(on: page, in: dialog)
        downloads(on: page)

        adw_preferences_dialog_add(ptr(dialog), ptr(page))
        on(dialog, "closed") { saveTypedKey() }
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    /// The Last.fm key, the same flow as the iPhone's and the Mac's Settings
    /// ("invullen opslaan bevestiging krijgen van de app", the photographer,
    /// 18 November 2026): pasted, saved with ✓ or Enter, Last.fm is asked,
    /// and only a key it accepted is kept, then shown as dots with Change and
    /// Remove. A typo never takes the radio's Last.fm away. Gives back what
    /// the dialog does on closing: a key typed and left without ✓ is checked
    /// all the same (it was once lost), and kept only if accepted.
    private static func lastFM(on group: Widget, in dialog: UnsafeMutablePointer<AdwDialog>) -> @MainActor () -> Void {
        let settings = app.settings
        let entry = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(entry), "Last.fm API Key")
        adw_entry_row_set_show_apply_button(ptr(entry), 1)
        let spinner = gtk_spinner_new()!
        spinner.isVisible = false
        adw_entry_row_add_suffix(ptr(entry), spinner)
        let saved = adw_action_row_new()!
        adw_preferences_row_set_title(ptr(saved), "Last.fm API Key")
        adw_action_row_set_subtitle(ptr(saved), "••••••••")
        gtk_widget_add_css_class(saved, "property")
        // The listener's Last.fm name, optional, once a key is kept: one
        // row in the key's flow (✓ or Enter, Last.fm asked, kept only when
        // it knows them), for the clock's scrobbles. Emptied, it is gone.
        // Not a secret, so shown as typed.
        let user = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(user), "Last.fm Username")
        adw_entry_row_set_show_apply_button(ptr(user), 1)
        gtk_editable_set_text(ptr(user), settings.lastFMUser)
        var isChecking = false
        var isCheckingUser = false
        var isClosed = false

        func typed() -> String {
            String(cString: gtk_editable_get_text(ptr(entry))).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func editing(_ isEditing: Bool) {
            entry.isVisible = isEditing
            saved.isVisible = !isEditing
            gtk_editable_set_text(ptr(entry), "")
            gtk_widget_remove_css_class(entry, "error")
        }
        // In the dialog while it is open, else in the window: a check may
        // answer after Preferences has closed.
        func say(_ words: String) {
            if isClosed { MainWindow.toast(words) } else { adw_preferences_dialog_add_toast(ptr(dialog), adw_toast_new(words)) }
        }
        func save() {
            let key = typed()
            guard !key.isEmpty, !isChecking else { return }
            isChecking = true
            entry.isSensitive = false
            spinner.isVisible = true
            gtk_spinner_start(ptr(spinner))
            gtk_widget_remove_css_class(entry, "error")
            Task {
                let check = await LastFMClient(apiKey: key).validateKey()
                isChecking = false
                if !isClosed {
                    gtk_spinner_stop(ptr(spinner))
                    spinner.isVisible = false
                    entry.isSensitive = true
                }
                guard check == .accepted else {
                    // The typed key stays, to be put right.
                    if !isClosed { gtk_widget_add_css_class(entry, "error") }
                    say(check.problem ?? "")
                    return
                }
                if key != settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) {
                    settings.lastFMAPIKey = key
                    app.radio.lastFMKeyChanged()
                    Stats.track(.lastFMKey, ["state": "added"])
                }
                if !isClosed {
                    // A refusal of the key before it no longer stands.
                    adw_action_row_set_subtitle(ptr(saved), "••••••••")
                    editing(false)
                    user.isVisible = true
                }
                say("Last.fm key saved")
            }
        }
        func typedUser() -> String {
            String(cString: gtk_editable_get_text(ptr(user))).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func saveUser() {
            let name = typedUser()
            guard !isCheckingUser, name != settings.lastFMUser.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            gtk_widget_remove_css_class(user, "error")
            guard !name.isEmpty else {
                settings.lastFMUser = ""
                app.radio.lastFMKeyChanged()
                say("Last.fm username removed")
                return
            }
            isCheckingUser = true
            user.isSensitive = false
            let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                let check = await LastFMClient(apiKey: key).validateUser(name)
                isCheckingUser = false
                if !isClosed { user.isSensitive = true }
                guard check == .accepted else {
                    // The typed name stays, to be put right.
                    if !isClosed { gtk_widget_add_css_class(user, "error") }
                    say(check.problem ?? "")
                    return
                }
                settings.lastFMUser = name
                app.radio.lastFMKeyChanged()
                say("Last.fm username saved")
            }
        }
        on(user, "apply") { saveUser() }
        on(user, "entry-activated") { saveUser() }
        on(user, "changed") { gtk_widget_remove_css_class(user, "error") }
        // ✓, and Enter: after "Could not reach Last.fm" the ✓ is gone until
        // the text changes, and Enter tries again.
        on(entry, "apply") { save() }
        on(entry, "entry-activated") { save() }
        // Typing again: the last answer was about another key.
        on(entry, "changed") { gtk_widget_remove_css_class(entry, "error") }

        let cancel = button("Cancel", "flat") { editing(false) }.align(vertical: GTK_ALIGN_CENTER)
        adw_entry_row_add_suffix(ptr(entry), cancel)
        let change = button("Change", "flat") {
            editing(true)
            cancel.isVisible = true
            gtk_widget_grab_focus(entry)
        }.align(vertical: GTK_ALIGN_CENTER)
        let remove = button("Remove", "flat") {
            settings.lastFMAPIKey = ""
            app.radio.lastFMKeyChanged()
            Stats.track(.lastFMKey, ["state": "removed"])
            editing(true)
            cancel.isVisible = false
            user.isVisible = false
            say("Last.fm key removed")
        }.align(vertical: GTK_ALIGN_CENTER)
        adw_action_row_add_suffix(ptr(saved), change)
        adw_action_row_add_suffix(ptr(saved), remove)
        adw_preferences_group_add(ptr(group), entry)
        adw_preferences_group_add(ptr(group), saved)
        adw_preferences_group_add(ptr(group), user)
        editing(!settings.hasLastFM)
        cancel.isVisible = false
        user.isVisible = settings.hasLastFM

        // The saved key, asked about again each time Preferences opens, as
        // the iPhone's Settings does: a revoked key shows here rather than as
        // a quieter radio. Quietly; only a refusal is said, and the key stays.
        if settings.hasLastFM {
            let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                let check = await LastFMClient(apiKey: key).validateKey()
                // Still the key shown: not one removed or changed meanwhile.
                guard !isClosed, check == .refused, saved.isVisible,
                      key == settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                adw_action_row_set_subtitle(ptr(saved), "•••••••• · " + (check.problem ?? ""))
            }
        }
        return {
            isClosed = true
            // Not one Last.fm already answered about.
            if entry.isVisible, !isChecking, gtk_widget_has_css_class(entry, "error") == 0 { save() }
            if user.isVisible, gtk_widget_has_css_class(user, "error") == 0 { saveUser() }
        }
    }

    /// Every account kept, as GNOME's Online Accounts lists them: the
    /// server's name, its kind and version and the user under it, the one
    /// signed in checked. A click on another switches to it (the dialog
    /// closes on its Home); Sign Out… on a row signs out of that one alone.
    /// Add Account… under them, as the iPhone's Settings has it.
    private static func accounts(on page: Widget, in dialog: UnsafeMutablePointer<AdwDialog>) {
        let group = group("Accounts", on: page)
        // In the group's header, where GNOME's Settings puts a group's own
        // action.
        let add = button("Add Account…", "flat") {
            adw_dialog_close(ptr(dialog))
            MainWindow.addAccount()
        }.align(vertical: GTK_ALIGN_CENTER)
        adw_preferences_group_set_header_suffix(ptr(group), add)
        var rows: [Widget] = []
        observe(group) {
            for row in rows { adw_preferences_group_remove(ptr(group), row) }
            rows = []
            let active = app.credentials
            let switching = app.isSwitching
            // Whether Playback Reporting answers, on Jellyfin and Emby: the
            // group's own description, where GNOME puts a group's note.
            adw_preferences_group_set_description(ptr(group), active.flatMap(ServerWords.playbackReportingNote))
            for account in app.accounts.saved {
                let row = adw_action_row_new()!
                adw_preferences_row_set_title(ptr(row), ServerWords.name(of: account))
                adw_action_row_set_subtitle(ptr(row), "\(ServerWords.product(account.kind, version: account.serverVersion)) · \(account.userName)")
                if active?.isSameAccount(as: account) == true {
                    let check = gtk_image_new_from_icon_name("object-select-symbolic")!.named("Signed In")
                    adw_action_row_add_suffix(ptr(row), check)
                } else {
                    gtk_list_box_row_set_activatable(ptr(row), 1)
                    // One switch at a time, while its server is asked.
                    row.isSensitive = !switching
                    on(raw(row), "activated") {
                        Task {
                            if let problem = await app.switchAccount(to: account) {
                                adw_preferences_dialog_add_toast(ptr(dialog), adw_toast_new(problem))
                            } else {
                                adw_dialog_close(ptr(dialog))
                            }
                        }
                    }
                }
                let out = button("Sign Out…", "flat") { MainWindow.confirmSignOut(of: account) }
                    .align(vertical: GTK_ALIGN_CENTER)
                adw_action_row_add_suffix(ptr(row), out)
                adw_preferences_group_add(ptr(group), row)
                rows.append(row)
            }
            // The year's music, a subpage (YourYearPage): from the server's
            // record where it keeps one, as the description above says.
            if active != nil {
                let year = adw_action_row_new()!
                adw_preferences_row_set_title(ptr(year), "Your Year")
                adw_action_row_add_suffix(ptr(year), gtk_image_new_from_icon_name("go-next-symbolic")!)
                gtk_list_box_row_set_activatable(ptr(year), 1)
                on(raw(year), "activated") {
                    adw_preferences_dialog_push_subpage(ptr(dialog), YourYearPage.make())
                }
                adw_preferences_group_add(ptr(group), year)
                rows.append(year)
            }
        }
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
        // MP3 from a Subsonic server or Plex, AAC from Jellyfin.
        let convertsToMP3 = app.credentials?.kind.convertedFormat == "MP3"
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
            let quality = convertsToMP3
                ? "Original is each file as it is, or MP3 at 320 kbit/s when this computer cannot play it; High and Normal have \(app.library.serverKind) convert songs to MP3 at that rate, so more of them fit. Kept songs wait while the power saver is on."
                : "Original is each file as it is, or AAC at 256 kbit/s when this computer cannot play it; High and Normal have \(app.library.serverKind) convert songs to AAC at that rate, so more of them fit. Kept songs wait while the power saver is on."
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
