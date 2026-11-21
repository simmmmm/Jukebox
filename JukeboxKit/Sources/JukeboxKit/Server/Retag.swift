// Every server id inside a model, mapped at once: tagged with its account
// when it comes from a member of MergedServer, stripped again before it
// goes back (docs/MULTI-SERVER.md, "Step 1"). One walk for both ways, so
// tagging and stripping cannot disagree about which fields are ids.
//
// Mapped: the item's id, a song's album and artists, its credits, an
// album's artists and `mergedIDs`, a cover's item. Not mapped: what goes
// back to the same server with the item and is never routed by itself
// (`playlistEntryID`, image tags, Plex's `fileKey`), and names.

import Foundation

extension ArtistRef {
    public func retagged(_ map: (ItemID) -> ItemID) -> ArtistRef {
        ArtistRef(id: id.map(map), name: name)
    }
}

extension Artwork {
    public func retagged(_ map: (ItemID) -> ItemID) -> Artwork {
        Artwork(itemID: map(itemID), tag: tag)
    }
}

extension Credit {
    public func retagged(_ map: (ItemID) -> ItemID) -> Credit {
        Credit(role: role, artist: artist.retagged(map), instrument: instrument)
    }
}

extension Track {
    public func retagged(_ map: (ItemID) -> ItemID) -> Track {
        var track = Track(
            id: map(id), name: name, albumID: albumID.map(map), albumName: albumName,
            artists: artists.map { $0.retagged(map) }, albumArtist: albumArtist?.retagged(map),
            genres: genres, year: year, trackNumber: trackNumber, discNumber: discNumber,
            duration: duration, imageTag: imageTag, albumImageTag: albumImageTag,
            isFavorite: isFavorite, playCount: playCount, lastPlayed: lastPlayed,
            dateAdded: dateAdded, normalizationGain: normalizationGain, playlistEntryID: playlistEntryID,
            container: container, credits: credits?.map { $0.retagged(map) }, work: work,
            movement: movement, grouping: grouping, discTitle: discTitle, rating: rating,
            albumNormalizationGain: albumNormalizationGain, moods: moods, bpm: bpm)
        // Not in the initializer: copied by hand, or a retagged Plex song
        // would lose its file.
        track.fileKey = fileKey
        return track
    }
}

extension Album {
    public func retagged(_ map: (ItemID) -> ItemID) -> Album {
        var album = Album(
            id: map(id), name: name, artists: artists.map { $0.retagged(map) }, year: year,
            genres: genres, imageTag: imageTag, trackCount: trackCount, duration: duration,
            isFavorite: isFavorite, dateAdded: dateAdded, playCount: playCount,
            lastPlayed: lastPlayed, rating: rating, normalizationGain: normalizationGain)
        album.mergedIDs = mergedIDs?.map(map)
        return album
    }
}

extension Artist {
    public func retagged(_ map: (ItemID) -> ItemID) -> Artist {
        Artist(id: map(id), name: name, imageTag: imageTag, genres: genres, isFavorite: isFavorite,
               albumCount: albumCount, songCount: songCount, overview: overview)
    }
}

extension Playlist {
    public func retagged(_ map: (ItemID) -> ItemID) -> Playlist {
        Playlist(id: map(id), name: name, imageTag: imageTag, trackCount: trackCount,
                 duration: duration, dateAdded: dateAdded, isReadOnly: isReadOnly)
    }
}

extension Genre {
    public func retagged(_ map: (ItemID) -> ItemID) -> Genre {
        Genre(id: map(id), name: name, imageTag: imageTag, songCount: songCount, albumCount: albumCount)
    }
}

extension SearchResults {
    public func retagged(_ map: (ItemID) -> ItemID) -> SearchResults {
        SearchResults(artists: artists.map { $0.retagged(map) }, albums: albums.map { $0.retagged(map) },
                      tracks: tracks.map { $0.retagged(map) }, playlists: playlists.map { $0.retagged(map) })
    }
}

extension PlaybackReport {
    public func retagged(_ map: (ItemID) -> ItemID) -> PlaybackReport {
        var report = self
        report.trackID = map(trackID)
        return report
    }
}

extension StationSeed {
    /// A collection's own id is left as it is: it is a playlist's id or a
    /// mix's ("<kind>-<key>-<day>"), the two cannot be told apart, and a
    /// mix's is none of a server's. Nothing is routed by it; its songs carry
    /// their accounts.
    public func retagged(_ map: (ItemID) -> ItemID) -> StationSeed {
        switch self {
        case let .track(id): .track(map(id))
        case let .artist(key, name, id): .artist(key: key, name: name, id: id.map(map))
        case let .album(id): .album(map(id))
        case let .collection(id, name, trackIDs): .collection(id: id, name: name, trackIDs: trackIDs.map(map))
        case .genre, .decade, .personal, .discovery, .favorites: self
        }
    }
}

extension Station {
    /// The station's id follows its seed when it was made from it
    /// ("track-<id>"), so a station kept and one made again stay one.
    public func retagged(_ map: (ItemID) -> ItemID) -> Station {
        let newSeed = seed.retagged(map)
        return Station(id: id == Self.id(for: seed) ? Self.id(for: newSeed) : id, seed: newSeed,
                       title: title, subtitle: subtitle, artwork: artwork.map { $0.retagged(map) })
    }
}

extension PlayState {
    public func retagged(_ map: (ItemID) -> ItemID) -> PlayState {
        var state = self
        state.trackIDs = trackIDs.map(map)
        state.station = station?.retagged(map)
        return state
    }
}
