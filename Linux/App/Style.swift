// Jukebox's brand on GNOME (docs/BRAND.md, docs/design/tells.md): GNOME's
// own controls and libadwaita's own shapes — the photographer, 14 November
// 2026: "ik wil net als met numa dat het vooral super nice werkt op gnome"
// — and Jukebox's in the content: Copper by day and Glow by night as the
// one accent, flat grounds (Paper, Night), titles in a serif, one radius
// for artwork, the arch for a station and light only for the one on air
// (the drawings themselves are Drawings.swift's).
//
// Every distance and size is a multiple of 4 ("zorg dat alles past op een
// 4pt grid", the photographer, 14 November 2026), here and in the screens:
// 4, 8, 12, 16, 24, 32, as the iPhone's Theme.Space. dev/grid-check.py says
// where one is not, on either platform. The one radius stays the brand's 6.

import CAdw
import Foundation

enum Style {
    private static let provider = gtk_css_provider_new()!

    static func install() {
        gtk_style_context_add_provider_for_display(gdk_display_get_default(), ptr(provider), 600)
        Glyphs.install()
        let manager = adw_style_manager_get_default()!
        on(manager, "notify::dark") { load() }
        load()
    }

    private static func load() {
        let dark = adw_style_manager_get_dark(adw_style_manager_get_default()) != 0
        let accent = dark ? "#FFB54D" : "#A84A17"
        let onAccent = dark ? "#2A1505" : "#FFFFFF"
        let ground = dark ? "#121110" : "#F6F3EE"
        // One step up, for the sidebar, the panel and the bar (the designer's
        // spec, §1).
        let raised = dark ? "#1B1918" : "#ECE7DF"
        // libadwaita 1.5 reads its colours by name, 1.6 and later from
        // variables (which GTK before 4.16 cannot read, and says so).
        var css = """
        @define-color accent_color \(accent);
        @define-color accent_bg_color \(accent);
        @define-color accent_fg_color \(onAccent);
        @define-color window_bg_color \(ground);
        @define-color view_bg_color \(ground);
        @define-color sidebar_bg_color \(raised);
        @define-color sidebar_backdrop_color \(raised);
        @define-color secondary_sidebar_bg_color \(raised);
        @define-color secondary_sidebar_backdrop_color \(raised);
        @define-color headerbar_bg_color \(raised);
        @define-color headerbar_backdrop_color \(raised);
        """
        if gtk_get_minor_version() >= 16 {
            css += """
            :root {
              --accent-color: \(accent); --accent-bg-color: \(accent); --accent-fg-color: \(onAccent);
              --window-bg-color: \(ground); --view-bg-color: \(ground);
              --sidebar-bg-color: \(raised); --sidebar-backdrop-color: \(raised);
              --secondary-sidebar-bg-color: \(raised); --secondary-sidebar-backdrop-color: \(raised);
              --headerbar-bg-color: \(raised); --headerbar-backdrop-color: \(raised);
            }
            """
        }
        css += """
        /* Titles as on sleeves: the system's serif, regular weight (tells.md 3). */
        .serif { font-family: serif; font-weight: 400; }
        /* The type scale (the designer's spec, §7): size / line, in px. */
        .page-title { font-size: 40px; line-height: 48px; }
        .hero-title { font-size: 32px; line-height: 40px; }
        .section-title { font-size: 24px; line-height: 32px; }
        .panel-head { font-size: 20px; line-height: 28px; }
        .brand-name { font-size: 18px; line-height: 24px; }
        .t17 { font-size: 17px; line-height: 24px; }
        .t15 { font-size: 15px; line-height: 20px; }
        .t13, .bar-fact { font-size: 13px; line-height: 16px; }
        .medium { font-weight: 500; }
        .fact { opacity: 0.6; }
        .faint { opacity: 0.4; }
        .times { font-feature-settings: "tnum"; }
        /* One radius, for artwork (tells.md 6). */
        .artwork { border-radius: 6px; background-color: alpha(currentColor, 0.08); }
        .artwork-empty { opacity: 0.35; }
        /* Rows on the ground, not cards (tells.md 6). */
        gridview, listview { background: none; }
        /* A tile's content sits on the page's grid; its hover reaches 8
           past it, so the button's padding is given back as margin. */
        button.tile { padding: 8px; margin: -8px; background: none; box-shadow: none; font-weight: inherit; }
        button.tile:hover { background-color: alpha(currentColor, 0.07); }
        scrolledwindow.shelf { margin: -8px 0 -8px -8px; }
        /* A grid's cell is wider than its tile, so GTK's own hover on the
           cell stood beside the tile ("de hover hier is fucking raar", 14
           November 2026): the cell shows nothing, the tile itself lights,
           8 past it as on a shelf. */
        gridview > child { padding: 0 24px 24px 0; background: none; }
        gridview > child:hover, gridview > child:selected { background: none; }
        gridview > child > .grid-tile { padding: 8px; margin: -8px; border-radius: 12px; }
        gridview > child:hover > .grid-tile { background-color: alpha(currentColor, 0.07); }
        flowboxchild { padding: 0; }
        /* Songs' rows: 48 (64 with a cover), their hover past the margin. */
        /* min-width: an empty list's least stays 0 under its -16 of margin. */
        listview.rows { margin: 0 -8px; min-width: 16px; }
        listview.rows > row { padding: 0 8px; }
        .track-row { min-height: 48px; }
        .track-row.covered { min-height: 64px; }
        /* The page's buttons, 40 tall: Play filled, the rest words. */
        button.page-button { min-height: 40px; padding: 0 24px; font-size: 15px; }
        button.word { min-height: 40px; padding: 0 8px; font-size: 15px; }
        button.plain { padding: 0; min-height: 0; background: none; box-shadow: none; font-weight: inherit; }
        .playing { color: @accent_color; }
        /* The sidebar of places (spec §4): rows of 40 inset 8, padding 12,
           the icon at 60 % until chosen; the playlists' rows 48. */
        .navigation-sidebar { padding: 8px 0; }
        .navigation-sidebar > row { min-height: 40px; padding: 0 12px; margin: 0 8px; }
        .navigation-sidebar > row.playlist { min-height: 48px; }
        .navigation-sidebar > row.gap { min-height: 16px; background: none; }
        .navigation-sidebar > row .place-icon { opacity: 0.6; }
        .navigation-sidebar > row:selected .place-icon { opacity: 1; }
        /* The player's bar (PlayerBar.swift), in the designer's measures
           (build/design-round/2027/spec.md, §2): 88 tall, buttons 32, Play
           40, the position's track 4 with its knob only under the pointer. */
        .player-bar { padding: 12px 0; }
        .player-bar button.tile { padding: 0; margin: 0; }
        .player-bar .bar-title { font-size: 15px; font-weight: 500; line-height: 20px; }
        .player-bar button.flat, .player-bar menubutton > button { min-width: 32px; min-height: 32px; padding: 0; }
        .player-bar button.play { min-width: 40px; min-height: 40px; padding: 0; }
        .player-bar button.toggle:checked { color: @accent_color; }
        button.given { color: @accent_color; }
        /* grid-ok: the 4 track centred in its row of 16, and the 16 knob on it */
        .player-bar scale { padding: 6px 0; min-height: 0; }
        .player-bar scale > trough { min-height: 4px; }
        /* grid-ok: the same centring */
        .player-bar scale > trough > slider { min-width: 16px; min-height: 16px; margin: -6px; opacity: 0; }
        .player-bar scale:hover > trough > slider { opacity: 1; }
        scale.level > trough > highlight { background-color: alpha(@window_fg_color, 0.6); }
        /* The panel (Panel.swift, spec §3): its tabs, and the lyrics, 600
           18/24 with 8 between lines ("Kun je de lyrics ook wat nicer
           opmaken, iets dichter op elkaar", 14 November 2026); the line
           sung in full, the rest at 40 %, a break a small quiet note. */
        button.panel-tab { font-size: 15px; font-weight: 600; }
        button.panel-tab:not(:checked) > label { opacity: 0.6; }
        .lyric { font-size: 18px; font-weight: 600; line-height: 24px; }
        .lyric.break { font-size: 13px; line-height: 16px; }
        /* Shuffle and repeat by the transport: quieter than it until on. */
        .player-bar button.mode:not(.accent) { opacity: 0.6; }
        .player-bar button.mode:checked { background: none; }
        button.lyric { padding: 0; margin: 0; min-height: 0; background: none; box-shadow: none; }
        button.lyric.timed > label { opacity: 0.4; transition: opacity 300ms ease-out; }
        button.lyric.timed.break > label { opacity: 0.24; }
        button.lyric.timed.current > label { opacity: 1; }
        button.lyric.timed:hover > label { opacity: 0.7; }
        button.lyric.timed.current:hover > label { opacity: 1; }
        .lyrics-quiet { font-size: 15px; }
        listview.queue { padding: 12px 0 16px; }
        listview.queue > row { padding: 0 16px; }
        .queue-row { min-height: 48px; }
        .queue-row.covered { min-height: 64px; }
        .queue-row.station { min-height: 72px; }
        /* The dial: the accent, its knob always shown (it is set, not read). */
        /* grid-ok: the 4 track centred in 16 */
        scale.dial { padding: 6px 0; }
        scale.dial > trough { min-height: 4px; }
        /* grid-ok: the same centring */
        scale.dial > trough > slider { min-width: 16px; min-height: 16px; margin: -6px; }
        /* Now Playing (spec §6): the bar and the docked panel lose their
           own ground over the room, fading as long as the room does
           (NowPlayingPage): at once, they jumped while all else faded. */
        window.in-room toolbarview > .bottom-bar { background: none; box-shadow: none; }
        window.room-docked .panel-split > .sidebar-pane { background: none; }
        toolbarview > .bottom-bar, .panel-split > .sidebar-pane {
          transition: background-color 200ms linear, box-shadow 200ms linear;
        }
        """
        gtk_css_provider_load_from_string(provider, css)
    }
}

/// The few glyphs Adwaita has not: the heart, Not This, the bars of the song
/// playing, Radio's arch and the playlists' list, from the designer's kit.js.
/// Symbolic icons, so GTK colours them as text; filled shapes only, as GTK
/// 4.14 paints every path's fill in the text colour (a stroke would fill).
/// Written where the icon theme looks, once a launch.
enum Glyphs {
    private static let shapes: [String: String] = [
        "heart": #"<path d="M8 14S1.5 9.8 1.5 5.6A3.4 3.4 0 0 1 8 4a3.4 3.4 0 0 1 6.5 1.6C14.5 9.8 8 14 8 14z"/>"#,
        "heart-outline": #"<path fill-rule="evenodd" d="M8 14S1.5 9.8 1.5 5.6A3.4 3.4 0 0 1 8 4a3.4 3.4 0 0 1 6.5 1.6C14.5 9.8 8 14 8 14zM8 12.49S3.19 9.38 3.19 6.28A2.52 2.52 0 0 1 8 5.09a2.52 2.52 0 0 1 4.81 1.19C12.81 9.38 8 12.49 8 12.49z"/>"#,
        "not-this": #"<path d="M2 3h3v7.5H2zM6.5 3h5.2c.8 0 1.4.5 1.6 1.2l1.2 4.3c.2.8-.4 1.5-1.2 1.5H10l.6 2.6c.2.8-.4 1.4-1.1 1.4L6.5 10z"/>"#,
        "playing": #"<rect x="2" y="6" width="2.6" height="8" rx="1"/><rect x="6.7" y="2" width="2.6" height="12" rx="1"/><rect x="11.4" y="8.5" width="2.6" height="5.5" rx="1"/>"#,
        "playlists": #"<rect x="1.5" y="3" width="8" height="1.6" rx=".8"/><rect x="1.5" y="7.2" width="8" height="1.6" rx=".8"/><rect x="1.5" y="11.4" width="5" height="1.6" rx=".8"/><path d="M11.65 12.6V4.9l3.35-1.15v1.6l-1.85.62v6.63z"/><circle cx="10.9" cy="12.6" r="1.7"/>"#,
        // The mark, heavy cut, as a template: its two tubes outlined, so
        // they are fills.
        "radio": #"<g transform="scale(.5)"><path d="M3 28.9V14.5A13 13 0 0 1 29 14.5V28.9A1.6 1.6 0 0 1 25.8 28.9V14.5A9.8 9.8 0 0 0 6.2 14.5V28.9A1.6 1.6 0 0 1 3 28.9Z"/><path d="M8.1 28.9V14.5A7.9 7.9 0 0 1 23.9 14.5V28.9A1.6 1.6 0 0 1 20.7 28.9V14.5A4.7 4.7 0 0 0 11.3 14.5V28.9A1.6 1.6 0 0 1 8.1 28.9Z"/><path d="M13.2 14.5A2.8 2.8 0 0 1 18.8 14.5V27.7A2.8 2.8 0 0 1 13.2 27.7Z"/></g>"#,
    ]

    /// The icon's name for `shape`: "jukebox-heart-symbolic".
    static func name(_ shape: String) -> String { "jukebox-\(shape)-symbolic" }

    static func install() {
        let folder = String(cString: g_get_user_cache_dir()) + "/jukebox/glyphs"
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for (shape, body) in shapes {
            let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">"# + body + "</svg>"
            try? svg.write(toFile: "\(folder)/\(name(shape)).svg", atomically: true, encoding: .utf8)
        }
        gtk_icon_theme_add_search_path(gtk_icon_theme_get_for_display(gdk_display_get_default()), folder)
    }
}
