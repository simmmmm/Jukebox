// What the shared files (Package.swift's `shared`) ask of the platform, in
// Linux's own way: where the signed-in session is kept, what the device is
// called, and for the songs kept on the machine (the shared OfflineStore)
// where they live, the network and the power saver.

import CAdw
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

/// What the device is, in the words the app says it with: "isn’t on this
/// computer" (OfflineText).
enum Device {
    static var model: String { "computer" }
}

/// The library's words that the shared files say too (the iPhone's are in
/// LibraryParts.swift, beside SwiftUI).
enum LibraryText {
    /// "1 song", "12 songs".
    static func songs(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }
}

// MARK: - Songs kept on the machine

extension OfflinePaths {
    /// $XDG_DATA_HOME/jukebox/offline, ~/.local/share/jukebox/offline where
    /// that is not set: the user's data, where GNOME's apps keep theirs. A
    /// folder of its own, as OfflineDisk.load removes whatever in it is not
    /// the account's.
    nonisolated static var base: URL {
        let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".local/share", isDirectory: true)
        return data.appendingPathComponent("jukebox/offline", isDirectory: true)
    }
}

extension OfflineDisk {
    /// Made once a launch. A desktop has no one flag that keeps a folder out
    /// of every backup tool, so none is set.
    nonisolated static func prepareBase() {
        try? FileManager.default.createDirectory(at: OfflinePaths.base, withIntermediateDirectories: true)
    }
}

/// On the iPhone, the system's news of downloads made while the app was not
/// running; Linux downloads only while Jukebox runs, so there is none.
enum OfflineBackgroundEvents {
    static weak var store: OfflineStore?
    static func tellSystem() {}
}

extension OfflineStore {
    /// The desktop's power saver, as Low Power Mode: the keep waits in it,
    /// what was chosen goes on. False where nothing says.
    nonisolated static var isLowPowerNow: Bool {
        guard let monitor = g_power_profile_monitor_dup_default() else { return false }
        defer { g_object_unref(raw(monitor)) }
        return g_power_profile_monitor_get_power_saver_enabled(monitor) != 0
    }

    /// The network as GLib's monitor tells it (NetworkManager, or the
    /// kernel's routes), and the power saver, told to the store as they
    /// change. The store keeps what this returns.
    // ponytail: a metered connection is never "expensive" here, so nothing
    // waits for Wi-Fi; the Mac's Download on a Hotspot if someone downloads
    // over a phone's hotspot.
    func watchSystem() -> AnyObject {
        let network = g_network_monitor_get_default()!
        let state = { OfflinePathState(isSatisfied: g_network_monitor_get_network_available(network) != 0, isExpensive: false) }
        on(raw(network), "notify::network-available") { [weak self] in self?.pathChanged(state()) }
        let power = g_power_profile_monitor_dup_default()
        if let power {
            on(raw(power), "notify::power-saver-enabled") { [weak self] in
                self?.powerChanged(isLowPower: g_power_profile_monitor_get_power_saver_enabled(power) != 0)
            }
        }
        // As NWPathMonitor tells its first path once started.
        Task { [weak self] in self?.pathChanged(state()) }
        return OfflineSystemWatch(power: power)
    }
}

/// The power monitor, kept as long as the store (GLib's network monitor is
/// the process's own).
private final class OfflineSystemWatch {
    let power: OpaquePointer?
    init(power: OpaquePointer?) { self.power = power }
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
