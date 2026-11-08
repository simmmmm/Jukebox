// CONTRACT — signatures fixed, bodies the kit agent's (docs/ARCHITECTURE.md).
//
// Last.fm, only when the listener has put their own (free) API key in
// Settings — the photographer chose this, 8 November 2026: the radio works
// from the library alone, and knows who sounds like whom far better with
// Last.fm. Only artist names and track titles leave the phone.
//
// https://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=…&api_key=…&format=json
// Note: artist.getsimilar gives `match` as a string ("0.87"), track.getsimilar
// as a number; an error is {"error": 10, "message": "Invalid API key"} with
// status 200 or 403.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LastFMClient: Sendable {
    public struct SimilarArtist: Codable, Sendable, Hashable {
        public var name: String
        /// 0 … 1.
        public var match: Double

        public init(name: String, match: Double) {
            self.name = name
            self.match = match
        }
    }

    public struct SimilarTrack: Codable, Sendable, Hashable {
        public var artist: String
        public var title: String
        /// 0 … 1.
        public var match: Double

        public init(artist: String, title: String, match: Double) {
            self.artist = artist
            self.title = title
            self.match = match
        }
    }

    public struct TopTrack: Codable, Sendable, Hashable {
        public var title: String
        public var playcount: Int
        /// 1 is the most played.
        public var rank: Int

        public init(title: String, playcount: Int, rank: Int) {
            self.title = title
            self.playcount = playcount
            self.rank = rank
        }
    }

    public enum Failure: Error, Sendable, Equatable, LocalizedError {
        case invalidKey
        case rateLimited
        case notFound
        case other(String)

        public var errorDescription: String? {
            switch self {
            case .invalidKey: "Last.fm did not accept the API key."
            case .rateLimited: "Last.fm asks to wait a moment."
            case .notFound: "Last.fm does not know that."
            case let .other(message): message
            }
        }
    }

    public let apiKey: String
    public let transport: any HTTPTransport

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    /// artist.getSimilar, with autocorrect.
    public func similarArtists(to artist: String, limit: Int = 50) async throws -> [SimilarArtist] {
        fatalError("not built yet")
    }

    /// track.getSimilar, with autocorrect.
    public func similarTracks(artist: String, title: String, limit: Int = 50) async throws -> [SimilarTrack] {
        fatalError("not built yet")
    }

    /// artist.getTopTracks: an artist page's "Top Songs", by Last.fm's
    /// play counts rather than only this listener's.
    public func topTracks(artist: String, limit: Int = 20) async throws -> [TopTrack] {
        fatalError("not built yet")
    }

    /// Whether the key works (one cheap call), for Settings.
    public func validateKey() async -> Bool {
        fatalError("not built yet")
    }
}

/// Builds and keeps the SimilarityGraph: the library's own edges, and
/// Last.fm's for the artists the listener plays most, fetched a few a second
/// (Last.fm asks for at most five), kept on disk for 30 days so a launch
/// asks again only for what is new or stale.
public actor SimilarityService {
    /// - Parameter directory: where the graph and Last.fm's answers are kept
    ///   (the app's Caches).
    public init(directory: URL, lastFM: LastFMClient?) {
        fatalError("SimilarityService is not built yet")
    }

    /// The graph as it is now: the library's edges, plus what is on disk.
    public func graph(for snapshot: LibrarySnapshot) -> SimilarityGraph {
        fatalError("not built yet")
    }

    /// Asks Last.fm about up to `maxArtists` artists, most liked first, that
    /// are not on disk or are stale, and returns the graph with them.
    /// Nothing when there is no key. Stops quietly on a network error.
    public func enrich(snapshot: LibrarySnapshot, priority artistKeys: [String],
                       maxArtists: Int = 150) async -> SimilarityGraph {
        fatalError("not built yet")
    }

    /// Last.fm's similar tracks for one track, as library tracks, for a song
    /// station. Empty when there is no key or nothing matches.
    public func similarTracks(to track: Track, in snapshot: LibrarySnapshot) async -> [Neighbor] {
        fatalError("not built yet")
    }

    /// Last.fm's top tracks of an artist, as library tracks, most played
    /// first. Empty when there is no key.
    public func topTracks(artist: ArtistRef, in snapshot: LibrarySnapshot, limit: Int = 10) async -> [Track] {
        fatalError("not built yet")
    }
}
