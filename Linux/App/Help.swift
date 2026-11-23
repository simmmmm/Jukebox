// Help & Feedback on Linux, GNOME's way: Help in the primary menu opens the
// website's help page, and About Jukebox carries the rest as libadwaita's
// own rows (Website, Support Questions, Report an Issue, Troubleshooting ›
// Debugging Information with its Copy). The sign-in page has the link and
// the copy too, where help is needed first. What they point at is the
// same on every client: Jukebox/App/Support.swift.

import CAdw
import Foundation

enum Help {
    /// Copy Diagnostic Info's words (Support.diagnostics): no address,
    /// name, user or token. Linux has no build number, so the version alone.
    static var diagnostics: String {
        Support.diagnostics(version: appVersion, client: "Linux", account: app.credentials, lastFM: app.settings.useLastFM)
    }

    /// The default browser, through GTK (the desktop portal in a Flatpak).
    static func open(_ url: URL) {
        let launcher = gtk_uri_launcher_new(url.absoluteString)
        gtk_uri_launcher_launch(launcher, ptr(MainWindow.window), nil, nil, nil)
        g_object_unref(UnsafeMutableRawPointer(launcher))
    }

    static func copyDiagnostics() {
        guard let display = gdk_display_get_default() else { return }
        gdk_clipboard_set_text(gdk_display_get_clipboard(display), diagnostics)
    }

    /// About's rows, under its version.
    static func add(to about: OpaquePointer) {
        adw_about_dialog_set_website(about, "https://tijmen.me/jukebox")
        adw_about_dialog_set_support_url(about, Support.help.absoluteString)
        adw_about_dialog_set_issue_url(about, Support.issues.absoluteString)
        if let contact = Support.contactURL { adw_about_dialog_add_link(about, "Contact Support", contact.absoluteString) }
        adw_about_dialog_set_debug_info(about, diagnostics)
        adw_about_dialog_set_debug_info_filename(about, "jukebox-diagnostic-info.txt")
    }
}
