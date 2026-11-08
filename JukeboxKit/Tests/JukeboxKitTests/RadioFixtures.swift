// A made-up library and listener for measuring the radio (docs/RADIO.md):
// artists in eight genre clusters, each with sub-genres, guests between
// neighbours, eras per cluster, and a listener who loves two clusters,
// likes a third, and hardly plays the rest. The same every run (its own
// SplitMix64 seed), and as big as asked: 60 artists for the evaluation,
// 20 000 tracks for the timings.

import Foundation
import JukeboxKit

struct RadioSyntheticLibrary {
    struct ArtistInfo {
        var name: String
        var key: String
        var id: String
        var cluster: Int
        var subgenre: String
        var genres: [String]
        var firstYear: Int
        /// How much the made-up listener likes them: 0 never plays … 3 loves.
        var liking: Int
    }

    static let clusters: [(genre: String, subgenres: [String], year: Int)] = [
        ("Rock", ["Alternative", "Shoegaze", "Hard Rock"], 1990),
        ("Electronic", ["House", "Ambient", "Techno"], 2005),
        ("Jazz", ["Bebop", "Vocal Jazz", "Fusion"], 1962),
        ("Hip-Hop", ["Nederhop", "Boom Bap", "Trap"], 2002),
        ("Classical", ["Piano", "Baroque", "Opera"], 1985),
        ("Folk", ["Americana", "Acoustic", "Singer-Songwriter"], 1975),
        ("Pop", ["Dance", "Synthpop", "Indie Pop"], 2010),
        ("Metal", ["Doom", "Thrash", "Black Metal"], 1988),
    ]

    /// The made-up listener: loves Rock and Electronic, likes Jazz, plays a
    /// little Folk and Pop, hardly Hip-Hop, Classical or Metal.
    static let clusterLiking = [3, 3, 2, 0, 0, 1, 1, 0]

    let tracks: [Track]
    let artists: [ArtistInfo]
    let history: ListeningHistory
    let now: Date
    let clusterOfArtist: [String: Int]
    let subgenreOfArtist: [String: String]

    /// - Parameter styleTags: when more than 0, every artist also gets one
    ///   of this many narrow tags ("Style 17"), as real libraries have
    ///   hundreds of genres.
    init(artistCount: Int = 60, albumsPerArtist: ClosedRange<Int> = 2...4, tracksPerAlbum: ClosedRange<Int> = 8...12,
         targetTracks: Int? = nil, styleTags: Int = 0, seed: UInt64 = 7) {
        var rng = SplitMix64(seed: seed)
        func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(rng.next() % UInt64(range.count))
        }
        func chance(_ p: Double) -> Bool { rng.nextUnit() < p }

        let now = Date(timeIntervalSinceReferenceDate: 815_000_000) // 30 October 2026
        let first = ["Velvet", "Paper", "Glass", "Iron", "Low", "Neon", "Blue", "Silver", "Northern", "Quiet",
                     "Wild", "Electric", "Ocean", "Golden", "Hollow", "Static", "Morning", "Ghost", "Red", "Satellite"]
        let second = ["Harbour", "Lanterns", "Orbit", "Meadow", "Poets", "Strings", "Hearts", "Engine", "Room",
                      "Pines", "Signal", "Tide", "Fields", "Machine", "Letters", "Parade", "Mirror", "Club", "Lights", "Road"]

        var artists: [ArtistInfo] = []
        for i in 0..<artistCount {
            let cluster = i % Self.clusters.count
            let c = Self.clusters[cluster]
            let sub = c.subgenres[(i / Self.clusters.count) % c.subgenres.count]
            var genres = [c.genre, sub]
            // Some have a second sub-genre, a few a genre from the next
            // cluster: libraries are not tidy.
            if i % 5 == 0 { genres.append(c.subgenres[(i / Self.clusters.count + 1) % c.subgenres.count]) }
            if i % 11 == 0 { genres.append(Self.clusters[(cluster + 1) % Self.clusters.count].genre) }
            if styleTags > 0 { genres.append("Style \(cluster * styleTags / Self.clusters.count + int(0...(styleTags / Self.clusters.count - 1)))") }
            let name = "\(first[i % first.count]) \(second[(i / first.count + i * 7) % second.count]) \(i)"
            var liking = Self.clusterLiking[cluster]
            // Not every artist of a loved cluster is loved.
            if liking > 0, i % 4 == 3 { liking -= 1 }
            artists.append(ArtistInfo(name: name, key: NameKey.artist(name), id: "ar\(i)", cluster: cluster,
                                      subgenre: sub, genres: genres, firstYear: c.year + int(0...20) - 10,
                                      liking: liking))
        }

        var tracks: [Track] = []
        var number = 0
        outer: for (i, artist) in artists.enumerated() {
            let albums = int(albumsPerArtist)
            for album in 0..<albums {
                let year = artist.firstYear + album * int(2...5)
                let albumID = "al\(i)-\(album)"
                let count = int(tracksPerAlbum)
                for t in 1...count {
                    var performers = [ArtistRef(id: artist.id, name: artist.name)]
                    if chance(0.15) {
                        // A guest from the same cluster, sometimes the next one.
                        let step = Self.clusters.count * (chance(0.5) ? 1 : -1)
                        var g = chance(0.8) ? i + step : i + 1
                        g = ((g % artists.count) + artists.count) % artists.count
                        if g != i { performers.append(ArtistRef(id: artists[g].id, name: artists[g].name)) }
                    }
                    var heard = false
                    var plays = 0
                    var favorite = false
                    var lastPlayed: Date?
                    switch artist.liking {
                    case 3: heard = chance(0.8); plays = heard ? int(1...25) : 0; favorite = heard && chance(0.18)
                    case 2: heard = chance(0.55); plays = heard ? int(1...8) : 0; favorite = heard && chance(0.08)
                    case 1: heard = chance(0.25); plays = heard ? int(1...3) : 0
                    default: heard = chance(0.04); plays = heard ? 1 : 0
                    }
                    if heard {
                        let daysAgo = Double(artist.liking >= 2 ? int(1...200) : int(30...700))
                        lastPlayed = now.addingTimeInterval(-daysAgo * 86_400)
                    }
                    tracks.append(Track(
                        id: String(format: "t%05d", number), name: "Song \(number)", albumID: albumID,
                        albumName: "Album \(i)-\(album)", artists: performers,
                        albumArtist: ArtistRef(id: artist.id, name: artist.name), genres: artist.genres,
                        year: year, trackNumber: t, discNumber: 1, duration: Double(int(150...330)),
                        albumImageTag: "tag\(i)-\(album)", isFavorite: favorite, playCount: plays,
                        lastPlayed: lastPlayed, dateAdded: now.addingTimeInterval(-Double(int(1...900)) * 86_400)))
                    number += 1
                    if let targetTracks, number >= targetTracks { break outer }
                }
            }
        }
        if let targetTracks, tracks.count < targetTracks {
            // Fill up with more of the same artists' albums.
            var extra = 0
            while tracks.count < targetTracks {
                let i = extra % artists.count
                let artist = artists[i]
                tracks.append(Track(
                    id: String(format: "t%05d", number), name: "Song \(number)", albumID: "al\(i)-x\(extra / artists.count)",
                    albumName: "Extra \(i)", artists: [ArtistRef(id: artist.id, name: artist.name)],
                    albumArtist: ArtistRef(id: artist.id, name: artist.name), genres: artist.genres,
                    year: artist.firstYear + 12, trackNumber: extra / artists.count + 1, discNumber: 1, duration: 200))
                number += 1
                extra += 1
            }
        }

        // The last two months on this device: mostly the loved clusters heard
        // to the end, some skips elsewhere.
        var events: [PlayEvent] = []
        var likingOf: [String: Int] = [:]
        for a in artists { likingOf[a.id] = a.liking }
        let lovedTracks = tracks.filter { (likingOf[$0.albumArtist?.id ?? ""] ?? 0) >= 2 }
        let otherTracks = tracks.filter { (likingOf[$0.albumArtist?.id ?? ""] ?? 0) < 2 }
        for k in 0..<400 {
            let date = now.addingTimeInterval(-Double(400 - k) * 3.5 * 3600)
            if chance(0.8), !lovedTracks.isEmpty {
                let t = lovedTracks[int(0...(lovedTracks.count - 1))]
                let outcome: PlayOutcome = chance(0.85) ? .completed : (chance(0.5) ? .liked : .skipped)
                events.append(PlayEvent(track: t, date: date, listened: outcome == .skipped ? 10 : t.duration, outcome: outcome))
            } else if !otherTracks.isEmpty {
                let t = otherTracks[int(0...(otherTracks.count - 1))]
                let outcome: PlayOutcome = chance(0.6) ? .skipped : .completed
                events.append(PlayEvent(track: t, date: date, listened: outcome == .skipped ? 12 : t.duration, outcome: outcome))
            }
        }

        self.tracks = tracks
        self.artists = artists
        self.history = ListeningHistory(events: events)
        self.now = now
        var clusterOf: [String: Int] = [:]
        var subOf: [String: String] = [:]
        for a in artists {
            clusterOf[a.key] = a.cluster
            subOf[a.key] = a.subgenre
        }
        clusterOfArtist = clusterOf
        subgenreOfArtist = subOf
    }

    func artist(key: String) -> ArtistInfo? { artists.first { $0.key == key } }
}

/// What the evaluation counts about a list of picks.
enum RadioMetrics {
    /// Pairs of picks closer than `separation` that share an artist (guests
    /// count), using the snapshot's keys.
    static func separationViolations(_ picks: [RadioPick], snapshot: LibrarySnapshot, separation: Int) -> Int {
        var violations = 0
        let keys = picks.map { Set(snapshot.artistKeys(of: $0.track)) }
        for i in picks.indices {
            for j in max(0, i - separation)..<i where !keys[i].isDisjoint(with: keys[j]) {
                violations += 1
            }
        }
        return violations
    }

    static func repeats(_ picks: [RadioPick]) -> Int {
        picks.count - Set(picks.map(\.track.id)).count
    }

    static func albumBackToBack(_ picks: [RadioPick]) -> Int {
        var count = 0
        for i in picks.indices.dropFirst() {
            if let a = picks[i].track.albumID, a == picks[i - 1].track.albumID { count += 1 }
        }
        return count
    }

    static func distinctArtists(_ picks: [RadioPick], snapshot: LibrarySnapshot) -> Int {
        Set(picks.compactMap { snapshot.primaryArtistKey(of: $0.track) }).count
    }
}
