// Home's album shelves beyond the mixes, as Feishin's Home and Music's have
// them: what was played most, a handful to explore today, and what the
// listener chose to play lately, with when; and when each station last
// played. Worked out here, from values, and not in
// the views' bodies: each is one pass over the library or the history.
// Measured in a Linux container (Swift 6.2, release, best of 7) for 20 000
// tracks on 2 000 albums and a full history of 20 000 events: most played
// 3.1 ms, explore 0.8 ms, recently played 1.5 ms at worst (every event a
// station's, so all are read and the shelf fills from the server's dates)
// and under 0.1 ms when the history alone fills it. Each runs when its
// shelf is drawn again — a song ended, a heart changed — not while one plays.

import Foundation
import JukeboxKit

enum HomeShelves {
    /// Albums by the sum of their tracks' play counts (Jellyfin's, so every
    /// device's), most first, from `minimumPlays` up: an album heard once
    /// or twice is not yet one the listener comes back to.
    static func mostPlayed(tracks: [Track], album lookup: (ItemID) -> Album?,
                           minimumPlays: Int = 3, limit: Int = 20) -> [Album] {
        guard limit > 0 else { return [] }
        var plays: [ItemID: Int] = [:]
        for track in tracks where track.playCount > 0 {
            guard let albumID = track.albumID else { continue }
            plays[albumID, default: 0] += track.playCount
        }
        var ranked: [(album: Album, plays: Int)] = []
        for (albumID, count) in plays where count >= minimumPlays {
            if let found = lookup(albumID) { ranked.append((found, count)) }
        }
        // Ties (the usual first weeks, a few plays each) go to the one played
        // last, then by name, so the shelf does not reorder on every redraw.
        ranked.sort { a, b in
            if a.plays != b.plays { return a.plays > b.plays }
            let x = a.album.lastPlayed ?? .distantPast, y = b.album.lastPlayed ?? .distantPast
            if x != y { return x > y }
            if a.album.name != b.album.name { return a.album.name < b.album.name }
            return a.album.id < b.album.id
        }
        return ranked.prefix(limit).map(\.album)
    }

    /// `limit` albums in an order drawn for the day: the same all day, a new
    /// one tomorrow. Each album's place comes from its own number (the day's
    /// seed and its id, through SplitMix64) rather than from shuffling the
    /// list, so an album added during the day, or the server listing its
    /// albums in another order, leaves the others where they were.
    static func explore(albums: [Album], day: Int, limit: Int = 20) -> [Album] {
        guard limit > 0, !albums.isEmpty else { return [] }
        var dayNumbers = SplitMix64(seed: UInt64(bitPattern: Int64(day)))
        let daySeed = dayNumbers.next()
        var keyed: [(key: UInt64, album: Album)] = []
        keyed.reserveCapacity(albums.count)
        for album in albums {
            var numbers = SplitMix64(seed: daySeed ^ SplitMix64.stableSeed(album.id))
            keyed.append((numbers.next(), album))
        }
        keyed.sort { $0.key != $1.key ? $0.key < $1.key : $0.album.id < $1.album.id }
        return keyed.prefix(limit).map(\.album)
    }

    /// The day `date` falls on, counted in the listener's calendar: one
    /// number from midnight to midnight where they are.
    static func dayNumber(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// Albums the listener chose to play, newest first, each once: from this
    /// device's history, which knows a station's songs (`stationID`) where
    /// Jellyfin's last-played dates do not — a night of radio would
    /// otherwise fill the shelf with every radio song's album. A skip or a
    /// thumbs down is not a choice to hear the album again.
    ///
    /// When the history has fewer than `limit`, the shelf is filled from
    /// Jellyfin's last-played dates, but only with albums last played before
    /// this history begins: played on another device, or before Jukebox, and
    /// so never by one of this device's stations. With no history at all
    /// (day one) that is every album the server knows was played.
    static func recentlyPlayed(events: [PlayEvent], tracks: [Track], albums: [Album],
                               track trackLookup: (ItemID) -> Track?, album albumLookup: (ItemID) -> Album?,
                               limit: Int = 20) -> [Album] {
        recentlyPlayedDated(events: events, tracks: tracks, albums: albums, track: trackLookup,
                            album: albumLookup, limit: limit).map(\.album)
    }

    /// As `recentlyPlayed`, each album with when it was last played: Home's
    /// Played lately says when ("Yesterday"), as a fact in a slogan's place.
    static func recentlyPlayedDated(events: [PlayEvent], tracks: [Track], albums: [Album],
                                    track trackLookup: (ItemID) -> Track?, album albumLookup: (ItemID) -> Album?,
                                    limit: Int = 20) -> [(album: Album, date: Date)] {
        guard limit > 0 else { return [] }
        var seen = Set<ItemID>()
        var result: [(album: Album, date: Date)] = []
        for event in events.reversed() {
            guard event.stationID == nil, event.outcome != .skipped, event.outcome != .disliked,
                  let albumID = trackLookup(event.trackID)?.albumID, !seen.contains(albumID),
                  let found = albumLookup(albumID) else { continue }
            seen.insert(albumID)
            result.append((found, event.date))
            if result.count >= limit { return result }
        }
        for dated in playedBeforeDated(events.first?.date, tracks: tracks, albums: albums, album: albumLookup)
        where seen.insert(dated.album.id).inserted {
            result.append(dated)
            if result.count >= limit { break }
        }
        return result
    }

    /// Albums by the last time Jellyfin says one of their tracks was played,
    /// newest first, those last played before `cutoff` (all when it is nil).
    /// As LibraryStore.recentlyPlayedAlbums, with the dates kept to compare.
    static func playedBefore(_ cutoff: Date?, tracks: [Track], albums: [Album],
                             album lookup: (ItemID) -> Album?) -> [Album] {
        playedBeforeDated(cutoff, tracks: tracks, albums: albums, album: lookup).map(\.album)
    }

    static func playedBeforeDated(_ cutoff: Date?, tracks: [Track], albums: [Album],
                                  album lookup: (ItemID) -> Album?) -> [(album: Album, date: Date)] {
        var latest: [ItemID: Date] = [:]
        for album in albums {
            if let date = album.lastPlayed { latest[album.id] = date }
        }
        for track in tracks {
            guard let date = track.lastPlayed, let albumID = track.albumID else { continue }
            if let known = latest[albumID], known >= date { continue }
            latest[albumID] = date
        }
        var dated = Array(latest)
        if let cutoff {
            dated.removeAll { $0.value >= cutoff }
        }
        dated.sort { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return dated.compactMap { entry in lookup(entry.key).map { (album: $0, date: entry.value) } }
    }

    /// When each station last played on this device, by the station's id
    /// (PlayEvent.stationID, Station.id): the newest event of each, in one
    /// pass from the newest back. For "Played Thursday" on Radio's list and
    /// Your Station's "Last played" on Home.
    static func stationDates(events: [PlayEvent]) -> [String: Date] {
        var dates: [String: Date] = [:]
        for event in events.reversed() {
            guard let id = event.stationID, dates[id] == nil else { continue }
            dates[id] = event.date
        }
        return dates
    }
}
