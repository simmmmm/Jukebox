// The library as Jukebox thinks of it: tracks, albums, artists, playlists
// and genres, made from Jellyfin's BaseItemDto (Jellyfin/DTO.swift) once, at
// the edge, so nothing above the client reads Jellyfin's field names.
// Codable so the whole library can be kept on disk (LibraryCache) and opened
// at once on the next launch, before the server has answered.

import Foundation

public typealias ItemID = String

/// An image Jellyfin can draw at any size: the item that has it and the tag
/// that changes when the image does, so a cached copy is never stale.
public struct Artwork: Hashable, Codable, Sendable {
    public let itemID: ItemID
    public let tag: String?

    public init(itemID: ItemID, tag: String?) {
        self.itemID = itemID
        self.tag = tag
    }
}

/// An artist as a track or an album names it: Jellyfin gives the id when it
/// knows the artist as an item, which it nearly always does.
public struct ArtistRef: Hashable, Codable, Sendable {
    public let id: ItemID?
    public let name: String

    public init(id: ItemID?, name: String) {
        self.id = id
        self.name = name
    }

    /// The name as the radio and the matching with Last.fm compare it.
    public var key: String { NameKey.artist(name) }
}

public struct Track: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public var name: String
    public var albumID: ItemID?
    public var albumName: String?
    /// The track's own performers, guests included (Jellyfin's ArtistItems).
    public var artists: [ArtistRef]
    /// The album's artist (the first of AlbumArtists): who a track is filed
    /// under, and the one the radio keeps apart.
    public var albumArtist: ArtistRef?
    public var genres: [String]
    public var year: Int?
    public var trackNumber: Int?
    public var discNumber: Int?
    /// Seconds.
    public var duration: TimeInterval
    public var imageTag: String?
    public var albumImageTag: String?
    public var isFavorite: Bool
    public var playCount: Int
    public var lastPlayed: Date?
    public var dateAdded: Date?
    /// Jellyfin 10.9+'s loudness normalisation, in dB (negative: play softer).
    public var normalizationGain: Double?
    /// Set when the track came from a playlist: what removing or moving it
    /// there needs (Jellyfin's PlaylistItemId).
    public var playlistEntryID: String?

    public init(id: ItemID, name: String, albumID: ItemID? = nil, albumName: String? = nil,
                artists: [ArtistRef] = [], albumArtist: ArtistRef? = nil, genres: [String] = [],
                year: Int? = nil, trackNumber: Int? = nil, discNumber: Int? = nil,
                duration: TimeInterval = 0, imageTag: String? = nil, albumImageTag: String? = nil,
                isFavorite: Bool = false, playCount: Int = 0, lastPlayed: Date? = nil,
                dateAdded: Date? = nil, normalizationGain: Double? = nil, playlistEntryID: String? = nil) {
        self.id = id
        self.name = name
        self.albumID = albumID
        self.albumName = albumName
        self.artists = artists
        self.albumArtist = albumArtist
        self.genres = genres
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.imageTag = imageTag
        self.albumImageTag = albumImageTag
        self.isFavorite = isFavorite
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.dateAdded = dateAdded
        self.normalizationGain = normalizationGain
        self.playlistEntryID = playlistEntryID
    }

    /// The one artist a track is by, for keeping artists apart and for
    /// "Go to Artist": the album artist, else the first performer.
    public var primaryArtist: ArtistRef? { albumArtist ?? artists.first }

    /// "Artist" or "Artist, Guest", as a row's second line.
    public var artistLine: String {
        let names = artists.map(\.name)
        if !names.isEmpty { return names.joined(separator: ", ") }
        return albumArtist?.name ?? ""
    }

    /// The track's own image, else its album's.
    public var artwork: Artwork? {
        if let imageTag { return Artwork(itemID: id, tag: imageTag) }
        if let albumID { return Artwork(itemID: albumID, tag: albumImageTag) }
        return nil
    }

    /// Every artist key on the track (performers and album artist), for the
    /// radio's matching.
    public var artistKeys: Set<String> {
        var keys = Set(artists.map(\.key))
        if let albumArtist { keys.insert(albumArtist.key) }
        return keys
    }
}

public struct Album: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public var name: String
    public var artists: [ArtistRef]
    public var year: Int?
    public var genres: [String]
    public var imageTag: String?
    public var trackCount: Int?
    /// Seconds.
    public var duration: TimeInterval?
    public var isFavorite: Bool
    public var dateAdded: Date?
    public var playCount: Int
    public var lastPlayed: Date?

    public init(id: ItemID, name: String, artists: [ArtistRef] = [], year: Int? = nil,
                genres: [String] = [], imageTag: String? = nil, trackCount: Int? = nil,
                duration: TimeInterval? = nil, isFavorite: Bool = false, dateAdded: Date? = nil,
                playCount: Int = 0, lastPlayed: Date? = nil) {
        self.id = id
        self.name = name
        self.artists = artists
        self.year = year
        self.genres = genres
        self.imageTag = imageTag
        self.trackCount = trackCount
        self.duration = duration
        self.isFavorite = isFavorite
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayed = lastPlayed
    }

    public var artistLine: String { artists.map(\.name).joined(separator: ", ") }
    public var primaryArtist: ArtistRef? { artists.first }
    public var artwork: Artwork? { Artwork(itemID: id, tag: imageTag) }
}

public struct Artist: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public var name: String
    public var imageTag: String?
    public var genres: [String]
    public var isFavorite: Bool
    public var albumCount: Int?
    public var songCount: Int?
    public var overview: String?

    public init(id: ItemID, name: String, imageTag: String? = nil, genres: [String] = [],
                isFavorite: Bool = false, albumCount: Int? = nil, songCount: Int? = nil,
                overview: String? = nil) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
        self.genres = genres
        self.isFavorite = isFavorite
        self.albumCount = albumCount
        self.songCount = songCount
        self.overview = overview
    }

    public var ref: ArtistRef { ArtistRef(id: id, name: name) }
    public var key: String { NameKey.artist(name) }
    /// Nil when Jellyfin has no image of the artist: the view draws its
    /// initials then, as Music does.
    public var artwork: Artwork? { imageTag.map { Artwork(itemID: id, tag: $0) } }
}

public struct Playlist: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public var name: String
    public var imageTag: String?
    public var trackCount: Int?
    /// Seconds.
    public var duration: TimeInterval?
    public var dateAdded: Date?

    public init(id: ItemID, name: String, imageTag: String? = nil, trackCount: Int? = nil,
                duration: TimeInterval? = nil, dateAdded: Date? = nil) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
        self.trackCount = trackCount
        self.duration = duration
        self.dateAdded = dateAdded
    }

    public var artwork: Artwork? { imageTag.map { Artwork(itemID: id, tag: $0) } }
}

public struct Genre: Identifiable, Hashable, Codable, Sendable {
    public let id: ItemID
    public var name: String
    public var imageTag: String?
    public var songCount: Int?
    public var albumCount: Int?

    public init(id: ItemID, name: String, imageTag: String? = nil, songCount: Int? = nil,
                albumCount: Int? = nil) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
        self.songCount = songCount
        self.albumCount = albumCount
    }

    public var key: String { NameKey.genre(name) }
}

/// A page of a longer list, as Jellyfin returns it.
public struct Page<Element: Sendable>: Sendable {
    public var items: [Element]
    public var totalCount: Int
    public var startIndex: Int

    public init(items: [Element], totalCount: Int, startIndex: Int) {
        self.items = items
        self.totalCount = totalCount
        self.startIndex = startIndex
    }
}

/// What one search finds, by kind, in the order Jellyfin ranks them.
public struct SearchResults: Sendable {
    public var artists: [Artist]
    public var albums: [Album]
    public var tracks: [Track]
    public var playlists: [Playlist]

    public init(artists: [Artist] = [], albums: [Album] = [], tracks: [Track] = [], playlists: [Playlist] = []) {
        self.artists = artists
        self.albums = albums
        self.tracks = tracks
        self.playlists = playlists
    }

    public var isEmpty: Bool { artists.isEmpty && albums.isEmpty && tracks.isEmpty && playlists.isEmpty }
}

/// A track's lyrics: timed lines when the file or Jellyfin has them synced,
/// plain lines otherwise.
public struct Lyrics: Sendable, Hashable {
    public struct Line: Sendable, Hashable {
        /// Seconds from the start; nil for unsynced lyrics.
        public var start: TimeInterval?
        public var text: String

        public init(start: TimeInterval?, text: String) {
            self.start = start
            self.text = text
        }
    }

    public var lines: [Line]
    public var isSynced: Bool { lines.contains { $0.start != nil } }

    public init(lines: [Line]) {
        self.lines = lines
    }
}
