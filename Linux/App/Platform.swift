// What the shared files (Package.swift's `shared`) ask of the platform, in
// Linux's own way: where the signed-in session is kept, the few words about
// being offline, and the store of songs kept on the machine — which Linux
// does not have yet, so it answers "none" and "online".

import CGlue
import Foundation
import JukeboxKit

/// The signed-in session in the desktop's keyring (libsecret: GNOME
/// Keyring, KWallet): a server's token is as good as a password to it. The
/// iPhone's Keychain.swift, by the same name.
///
/// A desktop without a keyring (a bare Hyprland, some XFCEs) keeps it in a
/// file only its user can read, as ssh keeps a key: "werkt het dan ook nice
/// in bijv hyprland xfce kde" (the photographer, 14 November 2026). A token,
/// never the password, which is not kept anywhere.
enum Keychain {
    private static var file: URL {
        let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return data.appendingPathComponent("Jukebox/credentials.json", isDirectory: false)
    }

    static func save(_ credentials: ServerCredentials) {
        guard let data = try? JSONEncoder().encode(credentials),
              let json = String(data: data, encoding: .utf8) else { return }
        if jb_secret_available() != 0, jb_secret_store(json) != 0 {
            // In the keyring now: not in a file as well.
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Opened with its permissions (and given them again, were it there
        // already), so it is never readable by another in between.
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { return }
        fchmod(descriptor, 0o600)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try? handle.write(contentsOf: data)
    }

    static func loadCredentials() -> ServerCredentials? {
        if jb_secret_available() != 0, let found = jb_secret_load() {
            defer { g_free(found) }
            return try? JSONDecoder().decode(ServerCredentials.self, from: Data(String(cString: found).utf8))
        }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ServerCredentials.self, from: data)
    }

    static func deleteCredentials() {
        if jb_secret_available() != 0 { jb_secret_clear() }
        try? FileManager.default.removeItem(at: file)
    }
}

/// Songs kept on the machine: none on Linux yet, and so never "offline" in
/// the iPhone's sense (only what is kept plays). The radio asks.
// ponytail: no downloads on Linux; Jukebox/Offline's store, once its
// background URLSession has a Linux twin.
final class OfflineStore {
    var isOffline: Bool { false }
    var revision: Int { 0 }
    func has(_ trackID: ItemID) -> Bool { false }
}

enum OfflineText {
    static func nothingForStation(_ title: String) -> String {
        "You’re offline. No songs on this computer for \(title)."
    }
}

extension Stats {
    /// Why a song could not be played, from GStreamer's words for it: the
    /// kind only, as on the iPhone (Stats+Apple.swift).
    static func playbackFailure(_ message: String) -> String {
        let text = message.lowercased()
        if text.contains("resolve") || text.contains("connect") || text.contains("network") || text.contains("timed out") {
            return "network"
        }
        if text.contains("decode") || text.contains("format") || text.contains("missing") { return "unsupported" }
        if text.contains("not authorized") || text.contains("forbidden") || text.contains("not found") { return "server" }
        return "other"
    }
}

extension String {
    /// Foundation on Linux has no `String(localized:)`, and Jukebox is in
    /// English only: the words as written. The shared files call it as the
    /// iPhone's String Catalog needs them to.
    init(localized words: String) { self = words }
}
