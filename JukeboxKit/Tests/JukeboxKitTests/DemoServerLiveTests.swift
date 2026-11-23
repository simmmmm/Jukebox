// The demo server App Review is told to sign in to (docs/RELEASE.md,
// "Review notes"): demo.navidrome.org, user demo, password demo, typed the
// ways a reviewer might. Where the internet is reached: DEMO_LIVE=1 makes a
// failure to reach it fail; otherwise it skips when the host does not
// answer within 5 s. App Review's five tries on 22 November 2026 all ended
// as `unreachable`.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class DemoServerLiveTests: XCTestCase {
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.3 (1)",
                                         deviceName: "Tests", deviceID: "demo-live-tests")

    func skipUnlessLive() async throws {
        if ProcessInfo.processInfo.environment["DEMO_LIVE"] == "1" { return }
        var request = URLRequest(url: URL(string: "https://demo.navidrome.org/rest/ping.view")!)
        request.timeoutInterval = 5
        do { _ = try await URLSessionTransport().send(request) } catch {
            throw XCTSkip("demo.navidrome.org could not be reached; DEMO_LIVE=1 makes this test run anyway.")
        }
    }

    /// Every way of typing it: found at https (http:// redirects there, and
    /// the server keeps the address it answered at), and signed in.
    func testEveryWayOfTypingItSignsIn() async throws {
        try await skipUnlessLive()
        for typed in ["demo.navidrome.org", "https://demo.navidrome.org", "http://demo.navidrome.org",
                      "http://demo.navidrome.org:80", "demo.navidrome.org/app/"] {
            let start = ContinuousClock().now
            let server = try await MusicServers.detect(typed, identity: Self.identity)
            let took = ContinuousClock().now - start
            print("DEMO-MEASURE \(typed): \(server.kind) at \(server.url) in \(took)")
            XCTAssertEqual(server.url.absoluteString, "https://demo.navidrome.org", typed)
            XCTAssertLessThan(took, .seconds(10), typed)
            let credentials = try await MusicServers.signIn(to: server, identity: Self.identity)
                .signIn(username: "demo", password: "demo")
            XCTAssertEqual(credentials.userName, "demo", typed)
        }
    }

    /// Three requests at once that are all redirected (http:// to https://,
    /// then /app/): Linux's URLSession crashed on that ("EasyHandle.swift:293:
    /// Fatal error … libcurl.Easy Code=43", 23 November 2026) until the kit
    /// followed redirects itself (URLSessionTransport).
    func testRedirectsAtOnce() async throws {
        try await skipUnlessLive()
        let transport = URLSessionTransport()
        let statuses = await withTaskGroup(of: Int.self) { group in
            for path in ["/rest/ping.view?f=json", "/System/Info/Public", "/identity"] {
                group.addTask {
                    var request = URLRequest(url: URL(string: "http://demo.navidrome.org" + path)!)
                    request.timeoutInterval = 15
                    return (try? await transport.send(request).status) ?? 0
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(statuses, [200, 200, 200])
    }
}
