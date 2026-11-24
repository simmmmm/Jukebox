// Preferences, as GNOME's apps have them (libadwaita's preferences dialog):
// the same choices as the iPhone's Settings, kept by the same AppSettings,
// less what only a phone has (the mobile network, the record that spins).
//
// In pages, the dialog's own view switcher over them and its search: "Voor
// een volgende versie moeten we ff de instellingen netjes opdelen in
// paginas, apple hig manier volgens mij kan dat ook op de gnome hig manier
// op Linux" (the photographer, 19 November 2026). The pages and their order
// are the iPhone's, the iPad's and the Mac's (SettingsView.swift's
// SettingsPage); About is the main menu's About Jukebox. A group's title
// only where it tells something the page's does not. Every row, its words,
// its order and its group's note, as the other clients have them:
// docs/design/settings.md ("check het echt goed met de rest ook", the
// photographer, 21 November 2026).

import CAdw
import Foundation
import JukeboxKit

enum Preferences {
    /// The pages' names, for the walk (Shots.swift) to open one.
    enum Page: String {
        case accounts, playback, radio, library, downloads, privacy
    }

    static func present() {
        let settings = app.settings
        Stats.track(.screen, ["name": "settings"])
        let dialog = adw_preferences_dialog_new()!
        adw_preferences_dialog_set_search_enabled(ptr(dialog), 1)
        let accountsPage = page(.accounts, "Accounts", "avatar-default-symbolic", in: dialog)
        let playbackPage = page(.playback, "Playback", "media-playback-start-symbolic", in: dialog)
        let radioPage = page(.radio, "Radio", Glyphs.name("radio"), in: dialog)
        let libraryPage = page(.library, "Library", "folder-music-symbolic", in: dialog)
        let downloadsPage = page(.downloads, "Downloads", Glyphs.name("download"), in: dialog)
        let privacyPage = page(.privacy, "Privacy", "view-conceal-symbolic", in: dialog)

        // The quality with its note under it, as the Mac's Settings has the
        // footer by its pickers; then how songs follow each other.
        let streaming = group(nil, on: playbackPage)
        let playing = group(nil, on: playbackPage)
        // Efficient where this server makes Opus; kept from another server
        // it reads as Low (StreamQuality.shown), as the Mac's picker.
        let opus = app.can(.opusStream)
        let names: [StreamQuality: String] = [.original: "Original", .high: "High (320 kbit/s)", .normal: "Normal (256 kbit/s)",
                                              .efficient: "Efficient (Opus, 128 kbit/s)", .low: "Low (128 kbit/s)"]
        let qualities = StreamQuality.offered(opus: opus).map { (names[$0] ?? "", $0) }
        let kept = settings.wifiQuality.shown(opus: opus)
        adw_preferences_group_add(ptr(streaming), combo("Streaming Quality", qualities.map { $0.0 },
                                                        selected: qualities.firstIndex { $0.1 == kept } ?? 0) {
            settings.wifiQuality = qualities[$0].1
        })
        // The Mac's Streaming on a Hotspot, in GNOME's word for a connection
        // that costs data (Platform.swift's watch, DataCost).
        adw_preferences_group_add(ptr(streaming), combo("Streaming on a Metered Connection", qualities.map { $0.0 },
                                                        selected: qualities.firstIndex { $0.1 == settings.cellularQuality.shown(opus: opus) } ?? 2) {
            settings.cellularQuality = qualities[$0].1
        })
        adw_preferences_group_add(ptr(streaming), toggle(
            "Adjust to the Connection", "When a song has to wait for the network, the next ones stream lower until it holds again.",
            settings.adjustsToConnection) { settings.adjustsToConnection = $0 })
        adw_preferences_group_set_description(
            ptr(streaming), "Original plays your files as they are. The others have \(app.library.serverKind) convert them to \(app.credentials?.kind.convertedFormat ?? "AAC") at that rate, which uses less data.\(opus ? StreamQuality.efficientNote : "")")
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
        // Where the server gives songs no loudness the switch would do
        // nothing: shown off and dimmed, saying why, as the Mac's.
        if app.can(.replayGain) {
            adw_preferences_group_add(ptr(playing), toggle(
                "Normalize Volume", app.credentials?.kind.isSubsonic == true
                    ? "Play every song at the loudness its ReplayGain tags give, so loud and quiet records sit side by side."
                    : "Play every song at the loudness Jellyfin measured, so loud and quiet records sit side by side.",
                settings.normalizeVolume) { settings.normalizeVolume = $0 })
        } else {
            let normalize = toggle("Normalize Volume", "\(app.library.serverKind) doesn’t give songs a loudness, so each plays as it is.",
                                   false) { _ in }
            gtk_widget_set_sensitive(normalize, 0)
            adw_preferences_group_add(ptr(playing), normalize)
        }
        adw_preferences_group_add(ptr(playing), toggle(
            "Find Lyrics Online", "When your server has no lyrics for a song, ask LRCLIB (lrclib.net), with its title, artist, album and length.",
            settings.findLyricsOnline) { settings.findLyricsOnline = $0 })

        // Enhance Radio (AppSettings.enhanceRadio), as the iPhone's, the
        // iPad's and the Mac's Settings › Radio: Last.fm and AcousticBrainz
        // together, "of lastfm en dit aan of beide uit" (the photographer,
        // 24 November 2026). Off, the username goes from the page, and the
        // radio plays from the library and what they said before. A build
        // without Jukebox's key has none of it.
        dial(on: radioPage)
        var saveTypedUser: @MainActor () -> Void = {}
        if AppSettings.canEnhanceRadio {
            let enhance = group(nil, on: radioPage)
            let user = lastFMUser(in: dialog)
            adw_preferences_group_add(ptr(enhance), toggle(
                "Enhance Radio",
                "To find music that sounds alike, Jukebox sends the artist, song and album names in your library to Last.fm and ListenBrainz, and asks AcousticBrainz how each song sounds. Your Last.fm username goes too, if you add one. Nothing about your music server, your sign-in or this device is sent.",
                settings.enhanceRadio) {
                settings.enhanceRadio = $0
                user.row.isVisible = $0
                app.radio.enhanceRadioChanged()
            })
            adw_preferences_group_add(ptr(enhance), user.row)
            user.row.isVisible = settings.enhanceRadio
            saveTypedUser = user.save
            // A Last.fm out of reach, said once and calmly by the switch,
            // as the Mac's footer (RadioController.lastFMTrouble).
            observe(enhance) {
                adw_preferences_group_set_description(ptr(enhance), app.radio.lastFMTrouble?.text)
            }
        }

        // Which places the sidebar shows (AppSettings.hiddenPages), in its
        // order; Home has no switch. The photographer, 15 November 2026:
        // "kan je zelf bepalen hoe minimalistisch je alles wilt hebben".
        library(on: libraryPage)
        let pages = group("Pages", on: libraryPage)
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

        // Not Counted first, as on the iPhone: what is kept from the server,
        // then what is told the developer.
        NotCountedUI.group(on: privacyPage)
        history(on: privacyPage)
        // The switch alone, and under the group what is counted and what
        // never is, as the Mac's footer, word for word.
        let privacy = group(nil, on: privacyPage)
        let usage = adw_switch_row_new()!
        adw_preferences_row_set_title(ptr(usage), "Share Anonymous Usage")
        adw_switch_row_set_active(ptr(usage), settings.shareUsage ? 1 : 0)
        on(usage, "notify::active") { settings.shareUsage = adw_switch_row_get_active(ptr(usage)) != 0 }
        adw_preferences_group_add(ptr(privacy), usage)
        adw_preferences_group_set_description(ptr(privacy), "Jukebox counts which screens and features are used, never titles, artists, searches, server addresses or names, on the developer's own server, without cookies or a device id. It helps decide what to improve.")

        accounts(on: accountsPage, in: dialog)
        downloads(on: downloadsPage)

        on(dialog, "closed") { saveTypedUser() }
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    /// The listener's Last.fm name, optional, for the clock's scrobbles: ✓
    /// or Enter, Last.fm asked, kept only when it knows them. Emptied, it
    /// is gone. Not a secret, so shown as typed. The key is Jukebox's own
    /// alone since 24 November 2026 ("Kan die api ding … ook uit de app
    /// dan?", the photographer). Gives back the row, and what the dialog
    /// does on closing: a name typed and left without ✓ is checked all the
    /// same.
    private static func lastFMUser(in dialog: UnsafeMutablePointer<AdwDialog>) -> (row: Widget, save: @MainActor () -> Void) {
        let settings = app.settings
        let user = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(user), "Last.fm Username (Optional)")
        adw_entry_row_set_show_apply_button(ptr(user), 1)
        gtk_editable_set_text(ptr(user), settings.lastFMUser)
        var isChecking = false
        var isClosed = false
        // In the dialog while it is open, else in the window: a check may
        // answer after Preferences has closed.
        func say(_ words: String) {
            guard !isClosed else { return MainWindow.toast(words) }
            let toast = adw_toast_new(words)!
            adw_toast_set_use_markup(toast, 0)
            adw_preferences_dialog_add_toast(ptr(dialog), toast)
        }
        func saveUser() {
            let name = String(cString: gtk_editable_get_text(ptr(user))).trimmingCharacters(in: .whitespacesAndNewlines)
            guard settings.hasLastFM, !isChecking, name != settings.lastFMUser.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            gtk_widget_remove_css_class(user, "error")
            guard !name.isEmpty else {
                settings.lastFMUser = ""
                app.radio.lastFMKeyChanged()
                say("Last.fm username removed")
                return
            }
            isChecking = true
            user.isSensitive = false
            let key = settings.lastFMKey
            Task {
                let check = await LastFMClient(apiKey: key).validateUser(name)
                isChecking = false
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
        return (user, {
            isClosed = true
            if user.isVisible, gtk_widget_has_css_class(user, "error") == 0 { saveUser() }
        })
    }

    /// Each account kept as a card, the cards a radio group: one is always
    /// the one signed in. The photographer, 21 November 2026: "kun je op
    /// alle versies een toegevoegde server als een soort card tonen die
    /// werken als een soort radiobutton (er moet altijd 1 server actief
    /// zijn)". GNOME's form for one choice of several: a boxed list, each
    /// row a check button in radio mode before it, as GNOME's Settings
    /// chooses a power mode. Then Add Account… as the list's last row, and
    /// Sign Out… of the one signed in under it. The same order and words as
    /// the Mac's cards (AccountCard.swift).
    private static func accounts(on page: Widget, in dialog: UnsafeMutablePointer<AdwDialog>) {
        let group = group(nil, on: page)
        var rows: [Widget] = []
        observe(group) {
            for row in rows { adw_preferences_group_remove(ptr(group), row) }
            rows = []
            let active = app.credentials
            let switching = app.isSwitching
            // Whether Playback Reporting answers, on Jellyfin and Emby: the
            // group's own description, where GNOME puts a group's note.
            // About the server, so beside its cards; On Your Jukebox itself is in
            // the sidebar now.
            adw_preferences_group_set_description(ptr(group), active.flatMap(ServerWords.playbackReportingNote))
            var radios: UnsafeMutablePointer<GtkCheckButton>?
            let saved = app.accounts.saved.isEmpty ? (active.map { [$0] } ?? []) : app.accounts.saved
            for account in saved {
                let isActive = active?.isSameAccount(as: account) == true
                let row = accountRow(account, isActive: isActive, group: &radios)
                if !isActive {
                    gtk_list_box_row_set_activatable(ptr(row), 1)
                    // One switch at a time, while its server is asked.
                    row.isSensitive = !switching
                    // Switched: the dialog closes on its Home. Not: the
                    // words why, and the radio stays where it was, as it
                    // follows the account signed in, never the click.
                    on(raw(row), "activated") {
                        Task {
                            if let problem = await app.switchAccount(to: account) {
                                // Plain words: they name the server, anyone's.
                                let toast = adw_toast_new(problem)!
                                adw_toast_set_use_markup(toast, 0)
                                adw_preferences_dialog_add_toast(ptr(dialog), toast)
                            } else {
                                adw_dialog_close(ptr(dialog))
                            }
                        }
                    }
                    // Another one signed out of, on its secondary click, as
                    // the Mac's context menu: one that no longer answers can
                    // still go.
                    contextMenu(on: row) { [("Sign Out…", { MainWindow.confirmSignOut(of: account) })] }
                }
                adw_preferences_group_add(ptr(group), row)
                rows.append(row)
            }
            // The list's last row, as GNOME's Online Accounts adds one.
            let add = adw_action_row_new()!
            adw_preferences_row_set_title(ptr(add), "Add Account…")
            adw_action_row_add_prefix(ptr(add), gtk_image_new_from_icon_name("list-add-symbolic")!)
            gtk_list_box_row_set_activatable(ptr(add), 1)
            on(raw(add), "activated") {
                adw_dialog_close(ptr(dialog))
                MainWindow.addAccount()
            }
            add.isSensitive = active != nil
            adw_preferences_group_add(ptr(group), add)
            rows.append(add)
            // Under the rows, as GNOME's Settings has its destructive
            // buttons (libadwaita 1.5 has no button row). Of the one signed
            // in: with others kept the next is signed in to, with none the
            // welcome (AppModel.signOut).
            if let active {
                let out = button("Sign Out…", "destructive-action") { MainWindow.confirmSignOut(of: active) }
                    .align(horizontal: GTK_ALIGN_START)
                gtk_widget_set_margin_top(out, 12)
                adw_preferences_group_add(ptr(group), out)
                rows.append(out)
            }
        }
    }

    /// An account's card: the radio, its kind's letter, the server's name,
    /// the kind and the user, the address. The radio is the card's one
    /// swappable part: today one account is signed in at a time; should
    /// several play side by side one day ("waarom we die beperking moeten
    /// hebben", the photographer, 21 November 2026), it becomes a check
    /// that keeps at least one on, and the row stays as it is. Its state is
    /// the account signed in alone; a click is the row's, never the radio's.
    private static func accountRow(_ account: ServerCredentials, isActive: Bool,
                                   group: inout UnsafeMutablePointer<GtkCheckButton>?) -> Widget {
        let row = adw_action_row_new()!.css("account-card")
        if isActive { gtk_widget_add_css_class(row, "on") }
        adw_preferences_row_set_use_markup(ptr(row), 0)
        adw_preferences_row_set_title(ptr(row), ServerWords.name(of: account))
        // Plain http away from home, said once at sign-in ("This Server
        // Isn't Secure") and kept in view, the Mac's line under the address.
        let insecure = account.isInsecure ? "\n\(InsecureServerWords.note)" : ""
        adw_action_row_set_subtitle(ptr(row), "\(ServerWords.product(account.kind, version: account.serverVersion)) · \(account.userName)\n\(account.serverURL.absoluteString)\(insecure)")
        let radio = gtk_check_button_new()!.named(isActive ? "Signed In" : "Switch to This Account")
        let check = UnsafeMutablePointer<GtkCheckButton>(OpaquePointer(radio))
        if let group { gtk_check_button_set_group(check, group) } else { group = check }
        gtk_check_button_set_active(check, isActive ? 1 : 0)
        gtk_widget_set_can_target(radio, 0)
        gtk_widget_set_focusable(radio, 0)
        let mark = label(ServerWords.mark(account.kind), "kind-mark", "serif").align(vertical: GTK_ALIGN_CENTER)
        gtk_label_set_xalign(ptr(mark), 0.5)
        // Each prefix goes before the last: the mark first, so the radio
        // leads, as on the Mac.
        adw_action_row_add_prefix(ptr(row), mark)
        adw_action_row_add_prefix(ptr(row), radio.align(vertical: GTK_ALIGN_CENTER))
        return row
    }

    /// Songs on this computer (OfflineStore), as the Mac's Settings ›
    /// Downloads: Keep Songs I Play, on at 5 GB ("automatisch bewaren wat je
    /// vaak of kort geleden hebt gespeeld, tot een grootte die je kiest" —
    /// "Alle drie", the photographer, 8 November 2026), the quality, the
    /// space each takes, and Remove All Downloads, asked first.
    private static func downloads(on page: Widget) {
        let settings = app.settings
        let offline = app.offline
        let group = group(nil, on: page)
        let keep = toggle("Keep Songs I Play", "Songs you play often or lately stay on this computer, to play without a connection.",
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
        // The Mac's Download on a Hotspot: off, downloads wait for a
        // connection that is not metered.
        adw_preferences_group_add(ptr(group), toggle(
            "Download on a Metered Connection", "Without it, downloads wait for a connection that is not metered.",
            settings.downloadOverCellular) { settings.downloadOverCellular = $0 })
        let chosen = fact("Downloaded")
        let kept = fact("Kept")
        let status = fact("Downloading")
        // What the downloads take, in a group of its own, as the Mac's: the
        // choices above with their note, the space and the button here.
        let space = Self.group(nil, on: page)
        for row in [chosen, kept, status] { adw_preferences_group_add(ptr(space), row) }
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
        adw_preferences_group_add(ptr(space), removeAll)
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

    /// The radio's dial, as the Mac's Settings › Radio has it over Last.fm:
    /// its name and its two ends, the panel's dial's twin (Panel.swift).
    private static func dial(on page: Widget) {
        let group = group(nil, on: page)
        adw_preferences_group_set_description(ptr(group), "Familiar stays close to where a station started and to songs you know. Adventurous goes further out and plays more that is new to you.")
        let dial = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 1, 0.05)!.css("dial")
        gtk_scale_set_draw_value(ptr(dial), 0)
        dial.named("Adventurousness")
        gtk_range_set_value(ptr(dial), app.settings.adventurousness)
        var counting: Task<Void, Never>?
        on(dial, "value-changed") {
            let value = gtk_range_get_value(ptr(dial))
            guard abs(value - app.settings.adventurousness) > 0.001 else { return }
            app.settings.adventurousness = value
            app.radio.adventurousnessChanged()
            // Counted when the hand lets go (docs/STATS.md), not at every step.
            counting?.cancel()
            counting = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                Stats.track(.dialChanged, ["value": Stats.dial(value)])
            }
        }
        let title = label("Adventurousness")
        gtk_label_set_xalign(ptr(title), 0)
        let adventurous = label("Adventurous", "t13", "fact").expand(horizontal: true)
        gtk_label_set_xalign(ptr(adventurous), 1)
        let ends = hbox(spacing: 8, [label("Familiar", "t13", "fact"), adventurous])
        let box = vbox(spacing: 8, [title, dial, ends])
        gtk_widget_set_margin_top(box, 12)
        gtk_widget_set_margin_bottom(box, 12)
        gtk_widget_set_margin_start(box, 12)
        gtk_widget_set_margin_end(box, 12)
        let row = gtk_list_box_row_new()!
        gtk_list_box_row_set_child(ptr(row), box)
        gtk_list_box_row_set_activatable(ptr(row), 0)
        adw_preferences_group_add(ptr(group), row)
        // Moved in the panel meanwhile: this one follows.
        observe(row) {
            if abs(gtk_range_get_value(ptr(dial)) - app.settings.adventurousness) > 0.001 {
                gtk_range_set_value(ptr(dial), app.settings.adventurousness)
            }
        }
    }

    /// The list of the music kept on this computer, as the Mac's Settings ›
    /// Library: its counts, when it was last read, and Refresh Library.
    private static func library(on page: Widget) {
        let library = app.library
        let group = group(nil, on: page)
        let songs = fact("Songs")
        let albums = fact("Albums")
        let artists = fact("Artists")
        let loaded = fact("Last Loaded")
        for row in [songs, albums, artists, loaded] { adw_preferences_group_add(ptr(group), row) }
        // Under the rows, as Remove All Downloads (libadwaita 1.5 has no
        // button row).
        let refresh = button("Refresh Library") { Task { await library.refresh() } }
            .align(horizontal: GTK_ALIGN_START)
        gtk_widget_set_margin_top(refresh, 12)
        adw_preferences_group_add(ptr(group), refresh)
        observe(group) {
            adw_action_row_set_subtitle(ptr(songs), library.tracks.count.formatted())
            adw_action_row_set_subtitle(ptr(albums), library.albums.count.formatted())
            adw_action_row_set_subtitle(ptr(artists), library.artists.count.formatted())
            loaded.isVisible = library.lastLoaded != nil
            if let lastLoaded = library.lastLoaded {
                adw_action_row_set_subtitle(ptr(loaded), lastLoaded.formatted(.relative(presentation: .named)))
            }
            var failure: String?
            var isLoading = false
            switch library.state {
            case let .loading(progress):
                isLoading = true
                let percent = progress.map { " " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? ""
                gtk_button_set_label(ptr(refresh), "Refreshing Library…" + percent)
            case let .failed(message):
                failure = message
            default:
                break
            }
            if !isLoading { gtk_button_set_label(ptr(refresh), "Refresh Library") }
            gtk_widget_set_sensitive(refresh, isLoading ? 0 : 1)
            // A group's description is Pango markup, and a failure's words
            // can be the server's: escaped, so they show as they are.
            let escaped = g_markup_escape_text(failure ?? "Jukebox keeps a copy of the list of your music, so it opens at once. It reads the server again each time it starts.", -1)
            adw_preferences_group_set_description(ptr(group), escaped)
            g_free(escaped)
        }
    }

    /// What the radio and the mixes learn from, as the Mac's Settings ›
    /// Privacy › History: how many plays, and Clear Listening History,
    /// asked first.
    private static func history(on page: Widget) {
        let history = app.history
        let group = group("History", on: page)
        adw_preferences_group_set_description(ptr(group), "What you play, skip and give a thumbs up or down to is how the radio and your mixes learn your taste. It stays on this computer.")
        let count = fact("Plays Remembered")
        adw_preferences_group_add(ptr(group), count)
        let clear = button("Clear Listening History", "destructive-action") {
            let dialog = adw_alert_dialog_new("Clear your listening history?",
                                              "The radio and your mixes start learning your taste again from your library and favorites. Play counts on the server stay as they are.")!
            adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
            adw_alert_dialog_add_response(ptr(dialog), "clear", "Clear Listening History")
            adw_alert_dialog_set_response_appearance(ptr(dialog), "clear", ADW_RESPONSE_DESTRUCTIVE)
            adw_alert_dialog_set_default_response(ptr(dialog), "cancel")
            adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
            on(raw(dialog), "response", argument: { response in
                guard let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "clear" else { return }
                history.clear()
                // Today's mixes were made from what is now forgotten.
                Task { await app.mixes.rebuild(library: app.library, history: history, settings: app.settings) }
            })
            adw_dialog_present(ptr(dialog), MainWindow.window)
        }.align(horizontal: GTK_ALIGN_START)
        gtk_widget_set_margin_top(clear, 12)
        adw_preferences_group_add(ptr(group), clear)
        observe(group) {
            let plays = history.history.events.count
            adw_action_row_set_subtitle(ptr(count), plays.formatted())
            gtk_widget_set_sensitive(clear, plays > 0 ? 1 : 0)
        }
    }

    /// A row of one fact: its name, and what it is under it.
    private static func fact(_ title: String) -> Widget {
        let row = adw_action_row_new()!
        adw_preferences_row_set_title(ptr(row), title)
        gtk_widget_add_css_class(row, "property")
        return row
    }

    /// A page of the dialog: its name in the view switcher, with its icon,
    /// and `name` for the walk to open it by.
    private static func page(_ name: Page, _ title: String, _ icon: String,
                             in dialog: UnsafeMutablePointer<AdwDialog>) -> Widget {
        let page = adw_preferences_page_new()!
        adw_preferences_page_set_name(ptr(page), name.rawValue)
        adw_preferences_page_set_title(ptr(page), title)
        adw_preferences_page_set_icon_name(ptr(page), icon)
        adw_preferences_dialog_add(ptr(dialog), ptr(page))
        return page
    }

    /// Nil: no title, where the page's own says it.
    private static func group(_ title: String?, on page: Widget) -> Widget {
        let group = adw_preferences_group_new()!
        if let title { adw_preferences_group_set_title(ptr(group), title) }
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
