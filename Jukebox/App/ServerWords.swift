// How the screens name a server: by the kind its owner installed —
// "Jellyfin", "Navidrome", "Gonic" — and its version, never by the API it
// speaks ("Subsonic API", "OpenSubsonic"), which nobody set up by that name.
// The photographer, 9 November 2026, asked for Navidrome and the other
// Subsonic servers before the release: "Kun je die navidunges en subsonic
// toevoegen dan Istie erna wel klaar voor release". The server's own name
// ("Tijmen's Music"; a Subsonic server has none, so its host) is for the
// sign-in screen and Settings; elsewhere "your Jellyfin server", "your
// Navidrome server".

import Foundation
import JukeboxKit

extension ServerKind {
    /// What a capped stream or a download is converted to: Jellyfin makes
    /// AAC, a Subsonic server MP3 (JukeboxKit asks it for MP3, since
    /// Navidrome's own choice, Ogg Opus, does not play on the phone;
    /// docs/SERVERS.md, "Streaming, measured"), Plex MP3 too (its
    /// transcoder's progressive MP3, "Plex"). Emby makes AAC as Jellyfin
    /// does (HLS when capped, m4a for a download; "Emby").
    var convertedFormat: String {
        switch self {
        case .jellyfin, .emby: "AAC"
        case .subsonic, .plex: "MP3"
        }
    }
}

enum ServerWords {
    /// "Jellyfin 12.4.0", "Navidrome 0.64.2": the kind and its version,
    /// without the build Navidrome adds in brackets ("0.64.2 (10114574)").
    /// The kind alone when the version is not known (a sign-in kept by the
    /// Jellyfin-only app, until the server has been asked).
    static func product(_ kind: ServerKind, version: String) -> String {
        let shown = shortVersion(version)
        guard !shown.isEmpty else { return kind.displayName }
        return "\(kind.displayName) \(shown)"
    }

    /// "Tijmen's Music", or a Subsonic server's host: what an account's row
    /// and its messages call its server.
    static func name(of account: ServerCredentials) -> String {
        account.serverName.isEmpty ? (account.serverURL.host ?? account.serverURL.absoluteString) : account.serverName
    }

    static func shortVersion(_ version: String) -> String {
        var shown = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bracket = shown.firstIndex(of: "(") {
            shown = String(shown[..<bracket]).trimmingCharacters(in: .whitespaces)
        }
        return shown
    }
}
