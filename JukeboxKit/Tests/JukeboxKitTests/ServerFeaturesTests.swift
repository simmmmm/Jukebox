// What a server can do beyond the library, asked of the real test servers,
// each both ways: a server that has it, and one that lacks it. The
// photographer, 18 November 2026: "zorg dat je ook alleen die opties toont
// als het beschikbaar is op die server en dat je dat ook zeker weet".
//
// The servers, each skipped when it is not up:
// - JELLYFIN_URL (dev/jellyfin-test-server.sh): remote control yes,
//   Playback Reporting no (the usual test server has no plugin);
// - PLAYBACK_REPORTING_URL: a Jellyfin with the plugin installed, where
//   "test" is an administrator (yes) and "second" is not (no);
// - EMBY_URL: remote control yes, Playback Reporting no;
// - NAVIDROME_URL: sharing yes (Navidrome 0.64.2's default);
//   NAVIDROME_NOSHARE_URL: a Navidrome with ND_ENABLESHARING=false (no),
//   and its library's songs tagged with moods and a tempo.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum FeatureServers {
    static let environment = ProcessInfo.processInfo.environment
    static func url(_ key: String) -> URL? { environment[key].flatMap { MusicServers.candidateAddresses(for: $0).first } }

    static func identity(_ device: String) -> ClientIdentity {
        ClientIdentity(clientName: "JukeboxKitTests", clientVersion: "1.0", deviceName: "Kit tests: \(device)",
                       deviceID: "kit-features-\(device)")
    }

    /// Signed in as the app signs in.
    static func open(_ url: URL, user: String = "test", password: String = "test",
                     device: String) async throws -> any MusicServer {
        let identity = identity(device)
        let found = try await MusicServers.detect(url.absoluteString, identity: identity)
        let credentials = try await MusicServers.signIn(to: found, identity: identity)
            .signIn(username: user, password: password)
        return MusicServers.open(credentials, identity: identity)
    }
}

@Suite("Server features: asked, both ways", .serialized, .timeLimit(.minutes(1)))
struct ServerCapabilityProbeTests {
    @Test("Jellyfin without the plugin: remote control, no Playback Reporting, no sharing",
          .enabled(if: FeatureServers.url("JELLYFIN_URL") != nil))
    func jellyfin() async throws {
        let server = try await FeatureServers.open(try #require(FeatureServers.url("JELLYFIN_URL")), device: "jellyfin")
        let found = try await server.currentCapabilities()
        #expect(found.contains(.remoteControl))
        // The usual test server has no plugin; the same server as
        // PLAYBACK_REPORTING_URL has it.
        let samePlugin = FeatureServers.environment["JELLYFIN_URL"] == FeatureServers.environment["PLAYBACK_REPORTING_URL"]
        #expect(found.contains(.playbackReporting) == samePlugin)
        #expect(!found.contains(.share))
        await server.signOut()
    }

    @Test("Jellyfin with Playback Reporting: an administrator has it, another user not",
          .enabled(if: FeatureServers.url("PLAYBACK_REPORTING_URL") != nil))
    func playbackReporting() async throws {
        let url = try #require(FeatureServers.url("PLAYBACK_REPORTING_URL"))
        let admin = try await FeatureServers.open(url, device: "reporting-admin")
        #expect(try await admin.currentCapabilities().contains(.playbackReporting))
        let plays = try await #require(admin as? JellyfinServer).client
            .playbackReportingPlays(year: Calendar.current.component(.year, from: Date()))
        // Only this user's, and only songs (the query says both).
        JellyfinTestServer.measure("playback reporting: \(plays.count) plays this year for test")
        await admin.signOut()

        let other = try await FeatureServers.open(url, user: "second", password: "second", device: "reporting-second")
        #expect(!(try await other.currentCapabilities().contains(.playbackReporting)))
        await #expect(throws: (any Error).self) {
            _ = try await #require(other as? JellyfinServer).client.playbackReportingPlays(year: 2026)
        }
        await other.signOut()
    }

    @Test("Emby: remote control, no Playback Reporting", .enabled(if: FeatureServers.url("EMBY_URL") != nil))
    func emby() async throws {
        let server = try await FeatureServers.open(try #require(FeatureServers.url("EMBY_URL")), device: "emby")
        let found = try await server.currentCapabilities()
        #expect(found.contains(.remoteControl))
        #expect(!found.contains(.playbackReporting))
        await server.signOut()
    }

    @Test("Navidrome with sharing: a link that opens, made once per song",
          .enabled(if: FeatureServers.url("NAVIDROME_URL") != nil))
    func navidromeShares() async throws {
        let server = try await FeatureServers.open(try #require(FeatureServers.url("NAVIDROME_URL")), device: "navidrome")
        let found = try await server.currentCapabilities()
        #expect(found.contains(.share))
        #expect(!found.contains(.remoteControl))
        #expect(!found.contains(.playbackReporting))
        let client = try #require(server as? SubsonicClient)
        let track = try #require(try await server.allTracks(progress: nil).first)
        let link = try await server.shareURL(for: track.id, tracks: [track.id])
        #expect(link.path.contains("/share/"))
        #expect(try await NavidromeTestServer.fetch(link).status == 200)
        // Asked again, the same link: no second share for the same song.
        #expect(try await server.shareURL(for: track.id, tracks: [track.id]) == link)
        try await client.deleteShares(for: [track.id])
        #expect(try await client.shares().allSatisfy { $0.trackIDs != [track.id] })
    }

    @Test("Navidrome with sharing off: no Share; songs carry their moods and tempo",
          .enabled(if: FeatureServers.url("NAVIDROME_NOSHARE_URL") != nil))
    func navidromeWithout() async throws {
        let server = try await FeatureServers.open(try #require(FeatureServers.url("NAVIDROME_NOSHARE_URL")),
                                                   device: "navidrome-noshare")
        #expect(!(try await server.currentCapabilities().contains(.share)))
        await #expect(throws: (any Error).self) {
            _ = try await server.shareURL(for: "x", tracks: ["x"])
        }
        let tracks = try await server.allTracks(progress: nil)
        let byName = Dictionary(tracks.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byName["Slow Rain"]?.moods == ["Melancholic", "Calm"])
        #expect(byName["Slow Rain"]?.bpm == 72)
        #expect(byName["Bright Run"]?.bpm == 140)
        // Untagged: nothing, not an empty list or a tempo of 0.
        #expect(byName["No Tags"]?.moods == nil)
        #expect(byName["No Tags"]?.bpm == nil)
    }

    @Test("A probe that cannot ask keeps what was known; a no is a no")
    func probeKeeps() async {
        let kept: Set<ServerCapability> = [.share]
        #expect(await ServerProbe.check(.share, kept: kept) { throw MusicServerError.transport("offline") } == .share)
        #expect(await ServerProbe.check(.share, kept: []) { throw MusicServerError.transport("offline") } == nil)
        #expect(await ServerProbe.check(.share, kept: kept) { throw MusicServerError.unsupported(.share) } == nil)
        #expect(await ServerProbe.check(.playbackReporting, kept: [.playbackReporting]) {
            throw JellyfinError.server(status: 403, message: nil)
        } == nil)
        #expect(await ServerProbe.check(.share, kept: []) {} == .share)
    }

    @Test("An unknown capability in the keychain is passed over, not the account lost")
    func lenientCapabilities() throws {
        var credentials = EmbyTestServer.credentials
        credentials.capabilities = [.share, .remoteControl]
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(credentials)) as? [String: Any])
        object["capabilities"] = ["share", "somethingNewer", "remoteControl"]
        let decoded = try JSONDecoder().decode(ServerCredentials.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.capabilities == [.share, .remoteControl])
    }
}

@Suite("Remote control: Jukebox as a controllable session", .serialized, .timeLimit(.minutes(3)))
struct RemoteControlTests {
    @Test("Messages as Jellyfin and Emby send them")
    func parse() {
        #expect(RemoteControlMessage.parse(#"{"MessageType":"ForceKeepAlive","Data":60}"#) == .keepAlive(60))
        #expect(RemoteControlMessage.parse(
            #"{"MessageType":"Play","Data":{"ItemIds":["a","b","c"],"StartIndex":1,"StartPositionTicks":50000000,"PlayCommand":"PlayNow"}}"#)
            == .play(ids: ["a", "b", "c"], startIndex: 1, position: 5, placement: .now))
        #expect(RemoteControlMessage.parse(#"{"MessageType":"Play","Data":{"ItemIds":[378,89],"PlayCommand":"PlayLast"}}"#)
            == .play(ids: ["378", "89"], startIndex: 0, position: 0, placement: .last))
        #expect(RemoteControlMessage.parse(#"{"MessageType":"Playstate","Data":{"Command":"PlayPause"}}"#) == .playPause)
        #expect(RemoteControlMessage.parse(#"{"MessageType":"Playstate","Data":{"Command":"Seek","SeekPositionTicks":120000000}}"#)
            == .seek(12))
        #expect(RemoteControlMessage.parse(#"{"MessageType":"GeneralCommand","Data":{"Name":"SetVolume","Arguments":{"Volume":"30"}}}"#)
            == .setVolume(0.3))
        #expect(RemoteControlMessage.parse(#"{"MessageType":"GeneralCommand","Data":{"Name":"DisplayMessage"}}"#) == nil)
        #expect(RemoteControlMessage.parse(#"{"MessageType":"Sessions","Data":[]}"#) == nil)
        #expect(RemoteControlMessage.parse("not json") == nil)
    }

    @Test("Jellyfin: this session offers itself, is listed to another, and its commands arrive",
          .enabled(if: JellyfinTestServer.url != nil))
    func jellyfin() async throws {
        try await roundTrip(url: try #require(JellyfinTestServer.url), isEmby: false)
    }

    @Test("Emby: the same", .enabled(if: EmbyTestServer.url != nil))
    func emby() async throws {
        try await roundTrip(url: try #require(EmbyTestServer.url), isEmby: true)
    }

    func roundTrip(url: URL, isEmby: Bool) async throws {
        let speaker = FeatureServers.identity("remote-speaker")
        let phone = FeatureServers.identity("remote-phone")
        let speakerClient = JellyfinClient(
            credentials: try await JellyfinClient(serverURL: url, identity: speaker, isEmby: isEmby)
                .signIn(username: "test", password: "test"),
            identity: speaker, isEmby: isEmby)
        let phoneClient = JellyfinClient(
            credentials: try await JellyfinClient(serverURL: url, identity: phone, isEmby: isEmby)
                .signIn(username: "test", password: "test"),
            identity: phone, isEmby: isEmby)
        defer { Task { await speakerClient.signOut(); await phoneClient.signOut() } }

        let socketURL = try #require(speakerClient.sessionSocketURL)
        #expect(socketURL.scheme == "ws")
        let socket = try ListeningSocket(host: try #require(socketURL.host), port: socketURL.port ?? 80,
                                         path: socketURL.path + "?" + (socketURL.query ?? ""))
        try await speakerClient.offerRemoteControl()

        var listed: RemoteSession?
        for _ in 0..<25 where listed == nil {
            listed = try await phoneClient.remoteSessions().first { $0.deviceID == speaker.deviceID }
            if listed == nil { try await Task.sleep(for: .milliseconds(200)) }
        }
        let session = try #require(listed, "the speaker is listed in the phone's Play On")

        // What the server sends first, then each command read as the app
        // reads it.
        func next() async throws -> RemoteControlCommand {
            for _ in 0..<20 {
                let text = try await Task.detached { try socket.receive() }.value
                if let command = RemoteControlMessage.parse(text), command != .keepAlive(60) {
                    if case .keepAlive = command {
                        JellyfinTestServer.measure("remote control (\(isEmby ? "Emby" : "Jellyfin")): \(text)")
                        continue
                    }
                    return command
                }
            }
            throw JellyfinError.decoding("no command came")
        }
        let ids = try await phoneClient.tracks(TrackQuery(limit: 3)).items.map(\.id)
        try await phoneClient.play(ids, startIndex: 2, at: 4, onSession: session.id)
        #expect(try await next() == .play(ids: ids, startIndex: 2, position: 4, placement: .now))
        try await phoneClient.send(.pause, toSession: session.id)
        #expect(try await next() == .pause)
        try await phoneClient.send(.next, toSession: session.id)
        #expect(try await next() == .next)
        try await phoneClient.seek(to: 7, onSession: session.id)
        #expect(try await next() == .seek(7))
        try await phoneClient.setVolume(0.25, onSession: session.id)
        #expect(try await next() == .setVolume(0.25))
        try await phoneClient.add([ids[0]], toSession: session.id)
        #expect(try await next() == .play(ids: [ids[0]], startIndex: 0, position: 0, placement: .last))

        // The speaker says what it plays with a progress report (no start:
        // that would count a play), and the phone reads it, volume too.
        await speakerClient.reportProgress(PlaybackReport(trackID: ids[1], position: 3, isPaused: true,
                                                          playSessionID: UUID().uuidString, volume: 0.4))
        let seen = try await phoneClient.remoteSession(id: session.id)
        #expect(seen?.nowPlayingID == ids[1])
        #expect(seen?.isPaused == true)
        #expect(seen?.volume == 0.4)
    }
}

@Suite("Your Year")
struct YourYearTests {
    static func track(_ id: String, artist: String, album: String, genres: [String]) -> Track {
        Track(id: id, name: "Song \(id)", albumID: album, albumName: "Album \(album)",
              artists: [ArtistRef(id: artist, name: artist)], genres: genres, duration: 200)
    }

    @Test("Tops by plays, minutes and months; another year and unknown songs counted rightly")
    func make() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ month: Int, _ year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: 10))!
        }
        let library = [
            "a": Self.track("a", artist: "Mira Lux", album: "x", genres: ["Rock; Shoegaze"]),
            "b": Self.track("b", artist: "Mira Lux", album: "x", genres: ["Rock"]),
            "c": Self.track("c", artist: "Blue Room Trio", album: "y", genres: ["Jazz"]),
        ]
        let plays = [
            YearPlay(trackID: "a", date: day(1), seconds: 120),
            YearPlay(trackID: "a", date: day(1), seconds: 120),
            YearPlay(trackID: "b", date: day(3), seconds: 60),
            YearPlay(trackID: "c", date: day(3), seconds: 600),
            YearPlay(trackID: "gone", date: day(12), seconds: 300),
            YearPlay(trackID: "c", date: day(5, 2025), seconds: 999),
        ]
        let year = YourYear.make(year: 2026, source: .server, plays: plays, track: { library[$0] }, calendar: calendar)
        #expect(year.plays == 5)
        #expect(year.minutes == 20)
        #expect(year.months == [4, 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 5])
        #expect(year.songs.map(\.id) == ["a", "c", "b"])
        #expect(year.artists.map(\.name) == ["Mira Lux", "Blue Room Trio"])
        #expect(year.artists.first?.plays == 3)
        #expect(year.albums.map(\.id) == ["x", "y"])
        #expect(year.genres.map(\.name) == ["Rock", "Shoegaze", "Jazz"])
        #expect(!year.isEmpty)
        #expect(YourYear.make(year: 2024, source: .thisDevice, plays: plays, track: { library[$0] }).isEmpty)
    }

    @Test("This device's history: what was heard, not skips or thumbs")
    func fromHistory() {
        var history = ListeningHistory()
        let now = Date()
        history.append(PlayEvent(trackID: "a", date: now, listened: 200, duration: 200, outcome: .completed))
        history.append(PlayEvent(trackID: "b", date: now, listened: 5, duration: 200, outcome: .skipped))
        history.append(PlayEvent(trackID: "a", date: now, listened: 0, duration: 200, outcome: .liked))
        history.append(PlayEvent(trackID: "c", date: now, listened: 90, duration: 200, outcome: .partial))
        #expect(YourYear.plays(from: history).map(\.trackID) == ["a", "c"])
    }

    @Test("Playback Reporting's dates", arguments: [("2026-11-18 19:12:12.4449127", true), ("nonsense", false)])
    func reportingDate(text: String, valid: Bool) {
        #expect((JellyfinClient.reportingDate(text) != nil) == valid)
    }
}

@Suite("Moods and tempo")
struct MoodEdgesTests {
    @Test("A song is near those that share its moods and tempo, and not the untagged")
    func edges() {
        let tracks = [
            Track(id: "rain", name: "Slow Rain", genres: ["Jazz"], moods: ["Melancholic", "Calm"], bpm: 72),
            Track(id: "harbour", name: "Grey Harbour", genres: ["Jazz"], moods: ["Melancholic"], bpm: 76),
            Track(id: "run", name: "Bright Run", genres: ["Jazz"], moods: ["Happy", "Energetic"], bpm: 140),
            Track(id: "plain", name: "No Tags", genres: ["Jazz"]),
        ]
        let graph = MoodEdges.graph(for: tracks)
        let near = graph.similarTracks(to: "rain")
        #expect(near.first?.key == "harbour")
        #expect(!near.contains { $0.key == "plain" })
        #expect(!near.contains { $0.key == "run" })
        #expect(near.allSatisfy { $0.weight <= MoodEdges.strongest })
        #expect(graph.similarTracks(to: "plain").isEmpty)
        #expect(MoodEdges.graph(for: [Track(id: "x", name: "x"), Track(id: "y", name: "y")]).similarTracks(to: "x").isEmpty)
    }
}
