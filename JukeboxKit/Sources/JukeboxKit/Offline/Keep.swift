// How the automatic keep ranks and fills (docs/OFFLINE.md, "The keep").
//
// A song's score is how much it is wanted on the phone, from two sources:
// - this device's history (ListeningHistory): each play counts by how it
//   ended, fading with age;
// - the server's own count (Track.playCount, lastPlayed, isFavorite): every
//   device's plays, so a song heard on the web player or before this phone
//   still counts — and with an empty history it is all there is.
// The keep then takes the best songs that fit in its limit, with a margin
// for the songs it already holds, so it does not trade songs back and forth
// over small differences: every trade is a download.
//
// Every number is a value here, in `Tuning`, so the tests can measure what
// another would do (KeepPolicySimulationTests); the measured choice is
// `.standard`.

import Foundation

extension KeepPolicy {
    struct Tuning: Sendable {
        /// How fast this device's plays fade: two weeks. Measured with the
        /// margin on a made-up listener (OFFLINE.md, "Half-life and margin"):
        /// shorter follows the listener more closely and fetches more for
        /// it. Two weeks at a margin of 1.5 held 59.3% of the next day's
        /// plays for 1.8 downloads a day; the month first guessed held less
        /// for as many (30 days: 58.2% for 1.3, 59.0% for 2.8 with no
        /// margin), and one week holds no more for the same downloads (7
        /// days, margin 2: 58.9% for 1.5). "Often" over a longer time is the
        /// server's play count.
        var halfLifeDays = 14.0
        /// The server's play count is a lifetime total, so it fades with
        /// its last play over a quarter-year, never below a quarter (as the
        /// radio counts it, Taste.swift): played forty times two years ago
        /// is still "often", only not "lately".
        var playCountHalfLifeDays = 90.0
        var playCountFloor = 0.25
        /// A song the keep holds stays unless one wanted half as much again
        /// needs its room: with the half-life, a kept song no longer played
        /// keeps its place about eight days (14 × log2 1.5) after a newer one
        /// has caught up with it. Measured (OFFLINE.md, "Half-life and
        /// margin"): half the downloads of no margin for a point fewer plays
        /// on the phone, and a day with no plays trades nothing, where with
        /// no margin time alone trades songs back and forth. A margin of 2
        /// fetches a third less again (1.2 a day) but holds 1.7 points fewer
        /// than none.
        var incumbentBonus = 1.5
        /// Below this a song is not worth fetching, however much room is
        /// left: one completed play two months ago (2^(−60/14) ≈ 0.05).
        /// The server's count of a played song never falls under it.
        var minimumScore = 0.05

        static let standard = Tuning()
    }

    /// What one play on this device says. A completed play counts most; a
    /// thumbs up comes with a play of its own (recorded too), so it adds to
    /// that rather than standing for one. A skip is "not now" as often as
    /// "not this": two skips undo one listen.
    static func value(of outcome: PlayOutcome) -> Double {
        switch outcome {
        case .completed: 1
        case .partial: 0.3
        case .liked: 0.5
        case .skipped: -0.5
        case .disliked: -2
        }
    }

    /// What the server's favourite is worth: a play and a half. More than a
    /// song heard once today (1 + 0.6 from its play count, 1.6) would make a
    /// few hundred favourites never played crowd out this week's listening.
    static let favoriteValue = 1.5
    /// log2(1 + plays) × this: 1 play 0.6, 7 plays 1.8, 63 plays 3.6. A
    /// lifetime count grows without end; "often" does not.
    static let playCountWeight = 0.6

    /// Every library song's score, by id; nil for a song not worth keeping
    /// at all: one whose last thumbs is down within half a year (the radio
    /// leaves it out as long, TasteData.thumbsDownDays, and offline the radio
    /// plays only what is on the phone).
    static func scores(tracks: [Track], history: ListeningHistory, now: Date,
                       tuning: Tuning = .standard) -> [ItemID: Double] {
        let reference = now.timeIntervalSinceReferenceDate
        func days(since date: Date) -> Double {
            let d = (reference - date.timeIntervalSinceReferenceDate) / 86_400
            return d.isFinite ? max(0, d) : 0
        }

        var score: [ItemID: Double] = [:]
        score.reserveCapacity(tracks.count)
        for track in tracks where score[track.id] == nil {
            var s = track.isFavorite ? Self.favoriteValue : 0
            // A song can be "played" with no count: 12.4 sets LastPlayedDate
            // and not PlayCount for a play reported without its start
            // (JellyfinClient.reportStart's measurement).
            let plays = max(0, track.playCount, track.lastPlayed == nil ? 0 : 1)
            if plays > 0 {
                // A count with no date: halfway between lately and long ago.
                var recency = tuning.playCountFloor + (1 - tuning.playCountFloor) * 0.5
                if let last = track.lastPlayed {
                    recency = tuning.playCountFloor
                        + (1 - tuning.playCountFloor) * exp2(-days(since: last) / tuning.playCountHalfLifeDays)
                }
                s += Self.playCountWeight * log2(1 + Double(plays)) * recency
            }
            score[track.id] = s
        }

        // Oldest first, so the last thumbs given is the one that holds.
        var thumbsDownAt: [ItemID: Date] = [:]
        for event in history.events {
            guard let s = score[event.trackID] else { continue }
            let v = Self.value(of: event.outcome) * exp2(-days(since: event.date) / tuning.halfLifeDays)
            if v.isFinite { score[event.trackID] = s + v }
            switch event.outcome {
            case .disliked: thumbsDownAt[event.trackID] = event.date
            case .liked: thumbsDownAt[event.trackID] = nil
            default: break
            }
        }
        for (id, date) in thumbsDownAt where days(since: date) <= TasteData.thumbsDownDays {
            score[id] = nil
        }
        return score
    }

    static func plan(tracks: [Track], history: ListeningHistory, manifest: OfflineManifest,
                     limitBytes: Int64, quality: DownloadQuality, now: Date, tuning: Tuning) -> KeepPlan {
        // No library (not loaded yet, or a server that answered nothing) is
        // no reason to empty the phone: nothing is planned until there is.
        guard !tracks.isEmpty else { return KeepPlan(download: [], remove: []) }

        let score = scores(tracks: tracks, history: history, now: now, tuning: tuning)
        struct Candidate {
            var id: ItemID
            var rank: Double
            var bytes: Int64
            var isHeld: Bool
        }
        var candidates: [Candidate] = []
        var seen = Set<ItemID>()
        for track in tracks where seen.insert(track.id).inserted {
            let file = manifest.file(track.id)
            // Chosen songs are on the phone for their own reasons: not the
            // keep's to fetch or to let go, and not in its room.
            if file?.isChosen == true { continue }
            guard let s = score[track.id], s >= tuning.minimumScore else { continue }
            if let file {
                candidates.append(Candidate(id: track.id, rank: s * tuning.incumbentBonus,
                                            bytes: max(0, file.bytes), isHeld: true))
            } else {
                candidates.append(Candidate(id: track.id, rank: s,
                                            bytes: estimatedBytes(of: track, quality: quality), isHeld: false))
            }
        }
        // Ties by id: the same inputs, the same plan.
        candidates.sort { $0.rank != $1.rank ? $0.rank > $1.rank : $0.id < $1.id }

        // Best first, each that still fits: a long song that does not fit
        // leaves its room to shorter ones further down rather than to none.
        var room = max(0, limitBytes)
        var keep = Set<ItemID>()
        var download: [ItemID] = []
        for candidate in candidates where candidate.bytes <= room {
            room -= candidate.bytes
            keep.insert(candidate.id)
            if !candidate.isHeld { download.append(candidate.id) }
        }
        // What the keep alone holds and no longer wants, or whose song has
        // left the library.
        let remove = manifest.files.values
            .filter { !$0.isChosen && !keep.contains($0.trackID) }
            .map(\.trackID)
            .sorted()
        return KeepPlan(download: download, remove: remove)
    }
}
