// CONTRACT — signatures fixed, bodies the kit agent's (docs/ARCHITECTURE.md).
//
// The whole library at one moment, indexed for the radio and the mixes:
// by id, artist, album, genre and decade, and by name for matching what
// Last.fm says to what the library has. A value: made off the main actor
// from the tracks LibraryStore holds, handed to the radio, never changed.

import Foundation

public struct LibrarySnapshot: Sendable {
    public let tracks: [Track]

    public init(tracks: [Track]) {
        self.tracks = tracks
        fatalError("LibrarySnapshot.init is not built yet")
    }

    public static let empty = LibrarySnapshot(tracks: [])

    public var isEmpty: Bool { tracks.isEmpty }

    public func track(id: ItemID) -> Track? {
        fatalError("not built yet")
    }

    /// Tracks with this artist key among their performers or as album artist.
    public func tracks(artistKey: String) -> [Track] {
        fatalError("not built yet")
    }

    /// An album's tracks in disc and track order.
    public func tracks(albumID: ItemID) -> [Track] {
        fatalError("not built yet")
    }

    public func tracks(genreKey: String) -> [Track] {
        fatalError("not built yet")
    }

    /// Tracks from the decade starting at `decade` (1990 for the 1990s).
    public func tracks(decade: Int) -> [Track] {
        fatalError("not built yet")
    }

    /// Every artist key that is an album artist or performer, with how many
    /// tracks carry it.
    public var artistTrackCounts: [String: Int] {
        fatalError("not built yet")
    }

    /// The artist as the library spells it, with its id when known.
    public func artist(key: String) -> ArtistRef? {
        fatalError("not built yet")
    }

    /// Every genre key with how many tracks carry it.
    public var genreTrackCounts: [String: Int] {
        fatalError("not built yet")
    }

    /// The genre as the library spells it.
    public func genreName(key: String) -> String? {
        fatalError("not built yet")
    }

    /// Decades with tracks (1970, 1980, …) and how many.
    public var decadeTrackCounts: [Int: Int] {
        fatalError("not built yet")
    }

    /// The track by this artist with this title, by NameKey, preferring
    /// the original album over a compilation or a live one when both are
    /// there (the one with most plays, then the oldest).
    public func match(artist: String, title: String) -> Track? {
        fatalError("not built yet")
    }

    /// The library's key for an artist name from elsewhere (Last.fm), when
    /// the library has that artist.
    public func matchArtist(_ name: String) -> String? {
        fatalError("not built yet")
    }
}
