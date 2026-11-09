// What a Subsonic server answers, for SubsonicClient's tests without a
// server: the answers are Navidrome 0.64.2's (the test server of
// dev/navidrome-test-server.sh, 9 November 2026, curl), trimmed to the
// fields the kit reads and a few it must step over; and SubsonicFake, a
// transport that answers by endpoint and keeps every request, GET or form
// POST, to look at afterwards.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit

enum SubsonicFixtures {
    static let server = URL(string: "http://nas.local:4533")!
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.0", deviceName: "Test",
                                         deviceID: "test-device")
    /// md5("test" + salt), as `md5sum` makes it.
    static let salt = "9f2c4a7e1b3d5f60"
    static let token = "63ef78a356b325ab6ec990c18db9b303"

    /// Navidrome 0.64.2's getOpenSubsonicExtensions, without credentials.
    static let navidromeExtensions: Set<String> = ["transcodeOffset", "formPost", "songLyrics", "indexBasedQueue",
                                                   "transcoding", "playbackReport", "topSongsByArtistId"]
    static let navidromeCapabilities = SubsonicConnection.capabilities(
        apiVersion: "1.16.1", openSubsonic: true, extensions: navidromeExtensions)
        .subtracting(ServerCapability.signingInOnly)

    static func credentials(capabilities: Set<ServerCapability> = navidromeCapabilities,
                            secret: ServerSecret = .subsonicToken(token: token, salt: salt),
                            apiVersion: String? = "1.16.1", url: URL = server) -> ServerCredentials {
        ServerCredentials(kind: .subsonic(flavour: .navidrome), serverURL: url, serverID: url.absoluteString,
                          serverName: url.host ?? "", serverVersion: "0.64.2 (10114574)", apiVersion: apiVersion,
                          userID: "test", userName: "test", secret: secret, capabilities: capabilities)
    }

    static func client(_ fake: SubsonicFake, capabilities: Set<ServerCapability> = navidromeCapabilities,
                       secret: ServerSecret = .subsonicToken(token: token, salt: salt)) -> SubsonicClient {
        SubsonicClient(credentials: credentials(capabilities: capabilities, secret: secret), identity: identity,
                       transport: fake)
    }

    static func detected(capabilities: Set<ServerCapability> = SubsonicConnection.capabilities(
        apiVersion: "1.16.1", openSubsonic: true, extensions: navidromeExtensions),
                         apiVersion: String? = "1.16.1", url: URL = server) -> DetectedServer {
        DetectedServer(kind: .subsonic(flavour: .navidrome), url: url, id: url.absoluteString,
                       name: url.host ?? "", version: "0.64.2 (10114574)", apiVersion: apiVersion,
                       capabilities: capabilities)
    }

    // MARK: The envelope

    static let head = #""status":"ok","version":"1.16.1","type":"navidrome","serverVersion":"0.64.2 (10114574)","openSubsonic":true"#

    /// `{"subsonic-response": {"status": "ok", …, <inner>}}`.
    static func ok(_ inner: String = "") -> String {
        #"{"subsonic-response":{"# + head + (inner.isEmpty ? "" : "," + inner) + "}}"
    }

    static func failed(_ code: Int, _ message: String) -> String {
        #"{"subsonic-response":{"status":"failed","version":"1.16.1","type":"navidrome","serverVersion":"0.64.2 (10114574)","openSubsonic":true,"error":{"code":\#(code),"message":"\#(message)"}}}"#
    }

    // MARK: Songs, albums, artists (Navidrome 0.64.2)

    /// "Blue Parade" on Iron Gardens, starred and played once: a guest in
    /// `artists`, the joined tag in `artist`, two genres split by the server.
    static let blueParadeIronGardens = #"""
    {"id":"7ljPKGNMSwb9xQJ9R6sgwi","parent":"0XtEsASSFBpRROqxktaHgP","isDir":false,"title":"Blue Parade",
     "album":"Iron Gardens","artist":"MC Polder; Lyric Engine","track":1,"year":2016,"genre":"Hip-Hop",
     "coverArt":"dc-0XtEsASSFBpRROqxktaHgP:1","size":97105,"contentType":"audio/mp4","suffix":"m4a","starred":"2026-11-09T17:54:32.576944837Z",
     "duration":6,"bitRate":126,"path":"MC Polder/Iron Gardens/01-01 - Blue Parade.m4a","playCount":1,"played":"2026-11-09T17:54:32Z",
     "discNumber":1,"created":"2026-11-09T17:49:48.147925471Z","albumId":"0XtEsASSFBpRROqxktaHgP",
     "artistId":"3hzlW4nytpm0ULiXdnIWFQ","type":"music","bpm":0,"comment":"","sortName":"blue parade","mediaType":"song",
     "musicBrainzId":"","isrc":[],"genres":[{"name":"Hip-Hop"},{"name":"Nederhop"}],"replayGain":{},"channelCount":1,
     "samplingRate":44100,"bitDepth":16,"moods":[],
     "artists":[{"id":"3hzlW4nytpm0ULiXdnIWFQ","name":"MC Polder"},{"id":"0uE2mIyabW57P8LI7VBB3J","name":"Lyric Engine"}],
     "displayArtist":"MC Polder; Lyric Engine",
     "albumArtists":[{"id":"3hzlW4nytpm0ULiXdnIWFQ","name":"MC Polder"}],"displayAlbumArtist":"MC Polder",
     "contributors":[],"displayComposer":"","explicitStatus":"","groupings":[],"works":[],"movements":[]}
    """#

    /// Another "Blue Parade": a FLAC never played, by two credited artists.
    static let blueParadeSignalLines = #"""
    {"id":"3UKyssVkQiwv7s5xWWfOH4","parent":"04Sf2tysz0iPZar28fjinH","isDir":false,"title":"Blue Parade",
     "album":"Signal Lines","artist":"Amsterdam Strings; Clara Venn","track":7,"year":1991,"genre":"Classical",
     "coverArt":"dc-04Sf2tysz0iPZar28fjinH:1","size":68879,"contentType":"audio/flac","suffix":"flac","duration":5,
     "bitRate":97,"discNumber":1,"created":"2026-11-09T17:49:46.460908914Z","albumId":"04Sf2tysz0iPZar28fjinH",
     "artistId":"6TSk0okaabdPif8GKRXLq1","type":"music","mediaType":"song","genres":[{"name":"Classical"}],
     "replayGain":{},
     "artists":[{"id":"6TSk0okaabdPif8GKRXLq1","name":"Amsterdam Strings"},{"id":"0NzJ5KVkx5GcIzVIZdYLnP","name":"Clara Venn"}],
     "albumArtists":[{"id":"6TSk0okaabdPif8GKRXLq1","name":"Amsterdam Strings"}]}
    """#

    /// getAlbum's Iron Gardens, without its songs.
    static let ironGardens = #"""
    {"id":"0XtEsASSFBpRROqxktaHgP","name":"Iron Gardens","artist":"MC Polder","artistId":"3hzlW4nytpm0ULiXdnIWFQ",
     "coverArt":"al-0XtEsASSFBpRROqxktaHgP_2d7f387fbb87b3d2","songCount":8,"duration":53,"playCount":1,
     "created":"2026-11-08T01:26:02.28830931Z","year":2016,"genre":"Hip-Hop","played":"2026-11-09T17:54:32Z","userRating":0,
     "genres":[{"name":"Hip-Hop"},{"name":"Nederhop"}],"musicBrainzId":"","isCompilation":false,"sortName":"iron gardens",
     "discTitles":[],"originalReleaseDate":{},"releaseDate":{"year":2016},"releaseTypes":[],"recordLabels":[],"moods":[],
     "artists":[{"id":"3hzlW4nytpm0ULiXdnIWFQ","name":"MC Polder"}],"displayArtist":"MC Polder","explicitStatus":"","version":""}
    """#

    /// getArtists' first index, and MC Polder as getArtist gives it.
    static let artistIndexes = #"""
    "artists":{"ignoredArticles":"The El La Los Las Le Les Os As O A","index":[
     {"name":"A","artist":[{"id":"6TSk0okaabdPif8GKRXLq1","name":"Amsterdam Strings","albumCount":3,"musicBrainzId":"",
       "sortName":"amsterdam strings","roles":["albumartist","artist","maincredit"]}]},
     {"name":"M","artist":[{"id":"3hzlW4nytpm0ULiXdnIWFQ","name":"MC Polder","albumCount":3,"starred":"2026-11-09T18:00:00Z",
       "roles":["artist","maincredit","albumartist"]},
       {"id":"guest","name":"Guest Only","albumCount":0,"roles":["artist"]}]}]}
    """#

    /// createPlaylist's answer for "Fixture": A B A.
    static let playlistHead = #""id":"49jbXaAzpdP4nsvwSAwyor","name":"Fixture","songCount":3,"duration":18,"owner":"test","created":"2026-11-09T17:54:57.096571676Z","changed":"2026-11-09T17:54:57.097169217Z","coverArt":"pl-49jbXaAzpdP4nsvwSAwyor","readonly":false"#

    static let extensions = #""openSubsonicExtensions":[{"name":"transcodeOffset","versions":[1]},{"name":"formPost","versions":[1]},{"name":"songLyrics","versions":[1,2]},{"name":"indexBasedQueue","versions":[1]},{"name":"transcoding","versions":[1]},{"name":"playbackReport","versions":[1]},{"name":"topSongsByArtistId","versions":[1]}]"#

    static let user = #""user":{"username":"test","scrobblingEnabled":true,"adminRole":true,"settingsRole":false,"downloadRole":true,"uploadRole":false,"playlistRole":false,"coverArtRole":true,"commentRole":false,"podcastRole":false,"streamRole":true,"jukeboxRole":false,"shareRole":true,"videoConversionRole":false,"folder":[1]}"#

    /// A song for the tests of lists and orders: only what they read.
    static func song(_ id: String, album: String = "al", track: Int? = nil, disc: Int? = nil,
                     albumArtist: Bool = true) -> String {
        var fields = [#""id":"\#(id)""#, #""title":"Song \#(id)""#, #""albumId":"\#(album)""#, #""album":"Album \#(album)""#,
                      #""artist":"Artist""#, #""artistId":"ar1""#, #""duration":5"#]
        if let track { fields.append(#""track":\#(track)"#) }
        if let disc { fields.append(#""discNumber":\#(disc)"#) }
        if albumArtist { fields.append(#""albumArtists":[{"id":"ar1","name":"Artist"}]"#) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func album(_ id: String, songs: Int, artist: String = "Artist") -> String {
        #"{"id":"\#(id)","name":"Album \#(id)","artist":"\#(artist)","artistId":"ar-\#(artist)","songCount":\#(songs)}"#
    }
}

/// A transport that answers for a Subsonic server by endpoint ("ping",
/// "getAlbum"…), and keeps every request with its parameters, read from the
/// URL or, for a form POST, from the body. An endpoint nobody answers is
/// HTTP 404 with no body, as Navidrome answers one it does not have.
final class SubsonicFake: HTTPTransport, @unchecked Sendable {
    struct Request: Sendable {
        var endpoint: String
        var method: String
        var url: URL
        var params: [Param]
        var body: String?

        func value(_ name: String) -> String? { params.first { $0.name == name }?.value }
        func values(_ name: String) -> [String] { params.filter { $0.name == name }.map(\.value) }
    }

    struct Param: Sendable, Hashable {
        var name: String
        var value: String
    }

    typealias Route = @Sendable (Request) throws -> HTTPResponse

    private let lock = NSLock()
    private var routes: [String: Route] = [:]
    private var sent: [Request] = []

    init() {}

    /// Answers `endpoint` with whatever `route` makes of the request.
    func on(_ endpoint: String, _ route: @escaping Route) {
        lock.withLock { routes[endpoint] = route }
    }

    /// Answers `endpoint` with this body, HTTP 200.
    func on(_ endpoint: String, body: String, status: Int = 200) {
        on(endpoint) { _ in HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8)) }
    }

    /// Answers `endpoint` "ok" with `inner` in the envelope.
    func on(_ endpoint: String, ok inner: String = "") {
        on(endpoint, body: SubsonicFixtures.ok(inner))
    }

    var requests: [Request] { lock.withLock { sent } }

    func requests(_ endpoint: String) -> [Request] { requests.filter { $0.endpoint == endpoint } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let parsed = Self.parse(request)
        let route = lock.withLock {
            sent.append(parsed)
            return routes[parsed.endpoint]
        }
        guard let route else { return HTTPResponse(status: 404, body: Data()) }
        return try route(parsed)
    }

    static func parse(_ request: URLRequest) -> Request {
        let url = request.url!
        var name = url.lastPathComponent
        if name.hasSuffix(".view") { name.removeLast(5) }
        var params = Self.params(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery)
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
        if let body { params += Self.params(body) }
        return Request(endpoint: name, method: request.httpMethod ?? "GET", url: url, params: params, body: body)
    }

    static func params(_ encoded: String?) -> [Param] {
        guard let encoded, !encoded.isEmpty else { return [] }
        var components = URLComponents()
        components.percentEncodedQuery = encoded
        return (components.queryItems ?? []).map { Param(name: $0.name, value: $0.value ?? "") }
    }
}

/// The calls a progress closure got, in order.
final class SubsonicProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(Int, Int)] = []

    func add(_ done: Int, _ total: Int) { lock.withLock { calls.append((done, total)) } }
    var values: [(Int, Int)] { lock.withLock { calls } }
}

extension HTTPResponse {
    /// A JSON answer, HTTP 200 unless said: every Subsonic answer, errors
    /// included (measured on Navidrome).
    static func json(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}

/// The query of a URL the kit made, as name → values.
func subsonicQuery(_ url: URL) -> [String: [String]] {
    var result: [String: [String]] = [:]
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
        result[item.name, default: []].append(item.value ?? "")
    }
    return result
}
