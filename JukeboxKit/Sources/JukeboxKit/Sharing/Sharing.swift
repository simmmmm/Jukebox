// Sharing a song, an album or an artist with a friend. The friend cannot
// play the listener's own server, so what goes is the name and a link that
// opens in the friend's own app (features.md, "De moeite waard": "titel en
// artiest met een link die in zijn eigen app opent"; "doe alles", 18
// November 2026).
//
// A server that makes its own link to play (Navidrome's shares) has Copy
// Share Link instead (the app's ShareLinks.swift). Elsewhere, the link:
// 1. Odesli's page (song.link, album.link), which opens Spotify, Apple
//    Music, Tidal and the rest, found through Apple's public iTunes search.
//    Only the title and the main artist leave the device, as for LRCLIB, and
//    only when the listener asks to share. An artist has no Odesli page by
//    Apple's id (artist.link/i/… is empty, measured 18 November 2026), so
//    its link is Apple Music's page, which opens on the web elsewhere.
// 2. None: the name alone. Better than a link to someone else's song.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What is shared.
public enum ShareItem: Sendable, Hashable {
    case track(Track)
    case album(Album)
    case artist(Artist)

    /// "Night Bus by Blue Room Trio", "Harbour Lights by Blue Room Trio",
    /// "Blue Room Trio".
    public var words: String {
        switch self {
        case let .track(track):
            let artist = track.primaryArtistName
            return artist.isEmpty ? track.name : "\(track.name) by \(artist)"
        case let .album(album):
            let artist = album.primaryArtist?.name ?? ""
            return artist.isEmpty ? album.name : "\(album.name) by \(artist)"
        case let .artist(artist):
            return artist.name
        }
    }

    /// The name for a share sheet's preview.
    public var name: String {
        switch self {
        case let .track(track): track.name
        case let .album(album): album.name
        case let .artist(artist): artist.name
        }
    }
}

extension Track {
    /// Who a friend would look for: the first performer, else the album's.
    var primaryArtistName: String { artists.first?.name ?? albumArtist?.name ?? "" }
}

/// The words and the link, as one text to send.
public struct ShareText: Sendable, Hashable {
    public var words: String
    public var url: URL?

    public init(words: String, url: URL?) {
        self.words = words
        self.url = url
    }

    /// "Night Bus by Blue Room Trio" and the link on the next line.
    public var text: String { url.map { "\(words)\n\($0.absoluteString)" } ?? words }
}

public struct Sharing: Sendable {
    public static let searchEndpoint = URL(string: "https://itunes.apple.com/search")!
    let transport: any HTTPTransport
    /// Short: the listener waits with the menu just closed.
    let timeout: TimeInterval = 5

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Odesli's or Apple Music's link, else the words alone. Never throws:
    /// a share always has its words.
    public func text(for item: ShareItem) async -> ShareText {
        ShareText(words: item.words, url: try? await publicLink(for: item))
    }

    /// Odesli's page for a song or an album, Apple Music's for an artist,
    /// found by name; nil when nothing found is the same title by the same
    /// artist.
    func publicLink(for item: ShareItem) async throws -> URL? {
        let (term, entity): (String, String)
        switch item {
        case let .track(track): (term, entity) = ("\(track.primaryArtistName) \(track.name)", "song")
        case let .album(album): (term, entity) = ("\(album.primaryArtist?.name ?? "") \(album.name)", "album")
        case let .artist(artist): (term, entity) = (artist.name, "musicArtist")
        }
        var parts = URLComponents(url: Self.searchEndpoint, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "term", value: term), URLQueryItem(name: "media", value: "music"),
                            URLQueryItem(name: "entity", value: entity), URLQueryItem(name: "limit", value: "10")]
        var request = URLRequest(url: parts.url!, timeoutInterval: timeout)
        request.httpMethod = "GET"
        let response = try await transport.send(request)
        guard response.status == 200 else { return nil }
        let results = try JSONDecoder().decode(SearchAnswer.self, from: response.body).results
        return Self.link(for: item, in: results)
    }

    static func link(for item: ShareItem, in results: [SearchAnswer.Result]) -> URL? {
        switch item {
        case let .track(track):
            let found = results.first {
                LRCLIBClient.sameTitle($0.trackName ?? "", track.name)
                    && LRCLIBClient.sameArtist($0.artistName ?? "", track.primaryArtistName)
            }
            return found?.trackId.flatMap { URL(string: "https://song.link/i/\($0)") }
        case let .album(album):
            let found = results.first {
                LRCLIBClient.sameTitle($0.collectionName ?? "", album.name)
                    && LRCLIBClient.sameArtist($0.artistName ?? "", album.primaryArtist?.name ?? "")
            }
            return found?.collectionId.flatMap { URL(string: "https://album.link/i/\($0)") }
        case let .artist(artist):
            let found = results.first { NameKey.artist($0.artistName ?? "") == artist.key }
            return found?.artistLinkUrl.flatMap { URL(string: $0) }
        }
    }

    /// Apple's answer: {"resultCount": n, "results": [{"trackId", "collectionId",
    /// "artistName", "trackName", "collectionName", "artistLinkUrl"}]}.
    struct SearchAnswer: Decodable {
        struct Result: Decodable {
            var trackId: Int?
            var collectionId: Int?
            var artistName: String?
            var trackName: String?
            var collectionName: String?
            var artistLinkUrl: String?
        }
        var results: [Result]
    }
}
