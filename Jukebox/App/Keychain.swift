// The sessions in the keychain: Jellyfin's access token, or a Subsonic
// server's token and salt (or API key), is as good as a password to that
// server, so none is kept in UserDefaults. Two items:
//
// - "credentials", the session signed in, as it always was: what the
//   Jellyfin-only app saved there (its Credentials, with `accessToken` and
//   no `kind`) reads as a Jellyfin ServerCredentials, so no update signs
//   anyone out (JukeboxKit's ServerCredentialsTests). A build from before
//   the list of accounts reads and writes this one alone.
// - "accounts", every account kept on the device (JukeboxKit's
//   SavedAccounts puts the two together at a launch; Accounts.swift).

import Foundation
import JukeboxKit
import Security

enum Keychain {
    private static let service = "com.tijmen.Jukebox"
    private static let active = "credentials"
    private static let list = "accounts"

    /// The session signed in.
    static func save(_ credentials: ServerCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        write(data, as: active)
    }

    static func saveAccounts(_ accounts: [ServerCredentials]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        write(data, as: list)
    }

    /// The session signed in, and every account kept (nil: no list yet, an
    /// install from before it). Nil as a whole when the session could not
    /// be read (the keychain locked, before the first unlock); `listKnown`
    /// false when the list could not, so nothing is written over it from
    /// what was not read.
    static func loadAccounts() -> (active: ServerCredentials?, saved: [ServerCredentials]?, listKnown: Bool)? {
        guard case let .read(signedIn) = read(active) else { return nil }
        let session = signedIn.flatMap { try? JSONDecoder().decode(ServerCredentials.self, from: $0) }
        guard case let .read(kept) = read(list) else { return (session, nil, false) }
        return (session, kept.flatMap { try? JSONDecoder().decode([ServerCredentials].self, from: $0) }, true)
    }

    /// Signed out of the last account: none is signed in.
    static func deleteCredentials() {
        delete(active)
    }

    // MARK: The items

    private enum Answer {
        /// Read; nil when there is no such item.
        case read(Data?)
        case unreadable
    }

    private static func read(_ account: String) -> Answer {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        switch SecItemCopyMatching(sent(query), &result) {
        case errSecSuccess: return .read(result as? Data)
        case errSecItemNotFound: return .read(nil)
        default: return .unreadable
        }
    }

    /// Over the item in place, or a new one when there is none: never a
    /// delete and then an add, which a failed add would leave with nothing
    /// (the list of accounts lost).
    private static func write(_ data: Data, as account: String) {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let changes: [String: Any] = [
            kSecValueData as String: data,
            // Readable after the first unlock: the radio fetches its next
            // tracks with the phone locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        guard SecItemUpdate(sent(item), changes as CFDictionary) == errSecItemNotFound else { return }
        SecItemAdd(sent(item.merging(changes) { $1 }), nil)
    }

    private static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(sent(query))
    }

    /// The query as the keychain gets it. On the Mac, in the iPhone's kind
    /// of keychain, the data protection one, as Apple advises for new code
    /// (TN3137): the file-based one is the Mac's legacy. It needs the app's
    /// signed identity, which TestFlight's builds have. A debug build made
    /// on the photographer's Mac has no provisioning profile, so it keeps
    /// the sign-in in the file-based one, which knows the build by its
    /// developer certificate: it stays signed in from one build to the next.
    /// The iPhone's query goes as it always did.
    private static func sent(_ query: [String: Any]) -> CFDictionary {
        var query = query
        #if os(macOS) && !DEBUG
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query as CFDictionary
    }
}
