// Share: a link anyone can open in a browser and play, made by the
// listener's own server (Subsonic's createShare; Navidrome's share page).
// A friend cannot play from someone else's server otherwise. Only where
// the server answers getShares (`ServerCapability.share`): Navidrome 0.64.2
// shares by default and answers 501 with ND_ENABLESHARING=false (measured,
// 18 November 2026). Jellyfin, Emby and Plex have nothing like it.
//
// The link is the server's own `url`, which honours its ShareURL setting
// behind a proxy. One link per thing: a song or album shared before is
// shared again with the same link, not a new share each tap.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SubsonicShares: Decodable {
    var share: [SubsonicShare]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        share = c.lenientList(SubsonicShare.self, SubsonicKey("share"))
    }
}

struct SubsonicShare: Decodable {
    var id: String?
    var url: String?
    var entry: [SubsonicChild]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        id = c.lenientString(SubsonicKey("id"))
        url = c.lenientString(SubsonicKey("url"))
        entry = c.lenientList(SubsonicChild.self, SubsonicKey("entry"))
    }
}

/// A share the server keeps: its link and the songs in it.
public struct ServerShare: Sendable, Hashable {
    public var id: String
    public var url: URL
    public var trackIDs: [ItemID]
}

extension SubsonicClient {
    /// This user's shares.
    public func shares() async throws -> [ServerShare] {
        try await call("getShares", timeout: 15, lacking: .share).shares.compactMap(\.asShare)
    }

    /// `tracks`: the songs `id` stands for (an album's), to find a share of
    /// them made before. A server with sharing off answers 501:
    /// `unsupported(.share)`.
    public func shareURL(for id: ItemID, tracks: [ItemID]) async throws -> URL {
        // The same songs in any order: an album's may come in another.
        let wanted = Set(tracks)
        if !wanted.isEmpty, let kept = try await shares().first(where: { Set($0.trackIDs) == wanted }) {
            return kept.url
        }
        let body = try await call("createShare", [URLQueryItem(name: "id", value: id)], timeout: 15, lacking: .share)
        guard let made = body.shares.lazy.compactMap(\.asShare).first else {
            throw MusicServerError.decoding("createShare answered without a link")
        }
        return made.url
    }

    /// The shares of exactly these songs, deleted (the tests' tidying up).
    func deleteShares(for tracks: [ItemID]) async throws {
        for share in try await shares() where share.trackIDs == tracks {
            _ = try await call("deleteShare", [URLQueryItem(name: "id", value: share.id)], timeout: 15)
        }
    }
}

extension SubsonicShare {
    var asShare: ServerShare? {
        guard let id, !id.isEmpty, let url = url.flatMap(URL.init(string:)) else { return nil }
        return ServerShare(id: id, url: url, trackIDs: entry.compactMap(\.id))
    }
}
