// What a cover is kept under on disk, on every client: the server, the
// path and the picture's own words (its id, tag and size), never the
// session's. A Subsonic cover's address carries the account's `u`, `t` and
// `s` (or its API key, or its password), a Plex one its token: kept by
// address, the cache's keys would hold them outside the keychain. Kept by
// this, a cover is also the same file across sign-ins, as a Subsonic token
// is made new at each.

import Foundation

public enum CoverKey {
    /// The query's names a cover's address may keep: Jellyfin's and Emby's
    /// sizes, quality and tag (JellyfinClient.imageURL), Subsonic's id and
    /// size (getCoverArt), Plex's transcoder's size and picture
    /// (PlexServer.artworkURL). Anything else goes, whatever a server adds.
    static let kept: Set<String> = ["id", "size", "tag", "quality", "fillwidth", "fillheight",
                                    "maxwidth", "maxheight", "width", "height", "url"]

    /// `url` with no user, password or fragment and only `kept`'s query
    /// items, in a fixed order.
    public static func of(_ url: URL) -> URL {
        // Never the address itself, should it not parse: then without its query.
        let bare = URL(string: String(url.absoluteString.prefix { $0 != "?" && $0 != "#" })) ?? URL(fileURLWithPath: "/")
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return bare }
        parts.user = nil
        parts.password = nil
        parts.fragment = nil
        let items = (parts.queryItems ?? []).filter { kept.contains($0.name.lowercased()) }
            .sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        parts.queryItems = items.isEmpty ? nil : items
        return parts.url ?? bare
    }
}
