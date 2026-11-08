// How TasteProfile is worked out (docs/RADIO.md, "Taste"). Every number
// here is bounded: affinities go through tanh, familiarity through
// 1 − e^−x, and every input that could be odd (a negative play count, a date
// in the future) is clamped first, so nothing downstream sees NaN.

import Foundation

/// The evidence behind a TasteProfile, aligned with the snapshot it was
/// made from (by track, artist and genre number), so the radio reads arrays.
final class TasteData: Sendable {
    let now: Date
    /// The snapshot the arrays are aligned with.
    let index: LibrarySnapshot.Index

    /// By track number: −1 … 1.
    let trackAffinity: [Double]
    /// By track number: 0 … 1.
    let familiarity: [Double]
    /// By track number: hours since last heard (Jellyfin's or this device's),
    /// `.infinity` when never.
    let hoursSinceHeard: [Double]
    /// By artist number: −1 … 1.
    let artistAffinity: [Double]
    /// By genre number: −1 … 1.
    let genreAffinity: [Double]
    /// By track number: the last thumbs on this device was down, within
    /// half a year (as the mixes count it), and no thumbs up since. The
    /// radio leaves these out: a thumbs down yesterday is still one today.
    /// Measured: four songs thumbed down the day before came back 7 times
    /// in 600 picks of their artist's station when they were only
    /// evidence (affinity −0.87, a score × 0.44).
    let thumbsDown: [Bool]

    let rankedArtists: [String]
    let rankedGenres: [String]
    let rankedTracks: [ItemID]

    // What each outcome says, and how fast it fades (docs/RADIO.md).
    static let halfLifeDays = 21.0
    static let playCountHalfLifeDays = 90.0
    /// How long a thumbs down keeps a song off the radio: the mixes' half year.
    static let thumbsDownDays = 183.0

    static func value(of outcome: PlayOutcome) -> Double {
        switch outcome {
        case .completed: 1
        case .partial: 0.3
        case .skipped: -0.8
        case .liked: 3
        case .disliked: -4
        }
    }

    init(snapshot: LibrarySnapshot, history: ListeningHistory, now: Date) {
        let index = snapshot.index
        let tracks = snapshot.tracks
        let n = tracks.count
        let reference = now.timeIntervalSinceReferenceDate
        func days(since date: Date) -> Double {
            let d = (reference - date.timeIntervalSinceReferenceDate) / 86_400
            return d.isFinite ? max(0, d) : 0
        }

        var evidence = [Double](repeating: 0, count: n)
        var plays = [Double](repeating: 0, count: n)
        var heardEvents = [Double](repeating: 0, count: n)
        var lightEvents = [Double](repeating: 0, count: n)
        var lastHeard = [Double](repeating: -.infinity, count: n)

        // Jellyfin's: favourites and play counts. A play count is a lifetime
        // total, so it fades slowly with the last play (a quarter-year
        // half-life, never below a third): a song played forty times two
        // years ago is still liked, just not "lately".
        for i in 0..<n {
            let track = tracks[i]
            if track.isFavorite { evidence[i] += 2 }
            let count = Double(max(0, track.playCount))
            plays[i] = count
            if count > 0 {
                var recency = 0.6
                if let last = track.lastPlayed {
                    recency = 0.35 + 0.65 * exp2(-days(since: last) / Self.playCountHalfLifeDays)
                }
                evidence[i] += 0.8 * log2(1 + count) * recency
            }
            if let last = track.lastPlayed {
                lastHeard[i] = max(lastHeard[i], last.timeIntervalSinceReferenceDate)
            }
        }

        // This device's history: what Jellyfin does not keep. Recent events
        // weigh more (a three-week half-life). Events of tracks no longer in
        // the library still say something about their artists and genres.
        var strayArtist = [Double](repeating: 0, count: index.artistCount)
        var strayGenre = [Double](repeating: 0, count: index.genreCount)
        var thumbsDown = [Bool](repeating: false, count: n)
        for event in history.events {
            let decay = exp2(-days(since: event.date) / Self.halfLifeDays)
            let v = Self.value(of: event.outcome) * decay
            if let i = index.trackByID[event.trackID] {
                evidence[i] += v
                // Oldest first: the last thumbs given is the one that holds.
                if event.outcome == .disliked {
                    thumbsDown[i] = days(since: event.date) <= Self.thumbsDownDays
                } else if event.outcome == .liked {
                    thumbsDown[i] = false
                }
                switch event.outcome {
                case .completed: heardEvents[i] += 1
                case .partial: lightEvents[i] += 0.5
                case .liked: lightEvents[i] += 0.5
                case .skipped: lightEvents[i] += 0.25
                case .disliked: lightEvents[i] += 0.25
                }
                let at = event.date.timeIntervalSinceReferenceDate
                if at.isFinite { lastHeard[i] = max(lastHeard[i], at) }
            } else {
                for key in event.artistKeys {
                    if let a = index.artistByKey[key] { strayArtist[a] += 0.5 * v }
                }
                for key in event.genreKeys {
                    if let g = index.genreByKey[key] { strayGenre[g] += 0.5 * v }
                }
            }
        }

        var trackAffinity = [Double](repeating: 0, count: n)
        var familiarity = [Double](repeating: 0, count: n)
        var hours = [Double](repeating: .infinity, count: n)
        for i in 0..<n {
            trackAffinity[i] = Self.bounded(tanh(evidence[i] / 3))
            // A completion this device saw is usually in Jellyfin's play count
            // too (the player reports it), so the larger of the two, not both.
            let heard = max(plays[i], heardEvents[i]) + lightEvents[i]
            var f = 1 - exp(-heard / 3)
            if tracks[i].isFavorite { f = max(f, 0.6) }
            familiarity[i] = Self.bounded(f, 0, 1)
            if lastHeard[i] > -.infinity {
                hours[i] = max(0, (reference - lastHeard[i]) / 3600)
            }
        }

        // Artists and genres: their tracks' evidence added up, the track's own
        // artist fully and a guest by half; dislikes count half (one bad song
        // is not a bad artist). Scaled by the 90th percentile of what the
        // listener has, so the artists they like most are near 1 whether they
        // have played a hundred songs or a hundred thousand.
        var artistEvidence = strayArtist
        var genreEvidence = strayGenre
        for i in 0..<n {
            let e = evidence[i]
            guard e != 0 else { continue }
            let signed = e > 0 ? e : 0.5 * e
            for (k, a) in index.trackArtists[i].enumerated() {
                artistEvidence[a] += k == 0 ? signed : 0.5 * signed
            }
            for g in index.trackGenres[i] { genreEvidence[g] += signed }
        }
        let artistScale = max(3, Self.percentile(artistEvidence.filter { $0 > 0 }, 0.9))
        let genreScale = max(3, Self.percentile(genreEvidence.filter { $0 > 0 }, 0.75))
        let artistAffinity = artistEvidence.map { Self.bounded(tanh($0 / artistScale)) }
        let genreAffinity = genreEvidence.map { Self.bounded(tanh($0 / genreScale)) }

        // Rankings, with ties broken by size and then by key, so they are the
        // same in every process. Disliked artists and genres are left out;
        // those never heard follow the liked ones, biggest first, so a new
        // listener still gets a list.
        let artistOrder = (0..<index.artistCount).filter { artistAffinity[$0] >= 0 }.sorted { x, y in
            if artistAffinity[x] != artistAffinity[y] { return artistAffinity[x] > artistAffinity[y] }
            let cx = index.artistOwnTracks[x].count, cy = index.artistOwnTracks[y].count
            if cx != cy { return cx > cy }
            return index.artistKeys[x] < index.artistKeys[y]
        }
        let genreOrder = (0..<index.genreCount).filter { genreAffinity[$0] >= 0 }.sorted { x, y in
            if genreAffinity[x] != genreAffinity[y] { return genreAffinity[x] > genreAffinity[y] }
            let cx = index.genreTracks[x].count, cy = index.genreTracks[y].count
            if cx != cy { return cx > cy }
            return index.genreKeys[x] < index.genreKeys[y]
        }
        let trackOrder = (0..<n).filter { trackAffinity[$0] > 0 }.sorted { x, y in
            if trackAffinity[x] != trackAffinity[y] { return trackAffinity[x] > trackAffinity[y] }
            if tracks[x].playCount != tracks[y].playCount { return tracks[x].playCount > tracks[y].playCount }
            return x < y
        }

        self.now = now
        self.index = index
        self.trackAffinity = trackAffinity
        self.familiarity = familiarity
        self.hoursSinceHeard = hours
        self.artistAffinity = artistAffinity
        self.genreAffinity = genreAffinity
        self.thumbsDown = thumbsDown
        self.rankedArtists = artistOrder.map { index.artistKeys[$0] }
        self.rankedGenres = genreOrder.map { index.genreKeys[$0] }
        self.rankedTracks = trackOrder.map { tracks[$0].id }
    }

    static func bounded(_ x: Double, _ low: Double = -1, _ high: Double = 1) -> Double {
        x.isFinite ? min(high, max(low, x)) : 0
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let at = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[min(sorted.count - 1, max(0, at))]
    }
}

// MARK: - For building on (the mixes)

extension TasteProfile {
    /// Track ids, most liked first; only tracks with some liking (> 0).
    public func topTracks(_ count: Int) -> [ItemID] { Array(data.rankedTracks.prefix(max(0, count))) }

    /// When the track was last heard, by Jellyfin's last-played date or this
    /// device's history, whichever is later.
    public func lastHeard(_ id: ItemID) -> Date? {
        guard let i = data.index.trackByID[id] else { return nil }
        let hours = data.hoursSinceHeard[i]
        return hours.isFinite ? data.now.addingTimeInterval(-hours * 3600) : nil
    }

    /// The moment the profile was made for.
    public var now: Date { data.now }
}
