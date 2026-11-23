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

extension StreamQuality {
    /// What a quality picker offers: Efficient only where the server makes
    /// Opus (`app.can(.opusStream)`), as every option that depends on the
    /// server ("zorg dat je ook alleen die opties toont als het beschikbaar
    /// is op die server", 18 November 2026).
    static func offered(opus: Bool) -> [StreamQuality] {
        allCases.filter { $0 != .efficient || opus }
    }

    /// A kept Efficient on a server without Opus reads as Low, which is
    /// what it plays as there (the same 128 kbit/s, StreamQuality).
    func shown(opus: Bool) -> StreamQuality {
        self == .efficient && !opus ? .low : self
    }

    /// The footer's sentence about Efficient, where it is offered.
    static let efficientNote = " Efficient makes Opus instead, at half of Normal's data."
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

    /// Settings' word on Playback Reporting, under the server, on Jellyfin
    /// and Emby only (the plugin is theirs): whether Jukebox found it and
    /// what it is for. The photographer, 18 November 2026: "ik heb playback
    /// reporting geinstalleerd, maak daar ook ff een notitie van in de app
    /// settings".
    static func playbackReportingNote(_ account: ServerCredentials) -> String? {
        guard account.kind == .jellyfin || account.kind == .emby else { return nil }
        if account.capabilities.contains(.playbackReporting) {
            return String(localized: "Playback Reporting is installed: Your Year counts every play, from every device.")
        }
        return String(localized: "Playback Reporting was not found, or this account may not read it (it takes an administrator). With the plugin installed, Your Year counts every device; until then, only this one.")
    }

    /// The letter on an account's card, its kind's mark: "J" for
    /// Jellyfin, "E" for Emby, "N" for Navidrome, "P" for Plex. A letter
    /// rather than the projects' own logos, which are theirs: printed in
    /// one ink, as a record's label is (docs/design/tells.md, 7).
    static func mark(_ kind: ServerKind) -> String {
        kind.displayName.first.map { String($0).uppercased() } ?? "?"
    }

    static func shortVersion(_ version: String) -> String {
        var shown = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bracket = shown.firstIndex(of: "(") {
            shown = String(shown[..<bracket]).trimmingCharacters(in: .whitespaces)
        }
        return shown
    }
}
