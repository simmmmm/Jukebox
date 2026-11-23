// The panel at the window's right: what plays next, or the song's words.
// The photographer, 14 November 2026, of Feishin: "persoonlijk vind ik het
// heel Nice wat [Feishin] heeft gedaan dat in je een paneel lyrics en de
// playlist kan bekijken. Als optionele toevoegingen. Wat wij echter niet
// moeten doen is het een hele drukke app maken" — so it is closed until
// asked for, opened and closed from the player's bar (the lit button is the
// one shown, and pressed again it closes), and remembered. Beside the page
// in a wide window, over it in a narrow one (MainWindow).

import CAdw
import Foundation
import JukeboxKit

// Whether the panel is open and on what: PanelState (Jukebox/App), shared
// with the iPad and the Mac.

/// Whether there are lyrics to be had at all: the server's (Jellyfin 10.9
/// and later, Navidrome), or LRCLIB's when Preferences allow it. Without,
/// no Lyrics button and no Lyrics tab, as on the iPhone.
func lyricsToBeHad() -> Bool {
    app.can(.lyrics) || app.settings.findLyricsOnline
}

/// Whether the song playing is known to have no lyrics: the bar's Lyrics
/// button and the panel's tab off, as on the iPhone and the Mac: "Kan je t
/// knoppie gewoon disablen toch?" (the photographer, 21 November 2026).
func songHasNoLyrics() -> Bool {
    LyricsFinder.shared.hasNone(app.player.currentTrack, online: app.settings.findLyricsOnline)
}

enum Panel {
    /// The panel's own page: its header bar (48) with the two tabs at the
    /// start and the window's buttons at the end while it is open, over Up
    /// next or the lyrics. No close button: the lit button in the bar is the
    /// way out (spec §3).
    static func make() -> Widget {
        let stack = gtk_stack_new()!
        gtk_stack_set_transition_type(ptr(stack), GTK_STACK_TRANSITION_TYPE_CROSSFADE)
        gtk_stack_set_transition_duration(ptr(stack), 150)
        gtk_stack_add_named(ptr(stack), UpNext.make(), PanelState.Content.upNext.rawValue)
        gtk_stack_add_named(ptr(stack), LyricsPanel.make(), PanelState.Content.lyrics.rawValue)
        // The panel's name, Now Playing ("moet up next niet trouwens gewoon
        // 'now playing' worden", the photographer, 15 November 2026), in
        // header capitals as a control and the Mac's tab (SYSTEM.md); its
        // list's own headings ("Up next", "Then") stay.
        let upNext = tab("Now Playing", .upNext)
        let lyrics = tab("Lyrics", .lyrics)
        // One group: pressing the pressed tab leaves it pressed.
        gtk_toggle_button_set_group(ptr(lyrics), ptr(upNext))
        let header = adw_header_bar_new()!
        adw_header_bar_set_show_title(ptr(header), 0)
        adw_header_bar_pack_start(ptr(header), hbox(spacing: 4, [upNext, lyrics]))
        let page = adw_toolbar_view_new()!
        adw_toolbar_view_add_top_bar(ptr(page), header)
        adw_toolbar_view_set_content(ptr(page), stack)
        observe(stack) {
            // No lyrics to be had: Up next, and no Lyrics tab. None for
            // this song, once that is known: Up next, and the tab off.
            let available = lyricsToBeHad()
            let none = songHasNoLyrics()
            if (!available || none) && app.panel.content == .lyrics { app.panel.content = .upNext }
            lyrics.isVisible = available
            gtk_widget_set_sensitive(lyrics, none ? 0 : 1)
            gtk_stack_set_visible_child_name(ptr(stack), app.panel.content.rawValue)
        }
        // Which is looked at (docs/STATS.md, `screen`), each time one is
        // shown, as the iPhone counts its queue and its lyrics.
        var counted: PanelState.Content?
        observe(page) {
            guard app.panel.isShown else {
                counted = nil
                return
            }
            let content = app.panel.content
            guard content != counted else { return }
            counted = content
            Stats.track(.screen, ["name": content == .upNext ? "queue" : "lyrics"])
        }
        return page
    }

    /// A tab of the panel's header: libadwaita's pressed fill and the words
    /// in full when chosen, at 60 % when not.
    private static func tab(_ title: String, _ content: PanelState.Content) -> Widget {
        let tab = gtk_toggle_button_new_with_label(title)!.css("flat", "panel-tab")
        var isSetting = false
        on(tab, "toggled") {
            guard !isSetting, gtk_toggle_button_get_active(ptr(tab)) != 0 else { return }
            app.panel.content = content
        }
        observe(tab) {
            isSetting = true
            gtk_toggle_button_set_active(ptr(tab), app.panel.content == content ? 1 : 0)
            isSetting = false
        }
        return tab
    }
}

/// Up next: where the music comes from at the top (an album's cover and
/// title with Shuffle and Repeat beside them, or the station with its dial),
/// a hairline, then the song playing and the ones to come in one list, and
/// on a station why the radio chose each, here and nowhere else (tells.md
/// 5). The designer's spec, §3: shuffle, repeat and the dial sit next to the
/// list they change. Its rows are UpNextList's (Jukebox/NowPlaying), shared
/// with the iPad and the Mac; drawn here as numbered rows of 48 for an album
/// or playlist, rows of 64 with their cover for songs queued from
/// elsewhere, rows of 72 with the reason on a station.
enum UpNext {
    typealias Item = UpNextList.Item

    static func make() -> Widget {
        let head = vbox([albumHead(), stationHead()]).margins(horizontal: 16)
        gtk_widget_set_margin_top(head, 8)
        let rule = hairline().margins(horizontal: 16)
        gtk_widget_set_margin_top(rule, 16)
        // One GtkListView, so it makes only the rows on screen however long
        // the queue (shuffled Songs puts the whole library up next).
        // Songs to come picked with Ctrl and Shift, as a page's
        // (TrackPicks), for the menu on all of them. By place, so they go
        // when the list's songs do.
        weak var made: ItemList<Item, UpNextRow>?
        let picked = PickedRows { [] }
        // A click plays, as a tap does on the iPhone and the Mac: it was a
        // double-click here, and a click did nothing ("hier zie je dat ik
        // niet kan klikken", the photographer, 24 November 2026). A second
        // click within half a second is the double-click of habit, not a
        // second skip: the list has moved under the pointer by then.
        var lastPlay = ContinuousClock.now - .seconds(1)
        let list = ItemList<Item, UpNextRow>(
            make: {
                let row = UpNextRow(picked: picked) { made?.items ?? [] }
                return (row.widget, row)
            },
            fill: { row, item, index in
                row.position = index
                row.show(item)
            },
            activate: { item, _, _ in
                guard ContinuousClock.now - lastPlay > .milliseconds(500) else { return }
                if case let .song(entry, _, _, playing, _) = item, !playing {
                    lastPlay = .now
                    app.player.skip(to: entry)
                }
            })
        list.activatable = { item in
            if case let .song(_, _, _, playing, _) = item { return !playing }
            return false
        }
        made = list
        keep(picked, on: raw(list.widget), as: "picked")
        list.widget.css("queue")
        // The list must be the scroller's own to make only the rows on
        // screen.
        let scroller = scrolled(list.widget).expand(vertical: true)
        var shown: [String] = []
        observe(list.widget) {
            let now = items()
            let keys = now.map(key)
            if keys != shown { picked.picks.clear() }
            shown = keys
            list.set(now)
        }
        return vbox([head, rule, scroller])
    }

    /// A row's song and whether it plays: the same keys, the same places.
    private static func key(_ item: Item) -> String {
        if case let .song(entry, _, _, playing, _) = item { return playing ? "\(entry.id)*" : "\(entry.id)" }
        return ""
    }

    /// What the list shows, in the order it plays.
    private static func items() -> [Item] {
        let player = app.player
        return UpNextList.items(current: player.current, upNext: player.upNext, context: player.context,
                                currentIndex: player.currentIndex, added: player.addedIDs,
                                autoplay: app.settings.autoplay, repeatMode: player.repeatMode,
                                played: player.played)
    }

    /// The panel's head, as UpNextList has it.
    private static func head() -> UpNextList.Head? {
        UpNextList.head(app.player.context, playing: app.player.currentTrack, library: app.library, mixes: app.mixes)
    }

    /// An album, a playlist, a mix: its cover 48, its title in the serif over
    /// its artist, and Shuffle and Repeat at the end.
    private static func albumHead() -> Widget {
        let art = Art(48)
        let title = label("", "serif", "panel-head")
        let artist = label("", "t13", "fact")
        let words = vbox(spacing: 0, [title, artist]).expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER)
        // Shuffle and repeat live in the bar, by the transport.
        let head = hbox(spacing: 12, [art.widget, words]).size(height: 48)
        observe(head) {
            guard case let .collection(name, line, cover, collage)? = Self.head() else {
                head.isVisible = false
                return
            }
            head.isVisible = true
            setText(title, name)
            // An album's: its title sleeve when it has no cover.
            var sleeve: TitleSleeve.Words?
            if case let .album(id)? = app.player.context?.kind, let album = app.library.album(id: id) {
                sleeve = TitleSleeve.Words(album: album)
            }
            if let collage { art.show(collage: collage) } else { art.show(cover, sleeve: sleeve) }
            setText(artist, line)
            artist.isVisible = !line.isEmpty
        }
        return head
    }

    /// A station: the template mark 24 in the accent, its name in the serif
    /// (one lit arch a screen is enough: the hero's), and the dial under
    /// them. No shuffle or repeat: the radio chooses the order.
    private static func stationHead() -> Widget {
        let mark = gtk_image_new_from_icon_name(Glyphs.name("radio"))!.css("accent")
        gtk_image_set_pixel_size(ptr(mark), 24)
        let name = label("", "serif", "panel-head")
        let top = hbox(spacing: 12, [mark, name.align(vertical: GTK_ALIGN_CENTER)]).size(height: 48)
        // The dial is set, not read: its knob always shows, and it shows its
        // two ends and nothing else (tells.md 5).
        let dial = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 1, 0.05)!.css("dial")
        gtk_scale_set_draw_value(ptr(dial), 0)
        dial.named("How adventurous the radio is")
        // Counted when the hand lets go (docs/STATS.md), not at every step.
        var counting: Task<Void, Never>?
        on(dial, "value-changed") {
            let value = gtk_range_get_value(ptr(dial))
            guard abs(value - app.settings.adventurousness) > 0.001 else { return }
            app.settings.adventurousness = value
            app.radio.adventurousnessChanged()
            counting?.cancel()
            counting = Task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                Stats.track(.dialChanged, ["value": Stats.dial(value)])
            }
        }
        let adventurous = label("Adventurous", "t13", "fact").expand(horizontal: true)
        gtk_label_set_xalign(ptr(adventurous), 1)
        let ends = hbox(spacing: 8, [label("Familiar", "t13", "fact"), adventurous])
        let head = vbox(spacing: 16, [top, vbox(spacing: 8, [dial, ends])])
        observe(head) {
            guard case let .station(station)? = Self.head() else {
                head.isVisible = false
                return
            }
            head.isVisible = true
            setText(name, station.title)
            if abs(gtk_range_get_value(ptr(dial)) - app.settings.adventurousness) > 0.001 {
                gtk_range_set_value(ptr(dial), app.settings.adventurousness)
            }
        }
        return head
    }
}

/// A row of Up next (UpNext.Item): a song in one of its three styles, or a
/// line of words ("Then", Autoplay, the foot).
final class UpNextRow {
    let widget: Widget
    private let song: Widget
    private let mark: Widget
    private let number = label("", "t15", "fact", "times")
    private let bars = gtk_image_new_from_icon_name(Glyphs.name("playing"))!.css("playing")
    private let endBars = gtk_image_new_from_icon_name(Glyphs.name("playing"))!.css("playing")
    private let art = Art(48)
    private let title = label("", "t15")
    private let guest = label("", "t13", "fact")
    private let artist = label("", "t13", "fact")
    private let reason = label("", "t13", "faint")
    private let time = label("", "t13", "fact", "times")
    private let words = label("", "t13", "fact")
    /// Takes a song to come out of the queue, shown as the pointer is
    /// over its row (or the keys are on it): GNOME's way to a list's
    /// remove, as a swipe is the iPhone's. A long press or a right click
    /// opens the menu with the same and what a station should know.
    private let remove = gtk_button_new_from_icon_name("list-remove-symbolic")!
        .named("Remove from Queue").tooltip("Remove from Queue")
    private var entry: QueueEntry?
    private var isPlaying = false
    /// In History: nothing to move or remove.
    private var isPlayed = false
    /// The row's place in the list, as the list last filled it.
    var position = 0
    /// The list's picked songs to come (TrackPicks), and its rows.
    private let picked: PickedRows
    private let items: () -> [UpNext.Item]

    init(picked: PickedRows, items: @escaping () -> [UpNext.Item]) {
        self.picked = picked
        self.items = items
        gtk_label_set_xalign(ptr(number), 1)
        gtk_label_set_xalign(ptr(time), 1)
        bars.expand(horizontal: true).align(horizontal: GTK_ALIGN_END)
        mark = hbox([number.expand(horizontal: true), bars]).size(width: 24)
        gtk_widget_set_hexpand(mark, 0)
        let line = hbox(spacing: 8, [title.align(vertical: GTK_ALIGN_BASELINE_FILL),
                                     guest.expand(horizontal: true).align(vertical: GTK_ALIGN_BASELINE_FILL)])
        let text = vbox(spacing: 0, [line, artist, reason]).expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER)
        for name in ["flat", "circular", "queue-remove"] { gtk_widget_add_css_class(remove, name) }
        remove.align(vertical: GTK_ALIGN_CENTER)
        song = hbox(spacing: 12, [mark, art.widget, text, time, remove, endBars]).css("queue-row")
        widget = vbox([song, words])
        contextMenu(on: widget) { [weak self] in self?.menu() ?? [] }
        on(remove, "clicked") { [weak self] in self?.removeFromQueue() }
        // Unseen, it takes no clicks either: a tap at a row's end on a
        // touch screen plays the song, as the rest of the row does, rather
        // than take it out unseen. The keys still reach it.
        gtk_widget_set_can_target(remove, 0)
        let pointer = gtk_event_controller_motion_new()!
        on(pointer, "enter") { [remove] in gtk_widget_set_can_target(remove, 1) }
        on(pointer, "leave") { [remove] in gtk_widget_set_can_target(remove, 0) }
        gtk_widget_add_controller(song, ptr(pointer))
        // Ctrl and Shift pick the songs to come, as on a page; a plain
        // click forgets the picks (a double-click plays, as before).
        onRowClick(widget) { [weak self] toggle, extend in
            guard let self else { return }
            guard self.isUpcoming else { picked.picks.clear(); return }
            if toggle { picked.picks.click(self.position, .toggle) }
            else if extend { picked.picks.click(self.position, .extend) }
            else { picked.picks.plain(self.position) }
        }
        observe(widget) { [weak self] in
            _ = picked.picks
            self?.markPicked()
        }
    }

    /// A song to come: what can be picked, moved and removed.
    private var isUpcoming: Bool { entry != nil && !isPlaying && !isPlayed }

    /// Picked: the list's own row lit as a page's picked songs are; a run
    /// of Shift over "Then" or the song playing leaves those out.
    private func markPicked() {
        guard let row = gtk_widget_get_parent(widget) else { return }
        if isUpcoming, picked.picks.contains(position) { gtk_widget_add_css_class(row, "picked") }
        else { gtk_widget_remove_css_class(row, "picked") }
    }

    func show(_ item: UpNext.Item) {
        guard case let .song(entry, position, style, playing, line) = item else {
            song.isVisible = false
            words.isVisible = true
            switch item {
            case .then: setText(words, "Then")
            case .history: setText(words, "History")
            case let .note(text), let .foot(text): setText(words, text)
            case .song: break
            }
            // "Then" and the foot 24 under the rows; the note right under "Then".
            if case .note = item { gtk_widget_set_margin_top(words, 0) } else { gtk_widget_set_margin_top(words, 24) }
            gtk_widget_set_margin_bottom(words, { switch item { case .then, .history: 4; default: 0 } }())
            entry = nil
            markPicked()
            return
        }
        self.entry = entry
        isPlaying = playing
        isPlayed = style == .played
        markPicked()
        song.isVisible = true
        words.isVisible = false
        let track = entry.track
        mark.isVisible = style == .numbered
        art.widget.isVisible = style != .numbered
        if style != .numbered { art.show(track.artwork, sleeve: TitleSleeve.Words(track: track)) }
        setText(number, position.map(String.init) ?? "")
        number.isVisible = !playing
        bars.isVisible = playing
        endBars.isVisible = playing && style == .station
        time.isVisible = !(playing && style == .station)
        remove.isVisible = !playing && style != .played
        setText(title, track.name)
        if playing { gtk_widget_add_css_class(title, "playing") } else { gtk_widget_remove_css_class(title, "playing") }
        setText(guest, line)
        guest.isVisible = style == .numbered && !line.isEmpty
        setText(artist, line)
        artist.isVisible = style != .numbered
        let why = style == .station ? entry.reason?.text ?? "" : ""
        setText(reason, why)
        reason.isVisible = !why.isEmpty
        setText(time, clock(track.duration))
        for (name, on) in [("covered", style == .covered), ("station", style == .station), ("played", style == .played)] {
            if on { gtk_widget_add_css_class(song, name) } else { gtk_widget_remove_css_class(song, name) }
        }
    }

    /// The song's menu, with moving and removing for the ones to come in
    /// its first section, the station's lessons beside the one Remove from
    /// Queue ("eigenlijk hadden we hier al remove from queue", 20 November
    /// 2026). Found by id when chosen: the list may have moved since.
    func menu() -> [(String, () -> Void)] {
        if let several = pickedMenu() { return several }
        guard let entry else { return [] }
        let moves: [(String, () -> Void)]
        if isPlaying || isPlayed {
            moves = []
        } else {
            let id = entry.id
            func offset() -> Int? { app.player.upNext.firstIndex { $0.id == id } }
            moves = [
                ("Move Up", { if let at = offset(), at > 0 { app.player.moveUpcoming(fromOffsets: [at], toOffset: at - 1) } }),
                ("Move Down", { if let at = offset(), at < app.player.upNext.count - 1 { app.player.moveUpcoming(fromOffsets: [at], toOffset: at + 2) } }),
                ("Remove from Queue", { if let at = offset() { app.player.removeUpcoming(atOffsets: [at]) } }),
            ] + stationItems(entry)
        }
        return trackMenu([entry.track], place: moves)
    }

    /// On one of two or more songs to come picked: what the queue does with
    /// them all, as with one (Move to Top and Move to Bottom where one has
    /// Up and Down), then Play Next, Add to Queue and Add to Playlist…. On a
    /// station, taking them out teaches it once a song
    /// (PlayQueue.removeUpcoming). Found by id when chosen.
    private func pickedMenu() -> [(String, () -> Void)]? {
        guard isUpcoming, picked.picks.rows.count > 1, picked.picks.contains(position) else { return nil }
        let entries = picked.picks.tracks(at: position, in: items()).compactMap { item -> QueueEntry? in
            guard case let .song(entry, _, style, playing, _) = item, !playing, style != .played else { return nil }
            return entry
        }
        guard entries.count > 1 else { return nil }
        let ids = Set(entries.map(\.id))
        func offsets() -> IndexSet { IndexSet(app.player.upNext.indices.filter { ids.contains(app.player.upNext[$0].id) }) }
        return trackMenu(entries.map(\.track), place: [
            ("Move to Top", { app.player.moveUpcoming(fromOffsets: offsets(), toOffset: 0) }),
            ("Move to Bottom", { app.player.moveUpcoming(fromOffsets: offsets(), toOffset: app.player.upNext.count) }),
            ("Remove from Queue", { app.player.removeUpcoming(atOffsets: offsets()) }),
        ])
    }

    /// A song the station chose, before it plays, as on the iPhone
    /// (QueueView): its artist off this station, or a thumbs down. Taking
    /// it out (above) is already a lesson for the station
    /// (PlayQueue.removeUpcoming).
    private func stationItems(_ entry: QueueEntry) -> [(String, () -> Void)] {
        guard entry.reason != nil, app.player.context?.station != nil else { return [] }
        let track = entry.track
        var items: [(String, () -> Void)] = []
        if let artist = track.artists.first?.name ?? track.primaryArtist?.name {
            items.append(("Don’t Play \(artist) Here", { app.radio.removeArtistFromStation(of: track) }))
        }
        items.append(("Dislike", { app.radio.dislike(track) }))
        return items
    }

    /// Found by id: the row may show another song since it was drawn.
    private func removeFromQueue() {
        guard let id = entry?.id, let at = app.player.upNext.firstIndex(where: { $0.id == id }) else { return }
        app.player.removeUpcoming(atOffsets: [at])
    }
}

/// The song's words (LyricsFinder: the server's, then LRCLIB's, the same as
/// on the iPhone), shown while they show; the bar asks for the song
/// playing's, for its Lyrics button. Timed lyrics follow the song
/// by the iPhone's rules (LyricsView), in the designer's measures (spec §3):
/// the line being sung in the full text colour and every other line at 40 %,
/// no colour; the view bringing it to 32 % of the panel's height; a click on
/// a line playing from there. Untimed lyrics are the same lines, all full.
enum LyricsPanel {
    /// Where the line sung sits, from the top of the panel.
    private static let readingPlace = 0.32

    static func make() -> Widget {
        var lines = vbox(spacing: 8)
        let credit = label("", "fact", "bar-fact")
        // A lookup that failed: a quiet line, not a status page ("Wat wij
        // echter niet moeten doen is het een hele drukke app maken").
        let quiet = label("", "fact", "lyrics-quiet", lines: 0)
        let column = vbox(spacing: 24, [lines, credit, quiet]).margins(24)
        let scroller = scrolled(column).expand(vertical: true)
        let adjustment = gtk_scrolled_window_get_vadjustment(ptr(scroller))!
        // The view moves to the line in 300 ms, easing out; at once where
        // the desktop asks for no animations.
        let glide = adw_timed_animation_new(scroller, 0, 0, 300,
                                            adw_property_animation_target_new(ptr(adjustment), "value"))!
        adw_timed_animation_set_easing(ptr(glide), ADW_EASE_OUT_CUBIC)

        var buttons: [Widget] = []
        /// The lyrics while they are timed: a button for each of its lines.
        var timed: Lyrics?
        var current: Int?
        /// Moved to its line once since the lines were made: the first
        /// time is at once, every line after that glides.
        var placed = false

        /// The line being sung at the reading place.
        func scrollToCurrent(animated: Bool) {
            guard let current, buttons.indices.contains(current) else { return }
            let page = gtk_adjustment_get_page_size(adjustment)
            var origin = graphene_point_t(x: 0, y: 0), point = graphene_point_t(x: 0, y: 0)
            // Before the lines are laid out there is nowhere to go; the
            // adjustment's "changed" comes back once they are.
            guard page > 0, gtk_widget_get_height(buttons[current]) > 0,
                  gtk_widget_compute_point(buttons[current], column, &origin, &point) != 0 else { return }
            let top = Double(point.y) + Double(gtk_widget_get_margin_top(column))
            let goal = min(max(0, top - page * readingPlace), max(0, gtk_adjustment_get_upper(adjustment) - page))
            defer { placed = true }
            if animated && placed {
                adw_timed_animation_set_value_from(ptr(glide), gtk_adjustment_get_value(adjustment))
                adw_timed_animation_set_value_to(ptr(glide), goal)
                adw_animation_play(glide)
            } else {
                adw_animation_reset(glide)
                gtk_adjustment_set_value(adjustment, goal)
            }
        }
        // Laid out, or the panel resized: the line back at its place.
        on(raw(adjustment), "changed") {
            if adw_animation_get_state(glide) != ADW_ANIMATION_PLAYING { scrollToCurrent(animated: false) }
        }

        /// The line being sung marked, and brought to the reading place. A
        /// scroll by hand holds until the next line.
        func follow() {
            // The clock read first, always: it is what `observe` follows.
            let elapsed = app.player.elapsed
            guard let timed else { return }
            let now = timed.lineIndex(at: elapsed)
            guard now != current else { return }
            current = now
            for (index, button) in buttons.enumerated() {
                if index == now { gtk_widget_add_css_class(button, "current") } else { gtk_widget_remove_css_class(button, "current") }
            }
            scrollToCurrent(animated: true)
        }

        /// One answer on screen; nil while it is being looked for (nothing,
        /// rather than a spinner for the moment it takes).
        func show(_ answer: LyricsAnswer?) {
            // A new box each time, made with its lines: a box first measured
            // empty keeps "constant size" and is then measured as if no line
            // wrapped, so the credit under it lay over the last lines.
            let fresh = vbox(spacing: 8)
            gtk_box_insert_child_after(ptr(column), fresh, lines)
            gtk_box_remove(ptr(column), lines)
            lines = fresh
            buttons = []
            timed = nil
            current = nil
            placed = false
            for widget in [lines, credit, quiet] { widget.isVisible = false }
            gtk_adjustment_set_value(adjustment, 0)
            guard let answer else { return }
            // Where a song's lyrics came from, and whether timed (Stats).
            Stats.track(.lyricsShown, Stats.lyrics(answer))
            switch answer {
            case let .lyrics(lyrics, fromLRCLIB):
                var made: [Widget] = []
                for line in lyrics.lines {
                    // An empty line is an instrumental break: a beat, as on
                    // the iPhone.
                    let isBreak = line.text.isEmpty
                    let words = label(isBreak ? "♪" : line.text, lines: 0)
                    guard lyrics.isSynced else {
                        made.append(isBreak ? words.css("lyric", "break") : words.css("lyric"))
                        continue
                    }
                    // A button, so the keys reach it too; it looks as the
                    // line it is.
                    let button = gtk_button_new()!.css("flat", "lyric", "timed")
                    if isBreak { button.css("break") }
                    gtk_button_set_child(ptr(button), words)
                    if let start = line.start {
                        button.tooltip("Play from here")
                        on(button, "clicked") {
                            app.player.seek(to: start)
                            if !app.player.isPlaying { app.player.resume() }
                        }
                    }
                    made.append(button)
                    buttons.append(button)
                }
                // The box gets its lines before it is first measured.
                let filled = vbox(spacing: 20, made)
                gtk_box_insert_child_after(ptr(column), filled, lines)
                gtk_box_remove(ptr(column), lines)
                lines = filled
                setText(credit, "Lyrics from \(fromLRCLIB ? "LRCLIB" : app.library.serverKind)")
                credit.isVisible = true
                // The line sung now at once, paused or not; outside the
                // caller's observation, which is of the song, not the clock.
                if lyrics.isSynced {
                    timed = lyrics
                    Task { follow() }
                }
            // None: nothing, as the tab goes off and Up next comes back.
            case .instrumental, .notFound:
                break
            case let .failed(server):
                setText(quiet, server ? "The lyrics could not be loaded from the server." : "The lyrics could not be loaded from LRCLIB.")
                quiet.isVisible = true
            }
        }

        // The song's lyrics, while they show (the bar asks for the song
        // playing's in any case, for its button).
        var loaded: ItemID?
        var asking: Task<Void, Never>?
        observe(scroller) {
            let shown = app.panel.isShown && app.panel.content == .lyrics
            guard shown, let track = app.player.currentTrack else {
                // A lookup under way stops, and is asked again when they show.
                if asking != nil {
                    asking?.cancel()
                    asking = nil
                    loaded = nil
                }
                return
            }
            guard track.id != loaded else { return }
            asking?.cancel()
            asking = nil
            loaded = track.id
            show(nil)
            let online = app.settings.findLyricsOnline
            guard let server = app.server, lyricsToBeHad() else {
                show(.notFound)
                return
            }
            let finder = LyricsFinder.shared
            if let known = finder.known(track, online: online) {
                show(known)
                finder.prefetch(app.player.upNext.first?.track, server: server, online: online)
                return
            }
            asking = Task {
                let answer = await finder.lyrics(for: track, server: server, online: online)
                guard !Task.isCancelled else { return }
                asking = nil
                show(answer)
                // While they show, the next song's too, so they are there
                // the moment it starts (LyricsView).
                finder.prefetch(app.player.upNext.first?.track, server: server, online: online)
            }
        }

        // As the song moves (its clock ticks twice a second). On the column,
        // which stays: the lines' box is made anew for each song.
        observe(column) { follow() }
        return scroller
    }
}
