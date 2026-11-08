// LRCLIB (lrclib.net): a free, open database of lyrics, most of them synced,
// with no key — where Now Playing looks when the listener's own server has
// no lyrics for a song. Feishin, the photographer's reference player, asks
// it too. The photographer, 8 November 2026: "Kun je ook lyrics toevoegen".
//
// GET /api/get?track_name=…&artist_name=…&album_name=…&duration=…
//   one record, matched by LRCLIB within ±2 s of the length; 404
//   {"code":404,"name":"TrackNotFound",…} when it has none.
// GET /api/search?track_name=…&artist_name=…
//   an array of records, perhaps empty.
// A record: {"id", "name", "trackName", "artistName", "albumName",
//   "duration", "instrumental", "plainLyrics", "syncedLyrics"}.
//
// LRCLIB asks every client to name itself, its version and a link in the
// User-Agent: "Jukebox/1.0 (https://github.com/simmmmm/Jukebox)".

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What LRCLIB knows of a song.
public enum LyricsLookup: Sendable, Hashable {
    /// Synced when the lines are timed (LRCLIB's syncedLyrics), plain
    /// otherwise.
    case found(Lyrics, synced: Bool)
    /// LRCLIB lists the song as having no words.
    case instrumental
    case notFound
}

public final class LRCLIBClient: Sendable {
    public enum Failure: Error, Sendable, Equatable, LocalizedError {
        /// Any answer but 200 or 404: LRCLIB is down or asks to wait. Not
        /// the same as "no lyrics", so nothing is remembered.
        case status(Int)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case let .status(status): "LRCLIB answered with status \(status)."
            case .unreadable: "LRCLIB's answer could not be read."
            }
        }
    }

    public static let defaultEndpoint = URL(string: "https://lrclib.net/api/")!

    /// A record more than this far from the song's own length is another
    /// recording (a live take, a radio edit), whose synced lines would run
    /// ahead or behind: never used.
    public static let durationTolerance: TimeInterval = 3

    public let userAgent: String
    public let endpoint: URL
    let transport: any HTTPTransport
    /// Short: Now Playing waits on it, and a song with no lyrics should say
    /// so before it has half played.
    let timeout: TimeInterval = 8

    public init(userAgent: String, transport: any HTTPTransport = URLSessionTransport(),
                endpoint: URL = LRCLIBClient.defaultEndpoint) {
        self.userAgent = userAgent
        self.transport = transport
        self.endpoint = endpoint
    }

    /// "Jukebox/1.0 (https://github.com/simmmmm/Jukebox)", as LRCLIB asks.
    public static func userAgent(appVersion: String) -> String {
        "Jukebox/\(appVersion) (https://github.com/simmmmm/Jukebox)"
    }

    /// The song's lyrics: /api/get with all four fields, and when LRCLIB
    /// has no record of exactly that, /api/search by title and artist,
    /// the best record of the same title and artist within 3 s of the
    /// length, synced lyrics before plain ones. A transport failure is
    /// thrown as the transport threw it, but for /api/get's timeout, after
    /// which the search is asked; "not found" is an answer.
    public func lyrics(artist: String, title: String, album: String?, duration: TimeInterval) async throws -> LyricsLookup {
        try await lyrics(LyricsQuery(artist: artist, title: title, album: album, duration: duration))
    }

    public func lyrics(_ query: LyricsQuery) async throws -> LyricsLookup {
        guard !query.artist.isEmpty, !query.title.isEmpty else { return .notFound }
        // /api/get needs every field: without an album or a length, the
        // search alone.
        if let album = query.album, query.seconds > 0, let response = try await getWithinTimeout([
            ("track_name", query.title),
            ("artist_name", query.artist),
            ("album_name", album),
            ("duration", String(query.seconds)),
        ]) {
            switch response.status {
            case 200:
                let record = try decode(LRCLIBRecord.self, response.body)
                if record.isClose(to: query), let lookup = record.lookup {
                    return lookup
                }
            case 404:
                break
            default:
                throw Failure.status(response.status)
            }
        }
        let response = try await send("search", [
            ("track_name", query.searchTitle),
            ("artist_name", query.artist),
        ])
        switch response.status {
        case 200:
            let records = try decode([LRCLIBRecord].self, response.body)
            return Self.best(of: records, for: query)?.lookup ?? .notFound
        case 404:
            return .notFound
        default:
            throw Failure.status(response.status)
        }
    }

    /// Of the records of this title by this artist within 3 s of the
    /// length: synced first, then the closest in length, then the same
    /// album. Instrumental records last, so a record with words wins over
    /// one that says there are none. Without a known length, the name
    /// alone decides.
    static func best(of records: [LRCLIBRecord], for query: LyricsQuery) -> LRCLIBRecord? {
        let album = query.album.map(NameKey.title)
        // Each record ranked once: its lyrics are parsed to rank it, and
        // `min` compares every pair.
        let ranked: [(record: LRCLIBRecord, rank: (Int, Double, Int))] = records.compactMap { record in
            guard record.isClose(to: query),
                  sameTitle(record.trackName ?? "", query.title),
                  sameArtist(record.artistName ?? "", query.artist),
                  let lookup = record.lookup else { return nil }
            let kind: Int
            switch lookup {
            case let .found(_, synced): kind = synced ? 0 : 1
            case .instrumental, .notFound: kind = 2
            }
            let off = query.seconds > 0 ? abs((record.duration ?? 0) - query.duration) : 0
            let sameAlbum = (album != nil && NameKey.title(record.albumName ?? "") == album) ? 0 : 1
            return (record, (kind, off, sameAlbum))
        }
        return ranked.min { $0.rank < $1.rank }?.record
    }

    /// The record's title is ours when their keys are (NameKey.title: no
    /// brackets, no "feat.", case and accents aside). A title of brackets
    /// or punctuation alone ("(Untitled)", "…") has no key, and would be
    /// the same as every other such title, so those are compared whole.
    static func sameTitle(_ recordTitle: String, _ title: String) -> Bool {
        let key = NameKey.title(title)
        if !key.isEmpty { return NameKey.title(recordTitle) == key }
        let whole = LyricsQuery.squeezeSpaces(title).lowercased()
        return !whole.isEmpty && LyricsQuery.squeezeSpaces(recordTitle).lowercased() == whole
    }

    /// Where stores and taggers join a song's artists, and where a guest's
    /// part or a name's "(US)" begins.
    static let creditBreaks = [",", ";", "/", "&", " + ", " x ", " and ", " feat. ", " feat ", " ft. ",
                               " featuring ", " with ", " ("]

    /// The record's artist is ours when the two names are the same, or when
    /// one is among the other's credits: "Daft Punk" and "Daft Punk,
    /// Pharrell Williams", which LRCLIB has from stores that join a song's
    /// artists. Whole names only: a name that only begins the other's
    /// letters is someone else ("Queen" and "Queensrÿche", "Kiss" and
    /// "Kissin' Dynamite").
    static func sameArtist(_ recordArtist: String, _ artist: String) -> Bool {
        let key = NameKey.artist(artist)
        let full = NameKey.artist(recordArtist)
        guard !key.isEmpty, !full.isEmpty else { return false }
        return full == key || credits(recordArtist).contains(key) || credits(artist).contains(full)
    }

    /// A name's credits, each as its key: "Daft Punk, Pharrell Williams" as
    /// "daftpunk" and "pharrellwilliams".
    static func credits(_ name: String) -> Set<String> {
        var marked = name
        for mark in creditBreaks {
            marked = marked.replacingOccurrences(of: mark, with: "\u{1F}", options: .caseInsensitive)
        }
        return Set(marked.split(separator: "\u{1F}").map { NameKey.artist(String($0)) }.filter { !$0.isEmpty })
    }

    // MARK: - The request

    /// RFC 3986's unreserved characters, everything else escaped: LRCLIB
    /// reads a bare "+" as a space, and "Simon + Garfunkel" must reach it
    /// as spelt (URLComponents leaves "+" as it is).
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    func request(_ path: String, _ parameters: [(String, String)]) throws -> URLRequest {
        let query = parameters.map { name, value in
            name + "=" + (value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? "")
        }.joined(separator: "&")
        guard let url = URL(string: path + "?" + query, relativeTo: endpoint)?.absoluteURL else {
            throw Failure.unreadable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func send(_ path: String, _ parameters: [(String, String)]) async throws -> HTTPResponse {
        try await transport.send(try request(path, parameters))
    }

    /// /api/get, or nil when it does not answer within the timeout. Its
    /// documentation says it looks beyond LRCLIB's own database for a song
    /// it has no record of (/api/get-cached is the one that does not), so a
    /// song LRCLIB lacks can be the slow one; the search answers from the
    /// database alone. Thrown, as it was, such a song failed each time it
    /// played and was never remembered as not found. Not measured: lrclib.net
    /// cannot be reached from where this was written.
    func getWithinTimeout(_ parameters: [(String, String)]) async throws -> HTTPResponse? {
        do {
            return try await send("get", parameters)
        } catch let error as URLError where error.code == .timedOut {
            return nil
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ body: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw Failure.unreadable
        }
    }
}

/// One of LRCLIB's records, every field optional: a record that lacks one
/// is still read, and what it lacks decides nothing.
struct LRCLIBRecord: Decodable, Sendable {
    var id: Int?
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var instrumental: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?

    /// Within 3 s of the song's length. A song without a length cannot be
    /// held to it. A record without one, for a song with one, cannot be
    /// told to be the same recording, and is not used (LRCLIB gives every
    /// record a length, so this costs nothing).
    func isClose(to query: LyricsQuery) -> Bool {
        guard query.seconds > 0 else { return true }
        guard let duration, duration > 0 else { return false }
        return abs(duration - query.duration) <= LRCLIBClient.durationTolerance
    }

    /// The record's lyrics, synced when it has them; nil when it has
    /// neither lyrics nor the instrumental mark.
    var lookup: LyricsLookup? {
        if let synced = syncedLyrics.flatMap(LRCParser.parse), synced.isSynced {
            return .found(synced, synced: true)
        }
        if let plain = plainLyrics.flatMap(LRCParser.plain) {
            return .found(plain, synced: false)
        }
        if instrumental == true { return .instrumental }
        return nil
    }
}
