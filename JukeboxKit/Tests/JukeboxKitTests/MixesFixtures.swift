// Libraries and listeners for the mixes' tests. The made-up library is the
// radio's (RadioSyntheticLibrary: 60 artists in eight genre clusters, a
// listener who loves Rock and Electronic, likes Jazz, plays a little Folk and
// Pop), with albums added the way a real library grows: most a year or two
// ago, a few in the last weeks. Its random dates are per track, which makes
// nearly every album look new.

import Foundation
@testable import JukeboxKit

struct MixesLibrary {
    let base: RadioSyntheticLibrary
    let tracks: [Track]
    let snapshot: LibrarySnapshot
    let history: ListeningHistory
    let now: Date
    /// Album ids added in the last 30 days.
    let newAlbums: Set<ItemID>

    /// - Parameter newAlbumCount: how many albums arrived in the last three weeks.
    init(_ base: RadioSyntheticLibrary = RadioSyntheticLibrary(), newAlbumCount: Int = 4, history: ListeningHistory? = nil) {
        self.base = base
        let now = base.now
        var albumIDs: [ItemID] = []
        var seen = Set<ItemID>()
        for t in base.tracks { if let a = t.albumID, seen.insert(a).inserted { albumIDs.append(a) } }
        // Every album an age of its own, from its id; the last few new.
        var added: [ItemID: Date] = [:]
        var newAlbums = Set<ItemID>()
        for (k, album) in albumIDs.enumerated() {
            let hash = SplitMix64.stableSeed(album)
            if k % max(1, albumIDs.count / max(1, newAlbumCount)) == 0, newAlbums.count < newAlbumCount {
                added[album] = now.addingTimeInterval(-Double(1 + hash % 20) * 86_400)
                newAlbums.insert(album)
            } else {
                added[album] = now.addingTimeInterval(-Double(60 + hash % 800) * 86_400)
            }
        }
        var tracks = base.tracks
        for i in tracks.indices {
            if let album = tracks[i].albumID { tracks[i].dateAdded = added[album] }
        }
        self.tracks = tracks
        snapshot = LibrarySnapshot(tracks: tracks)
        self.history = history ?? base.history
        self.now = now
        self.newAlbums = newAlbums
    }

    func taste(at date: Date? = nil) -> TasteProfile {
        TasteProfile(snapshot: snapshot, history: history, now: date ?? now)
    }

    func generator(at date: Date? = nil, graph: SimilarityGraph? = nil) -> MixGenerator {
        let at = date ?? now
        return MixGenerator(snapshot: snapshot, taste: taste(at: at), history: history,
                            graph: graph ?? .fromLibrary(snapshot), now: at, calendar: MixesCheck.calendar)
    }
}

/// What the tests count about mixes.
enum MixesCheck {
    /// The tests' calendar: Gregorian, UTC, so "the day" is the same on
    /// every machine.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }

    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    static func line(_ text: String) {
        print("MIXES-EVAL " + text)
    }

    /// Pairs of tracks within `window` places of each other that share an
    /// artist (guests count).
    static func separationViolations(_ tracks: [Track], snapshot: LibrarySnapshot, window: Int) -> Int {
        let keys = tracks.map { Set(snapshot.artistKeys(of: $0)) }
        var count = 0
        for i in tracks.indices {
            for j in max(0, i - window)..<i where !keys[i].isDisjoint(with: keys[j]) { count += 1 }
        }
        return count
    }

    static func albumBackToBack(_ tracks: [Track]) -> Int {
        var count = 0
        for i in tracks.indices.dropFirst() {
            if let a = tracks[i].albumID, a == tracks[i - 1].albumID { count += 1 }
        }
        return count
    }

    static func duplicates(_ tracks: [Track]) -> Int {
        tracks.count - Set(tracks.map(\.id)).count
    }

    /// The share of the most common value.
    static func purity<T: Hashable>(_ values: [T]) -> (value: T?, share: Double) {
        guard !values.isEmpty else { return (nil, 0) }
        var count: [T: Int] = [:]
        for v in values { count[v, default: 0] += 1 }
        let best = count.max { $0.value < $1.value }
        return (best?.key, Double(best?.value ?? 0) / Double(values.count))
    }

    static func jaccard(_ a: [Track], _ b: [Track]) -> Double {
        let x = Set(a.map(\.id)), y = Set(b.map(\.id))
        let union = x.union(y).count
        return union == 0 ? 1 : Double(x.intersection(y).count) / Double(union)
    }

    static func describe(_ mix: Mix, snapshot: LibrarySnapshot) -> String {
        let artists = Set(mix.tracks.compactMap { snapshot.primaryArtistKey(of: $0) }).count
        return "\(mix.title) — \(mix.subtitle) · \(mix.tracks.count) tracks, \(artists) artists, \(mix.artwork.count) covers"
    }

    static func fmt(_ x: Double, _ digits: Int = 2) -> String {
        String(format: "%.\(digits)f", x)
    }
}

/// Small hand-made libraries for the mixes' rules.
enum MixesTracks {
    static let now = MixesCheck.date("2026-11-08T10:00:00Z")

    static func ref(_ name: String) -> ArtistRef { ArtistRef(id: "id-" + NameKey.artist(name), name: name) }

    static func track(_ id: String, _ artist: String, album: String? = nil, guests: [String] = [], genres: [String] = ["Rock"],
                      year: Int? = 2000, favorite: Bool = false, plays: Int = 0, lastPlayed: Date? = nil,
                      added: Date? = nil) -> Track {
        let albumID = album ?? "album-\(NameKey.artist(artist))"
        return Track(id: id, name: "Song \(id)", albumID: albumID, albumName: "Album \(albumID)",
                     artists: [ref(artist)] + guests.map(ref), albumArtist: ref(artist), genres: genres, year: year,
                     trackNumber: 1, discNumber: 1, duration: 200, albumImageTag: "tag-\(albumID)",
                     isFavorite: favorite, playCount: plays, lastPlayed: lastPlayed,
                     dateAdded: added ?? now.addingTimeInterval(-400 * 86_400))
    }

    static func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    static func generator(_ tracks: [Track], history: ListeningHistory = ListeningHistory(), now: Date = now) -> MixGenerator {
        let snapshot = LibrarySnapshot(tracks: tracks)
        return MixGenerator(snapshot: snapshot, taste: TasteProfile(snapshot: snapshot, history: history, now: now),
                            history: history, graph: .fromLibrary(snapshot), now: now, calendar: MixesCheck.calendar)
    }
}
