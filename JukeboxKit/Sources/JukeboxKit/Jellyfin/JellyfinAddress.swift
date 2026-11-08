// What a person types as their server, made into a base URL
// (JellyfinClient.normalize). People type "music.example.com",
// "192.168.1.5:8096", "nas.local:8096", or paste the address bar of
// Jellyfin's web app ("https://jf.example.com/web/#/home.html"); all of them
// should simply work.
//
// The scheme, when none is typed: http for a name on the home network
// (an IP address, "localhost", a name without dots like "nas", or a home
// suffix like ".local" or ".fritz.box": no public certificate exists for
// those, and Jellyfin serves plain http there by default) and for port 8096
// (Jellyfin's http port; its https port is 8920). https for everything
// else, since a server on the internet should be behind TLS.
//
// Without a port, the address may well be missing the one Jellyfin listens
// on: JellyfinClient.candidateAddresses adds http at 8096 to try second
// (`candidates`, below, has the rule).

import Foundation

enum JellyfinAddress {
    /// Home-network suffixes no public certificate is issued for.
    static let homeSuffixes = [".local", ".lan", ".home", ".home.arpa", ".internal", ".localdomain", ".fritz.box"]

    /// Jellyfin's own http port.
    static let defaultPort = 8096

    /// What was typed, taken apart.
    struct Parts {
        /// "http" or "https" when typed, nil when not.
        var typedScheme: String?
        /// The scheme the address gets: the typed one, else the guess above.
        var scheme: String
        /// Lower case; an IPv6 address in brackets.
        var host: String
        var port: Int?
        /// "" or the path of a server behind a reverse proxy ("/jellyfin").
        var path: String

        func url(scheme: String, port: Int?) -> URL? {
            var string = "\(scheme)://\(host)"
            if let port { string += ":\(port)" }
            string += path
            return URL(string: string)
        }
    }

    static func normalize(_ input: String) -> URL? {
        guard let parts = parse(input) else { return nil }
        return parts.url(scheme: parts.scheme, port: parts.port)
    }

    /// The addresses to try, in order: the normalized one; then, when no
    /// port was typed, the same host on http at 8096. People type
    /// "192.168.1.10" or "nas.local" for a server that answers only on
    /// Jellyfin's own port (a fresh install listens on http 8096 and nowhere
    /// else), and the guess without it reaches nothing.
    ///
    /// Not when "https://" was typed: the person asked for TLS, and plain
    /// http would send their password in the clear to whoever answers on
    /// 8096. A typed "http://" (no TLS asked for) and no scheme at all (the
    /// https was this app's guess) get it. A typed port is the port: no
    /// second guess. The path stays: Jellyfin's own Base URL setting puts a
    /// server at "/jellyfin" on 8096 as well.
    static func candidates(_ input: String) -> [URL] {
        guard let parts = parse(input), let first = parts.url(scheme: parts.scheme, port: parts.port) else { return [] }
        guard parts.port == nil, parts.typedScheme != "https",
              let fallback = parts.url(scheme: "http", port: defaultPort), fallback != first else { return [first] }
        return [first, fallback]
    }

    static func parse(_ input: String) -> Parts? {
        var rest = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty,
              !rest.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
        else { return nil }

        var scheme: String?
        if let separator = rest.range(of: "://") {
            let typed = rest[..<separator.lowerBound].lowercased()
            guard typed == "http" || typed == "https" else { return nil }
            scheme = typed
            rest = String(rest[separator.upperBound...])
        }
        // The query and fragment are the web app's, never the server's.
        if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            rest = String(rest[..<cut])
        }

        let slash = rest.firstIndex(of: "/")
        let authority = slash.map { String(rest[..<$0]) } ?? rest
        var path = slash.map { String(rest[$0...]) } ?? ""
        // No user:password@ in a server address.
        guard !authority.isEmpty, !authority.contains("@") else { return nil }

        guard let (host, port, isIP) = hostAndPort(authority) else { return nil }

        guard path.unicodeScalars.allSatisfy({ pathAllowed.contains($0) }) else { return nil }
        path = serverPath(path)

        let chosen = scheme ?? (isHomeNetwork(host: host, isIP: isIP) || port == defaultPort ? "http" : "https")
        return Parts(typedScheme: scheme, scheme: chosen, host: host, port: port, path: path)
    }

    /// The host (lower case; an IPv6 address in brackets), the port, and
    /// whether the host is an IP address. Nil when either is not valid.
    static func hostAndPort(_ authority: String) -> (String, Int?, Bool)? {
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            let inner = authority[authority.index(after: authority.startIndex)..<close]
            guard inner.contains(":"),
                  inner.unicodeScalars.allSatisfy({ ipv6Allowed.contains($0) }) else { return nil }
            let after = authority[authority.index(after: close)...]
            var port: Int?
            if !after.isEmpty {
                guard after.hasPrefix(":"), let p = validPort(after.dropFirst()) else { return nil }
                port = p
            }
            return ("[\(inner.lowercased())]", port, true)
        }

        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        var host = parts[0].lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        var port: Int?
        if parts.count == 2 {
            guard let p = validPort(parts[1]) else { return nil }
            port = p
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !host.isEmpty, host.count <= 253, labels.allSatisfy(validLabel) else { return nil }
        // All digits: it must be an IPv4 address ("1.2.3.4"), not "1.2.3".
        if labels.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) {
            guard labels.count == 4, labels.allSatisfy({ (Int($0) ?? 256) <= 255 }) else { return nil }
            return (host, port, true)
        }
        return (host, port, false)
    }

    static func validPort(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.count <= 5, text.allSatisfy(\.isASCIIDigit),
              let port = Int(text), (1...65_535).contains(port) else { return nil }
        return port
    }

    static func validLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty, label.count <= 63,
              label.first != "-", label.last != "-" else { return false }
        return label.unicodeScalars.allSatisfy { hostAllowed.contains($0) }
    }

    static func isHomeNetwork(host: String, isIP: Bool) -> Bool {
        if isIP || host == "localhost" || !host.contains(".") { return true }
        return homeSuffixes.contains { host.hasSuffix($0) }
    }

    /// The path of a server behind a reverse proxy ("/jellyfin"), without
    /// the web app's part ("/web/index.html") and the trailing slash.
    static func serverPath(_ path: String) -> String {
        var path = path
        var from = path.startIndex
        while let web = path.range(of: "/web", options: .caseInsensitive, range: from..<path.endIndex) {
            let after = path[web.upperBound...]
            if after.isEmpty || after.hasPrefix("/") {
                path = String(path[..<web.lowerBound])
                break
            }
            // "/webdav", "/website": a folder of the proxy's, keep looking.
            from = web.upperBound
        }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static let hostAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
    static let ipv6Allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.%")
    /// RFC 3986 path characters, and % for what is already escaped.
    static let pathAllowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@/%")
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
