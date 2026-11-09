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
    static let fallbackPorts = [JellyfinAddress.defaultPort] + subsonicPorts

    // MARK: The addresses to try

    /// The address as typed, normalized as JellyfinAddress does and with
    /// the web apps' own paths cut off (Jellyfin's "/web…" there, and here
    /// Navidrome's last segment "/app" and Gonic's "/admin…"); then, when
    /// no port and no "https://" were typed, the same host over http on
    /// 8096, 4533, 4747, 4040 and 5082: a fresh install listens on its own
    /// port only. Empty when it cannot be an address.
    static func candidates(_ typed: String) -> [URL] {
        guard var parts = JellyfinAddress.parse(typed) else { return [] }
        parts.path = serverPath(parts.path)
        if parts.typedScheme == nil, let port = parts.port, subsonicPorts.contains(port) { parts.scheme = "http" }
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

    /// Whether a password may go with every request to this address: over
    /// https, or to the home network — a private address (RFC 1918, the
    /// loopback, link-local, Tailscale's 100.64/10, IPv6's fc00::/7 and
    /// fe80::/10) or a home name ("nas", ".local", ".lan", …). Stricter than
    /// JellyfinAddress's guess at http, which takes any IP address: a
    /// public IP over plain http is not home.
    static func mayCarryPassword(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
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

    /// Every candidate at once, both ways at once; the first candidate in
    /// order that proved to be a server wins, a later one only once every
    /// earlier one has failed. So the address as typed wins whenever it
    /// works, and the fallback ports add no wait of their own: the longest
    /// wait is one 15 s timeout, not six. Nothing proved: the first
    /// candidate's error (`.transport` when nothing answered there,
    /// `.invalidServerAddress` when something did that is not a server).
    static func detect(_ typed: String, identity: ClientIdentity,
                       transport: any HTTPTransport) async throws -> DetectedServer {
        let candidates = candidates(typed)
        guard !candidates.isEmpty else { throw MusicServerError.invalidServerAddress }
        let outcome = await withTaskGroup(of: (Int, Result<DetectedServer, MusicServerError>).self) { group in
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
            return results[0] ?? .failure(.invalidServerAddress)
        }
        return try outcome.get()
    }

    /// One address, both ways at once.
    static func probe(_ url: URL, identity: ClientIdentity,
                      transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        async let jellyfin = probeJellyfin(url, identity: identity, transport: transport)
        async let subsonic = probeSubsonic(url, identity: identity, transport: transport)
        let j = await jellyfin
        if case .success = j { return j }
        let s = await subsonic
        if case .success = s { return s }
        // A Subsonic server that proved itself and cannot be used (it
        // speaks XML only) says so; else whether anything answered.
        if case .failure(.server(status: 30, _)) = s { return s }
        for result in [j, s] {
            if case let .failure(error) = result, !error.isTransport { return .failure(.invalidServerAddress) }
        }
        return j
    }

    /// /System/Info/Public with a non-empty Id, then /QuickConnect/Enabled.
    static func probeJellyfin(_ url: URL, identity: ClientIdentity,
                              transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        let client = JellyfinClient(serverURL: url, identity: identity, transport: transport)
        do {
            let info = try await client.publicInfo()
            var capabilities = JellyfinServer.capabilities(version: info.version)
            if await client.quickConnectEnabled() { capabilities.insert(.quickConnect) }
            return .success(DetectedServer(kind: .jellyfin, url: url, id: info.id, name: info.name,
                                           version: info.version, capabilities: capabilities))
        } catch let error as JellyfinError {
            return .failure(MusicServerError(error))
        } catch {
            return .failure(.transport(error.localizedDescription))
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
            return .failure(.transport(error.localizedDescription))
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

extension MusicServerError {
    var isTransport: Bool {
        if case .transport = self { return true }
        return false
    }
}
