// Help & Feedback on Apple's clients: Settings › About on the iPhone and
// the iPad, the Help menu on the Mac (and an iPad's keyboard), and quiet
// words under the sign-in form, where help is needed first ("eigenlijk
// vanaf de inlogpagina hebben meerdere gebruikers nu al hulp nodig", the
// photographer, 23 November 2026). Linux's are in Linux/App/Help.swift;
// what they all point at is Jukebox/App/Support.swift.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The entries, the same in Settings and in the Help menu: the website's
/// help page, GitHub's issues, the way to reach the developer once
/// `Support.contact` has one, and Copy Diagnostic Info.
struct HelpItems: View {
    let app: AppModel

    var body: some View {
        Link("Jukebox Help", destination: Support.help)
        Link("Report a Problem", destination: Support.issues)
        if let contact = Support.contactURL {
            Link("Contact Support", destination: contact)
        }
        CopyDiagnosticsButton(app: app)
    }
}

/// Copy Diagnostic Info: the version and build, the client, the system, the
/// kind of server and Last.fm on or off (Support.diagnostics), to paste
/// into a report. It says "Copied" for a moment.
struct CopyDiagnosticsButton: View {
    let app: AppModel
    @State private var isCopied = false

    var body: some View {
        Button(isCopied ? "Copied" : "Copy Diagnostic Info") {
            let info = Bundle.main.infoDictionary
            let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
            let build = info?["CFBundleVersion"] as? String ?? "1"
            let text = Support.diagnostics(version: "\(short) (\(build))", client: Device.model,
                                           account: app.credentials, lastFM: app.settings.hasLastFM)
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            isCopied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                isCopied = false
            }
        }
    }
}

/// Under the sign-in form, on every step: grey words, never a second
/// button beside Sign In.
struct SignInHelp: View {
    @Environment(AppModel.self) private var app
    @Environment(\.isWide) private var isWide

    var body: some View {
        VStack(spacing: 0) {
            Group {
                Link("Trouble signing in?", destination: Support.signInHelp)
                CopyDiagnosticsButton(app: app)
            }
            // A finger's 44 on the iPhone; a pointer needs less.
            .frame(minHeight: isWide ? 28 : 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
