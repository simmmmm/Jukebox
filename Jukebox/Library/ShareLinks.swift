// Copy Share Link: a link anyone can open in a browser and play, made by the
// listener's own server (Navidrome's shares, JukeboxKit's SubsonicShare),
// so a friend hears a song without an account. Only where the server
// answered that it shares (`ServerCapability.share`); Jellyfin, Emby and
// Plex have nothing like it, so no item there. In a song's and an album's
// menu, beside Favorite; no new button. Made on the tap, not when the menu
// opens, and the same link again for the same songs. One file for every
// client (Package.swift's `shared`); each copies it its own way.

import Foundation
import JukeboxKit

extension LibraryStore {
    /// The link, or nil when the server would not make one.
    func shareLink(for id: ItemID, tracks: [ItemID]) async -> URL? {
        guard can(.share), let server else { return nil }
        return try? await server.shareURL(for: id, tracks: tracks)
    }
}
