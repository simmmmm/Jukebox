// Where help is, the same on every client: the website's help page, the
// issues on GitHub, and one place for a way to reach the developer once he
// has chosen one (docs/SUPPORT.md). The photographer, 23 November 2026: "ik
// weet niet zo goed hoe slim het is om mijn email zomaar erbij te zetten",
// so nothing personal is here, and then: "eigenlijk vanaf de inlogpagina
// hebben meerdere gebruikers nu al hulp nodig", so the sign-in page links
// to the help page's part on signing in.

import Foundation
import JukeboxKit

enum Support {
    /// The one thing to fill in: a support address ("jukebox@…") or a
    /// page's URL. Empty, the clients show the help page and GitHub only.
    static let contact = ""

    /// docs/help.html, as GitHub Pages serves it.
    static let help = URL(string: "https://simmmmm.github.io/Jukebox/help.html")!
    static let signInHelp = URL(string: "https://simmmmm.github.io/Jukebox/help.html#sign-in")!
    static let issues = URL(string: "https://github.com/simmmmm/Jukebox/issues")!

    /// `contact` as a link: an address becomes a mailto. Nil while empty.
    static var contactURL: URL? { contactURL(contact) }

    static func contactURL(_ contact: String) -> URL? {
        let contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contact.isEmpty else { return nil }
        return URL(string: contact.contains("://") || contact.hasPrefix("mailto:") ? contact : "mailto:\(contact)")
    }

    /// Copy Diagnostic Info: what a report needs and nothing that says
    /// whose it is. The app, the client, the system, the kind of server and
    /// its version, Last.fm on or off. Never the server's address or name,
    /// the user, a token, the device's name or anything of the library.
    static func diagnostics(version: String, client: String, account: ServerCredentials?, lastFM: Bool) -> String {
        let server = account.map { ServerWords.product($0.kind, version: $0.serverVersion) } ?? "not signed in"
        return """
            Jukebox \(version)
            Client: \(client)
            System: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Server: \(server)
            Last.fm: \(lastFM ? "on" : "off")
            """
    }
}
