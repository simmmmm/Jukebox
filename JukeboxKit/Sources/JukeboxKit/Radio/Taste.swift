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

    // The clock (docs/RADIO.md, "The clock"): "leren van wanneer ik welke
    // muziek op prijs kan stellen en daar mijn 'your station' op afbaken"
    // (the photographer, 18 November 2026). Only Your Station reads these.
    /// When `now` is: weekday or weekend, part of the day.
    let slot: TimeSlot
    /// By artist and genre number: λ · L, how much more (or less, below 0)
    /// they are heard around this hour on this kind of day than overall,
    /// already shrunk by the evidence. 0 everywhere without a pattern.
    let artistLift: [Double]
    let genreLift: [Double]
    /// λ = n / (n + 12), n the sessions near now.
    let timeConfidence: Double
    /// By genre number: its share of what was heard to the end near now, and
    /// overall (for the fact on Your Station's card and the tests).
    let genreShareNow: [Double]
    let genreShareAll: [Double]

    // What each outcome says, and how fast it fades (docs/RADIO.md).
    static let halfLifeDays = 21.0
    static let playCountHalfLifeDays = 90.0
    /// How long a thumbs down keeps a song off the radio: the mixes' half year.
    static let thumbsDownDays = 183.0
    /// A song this familiar (and not by its skips) that is skipped is "not
    /// now", not "less": the skip counts in its own hours only. Measured
    /// and argued in docs/RADIO.md ("Not now").
    static let knownSkip = 0.6
    /// The clock's prior: sessions near now before λ is a half.
    static let sessionPrior = 12.0
    /// Smoothing of a share before the log ratio, and the ratio's bound.
    static let liftAlpha = 0.05
    static let liftBound = 1.0
    /// Only what is heard clearly more now (a quarter more than at other
    /// hours) lifts. Less, below 0, did not: Jazz heard on
    /// workday mornings made its share overall larger, so at 15:00 its lift
    /// was below 0 and Your Station dropped it from 0.18 to 0.12 of its
    /// picks, though the listener plays it then as much as anywhere else
    /// but the mornings; and by chance alone a listener with no pattern
    /// moved a cluster's share by up to 0.05 (measured, RadioClockTests).
    static let liftThreshold = log(1.6)
    /// What a scrobble counts for the clock against one of this device's
    /// plays: what was heard elsewhere (a phone in a pocket, someone else
    /// at the speaker) says less of this listener here. Measured in
    /// docs/RADIO.md ("Scrobbles").
    static let scrobbleWeight = 0.5
    /// A gap this long between two events starts a new session.
    static let sessionGap = 45.0 * 60

    /// How near an event's hour and kind of day are to now's: about ±3 hours
    /// wide, round over midnight; × 0.3 on the other kind of day.
    static func nearness(hours: Double, sameKindOfDay: Bool) -> Double {
        exp(2 * (cos(2 * .pi * hours / 24) - 1)) * (sameKindOfDay ? 1 : 0.3)
    }

    static func value(of outcome: PlayOutcome) -> Double {
        switch outcome {
        case .completed: 1
        case .partial: 0.3
        case .skipped: -0.8
        case .liked: 3
        case .disliked: -4
        }
    }

    /// - Parameter scrobbles: Last.fm's plays of library songs, for the
    ///   clock only (SimilarityService.scrobbles); none changes nothing.
    /// - Parameter timeAware: false is the radio as it was before the clock
    ///   (no lift, a skip counting everywhere), for the measurements.
    init(snapshot: LibrarySnapshot, history: ListeningHistory, scrobbles: ListeningHistory = ListeningHistory(),
         now: Date, calendar: Calendar = .current, timeAware: Bool = true,
         scrobbleWeight: Double = TasteData.scrobbleWeight) {
        let index = snapshot.index
        let tracks = snapshot.tracks
        let n = tracks.count
        let reference = now.timeIntervalSinceReferenceDate
        func days(since date: Date) -> Double {
            let d = (reference - date.timeIntervalSinceReferenceDate) / 86_400
            return d.isFinite ? max(0, d) : 0
        }
        let at = history.events.map { index.trackByID[$0.trackID] }

        // The clock: each event's hour and kind of day, by arithmetic rather
        // than a Calendar call per event (20 000 of them).
        // ponytail: one offset for all, now's: across a DST change an event
        // is an hour off, well inside the ±3 hours; Saturday and Sunday are
        // the weekend whatever the locale says.
        let offset = Double(calendar.timeZone.secondsFromGMT(for: now))
        func clock(_ date: Date) -> (hour: Double, weekend: Bool) {
            let local = date.timeIntervalSince1970 + offset
            guard local.isFinite else { return (0, false) }
            let day = (local / 86_400).rounded(.down)
            // 1 January 1970 was a Thursday; 0 is Sunday.
            let weekday = ((Int(max(-1e12, min(1e12, day))) + 4) % 7 + 7) % 7
            return ((local - day * 86_400) / 3600, weekday == 0 || weekday == 6)
        }
        let nowClock = clock(now)
        let near: [Double] = history.events.map { event in
            let c = clock(event.date)
            return Self.nearness(hours: c.hour - nowClock.hour, sameKindOfDay: c.weekend == nowClock.weekend)
        }

        // How well each song is known before its skips: a skip's own quarter
        // play would make a song skipped a dozen times "well known".
        var knownEvents = [Double](repeating: 0, count: n)
        var knownLight = [Double](repeating: 0, count: n)
        for (k, event) in history.events.enumerated() {
            guard let i = at[k] else { continue }
            switch event.outcome {
            case .completed: knownEvents[i] += 1
            case .partial, .liked: knownLight[i] += 0.5
            case .skipped, .disliked: break
            }
        }
        let known: [Bool] = (0..<n).map { i in
            let heard = max(Double(max(0, tracks[i].playCount)), knownEvents[i]) + knownLight[i]
            return tracks[i].isFavorite || 1 - exp(-heard / 3) >= Self.knownSkip
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
        // The clock's evidence: what was heard (positive outcomes), near now
        // and overall, by artist and genre; and the sessions near now.
        var artistNear = [Double](repeating: 0, count: index.artistCount)
        var artistAll = [Double](repeating: 0, count: index.artistCount)
        var genreNear = [Double](repeating: 0, count: index.genreCount)
        var genreAll = [Double](repeating: 0, count: index.genreCount)
        var totalNear = 0.0, totalAll = 0.0
        var sessions = 0.0, session = 0.0
        var sessionEnd = -Double.infinity
        /// One event for the clock, oldest first: `weight` 1 for this
        /// device's, `scrobbleWeight` for one of Last.fm's.
        func countForClock(_ event: PlayEvent, track: Int?, date: Double, near: Double, decay: Double,
                           value v: Double, weight: Double) {
            // A session counts once, by its nearest event.
            if date - sessionEnd > Self.sessionGap {
                sessions += session
                session = 0
            }
            sessionEnd = max(sessionEnd, date)
            session = max(session, weight * near * decay)
            guard v > 0 else { return }
            let w = v * weight
            totalAll += w
            totalNear += w * near
            if let t = track {
                for a in index.trackArtists[t] {
                    artistAll[a] += w
                    artistNear[a] += w * near
                }
                for (j, g) in index.trackGenres[t].enumerated() {
                    let gw = w * index.genreWeight(t, j)
                    genreAll[g] += gw
                    genreNear[g] += gw * near
                }
            } else {
                for a in event.artistKeys.compactMap({ index.artistByKey[$0] }) {
                    artistAll[a] += w
                    artistNear[a] += w * near
                }
                for g in event.genreKeys.compactMap({ index.genreByKey[$0] }) {
                    genreAll[g] += w
                    genreNear[g] += w * near
                }
            }
        }

        // Last.fm's scrobbles (docs/RADIO.md, "Scrobbles"): weeks of when
        // the listener plays what, on day one. Only those older than this
        // device's first event, so a play this device also scrobbled (a
        // Navidrome or a Jellyfin plugin sends them) is never counted twice;
        // for the clock alone (Jellyfin's play counts already say what is
        // liked), and below this device's own.
        if timeAware, !scrobbles.events.isEmpty {
            let firstOwn = history.events.lazy.map(\.date).min() ?? .distantFuture
            for event in scrobbles.events.sorted(by: { $0.date < $1.date }) where event.date < firstOwn {
                let date = event.date.timeIntervalSinceReferenceDate
                guard date.isFinite else { continue }
                let c = clock(event.date)
                let near = Self.nearness(hours: c.hour - nowClock.hour, sameKindOfDay: c.weekend == nowClock.weekend)
                let decay = exp2(-days(since: event.date) / Self.halfLifeDays)
                countForClock(event, track: index.trackByID[event.trackID], date: date, near: near, decay: decay,
                              value: decay, weight: scrobbleWeight)
            }
        }

        for (k, event) in history.events.enumerated() {
            let decay = exp2(-days(since: event.date) / Self.halfLifeDays)
            var v = Self.value(of: event.outcome) * decay
            let date = event.date.timeIntervalSinceReferenceDate
            if timeAware, date.isFinite {
                countForClock(event, track: at[k], date: date, near: near[k], decay: decay, value: v, weight: 1)
                // Not now: a song the listener knows, skipped, was not
                // wanted then. Pandora's "tired of this track" against its
                // thumbs down; the research's (docs/RADIO.md) "a skip of a
                // loved song is mostly 'not now'". It counts in its own hours
                // and kind of day, not against the song (and its artist and
                // genres) everywhere for weeks; the freshness rests it.
                if event.outcome == .skipped, let i = at[k], known[i] { v *= near[k] }
            }
            if let i = at[k] {
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

        // The lift: L = ln((share near now + α) / (share overall + α)),
        // shrunk toward nothing by λ = n / (n + 12): with few sessions near
        // now the station is what it was.
        sessions += session
        let confidence = timeAware && sessions > 0 ? sessions / (sessions + Self.sessionPrior) : 0
        func shares(_ values: [Double], _ total: Double) -> [Double] {
            total > 0 ? values.map { $0 / total } : values.map { _ in 0 }
        }
        let genreShareNow = shares(genreNear, totalNear), genreShareAll = shares(genreAll, totalAll)
        func lifts(_ nearValues: [Double], _ allValues: [Double]) -> [Double] {
            guard confidence > 0, totalNear > 0 else { return nearValues.map { _ in 0 } }
            // Against the rest of the hours, not all of them: the slot's own
            // plays made "overall" lean its way (Jazz 0.66 near workday 08:00
            // against 0.44 overall, but 0.3 at other hours).
            let away = zip(allValues, nearValues).map { max(0, $0 - $1) }
            return zip(shares(nearValues, totalNear), shares(away, totalAll - totalNear)).map { now, rest in
                let l = log((now + Self.liftAlpha) / (rest + Self.liftAlpha))
                return l >= Self.liftThreshold ? confidence * min(l, Self.liftBound) : 0
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
            for (k, g) in index.trackGenres[i].enumerated() { genreEvidence[g] += signed * index.genreWeight(i, k) }
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
        self.slot = TimeSlot(hour: Int(nowClock.hour), weekend: nowClock.weekend)
        self.timeConfidence = confidence
        self.artistLift = lifts(artistNear, artistAll)
        self.genreLift = lifts(genreNear, genreAll)
        self.genreShareNow = genreShareNow
        self.genreShareAll = genreShareAll
    }

    /// The fact only with enough sessions near now (λ a half, twelve) and a
    /// genre heard clearly more now (λ · L 0.3, a third more), in at least
    /// a sixth of what was heard then: a card says it only when it is so.
    var timeFact: TimeFact? {
        guard timeConfidence >= 0.4 else { return nil }
        let genres = genreLift.indices
            .filter { genreLift[$0] >= 0.3 && genreShareNow[$0] >= 1.0 / 6 }
            .sorted { genreShareNow[$0] != genreShareNow[$1] ? genreShareNow[$0] > genreShareNow[$1] : $0 < $1 }
            .prefix(2)
        guard !genres.isEmpty else { return nil }
        return TimeFact(slot: slot, genres: genres.map { index.genreNames[$0] })
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

extension TasteData {
    func artistLift(key: String) -> Double { index.artistByKey[key].map { artistLift[$0] } ?? 0 }
    func genreLift(key: String) -> Double { index.genreByKey[key].map { genreLift[$0] } ?? 0 }
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
