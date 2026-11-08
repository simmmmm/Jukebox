// JellyfinClient.normalize(serverAddress:): what people type as their
// server, and the base URL it becomes.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Jellyfin: server address")
struct JellyfinAddressTests {
    @Test("Addresses people type", arguments: [
        // The task's cases.
        ("demo.example.com", "https://demo.example.com"),
        ("http://1.2.3.4:8096/", "http://1.2.3.4:8096"),
        ("192.168.1.5:8096", "http://192.168.1.5:8096"),
        ("nas.local:8096", "http://nas.local:8096"),
        ("https://x.y/jellyfin/", "https://x.y/jellyfin"),
        // Spaces around are trimmed; one word is a name on the home network.
        (" spaces ", "http://spaces"),
        ("  demo.example.com \n", "https://demo.example.com"),
        // Case, ports, home names.
        ("HTTPS://Music.Example.COM/", "https://music.example.com"),
        ("music.example.com:8920", "https://music.example.com:8920"),
        ("music.example.com:8096", "http://music.example.com:8096"),
        ("https://jellyfin.example.com:443/", "https://jellyfin.example.com:443"),
        ("localhost:8096", "http://localhost:8096"),
        ("nas:8096", "http://nas:8096"),
        ("nas.fritz.box", "http://nas.fritz.box"),
        ("media.home.arpa:8096", "http://media.home.arpa:8096"),
        ("10.0.0.2", "http://10.0.0.2"),
        ("[::1]:8096", "http://[::1]:8096"),
        ("[FD00::1]", "http://[fd00::1]"),
        ("https://10.0.0.2:8920", "https://10.0.0.2:8920"),
        ("nas.example.com.", "https://nas.example.com"),
        // The web app's address bar, pasted.
        ("https://jf.example.com/web/index.html#!/home.html", "https://jf.example.com"),
        ("https://jf.example.com/jellyfin/web/#/home", "https://jf.example.com/jellyfin"),
        ("jf.example.com/WEB/", "https://jf.example.com"),
        ("jf.example.com/webdav/", "https://jf.example.com/webdav"),
        ("jellyfin.example.com?x=1", "https://jellyfin.example.com"),
        ("https://x.y/a/b//", "https://x.y/a/b"),
    ])
    func accepted(_ input: String, _ expected: String) {
        #expect(JellyfinClient.normalize(serverAddress: input)?.absoluteString == expected)
    }

    @Test("Not a server address", arguments: [
        "", "   ", "\n", "not a url", "ftp://x.y", "http://", "https://", "user:pw@x.y",
        "x.y:99999", "x.y:0", "x.y:", "x.y:abc", "1.2.3", "256.1.1.1", "-bad.example.com",
        "bad-.example.com", "a..b", "under_score.example.com", "música.example.com",
        "https:/x.y", "x.y/a b", "[::1", "[zz::1]", "x.y:80:80",
    ])
    func rejected(_ input: String) {
        #expect(JellyfinClient.normalize(serverAddress: input) == nil)
    }

    @Test("Addresses to try: http at 8096 second, when no port was typed", arguments: [
        ("192.168.1.10", ["http://192.168.1.10", "http://192.168.1.10:8096"]),
        ("nas.local", ["http://nas.local", "http://nas.local:8096"]),
        ("nas", ["http://nas", "http://nas:8096"]),
        ("[fd00::1]", ["http://[fd00::1]", "http://[fd00::1]:8096"]),
        // No scheme typed: the https was a guess, so http at 8096 is tried too.
        ("music.example.com", ["https://music.example.com", "http://music.example.com:8096"]),
        ("http://music.example.com", ["http://music.example.com", "http://music.example.com:8096"]),
        ("nas.local/jellyfin/", ["http://nas.local/jellyfin", "http://nas.local:8096/jellyfin"]),
        // A typed port is the port.
        ("nas.local:8096", ["http://nas.local:8096"]),
        ("192.168.1.10:80", ["http://192.168.1.10:80"]),
        ("music.example.com:8920", ["https://music.example.com:8920"]),
        ("http://1.2.3.4:8096/", ["http://1.2.3.4:8096"]),
        // https typed: TLS was asked for, never plain http instead.
        ("https://music.example.com", ["https://music.example.com"]),
        ("HTTPS://Music.Example.COM/", ["https://music.example.com"]),
        ("https://10.0.0.2", ["https://10.0.0.2"]),
        ("https://jf.example.com/jellyfin/web/#/home", ["https://jf.example.com/jellyfin"]),
        ("  https://music.example.com \n", ["https://music.example.com"]),
    ])
    func candidates(_ input: String, _ expected: [String]) {
        let found = JellyfinClient.candidateAddresses(for: input).map(\.absoluteString)
        #expect(found == expected)
        // The first is always what normalize gives.
        #expect(found.first == JellyfinClient.normalize(serverAddress: input)?.absoluteString)
    }

    @Test("No addresses to try for what is not an address", arguments: ["", "   ", "not a url", "ftp://x.y", "x.y:0", "user:pw@x.y"])
    func noCandidates(_ input: String) {
        #expect(JellyfinClient.candidateAddresses(for: input).isEmpty)
    }

    @Test("A base path is kept for routes behind a reverse proxy")
    func basePath() throws {
        let base = try #require(JellyfinClient.normalize(serverAddress: "https://x.y/jellyfin/"))
        let client = JellyfinClient(serverURL: base, identity: JellyfinFixtures.identity)
        #expect(client.url("/System/Info/Public").absoluteString == "https://x.y/jellyfin/System/Info/Public")
        // A base URL given with a trailing slash (not from normalize) works too.
        let slashed = JellyfinClient(serverURL: URL(string: "https://x.y/jellyfin/")!, identity: JellyfinFixtures.identity)
        #expect(slashed.url("/Items").absoluteString == "https://x.y/jellyfin/Items")
    }
}
