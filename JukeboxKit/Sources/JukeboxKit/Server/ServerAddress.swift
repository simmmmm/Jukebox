// Which server is at what a person typed (docs/SERVERS.md, "Which server
// is at an address"): the addresses to try, and asking each one both ways
// at once — Jellyfin's /System/Info/Public and Subsonic's /rest/ping.view —
// so the sign-in screen never asks "Jellyfin or Subsonic?".
//
// Measured across the two test servers: Jellyfin 12.4 answers
// /rest/ping.view with 404 and no body; Navidrome 0.64.2 answers
// /System/Info/Public with 302 to /app/ and then its web app's HTML. So
// each server answers only its own question, and if both ever did,
// Jellyfin wins (its API gives more).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ServerAddress {
    /// The default ports of plain http, besides Jellyfin's 8096 (which
    /// JellyfinAddress knows): Navidrome's 4533 (measured), Gonic's 4747,
    /// Airsonic's 4040 and LMS's 5082 (their documentation).
    static let subsonicPorts = [4533, 4747, 4040, 5082]
    /// Plex Media Server's own, plain http too.
    static let plexPort = 32400
    static let fallbackPorts = [JellyfinAddress.defaultPort] + subsonicPorts + [plexPort]

    // MARK: The addresses to try

    /// The address as typed, normalized as JellyfinAddress does and with
    /// the web apps' own paths cut off (Jellyfin's "/web…" there, and here
    /// Navidrome's last segment "/app" and Gonic's "/admin…"); then, when
    /// no port and no "https://" were typed, the same host over http on
    /// 8096, 4533, 4747, 4040, 5082 and 32400: a fresh install listens on its own
    /// port only. Empty when it cannot be an address.
    static func candidates(_ typed: String) -> [URL] {
        guard var parts = JellyfinAddress.parse(typed) else { return [] }
        parts.path = serverPath(parts.path)
        if parts.typedScheme == nil, let port = parts.port, subsonicPorts.contains(port) || port == plexPort { parts.scheme = "http" }
        guard let first = parts.url(scheme: parts.scheme, port: parts.port) else { return [] }
        var list = [first]
        // Not after a typed "https://": TLS was asked for, and plain http
        // would send the password in the clear. A typed port is the port.
        guard parts.port == nil, parts.typedScheme != "https" else { return list }
        for port in fallbackPorts {
            if let url = parts.url(scheme: "http", port: port), !list.contains(url) { list.append(url) }
        }
        return list
    }

    /// Navidrome's web app is at "/app" ("http://nas:4533/app/#/album/all",
    /// whose "#…" JellyfinAddress cuts off already): a last segment "/app"
    /// goes, only the last ("/app/music" is a reverse proxy's path). Gonic's
    /// pages are "/admin/…": "/admin" and what follows goes, as Jellyfin's
    /// "/web" does.
    static func serverPath(_ path: String) -> String {
        var path = path
        var from = path.startIndex
        while let admin = path.range(of: "/admin", options: .caseInsensitive, range: from..<path.endIndex) {
            let after = path[admin.upperBound...]
            if after.isEmpty || after.hasPrefix("/") {
                path = String(path[..<admin.lowerBound])
                break
            }
            // "/administration": a folder of the proxy's, keep looking.
            from = admin.upperBound
        }
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased().hasSuffix("/app") { path.removeLast(4) }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    // MARK: Where a password may go

    /// Plain http away from the home network: what "This Server Isn't
    /// Secure" asks about, and what an account's card says "Not secure" of.
    /// Plain http at home is no question: "als het binnen een thuisnetwerk
    /// blijft vind ik het wat anders […] maar daarbuiten wel" (the
    /// photographer, 23 November 2026).
    /// Home is an address of the home's shape on a network the device is
    /// on now (LocalNetwork): 192.168.1.10 typed in a café is asked about.
    /// May resolve a name, so not on the main thread.
    public static func isInsecure(_ url: URL, network: @autoclosure () -> LocalNetwork = .current) -> Bool {
        guard url.scheme?.lowercased() != "https" else { return false }
        guard isHomeNetwork(url), let host = url.host else { return true }
        return !network().reaches(host)
    }

    /// Plain http to an address not of the home's shape, wherever the
    /// device is: what an account's card says "Not secure" of. No lookup,
    /// so a view may ask.
    public static func isInsecureAnywhere(_ url: URL) -> Bool {
        url.scheme?.lowercased() != "https" && !isHomeNetwork(url)
    }

    /// The home network's shape: a private address (RFC 1918, the loopback,
    /// link-local, Tailscale's 100.64/10, IPv6's fc00::/7 and fe80::/10) or
    /// a home name ("nas", ".local", ".lan", …). Stricter than
    /// JellyfinAddress's guess at http, which takes any IP address: a
    /// public IP is not home. Whether the device is there now is
    /// LocalNetwork's (`isInsecure`).
    static func isHomeNetwork(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.contains(":") {
            return host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe8")
                || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb")
        }
        let octets = host.split(separator: ".").map { Int($0) }
        if octets.count == 4, octets.allSatisfy({ $0 != nil }) {
            let a = octets[0]!, b = octets[1]!
            return a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
                || (a == 169 && b == 254) || (a == 100 && (64...127).contains(b))
        }
        return JellyfinAddress.isHomeNetwork(host: host, isIP: false)
    }

    // MARK: Asking

    /// At home, every candidate at once, both ways at once; the first
    /// candidate in order that proved to be a server wins, a later one only
    /// once every earlier one has failed. So the address as typed wins
    /// whenever it works, and the fallback ports add no wait of their own:
    /// the longest wait is one 15 s timeout, not six. Nothing proved: the
    /// first candidate's error (`.transport` when nothing answered there,
    /// `.invalidServerAddress` when something did that is not a server).
    ///
    /// A name on the internet ("demo.navidrome.org") is asked alone first,
    /// its fallback ports only once it has failed. A public host drops a
    /// connection to a port it does not serve rather than refusing it
    /// (demo.navidrome.org's 8096, 4533 and 32400 time out, measured), so
    /// those eighteen requests hung for 15 s each beside the one that
    /// works. Hardening after App Review's five tries at the demo server on
    /// 22 November 2026 all ended in `unreachable`; that cause is not
    /// confirmed (the kit signs in there every way it can be typed, on
    /// Linux), and the counts now say which network error it was. The
    /// cost: a public name that answers nowhere waits 30 s, not 15.
    static func detect(_ typed: String, identity: ClientIdentity,
                       transport: any HTTPTransport) async throws -> DetectedServer {
        let candidates = candidates(typed)
        guard let first = candidates.first else { throw MusicServerError.invalidServerAddress }
        if candidates.count > 1, !isHomeNetwork(first) {
            let alone = await probe(first, identity: identity, transport: transport)
            if case .success = alone { return try alone.get() }
            let later = await firstServer(Array(candidates.dropFirst()), identity: identity, transport: transport)
            if case .success = later { return try later.get() }
            if case .failure(.movedElsewhere) = later { return try later.get() }
            return try alone.get()
        }
        return try await firstServer(candidates, identity: identity, transport: transport).get()
    }

    /// The first of `candidates` in order that proves to be a server, all
    /// asked at once; else the first one's error.
    static func firstServer(_ candidates: [URL], identity: ClientIdentity,
                            transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        await withTaskGroup(of: (Int, Result<DetectedServer, MusicServerError>).self) { group in
            for (i, url) in candidates.enumerated() {
                group.addTask { (i, await probe(url, identity: identity, transport: transport)) }
            }
            var results = [Result<DetectedServer, MusicServerError>?](repeating: nil, count: candidates.count)
            while case let (i, result)? = await group.next() {
                results[i] = result
                for earlier in results {
                    guard let earlier else { break }  // one before is still asking
                    if case .success = earlier {
                        group.cancelAll()
                        return earlier
                    }
                }
            }
            // A server that sent Jukebox elsewhere says so before "nothing
            // answered here".
            let moved = results.first { if case .failure(.movedElsewhere)? = $0 { true } else { false } }
            return moved.flatMap { $0 } ?? results.first.flatMap { $0 } ?? .failure(.invalidServerAddress)
        }
    }

    /// One address, both ways at once.
    /// The server keeps the address it answered at after a redirect
    /// (`Redirects`): typed "http://demo.navidrome.org", it is https from
    /// then on, so the password never goes the plain way first and
    /// Jellyfin's sign-in POST is not turned into a GET by a 301.
    static func probe(_ url: URL, identity: ClientIdentity,
                      transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        let redirects = Redirects(transport)
        let result = await probeAsked(url, identity: identity, transport: redirects)
        // Sent on to another host or port: that is another server, whatever
        // it says it is, and the password would follow it there with no
        // question asked of it. Not taken: it can be typed as itself.
        if case .success = result, let elsewhere = redirects.elsewhere(for: url) {
            let port = elsewhere.port.map { ":\($0)" } ?? ""
            return .failure(.movedElsewhere(host: (elsewhere.host ?? elsewhere.absoluteString) + port))
        }
        return result.map { found in
            guard let moved = redirects.base(for: url) else { return found }
            var found = found
            found.url = moved
            // A Subsonic server's id and name are its address and host.
            if found.id == url.absoluteString { found.id = moved.absoluteString }
            if found.name == url.host { found.name = moved.host ?? found.name }
            return found
        }
    }

    static func probeAsked(_ url: URL, identity: ClientIdentity,
                           transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        async let jellyfin = probeJellyfin(url, identity: identity, transport: transport)
        async let subsonic = probeSubsonic(url, identity: identity, transport: transport)
        async let plex = PlexSignIn.probe(url, identity: identity, transport: transport)
        let j = await jellyfin
        if case .success = j { return j }
        let p = await plex
        if case .success = p { return p }
        let s = await subsonic
        if case .success = s { return s }
        // A Subsonic server that proved itself and cannot be used (it
        // speaks XML only) says so; else whether anything answered.
        if case .failure(.server(status: 30, _)) = s { return s }
        for result in [j, s, p] {
            // Every answer a 401 or 403: something in front of the server
            // (a proxy's sign-in, a login page) turned Jukebox away, which
            // "no server at this address" would hide.
            if case let .failure(error) = result, !error.isTransport, let status = (transport as? Redirects)?.wall {
                return .failure(.server(status: status, message: nil))
            }
            if case let .failure(error) = result, !error.isTransport { return .failure(.invalidServerAddress) }
        }
        return j
    }

    /// /System/Info/Public with a non-empty Id, then /QuickConnect/Enabled.
    /// Emby answers the same question: Jellyfin names itself in ProductName
    /// ("Jellyfin Server"), Emby 4.10 names nothing there (measured), so
    /// without a ProductName /System/Ping decides ("Emby Server"). Emby has
    /// no Quick Connect (404).
    static func probeJellyfin(_ url: URL, identity: ClientIdentity,
                              transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        let client = JellyfinClient(serverURL: url, identity: identity, transport: transport)
        do {
            let info = try await client.publicInfo()
            let isEmby = if let product = info.productName { product.contains("Emby") } else { await client.pingSaysEmby() }
            let kind: ServerKind = isEmby ? .emby : .jellyfin
            var capabilities = JellyfinServer.capabilities(kind: kind, version: info.version)
            if await client.quickConnectEnabled() { capabilities.insert(.quickConnect) }
            return .success(DetectedServer(kind: kind, url: url, id: info.id, name: info.name,
                                           version: info.version, capabilities: capabilities))
        } catch let error as JellyfinError {
            return .failure(MusicServerError(error))
        } catch {
            return .failure(.transport(ConnectionProblem.describe(error)))
        }
    }

    /// An unauthenticated ping: any `subsonic-response` with a status is a
    /// Subsonic server, whatever the status. Navidrome answers
    /// `{"status":"failed","version":"1.16.1","type":"navidrome",
    /// "serverVersion":"0.64.2 (10114574)","openSubsonic":true,"error":{"code":10,
    /// "message":"missing parameter: 'u'"}}` (HTTP 200, measured); another
    /// may answer 40, or 30 (our `v` is newer than it knows: its `version`
    /// is what is sent from then on), or ok. Then, for OpenSubsonic,
    /// getOpenSubsonicExtensions, which answers without credentials (the
    /// spec; measured on Navidrome).
    static func probeSubsonic(_ url: URL, identity: ClientIdentity,
                              transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        let connection = SubsonicConnection(baseURL: url, clientName: identity.clientName, transport: transport)
        let body: SubsonicBody
        do {
            body = try await connection.answer("ping", timeout: 15)
        } catch let error as MusicServerError {
            if case .transport = error { return .failure(error) }
            if case .server(status: 30, _) = error { return .failure(error) }  // XML only: too old
            return .failure(.invalidServerAddress)
        } catch {
            return .failure(.transport(ConnectionProblem.describe(error)))
        }
        guard let status = body.status, !status.isEmpty else { return .failure(.invalidServerAddress) }
        let apiVersion = body.version.flatMap { SubsonicConnection.numbers($0).isEmpty ? nil : $0 }
        let openSubsonic = body.openSubsonic == true
        let extensions = openSubsonic
            ? await connection.with(auth: [], serverAPIVersion: apiVersion).extensions() : []
        let capabilities = SubsonicConnection.capabilities(apiVersion: apiVersion, openSubsonic: openSubsonic,
                                                           extensions: extensions)
        return .success(DetectedServer(kind: .subsonic(flavour: SubsonicFlavour(type: body.type)), url: url,
                                       id: url.absoluteString, name: url.host ?? url.absoluteString,
                                       version: body.serverVersion ?? apiVersion ?? "",
                                       apiVersion: apiVersion, capabilities: capabilities))
    }
}

/// The probes' transport, noting where each request ended up and what it
/// was answered: a base answered from another scheme, host or port
/// (http:// to https://, the same path after it) is the server's address
/// from then on; answers that were all 401 or 403 are a wall in front.
final class Redirects: HTTPTransport, @unchecked Sendable {
    let base: any HTTPTransport
    private let lock = NSLock()
    private var moved: [(asked: URL, answered: URL)] = []
    private var statuses: [Int] = []

    init(_ base: any HTTPTransport) { self.base = base }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let response = try await base.send(request)
        lock.withLock {
            statuses.append(response.status)
            if let asked = request.url, let answered = response.url, answered != asked { moved.append((asked, answered)) }
        }
        return response
    }

    /// 401 or 403 when every answer was one of those; else nil.
    var wall: Int? {
        let seen = lock.withLock { statuses }
        guard let first = seen.first, seen.allSatisfy({ $0 == 401 || $0 == 403 }) else { return nil }
        return first
    }

    /// The first place a request of `url`'s ended up that is not `url`'s
    /// own origin (RedirectPolicy.sameOrigin); nil when none did.
    func elsewhere(for url: URL) -> URL? {
        let prefix = url.absoluteString
        return lock.withLock { moved }.first { asked, answered in
            asked.absoluteString.hasPrefix(prefix) && !RedirectPolicy.sameOrigin(asked, answered)
        }?.answered
    }

    /// `url` at the scheme and port its requests were redirected to on its
    /// own origin (http to https), when one went there with its path
    /// unchanged; else nil. Another host or port is never taken as the
    /// server (`elsewhere`).
    func base(for url: URL) -> URL? {
        let prefix = url.absoluteString
        for (asked, answered) in lock.withLock({ moved }) where asked.absoluteString.hasPrefix(prefix) {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let from = URLComponents(url: asked, resolvingAgainstBaseURL: false),
                  let to = URLComponents(url: answered, resolvingAgainstBaseURL: false),
                  RedirectPolicy.sameOrigin(asked, answered), from.path == to.path, from.scheme != to.scheme || from.host != to.host || from.port != to.port
            else { continue }
            parts.scheme = to.scheme
            parts.host = to.host
            parts.port = to.port
            return parts.url
        }
        return nil
    }
}

extension MusicServerError {
    var isTransport: Bool {
        if case .transport = self { return true }
        return false
    }
}
