// Jellyfin's (and Emby's) Playback Reporting plugin: every play of every
// client, kept on the server, so Your Year is the listener's year and not
// one device's. The photographer, 18 November 2026: "ik heb playback
// reporting geinstalleerd, maak daar ook ff een notitie van in de app
// settings en op de website".
//
// Measured on Jellyfin 12.4 with the plugin 19.0.0.0 (18 November 2026):
// - its one table is PlaybackActivity (DateCreated, UserId, ItemId,
//   ItemType, ItemName, PlaybackMethod, ClientName, DeviceName,
//   PlayDuration in seconds); POST /user_usage_stats/submit_custom_query
//   runs a SELECT on it and answers {"colums": [...], "results": [[text]]};
// - a play of 15 s was kept (PlayDuration "15"), one of 2 s was not;
// - an administrator gets 200, a user who is not one 403, a server without
//   the plugin 404 (the same on Emby 4.10 without it);
// - `SELECT *` fails ("Error processing request.") on a row with no
//   PlaybackMethod: the columns are named.
//
// An administrator reads the whole household's plays, so every query is
// of the signed-in user's id only.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One play the server kept.
public struct ServerPlay: Sendable, Hashable {
    public var date: Date
    public var itemID: ItemID
    public var seconds: TimeInterval

    public init(date: Date, itemID: ItemID, seconds: TimeInterval) {
        self.date = date
        self.itemID = itemID
        self.seconds = seconds
    }
}

struct PlaybackReportingQuery: Encodable, Sendable {
    var CustomQueryString: String
    var ReplaceUserId = false
}

struct PlaybackReportingAnswer: Decodable, Sendable {
    var colums: [String]?
    var results: [[String?]]?
}

extension JellyfinClient {
    /// The signed-in user's id as it may stand in the SQL: Jellyfin's are
    /// 32 hex digits, Emby's hex too; anything else is refused, never quoted.
    func reportingUser() throws -> String {
        let user = try requireUser()
        guard !user.isEmpty, user.allSatisfy({ $0.isHexDigit || $0 == "-" }) else {
            throw JellyfinError.decoding("a user id that is not hex")
        }
        return user
    }

    func reportingQuery(_ sql: String) async throws -> PlaybackReportingAnswer {
        let response = try await send("POST", "/user_usage_stats/submit_custom_query",
                                      json: PlaybackReportingQuery(CustomQueryString: sql), timeout: 20)
        return try decode(PlaybackReportingAnswer.self, from: response)
    }

    /// Whether the plugin answers this user: a count of their plays, the
    /// cheapest question that needs both the plugin and the right to ask.
    func playbackReportingAnswers() async throws {
        let user = try reportingUser()
        let answer = try await reportingQuery("SELECT COUNT(1) FROM PlaybackActivity WHERE UserId = '\(user)'")
        guard answer.results != nil else { throw JellyfinError.decoding("not Playback Reporting's answer") }
    }

    /// The user's plays of songs in a year, oldest first.
    public func playbackReportingPlays(year: Int) async throws -> [ServerPlay] {
        let user = try reportingUser()
        let sql = """
            SELECT DateCreated, ItemId, PlayDuration FROM PlaybackActivity \
            WHERE UserId = '\(user)' AND ItemType = 'Audio' \
            AND DateCreated >= '\(year)-01-01' AND DateCreated < '\(year + 1)-01-01' \
            ORDER BY DateCreated
            """
        let answer = try await reportingQuery(sql)
        return (answer.results ?? []).compactMap { row in
            guard row.count >= 3, let text = row[0], let id = row[1], !id.isEmpty,
                  let date = Self.reportingDate(text) else { return nil }
            return ServerPlay(date: date, itemID: id, seconds: TimeInterval(row[2] ?? "") ?? 0)
        }
    }

    /// "2026-11-18 19:12:12.4449127", the server's own clock in UTC.
    static func reportingDate(_ text: String) -> Date? {
        let head = String(text.prefix(19))
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return parser.date(from: head)
    }
}
