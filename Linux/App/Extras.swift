// Three things from features.md's "De moeite waard", Linux's own way
// ("doe alles", 18 November 2026), each where something already is, no
// new buttons ("ik wil alleen er voor waken dat we niet 10000 knopen
// krijgen"):
// - Copy Link in a song's, an album's and an artist's menu: the words and a
//   link for a friend on the clipboard (Sharing), GNOME's way to share.
// - Choose Picture… in a playlist's ⋮: a photograph as its cover, where the
//   server takes one (PlaylistCovers).
// - Mini Player in the primary menu: a small window of the song and its
//   transport in place of the big one. GNOME on Wayland lets no window keep
//   itself on top: the window manager's own "Always on Top" does that.

import CAdw
import CGlue
import Foundation
import JukeboxKit

/// Copy Link, unless the server makes its own link to play (Copy Share
/// Link, ShareLinks.swift), which a friend can hear: one way to share a
/// song or an album, never two.
func publicShareItems(_ item: ShareItem) -> [(String, () -> Void)] {
    app.library.sharesPublicLink(item) ? [("Copy Link", { Share.copy(item) })] : []
}

enum Share {
    /// "Copy Link": the words and the link on the clipboard, then a toast
    /// saying so; the words alone when no link was found.
    static func copy(_ item: ShareItem) {
        Task {
            let shared = await app.library.shareText(item)
            guard let display = gdk_display_get_default() else { return }
            gdk_clipboard_set_text(gdk_display_get_clipboard(display), shared.text)
            MainWindow.toast(shared.url == nil ? "Copied “\(item.name)”" : "Copied “\(item.name)” and its link")
        }
    }
}

enum PlaylistCover {
    /// Choose Picture… once the server and the user may: added to the
    /// playlist's ⋮ when known (`menu` makes the popover again).
    static func offer(_ playlist: Playlist, _ menu: @escaping ([(String, () -> Void)]) -> Void) {
        guard !playlist.isReadOnly else { return }
        Task {
            guard await app.library.playlistCoversAllowed() else { return }
            menu([("Choose Picture…", { choose(for: playlist) })])
        }
    }

    /// GTK's file dialog for a picture, then the upload.
    static func choose(for playlist: Playlist) {
        let chosen = PathChosen { path in if let path { set(path, for: playlist) } }
        jb_choose_picture(ptr(MainWindow.window), "Choose a Picture for “\(playlist.name)”", { path, data in
            guard let data else { return }
            let chosen = Unmanaged<PathChosen>.fromOpaque(data).takeUnretainedValue()
            let path = path.map { String(cString: $0) }
            MainActor.assumeIsolated { chosen.run(path) }
        }, Unmanaged.passRetained(chosen).toOpaque(), { data in
            guard let data else { return }
            Unmanaged<PathChosen>.fromOpaque(data).release()
        })
    }

    /// The picture as a JPEG of 1200 at most (a server's cover is shown at
    /// 880 at the largest, Artwork.swift), then the server's.
    static func set(_ path: String, for playlist: Playlist) {
        var length: gsize = 0
        guard let bytes = jb_jpeg_from_file(path, 1200, &length) else {
            MainWindow.toast("That picture could not be read.")
            return
        }
        let jpeg = Data(bytes: bytes, count: Int(length))
        g_free(bytes)
        Task {
            do {
                try await app.library.setCover(jpeg, of: playlist)
                MainWindow.toast("“\(playlist.name)” has its new picture")
            } catch {
                MainWindow.toast(error.localizedDescription)
            }
        }
    }
}

private nonisolated final class PathChosen {
    let run: @MainActor (String?) -> Void
    init(_ run: @escaping @MainActor (String?) -> Void) { self.run = run }
}

/// The small window: the cover 64, the title over the artist, and under
/// them the transport and where it is in the song; 360 wide. The big window
/// hides while it shows, and comes back when it closes, as Music's
/// MiniPlayer on the Mac. Amperfy 2.1.1 has one (features.md).
enum MiniPlayer {
    private static var window: Widget?
    /// The window while it shows, for the screenshot walk.
    static var shown: Widget? { window }

    static func open() {
        guard window == nil, app.player.currentTrack != nil else { return }
        let made = adw_window_new()!
        window = made
        gtk_window_set_title(ptr(made), "Mini Player")
        gtk_window_set_application(ptr(made), gtk_window_get_application(ptr(MainWindow.window)))
        gtk_window_set_default_size(ptr(made), 360, -1)
        gtk_window_set_resizable(ptr(made), 0)

        let art = Art(64)
        let title = label("", "t15", "medium")
        let artist = label("", "t13", "fact")
        let words = vbox(spacing: 4, [title, artist]).expand(horizontal: true).align(vertical: GTK_ALIGN_CENTER)
        gtk_label_set_max_width_chars(ptr(title), 1)
        gtk_label_set_max_width_chars(ptr(artist), 1)
        let song = hbox(spacing: 12, [art.widget, words])
        let previous = iconButton("media-skip-backward-symbolic", "Previous", "flat") { app.player.previous() }
        let play = iconButton("media-playback-start-symbolic", "Play", "circular", "play") { app.player.togglePlayPause() }
        let next = iconButton("media-skip-forward-symbolic", "Next", "flat") { app.player.next() }
        let transport = hbox(spacing: 16, [previous, play, next]).align(horizontal: GTK_ALIGN_CENTER)
        let progress = gtk_progress_bar_new()!
        let column = vbox(spacing: 16, [song, transport, progress]).margins(16)
        gtk_widget_set_margin_top(column, 0)

        let header = adw_header_bar_new()!
        adw_header_bar_set_show_title(ptr(header), 0)
        let toolbar = adw_toolbar_view_new()!
        adw_toolbar_view_add_top_bar(ptr(toolbar), header)
        adw_toolbar_view_set_content(ptr(toolbar), column)
        adw_window_set_content(ptr(made), toolbar)
        keep(art, on: raw(made), as: "art")

        observe(column) {
            let player = app.player
            let track = player.currentTrack
            art.show(track?.artwork)
            setText(title, track?.name ?? "")
            setText(artist, track?.artistLine ?? "")
            setIcon(play, player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic")
            play.tooltip(player.isPlaying ? "Pause" : "Play")
            let length = track?.duration ?? 0
            gtk_progress_bar_set_fraction(ptr(progress), length > 0 ? min(1, player.position / length) : 0)
        }
        // Closed: the big window again, where it was.
        on(raw(made), "destroy") {
            window = nil
            gtk_widget_set_visible(MainWindow.window, 1)
            gtk_window_present(ptr(MainWindow.window))
        }
        gtk_window_present(ptr(made))
        gtk_widget_set_visible(MainWindow.window, 0)
    }
}
