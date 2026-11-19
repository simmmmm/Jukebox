// Your Year's plays, from the first source that is really there
// (JukeboxKit's YourYear): Jellyfin's or Emby's Playback Reporting where it
// answers this user (`ServerCapability.playbackReporting`), every device;
// otherwise this device's own history, and the page says so. Plex's
// history (viewedAt) is not used: the test Plex is unclaimed and offline,
// so it could not be proven to answer. One file for every client
// (Package.swift's `shared`); each draws the page its own way, from
// Settings' server section (no new button: "niet 10000 knopen").

import Foundation
import JukeboxKit

enum YourYearLoader {
    /// The year to show: this one, or in January the one just over.
    static func year(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) == 1 ? year - 1 : year
    }

    static func load(year: Int, server: (any MusicServer)?, history: ListeningHistory,
                     library: LibraryStore) async -> YourYear {
        if let jellyfin = server as? JellyfinServer, jellyfin.capabilities.contains(.playbackReporting),
           let plays = try? await jellyfin.client.playbackReportingPlays(year: year) {
            return YourYear.make(year: year, source: .server,
                                 plays: plays.map { YearPlay(trackID: $0.itemID, date: $0.date, seconds: $0.seconds) },
                                 track: { library.track(id: $0) })
        }
        return YourYear.make(year: year, source: .thisDevice, plays: YourYear.plays(from: history),
                             track: { library.track(id: $0) })
    }

    /// Under the year: the minutes, the plays, and where they come from.
    static func facts(_ year: YourYear) -> String {
        let minutes = year.minutes.formatted()
        let plays = year.plays.formatted()
        return String(localized: "\(minutes) minutes · \(plays) plays")
    }

    static func source(_ year: YourYear) -> String {
        switch year.source {
        case .server: String(localized: "Every device, from Playback Reporting on your server.")
        case .thisDevice: String(localized: "This device only. Playback Reporting on a Jellyfin or Emby server counts every device.")
        }
    }

    /// "J" … "D" under the months' bars, in the device's language.
    static var monthLetters: [String] {
        let formatter = DateFormatter()
        return formatter.veryShortStandaloneMonthSymbols ?? ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    }

    /// "12 plays".
    static func plays(_ entry: YourYear.Entry) -> String {
        String(localized: "\(entry.plays) plays")
    }
}
