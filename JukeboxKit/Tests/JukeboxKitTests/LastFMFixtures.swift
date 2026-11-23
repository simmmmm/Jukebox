// Last.fm for the tests, which cannot reach it: its answers in the shapes
// its documentation and its servers give (artist.getsimilar with `match` as
// a string, track.getsimilar with `match` as a number, artist.gettoptracks
// with play counts and ranks as strings, errors as {"error": N, "message":
// …}), and a transport that answers from a small made-up knowledge of who
// sounds like whom, keeping every request and when it was sent.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit

/// A request as the mock reads it.
struct LastFMRequest: Sendable {
    var method: String
    var query: [String: String]
    var artist: String { query["artist"] ?? "" }
    var track: String { query["track"] ?? "" }
}

/// Answers instead of Last.fm, and keeps what it was asked.
final class LastFMMockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (LastFMRequest) throws -> HTTPResponse

    struct Sent: Sendable {
        var request: URLRequest
        var asked: LastFMRequest
        var at: ContinuousClock.Instant
    }

    private let lock = NSLock()
    private let handler: Handler
    private var sent: [Sent] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Answers from `knowledge`; anything it does not know is Last.fm's
    /// "not found".
    convenience init(_ knowledge: LastFMKnowledge) {
        self.init { request in knowledge.answer(request) }
    }

    var requests: [Sent] { lock.withLock { sent } }
    var count: Int { lock.withLock { sent.count } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        var query: [String: String] = [:]
        if let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items { query[item.name] = item.value ?? "" }
        }
        let asked = LastFMRequest(method: query["method"] ?? "", query: query)
        lock.withLock { sent.append(Sent(request: request, asked: asked, at: ContinuousClock().now)) }
        return try handler(asked)
    }
}

/// Who Last.fm says sounds like whom, for the mock.
struct LastFMKnowledge: Sendable {
    var similarArtists: [String: [(name: String, match: Double)]] = [:]
    /// By "artist|title".
    var similarTracks: [String: [(artist: String, title: String, match: Double)]] = [:]
    var topTracks: [String: [String]] = [:]
    /// By artist, as Last.fm spells them: (tag, count 0 … 100).
    var topTags: [String: [(name: String, count: Int)]] = [:]
    /// artist.search, by the name searched: the pages Last.fm has (as
    /// "Angele" has "Angèle", "Angele" and "Angéle"). A name not here is
    /// found as itself alone, as most are.
    var pages: [String: [(name: String, listeners: Int)]] = [:]
    /// By listener: their plays, any order. A listener named in
    /// `hiddenUsers` keeps them private.
    var scrobbles: [String: [LastFMClient.Scrobble]] = [:]
    var hiddenUsers: Set<String> = []
    /// What a listener plays now: the row user.getrecenttracks puts first,
    /// without a date.
    var nowPlaying: [String: (artist: String, title: String)] = [:]

    func answer(_ request: LastFMRequest) -> HTTPResponse {
        switch request.method {
        case "artist.search":
            return LastFMFixtures.respond(200, LastFMFixtures.search(request.artist, pages[request.artist] ?? [(request.artist, 1000)]))
        case "artist.gettoptags":
            guard let tags = topTags[request.artist] else { return LastFMFixtures.respond(200, LastFMFixtures.artistNotFound) }
            return LastFMFixtures.respond(200, LastFMFixtures.topTags(request.artist, tags))
        case "user.getrecenttracks":
            let user = request.query["user"] ?? ""
            if hiddenUsers.contains(user) { return LastFMFixtures.respond(200, LastFMFixtures.hiddenUser) }
            guard let plays = scrobbles[user] else { return LastFMFixtures.respond(200, LastFMFixtures.userNotFound) }
            let from = Double(request.query["from"] ?? "").map { Date(timeIntervalSince1970: $0) } ?? .distantPast
            let limit = Int(request.query["limit"] ?? "") ?? 50
            let page = Int(request.query["page"] ?? "") ?? 1
            let all = plays.filter { $0.date >= from }.sorted { $0.date > $1.date }
            let pages = max(1, (all.count + limit - 1) / limit)
            let these = Array(all.dropFirst((page - 1) * limit).prefix(limit))
            return LastFMFixtures.respond(200, LastFMFixtures.recentTracks(user, these, page: page, pages: pages,
                                                                           total: all.count, nowPlaying: page == 1 ? nowPlaying[user] : nil))
        case "artist.getsimilar":
            guard let similar = similarArtists[request.artist] else { return LastFMFixtures.respond(200, LastFMFixtures.artistNotFound) }
            return LastFMFixtures.respond(200, LastFMFixtures.similarArtists(request.artist, similar))
        case "track.getsimilar":
            guard let similar = similarTracks[request.artist + "|" + request.track] else {
                return LastFMFixtures.respond(200, LastFMFixtures.trackNotFound)
            }
            return LastFMFixtures.respond(200, LastFMFixtures.similarTracks(request.artist, similar))
        case "artist.gettoptracks":
            guard let titles = topTracks[request.artist] else { return LastFMFixtures.respond(200, LastFMFixtures.artistNotFound) }
            return LastFMFixtures.respond(200, LastFMFixtures.topTracks(request.artist, titles))
        default:
            return LastFMFixtures.respond(200, #"{"error":3,"message":"Invalid Method - No method with that name in this package"}"#)
        }
    }
}

enum LastFMFixtures {
    static func respond(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    /// JSON's string escaping, for names in the made-up answers.
    static func quoted(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// artist.getsimilar as Last.fm sends it: `match` a string, with an
    /// image list and "streamable" the app does not read.
    static func similarArtists(_ artist: String, _ similar: [(name: String, match: Double)]) -> String {
        let items = similar.map { s in
            """
            {"name":\(quoted(s.name)),"mbid":"","match":"\(s.match)","url":"https://www.last.fm/music/x",\
            "image":[{"#text":"https://lastfm.freetls.fastly.net/i/u/34s/x.png","size":"small"}],"streamable":"0"}
            """
        }
        return #"{"similarartists":{"artist":["# + items.joined(separator: ",") + #"],"@attr":{"artist":"# + quoted(artist) + "}}}"
    }

    /// track.getsimilar as Last.fm sends it: `match` and `playcount` numbers,
    /// the artist an object.
    static func similarTracks(_ artist: String, _ similar: [(artist: String, title: String, match: Double)]) -> String {
        let items = similar.map { s in
            """
            {"name":\(quoted(s.title)),"playcount":12345,"mbid":"","match":\(s.match),"url":"https://www.last.fm/music/x",\
            "streamable":{"#text":"0","fulltrack":"0"},"duration":245,\
            "artist":{"name":\(quoted(s.artist)),"mbid":"","url":"https://www.last.fm/music/x"},"image":[]}
            """
        }
        return #"{"similartracks":{"track":["# + items.joined(separator: ",") + #"],"@attr":{"artist":"# + quoted(artist) + "}}}"
    }

    /// artist.gettoptracks as Last.fm sends it: play counts, listeners and
    /// ranks as strings.
    static func topTracks(_ artist: String, _ titles: [String]) -> String {
        let items = titles.enumerated().map { k, title in
            """
            {"name":\(quoted(title)),"playcount":"\(100_000 - k * 1000)","listeners":"\(5000 - k * 10)","mbid":"",\
            "url":"https://www.last.fm/music/x","streamable":"0","artist":{"name":\(quoted(artist)),"mbid":"","url":""},\
            "image":[],"@attr":{"rank":"\(k + 1)"}}
            """
        }
        return #"{"toptracks":{"track":["# + items.joined(separator: ",") + #"],"@attr":{"artist":"# + quoted(artist)
            + #","page":"1","perPage":"50","totalPages":"1","total":""# + String(titles.count) + #""}}}"#
    }

    /// artist.search as Last.fm sends it: listeners as strings, beside
    /// "opensearch" counts the app does not read.
    static func search(_ artist: String, _ pages: [(name: String, listeners: Int)]) -> String {
        let items = pages.map { p in
            #"{"name":\#(quoted(p.name)),"listeners":"\#(p.listeners)","mbid":"","url":"https://www.last.fm/music/x","streamable":"0","image":[]}"#
        }
        return ##"{"results":{"opensearch:Query":{"#text":"","role":"request","searchTerms":"## + quoted(artist)
            + #","startPage":"1"},"opensearch:totalResults":""# + String(pages.count)
            + #"","artistmatches":{"artist":["# + items.joined(separator: ",") + #"]},"@attr":{"for":"# + quoted(artist) + "}}}"
    }

    /// artist.gettoptags in Last.fm's documented shape: `count` a number.
    static func topTags(_ artist: String, _ tags: [(name: String, count: Int)]) -> String {
        let items = tags.map { t in
            #"{"count":\#(t.count),"name":\#(quoted(t.name)),"url":"https://www.last.fm/tag/x"}"#
        }
        return #"{"toptags":{"tag":["# + items.joined(separator: ",") + #"],"@attr":{"artist":"# + quoted(artist) + "}}}"
    }

    /// user.getrecenttracks in Last.fm's documented shape: the artist and
    /// album as {"#text": …}, the date's `uts` a string, numbers in "@attr"
    /// strings, and the song playing now first, with no date.
    static func recentTracks(_ user: String, _ plays: [LastFMClient.Scrobble], page: Int, pages: Int, total: Int,
                             nowPlaying: (artist: String, title: String)? = nil) -> String {
        var items = plays.map { p in
            """
            {"artist":{"mbid":"","#text":\(quoted(p.artist))},"streamable":"0","image":[{"size":"small","#text":""}],\
            "mbid":"","album":{"mbid":"","#text":"An Album"},"name":\(quoted(p.title)),"url":"https://www.last.fm/music/x",\
            "date":{"uts":"\(Int(p.date.timeIntervalSince1970))","#text":"01 Nov 2026, 08:00"}}
            """
        }
        if let nowPlaying {
            items.insert("""
            {"artist":{"mbid":"","#text":\(quoted(nowPlaying.artist))},"streamable":"0","image":[],"mbid":"",\
            "album":{"mbid":"","#text":""},"name":\(quoted(nowPlaying.title)),"@attr":{"nowplaying":"true"},"url":""}
            """, at: 0)
        }
        return #"{"recenttracks":{"track":["# + items.joined(separator: ",") + #"],"@attr":{"user":"# + quoted(user)
            + #","totalPages":"\#(pages)","page":"\#(page)","perPage":"200","total":"\#(total)"}}}"#
    }

    static let userNotFound = #"{"error":6,"message":"User not found","links":[]}"#
    static let hiddenUser = #"{"error":17,"message":"Login: User required to be logged in","links":[]}"#

    // Straight from Last.fm.
    static let cherSimilar = #"""
    {"similarartists":{"artist":[{"name":"Sonny & Cher","mbid":"3d6e4b6d-2700-458c-9722-9021965a8164","match":"1",
    "url":"https://www.last.fm/music/Sonny+&+Cher","image":[{"#text":"https://lastfm.freetls.fastly.net/i/u/34s/2a96cbd8b46e442fc41c2b86b821562f.png","size":"small"},
    {"#text":"","size":"mega"}],"streamable":"0"},{"name":"Cyndi Lauper","mbid":"5e2cd1b1-7c9b-4c2b-9ba3-3a2b4d1f7d2c","match":"0.354226",
    "url":"https://www.last.fm/music/Cyndi+Lauper","image":[],"streamable":"0"},{"name":"Madonna","mbid":"79239441-bfd5-4981-a70c-55c3f15c1287",
    "match":"0.31","url":"https://www.last.fm/music/Madonna","image":[],"streamable":"0"}],"@attr":{"artist":"Cher"}}}
    """#
    static let radioheadSimilarTracks = #"""
    {"similartracks":{"track":[{"name":"Fake Plastic Trees","playcount":1180530,"mbid":"0f6a0ea6-fbd6-4bbb-92c0-cbbd7a0ff7d9","match":1,
    "url":"https://www.last.fm/music/Radiohead/_/Fake+Plastic+Trees","streamable":{"#text":"0","fulltrack":"0"},"duration":291,
    "artist":{"name":"Radiohead","mbid":"a74b1b7f-71a5-4011-9441-d0b5e4122711","url":"https://www.last.fm/music/Radiohead"},"image":[]},
    {"name":"Teardrop","playcount":980450,"match":0.873,"url":"https://www.last.fm/music/Massive+Attack/_/Teardrop",
    "streamable":{"#text":"0","fulltrack":"0"},"duration":330,"artist":{"name":"Massive Attack","mbid":"","url":""},"image":[]}],
    "@attr":{"artist":"Radiohead"}}}
    """#
    static let radioheadTopTracks = #"""
    {"toptracks":{"track":[{"name":"Creep","playcount":"10985723","listeners":"1868375","mbid":"","url":"https://www.last.fm/music/Radiohead/_/Creep",
    "streamable":"0","artist":{"name":"Radiohead","mbid":"a74b1b7f-71a5-4011-9441-d0b5e4122711","url":"https://www.last.fm/music/Radiohead"},
    "image":[],"@attr":{"rank":"1"}},{"name":"Karma Police","playcount":"9411830","listeners":"1505127","mbid":"",
    "url":"https://www.last.fm/music/Radiohead/_/Karma+Police","streamable":"0","artist":{"name":"Radiohead","mbid":"","url":""},
    "image":[],"@attr":{"rank":"2"}}],"@attr":{"artist":"Radiohead","page":"1","perPage":"2","totalPages":"500","total":"1000"}}}
    """#
    static let invalidKey = #"{"error":10,"message":"Invalid API key - You must be granted a valid key by last.fm","links":[]}"#
    static let suspendedKey = #"{"error":26,"message":"Suspended API key - Access for your account has been suspended, please contact Last.fm","links":[]}"#
    static let rateLimited = #"{"error":29,"message":"Rate Limit Exceded - Your IP has made too many requests in a short period","links":[]}"#
    static let artistNotFound = #"{"error":6,"message":"The artist you supplied could not be found","links":[]}"#
    static let trackNotFound = #"{"error":6,"message":"Track not found","links":[]}"#
    static let operationFailed = #"{"error":8,"message":"Operation failed - Most likely the backend service failed. Please try again.","links":[]}"#

    /// A directory of its own for one test, removed after it.
    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("jukebox-lastfm-\(UUID().uuidString)", isDirectory: true)
    }
}
