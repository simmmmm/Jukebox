// On Your Jukebox (first Your Year) on Linux: a place in the sidebar, last,
// and the primary menu's On Your Jukebox (MainWindow). This Week, This Month
// or This Year as GNOME's linked toggle buttons (libadwaita 1.5 has no
// AdwToggleGroup), the period in the serif, the minutes and plays, its days
// or months as bars, the artist and the song it was most, then the songs,
// artists, albums and genres, each a group of rows. "Your year kun je on
// your jukebox van maken en het gewoon wekelijks/maandelijks/jaarlijks
// laten zien" (the photographer, 23 November 2026); rows on the ground, not
// Spotify's cards ("Niet teveel als Spotify qua ui"). It was a subpage of
// Preferences, and left it: the music is content, not a setting (21
// November 2026). YourYearLoader (shared) has the sources and the words;
// the Apple clients' is YourYearView.

import CAdw
import CGlue
import Foundation
import JukeboxKit

enum YourYearPage {
    /// The covers on the page, kept while it shows.
    private static var arts: [Art] = []
    /// The groups under the period's buttons, taken off for another period.
    private static var groups: [Widget] = []
    /// The latest period asked for: a load that comes in after a newer one
    /// was asked is dropped.
    private static var asked = 0

    /// The page under the sidebar's header (MainWindow's sections).
    static func make() -> Widget {
        let page = adw_preferences_page_new()!
        groups = []
        // The buttons, left as the page's text is (tells.md 8), linked as
        // GNOME's own segmented choice.
        let switcher = hbox().css("linked").align(horizontal: GTK_ALIGN_START)
        var first: Widget?
        for period in YourYear.Period.allCases {
            let button = gtk_toggle_button_new_with_label(YourYearLoader.name(period))!
            if let first { gtk_toggle_button_set_group(ptr(button), ptr(first)) } else { first = button }
            on(button, "toggled") {
                if gtk_toggle_button_get_active(ptr(button)) != 0 { show(period, on: page) }
            }
            append(button, to: switcher)
            if period == YourYearLoader.firstPeriod { gtk_toggle_button_set_active(ptr(button), 1) }
        }
        let control = adw_preferences_group_new()!
        adw_preferences_group_add(ptr(control), switcher)
        adw_preferences_page_add(ptr(page), ptr(control))
        if groups.isEmpty { show(YourYearLoader.firstPeriod, on: page) }
        return page
    }

    private static func show(_ period: YourYear.Period, on page: Widget) {
        asked += 1
        let mine = asked
        for group in groups { adw_preferences_page_remove(ptr(page), ptr(group)) }
        let spinner = gtk_spinner_new()!.size(width: 32, height: 32).align(horizontal: GTK_ALIGN_CENTER)
        gtk_spinner_start(ptr(spinner))
        let waiting = adw_preferences_group_new()!
        adw_preferences_group_add(ptr(waiting), spinner)
        adw_preferences_page_add(ptr(page), ptr(waiting))
        groups = [waiting]
        // Held while the period is read: the place is made anew each time
        // it is chosen, so this one may have gone by the time it comes.
        g_object_ref(raw(page))
        Task {
            let made = await YourYearLoader.load(period: period, server: app.server,
                                                 history: app.history.history, library: app.library)
            if mine == asked, gtk_widget_get_parent(page) != nil {
                adw_preferences_page_remove(ptr(page), ptr(waiting))
                groups = fill(page, made)
            }
            g_object_unref(raw(page))
        }
    }

    private static func fill(_ page: Widget, _ made: YourYear) -> [Widget] {
        arts = []
        var added: [Widget] = []
        let head = adw_preferences_group_new()!
        let title = label(YourYearLoader.heading(made), "serif", "page-title")
        // Nothing played: its one line, as the iPhone's.
        let facts = label(made.isEmpty ? String(localized: "Nothing played yet") : YourYearLoader.facts(made), "fact")
        // The same structure on every client: the head in a boxed list of
        // one row, as the groups below are (the iPhone's and the Mac's
        // grouped section), and where the plays come from under it, as
        // their section's footer.
        let box = gtk_list_box_new()!.css("boxed-list")
        gtk_list_box_set_selection_mode(ptr(box), GTK_SELECTION_NONE)
        let row = gtk_list_box_row_new()!
        gtk_list_box_row_set_activatable(ptr(row), 0)
        gtk_list_box_row_set_child(ptr(row), vbox(spacing: 8, [title, facts, bars(made)]).margins(horizontal: 16, vertical: 12))
        gtk_list_box_append(ptr(box), row)
        let source = label(YourYearLoader.source(made), "t13", "fact", lines: 0).margins(horizontal: 12, vertical: 0)
        adw_preferences_group_add(ptr(head), vbox(spacing: 8, [box, source]))
        adw_preferences_page_add(ptr(page), ptr(head))
        added.append(head)
        if let artist = made.artists.first, let song = made.songs.first {
            let top = adw_preferences_group_new()!
            adw_preferences_group_set_title(ptr(top), String(localized: "Most played"))
            adw_preferences_group_add(ptr(top), topRow(artist, line: YourYearLoader.plays(artist)))
            adw_preferences_group_add(ptr(top), topRow(song, line: [song.detail, YourYearLoader.plays(song)]
                .compactMap { $0 }.joined(separator: " · ")))
            adw_preferences_page_add(ptr(page), ptr(top))
            added.append(top)
        }
        for (title, list, covers) in [("Songs", made.songs, true), ("Artists", made.artists, false),
                                      ("Albums", made.albums, true), ("Genres", made.genres, false)] {
            if let group = entries(title, list, covers: covers) {
                adw_preferences_page_add(ptr(page), ptr(group))
                added.append(group)
            }
        }
        return added
    }

    /// A bar a day of the week or the month, or a month of the year, as
    /// tall as its minutes. A grid of equal columns, so a month's day
    /// numbers (one each seven days) span their week and leave the bars
    /// even.
    private static func bars(_ made: YourYear) -> Widget {
        let minutes = made.spread
        let most = max(1, minutes.max() ?? 1)
        let labels = YourYearLoader.spreadLabels(made)
        let many = minutes.count > 12
        let grid = gtk_grid_new()!.margins(horizontal: 0, vertical: 12)
        gtk_grid_set_column_homogeneous(ptr(grid), 1)
        gtk_grid_set_column_spacing(ptr(grid), many ? 2 : 4)
        gtk_grid_set_row_spacing(ptr(grid), 4)
        for (index, value) in minutes.enumerated() {
            let height = Int32(max(1, 64 * value / most))
            let bar = adw_bin_new()!.css("year-bar").size(height: height).align(vertical: GTK_ALIGN_END)
            gtk_grid_attach(ptr(grid), vbox(spacing: 0, [bar.expand(vertical: true)]).size(height: 64), Int32(index), 0, 1, 1)
        }
        for (index, text) in labels.enumerated() where !text.isEmpty {
            let letter = label(text, "t13", "fact")
            gtk_label_set_xalign(ptr(letter), many ? 0 : 0.5)
            gtk_grid_attach(ptr(grid), letter, Int32(index), 1, Int32(many ? min(7, labels.count - index) : 1), 1)
        }
        jb_accessible_label(grid, YourYearLoader.spreadName(made))
        return grid
    }

    /// The artist or the song it was most: its cover larger, its name in
    /// the serif.
    private static func topRow(_ entry: YourYear.Entry, line: String) -> Widget {
        let row = adw_action_row_new()!.css("year-top")
        adw_preferences_row_set_use_markup(ptr(row), 0)
        adw_preferences_row_set_title(ptr(row), entry.name)
        adw_action_row_set_subtitle(ptr(row), line)
        let art = Art(64)
        art.show(entry.track?.artwork, sleeve: entry.track.map(TitleSleeve.Words.init(track:)))
        arts.append(art)
        adw_action_row_add_prefix(ptr(row), art.widget.margins(horizontal: 0, vertical: 6))
        return row
    }

    private static func entries(_ title: String, _ list: [YourYear.Entry], covers: Bool) -> Widget? {
        guard !list.isEmpty else { return nil }
        let group = adw_preferences_group_new()!
        adw_preferences_group_set_title(ptr(group), title)
        for (rank, entry) in list.enumerated() {
            let row = adw_action_row_new()!
            adw_preferences_row_set_use_markup(ptr(row), 0)
            adw_preferences_row_set_title(ptr(row), entry.name)
            if let detail = entry.detail { adw_action_row_set_subtitle(ptr(row), detail) }
            let number = label("\(rank + 1)", "serif", "fact").size(width: 24)
            gtk_label_set_xalign(ptr(number), 1)
            adw_action_row_add_prefix(ptr(row), number)
            if covers {
                let art = Art(40)
                art.show(entry.track?.artwork, sleeve: entry.track.map(TitleSleeve.Words.init(track:)))
                arts.append(art)
                adw_action_row_add_prefix(ptr(row), art.widget)
            }
            adw_action_row_add_suffix(ptr(row), label(YourYearLoader.plays(entry), "fact"))
            adw_preferences_group_add(ptr(group), row)
        }
        return group
    }
}
