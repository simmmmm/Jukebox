// The player's bar under the window, in three zones as the desktop's music
// players have it (Spotify, Feishin): the song at the left, the transport
// and where it is in the song in the middle of the window, the volume and
// the panel's buttons at the right. Hidden until there is a song.
//
// It was redrawn for one complaint, the photographer's, 14 November 2026:
// "ook klopt er geen fuck van deze verhoudingen". So the middle is the
// window's middle, whatever the song's title, and the zones keep their
// shares from 760 to 2560 wide (ThreeZones).

import CAdw
import Foundation
import JukeboxKit

enum PlayerBar {
    /// What a narrow window changes (MainWindow's breakpoints): the volume
    /// becomes a button below 900, the times go below 600.
    private(set) static var times: [Widget] = []
    private(set) static var volume: Widget!
    private(set) static var volumeButton: Widget!
    /// The heart and Not This beside the song; below 900 only in its menu.
    private(set) static var songActions: Widget!

    // Measures from the designer's spec (build/design-round/2027/spec.md, §2):
    // 88 tall (12 + Play 40 + 8 + the position 16 + 12), cover 56, buttons
    // 32, Play 40, the times 40 wide.
    static func make() -> Widget {
        // The song, only as wide as its content: the cover and the words
        // open Now Playing.
        let art = Art(56)
        let title = label("", "bar-title")
        let artist = label("", "fact", "bar-fact")
        // On a station, a line of its own under the artist ("Kun je de
        // station naam ergens anders plaatsen?", the photographer, 15
        // November 2026): the template mark 12 and the name in the accent.
        // Each line ends in "…" by itself. Title 20, 4, then the artist and
        // the station 16 each: 56, the cover's height, so the bar stays 88.
        let stationMark = gtk_image_new_from_icon_name(Glyphs.name("radio"))!.css("accent")
        gtk_image_set_pixel_size(ptr(stationMark), 12)
        let stationName = label("", "bar-fact", "accent")
        // As wide as their words, so the links laid over them (below) are too.
        let station = hbox(spacing: 4, [stationMark, stationName]).css("covered").align(horizontal: GTK_ALIGN_START)
        artist.align(horizontal: GTK_ALIGN_START)
        let words = vbox(spacing: 4, [title, vbox([artist, station])]).align(vertical: GTK_ALIGN_CENTER)
        // The tile's own hover, 8 past the cover and the words on every
        // side (Style's button.tile): the bar had taken its padding away, so
        // the hover ended flush on the words ("ik zie een bug", the
        // photographer, 15 November 2026).
        let song = tileButton(hbox(spacing: 12, [art.widget, words])) { NowPlayingPage.open() }
        // The screen it opens is Full Player (the photographer, 15 November
        // 2026), as the panel took the name Now Playing.
        song.tooltip("Full Player").align(vertical: GTK_ALIGN_CENTER)
        // The pointer over the song, a click may follow: Now Playing's sleeve
        // drawn now, at the room's size as it is now (the window may have
        // changed since the song began; a sleeve takes 100 ms or more).
        let hover = gtk_event_controller_motion_new()!
        on(raw(hover), "enter") { NowPlayingPage.prepare() }
        gtk_widget_add_controller(song, hover)
        // The artist's name opens the artist ("je zou hier eigenlijk ook op
        // angele willen kunnen klikken", the photographer, 15 November 2026),
        // as Go to Artist does: the song's first artist, when the library
        // knows them; else the name stays words of the song. On a station
        // its name shows the panel on Up Next, what the station plays next
        // ("ook die oranje link hier zou gewoon 'up next' moeten openen",
        // the same day), and never closes it. Each is a button of its own
        // laid over its words in the song, not one inside the other: the
        // song's button stays the cover and the title.
        let artistLinkName = label("", "fact", "bar-fact")
        let artistLink = link(artistLinkName, over: artist, "Go to Artist") {
            if let ref = app.player.currentTrack?.primaryArtist, let found = app.library.artist(ref) { Pages.open(found) }
        }
        let stationLinkMark = gtk_image_new_from_icon_name(Glyphs.name("radio"))!.css("accent")
        gtk_image_set_pixel_size(ptr(stationLinkMark), 12)
        let stationLinkName = label("", "bar-fact", "accent")
        let stationLink = link(hbox(spacing: 4, [stationLinkMark, stationLinkName]), over: station, "Now Playing") {
            app.panel.show(.upNext)
        }
        let songWithLinks = gtk_overlay_new()!.align(vertical: GTK_ALIGN_CENTER)
        gtk_overlay_set_child(ptr(songWithLinks), song)
        gtk_overlay_add_overlay(ptr(songWithLinks), artistLink)
        gtk_overlay_add_overlay(ptr(songWithLinks), stationLink)
        g_signal_connect_data(raw(songWithLinks), "get-child-position", unsafeBitCast(placeLink, to: GCallback.self), nil, nil, GConnectFlags(0))
        contextMenu(on: songWithLinks) { songMenu() }
        // Not This on a station, then the heart (32 each, 4 apart).
        let notThis = iconButton(Glyphs.name("not-this"), "Not This", "flat") {
            if let track = app.player.currentTrack { app.radio.dislike(track) }
        }
        let heart = heartButton { app.player.currentTrack.map { .track($0.id) } }
        songActions = hbox(spacing: 4, [notThis, heart]).align(vertical: GTK_ALIGN_CENTER)
        // Its own width, down to its zone's: then the title ends in "…"
        // rather than push the middle aside.
        let songZone = hbox(spacing: 16, [songWithLinks, songActions]).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
        songZone.margins(horizontal: 16)

        // The transport, over where it is in the song. Play keeps
        // libadwaita's own fill, never the accent: the page's Play is the
        // one filled button.
        let previous = iconButton("media-skip-backward-symbolic", "Previous", "flat") { app.player.previous() }
        let play = iconButton("media-playback-start-symbolic", "Play", "circular", "play") { app.player.togglePlayPause() }
        let next = iconButton("media-skip-forward-symbolic", "Next", "flat") { app.player.next() }
        // Shuffle and repeat flank the transport, as every desktop player
        // has them ("mis ook nog repeat, repeat all en shuffle", 14 November
        // 2026): lit in the accent while on. A station chooses its own
        // order, so there they rest, dimmed.
        let shuffle = gtk_toggle_button_new()!.css("flat", "mode").named("Shuffle")
        gtk_button_set_icon_name(ptr(shuffle), "media-playlist-shuffle-symbolic")
        var isSettingMode = false
        on(shuffle, "toggled") { if !isSettingMode { app.player.toggleShuffle() } }
        let again = iconButton("media-playlist-repeat-symbolic", "Repeat", "flat", "mode") { app.player.cycleRepeat() }
        let transport = hbox(spacing: 16, [shuffle, previous, play, next, again]).align(horizontal: GTK_ALIGN_CENTER)
        observe(transport) {
            let player = app.player
            let station = player.context?.isRadio == true
            shuffle.isSensitive = player.hasTrack && !station
            again.isSensitive = player.hasTrack && !station
            isSettingMode = true
            gtk_toggle_button_set_active(ptr(shuffle), player.isShuffled ? 1 : 0)
            isSettingMode = false
            if player.isShuffled { gtk_widget_add_css_class(shuffle, "accent") } else { gtk_widget_remove_css_class(shuffle, "accent") }
            setIcon(again, player.repeatMode == .one ? "media-playlist-repeat-song-symbolic" : "media-playlist-repeat-symbolic")
            if player.repeatMode == .off { gtk_widget_remove_css_class(again, "accent") } else { gtk_widget_add_css_class(again, "accent") }
            again.tooltip(station ? "The station chooses the order"
                          : player.repeatMode == .off ? "Repeat" : player.repeatMode == .all ? "Repeat All" : "Repeat One")
            shuffle.tooltip(station ? "The station chooses the order" : "Shuffle")
        }

        let elapsed = label("0:00", "fact", "times", "bar-fact").size(width: 40)
        let total = label("0:00", "fact", "times", "bar-fact").size(width: 40)
        gtk_label_set_xalign(ptr(elapsed), 1)
        times = [elapsed, total]
        let scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 1, 1)!
        gtk_scale_set_draw_value(ptr(scale), 0)
        scale.expand(horizontal: true).named("Position")
        // The listener's hand on the slider, as against the song moving it:
        // a drag seeks once it rests, not at every step of the way.
        var isSetting = false
        var seekTask: Task<Void, Never>?
        on(scale, "value-changed") {
            guard !isSetting else { return }
            let target = gtk_range_get_value(ptr(scale))
            setText(elapsed, clock(target))
            seekTask?.cancel()
            seekTask = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                app.player.seek(to: target)
                seekTask = nil
            }
        }
        let position = hbox(spacing: 8, [elapsed, scale, total])
        let middle = vbox(spacing: 8, [transport, position]).align(vertical: GTK_ALIGN_CENTER)

        // The tools: the panel's two buttons (Panel.swift), then the level;
        // below 900 the level is a button with the slider in its popover.
        let lyrics = panelButton("media-view-subtitles-symbolic", "Lyrics", .lyrics)
        // The panel is Now Playing ("moet up next niet trouwens gewoon 'now
        // playing' worden", the photographer, 15 November 2026).
        let upNext = panelButton("view-list-ordered-symbolic", "Now Playing", .upNext)
        let (speaker, level) = (gtk_image_new_from_icon_name("audio-volume-high-symbolic")!, levelScale(width: 96))
        volume = hbox(spacing: 8, [speaker, level])
        gtk_widget_set_margin_start(volume, 8)
        let popover = gtk_popover_new()!
        gtk_popover_set_child(ptr(popover), levelScale(width: 160).margins(8))
        volumeButton = gtk_menu_button_new()!.css("flat").named("Volume")
        gtk_menu_button_set_popover(ptr(volumeButton), popover)
        volumeButton.isVisible = false
        gtk_widget_set_margin_start(volumeButton, 8)
        // Lyrics shows only where there are lyrics to be had (the server's,
        // or LRCLIB's when Preferences allow it), as on the iPhone.
        observe(lyrics) { lyrics.isVisible = lyricsToBeHad() }
        // Off for a song with none, once that is known (Panel.swift); the
        // song playing asked for here, so the button knows.
        observe(lyrics) { gtk_widget_set_sensitive(lyrics, songHasNoLyrics() ? 0 : 1) }
        var asked: String?
        observe(lyrics) {
            let online = app.settings.findLyricsOnline
            guard lyricsToBeHad(), let server = app.server, let track = app.player.currentTrack,
                  "\(track.id)\(online)" != asked else { return }
            asked = "\(track.id)\(online)"
            LyricsFinder.shared.prefetch(track, server: server, online: online)
        }
        let tools = hbox(spacing: 8, [NotCountedUI.sign(), lyrics, upNext, playOnButton(), volume, volumeButton]).align(horizontal: GTK_ALIGN_END, vertical: GTK_ALIGN_CENTER)
        tools.margins(horizontal: 16)

        let bar = ThreeZones.make(songZone, middle, tools).css("player-bar")
        observe(bar) {
            let player = app.player
            let track = player.currentTrack
            bar.isVisible = track != nil
            art.show(track?.artwork, sleeve: track.map(TitleSleeve.Words.init(track:)))
            setText(title, track?.name ?? "")
            let line = track?.artistLine ?? ""
            setText(artist, line)
            setText(artistLinkName, line)
            let opensArtist = !line.isEmpty && track?.primaryArtist.flatMap { app.library.artist($0) } != nil
            artistLink.isVisible = opensArtist
            if opensArtist { gtk_widget_add_css_class(artist, "covered") } else { gtk_widget_remove_css_class(artist, "covered") }
            let onStation = player.context?.station
            station.isVisible = onStation != nil
            stationLink.isVisible = onStation != nil
            setText(stationName, onStation?.title ?? "")
            setText(stationLinkName, onStation?.title ?? "")
            notThis.isVisible = onStation != nil
            let disliked = track.map { app.radio.disliked.contains($0.id) } ?? false
            if disliked { gtk_widget_add_css_class(notThis, "given") } else { gtk_widget_remove_css_class(notThis, "given") }
            setIcon(play, player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic")
            play.named(player.isPlaying ? "Pause" : "Play")
        }
        observe(speaker) {
            let icon = app.player.volume == 0 ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
            gtk_image_set_from_icon_name(ptr(speaker), icon)
            gtk_menu_button_set_icon_name(ptr(volumeButton), icon)
        }
        // The clock apart: it moves twice a second, the rest when a song does.
        observe(scale) {
            let player = app.player
            setText(total, clock(player.duration))
            guard seekTask == nil else { return }
            isSetting = true
            gtk_range_set_range(ptr(scale), 0, max(1, player.duration))
            gtk_range_set_value(ptr(scale), player.elapsed)
            isSetting = false
            setText(elapsed, clock(player.elapsed))
        }
        return bar
    }

    /// A button of words laid over `words` in the song (placeLink), at
    /// their place and size: the same words, so they line up and end in
    /// "…" where those do. The words under it are not drawn while it shows
    /// (Style's `covered`).
    private static func link(_ content: Widget, over words: Widget, _ name: String,
                             action: @escaping @MainActor () -> Void) -> Widget {
        let button = gtk_button_new()!.css("bar-link").tooltip(name)
        gtk_button_set_child(ptr(button), content)
        g_object_set_data(ptr(raw(button)), "jukebox-over", raw(words))
        on(button, "clicked", action)
        return button
    }

    /// The song's overlay places each link where its words are, once the
    /// song's button is laid out (the overlay lays out its child first).
    private static let placeLink: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                                  UnsafeMutablePointer<GdkRectangle>?, UnsafeMutableRawPointer?) -> gboolean = { overlay, link, place, _ in
        guard let overlay, let link, let place,
              let words = g_object_get_data(ptr(link), "jukebox-over") else { return 0 }
        var bounds = graphene_rect_t()
        guard gtk_widget_compute_bounds(ptr(words), ptr(overlay), &bounds) != 0 else { return 0 }
        place.pointee = GdkRectangle(x: Int32(bounds.origin.x.rounded()), y: Int32(bounds.origin.y.rounded()),
                                     width: Int32(bounds.size.width.rounded()), height: Int32(bounds.size.height.rounded()))
        return 1
    }

    /// The song's menu, the bar's right-click and Full Player's ⋮: every
    /// song's menu (`trackMenu`), its first section the station's lessons
    /// while a station plays. The heart and Not This are in it at every
    /// width, though the bar has them as buttons when wide: the same menu
    /// as everywhere else ("Los ze op", the photographer, 20 November 2026).
    static func songMenu() -> [(String, () -> Void)] {
        guard let track = app.player.currentTrack else { return [] }
        var station: [(String, () -> Void)] = []
        if app.player.context?.isRadio == true {
            station = [(app.radio.liked.contains(track.id) ? "Liked" : "More Like This", { app.radio.like(track) }),
                       (app.radio.disliked.contains(track.id) ? "Not This (Undo)" : "Not This", { app.radio.dislike(track) })]
        }
        return trackMenu([track], place: station)
    }

    /// The listener's level, 0 to 1, as the player keeps it.
    private static func levelScale(width: Int32) -> Widget {
        let level = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 1, 0.05)!.css("level")
        gtk_scale_set_draw_value(ptr(level), 0)
        level.size(width: width).named("Volume")
        var isSetting = false
        // Playing elsewhere, the device's own level (PlayOn.swift).
        on(level, "value-changed") {
            guard !isSetting else { return }
            let value = gtk_range_get_value(ptr(level))
            if app.player.playsOn != nil { app.player.setRemoteVolume(value) } else { app.player.volume = value }
        }
        observe(level) {
            let value = app.player.playsOn != nil ? app.player.remoteVolume ?? 1 : app.player.volume
            isSetting = true
            gtk_range_set_value(ptr(level), value)
            isSetting = false
        }
        return level
    }

    /// Where the music plays (PlayOn.swift): this computer, a Chromecast, the
    /// user's other Jellyfin clients, the server's jukebox. Where the Mac's
    /// bar has AirPlay, 1:1, and the only such control: no button more
    /// ("ik wil alleen er voor waken dat we niet 10000 knopen krijgen", the
    /// photographer, 17 November 2026). The list looks only while it is
    /// open; the glyph is in the accent while the music plays elsewhere.
    /// Once, before an account's first cast that hands the device its key
    /// (PlayOn.needsKeyNotice): the iPhone's alert, as GNOME's dialog.
    private static func askKeyNotice() {
        typealias Words = PlayOn.KeyNoticeWords
        let dialog = adw_alert_dialog_new(Words.title, Words.body)!
        adw_alert_dialog_add_response(ptr(dialog), "cancel", Words.cancel)
        adw_alert_dialog_add_response(ptr(dialog), "cast", Words.castAnyway)
        adw_alert_dialog_set_default_response(ptr(dialog), "cancel")
        adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
        on(raw(dialog), "response", argument: { response in
            if let response, String(cString: response.assumingMemoryBound(to: CChar.self)) == "cast" {
                app.player.playOn.castAnyway()
            } else {
                app.player.playOn.cancelKeyNotice()
            }
        })
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    private static func playOnButton() -> Widget {
        // A menu as libadwaita draws one ("dit staat niet netjes", the
        // photographer, 19 November 2026): the popover's `menu` style, whose
        // list rows are a menu's own (32 high, 12 in from the 6 around them,
        // rounded, lit on hover), so the heading and every row's text start
        // on one edge, 18 in, and the check sits at the row's end.
        let rows = gtk_list_box_new()!
        gtk_list_box_set_selection_mode(ptr(rows), GTK_SELECTION_NONE)
        let heading = label("Play On", "heading").align(horizontal: GTK_ALIGN_START).margins(horizontal: 12, vertical: 6)
        let popover = gtk_popover_new()!.css("menu")
        gtk_popover_set_child(ptr(popover), vbox([heading, rows]).margins(6))
        let button = gtk_menu_button_new()!.css("flat").named("Play On")
        gtk_menu_button_set_icon_name(ptr(button), Glyphs.name("play-on"))
        gtk_menu_button_set_popover(ptr(button), popover)
        on(raw(popover), "show") { app.player.playOn.look() }
        on(raw(popover), "closed") { app.player.playOn.stopLooking() }
        // Each row's device, by its place in the list.
        var shown: [PlayOnDevice?] = []
        // After the popover has closed: the choice remakes these rows, this
        // one among them.
        on(raw(rows), "row-activated", argument: { row in
            guard let row else { return }
            let index = Int(gtk_list_box_row_get_index(ptr(row)))
            guard shown.indices.contains(index) else { return }
            let device = shown[index]
            gtk_popover_popdown(ptr(popover))
            Task {
                app.player.playOn.choose(device)
                if app.player.playOn.pendingKeyNotice != nil { Self.askKeyNotice() }
            }
        })
        // The rows change in the open popover, which stays open: a menu made
        // again would close under the pointer (the sleep timer's).
        observe(rows) {
            gtk_list_box_remove_all(ptr(rows))
            let player = app.player
            var devices = player.playOn.devices
            if let elsewhere = player.playsOn, !devices.contains(elsewhere) { devices.insert(elsewhere, at: 0) }
            shown = [nil] + devices
            let choices: [(String, String?)] = [("This Computer", nil)] + devices.map { ($0.name, $0.detail) }
            for (index, (name, detail)) in choices.enumerated() {
                let check = gtk_image_new_from_icon_name("object-select-symbolic")!
                gtk_widget_set_opacity(check, shown[index]?.id == player.playsOn?.id ? 1 : 0)
                var lines = [label(name).align(horizontal: GTK_ALIGN_START)]
                if let detail { lines.append(label(detail, "dim-label", "caption").align(horizontal: GTK_ALIGN_START)) }
                let row = gtk_list_box_row_new()!
                gtk_list_box_row_set_child(ptr(row), hbox(spacing: 12, [
                    vbox(lines).expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER).margins(vertical: detail == nil ? 0 : 6),
                    check,
                ]))
                gtk_list_box_append(ptr(rows), row)
            }
            if player.playOn.devices.isEmpty {
                // Said as a row is, on the same edge, but no choice.
                let row = gtk_list_box_row_new()!
                gtk_list_box_row_set_activatable(ptr(row), 0)
                gtk_list_box_row_set_child(ptr(row), label("Looking for devices on this network", "dim-label").align(horizontal: GTK_ALIGN_START))
                gtk_list_box_append(ptr(rows), row)
            }
        }
        observe(button) {
            if app.player.playsOn != nil { gtk_widget_add_css_class(button, "accent") } else { gtk_widget_remove_css_class(button, "accent") }
        }
        return button
    }

    /// One of the panel's buttons: lit (pressed, the glyph in the accent)
    /// while the panel shows its content; pressed then, it closes the panel.
    private static func panelButton(_ icon: String, _ name: String, _ content: PanelState.Content) -> Widget {
        let toggle = gtk_toggle_button_new()!.css("flat").named(name)
        gtk_button_set_icon_name(ptr(toggle), icon)
        var isSetting = false
        on(toggle, "toggled") { if !isSetting { app.panel.toggle(content) } }
        observe(toggle) {
            let shown = app.panel.isShown && app.panel.content == content
            isSetting = true
            gtk_toggle_button_set_active(ptr(toggle), shown ? 1 : 0)
            isSetting = false
        }
        return toggle
    }
}

/// Three zones in a row: the middle one a share of the row, in the row's
/// own middle; the two outer ones what is left, half each. So the middle is
/// the window's middle and not the middle of the room the song's title
/// leaves. The widths are DesktopMeasures.zones (Jukebox/Components), the
/// iPad's and the Mac's bar's too. Narrower than the outer zones' least
/// allows (below 600, where the spec has the iPhone's mini player, not
/// built yet), the middle gives way, down to its own least.
nonisolated enum ThreeZones {
    @MainActor static func make(_ start: Widget, _ middle: Widget, _ end: Widget) -> Widget {
        // A box for its children; laid out by the functions below.
        let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_set_layout_manager(row, gtk_custom_layout_new(nil, measure, allocate))
        for zone in [start, middle, end] { gtk_box_append(ptr(row), zone) }
        return row
    }

    private static func zones(_ row: Widget) -> [Widget] {
        var found: [Widget] = []
        var child = gtk_widget_get_first_child(row)
        while let zone = child {
            found.append(zone)
            child = gtk_widget_get_next_sibling(zone)
        }
        return found
    }

    private static func size(_ zone: Widget, _ orientation: GtkOrientation) -> (least: Int32, natural: Int32) {
        var least: Int32 = 0, natural: Int32 = 0
        gtk_widget_measure(zone, orientation, -1, &least, &natural, nil, nil)
        return (least, natural)
    }

    private static let measure: GtkCustomMeasureFunc = { row, orientation, _, least, natural, leastBaseline, naturalBaseline in
        leastBaseline?.pointee = -1
        naturalBaseline?.pointee = -1
        guard let row else { return }
        let all = zones(row)
        guard all.count == 3 else { return }
        let sizes = all.map { size($0, orientation) }
        if orientation == GTK_ORIENTATION_HORIZONTAL {
            // The children's own least, not the 304: the window's least is 360.
            least?.pointee = 2 * max(sizes[0].least, sizes[2].least) + sizes[1].least
            natural?.pointee = 2 * max(sizes[0].natural, sizes[2].natural) + max(sizes[1].natural, Int32(DesktopMeasures.middleLeast))
        } else {
            least?.pointee = sizes.map(\.least).max() ?? 0
            natural?.pointee = sizes.map(\.natural).max() ?? 0
        }
    }

    private static let allocate: GtkCustomAllocateFunc = { row, width, height, _ in
        guard let row else { return }
        let all = zones(row)
        guard all.count == 3 else { return }
        let side = max(size(all[0], GTK_ORIENTATION_HORIZONTAL).least, size(all[2], GTK_ORIENTATION_HORIZONTAL).least)
        let widths = DesktopMeasures.zones(width: Int(width), sides: Int(side),
                                           middle: Int(size(all[1], GTK_ORIENTATION_HORIZONTAL).least))
        let start = Int32(widths.start), middle = Int32(widths.middle)
        place(all[0], x: 0, width: start, height: height)
        place(all[1], x: start, width: middle, height: height)
        place(all[2], x: start + middle, width: Int32(widths.end), height: height)
    }

    private static func place(_ zone: Widget, x: Int32, width: Int32, height: Int32) {
        var box = GtkAllocation(x: x, y: 0, width: max(0, width), height: height)
        gtk_widget_size_allocate(zone, &box, -1)
    }
}

/// Now Playing: a room over the places and the page (the designer's spec,
/// §6), opened from the bar's song and closed by its chevron or Escape. The bar and the panel stay as they were, open or not, and lose
/// their own ground over it: the bar is the transport, and what plays next
/// and the words are the panel's. Always dark, as on the iPhone; in Glow
/// (the photographer chose the one accent over the cover's own).
enum NowPlayingPage {
    private static var stack: Widget!
    private static var header: Widget!
    private static var down: Widget!
    /// ⋮ at the header's end (the screenshot walk opens it too).
    private(set) static var more: Widget!
    private static var sleeve: SleeveArt!
    /// The sleeve's share of the room's height (472 at 1440 × 900).
    private static let sleeveShare = 0.62
    /// Opened, and waiting a moment for the sleeve to be drawn.
    private static var isWaiting = false

    /// The sleeve is drawn for the song, at the room's size (the
    /// screenshot walk's check on the transition).
    static var isSleeveDrawn: Bool { sleeve.isReady }

    static var isOpen: Bool {
        guard let stack, let name = gtk_stack_get_visible_child_name(ptr(stack)) else { return false }
        return String(cString: name) == "now-playing"
    }

    /// The room's stack: the library under, Now Playing over it. One fades
    /// into the other in 200 ms, both ways ("de transitie op linux iig is
    /// niet heel nice nu", 14 November 2026); the whole room sliding up over
    /// the window was abrupt. GtkStack leaves it out where the desktop asks
    /// for no animations.
    static func room(over library: Widget) -> Widget {
        stack = gtk_stack_new()!
        gtk_stack_set_transition_type(ptr(stack), GTK_STACK_TRANSITION_TYPE_CROSSFADE)
        gtk_stack_set_transition_duration(ptr(stack), 200)
        gtk_stack_add_named(ptr(stack), library, "library")
        gtk_stack_add_named(ptr(stack), make(), "now-playing")
        gtk_stack_set_visible_child_name(ptr(stack), "library")
        return stack
    }

    static func open() {
        guard !isOpen, !isWaiting else { return }
        Stats.track(.screen, ["name": "now_playing"])
        prepare()
        if sleeve.isReady { return appear() }
        // Not drawn yet (the window resized since, a song just begun): the
        // room waits for its sleeve rather than fade in without it. A third
        // of a second at most: a cover slow to come from the server is not
        // waited for.
        isWaiting = true
        Task {
            for _ in 0..<20 where isWaiting && !sleeve.isReady { try? await Task.sleep(for: .milliseconds(16)) }
            guard isWaiting else { return }
            isWaiting = false
            appear()
        }
    }

    static func close() {
        isWaiting = false
        guard isOpen else { return }
        gtk_stack_set_visible_child_name(ptr(stack), "library")
        ground()
    }

    private static func appear() {
        gtk_stack_set_visible_child_name(ptr(stack), "now-playing")
        ground()
        // The keys inside the room, so Escape closes it.
        gtk_widget_grab_focus(down)
    }

    /// The sleeve's side in a room of `width` by `height`: 0.62 of its
    /// height, with the pair and 24 either side within its width, on the
    /// grid.
    private static func sleeveSide(width: Double, height: Double) -> Double {
        let fits = (width - 48 - Double(SleeveLayout.recordBeyond)) / (1 + Double(SleeveLayout.recordSide) / 2)
        return Double(Int(min(height * sleeveShare, fits)) / 4 * 4)
    }

    /// The sleeve drawn ahead, at the size the room will give it. The room
    /// is laid out only while it shows, so its size is the stack's, less
    /// its header.
    static func prepare() {
        var headerHeight: Int32 = 0
        gtk_widget_measure(header, GTK_ORIENTATION_VERTICAL, -1, nil, &headerHeight, nil, nil)
        let side = sleeveSide(width: Double(gtk_widget_get_width(stack)), height: Double(gtk_widget_get_height(stack) - headerHeight))
        if side >= 120 { sleeve.resize(side) }
        sleeve.show(app.player.currentTrack)
    }

    /// The room's ground: dark whatever the system's appearance while it is
    /// open, the bar's and the docked panel's own gone (Style's `in-room`).
    /// Lying over the page, the panel keeps its ground: the room shows
    /// under it otherwise.
    /// The sleep timer, a moon beside ⋮, as the iPhone's and the Mac's
    /// (Jukebox/NowPlaying/SleepTimerMenu.swift): before it the time left,
    /// or what it waits for ("End of Album"). The timer is the queue's.
    private static func sleepTimer() -> Widget {
        let left = label("", "t15", "times")
        let moon = gtk_image_new_from_icon_name("weather-clear-night-symbolic")!
        let button = gtk_menu_button_new()!.css("flat").named("Sleep Timer")
        gtk_menu_button_set_child(ptr(button), hbox(spacing: 8, [left, moon]))
        // The words apart from the menu: they change every second, and the
        // menu, made again, would close under the pointer.
        observe(left) {
            let player = app.player
            if let seconds = player.sleepLeft {
                setText(left, clock(seconds))
            } else {
                setText(left, player.sleepChoice.map(player.sleepTitle) ?? "")
            }
            left.isVisible = player.sleepChoice != nil
        }
        observe(button) {
            let player = app.player
            var items: [(String, () -> Void)] = player.sleepChoices.map { choice in
                (player.sleepTitle(choice), { app.player.setSleepTimer(choice) })
            }
            // Off only while it runs; the words before the moon say which.
            if player.sleepChoice != nil { items.insert(("Off", { app.player.setSleepTimer(nil) }), at: 0) }
            gtk_menu_button_set_popover(ptr(button), popoverMenu(items))
        }
        return button
    }

    private static func ground() {
        guard let window = MainWindow.window else { return }
        let open = isOpen
        adw_style_manager_set_color_scheme(adw_style_manager_get_default(), open ? ADW_COLOR_SCHEME_FORCE_DARK : ADW_COLOR_SCHEME_DEFAULT)
        for (name, on) in [("in-room", open), ("room-docked", open && !app.panel.isOverlaid)] {
            if on { gtk_widget_add_css_class(window, name) } else { gtk_widget_remove_css_class(window, name) }
        }
    }

    private static func make() -> Widget {
        // The sleeve with its record half out, still (Drawings.swift), at
        // 0.62 of the room's height.
        sleeve = SleeveArt(side: 300)
        let sleeve = sleeve!
        let title = label("", "serif", "page-title", lines: 2)
        let artist = label("", "t17", "fact", lines: 2)
        // Where it plays, when not here: one quiet line (PlayOn.swift).
        let elsewhere = label("", "t15", "dim-label")
        gtk_widget_set_margin_top(elsewhere, 8)
        observe(elsewhere) {
            let device = app.player.playsOn
            setText(elsewhere, device.map { "Playing on \($0.name)" } ?? "")
            elsewhere.isVisible = device != nil
        }
        // "Lossless" when the song is heard as its lossless file is
        // (PlayQueue.playsLossless): "als originals lossless zijn dat we dat
        // tonen als je gaat streamen" (the photographer, 24 November 2026).
        // A fact of the sound, quiet; its line is always there, only seen
        // or not, so the centred sleeve never moves for it.
        let lossless = label("Lossless", "t15", "fact")
        gtk_widget_set_margin_top(lossless, 8)
        observe(lossless) { gtk_widget_set_opacity(lossless, app.player.playsLossless ? 1 : 0) }
        // As wide as the sleeve and its record, not wider: the words start
        // at the sleeve's left edge.
        for words in [title, artist, lossless, elsewhere] { gtk_label_set_max_width_chars(ptr(words), 1) }
        gtk_widget_set_margin_top(title, 32)
        let content = vbox([sleeve.widget, title, artist, lossless, elsewhere]).align(horizontal: GTK_ALIGN_CENTER, vertical: GTK_ALIGN_CENTER)

        // The room itself, flat (the land under it is not built: whether it
        // turns is the photographer's to say); its size sets the sleeve's.
        let room = gtk_drawing_area_new()!.expand(horizontal: true, vertical: true)
        on(raw(room), "resize") {
            let side = sleeveSide(width: Double(gtk_widget_get_width(room)), height: Double(gtk_widget_get_height(room)))
            // Told while the room is allocated: drawn after it.
            if side >= 120, side != sleeve.side { Task { sleeve.resize(side) } }
        }
        let overlay = gtk_overlay_new()!
        gtk_overlay_set_child(ptr(overlay), room)
        gtk_overlay_add_overlay(ptr(overlay), content)

        down = iconButton("go-down-symbolic", "Close Full Player", "flat") { close() }
        // ⋮: the song's menu, made as it opens (the song and the window's
        // width decide it), under the button.
        more = iconButton("view-more-symbolic", "More", "flat") {
            showMenu(at: more, x: Double(gtk_widget_get_width(more)) / 2, y: Double(gtk_widget_get_height(more)),
                     PlayerBar.songMenu())
        }
        header = adw_header_bar_new()!
        adw_header_bar_set_show_title(ptr(header), 0)
        adw_header_bar_pack_start(ptr(header), down)
        adw_header_bar_pack_end(ptr(header), more)
        adw_header_bar_pack_end(ptr(header), sleepTimer())
        let page = adw_toolbar_view_new()!
        adw_toolbar_view_add_top_bar(ptr(page), header)
        adw_toolbar_view_set_content(ptr(page), overlay)
        let keys = gtk_shortcut_controller_new()!
        gtk_shortcut_controller_add_shortcut(ptr(keys), gtk_shortcut_new(gtk_shortcut_trigger_parse_string("Escape"),
                                                                     gtk_named_action_new("app.close-now-playing")))
        gtk_widget_add_controller(page, ptr(keys))

        observe(content) {
            let track = app.player.currentTrack
            // Each song's sleeve is drawn as it begins, open or not, so the
            // room comes up with it.
            prepare()
            setText(title, track?.name ?? "Nothing playing")
            setText(artist, [track?.artistLine, track?.albumName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            // Nothing playing (the queue ended, or signed out): down again.
            if track == nil { close() }
        }
        // The panel docking or lying over while the room is open.
        observe(page) {
            _ = app.panel.isOverlaid
            ground()
        }
        return page
    }
}
