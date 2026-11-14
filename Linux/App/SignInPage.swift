// Signing in: the server's address, a user name and a password, on one
// page. JukeboxKit finds what is at the address (Jellyfin, Navidrome or
// another Subsonic server) and signs in to it; a server that takes an API
// key instead of a password is asked for that in the same field.
// ponytail: no Quick Connect on Linux yet (the kit has it: QuickConnectSignIn).

import CAdw
import Foundation
import JukeboxKit

enum SignInPage {
    static func make() -> Widget {
        let address = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(address), "Server Address")
        let user = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(user), "User Name")
        let password = adw_password_entry_row_new()!
        adw_preferences_row_set_title(ptr(password), "Password")
        let group = adw_preferences_group_new()!
        for row in [address, user, password] { adw_preferences_group_add(ptr(group), row) }

        let message = label("", lines: 0)
        message.isVisible = false
        var needsKey = false
        var isBusy = false
        var signIn: Widget!

        func text(_ row: Widget) -> String {
            String(cString: gtk_editable_get_text(ptr(row))).trimmingCharacters(in: .whitespaces)
        }

        func submit() {
            guard !isBusy else { return }
            let typed = text(address), name = text(user), secret = text(password)
            guard !typed.isEmpty else { return }
            isBusy = true
            signIn.isSensitive = false
            message.isVisible = false
            Task {
                defer {
                    isBusy = false
                    signIn.isSensitive = true
                }
                do {
                    let server = try await app.detectServer(at: typed)
                    let way = app.signIn(to: server)
                    let credentials: ServerCredentials
                    if needsKey, let withKey = way as? any APIKeySignIn {
                        credentials = try await withKey.signIn(apiKey: secret)
                    } else {
                        credentials = try await way.signIn(username: name, password: secret)
                    }
                    Stats.track(.signedIn, ["server": Stats.server(credentials.kind)])
                    gtk_editable_set_text(ptr(password), "")
                    await app.signIn(credentials)
                } catch {
                    Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                    if case .needsAPIKey? = error as? MusicServerError {
                        needsKey = true
                        adw_preferences_row_set_title(ptr(password), "API Key")
                        gtk_editable_set_text(ptr(password), "")
                    }
                    setText(message, error.localizedDescription)
                    message.isVisible = true
                }
            }
        }

        signIn = button("Sign In", "suggested-action") { submit() }.align(horizontal: GTK_ALIGN_CENTER)
        for row in [address, user, password] { on(raw(row), "entry-activated") { submit() } }

        let title = label("Jukebox", "serif", "page-title")
        let fact = label("Music from your Jellyfin, Navidrome or other Subsonic server.", "fact", lines: 0)
        let column = vbox(spacing: 24, [markTile(), title, fact, group, message, signIn]).margins(24)
        gtk_widget_set_valign(column, GTK_ALIGN_CENTER)
        let clamp = adw_clamp_new()!
        adw_clamp_set_maximum_size(ptr(clamp), 420)
        adw_clamp_set_child(ptr(clamp), column)
        let toolbar = adw_toolbar_view_new()!
        adw_toolbar_view_add_top_bar(ptr(toolbar), adw_header_bar_new())
        adw_toolbar_view_set_content(ptr(toolbar), clamp)
        return toolbar
    }

    /// The mark on its tile, as the icon is shaped, before Jukebox's name,
    /// as the iPhone's welcome has it (ShellAppMark): flat on Cabinet, never
    /// lit, as the welcome plays nothing. Still: the iPhone's warm-up, the
    /// bands coming on one by one, waits for motion on Linux.
    private static func markTile() -> Widget {
        let side: Int32 = 112
        let tile = gtk_image_new()!
        gtk_image_set_pixel_size(ptr(tile), side)
        tile.size(width: side, height: side).align(horizontal: GTK_ALIGN_START)
        observe(tile) {
            let scale = Screen.shared.scale
            Task {
                let size = Double(side)
                guard let drawing = await drawn("tile \(side)", width: size, height: size, scale: scale, { cr, _ in
                    Draw.shellTile(cr, side: size)
                }) else { return }
                gtk_image_set_from_paintable(ptr(tile), drawing.pointer)
            }
        }
        return tile
    }
}
