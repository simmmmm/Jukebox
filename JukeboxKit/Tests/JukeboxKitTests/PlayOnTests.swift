// Play On's calls without a server: Jellyfin's Sessions API, the Subsonic
// jukebox and the cast URLs, request by request. The real Jellyfin's side
// is JellyfinSessionsIntegrationTests.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Play On: the servers' calls")
struct PlayOnTests {
    typealias F = JellyfinFixtures

    /// Three sessions as 12.4 lists them: a controllable web client playing,
    /// one without remote control, and this device's own.
    static let sessions = #"""
    [
      {"Id": "s-web", "DeviceName": "Living Room", "Client": "Jellyfin Web", "DeviceId": "tv-1",
       "SupportsRemoteControl": true, "PlayableMediaTypes": ["Audio", "Video"],
       "NowPlayingItem": {"Id": "track-7", "Name": "Blue Parade"},
       "PlayState": {"PositionTicks": 125000000, "IsPaused": true, "VolumeLevel": 40}},
      {"Id": "s-cli", "DeviceName": "cli", "Client": "curl", "DeviceId": "x",
       "SupportsRemoteControl": false, "PlayableMediaTypes": ["Audio"]},
      {"Id": "s-self", "DeviceName": "Test iPhone", "Client": "Jukebox", "DeviceId": "device-1",
       "SupportsRemoteControl": true, "PlayableMediaTypes": ["Audio"]},
      {"Id": "s-video", "DeviceName": "Box", "Client": "Kodi", "DeviceId": "k",
       "SupportsRemoteControl": true, "PlayableMediaTypes": ["Video"]}
    ]
    """#

    @Test("Sessions: only controllable audio sessions of others, with what they play")
    func listing() async throws {
        let transport = JellyfinMockTransport { _ in JellyfinMockTransport.respond(200, Self.sessions) }
        let sessions = try await F.client(transport).remoteSessions()
        #expect(sessions == [RemoteSession(id: "s-web", deviceName: "Living Room", client: "Jellyfin Web",
                                           deviceID: "tv-1", nowPlayingID: "track-7", position: 12.5,
                                           isPaused: true, volume: 0.4)])
        let request = try #require(transport.requests.first)
        #expect(request.jellyfinPath == "/jellyfin/Sessions")
        #expect(request.jellyfinQuery["controllableByUserId"] == F.userID)
        #expect(try await F.client(transport).remoteSession(id: "s-gone") == nil)
    }

    @Test("Play, add, commands, seek and volume: their routes and arguments")
    func commands() async throws {
        let transport = JellyfinMockTransport { _ in JellyfinMockTransport.respond(204) }
        let client = F.client(transport)
        try await client.play(["a", "b", "c"], startIndex: 1, at: 5, onSession: "s 1")
        try await client.add(["d"], toSession: "s1")
        try await client.send(.next, toSession: "s1")
        try await client.seek(to: 61.5, onSession: "s1")
        try await client.setVolume(0.555, onSession: "s1")
        let sent = transport.requests
        #expect(sent.allSatisfy { $0.httpMethod == "POST" })
        #expect(sent[0].jellyfinPath == "/jellyfin/Sessions/s%201/Playing")
        #expect(sent[0].jellyfinQuery == ["playCommand": "PlayNow", "itemIds": "a,b,c", "startIndex": "1",
                                          "startPositionTicks": "50000000"])
        #expect(sent[1].jellyfinQuery["playCommand"] == "PlayLast")
        #expect(sent[1].jellyfinQuery["itemIds"] == "d")
        #expect(sent[2].jellyfinPath == "/jellyfin/Sessions/s1/Playing/NextTrack")
        #expect(sent[3].jellyfinPath == "/jellyfin/Sessions/s1/Playing/Seek")
        #expect(sent[3].jellyfinQuery["seekPositionTicks"] == "615000000")
        #expect(sent[4].jellyfinPath == "/jellyfin/Sessions/s1/Command")
        #expect(sent[4].jellyfinBody["Name"] as? String == "SetVolume")
        #expect((sent[4].jellyfinBody["Arguments"] as? [String: String])?["Volume"] == "56")
        // From the start: no position sent.
        try await client.play(["a"], startIndex: 0, at: 0, onSession: "s1")
        #expect(transport.requests.last?.jellyfinQuery["startPositionTicks"] == nil)
    }

    @Test("Jellyfin's cast URL: a plain file, FLAC as it is, the rest MP3; the token in the query")
    func jellyfinCast() throws {
        let client = F.client(JellyfinMockTransport { _ in JellyfinMockTransport.respond(200) })
        var track = Track(id: "t1", name: "x", artists: [], genres: [], duration: 60)
        track.container = "flac"
        let flac = client.castURL(for: track)
        #expect(flac.contentType == "audio/flac")
        let query = URLRequest(url: flac.url).jellyfinQuery
        #expect(query["Container"] == "mp3,flac")
        #expect(query["TranscodingProtocol"] == "http")
        #expect(query["TranscodingContainer"] == "mp3")
        #expect(query["ApiKey"] == F.token)
        #expect(flac.url.path.hasSuffix("/Audio/t1/universal"))
        for container in [nil, "mp3", "mov,mp4,m4a,3gp,3g2,mj2"] {
            track.container = container
            let stream = client.castURL(for: track)
            #expect(stream.contentType == "audio/mpeg")
            #expect(URLRequest(url: stream.url).jellyfinQuery["Container"] == "mp3")
        }
    }

    @Test("A Jellyfin track keeps its container")
    func jellyfinContainer() throws {
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(F.track.utf8))
        #expect(item.asTrack()?.container == "mov,mp4,m4a,3gp,3g2,mj2")
    }

    @Test("Subsonic's cast URL: MP3, FLAC and AAC raw, anything else MP3 at 320")
    func subsonicCast() {
        let client = SubsonicFixtures.client(SubsonicFake())
        var track = Track(id: "s1", name: "x", artists: [], genres: [], duration: 60)
        for (suffix, type) in [("mp3", "audio/mpeg"), ("flac", "audio/flac"), ("aac", "audio/aac")] {
            track.container = suffix
            let stream = client.castURL(for: track)
            #expect(stream.contentType == type)
            #expect(stream.url.query?.contains("format=raw") == true)
        }
        for suffix in [nil, "m4a", "opus", "wav"] {
            track.container = suffix
            let stream = client.castURL(for: track)
            #expect(stream.contentType == "audio/mpeg")
            #expect(stream.url.query?.contains("format=mp3") == true)
            #expect(stream.url.query?.contains("maxBitRate=320") == true)
        }
    }

    @Test("Jukebox: each action's query, the status read, -1 as none")
    func jukebox() async throws {
        let fake = SubsonicFake()
        fake.on("jukeboxControl") { request in
            let status = request.value("action") == "status"
                ? #""jukeboxStatus":{"currentIndex":2,"playing":true,"gain":0.75,"position":31}"#
                : #""jukeboxStatus":{"currentIndex":-1,"playing":false,"gain":0.5,"position":0}"#
            return HTTPResponse(status: 200, body: Data(SubsonicFixtures.ok(status).utf8))
        }
        let client = SubsonicFixtures.client(fake)
        #expect(try await client.jukeboxStatus() == JukeboxStatus(currentIndex: 2, playing: true, gain: 0.75,
                                                                  position: 31))
        try await client.jukeboxSet(["a", "b"])
        try await client.jukeboxAdd(["c"])
        try await client.jukeboxSkip(to: 1, offset: 12.7)
        try await client.jukeboxStart()
        try await client.jukeboxStop()
        try await client.jukeboxGain(1.4)
        let sent = fake.requests("jukeboxControl")
        #expect(sent.map { $0.value("action") } == ["status", "set", "add", "skip", "start", "stop", "setGain"])
        #expect(sent[1].values("id") == ["a", "b"])
        #expect(sent[2].values("id") == ["c"])
        #expect(sent[3].value("index") == "1" && sent[3].value("offset") == "12")
        #expect(sent[6].value("gain") == "1.0")
    }

    @Test("Jukebox: offered only with the role and a status that answers")
    func jukeboxAvailable() async throws {
        let withRole = SubsonicFixtures.user.replacingOccurrences(of: #""jukeboxRole":false"#,
                                                                   with: #""jukeboxRole":true"#)
        // The role, the jukebox on.
        let on = SubsonicFake()
        on.on("getUser", ok: withRole)
        on.on("jukeboxControl", ok: #""jukeboxStatus":{"currentIndex":-1,"playing":false,"gain":1,"position":0}"#)
        #expect(await SubsonicFixtures.client(on).jukeboxAvailable())
        // The role, the jukebox off: Navidrome answers with an error.
        let off = SubsonicFake()
        off.on("getUser", ok: withRole)
        off.on("jukeboxControl", body: SubsonicFixtures.failed(0, "Jukebox is disabled"))
        #expect(await !SubsonicFixtures.client(off).jukeboxAvailable())
        // No role: the jukebox is not even asked.
        let none = SubsonicFake()
        none.on("getUser", ok: SubsonicFixtures.user)
        #expect(await !SubsonicFixtures.client(none).jukeboxAvailable())
        #expect(none.requests("jukeboxControl").isEmpty)
    }
}
