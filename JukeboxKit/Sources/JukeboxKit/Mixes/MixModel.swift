// What every mix reads, worked out once per MixGenerator: the taste by
// track, artist and genre number of the snapshot (as the radio reads it),
// what was played lately, and the day. And the parts every mix is made
// with: drawing tracks at random but the same all day, putting them in an
// order that keeps artists apart, and the collage and the "A, B and more".
//
// "The same for a whole day" (Mixes.swift): the app makes the mixes again
// every few hours, and a mix being listened to must not change because it
// is being listened to. So everything here is as of the start of the day:
// the taste is made from the history before today, "heard lately" and "on
// repeat" count to midnight, and the random numbers come from the date. Only
// a thumbs down acts at once, and an album added today joins New Arrivals.
//
// Nothing depends on a Dictionary's order, and every random number comes
// from the day and the track's id, so the same library on the same day
// gives the same mixes in every process, and adding an album does not
// shuffle every other mix.

import Foundation

final class MixModel: Sendable {
    let snapshot: LibrarySnapshot
    let index: LibrarySnapshot.Index
    let graph: SimilarityGraph
    /// When the mixes are made; New Arrivals counts albums to this moment.
    let now: Date
    /// Midnight before `now`, in the generator's calendar: what everything
    /// else is counted to.
    let dayStart: Date
    /// "2026-11-08": with the mix's kind and key, the seed of its random
    /// numbers, so the mixes are the same all day and new the next.
    let day: String

    /// The tracks as they were at midnight: Jellyfin's play count and last
    /// play of a song played today put back as far as this device's
    /// history can tell (MixModel.init). What the mixes decide by; what
    /// they show is `snapshot.tracks`, as the tracks are now.
    let dayTracks: [Track]

    // Taste as of the start of the day, by track number.
    let affinity: [Double]
    let familiarity: [Double]
    /// Hours from the last time heard before today to midnight; infinity
    /// when never (or only today).
    let hoursSince: [Double]
    // By artist and genre number.
    let artistAffinity: [Double]
    let genreAffinity: [Double]
    /// Artist numbers, most liked first, then the biggest; the disliked left out.
    let rankedArtists: [Int]
    let rankedGenres: [Int]

    /// FNV-1a of the track's id: its random number is drawn from this and
    /// the mix's seed, so it does not depend on where the track is.
    let trackHash: [UInt64]
    /// Plays in the 30 days before today, each fading by half in 14: this
    /// device's completions and likes, or Jellyfin's count when it was last
    /// played within the month, whichever says more (the player reports each
    /// completion to Jellyfin, so not both).
    let recentPlays: [Double]
    /// Completions and likes on this device before today.
    let heardCount: [Int]
    /// A thumbs down on this device in the last half year (today's
    /// included: that one acts at once), or a taste turned against it.
    let avoided: [Bool]

    static let recentDays = 30.0
    static let recentHalfLifeDays = 14.0

    init(snapshot: LibrarySnapshot, taste: TasteProfile, history: ListeningHistory, graph: SimilarityGraph,
         now: Date, calendar: Calendar) {
        let index = snapshot.index
        let tracks = snapshot.tracks
        let n = tracks.count
        self.snapshot = snapshot
        self.index = index
        self.graph = graph
        self.now = now
        let dayStart = calendar.startOfDay(for: now)
        self.dayStart = dayStart
        day = Self.dayKey(now, calendar: calendar)

        // Jellyfin as it was at midnight. A song played today has today as
        // its last play and one more in its count, and that alone would move
        // it in the mixes (a song heard twice now counts as known), so the
        // plays this device made today are taken off and the last play
        // before today taken from the history. A play today on another
        // device cannot be told and stays.
        let before = history.events.filter { $0.date < dayStart }
        var lastBefore = [Double](repeating: -.infinity, count: n)
        var playsToday = [Int](repeating: 0, count: n)
        for event in history.events {
            guard let t = index.trackByID[event.trackID] else { continue }
            if event.date < dayStart {
                lastBefore[t] = max(lastBefore[t], event.date.timeIntervalSinceReferenceDate)
            } else if event.outcome == .completed || event.outcome == .liked {
                playsToday[t] += 1
            }
        }
        var dayTracks = tracks
        var changed = false
        for t in 0..<n {
            guard let last = tracks[t].lastPlayed, last >= dayStart else { continue }
            dayTracks[t].playCount = max(0, tracks[t].playCount - playsToday[t])
            dayTracks[t].lastPlayed = lastBefore[t].isFinite ? Date(timeIntervalSinceReferenceDate: lastBefore[t]) : nil
            changed = true
        }
        self.dayTracks = dayTracks

        // The taste as of midnight: the one given when it is that, else made
        // from the history before today and the tracks as they were (13 ms
        // on 20 000 tracks and 20 000 events, release).
        let dayTaste: TasteProfile
        if taste.now <= dayStart, !changed, taste.data.index === index {
            dayTaste = taste
        } else {
            let daySnapshot = changed ? LibrarySnapshot(tracks: dayTracks, sharingIndexOf: snapshot) : snapshot
            dayTaste = TasteProfile(snapshot: daySnapshot, history: ListeningHistory(events: before), now: dayStart)
        }
        let data = dayTaste.data
        affinity = data.trackAffinity
        familiarity = data.familiarity
        artistAffinity = data.artistAffinity
        genreAffinity = data.genreAffinity
        rankedArtists = data.rankedArtists.compactMap { index.artistByKey[$0] }
        rankedGenres = data.rankedGenres.compactMap { index.genreByKey[$0] }
        trackHash = tracks.map { SplitMix64.stableSeed($0.id) }

        let reference = dayStart.timeIntervalSinceReferenceDate
        func daysAgo(_ date: Date) -> Double {
            let d = (reference - date.timeIntervalSinceReferenceDate) / 86_400
            return d.isFinite ? d : .infinity
        }
        var lastHeard = [Double](repeating: -.infinity, count: n)
        var historyPlays = [Double](repeating: 0, count: n)
        var heard = [Int](repeating: 0, count: n)
        var avoided = [Bool](repeating: false, count: n)
        for event in history.events {
            guard let t = index.trackByID[event.trackID] else { continue }
            let at = event.date.timeIntervalSinceReferenceDate
            if event.outcome == .disliked, daysAgo(event.date) <= 183 { avoided[t] = true }
            // Today's plays count from tomorrow.
            guard at < reference, at.isFinite else { continue }
            lastHeard[t] = max(lastHeard[t], at)
            let age = daysAgo(event.date)
            let fade = age <= Self.recentDays ? exp2(-age / Self.recentHalfLifeDays) : 0
            switch event.outcome {
            case .completed, .liked:
                heard[t] += 1
                historyPlays[t] += fade
            case .partial:
                historyPlays[t] += 0.3 * fade
            case .skipped, .disliked:
                break
            }
        }
        var recent = [Double](repeating: 0, count: n)
        var hours = [Double](repeating: .infinity, count: n)
        for t in 0..<n {
            var jellyfin = 0.0
            // Jellyfin's last play as it was at midnight.
            if let last = dayTracks[t].lastPlayed?.timeIntervalSinceReferenceDate, last.isFinite, last < reference {
                lastHeard[t] = max(lastHeard[t], last)
                let age = (reference - last) / 86_400
                if dayTracks[t].playCount > 0, age <= Self.recentDays {
                    // A lifetime count, last heard this month: log₂(1 + plays)
                    // is one for one play, three for seven.
                    jellyfin = log2(1 + Double(dayTracks[t].playCount)) * exp2(-age / Self.recentHalfLifeDays)
                }
            }
            recent[t] = max(historyPlays[t], jellyfin)
            if lastHeard[t] > -.infinity { hours[t] = (reference - lastHeard[t]) / 3600 }
            if affinity[t] < -0.3 { avoided[t] = true }
        }
        hoursSince = hours
        recentPlays = recent
        heardCount = heard
        self.avoided = avoided
    }

    var trackCount: Int { snapshot.tracks.count }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let text = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
    }

    // MARK: - Small facts

    func primaryArtist(_ t: Int) -> Int? { index.trackArtists[t].first }

    func artistName(_ a: Int) -> String { index.artistRefs[a].name }

    /// A song heard just now is less welcome in today's mix than one heard
    /// last week: 0.4 just heard, 0.7 a day ago, 0.93 three days ago.
    func freshness(_ t: Int) -> Double {
        let hours = hoursSince[t]
        guard hours.isFinite else { return 1 }
        return 1 - 0.6 * exp2(-max(0, hours) / 24)
    }

    /// Whether a track may be in a mix at all: not thumbed down, not
    /// disliked by taste, not by an artist the listener has turned against.
    func welcome(_ t: Int) -> Bool {
        guard !avoided[t], affinity[t] > -0.2 else { return false }
        if let a = primaryArtist(t), artistAffinity[a] < -0.3 { return false }
        return true
    }

    /// The mean genre affinity of a track's genres.
    func genreTaste(_ t: Int) -> Double {
        let genres = index.trackGenres[t]
        guard !genres.isEmpty else { return 0 }
        return genres.reduce(0) { $0 + genreAffinity[$1] } / Double(genres.count)
    }

    // MARK: - The day's random numbers

    /// A mix's seed: its kind, its key and the day.
    func seed(_ parts: String...) -> UInt64 {
        SplitMix64.stableSeed((parts + [day]).joined(separator: "-"))
    }

    /// The track's random number for a mix, in (0, 1].
    func unit(_ seed: UInt64, _ t: Int) -> Double {
        var generator = SplitMix64(seed: seed ^ trackHash[t])
        return 1 - generator.nextUnit()
    }

    // MARK: - Drawing

    /// `count` tracks drawn at random in proportion to their weight, without
    /// putting any back (Efraimidis and Spirakis, 2006: each track's key is
    /// u^(1/w) and the largest keys win), best first. At most `artistCap`
    /// filed under one artist and `albumCap` from one album, counting what
    /// `counts` already holds; when that leaves the mix short, the caps give
    /// way rather than the mix. A song once, whatever gives way: its album's
    /// and its best-of's recordings are one (LibrarySnapshot.Index.trackSong;
    /// with best-ofs of the made-up listener's loved songs, 7 songs were
    /// twice in a mix).
    func draw(_ weighted: [(track: Int, weight: Double)], count: Int, seed: UInt64,
              artistCap: Int? = nil, albumCap: Int? = nil, counts: inout MixCounts) -> [Int] {
        guard count > 0 else { return [] }
        var keyed: [(track: Int, key: Double)] = []
        keyed.reserveCapacity(weighted.count)
        for (t, w) in weighted where w > 0 && w.isFinite {
            keyed.append((t, log(unit(seed, t)) / w))
        }
        keyed.sort { $0.key != $1.key ? $0.key > $1.key : $0.track < $1.track }

        var picked: [Int] = []
        var taken = Set<Int>()
        for (t, _) in keyed {
            if picked.count == count { break }
            if counts.songs.contains(index.trackSong[t]) { continue }
            if let artistCap, let a = primaryArtist(t), counts.artists[a, default: 0] >= artistCap { continue }
            let album = index.trackAlbum[t]
            if let albumCap, album >= 0, counts.albums[album, default: 0] >= albumCap { continue }
            picked.append(t)
            taken.insert(t)
            counts.add(t, self)
        }
        if picked.count < count, artistCap != nil || albumCap != nil {
            for (t, _) in keyed where !taken.contains(t) && !counts.songs.contains(index.trackSong[t]) {
                if picked.count == count { break }
                picked.append(t)
                counts.add(t, self)
            }
        }
        return picked
    }

    // MARK: - Order

    /// The mix in order: the lanes interleaved by their share, so a mix of
    /// 60% familiar is familiar three songs in five all the way through
    /// rather than first all of that; no artist (a guest counts) twice
    /// within `separation` places and no album twice in a row, loosened only
    /// where nothing else fits. Within a lane, of the tracks that fit, the
    /// one whose artists have the most tracks left goes first (the greedy
    /// rule that spaces a list best: no artist is left over to clump at the
    /// end), a song with a guest counting both, as it is the harder to place;
    /// the first track is the first lane's best.
    func order(_ lanes: [[Int]], separation: Int) -> [Int] {
        let total = lanes.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        var remaining = lanes
        var taken = [Int](repeating: 0, count: lanes.count)
        var left: [Int: Int] = [:]
        for lane in lanes { for t in lane { for a in index.trackArtists[t] { left[a, default: 0] += 1 } } }
        var placed: [Int] = []
        placed.reserveCapacity(total)

        func fits(_ t: Int, window: Int, album: Bool) -> Bool {
            if album, let last = placed.last {
                let a = index.trackAlbum[t]
                if a >= 0, a == index.trackAlbum[last] { return false }
            }
            guard window > 0 else { return true }
            let artists = index.trackArtists[t]
            for previous in placed.suffix(window) {
                for a in index.trackArtists[previous] where artists.contains(a) { return false }
            }
            return true
        }

        // Strictest first: the full separation and the album rule, then
        // less separation, then the album rule alone, then anything.
        var levels: [(window: Int, album: Bool)] = stride(from: separation, through: 1, by: -1).map { ($0, true) }
        levels.append((0, true))
        levels.append((0, false))

        while placed.count < total {
            let position = Double(placed.count + 1)
            // The lane furthest behind its share is asked first.
            let laneOrder = lanes.indices.filter { !remaining[$0].isEmpty }.sorted { x, y in
                let lagX = Double(lanes[x].count) * position / Double(total) - Double(taken[x])
                let lagY = Double(lanes[y].count) * position / Double(total) - Double(taken[y])
                return lagX != lagY ? lagX > lagY : x < y
            }
            var chosen: (lane: Int, at: Int)?
            search: for level in levels {
                for lane in laneOrder {
                    var best: (at: Int, left: Int)?
                    for (k, t) in remaining[lane].enumerated() where fits(t, window: level.window, album: level.album) {
                        if placed.isEmpty {
                            best = (k, 0)
                            break
                        }
                        let count = index.trackArtists[t].reduce(0) { $0 + (left[$1] ?? 0) }
                        if count > (best?.left ?? -1) { best = (k, count) }
                    }
                    if let best {
                        chosen = (lane, best.at)
                        break search
                    }
                }
            }
            guard let chosen else { break }
            let t = remaining[chosen.lane].remove(at: chosen.at)
            placed.append(t)
            taken[chosen.lane] += 1
            for a in index.trackArtists[t] { left[a, default: 1] -= 1 }
        }
        return repaired(placed, separation: separation)
    }

    /// The greedy order can corner itself at the end (the last few songs all
    /// by two artists); a song that breaks a rule there is swapped with one
    /// elsewhere when that breaks fewer, the first song staying first.
    func repaired(_ list: [Int], separation: Int) -> [Int] {
        var list = list
        guard list.count > 2 else { return list }
        func clashes(_ i: Int) -> Int {
            var count = 0
            let artists = index.trackArtists[list[i]]
            for j in max(0, i - separation)...min(list.count - 1, i + separation) where j != i {
                if index.trackArtists[list[j]].contains(where: { artists.contains($0) }) { count += 1 }
            }
            let album = index.trackAlbum[list[i]]
            if album >= 0 {
                if i > 0, index.trackAlbum[list[i - 1]] == album { count += 1 }
                if i + 1 < list.count, index.trackAlbum[list[i + 1]] == album { count += 1 }
            }
            return count
        }
        for _ in 0..<3 {
            var improved = false
            for i in 1..<list.count where clashes(i) > 0 {
                for j in 1..<list.count where j != i {
                    let before = clashes(i) + clashes(j)
                    list.swapAt(i, j)
                    if clashes(i) + clashes(j) < before {
                        improved = true
                        break
                    }
                    list.swapAt(i, j)
                }
            }
            if !improved { break }
        }
        return list
    }

    // MARK: - How a mix looks

    /// Up to four covers of different albums in the mix, the first tracks
    /// (the lanes' best) first; different artists before a second album of
    /// one artist.
    func covers(_ tracks: [Int]) -> [Artwork] {
        var out: [Artwork] = []
        var albums = Set<Int>()
        var artists = Set<Int>()
        var seen = Set<Artwork>()
        for pass in 0..<2 {
            for t in tracks {
                if out.count == 4 { return out }
                guard let art = snapshot.tracks[t].artwork, !seen.contains(art) else { continue }
                let album = index.trackAlbum[t]
                if album >= 0, albums.contains(album) { continue }
                let artist = primaryArtist(t) ?? -1
                if pass == 0, artists.contains(artist) { continue }
                out.append(art)
                seen.insert(art)
                if album >= 0 { albums.insert(album) }
                artists.insert(artist)
            }
        }
        return out
    }

    /// "Radiohead, Portishead and more": the mix's leading artists, those in
    /// `lead` first (in that order), then those with the most tracks in it
    /// (liked ones counting more), then the one that comes first in it.
    func artistLine(_ tracks: [Int], lead: [Int] = []) -> String {
        var count: [Int: Int] = [:]
        var first: [Int: Int] = [:]
        for (position, t) in tracks.enumerated() {
            guard let a = primaryArtist(t) else { continue }
            count[a, default: 0] += 1
            if first[a] == nil { first[a] = position }
        }
        var names: [Int] = lead.filter { count[$0] != nil }
        var listed = Set(names)
        let rest = count.keys.filter { !listed.contains($0) }.sorted { x, y in
            let cx = Double(count[x] ?? 0) * (1 + max(0, artistAffinity[x]))
            let cy = Double(count[y] ?? 0) * (1 + max(0, artistAffinity[y]))
            return cx != cy ? cx > cy : (first[x] ?? 0) < (first[y] ?? 0)
        }
        for a in rest where listed.insert(a).inserted { names.append(a) }
        switch names.count {
        case 0: return ""
        case 1: return artistName(names[0])
        case 2: return "\(artistName(names[0])) and \(artistName(names[1]))"
        default: return "\(artistName(names[0])), \(artistName(names[1])) and more"
        }
    }
}

/// How many tracks of each artist (the one a track is filed under) and
/// album a mix already has, for the caps.
struct MixCounts {
    var artists: [Int: Int] = [:]
    var albums: [Int: Int] = [:]
    var songs: Set<Int> = []

    mutating func add(_ t: Int, _ model: MixModel) {
        songs.insert(model.index.trackSong[t])
        if let a = model.primaryArtist(t) { artists[a, default: 0] += 1 }
        let album = model.index.trackAlbum[t]
        if album >= 0 { albums[album, default: 0] += 1 }
    }
}

extension LibrarySnapshot {
    /// The same library with other numbers on some tracks (play counts,
    /// last plays): the index is of who, what, which album and when made,
    /// which those do not change, so it is shared rather than made again
    /// (90 ms on 20 000 tracks). Only for tracks in the same order with the
    /// same ids, artists, genres, albums and years.
    init(tracks: [Track], sharingIndexOf other: LibrarySnapshot) {
        self.tracks = tracks
        self.index = other.index
    }
}
