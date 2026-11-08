// The radio on the test server's real library (RadioRealLibraryFixture: 358
// tracks as Jellyfin 12.4 gives them), with listings to judge by eye
// (docs/RADIO.md, "On the test server"). And, when JELLYFIN_URL is set
// (dev/kit-test.sh beside dev/jellyfin-test-server.sh), the same against
// the live server, to check the fixture still is what the server has.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import JukeboxKit
import XCTest

final class RadioRealServerTests: XCTestCase {
    static func listing(_ title: String, _ picks: [RadioPick], snapshot: LibrarySnapshot) {
        RadioEvaluationTests.line(title)
        for (k, pick) in picks.enumerated() {
            let genres = snapshot.genreKeys(of: pick.track).compactMap { snapshot.genreName(key: $0) }.joined(separator: ", ")
            RadioEvaluationTests.line(String(format: "  %2d. %@ — %@ (%@, %d) · %@", k + 1, pick.track.name, pick.track.artistLine,
                                             genres, pick.track.year ?? 0, pick.reason.text))
        }
    }

    func testStationsOnTheTestServersLibrary() throws {
        let tracks = RadioRealLibraryFixture.tracks
        XCTAssertEqual(tracks.count, 358)
        let snapshot = LibrarySnapshot(tracks: tracks)
        let history = ListeningHistory()
        let taste = TasteProfile(snapshot: snapshot, history: history, now: Date(timeIntervalSinceReferenceDate: 815_800_000))
        let graph = SimilarityGraph.fromLibrary(snapshot)

        // The joined tags are split: 23 artists, not 23 plus every pairing.
        XCTAssertEqual(snapshot.artistTrackCounts.count, 23)
        XCTAssertEqual(snapshot.genreTrackCounts.count, 23)
        XCTAssertNotNil(snapshot.artist(key: NameKey.artist("Lyric Engine"))?.id)
        let neighbors = graph.similarArtists(to: NameKey.artist("Velvet Static"), limit: 6)
            .map { "\(snapshot.artist(key: $0.key)?.name ?? $0.key) \(String(format: "%.2f", $0.weight))" }
        RadioEvaluationTests.line("real library: Velvet Static's neighbours: \(neighbors.joined(separator: ", "))")

        func run(_ seed: StationSeed, randomSeed: UInt64, count: Int = 20, adventurousness: Double = 0.35) -> RadioSession {
            RadioSession(station: Station(seed: seed, snapshot: snapshot), snapshot: snapshot, taste: taste, graph: graph,
                         settings: RadioSettings(adventurousness: adventurousness), randomSeed: randomSeed)
        }

        // An artist station.
        let velvet = try XCTUnwrap(snapshot.artist(key: NameKey.artist("Velvet Static")))
        var artistStation = run(.artist(key: velvet.key, name: velvet.name, id: velvet.id), randomSeed: 8)
        let artistPicks = artistStation.next(20)
        Self.listing("real library: \(artistStation.station.title) (\(artistStation.station.subtitle ?? "")), adventurousness 0.35",
                     artistPicks, snapshot: snapshot)

        // A song station from a song with a guest.
        let duet = try XCTUnwrap(tracks.first { $0.artists.first?.name == "MC Polder; Lyric Engine" })
        var songStation = run(.track(duet.id), randomSeed: 9)
        let songPicks = songStation.next(20)
        Self.listing("real library: \(songStation.station.title) (\(songStation.station.subtitle ?? ""))", songPicks, snapshot: snapshot)
        XCTAssertEqual(songPicks.first?.track.id, duet.id)

        // A genre station, then the listener skips the first two Bebop songs.
        var jazz = run(.genre(key: NameKey.genre("Jazz"), name: "Jazz"), randomSeed: 10)
        let jazzPicks = jazz.next(20)
        Self.listing("real library: \(jazz.station.title)", jazzPicks, snapshot: snapshot)

        for picks in [artistPicks, songPicks, jazzPicks] {
            XCTAssertEqual(picks.count, 20)
            XCTAssertEqual(RadioMetrics.repeats(picks), 0)
            XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: snapshot, separation: 3), 0)
            XCTAssertEqual(RadioMetrics.albumBackToBack(picks), 0)
        }
        // Velvet Static's station stays with rock: every pick shares a genre
        // with Velvet Static or is by a neighbour.
        let velvetGenres = Set(snapshot.tracks(artistKey: velvet.key).flatMap { snapshot.genreKeys(of: $0) })
        let near = artistPicks.filter { pick in
            !velvetGenres.isDisjoint(with: snapshot.genreKeys(of: pick.track))
                || snapshot.artistKeys(of: pick.track).contains { graph.weight(velvet.key, $0) > 0 }
        }
        XCTAssertGreaterThanOrEqual(near.count, 18)
        // Jazz Radio plays jazz, as much as it can: the server has three jazz
        // artists, and three tracks between two by one artist leave every
        // fourth song to someone else (at most 15 of 20).
        let jazzArtists = Set(jazzPicks.compactMap { snapshot.primaryArtistKey(of: $0.track) }
            .filter { key in snapshot.ownTracks(artistKey: key).allSatisfy { snapshot.genreKeys(of: $0).contains(NameKey.genre("Jazz")) } })
        XCTAssertEqual(jazzArtists.count, 3)
        XCTAssertGreaterThanOrEqual(jazzPicks.filter { snapshot.genreKeys(of: $0.track).contains(NameKey.genre("Jazz")) }.count, 14)

        // Feedback on The Lanterns Radio at 0.7: the listener plays the queue,
        // skips the pop songs (two at most), gives a thumbs down to the first
        // Iron Meadow song; the rest of the queue is put back and chosen again.
        var feedback = run(.artist(key: NameKey.artist("The Lanterns"), name: "The Lanterns", id: nil), randomSeed: 12,
                           adventurousness: 0.7)
        let opening = feedback.next(8)
        Self.listing("real library: The Lanterns Radio at 0.7, first 8", opening, snapshot: snapshot)
        var said: [String] = []
        var heard = 0
        var skips = 0
        var disliked = false
        for pick in opening {
            heard += 1
            let genres = snapshot.genreKeys(of: pick.track)
            if skips < 2, genres.contains("pop") {
                // The test server's songs are tones of 5 to 8 seconds.
                feedback.record(.skipped(pick.track.id, after: 1))
                said.append("skipped “\(pick.track.name)” (\(pick.track.artistLine))")
                skips += 1
            } else if !disliked, snapshot.primaryArtistKey(of: pick.track) == "ironmeadow" {
                feedback.record(.disliked(pick.track.id))
                said.append("thumbs down on “\(pick.track.name)” (\(pick.track.artistLine))")
                disliked = true
            } else {
                feedback.record(.finished(pick.track.id))
            }
            if skips == 2, disliked { break }
        }
        feedback.returnUnplayed(Array(feedback.handedOut.dropFirst(heard)))
        let afterFeedback = feedback.next(10)
        Self.listing("real library: heard \(heard): \(said.joined(separator: "; ")); the next 10", afterFeedback, snapshot: snapshot)
        XCTAssertTrue(disliked)
        XCTAssertFalse(afterFeedback.contains { snapshot.primaryArtistKey(of: $0.track) == "ironmeadow" })
        XCTAssertLessThanOrEqual(afterFeedback.filter { snapshot.genreKeys(of: $0.track).contains("pop") }.count,
                                 opening.filter { snapshot.genreKeys(of: $0.track).contains("pop") }.count)
    }

    // MARK: Against the live server

    struct LiveItems: Decodable {
        struct Item: Decodable {
            struct Ref: Decodable {
                var Id: String?
                var Name: String
            }

            var Id: String
            var Name: String
            var Genres: [String]?
            var ArtistItems: [Ref]?
            var AlbumArtists: [Ref]?
        }

        var Items: [Item]
    }

    func testFixtureMatchesTheLiveServer() async throws {
        guard let base = ProcessInfo.processInfo.environment["JELLYFIN_URL"].flatMap(URL.init(string:)) else {
            throw XCTSkip("JELLYFIN_URL is not set")
        }
        let user = ProcessInfo.processInfo.environment["JELLYFIN_USER"] ?? "test"
        let password = ProcessInfo.processInfo.environment["JELLYFIN_PASSWORD"] ?? "test"
        let auth = #"MediaBrowser Client="JukeboxRadioTests", Device="Linux", DeviceId="jukebox-radio-tests", Version="1.0""#

        var signIn = URLRequest(url: base.appendingPathComponent("Users/AuthenticateByName"))
        signIn.httpMethod = "POST"
        signIn.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signIn.setValue(auth, forHTTPHeaderField: "Authorization")
        signIn.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": password])
        let (signedIn, _) = try await URLSession.shared.data(for: signIn)
        let session = try XCTUnwrap(JSONSerialization.jsonObject(with: signedIn) as? [String: Any])
        let token = try XCTUnwrap(session["AccessToken"] as? String)
        let userID = try XCTUnwrap((session["User"] as? [String: Any])?["Id"] as? String)

        var components = try XCTUnwrap(URLComponents(url: base.appendingPathComponent("Items"), resolvingAgainstBaseURL: false))
        components.queryItems = [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Genres"),
        ]
        var request = URLRequest(url: try XCTUnwrap(components.url))
        request.setValue(auth + #", Token="\#(token)""#, forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let live = try JSONDecoder().decode(LiveItems.self, from: data).Items

        // Compared by what the radio reads (title, performers, genres), not by
        // id: a server set up afresh (CI's) may number its items otherwise.
        let fixture = RadioRealLibraryFixture.tracks
        let fixtureLines = fixture.map { "\($0.name)|\($0.artists.map(\.name))|\($0.genres)" }.sorted()
        let liveLines = live.map { "\($0.Name)|\(($0.ArtistItems ?? []).map(\.Name))|\($0.Genres ?? [])" }.sorted()
        let same = zip(fixtureLines, liveLines).filter { $0 == $1 }.count
        RadioEvaluationTests.line("live server: \(live.count) tracks, \(same) the same as the fixture")
        XCTAssertEqual(live.count, fixture.count)
        XCTAssertEqual(same, fixture.count)

        // A station on the live library, mapped the same way.
        let tracks = live.map { item in
            Track(id: item.Id, name: item.Name, artists: (item.ArtistItems ?? []).map { ArtistRef(id: $0.Id, name: $0.Name) },
                  albumArtist: item.AlbumArtists?.first.map { ArtistRef(id: $0.Id, name: $0.Name) }, genres: item.Genres ?? [])
        }
        let snapshot = LibrarySnapshot(tracks: tracks)
        var station = RadioSession(station: Station(seed: .personal, snapshot: snapshot), snapshot: snapshot,
                                   taste: TasteProfile(snapshot: snapshot, history: ListeningHistory(), now: Date()),
                                   graph: .fromLibrary(snapshot), randomSeed: 1)
        let picks = station.next(30)
        XCTAssertEqual(picks.count, 30)
        XCTAssertEqual(RadioMetrics.separationViolations(picks, snapshot: snapshot, separation: 3), 0)
    }
}
