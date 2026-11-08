// Lyrics for the LRC parser and LRCLIB's answers for the client, all made
// up here: two songs written for these tests (a Dutch one in plain LRC with
// metadata, an offset, a chorus stamped twice and pauses; an English one in
// Enhanced LRC with word stamps, Windows line ends and every form of time
// stamp), and LRCLIB's records as its documentation describes them. Nothing
// is copied from a real song.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit

enum LyricsFixtures {
    /// "Langs het water" by De Kanaalzangers, 3:12. The chorus (0:41 and
    /// 1:32) is written once with two stamps; [offset:+250] shows every
    /// line a quarter second sooner; two empty lines in a row at 1:50.
    static let dutch = """
    [ar:De Kanaalzangers]
    [ti:Langs het water]
    [al:Oktoberlicht]
    [by:Jukebox-tests]
    [length: 03:12]
    [offset:+250]

    [00:12.40]De lantaarns gaan aan langs het water
    [00:16.85]Jij fietst voor mij uit door de mist
    [00:21.10]Ik roep je naam, maar die waait naar later
    [00:25.60]Naar een straat die ik nog niet wist
    [00:30.20]
    [00:41.20][01:32.20]Hou me vast, de brug gaat open
    [00:45.75][01:36.75]Hou me vast, de nacht is lang
    [00:50.30][01:41.30]Alles wat we nooit beloofden
    [00:54.90][01:45.90]Klinkt vannacht als een gezang
    [00:59.50]
    [01:05.00]De bakker slaapt nog, de kerk telt de uren
    [01:09.40]Een kat op een dak kijkt ons na
    [01:13.80]Wat wij hier bouwen hoeft niet te duren
    [01:18.20]Zolang ik naast jou verder ga
    [01:50.50]
    [01:50.90]
    [02:20.00]Langs het water, langs het water
    [02:24.60]Tot de ochtend ons vindt
    """

    /// "Paper Lanterns" by The Harbour Lights, 3:30: a byte order mark,
    /// "\r\n" line ends, word stamps with and without spaces around them,
    /// [mm:ss.xxx], [mm:ss.x], [m:ss.xx], [mm:ss:xx] and [mm:ss], and an
    /// aside in brackets that is part of the words.
    static let english = [
        "\u{FEFF}[ti:Paper Lanterns]",
        "[ar:The Harbour Lights]",
        "[al:Low Tide Radio]",
        "[re:Typed by hand for the tests]",
        "[ve:1.0]",
        "",
        "[00:08.00]<00:08.00>We <00:08.40>folded <00:09.10>paper <00:09.80>lanterns",
        "[00:11.50]<00:11.50>and <00:11.90>lit them <00:12.60>one by one",
        "[00:15.20]<00:15.20> The <00:15.50> river <00:16.10> took <00:16.40> the <00:16.70> brightest",
        "[00:19.00]Down to where the night had gone",
        "[00:23.000]",
        "[00:31.5]Oh, hold the light (hold the light)",
        "[00:35.25]Don't let the morning [laughs] in too soon",
        "[0:39.75]We were never made of daylight",
        "[00:44:10]We were made of paper and the moon",
        "[01:02]Paper and the moon",
        "",
    ].joined(separator: "\r\n")

    static let dutchPlain = """

    De lantaarns gaan aan langs het water
    Jij fietst voor mij uit door de mist


    Hou me vast, de brug gaat open
    Hou me vast, de nacht is lang

    """

    // MARK: - LRCLIB's records

    /// One record, as LRCLIB sends it; nil fields as JSON's null.
    static func record(id: Int = 1, track: String, artist: String, album: String, duration: Double,
                       instrumental: Bool = false, plain: String? = nil, synced: String? = nil) -> [String: Any] {
        [
            "id": id,
            "name": track,
            "trackName": track,
            "artistName": artist,
            "albumName": album,
            "duration": duration,
            "instrumental": instrumental,
            "plainLyrics": plain.map { $0 as Any } ?? NSNull(),
            "syncedLyrics": synced.map { $0 as Any } ?? NSNull(),
        ]
    }

    static func json(_ object: Any) -> Data {
        // Fixtures written here: a failure is the test's own mistake.
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static let notFound = Data(#"{"code":404,"name":"TrackNotFound","message":"Failed to find specified track"}"#.utf8)

    /// "Langs het water" as LRCLIB would have it, synced, 192 s.
    static var dutchRecord: [String: Any] {
        record(id: 4242, track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
               duration: 192, plain: dutchPlain, synced: dutch)
    }
}

/// Answers each request with the handler; keeps what was asked.
final class LRCLIBMockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> HTTPResponse

    private let lock = NSLock()
    private let handler: Handler
    private var sent: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// /api/get answers `get` (404 when nil), /api/search answers `search`.
    convenience init(get: Data?, getStatus: Int = 200, search: Data = Data("[]".utf8)) {
        self.init { request in
            switch request.url?.path {
            case "/api/get":
                guard let get else { return HTTPResponse(status: 404, body: LyricsFixtures.notFound) }
                return HTTPResponse(status: getStatus, body: get)
            case "/api/search":
                return HTTPResponse(status: 200, body: search)
            default:
                return HTTPResponse(status: 404, body: Data())
            }
        }
    }

    var requests: [URLRequest] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lock.withLock { sent.append(request) }
        return try handler(request)
    }
}

extension URLRequest {
    /// The query as name → value, decoded.
    var lrclibQuery: [String: String] {
        var query: [String: String] = [:]
        if let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items { query[item.name] = item.value ?? "" }
        }
        return query
    }
}
