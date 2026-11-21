// Which account an id belongs to, while several are on at once
// (docs/MULTI-SERVER.md, "Identity"). The photographer, 21 November 2026:
// "ik zou niet weten waarom we die beperking moeten hebben als er meer
// mogelijk zijn". Ids collide across servers (Emby's "378", Plex's "150"),
// so in memory an id carries its account: "3fa9c1d2:378". On disk and to
// the server it stays the server's own: MergedServer strips the tag before
// a member is asked and adds it to what comes back.

import Foundation

public struct AccountTag: Hashable, Sendable, CustomStringConvertible {
    /// 8 lower-case hex digits. A fixed length, so splitting never has to
    /// guess where the tag ends, whatever a Subsonic id contains.
    public let value: String

    /// FNV-1a of the server's id and the user's (SavedAccounts.stableHash):
    /// the same on every launch and platform. The server's id, not its
    /// address, so a Jellyfin reached at home and away is one account.
    public init(_ credentials: ServerCredentials) {
        value = SavedAccounts.stableHash(credentials.serverID + "\n" + credentials.userID)
    }

    init?(value: Substring) {
        guard value.count == 8, value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        self.value = String(value)
    }

    public var description: String { value }

    /// "3fa9c1d2:<id>".
    public func wrap(_ id: ItemID) -> ItemID { value + ":" + id }

    /// The server's own id, when `id` is this account's; nil for another's
    /// or an untagged one. Checked against this tag, not any 8 hex digits
    /// and a colon: a bare Subsonic id may look like that.
    public func unwrap(_ id: ItemID) -> ItemID? {
        guard id.count > 9, id.hasPrefix(value + ":") else { return nil }
        return String(id.dropFirst(9))
    }

    /// The tag and the server's own id of a tagged id; nil when it is not
    /// tagged.
    public static func split(_ id: ItemID) -> (tag: AccountTag, bare: ItemID)? {
        guard id.count > 9, id[id.index(id.startIndex, offsetBy: 8)] == ":",
              let tag = AccountTag(value: id.prefix(8)) else { return nil }
        return (tag, String(id.dropFirst(9)))
    }
}
