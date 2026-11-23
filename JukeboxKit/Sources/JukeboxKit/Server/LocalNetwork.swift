// Whether the device is on the network an address belongs to. "Home" is
// where plain http may carry a password or a token without a question
// ("als het binnen een thuisnetwerk blijft vind ik het wat anders", the
// photographer, 23 November 2026): that is about the network the device is
// on, not the address's shape. 192.168.1.10 is home only while one of the
// device's own interfaces is in 192.168.1.0/24, a name like "nas" only
// while it resolves to such an address. Tailscale's 100.64/10 (and its
// fd7a:115c:a1e0::/48) is shared with carrier-grade NAT, so it counts only
// while a Tailscale-like interface (tailscale0, a utun) carries an address
// in it; its own address is a /32, so a subnet would never match a peer.
// getifaddrs on both platforms: Foundation alone, as the kit is.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

public struct LocalNetwork: Sendable {
    public struct Interface: Sendable, Equatable {
        public var name: String
        /// 4 bytes for IPv4, 16 for IPv6.
        public var address: [UInt8]
        public var mask: [UInt8]

        public init(name: String, address: [UInt8], mask: [UInt8]) {
            self.name = name
            self.address = address
            self.mask = mask
        }
    }

    public var interfaces: [Interface]
    /// A name's addresses (getaddrinfo); a literal address is not resolved.
    public var resolve: @Sendable (String) -> [[UInt8]]

    public init(interfaces: [Interface], resolve: @escaping @Sendable (String) -> [[UInt8]] = { _ in [] }) {
        self.interfaces = interfaces
        self.resolve = resolve
    }

    /// The device's interfaces now, names resolved by the system; a test's
    /// own network while it runs with `$standIn` set.
    public static var current: LocalNetwork {
        standIn ?? LocalNetwork(interfaces: upInterfaces(), resolve: resolved)
    }

    @TaskLocal public static var standIn: LocalNetwork?

    /// Whether `host` (a name, an IPv4 address or an IPv6 one, brackets or
    /// not) is on one of the device's own networks: the loopback always;
    /// a name only when every address it resolves to is.
    public func reaches(_ host: String) -> Bool {
        var host = host.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if let zone = host.firstIndex(of: "%") { host = String(host[..<zone]) }
        if host == "localhost" { return true }
        if let bytes = Self.literal(host) { return reaches(bytes: bytes) }
        let addresses = resolve(host)
        return !addresses.isEmpty && addresses.allSatisfy(reaches(bytes:))
    }

    func reaches(bytes: [UInt8]) -> Bool {
        if bytes.count == 4, bytes[0] == 127 { return true }
        if bytes == [UInt8](repeating: 0, count: 15) + [1] { return true }
        if Self.isTailnet(bytes) {
            return interfaces.contains { Self.isTailscaleLike($0.name) && Self.isTailnet($0.address) }
        }
        return interfaces.contains { interface in
            interface.address.count == bytes.count && !interface.mask.allSatisfy({ $0 == 0 })
                && zip(zip(interface.address, interface.mask), bytes).allSatisfy { ($0.0 & $0.1) == ($1 & $0.1) }
        }
    }

    static func isTailnet(_ bytes: [UInt8]) -> Bool {
        if bytes.count == 4 { return bytes[0] == 100 && (64...127).contains(bytes[1]) }
        return bytes.count == 16 && bytes.prefix(6) == [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0]
    }

    static func isTailscaleLike(_ name: String) -> Bool {
        name.hasPrefix("tailscale") || name.hasPrefix("utun")
    }

    /// The bytes of a literal IPv4 or IPv6 address; nil for a name.
    static func literal(_ host: String) -> [UInt8]? {
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
        return nil
    }

    static func bytes(_ address: UnsafeMutablePointer<sockaddr>?) -> [UInt8]? {
        guard let address else { return nil }
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { v4 in
                withUnsafeBytes(of: v4.pointee.sin_addr) { Array($0) }
            }
        case AF_INET6:
            return address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { v6 in
                withUnsafeBytes(of: v6.pointee.sin6_addr) { Array($0) }
            }
        default:
            return nil
        }
    }

    static func upInterfaces() -> [Interface] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var found: [Interface] = []
        var next = first
        while let entry = next {
            next = entry.pointee.ifa_next
            guard (Int32(entry.pointee.ifa_flags) & Int32(IFF_UP)) != 0,
                  let address = bytes(entry.pointee.ifa_addr), let mask = bytes(entry.pointee.ifa_netmask),
                  address.count == mask.count else { continue }
            found.append(Interface(name: String(cString: entry.pointee.ifa_name), address: address, mask: mask))
        }
        return found
    }

    /// getaddrinfo, which may wait on DNS or mDNS: called off the main
    /// thread (the sign-in asks from a detached task, the transport from
    /// its own).
    static func resolved(_ name: String) -> [[UInt8]] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if canImport(Darwin)
        hints.ai_socktype = SOCK_STREAM
        #else
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #endif
        var first: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &first) == 0 else { return [] }
        defer { freeaddrinfo(first) }
        var found: [[UInt8]] = []
        var next = first
        while let entry = next {
            next = entry.pointee.ai_next
            if let address = bytes(entry.pointee.ai_addr), !found.contains(address) { found.append(address) }
        }
        return found
    }
}

/// What URLSessionTransport asks before every request: a credential over
/// plain http to an address of the home's shape goes only while the device
/// is on that network, or where someone said Sign In Anyway for it. So an
/// account signed in at home at http://192.168.1.10:8096 sends nothing to
/// whoever has that address on a café's Wi-Fi: it waits until home. A
/// request without credentials (detection's first questions) goes as it
/// is; sign-in asks "This Server Isn't Secure" there first (mustAsk).
enum PlainHTTPGuard {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: (home: Bool, at: Date)] = [:]

    /// Nil to send; else why not.
    static func refusal(_ request: URLRequest, consent: PlainHTTPConsent = PlainHTTPConsent()) -> String? {
        guard let url = request.url, url.scheme?.lowercased() == "http", let host = url.host?.lowercased(),
              ServerAddress.isHomeNetwork(url), carriesCredentials(request),
              !reaches(host), !consent.isAcceptedOrigin(url) else { return nil }
        return "This device isn't on the network of \(host) now, so Jukebox sends nothing there over plain http. Connect to that network, or sign in again."
    }

    /// Asked again after 30 s: a laptop moves between networks.
    /// ponytail: a cache by host, no network-change signal; one if 30 s is
    /// ever too slow.
    private static func reaches(_ host: String) -> Bool {
        let now = Date()
        if let seen = lock.withLock({ known[host] }), now.timeIntervalSince(seen.at) < 30 { return seen.home }
        let home = LocalNetwork.current.reaches(host)
        lock.withLock { known[host] = (home, now) }
        return home
    }

    static func carriesCredentials(_ request: URLRequest) -> Bool {
        if request.httpBody != nil || request.httpBodyStream != nil { return true }
        for header in ["Authorization", "X-Emby-Authorization"] {
            if request.value(forHTTPHeaderField: header)?.contains("Token=") == true { return true }
        }
        for header in ["X-Emby-Token", "X-Plex-Token", "X-MediaBrowser-Token"]
        where request.value(forHTTPHeaderField: header)?.isEmpty == false { return true }
        let names: Set<String> = ["t", "s", "p", "apikey", "api_key", "x-plex-token"]
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return items.contains { names.contains($0.name.lowercased()) && $0.value?.isEmpty == false }
    }
}
