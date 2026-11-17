// What the widget shows, as the app last saw it: whether someone is signed
// in, whether Your Station is on the air, and Home's first mixes with their
// covers. The app writes it into the App Group's folder (WidgetDoors.swift);
// the widget (JukeboxWidget/) only reads it. The widget never asks the
// server and holds no credentials, so this is all it knows.
//
// In the app and in the widget both (project.yml): Foundation only.

import Foundation

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Mix: Codable, Equatable, Sendable {
        let id: String
        let title: String
    }

    var signedIn: Bool
    /// Your Station plays: its arch is lit and it has no Play.
    var onAir: Bool
    /// Home's first three, in Home's order.
    var mixes: [Mix]

    /// The App Group both carry in their entitlements (docs/RELEASE.md,
    /// The widget).
    static let group = "group.com.tijmen.Jukebox"

    /// Nil without the App Group's entitlement: then nothing is written or read.
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Widget", isDirectory: true)
    }

    static let file = "snapshot.json"

    /// A mix's cover in the folder: a small JPEG, named by the mix's id
    /// (kind, key and day) in letters and digits.
    static func cover(of mixID: String) -> String {
        String(mixID.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init)) + ".jpg"
    }

    /// Nil before the app has written one (installed, never opened).
    static func read() -> WidgetSnapshot? {
        guard let url = folder?.appendingPathComponent(file), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
