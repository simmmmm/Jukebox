// The signed-in session in the keychain: Jellyfin's access token, or a
// Subsonic server's token and salt (or API key), is as good as a password to
// that server, so it is not kept in UserDefaults. One item, as before the
// app spoke Subsonic: what the Jellyfin-only app saved there (its
// Credentials, with `accessToken` and no `kind`) reads as a Jellyfin
// ServerCredentials, so the update signs nobody out (JukeboxKit's
// ServerCredentialsTests). Saved again, it is written in the new shape.

import Foundation
import JukeboxKit
import Security

enum Keychain {
    private static let service = "com.tijmen.Jukebox"
    private static let account = "credentials"

    static func save(_ credentials: ServerCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        deleteCredentials()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Readable after the first unlock: the radio fetches its next
            // tracks with the phone locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(sent(query), nil)
    }

    static func loadCredentials() -> ServerCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(sent(query), &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ServerCredentials.self, from: data)
    }

    static func deleteCredentials() {
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
    /// signed identity, which TestFlight's builds have. The iPhone's query
    /// goes as it always did.
    private static func sent(_ query: [String: Any]) -> CFDictionary {
        var query = query
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query as CFDictionary
    }
}
