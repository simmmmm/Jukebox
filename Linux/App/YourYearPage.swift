// Your Year on Linux: a subpage of Preferences, opened from the Accounts
// group, as GNOME's Settings opens a detail (the iPhone's is a sheet from
// Settings' server section). The year in the serif, the minutes and plays,
// the months as bars, then the songs, artists, albums and genres, each a
// group of rows. YourYearLoader (shared) has the sources and the words.

import CAdw
import Foundation
import JukeboxKit

enum YourYearPage {
    /// The covers on the page, kept while it shows.
    private static var arts: [Art] = []

    static func make() -> UnsafeMutablePointer<AdwNavigationPage> {
        let page = adw_preferences_page_new()!
        let toolbar = adw_toolbar_view_new()!
        adw_toolbar_view_add_top_bar(ptr(toolbar), adw_header_bar_new())
        adw_toolbar_view_set_content(ptr(toolbar), page)
        let spinner = gtk_spinner_new()!.size(width: 32, height: 32).align(horizontal: GTK_ALIGN_CENTER)
        gtk_spinner_start(ptr(spinner))
        let waiting = adw_preferences_group_new()!
        adw_preferences_group_add(ptr(waiting), spinner)
        adw_preferences_page_add(ptr(page), ptr(waiting))
        Task {
            let year = await YourYearLoader.load(year: YourYearLoader.year(), server: app.server,
                                                 history: app.history.history, library: app.library)
            adw_preferences_page_remove(ptr(page), ptr(waiting))
            fill(page, year)
        }
        return adw_navigation_page_new(toolbar, "Your Year")!
    }

    private static func fill(_ page: Widget, _ year: YourYear) {
        arts = []
        let head = adw_preferences_group_new()!
        adw_preferences_group_set_description(ptr(head), YourYearLoader.source(year))
        let title = label(String(year.year), "serif", "page-title")
        let facts = label(YourYearLoader.facts(year), "fact")
        adw_preferences_group_add(ptr(head), vbox(spacing: 8, [title, facts, bars(year.months)]))
        adw_preferences_page_add(ptr(page), ptr(head))
        if year.isEmpty {
            setText(facts, String(localized: "Nothing played yet"))
            return
        }
        entries("Songs", year.songs, covers: true, on: page)
        entries("Artists", year.artists, covers: false, on: page)
        entries("Albums", year.albums, covers: true, on: page)
        entries("Genres", year.genres, covers: false, on: page)
    }

    /// Twelve bars, January first, as tall as each month's minutes.
    private static func bars(_ minutes: [Int]) -> Widget {
        let most = max(1, minutes.max() ?? 1)
        let letters = YourYearLoader.monthLetters
        let row = hbox(spacing: 4).size(height: 88).margins(horizontal: 0, vertical: 12)
        for month in 0..<12 {
            let height = Int32(max(1, 64 * minutes[month] / most))
            let bar = adw_bin_new()!.css("year-bar").size(height: height).align(vertical: GTK_ALIGN_END)
            let letter = label(letters.indices.contains(month) ? letters[month] : "", "t13", "fact")
            gtk_label_set_xalign(ptr(letter), 0.5)
            let column = vbox(spacing: 4, [bar.expand(vertical: true), letter]).expand(horizontal: true)
            append(column, to: row)
        }
        return row
    }

    private static func entries(_ title: String, _ list: [YourYear.Entry], covers: Bool, on page: Widget) {
        guard !list.isEmpty else { return }
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
        adw_preferences_page_add(ptr(page), ptr(group))
    }
}
