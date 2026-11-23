// On Your Jukebox's plays (first Your Year), from the first source that is
// really there (JukeboxKit's YourYear): Jellyfin's or Emby's Playback
// Reporting where it answers this user (`ServerCapability.playbackReporting`),
// every device; otherwise this device's own history, and the page says so.
// Plex's history (viewedAt) is not used, and not tried: the test Plex is
// unclaimed and offline. One file for every client (Package.swift's
// `shared`), with the page's words; each draws the page its own way.

import Foundation
import JukeboxKit

enum YourYearLoader {
    /// The page's name, everywhere it is offered: "Your year kun je on your
    /// jukebox van maken" (the photographer, 23 November 2026).
    static var title: String { String(localized: "On Your Jukebox") }

    /// The page opens on the week: what he showed was a week's ("het gewoon
    /// wekelijks/maandelijks/jaarlijks laten zien", in that order).
    static let firstPeriod = YourYear.Period.week

    static func name(_ period: YourYear.Period) -> String {
        switch period {
        case .week: String(localized: "This Week")
        case .month: String(localized: "This Month")
        case .year: String(localized: "This Year")
        }
    }

    /// The period holding `now`. Each is the calendar's own, as its name
    /// says: no year just over in January (the page has This Week and This
    /// Month for the first days).
    static func load(period: YourYear.Period, now: Date = Date(), server: (any MusicServer)?,
                     history: ListeningHistory, library: LibraryStore) async -> YourYear {
        let interval = period.interval(containing: now)
        if let jellyfin = server as? JellyfinServer, jellyfin.capabilities.contains(.playbackReporting),
           let plays = try? await jellyfin.client.playbackReportingPlays(in: interval) {
            return YourYear.make(period: period, now: now, source: .server,
                                 plays: plays.map { YearPlay(trackID: $0.itemID, date: $0.date, seconds: $0.seconds) },
                                 track: { library.track(id: $0) })
        }
        return YourYear.make(period: period, now: now, source: .thisDevice, plays: YourYear.plays(from: history),
                             track: { library.track(id: $0) })
    }

    /// The head, in the serif as on a sleeve: "23 Nov – 29 Nov",
    /// "November", "2026", in the device's language.
    static func heading(_ made: YourYear, calendar: Calendar = .current) -> String {
        func format(_ template: String, _ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }
        let start = made.interval.start
        switch made.period {
        case .week:
            let last = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(format("dMMM", start)) – \(format("dMMM", last))"
        case .month:
            return format("LLLL", start)
        case .year:
            return String(calendar.component(.year, from: start))
        }
    }

    /// Under the head: the minutes and the plays.
    static func facts(_ made: YourYear) -> String {
        let minutes = made.minutes.formatted()
        let plays = made.plays.formatted()
        return String(localized: "\(minutes) minutes · \(plays) plays")
    }

    static func source(_ made: YourYear) -> String {
        switch made.source {
        case .server: String(localized: "Every device, from Playback Reporting on your server.")
        case .thisDevice: String(localized: "This device only. Playback Reporting on a Jellyfin or Emby server counts every device.")
        }
    }

    /// Under the spread's bars, one a bar: the weekdays' letters from the
    /// calendar's first, every seventh day of a month ("1", "8", "15", "22",
    /// "29"; a label under each of 31 bars would not fit a phone), the
    /// months' letters.
    static func spreadLabels(_ made: YourYear, calendar: Calendar = .current) -> [String] {
        switch made.period {
        case .week:
            let letters = calendar.veryShortStandaloneWeekdaySymbols
            guard letters.count == 7 else { return Array(repeating: "", count: made.spread.count) }
            return (0..<made.spread.count).map { letters[(calendar.firstWeekday - 1 + $0) % 7] }
        case .month:
            return (0..<made.spread.count).map { $0 % 7 == 0 ? String($0 + 1) : "" }
        case .year:
            let letters = calendar.veryShortStandaloneMonthSymbols
            return (0..<made.spread.count).map { letters.indices.contains($0) ? letters[$0] : "" }
        }
    }

    /// The bars' name for VoiceOver and Orca.
    static func spreadName(_ made: YourYear) -> String {
        made.period == .year ? String(localized: "Minutes by month") : String(localized: "Minutes by day")
    }

    /// "12 plays".
    static func plays(_ entry: YourYear.Entry) -> String {
        String(localized: "\(entry.plays) plays")
    }
}
