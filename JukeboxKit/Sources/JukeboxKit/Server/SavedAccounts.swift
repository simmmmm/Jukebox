// The accounts kept on one device, one of them signed in: a home server and
// a shared one, or two people on one server. Self-hosters often have more
// than one, and every comparable player keeps them side by side ("maak ze
// allemaal maar", the photographer, 17 November 2026, of the features those
// players have).
//
// The keychain keeps two things (the app's Keychain.swift, Linux's
// Platform.swift): the active session as it always did, one item, which is
// what a build from before the list still reads, and the list beside it.
// This is how the two are put together at a launch. Before the list there
// was the one session only: it becomes the list's only entry, and nobody
// signs in again.

import Foundation

public struct SavedAccounts: Hashable, Sendable {
    /// Every account, in the order they were added.
    public private(set) var all: [ServerCredentials]
    /// The one signed in; nil when signed out.
    public private(set) var active: ServerCredentials?
    /// The list read differs from `all`: it is written back once, so the
    /// next launch reads what this one made.
    public let needsSaving: Bool

    /// From the keychain's two items. `saved` is nil when there is no list
    /// yet (every install from before it). The active session joins the
    /// list, in its own copy's place: it is the newer of the two, as a
    /// build from before the list signs in again without touching the
    /// list. With no active session and a list (a launch after one ended
    /// between the two writes), the first saved account is the active
    /// one. Made again from its own result, nothing changes.
    public init(active: ServerCredentials?, saved: [ServerCredentials]?) {
        var all = saved ?? []
        if let active {
            Self.keep(active, in: &all)
        }
        self.all = all
        self.active = active.flatMap { active in all.first { $0.isSameAccount(as: active) } } ?? all.first
        needsSaving = all != (saved ?? [])
    }

    /// An account from before the list: the one session the device had.
    /// Its files from then (the history, the stations started) become
    /// this account's.
    public static func isMigrating(active: ServerCredentials?, saved: [ServerCredentials]?) -> Bool {
        active != nil && saved == nil
    }

    /// Signed in, perhaps again to an account already here (a new token):
    /// it is kept in its place, or added at the end, and is the active one.
    /// True when it was not here before.
    @discardableResult
    public mutating func activate(_ account: ServerCredentials) -> Bool {
        let added = Self.keep(account, in: &all)
        // The list's copy: with the folder name it was given, or kept.
        active = all.first { $0.isSameAccount(as: account) } ?? account
        return added
    }

    /// The same account with what its server said of itself since (a new
    /// version, its capabilities), in its place.
    public mutating func update(_ account: ServerCredentials) {
        guard let at = all.firstIndex(where: { $0.isSameAccount(as: account) }) else { return }
        var account = account
        if account.folderName == nil { account.folderName = all[at].folderName }
        all[at] = account
        if active?.isSameAccount(as: account) == true { active = account }
    }

    /// Signed out of. When it was the active one, the first that is left
    /// becomes active (nil when none is).
    public mutating func remove(_ account: ServerCredentials) {
        all.removeAll { $0.isSameAccount(as: account) }
        if active?.isSameAccount(as: account) != false { active = all.first }
    }

    /// In its place when it is there (true: it was not, and is added).
    /// A new account whose folder name another saved account has already
    /// gets one of its own; one already here keeps the one it had.
    @discardableResult
    private static func keep(_ account: ServerCredentials, in list: inout [ServerCredentials]) -> Bool {
        var account = account
        if let at = list.firstIndex(where: { $0.isSameAccount(as: account) }) {
            if account.folderName == nil { account.folderName = list[at].folderName }
            list[at] = account
            return false
        }
        if account.folderName == nil, list.contains(where: { $0.folder == account.folder }) {
            account.folderName = account.baseFolder + "-" + Self.stableHash(account.serverURL.absoluteString + "\n" + account.userID)
        }
        list.append(account)
        return true
    }

    /// FNV-1a, 32 bits, in hex: the same on every launch and platform, as
    /// Swift's own hash is not.
    static func stableHash(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }
}

extension ServerCredentials {
    /// The same server and user: a new token, version or capabilities do
    /// not make another account. What the library cache and the downloads'
    /// folder are named by, too.
    public func isSameAccount(as other: ServerCredentials) -> Bool {
        serverID == other.serverID && userID == other.userID
    }

    /// The name of the account's own folders and files on the device (its
    /// songs, its history; the app's OfflinePaths and AccountFiles).
    public var folder: String { folderName ?? baseFolder }

    /// The server's id and the user's, letters and digits only, as every
    /// account's folders were named before there was a list: Jellyfin's
    /// hex GUIDs, or a Subsonic server's URL and the user's name.
    public var baseFolder: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return "\(String(serverID.filter { allowed.contains($0) }))-\(String(userID.filter { allowed.contains($0) }))"
    }
}
