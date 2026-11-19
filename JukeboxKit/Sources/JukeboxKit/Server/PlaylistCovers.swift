// The listener's own photograph as a playlist's cover: "Voor de app van een
// fotograaf" (features.md; "doe alles", 18 November 2026).
//
// Only where it works, measured on Jellyfin 12.4 (18 November 2026):
// POST /Items/{id}/Images/Primary, the image base64 in the body, answers
// 204 for an administrator and 403 for any other user, whose own playlist
// it is or not (Jellyfin's RequiresElevation; Emby's admin role, from which
// it came). So the app offers it only to an administrator.
// Emby 4.10 takes it the same way from its administrator (measured; its
// test server has no other user to refuse).
// Not offered: Navidrome and the other Subsonic servers (the Subsonic API
// has no call to set an image), Plex (not tried: its test server would need
// plex.tv).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A server that takes a playlist's image: `server as? any PlaylistCovers`.
public protocol PlaylistCovers: MusicServer {
    /// Whether this user may set one (Jellyfin: an administrator).
    func playlistCoversAllowed() async throws -> Bool
    /// The playlist's own image, as JPEG; the playlist's next
    /// `imageTag` is the new one's.
    func setPlaylistCover(playlistID: ItemID, jpeg: Data) async throws
}

extension JellyfinServer: PlaylistCovers {
    public func playlistCoversAllowed() async throws -> Bool {
        try await mapped { try await client.isAdministrator() }
    }

    public func setPlaylistCover(playlistID: ItemID, jpeg: Data) async throws {
        try await mapped { try await client.setPrimaryImage(itemID: playlistID, jpeg: jpeg) }
    }
}

extension JellyfinClient {
    /// GET /Users/{id}: Policy.IsAdministrator.
    func isAdministrator() async throws -> Bool {
        let user = try requireUser()
        struct Answer: Decodable {
            struct UserPolicy: Decodable { var IsAdministrator: Bool? }
            var Policy: UserPolicy?
        }
        return try await get(Answer.self, "/Users/\(Self.segment(user))").Policy?.IsAdministrator ?? false
    }

    /// POST /Items/{id}/Images/Primary, the bytes base64 as Jellyfin reads
    /// them, with the image's own type.
    func setPrimaryImage(itemID: ItemID, jpeg: Data) async throws {
        _ = try requireUser()
        var request = URLRequest(url: url("/Items/\(Self.segment(itemID))/Images/Primary"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg.base64EncodedData()
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw JellyfinError.transport(error.localizedDescription)
        }
        try Self.check(response)
    }
}
