// What the shared files (Package.swift's `shared`) ask of the platform, in
// Linux's own way: where the accounts' sessions are kept, what the device is
// called, and for the songs kept on the machine (the shared OfflineStore)
// where they live, the network and the power saver.

import CAdw
import CGlue
import Foundation
import JukeboxKit

/// The sessions in the desktop's keyring (libsecret: GNOME Keyring,
/// KWallet): a server's token is as good as a password to it. The
/// iPhone's Keychain.swift, by the same name and with the same two items:
/// "credentials", the session signed in (all a build from before the list
/// of accounts knows), and "accounts", every account kept.
///
/// A desktop without a keyring (a bare Hyprland, some XFCEs) keeps them in
/// files only its user can read, as ssh keeps a key: "werkt het dan ook
/// nice in bijv hyprland xfce kde" (the photographer, 14 November 2026).
/// Tokens, never a password, which is not kept anywhere.
enum Keychain {
    private static let active = "credentials"
    private static let list = "accounts"

    /// ~/.local/share/Jukebox/credentials.json and accounts.json.
    private static func file(_ item: String) -> URL {
        let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return data.appendingPathComponent("Jukebox/\(item).json", isDirectory: false)
    }

    static func save(_ credentials: ServerCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        write(data, as: active)
    }

    static func saveAccounts(_ accounts: [ServerCredentials]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        write(data, as: list)
    }

    /// The session signed in, and every account kept (nil: no list yet).
    /// Nil as a whole when the session could not be read (a keyring that
    /// did not answer); `listKnown` false when the list could not, so
    /// nothing is written over it from what was not read.
    static func loadAccounts() -> (active: ServerCredentials?, saved: [ServerCredentials]?, listKnown: Bool)? {
        guard case let .read(signedIn) = read(active) else { return nil }
        let session = signedIn.flatMap { try? JSONDecoder().decode(ServerCredentials.self, from: $0) }
        guard case let .read(kept) = read(list) else { return (session, nil, false) }
        return (session, kept.flatMap { try? JSONDecoder().decode([ServerCredentials].self, from: $0) }, true)
    }

    /// Signed out of the last account: none is signed in.
    static func deleteCredentials() {
        if jb_secret_available() != 0 { jb_secret_clear(active) }
        try? FileManager.default.removeItem(at: file(active))
    }

    private enum Answer {
        /// Read; nil when there is no such item.
        case read(Data?)
        case unreadable
    }

    /// The keyring's item where there is one, else the file (as it was
    /// kept while the desktop had no keyring, or one that did not answer
    /// when it was written). A keyring that does not answer, and no file:
    /// not known.
    private static func read(_ item: String) -> Answer {
        var failed: gboolean = 0
        if hasKeyring, let found = jb_secret_load(item, &failed) {
            defer { g_free(found) }
            return .read(Data(String(cString: found).utf8))
        }
        // Each question to a keyring that does not answer waits out D-Bus's
        // 25 seconds: asked once a launch, not for every item.
        if failed != 0 { keyringAnswers = false }
        let kept = try? Data(contentsOf: file(item))
        // Not in a file, and a keyring is there that did not answer: it may
        // hold it.
        return kept == nil && !keyringAnswers && jb_secret_available() != 0 ? .unreadable : .read(kept)
    }

    private static var keyringAnswers = true
    private static var hasKeyring: Bool { keyringAnswers && jb_secret_available() != 0 }

    private static func write(_ data: Data, as item: String) {
        if hasKeyring, let json = String(data: data, encoding: .utf8),
           jb_secret_store(item, json) != 0 {
            // In the keyring now: not in a file as well.
            try? FileManager.default.removeItem(at: file(item))
            return
        }
        let url = file(item)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written whole beside it, then put in its place in one step: the
        // file is the old one or the new one, never half of either (a full
        // disk, the app ended mid-write). Opened with its permissions (and
        // given them again, were it there already), so it is never readable
        // by another in between.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(item).json.new", isDirectory: false)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { return }
        fchmod(descriptor, 0o600)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            unlink(temporary.path)
            return
        }
        if rename(temporary.path, url.path) != 0 { unlink(temporary.path) }
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
    /// change. The store keeps what this returns. A metered connection
    /// (NetworkManager's guess for a phone's hotspot, or GNOME Settings'
    /// switch) costs data as the iPhone's mobile network does: streamed at
    /// Streaming on a Metered Connection's quality, downloads wait unless
    /// Download on a Metered Connection is on (DataCost).
    func watchSystem() -> AnyObject {
        let network = g_network_monitor_get_default()!
        let state = { OfflinePathState(isSatisfied: g_network_monitor_get_network_available(network) != 0,
                                       isExpensive: g_network_monitor_get_network_metered(network) != 0) }
        on(raw(network), "notify::network-available") { [weak self] in self?.pathChanged(state()) }
        on(raw(network), "notify::network-metered") { [weak self] in self?.pathChanged(state()) }
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
