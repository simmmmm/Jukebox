// The facts Jukebox writes where it used to write slogans (docs/design/
// tells.md, 5: "Facts, not slogans"): when something last played, said as a
// person says it — "Today", "Yesterday", the weekday within the week
// ("Thursday"), the date before that ("2 November"), with the year only when
// it is another year's. So "Played Thursday", "Last played yesterday", "Not
// played yet"; and Home's title by the hour, "Tonight". Foundation only, so
// it is tried on Linux with the kit.

import Foundation

nonisolated enum RelativeDay {
    /// How a day is named, seen from `now`.
    enum Name: Equatable, Sendable {
        case today
        case yesterday
        /// Two to six days ago: the weekday's name.
        case weekday(String)
        /// A week ago or longer: the date, the year only when it differs.
        case date(String)
    }

    /// The day `date` falls on, named from `now`, both in `calendar` (the
    /// listener's). A date ahead of now — another device's clock — is today.
    static func name(of date: Date, now: Date = Date(), calendar: Calendar = .current) -> Name {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return .today }
        if days == 1 { return .yesterday }
        if days < 7 {
            return .weekday(date.formatted(.dateTime.weekday(.wide)))
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return .date(date.formatted(.dateTime.day().month(.wide)))
        }
        return .date(date.formatted(.dateTime.day().month(.wide).year()))
    }

    /// On its own, at a row's end: "Today", "Yesterday", "Thursday", "2 November".
    static func standalone(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch name(of: date, now: now, calendar: calendar) {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case let .weekday(day), let .date(day): return day
        }
    }

    /// A station's row: "Played today", "Played Thursday", "Not played yet".
    static func played(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return String(localized: "Not played yet") }
        switch name(of: date, now: now, calendar: calendar) {
        case .today: return String(localized: "Played today")
        case .yesterday: return String(localized: "Played yesterday")
        case let .weekday(day), let .date(day): return String(localized: "Played \(day)")
        }
    }

    /// Your Station on Home: "Last played yesterday", "Not played yet".
    static func lastPlayed(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return String(localized: "Not played yet") }
        switch name(of: date, now: now, calendar: calendar) {
        case .today: return String(localized: "Last played today")
        case .yesterday: return String(localized: "Last played yesterday")
        case let .weekday(day), let .date(day): return String(localized: "Last played \(day)")
        }
    }

    /// Home's title by the hour, as sketch D's "Tonight" is the evening's:
    /// "This morning" from 5, "This afternoon" from 12, "This evening" from
    /// 17, "Tonight" from 21 until 5. What time it is, not a greeting.
    static func partOfDay(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return String(localized: "This morning")
        case 12..<17: return String(localized: "This afternoon")
        case 17..<21: return String(localized: "This evening")
        default: return String(localized: "Tonight")
        }
    }
}
