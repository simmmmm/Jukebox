// How Jukebox talks to a Subsonic server (docs/SERVERS.md, "Talking
// Subsonic"): every request is `GET {base}/rest/{endpoint}.view` with the
// credentials, `v`, `c` and `f=json` in the query, and every answer is
// `{"subsonic-response": {status, version, …, error?}}`, HTTP 200 even for
// an error. The public calls (SubsonicClient.swift), the sign-in
// (SubsonicSignIn.swift) and the detection (Server/ServerAddress.swift) are
// built from this one connection.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SubsonicConnection: Sendable {
    /// The newest API version Jukebox speaks: what Navidrome 0.64.2 says
    /// it is (measured), OpenSubsonic's base.
    static let newestAPIVersion = "1.16.1"

    let baseURL: URL
    /// u/t/s, apiKey, or u/p; empty for the questions asked before signing
    /// in (ping and getOpenSubsonicExtensions answer without).
    let auth: [URLQueryItem]
    /// `v`: the lower of the server's version and ours. A server answers a
    /// newer `v` than it knows with error 30.
    let apiVersion: String
    /// `c`: who asks; Navidrome shows it as the player's name.
    let clientName: String
    let transport: any HTTPTransport

    init(baseURL: URL, auth: [URLQueryItem] = [], serverAPIVersion: String? = nil,
         clientName: String, transport: any HTTPTransport) {
        self.baseURL = baseURL
        self.auth = auth
        self.apiVersion = Self.lower(serverAPIVersion, Self.newestAPIVersion)
        self.clientName = clientName.isEmpty ? "Jukebox" : clientName
        self.transport = transport
    }

    /// The same server and client with other credentials.
    func with(auth: [URLQueryItem], serverAPIVersion: String? = nil) -> SubsonicConnection {
        SubsonicConnection(baseURL: baseURL, auth: auth, serverAPIVersion: serverAPIVersion ?? apiVersion,
                           clientName: clientName, transport: transport)
    }

    // MARK: Credentials

    /// What goes in every query for a secret. A Jellyfin token is nothing
    /// here: the calls then fail as not signed in.
    static func auth(_ secret: ServerSecret, user: String) -> [URLQueryItem] {
        switch secret {
        case let .subsonicToken(token, salt):
            [URLQueryItem(name: "u", value: user), URLQueryItem(name: "t", value: token),
             URLQueryItem(name: "s", value: salt)]
        case let .subsonicAPIKey(key):
            // Not `u` with a key: the spec makes that error 43.
            [URLQueryItem(name: "apiKey", value: key)]
        case let .subsonicPassword(password):
            // "enc:" and hex, the API's own way, so no character of the
            // password needs escaping (it is no secret from anyone who
            // sees the URL either way: why this is https or home only).
            [URLQueryItem(name: "u", value: user),
             URLQueryItem(name: "p", value: "enc:" + hex(Array(password.utf8)))]
        case .jellyfinToken:
            []
        }
    }

    /// A fresh salt: 16 random hex digits, made once per sign-in.
    static func makeSalt() -> String {
        let digits = String(UInt64.random(in: .min ... .max), radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }

    static func token(password: String, salt: String) -> String {
        MD5.hex(password + salt)
    }

    // MARK: URLs

    /// `{base}/rest/{endpoint}.view?{query}&{credentials}&v=&c=&f=json`,
    /// escaped as JellyfinClient escapes (only A–Z a–z 0–9 - . _ ~ stay).
    /// The same query gives the same URL, always: the image cache is keyed
    /// by it.
    func url(_ endpoint: String, _ query: [URLQueryItem] = []) -> URL {
        var string = baseURL.absoluteString
        if let cut = string.firstIndex(where: { $0 == "?" || $0 == "#" }) { string = String(string[..<cut]) }
        while string.hasSuffix("/") { string.removeLast() }
        string += "/rest/\(endpoint).view"
        let all = query + auth + [URLQueryItem(name: "v", value: apiVersion),
                                  URLQueryItem(name: "c", value: clientName),
                                  URLQueryItem(name: "f", value: "json")]
        string += "?" + all.map { "\(JellyfinClient.escape($0.name))=\(JellyfinClient.escape($0.value ?? ""))" }
            .joined(separator: "&")
        return URL(string: string) ?? baseURL
    }

    // MARK: Sending

    /// The answer, which must be "ok": an error in it is thrown as
    /// MusicServerError (`error(_:)`). `capability` is what a missing
    /// endpoint (HTTP 404) means the server lacks.
    func call(_ endpoint: String, _ query: [URLQueryItem] = [], timeout: TimeInterval = 30,
              lacking capability: ServerCapability? = nil) async throws -> SubsonicBody {
        let body = try await answer(endpoint, query, timeout: timeout, lacking: capability)
        guard body.isOK else { throw Self.error(body.error) }
        return body
    }

    /// The answer whatever its status: for the ping, where a failed status
    /// still says who answered and why.
    func answer(_ endpoint: String, _ query: [URLQueryItem] = [], timeout: TimeInterval = 30,
                lacking capability: ServerCapability? = nil) async throws -> SubsonicBody {
        var request = URLRequest(url: url(endpoint, query))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await Self.send(request, transport: transport)
        switch response.status {
        case 200..<300: break
        case 401: throw MusicServerError.unauthorized
        case 403: throw MusicServerError.notAllowed
        // No such endpoint: Navidrome answers getSonicSimilarTracks and
        // tokenInfo with 404 and "404 page not found" (measured).
        case 404, 501: throw MusicServerError.unsupported(capability)
        default:
            throw MusicServerError.server(status: response.status,
                                          message: JellyfinClient.message(from: response.body))
        }
        return try Self.decode(response.body)
    }

    /// The transport's errors as MusicServerError; cancellation stays
    /// cancellation.
    static func send(_ request: URLRequest, transport: any HTTPTransport) async throws -> HTTPResponse {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let JellyfinError.transport(message) {
            throw MusicServerError.transport(message)
        } catch let error as MusicServerError {
            throw error
        } catch {
            throw MusicServerError.transport(error.localizedDescription)
        }
    }

    static func decode(_ data: Data) throws -> SubsonicBody {
        do {
            return try JSONDecoder().decode(SubsonicEnvelope.self, from: data).body
        } catch {
            if isXMLAnswer(data) { throw MusicServerError.server(status: 30, message: tooOld) }
            throw MusicServerError.decoding("not a Subsonic answer")
        }
    }

    /// `<subsonic-response …>`: a Subsonic server that does not speak JSON
    /// (before API 1.4.0), or one asked without `f=json`.
    static func isXMLAnswer(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(512), as: UTF8.self)
        return head.contains("<subsonic-response")
    }

    static let tooOld = "This server is too old for Jukebox."

    // MARK: Errors

    /// Subsonic's error codes as the app tells them apart (docs/SERVERS.md,
    /// "Errors"). 41 and 42 (tokens, or this way of signing in, not
    /// supported) matter only when signing in, which reads the code itself.
    static func error(_ error: SubsonicErrorDTO?) -> MusicServerError {
        let code = error?.code ?? 0
        let message = error?.message.flatMap { $0.isEmpty ? nil : $0 }
        switch code {
        case 20: return .server(status: 20, message: "This server is newer than Jukebox can talk to.")
        case 30: return .server(status: 30, message: tooOld)
        case 40, 44: return .unauthorized
        case 50: return .notAllowed
        case 70: return .notFound
        default: return .server(status: code, message: message)
        }
    }

    // MARK: Versions

    /// The lower of two versions ("1.15.0" < "1.16.1"); nil or nonsense
    /// counts as ours.
    static func lower(_ a: String?, _ b: String) -> String {
        guard let a, !numbers(a).isEmpty else { return b }
        return compare(a, b) == .orderedAscending ? a : b
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = numbers(a), y = numbers(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// "1.16.1" → [1, 16, 1]; "0.64.2 (10114574)" → [0, 64, 2].
    static func numbers(_ version: String) -> [Int] {
        let head = version.split(separator: " ").first.map(String.init) ?? ""
        return head.split(separator: ".").compactMap { Int($0.prefix(while: \.isNumber)) }
    }

    static func atLeast(_ version: String?, _ minimum: String) -> Bool {
        guard let version, !numbers(version).isEmpty else { return false }
        return compare(version, minimum) != .orderedAscending
    }

    // MARK: Capabilities

    /// What a Subsonic server can do, from its API version and what
    /// getOpenSubsonicExtensions lists (docs/SERVERS.md, "Capabilities").
    /// Never from the flavour: a Gonic that grows lyrics gets lyrics.
    static func capabilities(apiVersion: String?, openSubsonic: Bool,
                             extensions: Set<String>) -> Set<ServerCapability> {
        var set: Set<ServerCapability> = [.lyrics]
        if extensions.contains("apiKeyAuthentication") { set.insert(.apiKeySignIn) }
        if atLeast(apiVersion, "1.11.0") { set.formUnion([.instantMix, .similarArtists]) }
        if atLeast(apiVersion, "1.13.0") { set.insert(.topSongs) }
        if atLeast(apiVersion, "1.14.0") { set.insert(.playlistReorder) }
        if extensions.contains("songLyrics") { set.insert(.syncedLyrics) }
        if openSubsonic { set.formUnion([.replayGain, .lastPlayed]) }
        if extensions.contains("playbackReport") { set.insert(.playbackTimeline) }
        if extensions.contains("transcodeOffset") { set.insert(.transcodeOffset) }
        return set
    }

    /// getOpenSubsonicExtensions' names; none when the server is not
    /// OpenSubsonic or the call fails (it is a nicety, not a need).
    func extensions() async -> Set<String> {
        guard let body = try? await call("getOpenSubsonicExtensions", timeout: 15) else { return [] }
        return Set(body.openSubsonicExtensions.compactMap(\.name))
    }

    // MARK: Lists of ids

    /// Ids per request when many go in the query: 100 of Navidrome's
    /// 22-character ids are 3 kB, inside the 8 kB a reverse proxy takes as
    /// a request line (nginx's default), as JellyfinClient's 100.
    static let idsPerRequest = 100

    static func chunks<T>(_ list: [T], of size: Int = idsPerRequest) -> [[T]] {
        stride(from: 0, to: list.count, by: size).map { Array(list[$0..<min($0 + size, list.count)]) }
    }
}
