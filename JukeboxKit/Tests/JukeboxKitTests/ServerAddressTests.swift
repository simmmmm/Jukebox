// Which server is at what a person typed (Server/ServerAddress.swift,
// docs/SERVERS.md "Which server is at an address"): the addresses to try,
// where a password may go, and detection — against a fake that answers as
// Jellyfin 12.4 and Navidrome 0.64.2 did, and against both real test
// servers when they run.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

/// Answers by host, port and path, after a delay if asked: several servers
/// at several addresses, as detection meets them.
final class AddressFake: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URL) async throws -> HTTPResponse
    private let handler: Handler
    private let lock = NSLock()
    private var sent: [URL] = []

    init(_ handler: @escaping Handler) { self.handler = handler }

    var requests: [URL] { lock.withLock { sent } }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url!
        lock.withLock { sent.append(url) }
        return try await handler(url)
    }

    /// "nas.local:4533" or "nas.local" for a URL.
    static func address(_ url: URL) -> String {
        (url.host ?? "") + (url.port.map { ":\($0)" } ?? "")
    }

    /// What Jellyfin 12.4 answers at these paths.
    static func jellyfin(_ url: URL) -> HTTPResponse {
        switch url.path {
        case "/System/Info/Public": .json(JellyfinFixtures.publicInfo)
        case "/QuickConnect/Enabled": .json("true")
        default: HTTPResponse(status: 404, body: Data())  // /rest/ping.view, measured
        }
    }

    /// What Navidrome 0.64.2 answers, without credentials.
    static func navidrome(_ url: URL) -> HTTPResponse {
        switch url.path {
        case "/rest/ping.view": .json(SubsonicFixtures.failed(10, "missing parameter: 'u'"))
        case "/rest/getOpenSubsonicExtensions.view": .json(SubsonicFixtures.ok(SubsonicFixtures.extensions))
        // /System/Info/Public: 302 to /app/, and then the web app's page.
        default: HTTPResponse(status: 200, headers: ["Content-Type": "text/html"],
                              body: Data("<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\" />".utf8))
        }
    }

    static func refused() throws -> HTTPResponse { throw URLError(.cannotConnectToHost) }
}

@Suite("Servers: which server is at an address")
struct ServerAddressTests {
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.0", deviceName: "Test",
                                         deviceID: "test-device")

    static func ports(_ base: String, path: String = "") -> [String] {
        [8096, 4533, 4747, 4040, 5082].map { "http://\(base):\($0)\(path)" }
    }

    @Test("The addresses to try, for what people type", arguments: [
        ("nas.local", ["http://nas.local"] + ServerAddressTests.ports("nas.local")),
        ("music.example.com", ["https://music.example.com"] + ServerAddressTests.ports("music.example.com")),
        ("http://nas.local/jellyfin", ["http://nas.local/jellyfin"] + ServerAddressTests.ports("nas.local", path: "/jellyfin")),
        ("https://music.example.com", ["https://music.example.com"]),
        // Navidrome's web app as it is in the address bar.
        ("http://nas:4533/app/#/album/all", ["http://nas:4533"]),
        ("nas.local:4533/app", ["http://nas.local:4533"]),
        ("https://example.com/navidrome/app/", ["https://example.com/navidrome"]),
        // A reverse proxy's path that begins with "app" stays.
        ("https://example.com/app/music", ["https://example.com/app/music"]),
        ("https://example.com/APP", ["https://example.com"]),
        // Navidrome's, Gonic's, Airsonic's and LMS's own ports mean http.
        ("music.example.com:4533", ["http://music.example.com:4533"]),
        ("music.example.com:4040", ["http://music.example.com:4040"]),
        ("music.example.com:9000", ["https://music.example.com:9000"]),
        // Gonic's pages.
        ("192.168.1.5:4747/admin/home", ["http://192.168.1.5:4747"]),
        ("https://example.com/gonic/admin", ["https://example.com/gonic"]),
        ("https://example.com/administration", ["https://example.com/administration"]),
        ("https://example.com/administration/gonic/admin/", ["https://example.com/administration/gonic"]),
        // Jellyfin's web app, as before.
        ("https://jf.example.com/web/#/home.html", ["https://jf.example.com"]),
        ("192.168.1.10:8096", ["http://192.168.1.10:8096"]),
        ("", []),
        ("not an address", []),
        ("ftp://nas.local", []),
    ])
    func candidates(typed: String, expected: [String]) {
        #expect(MusicServers.candidateAddresses(for: typed).map(\.absoluteString) == expected)
    }

    @Test("A password may go with every request over https, or on the home network only", arguments: [
        ("https://music.example.com", true), ("https://203.0.113.9", true),
        ("http://nas.local:4533", true), ("http://nas:4533", true), ("http://localhost:4533", true),
        ("http://music.fritz.box", true), ("http://127.0.0.1:4533", true), ("http://10.0.0.5", true),
        ("http://172.16.0.1", true), ("http://172.31.255.1", true), ("http://192.168.1.20", true),
        ("http://169.254.1.1", true), ("http://100.64.0.1", true), ("http://100.127.255.255", true),
        ("http://[::1]:4533", true), ("http://[fd12:3456::1]", true), ("http://[fe80::1]", true),
        ("http://172.32.0.1", false), ("http://100.128.0.1", false), ("http://203.0.113.9:4533", false),
        ("http://8.8.8.8", false), ("http://music.example.com:4533", false), ("http://[2001:db8::1]", false),
    ])
    func password(address: String, allowed: Bool) throws {
        #expect(ServerAddress.mayCarryPassword(try #require(URL(string: address))) == allowed)
    }

    // MARK: Detecting

    @Test("Jellyfin: its public info and Quick Connect")
    func jellyfin() async throws {
        let fake = AddressFake { AddressFake.jellyfin($0) }
        let server = try await MusicServers.detect("http://jf.local:8096", identity: Self.identity, transport: fake)
        #expect(server.kind == .jellyfin)
        #expect(server.url.absoluteString == "http://jf.local:8096")
        #expect(server.id == "ab1b921a10354a07a7dfbbc2c8061335" && server.name == "0548ac3b6612")
        #expect(server.version == "12.4.0" && server.apiVersion == nil)
        #expect(server.capabilities == ServerCapability.jellyfin.union([.quickConnect]))
        #expect(MusicServers.signIn(to: server, identity: Self.identity, transport: fake) is any QuickConnectSignIn)
    }

    @Test("Navidrome: the ping without credentials, its extensions; named by its host")
    func navidrome() async throws {
        let fake = AddressFake { AddressFake.navidrome($0) }
        let server = try await MusicServers.detect("http://nas.local:4533/app/#/album/all", identity: Self.identity,
                                                   transport: fake)
        #expect(server.kind == .subsonic(flavour: .navidrome))
        #expect(server.url.absoluteString == "http://nas.local:4533")
        #expect(server.id == "http://nas.local:4533" && server.name == "nas.local")
        #expect(server.version == "0.64.2 (10114574)" && server.apiVersion == "1.16.1")
        #expect(server.capabilities == SubsonicFixtures.navidromeCapabilities)
        for url in fake.requests where url.path.hasPrefix("/rest/") {
            let query = subsonicQuery(url)
            #expect(query["u"] == nil && query["t"] == nil && query["p"] == nil && query["apiKey"] == nil)
            #expect(query["f"] == ["json"] && query["v"] == ["1.16.1"] && query["c"] == ["Jukebox"])
        }
        #expect(MusicServers.signIn(to: server, identity: Self.identity, transport: fake) is SubsonicSignIn)
    }

    @Test("Other Subsonic servers: a 40 or an ok to the ping proves one too; an old one names its API version")
    func otherSubsonic() async throws {
        let old = AddressFake { url in
            url.path == "/rest/ping.view"
                ? .json(#"{"subsonic-response":{"status":"failed","version":"1.15.0","error":{"code":40,"message":"Wrong username or password"}}}"#)
                : HTTPResponse(status: 404, body: Data())
        }
        let server = try await MusicServers.detect("http://192.168.1.4:4040", identity: Self.identity, transport: old)
        #expect(server.kind == .subsonic(flavour: .subsonic))
        #expect(server.version == "1.15.0" && server.apiVersion == "1.15.0")
        #expect(server.capabilities == [.lyrics, .playlistReorder, .instantMix, .similarArtists, .topSongs])
        #expect(!old.requests.contains { $0.path.contains("getOpenSubsonicExtensions") })

        let gonic = AddressFake { url in
            url.path == "/rest/ping.view"
                ? .json(#"{"subsonic-response":{"status":"ok","version":"1.15.0","type":"gonic","serverVersion":"v0.16.4","openSubsonic":true}}"#)
                : HTTPResponse(status: 404, body: Data())
        }
        let found = try await MusicServers.detect("http://gonic.lan:4747", identity: Self.identity, transport: gonic)
        #expect(found.kind == .subsonic(flavour: .gonic) && found.version == "v0.16.4")
        // Its extensions call is not there (404): no extensions, not a failure.
        #expect(found.capabilities.contains(.replayGain) && !found.capabilities.contains(.syncedLyrics))
    }

    @Test("Neither, nothing, and a Subsonic server too old to speak JSON")
    func notAServer() async throws {
        let page = AddressFake { _ in HTTPResponse(status: 200, body: Data("<html><body>It works!</body></html>".utf8)) }
        await #expect(throws: MusicServerError.invalidServerAddress) {
            _ = try await MusicServers.detect("http://192.168.1.2:8080", identity: Self.identity, transport: page)
        }
        let nobody = AddressFake { _ in try AddressFake.refused() }
        do {
            _ = try await MusicServers.detect("http://192.168.1.3:4533", identity: Self.identity, transport: nobody)
            Issue.record("no error")
        } catch let MusicServerError.transport(message) {
            #expect(!message.isEmpty)
        }
        let xml = AddressFake { url in
            url.path == "/rest/ping.view"
                ? HTTPResponse(status: 200, headers: ["Content-Type": "text/xml"],
                               body: Data(#"<?xml version="1.0"?><subsonic-response xmlns="http://subsonic.org/restapi" status="failed" version="1.3.0"><error code="10"/></subsonic-response>"#.utf8))
                : HTTPResponse(status: 404, body: Data())
        }
        await #expect(throws: MusicServerError.server(status: 30, message: SubsonicConnection.tooOld)) {
            _ = try await MusicServers.detect("http://192.168.1.4:4040", identity: Self.identity, transport: xml)
        }
        let empty = AddressFake { _ in try AddressFake.refused() }
        await #expect(throws: MusicServerError.invalidServerAddress) {
            _ = try await MusicServers.detect("ftp://nas", identity: Self.identity, transport: empty)
        }
        #expect(empty.requests.isEmpty)
    }

    @Test("The address as typed wins when it works, even when a fallback port answers sooner")
    func order() async throws {
        // Navidrome behind a proxy at the address as typed, slow; a Jellyfin
        // at 8096 on the same host, at once.
        let both = AddressFake { url in
            switch AddressFake.address(url) {
            case "nas.local":
                try await Task.sleep(for: .milliseconds(300))
                return AddressFake.navidrome(url)
            case "nas.local:8096": return AddressFake.jellyfin(url)
            default: return try AddressFake.refused()
            }
        }
        let typed = try await MusicServers.detect("nas.local", identity: Self.identity, transport: both)
        #expect(typed.kind == .subsonic(flavour: .navidrome) && typed.url.absoluteString == "http://nas.local")

        // Nothing at the address as typed: the first port in order that answers.
        let fresh = AddressFake { url in
            switch AddressFake.address(url) {
            case "nas.local:4533": return AddressFake.navidrome(url)
            case "nas.local:5082":
                try await Task.sleep(for: .milliseconds(100))
                return AddressFake.jellyfin(url)
            default: return try AddressFake.refused()
            }
        }
        let found = try await MusicServers.detect("nas.local", identity: Self.identity, transport: fresh)
        #expect(found.url.absoluteString == "http://nas.local:4533" && found.kind.isSubsonic)

        // Both at one address: Jellyfin, whose API gives more.
        let one = AddressFake { url in
            url.path.hasPrefix("/rest/") ? AddressFake.navidrome(url) : AddressFake.jellyfin(url)
        }
        #expect(try await MusicServers.detect("http://box:8096", identity: Self.identity, transport: one).kind == .jellyfin)
    }

    // MARK: The real servers

    @Test("The real Jellyfin and Navidrome found as typed, from the web app's address, and by the host alone",
          .enabled(if: JellyfinTestServer.url != nil || NavidromeTestServer.url != nil))
    func realServers() async throws {
        if let url = NavidromeTestServer.url {
            let server = try await MusicServers.detect(url.absoluteString, identity: Self.identity)
            #expect(server.kind == .subsonic(flavour: .navidrome))
            #expect(server.url == url && server.apiVersion == "1.16.1")
            #expect(server.capabilities.isSuperset(of: [.instantMix, .similarArtists, .topSongs, .syncedLyrics,
                                                         .playlistReorder, .replayGain, .playbackTimeline, .lastPlayed]))
            #expect(!server.capabilities.contains(.apiKeySignIn))
            let webApp = try await MusicServers.detect(url.absoluteString + "/app/#/album/all", identity: Self.identity)
            #expect(webApp.url == url)
            if url.port == 4533, let host = url.host {
                let bare = try await MusicServers.detect(host, identity: Self.identity)
                #expect(bare.url == url, "\(host)")
            }
            // Asked Jellyfin's way, Navidrome sends its web app: not a server.
            let asJellyfin = await ServerAddress.probeJellyfin(url, identity: Self.identity, transport: URLSessionTransport())
            #expect(throws: (any Error).self) { try asJellyfin.get() }
            NavidromeTestServer.measure("detected \(server.kind.displayName) \(server.version) at \(server.url), capabilities \(server.capabilities.map(\.rawValue).sorted())")
        }
        if let url = JellyfinTestServer.url {
            let server = try await MusicServers.detect(url.absoluteString, identity: Self.identity)
            #expect(server.kind == .jellyfin && server.url == url && !server.id.isEmpty)
            if url.port == 8096, let host = url.host {
                #expect(try await MusicServers.detect(host, identity: Self.identity).url == url)
            }
            // Asked Subsonic's way, Jellyfin answers 404: not a server.
            let asSubsonic = await ServerAddress.probeSubsonic(url, identity: Self.identity, transport: URLSessionTransport())
            #expect(throws: MusicServerError.invalidServerAddress) { try asSubsonic.get() }
        }
    }
}
