// LRCLIBClient against the real lrclib.net, where it can be reached: with
// LRCLIB_LIVE=1 always (and then a failure to reach it fails the test), and
// otherwise when the host answers within 3 s. GitHub's runners reach it;
// the machine these were written on does not, and skips. XCTest rather than
// swift-testing because a test that finds it cannot run says so with XCTSkip.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class LRCLIBLiveTests: XCTestCase {
    /// Whether lrclib.net answers at all, any status, within 3 s.
    static func reachable() async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: "https://lrclib.net/api/get-cached?track_name=Get%20Lucky&artist_name=Daft%20Punk") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.setValue(LRCLIBClient.userAgent(appVersion: "tests"), forHTTPHeaderField: "User-Agent")
        do {
            _ = try await URLSessionTransport(session: session).send(request)
            return true
        } catch {
            return false
        }
    }

    func skipUnlessLive() async throws {
        if ProcessInfo.processInfo.environment["LRCLIB_LIVE"] == "1" { return }
        let start = ContinuousClock().now
        let reachable = await Self.reachable()
        guard reachable else {
            throw XCTSkip("lrclib.net could not be reached (gave up after \(ContinuousClock().now - start), at most 3 s); LRCLIB_LIVE=1 makes this test run anyway.")
        }
    }

    func testAFamousSongHasSyncedLyrics() async throws {
        try await skipUnlessLive()
        let client = LRCLIBClient(userAgent: LRCLIBClient.userAgent(appVersion: "tests"))
        let start = ContinuousClock().now
        let found = try await client.lyrics(artist: "Daft Punk", title: "Get Lucky (feat. Pharrell Williams)",
                                            album: "Random Access Memories", duration: 369)
        let took = ContinuousClock().now - start
        guard case let .found(lyrics, synced) = found else {
            return XCTFail("LRCLIB has no lyrics for Get Lucky: \(found)")
        }
        print("LRCLIB-MEASURE Get Lucky: \(lyrics.lines.count) lines, synced \(synced), in \(took)")
        XCTAssertTrue(synced)
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertGreaterThan(lyrics.lines.count, 20)
        let starts = lyrics.lines.compactMap(\.start)
        XCTAssertEqual(starts, starts.sorted())
        // The song is six minutes long; its words end before it does.
        XCTAssertLessThan(starts.last ?? 999, 369)
        XCTAssertTrue(lyrics.lines.contains { $0.text.localizedCaseInsensitiveContains("lucky") })
    }

    /// Without an album, the search alone: LRCLIB's own database, quick,
    /// where /api/get for an unknown song may look elsewhere for seconds.
    func testAMadeUpSongIsNotFound() async throws {
        try await skipUnlessLive()
        let client = LRCLIBClient(userAgent: LRCLIBClient.userAgent(appVersion: "tests"))
        let found = try await client.lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                            album: nil, duration: 192)
        XCTAssertEqual(found, .notFound)
    }
}
