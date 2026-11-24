// On Your Jukebox (first Your Year): the songs, artists, albums and genres
// a week, a month or a year was made of, the minutes, and how they spread
// over its days or months. "Your year kun je on your jukebox van maken en
// het gewoon wekelijks/maandelijks/jaarlijks laten zien" (the photographer,
// 23 November 2026). The period is the calendar's own: its week starts on
// the day the device's calendar starts one. From the server's own
// record of every play when it keeps one (Jellyfin's Playback Reporting:
// every device), otherwise from this device's history, and then it says so.
// The photographer, 18 November 2026, of the other players' features: "wat
// is echt belangrijk om te hebben?" — and "ik heb playback reporting
// geinstalleerd".

import Foundation

/// One play, wherever it was kept.
public struct YearPlay: Sendable, Hashable {
    public var trackID: ItemID
    public var date: Date
    public var seconds: TimeInterval

    public init(trackID: ItemID, date: Date, seconds: TimeInterval) {
        self.trackID = trackID
        self.date = date
        self.seconds = seconds
    }
}

public struct YourYear: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// Every device's plays, kept by the server (Playback Reporting).
        case server
        /// Only what this device heard (HistoryStore).
        case thisDevice
    }

    /// The calendar's week, month or year that holds a moment.
    public enum Period: String, Sendable, CaseIterable, Hashable {
        case week, month, year

        /// The unit of the spread: days for a week or a month, months for
        /// a year.
        public var bucket: Calendar.Component { self == .year ? .month : .day }

        /// The week (from `calendar.firstWeekday`), month or year holding
        /// `now`, in `calendar`'s time zone.
        public func interval(containing now: Date, calendar: Calendar = .current) -> DateInterval {
            let unit: Calendar.Component = switch self {
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
            return calendar.dateInterval(of: unit, for: now) ?? DateInterval(start: now, duration: 0)
        }
    }

    /// A song, artist, album or genre and how much of the period it was.
    public struct Entry: Sendable, Hashable, Identifiable {
        /// The track's or album's id; the artist's or genre's name key.
        public var id: String
        public var name: String
        /// The artist, for a song or an album.
        public var detail: String?
        /// The song or album whose cover stands for it.
        public var track: Track?
        public var plays: Int
        public var minutes: Int
    }

    public var period: Period
    public var interval: DateInterval
    public var source: Source
    public var plays: Int
    public var minutes: Int
    /// Minutes in each day of a week or a month, or each month of a year,
    /// the first first: 7, 28 to 31, or 12.
    public var spread: [Int]
    public var songs: [Entry]
    public var artists: [Entry]
    public var albums: [Entry]
    public var genres: [Entry]

    public var isEmpty: Bool { plays == 0 }

    /// How many of each kind are kept.
    public static let top = 10

    /// The period holding `now`, from its plays. A play of a song the
    /// library no longer has counts in the minutes and the spread, not in
    /// the lists (it has no name to show). `calendar`'s time zone places a
    /// play in its day; days are counted as days, not as 24 hours, so a
    /// week with a clock change still has seven.
    public static func make(period: Period, now: Date = Date(), source: Source, plays: [YearPlay],
                            track: (ItemID) -> Track?, calendar: Calendar = .current) -> YourYear {
        let interval = period.interval(containing: now, calendar: calendar)
        func bucket(_ date: Date) -> Int {
            calendar.dateComponents([period.bucket], from: interval.start, to: date).value(for: period.bucket) ?? 0
        }
        // The end is the next period's start: the last bucket is the one
        // just before it.
        let buckets = max(1, bucket(interval.end.addingTimeInterval(-1)) + 1)
        var spread = [Double](repeating: 0, count: buckets)
        var total = 0.0
        var count = 0
        var songs: [String: (Track, Int, Double)] = [:]
        var artists: [String: (String, Track, Int, Double)] = [:]
        var albums: [String: (Track, Int, Double)] = [:]
        var genres: [String: (String, Track, Int, Double)] = [:]
        // Half open: a play at the next period's first moment is the next's.
        for play in plays where play.date >= interval.start && play.date < interval.end {
            let seconds = max(0, play.seconds)
            count += 1
            total += seconds
            spread[min(max(0, bucket(play.date)), buckets - 1)] += seconds
            guard let song = track(play.trackID) else { continue }
            songs[song.id, default: (song, 0, 0)].1 += 1
            songs[song.id]!.2 += seconds
            if let artist = song.artists.first ?? song.albumArtist {
                let key = NameKey.artist(artist.name)
                artists[key, default: (artist.name, song, 0, 0)].2 += 1
                artists[key]!.3 += seconds
            }
            if let album = song.albumID {
                albums[album, default: (song, 0, 0)].1 += 1
                albums[album]!.2 += seconds
            }
            for name in LibrarySnapshot.Index.splitGenreNames(song.genres) {
                let key = NameKey.genre(name)
                guard !key.isEmpty else { continue }
                genres[key, default: (name, song, 0, 0)].2 += 1
                genres[key]!.3 += seconds
            }
        }
        func minutes(_ seconds: Double) -> Int { Int((seconds / 60).rounded()) }
        func ranked(_ list: [Entry]) -> [Entry] {
            Array(list.sorted {
                ($0.plays, $0.minutes, $1.name) > ($1.plays, $1.minutes, $0.name)
            }.prefix(top))
        }
        return YourYear(
            period: period, interval: interval, source: source, plays: count, minutes: minutes(total),
            spread: spread.map(minutes),
            songs: ranked(songs.map { Entry(id: $0.key, name: $0.value.0.name, detail: $0.value.0.artists.first?.name,
                                            track: $0.value.0, plays: $0.value.1, minutes: minutes($0.value.2)) }),
            artists: ranked(artists.map { Entry(id: $0.key, name: $0.value.0, detail: nil, track: $0.value.1,
                                                plays: $0.value.2, minutes: minutes($0.value.3)) }),
            albums: ranked(albums.map { Entry(id: $0.key, name: $0.value.0.albumName ?? $0.value.0.name,
                                              detail: ($0.value.0.albumArtist ?? $0.value.0.artists.first)?.name,
                                              track: $0.value.0, plays: $0.value.1, minutes: minutes($0.value.2)) }),
            genres: ranked(genres.map { Entry(id: $0.key, name: $0.value.0, detail: nil, track: $0.value.1,
                                              plays: $0.value.2, minutes: minutes($0.value.3)) }))
    }

    /// This device's history as plays: what was heard, not a skip or a
    /// thumb (a thumb is its own event, not a play).
    public static func plays(from history: ListeningHistory) -> [YearPlay] {
        history.events.compactMap { event in
            guard event.outcome == .completed || event.outcome == .partial else { return nil }
            return YearPlay(trackID: event.trackID, date: event.date, seconds: event.listened)
        }
    }
}
