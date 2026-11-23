// Signing in: the server's address, a user name and a password, on one
// page. JukeboxKit finds what is at the address (Jellyfin, Navidrome or
// another Subsonic server) and signs in to it; a server that takes an API
// key instead of a password is asked for that in the same field (a Plex
// server's token too). Under Sign In, Sign In with Plex: plex.tv in the
// browser, for Plex's people, who seldom know their server's address.
// The same page adds an account to those kept (the primary menu's or
// Preferences' Add Account): over the signed-in window, with Cancel.
// Use Quick Connect under Sign In where the Jellyfin at the address has it
// on (the server is asked once the address is left), as on the Mac.

import CAdw
import CGlue
import Foundation
import JukeboxKit

enum SignInPage {
    /// The address, the user name and Use Quick Connect: the screenshot
    /// walk's too (Shots).
    static var address: Widget!
    static var user: Widget!
    static var quickConnect: Widget!
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
        Self.address = address
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

        signIn = button("Sign In", "suggested-action", "page-button") { submit() }.align(horizontal: GTK_ALIGN_CENTER)
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
        plex = button("Sign In with Plex", "flat", "accent", "word") { signInWithPlex() }.align(horizontal: GTK_ALIGN_CENTER)

        // Quick Connect: a code typed into another signed-in Jellyfin app,
        // so no password is typed here. Offered only where the server said
        // it has it on (`/QuickConnect/Enabled`, asked by the kit's detect
        // as the address is left); the same button cancels the wait.
        var way: (any QuickConnectSignIn)?
        var askedAt = ""
        var quickTask: Task<Void, Never>?
        var quick: Widget!
        let code = label("", "title-1", "numeric", selectable: true).align(horizontal: GTK_ALIGN_CENTER)
        code.isVisible = false
        func quickDone() {
            quickTask = nil
            code.isVisible = false
            gtk_button_set_label(ptr(quick), "Use Quick Connect")
            signIn.isSensitive = true
            plex.isSensitive = true
        }
        func useQuickConnect() {
            if let running = quickTask {
                running.cancel()
                message.isVisible = false
                return quickDone()
            }
            guard !isBusy, plexTask == nil, let way else { return }
            gtk_button_set_label(ptr(quick), "Cancel")
            signIn.isSensitive = false
            plex.isSensitive = false
            say("Asking \(way.server.name) for a code…")
            quickTask = Task {
                do {
                    var state = try await way.quickConnectStart()
                    try Task.checkCancellation()
                    setText(code, state.code)
                    // Read digit by digit, as it is typed.
                    jb_accessible_label(code, state.code.map(String.init).joined(separator: " "))
                    code.isVisible = true
                    say("Enter this code in another Jellyfin app: Settings › Quick Connect. Jukebox waits here.")
                    // The server says nothing by itself: asked every 3 s,
                    // as on the iPhone, for the few minutes a code lives.
                    while !state.isAuthenticated {
                        try await Task.sleep(for: .seconds(3))
                        state = try await way.quickConnectState(secret: state.secret)
                    }
                    let credentials = try await way.signIn(quickConnectSecret: state.secret)
                    try Task.checkCancellation()
                    quickDone()
                    message.isVisible = false
                    Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "quick_connect"])
                    await app.signIn(credentials)
                } catch {
                    guard !Task.isCancelled else { return }
                    quickDone()
                    Stats.track(.signInFailed, ["reason": Stats.signInFailure(error, quickConnect: true)])
                    // The Mac's words.
                    switch error as? MusicServerError {
                    case .notFound?: say("The code has expired. Use Quick Connect again for a new one.")
                    case .unauthorized?: say("Quick Connect is turned off on this server. Sign in with your password instead.")
                    default: say(error.localizedDescription)
                    }
                }
            }
        }
        quick = button("Use Quick Connect", "flat", "accent", "word") { useQuickConnect() }.align(horizontal: GTK_ALIGN_CENTER)
        Self.quickConnect = quick
        quick.isVisible = false
        // The address left: asked now, quietly (Sign In says what went
        // wrong), so Quick Connect shows only for a server that has it.
        let leaving = gtk_event_controller_focus_new()!
        on(leaving, "leave") {
            let typed = text(address)
            guard !typed.isEmpty, typed != askedAt else { return }
            askedAt = typed
            Task {
                let found = try? await app.detectServer(at: typed)
                guard text(address) == typed else { return }
                way = found.flatMap { $0.capabilities.contains(.quickConnect) ? app.signIn(to: $0) as? any QuickConnectSignIn : nil }
                quick.isVisible = way != nil
            }
        }
        gtk_widget_add_controller(address, ptr(leaving))
        // Another address: what the last one offered no longer holds.
        on(raw(address), "changed") {
            guard quickTask == nil, text(address) != askedAt else { return }
            askedAt = ""
            way = nil
            quick.isVisible = false
        }

        // One centred column, as GNOME's own welcome and status pages
        // (AdwStatusPage) and the iPhone have it: the mark, the name, the
        // fact, the note and the buttons on one axis, the rows the
        // column's width. Centred is what the platform does here (tells.md
        // 8). The photographer, 20 November 2026: "weer parity, dit staat
        // opeens voor de helft links uitgelijnd?".
        let title = label("Jukebox", "serif", "page-title")
        let fact = label("Music from your Jellyfin, Emby, Plex, Navidrome or other Subsonic server.", "fact", lines: 0)
        for line in [title, fact, message] {
            gtk_label_set_xalign(ptr(line), 0.5)
            gtk_label_set_justify(ptr(line), GTK_JUSTIFY_CENTER)
        }
        // Help where it is needed first: "eigenlijk vanaf de inlogpagina
        // hebben meerdere gebruikers nu al hulp nodig" (the photographer,
        // 23 November 2026). Quiet words under the buttons (Help.swift).
        let trouble = button("Trouble signing in?", "flat", "word", "help", "fact") { Help.open(Support.signInHelp) }
        let copyInfo = button("Copy Diagnostic Info", "flat", "word", "help", "fact") {
            Help.copyDiagnostics()
            say("Diagnostic info copied. It holds no address, user name or password.")
        }
        let help = vbox([trouble, copyInfo]).align(horizontal: GTK_ALIGN_CENTER)
        let actions = vbox(spacing: 8, [signIn, quick, plex, help])
        let column = vbox(spacing: 24, [markTile(), title, fact, group, code, message, actions]).margins(24)
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
        // Scrolls where the window is too low for the column (400×800 with
        // Quick Connect and the help's words): nothing is cut off.
        adw_toolbar_view_set_content(ptr(toolbar), scrolled(clamp))
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

    /// The welcome's picture above Jukebox's name, as the Mac's and the
    /// iPhone's (WelcomeSleeve): the mark on its sleeve with the record half
    /// out, 240 wide, never lit, as the welcome plays nothing. Built up as
    /// the Mac's is, a jukebox switched on: close on the mark, the outer
    /// band drawn, then the inner, then the core; drawn back to the whole
    /// sleeve, and the record slides out ("doe ze allemaal", 23 November
    /// 2026). Each time the welcome shows; at rest when an account is added,
    /// which is no first sight, and where GNOME asks for no animations
    /// (gtk-enable-animations off: an AdwAnimation ends at once).
    private static func markTile() -> Widget {
        // Drawn with room around it for the sleeve's and the record's
        // shadows, which the picture's own edge cut off square: "Je snijd
        // nu de schaduw af bij t inlogscherm" (the photographer, 21
        // November 2026).
        let width = 240.0, height = 160.0, room = 32.0
        let area = gtk_drawing_area_new()!.size(width: Int32(width + 2 * room), height: Int32(height + 2 * room))
            .align(horizontal: GTK_ALIGN_CENTER)
        let build = WelcomeBuild(area: area, width: width, room: room)
        gtk_drawing_area_set_draw_func(ptr(area), { _, cr, _, _, data in
            guard let cr, let data else { return }
            MainActor.assumeIsolated { Unmanaged<WelcomeBuild>.fromOpaque(data).takeUnretainedValue().draw(cr) }
        }, Unmanaged.passRetained(build).toOpaque(), { data in
            guard let data else { return }
            Unmanaged<WelcomeBuild>.fromOpaque(data).release()
        })
        on(area, "map") { build.start(animated: !cancel.isVisible) }
        return area
    }
}

/// The welcome's build-up with the Mac's WelcomeSleeve's stages and timing.
@MainActor
private final class WelcomeBuild {
    /// 1 the outer band drawn, 2 the inner, 3 the core on, 4 drawn back to
    /// the whole sleeve, 5 the record out: each step's wait after the one
    /// before it began, how long it moves, and how (SwiftUI's easeOut and
    /// easeInOut, as libadwaita's cubic ones).
    static let steps: [(wait: Double, duration: Double, easing: AdwEasing)] = [
        (0.2, 0.9, ADW_EASE_OUT_CUBIC),
        (0.8, 0.8, ADW_EASE_OUT_CUBIC),
        (0.7, 0.45, ADW_EASE_OUT_CUBIC),
        (0.7, 1.1, ADW_EASE_IN_OUT_CUBIC),
        (0.8, 1.0, ADW_EASE_OUT_CUBIC),
    ]
    /// When each step begins, and when the last has ended (4.2 s).
    static let starts = steps.indices.map { i in steps[...i].reduce(0) { $0 + $1.wait } }
    static let end = starts.last! + steps.last!.duration

    let area: Widget, width: Double, room: Double
    /// Seconds since the welcome showed; at rest until it starts.
    var time = WelcomeBuild.end
    var animation: OpaquePointer?
    /// The record and the sleeve's card, drawn once for the screen's scale:
    /// the shadows' blur is too slow for every frame.
    var layers: (scale: Double, record: OpaquePointer, sleeve: OpaquePointer)?

    init(area: Widget, width: Double, room: Double) {
        self.area = area; self.width = width; self.room = room
    }

    func start(animated: Bool) {
        if animation == nil {
            // The time itself, linear: each step eases its own part of it.
            let target = adw_callback_animation_target_new({ value, data in
                guard let data else { return }
                MainActor.assumeIsolated {
                    let build = Unmanaged<WelcomeBuild>.fromOpaque(data).takeUnretainedValue()
                    build.time = value
                    gtk_widget_queue_draw(build.area)
                }
            }, Unmanaged.passUnretained(self).toOpaque(), nil)
            animation = OpaquePointer(adw_timed_animation_new(area, 0, Self.end, guint(Self.end * 1000), target))
            adw_timed_animation_set_easing(ptr(animation!), ADW_LINEAR)
        }
        guard animated else {
            adw_animation_skip(ptr(animation!))
            return
        }
        adw_animation_reset(ptr(animation!))
        adw_animation_play(ptr(animation!))
    }

    /// How far step `n` (1 to 5) has come, eased, 0 to 1.
    func reached(_ n: Int) -> Double {
        let step = Self.steps[n - 1]
        let linear = min(1, max(0, (time - Self.starts[n - 1]) / step.duration))
        return adw_easing_ease(step.easing, linear)
    }

    func draw(_ cr: OpaquePointer) {
        let scale = Screen.shared.scale
        if layers?.scale != scale {
            if let old = layers { cairo_surface_destroy(old.record); cairo_surface_destroy(old.sleeve) }
            layers = nil
            guard let record = Draw.welcomeLayer(scale: scale, width: width, room: room, record: true),
                  let sleeve = Draw.welcomeLayer(scale: scale, width: width, room: room, record: false) else { return }
            layers = (scale, record, sleeve)
        }
        guard let layers else { return }
        let u = width / 300, height = width * 2 / 3
        let drawBack = reached(4), out = reached(5)
        cairo_translate(cr, room, room)
        cairo_push_group(cr)
        // Close: 2.4 times as large about the mark's crown, drawing back to
        // the whole picture.
        let zoom = 2.4 + (1 - 2.4) * drawBack, anchor = (x: 0.2714 * width, y: 0.3536 * height)
        cairo_translate(cr, anchor.x, anchor.y)
        cairo_scale(cr, zoom, zoom)
        cairo_translate(cr, -anchor.x, -anchor.y)
        // The record behind the sleeve, wholly, until it slides out (from
        // 24 to 122 of the 300 units).
        if out > 0 {
            cairo_set_source_surface(cr, layers.record, -room - (1 - out) * 98 * u, -room)
            cairo_paint_with_alpha(cr, out)
        }
        // The sleeve only as the mark draws back: first the arches alone on
        // the page, then the sleeve round them, then the record.
        if drawBack > 0 {
            cairo_set_source_surface(cr, layers.sleeve, -room, -room)
            cairo_paint_with_alpha(cr, drawBack)
        }
        // On the page the page's own core; on the sleeve the night's.
        let dark = adw_style_manager_get_dark(adw_style_manager_get_default()) != 0
        Draw.welcomeMark(cr, width: width, outer: reached(1), inner: reached(2), core: reached(3),
                         pageCore: dark ? Tokens.Arch.markCore.dark : Tokens.Arch.markCore.light, onSleeve: drawBack)
        cairo_pop_group_to_source(cr)
        // Close, the legs run on below the picture: they fade out there
        // rather than end on a line, which would read as a box.
        let fade = cairo_pattern_create_linear(0, 0, 0, height)!
        cairo_pattern_add_color_stop_rgba(fade, 0, 0, 0, 0, 1)
        cairo_pattern_add_color_stop_rgba(fade, 0.7 + 0.3 * drawBack, 0, 0, 0, 1)
        cairo_pattern_add_color_stop_rgba(fade, 1, 0, 0, 0, drawBack)
        cairo_mask(cr, fade)
        cairo_pattern_destroy(fade)
    }
}
