// Signing in: the server's address, a user name and a password, on one
// page. JukeboxKit finds what is at the address (Jellyfin, Navidrome or
// another Subsonic server) and signs in to it; a server that takes an API
// key instead of a password is asked for that in the same field (a Plex
// server's token too). Under Sign In, Sign In with Plex: plex.tv in the
// browser, for Plex's people, who seldom know their server's address.
// The same page adds an account to those kept (the primary menu's or
// Preferences' Add Account): over the signed-in window, with Cancel.
// ponytail: no Quick Connect on Linux yet (the kit has it: QuickConnectSignIn).

import CAdw
import Foundation
import JukeboxKit

enum SignInPage {
    private static var user: Widget!
    private static var password: Widget!
    private static var cancel: Widget!

    /// Add Account: the address stays (often the same server, another
    /// user), the user name and the password are typed afresh, and Cancel
    /// goes back to the window.
    static func prepareForAnother() {
        gtk_editable_set_text(ptr(user), "")
        gtk_editable_set_text(ptr(password), "")
        showsCancel(true)
    }

    /// Only while an account is being added.
    static func showsCancel(_ shown: Bool) {
        cancel.isVisible = shown
    }

    static func make() -> Widget {
        let address = adw_entry_row_new()!
        adw_preferences_row_set_title(ptr(address), "Server Address")
        let user = adw_entry_row_new()!
        Self.user = user
        adw_preferences_row_set_title(ptr(user), "User Name")
        let password = adw_password_entry_row_new()!
        Self.password = password
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
                var kind: ServerKind?
                do {
                    let server = try await app.detectServer(at: typed)
                    kind = server.kind
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
                        // Plex's own word for its key (X-Plex-Token).
                        adw_preferences_row_set_title(ptr(password), kind == .plex ? "Token" : "API Key")
                        gtk_editable_set_text(ptr(password), "")
                    }
                    setText(message, error.localizedDescription)
                    message.isVisible = true
                }
            }
        }

        signIn = button("Sign In", "suggested-action") { submit() }.align(horizontal: GTK_ALIGN_CENTER)
        for row in [address, user, password] { on(raw(row), "entry-activated") { submit() } }

        // Sign In with Plex: plex.tv's page in the default browser, so the
        // password goes to Plex and never to Jukebox, while the kit asks
        // plex.tv every 2 s whether it is done (PlexAccount; docs/SERVERS.md
        // "Plex"). Then the account's server: the one at the address typed,
        // the only one, or the one chosen. The same button again cancels.
        var plexTask: Task<Void, Never>?
        var plex: Widget!
        func say(_ text: String) {
            setText(message, text)
            message.isVisible = true
        }
        func plexDone() {
            plexTask = nil
            gtk_button_set_label(ptr(plex), "Sign In with Plex")
            signIn.isSensitive = true
        }
        func signInWithPlex() {
            if let running = plexTask {
                running.cancel()
                message.isVisible = false
                return plexDone()
            }
            guard !isBusy else { return }
            let typed = text(address)
            gtk_button_set_label(ptr(plex), "Cancel")
            signIn.isSensitive = false
            message.isVisible = false
            plexTask = Task {
                do {
                    let found = typed.isEmpty ? nil : try? await app.detectServer(at: typed)
                    let typedServer = found?.kind == .plex ? found : nil
                    let account = PlexAccount(identity: app.identity)
                    let pin = try await account.start()
                    openInBrowser(pin.authURL)
                    say("Sign in to Plex in your browser. Jukebox waits here.")
                    let token = try await account.token(for: pin)
                    var servers = try await account.servers(token: token)
                    if let typedServer { servers = servers.filter { $0.id == typedServer.id } }
                    guard !servers.isEmpty else {
                        say(typedServer.map { "This Plex account cannot play from \($0.name)." }
                            ?? "This Plex account has no server to play from yet.")
                        return plexDone()
                    }
                    guard let chosen = servers.count == 1 ? servers[0] : await choose(servers) else {
                        message.isVisible = false
                        return plexDone()
                    }
                    let credentials = try await account.signIn(to: chosen, accountToken: token,
                                                               preferring: typedServer?.url)
                    plexDone()
                    message.isVisible = false
                    Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "plex_pin"])
                    await app.signIn(credentials)
                } catch {
                    guard !Task.isCancelled else { return }
                    plexDone()
                    Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                    // plex.tv forgets a sign-in after 30 minutes.
                    say(error as? MusicServerError == .notFound
                        ? "The sign-in at Plex took too long. Sign in with Plex again." : error.localizedDescription)
                }
            }
        }
        plex = button("Sign In with Plex", "flat") { signInWithPlex() }.align(horizontal: GTK_ALIGN_CENTER)

        let title = label("Jukebox", "serif", "page-title")
        let fact = label("Music from your Jellyfin, Plex, Navidrome or other Subsonic server.", "fact", lines: 0)
        let actions = vbox(spacing: 8, [signIn, plex])
        let column = vbox(spacing: 24, [markTile(), title, fact, group, message, actions]).margins(24)
        gtk_widget_set_valign(column, GTK_ALIGN_CENTER)
        let clamp = adw_clamp_new()!
        adw_clamp_set_maximum_size(ptr(clamp), 420)
        adw_clamp_set_child(ptr(clamp), column)
        let toolbar = adw_toolbar_view_new()!
        let header = adw_header_bar_new()!
        // Adding an account, over the window signed in: back to it.
        let cancel = button("Cancel") { MainWindow.cancelAddAccount() }
        cancel.isVisible = false
        Self.cancel = cancel
        adw_header_bar_pack_start(ptr(header), cancel)
        adw_toolbar_view_add_top_bar(ptr(toolbar), header)
        adw_toolbar_view_set_content(ptr(toolbar), clamp)
        return toolbar
    }

    /// The default browser, through GTK (the desktop portal in a Flatpak).
    private static func openInBrowser(_ url: URL) {
        let launcher = gtk_uri_launcher_new(url.absoluteString)
        gtk_uri_launcher_launch(launcher, ptr(MainWindow.window), nil, nil, nil)
        g_object_unref(UnsafeMutableRawPointer(launcher))
    }

    /// Which of the account's servers, when it has more than one: GNOME's
    /// alert, a response a server. Nil when closed.
    private static func choose(_ servers: [PlexAccount.Server]) async -> PlexAccount.Server? {
        await withCheckedContinuation { continuation in
            let dialog = adw_alert_dialog_new("Which Plex Server?", nil)!
            adw_alert_dialog_add_response(ptr(dialog), "cancel", "Cancel")
            for (i, server) in servers.enumerated() {
                adw_alert_dialog_add_response(ptr(dialog), "\(i)", server.name)
            }
            adw_alert_dialog_set_response_appearance(ptr(dialog), "0", ADW_RESPONSE_SUGGESTED)
            adw_alert_dialog_set_close_response(ptr(dialog), "cancel")
            on(raw(dialog), "response", argument: { response in
                let id = response.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) }
                continuation.resume(returning: id.flatMap(Int.init).map { servers[$0] })
            })
            adw_dialog_present(ptr(dialog), MainWindow.window)
        }
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
