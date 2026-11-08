// LastFMClient against Last.fm's answers as literals (the network is not
// reachable from the tests): the request it makes, the three methods read
// leniently (numbers as strings or numbers, a list of one as one object,
// nothing as ""), Last.fm's errors as the four cases, and the key check.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import XCTest

final class LastFMClientTests: XCTestCase {
    func client(_ body: String, status: Int = 200) -> (LastFMClient, LastFMMockTransport) {
        let mock = LastFMMockTransport { _ in LastFMFixtures.respond(status, body) }
        return (LastFMClient(apiKey: "0123456789abcdef0123456789abcdef", transport: mock), mock)
    }

    func testTheRequest() async throws {
        let (client, mock) = client(LastFMFixtures.cherSimilar)
        _ = try await client.similarArtists(to: "Simon + Garfunkel", limit: 30)
        _ = try await client.similarTracks(artist: "Mumford & Sons", title: "Little Lion Man", limit: 5000)
        _ = try await client.topTracks(artist: "Beyoncé", limit: 0)
        let sent = mock.requests
        XCTAssertEqual(sent.count, 3)

        let first = try XCTUnwrap(sent.first)
        let url = try XCTUnwrap(first.request.url)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://ws.audioscrobbler.com/2.0/?"), url.absoluteString)
        XCTAssertEqual(first.request.httpMethod, "GET")
        XCTAssertEqual(first.asked.query, ["method": "artist.getsimilar", "artist": "Simon + Garfunkel", "limit": "30",
                                           "autocorrect": "1", "api_key": "0123456789abcdef0123456789abcdef", "format": "json"])
        // "+" escaped: Last.fm would read a bare one as a space.
        XCTAssertTrue(url.absoluteString.contains("artist=Simon%20%2B%20Garfunkel"), url.absoluteString)
        XCTAssertNotNil(first.request.value(forHTTPHeaderField: "User-Agent"))

        let second = sent[1].asked
        XCTAssertEqual(second.method, "track.getsimilar")
        XCTAssertEqual(second.artist, "Mumford & Sons")
        XCTAssertEqual(second.track, "Little Lion Man")
        XCTAssertEqual(second.query["limit"], "1000", "Last.fm takes at most 1000")
        XCTAssertTrue(sent[1].request.url?.absoluteString.contains("artist=Mumford%20%26%20Sons") ?? false)

        let third = sent[2].asked
        XCTAssertEqual(third.method, "artist.gettoptracks")
        XCTAssertEqual(third.artist, "Beyoncé")
        XCTAssertEqual(third.query["limit"], "1", "at least 1")
        XCTAssertEqual(third.query["autocorrect"], "1")
    }

    func testSimilarArtistsWithMatchAsAString() async throws {
        let (client, _) = client(LastFMFixtures.cherSimilar)
        let similar = try await client.similarArtists(to: "Cher")
        XCTAssertEqual(similar, [.init(name: "Sonny & Cher", match: 1), .init(name: "Cyndi Lauper", match: 0.354226),
                                 .init(name: "Madonna", match: 0.31)])
        let (limited, _) = self.client(LastFMFixtures.cherSimilar)
        let two = try await limited.similarArtists(to: "Cher", limit: 2)
        XCTAssertEqual(two.map(\.name), ["Sonny & Cher", "Cyndi Lauper"])
    }

    func testSimilarArtistsLeniently() async throws {
        let cases: [(String, [LastFMClient.SimilarArtist])] = [
            // `match` as a number.
            (#"{"similarartists":{"artist":[{"name":"Portishead","match":0.8}],"@attr":{"artist":"Massive Attack"}}}"#,
             [.init(name: "Portishead", match: 0.8)]),
            // One similar artist, as the object rather than a list of it.
            (#"{"similarartists":{"artist":{"name":"Portishead","match":"0.5"},"@attr":{"artist":"Tricky"}}}"#,
             [.init(name: "Portishead", match: 0.5)]),
            // None: "" for the list, or no list at all.
            (#"{"similarartists":{"artist":"","@attr":{"artist":"Nobody"}}}"#, []),
            (##"{"similarartists":{"#text":"\n","@attr":{"artist":"Nobody"}}}"##, []),
            (#"{}"#, []),
            // An element without a name or a match, or not an object, is left out.
            (#"{"similarartists":{"artist":[{"match":"0.9"},{"name":"Björk","match":"0.7"},{"name":"Nobody"},42,{"name":"  ","match":"1"},{"name":"Tricky","match":"bad"}]}}"#,
             [.init(name: "Björk", match: 0.7)]),
            // A name that is a number; a match above 1 is 1.
            (#"{"similarartists":{"artist":[{"name":311,"match":"1.5"}]}}"#, [.init(name: "311", match: 1)]),
        ]
        for (body, expected) in cases {
            let (client, _) = client(body)
            let similar = try await client.similarArtists(to: "X")
            XCTAssertEqual(similar, expected, body)
        }
    }

    func testSimilarTracksWithMatchAsANumber() async throws {
        let (client, _) = client(LastFMFixtures.radioheadSimilarTracks)
        let similar = try await client.similarTracks(artist: "Radiohead", title: "Street Spirit")
        XCTAssertEqual(similar, [.init(artist: "Radiohead", title: "Fake Plastic Trees", match: 1),
                                 .init(artist: "Massive Attack", title: "Teardrop", match: 0.873)])
        // The artist as a string, or as {"#text": …}; `match` as a string.
        let other = #"""
        {"similartracks":{"track":[{"name":"Roads","match":"0.6","artist":"Portishead"},
        {"name":"Unfinished Sympathy","match":0.5,"artist":{"#text":"Massive Attack"}},
        {"name":"No Artist","match":0.4}]}}
        """#
        let (lenient, _) = self.client(other)
        let more = try await lenient.similarTracks(artist: "X", title: "Y")
        XCTAssertEqual(more, [.init(artist: "Portishead", title: "Roads", match: 0.6),
                              .init(artist: "Massive Attack", title: "Unfinished Sympathy", match: 0.5)])
    }

    func testTopTracksWithCountsAndRanksAsStrings() async throws {
        let (client, _) = client(LastFMFixtures.radioheadTopTracks)
        let top = try await client.topTracks(artist: "Radiohead")
        XCTAssertEqual(top, [.init(title: "Creep", playcount: 10_985_723, rank: 1),
                             .init(title: "Karma Police", playcount: 9_411_830, rank: 2)])
        // Out of order, a rank missing (its place then), counts as numbers.
        let other = #"""
        {"toptracks":{"track":[{"name":"B","playcount":50,"@attr":{"rank":"3"}},{"name":"A","playcount":"90","@attr":{"rank":1}},
        {"name":"C"}]}}
        """#
        let (lenient, _) = self.client(other)
        let ranked = try await lenient.topTracks(artist: "X")
        XCTAssertEqual(ranked, [.init(title: "A", playcount: 90, rank: 1), .init(title: "B", playcount: 50, rank: 3),
                                .init(title: "C", playcount: 0, rank: 3)])
    }

    func testLastFMsErrors() async {
        let cases: [(Int, String, LastFMClient.Failure)] = [
            (403, LastFMFixtures.invalidKey, .invalidKey),
            (200, LastFMFixtures.invalidKey, .invalidKey),
            (403, LastFMFixtures.suspendedKey, .invalidKey),
            (200, LastFMFixtures.rateLimited, .rateLimited),
            (429, LastFMFixtures.rateLimited, .rateLimited),
            (429, "", .rateLimited),
            (200, LastFMFixtures.artistNotFound, .notFound),
            (200, #"{"error":"6","message":"Track not found"}"#, .notFound),
            (200, LastFMFixtures.operationFailed,
             .other("Operation failed - Most likely the backend service failed. Please try again.")),
            (200, #"{"error":11}"#, .other("Last.fm error 11.")),
            (502, "<html><body>Bad Gateway</body></html>", .other("Last.fm answered with status 502.")),
            (200, "not JSON at all", .other("Last.fm's answer could not be read.")),
        ]
        for (status, body, expected) in cases {
            let (client, _) = client(body, status: status)
            do {
                _ = try await client.similarArtists(to: "Cher")
                XCTFail("no error for \(status) \(body)")
            } catch {
                XCTAssertEqual(error as? LastFMClient.Failure, expected, "\(status) \(body)")
            }
            do {
                _ = try await client.topTracks(artist: "Cher")
                XCTFail("no error for \(status) \(body)")
            } catch {
                XCTAssertEqual(error as? LastFMClient.Failure, expected, "\(status) \(body)")
            }
        }
        XCTAssertEqual(LastFMClient.Failure.invalidKey.errorDescription, "Last.fm did not accept the API key.")
    }

    func testNoNetworkIsNotALastFMError() async {
        let mock = LastFMMockTransport { _ in throw URLError(.notConnectedToInternet) }
        let client = LastFMClient(apiKey: "key", transport: mock)
        do {
            _ = try await client.similarTracks(artist: "A", title: "B")
            XCTFail("no error")
        } catch {
            XCTAssertNil(error as? LastFMClient.Failure)
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testValidateKey() async {
        let (good, mock) = client(LastFMFixtures.cherSimilar)
        let accepted = await good.validateKey()
        XCTAssertTrue(accepted)
        XCTAssertEqual(mock.requests.first?.asked.query["limit"], "1", "one cheap call")

        let (bad, _) = client(LastFMFixtures.invalidKey, status: 403)
        let rejected = await bad.validateKey()
        XCTAssertFalse(rejected)
        // Asked to wait: the key was read and taken.
        let (busy, _) = client(LastFMFixtures.rateLimited)
        let waiting = await busy.validateKey()
        XCTAssertTrue(waiting)
        let (broken, _) = client("", status: 500)
        let failing = await broken.validateKey()
        XCTAssertFalse(failing)
        let offline = LastFMClient(apiKey: "key", transport: LastFMMockTransport { _ in throw URLError(.timedOut) })
        let unreachable = await offline.validateKey()
        XCTAssertFalse(unreachable)

        // No key, or not one: no request at all.
        for key in ["", "   ", "two words"] {
            let mock = LastFMMockTransport { _ in LastFMFixtures.respond(200, LastFMFixtures.cherSimilar) }
            let result = await LastFMClient(apiKey: key, transport: mock).validateKey()
            XCTAssertFalse(result, key)
            XCTAssertEqual(mock.count, 0, key)
        }
    }
}
