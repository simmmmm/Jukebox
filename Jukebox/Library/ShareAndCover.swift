// What the library store does for sharing (JukeboxKit's Sharing) and for a
// playlist's own picture (JukeboxKit's PlaylistCovers), the same on every
// client: each draws its own menu item and picker, and calls these.

import Foundation
import JukeboxKit

extension LibraryStore {
    /// The words and the link a friend gets for a song, an album or an
    /// artist (Sharing: the server's link, else Odesli's, else the words).
    func shareText(_ item: ShareItem) async -> ShareText {
        await Sharing().text(for: item)
    }

    /// Whether Share… (Copy Link) is offered: not for a song or an album on
    /// a server that makes its own link to play them (Copy Share Link,
    /// ShareLinks.swift), so a menu has one way to share, not two.
    func sharesPublicLink(_ item: ShareItem) -> Bool {
        if case .artist = item { return true }
        return !can(.share)
    }

    /// Whether this account may give a playlist of its own a picture: the
    /// server takes one (Jellyfin, Emby) and the user may set it (an
    /// administrator). Asked once a session; nothing is offered while it
    /// is not known.
    func playlistCoversAllowed() async -> Bool {
        guard let server = server as? any PlaylistCovers else { return false }
        let key = "\(server.credentials.serverID)/\(server.credentials.userID)"
        if let known = Self.coversAllowed[key] { return known }
        guard let allowed = try? await server.playlistCoversAllowed() else { return false }
        Self.coversAllowed[key] = allowed
        return allowed
    }

    private static var coversAllowed: [String: Bool] = [:]

    /// The picture, as a JPEG, as the playlist's own; then the playlist's
    /// new image tag, so every cover of it shows the new one (the image
    /// cache is keyed by the tag).
    func setCover(_ jpeg: Data, of playlist: Playlist) async throws {
        guard let server = server as? any PlaylistCovers else { throw MusicServerError.unsupported(nil) }
        try await server.setPlaylistCover(playlistID: playlist.id, jpeg: jpeg)
        let tag = try await server.playlists().first { $0.id == playlist.id }?.imageTag
        notePlaylistImage(playlist.id, tag: tag)
    }
}
