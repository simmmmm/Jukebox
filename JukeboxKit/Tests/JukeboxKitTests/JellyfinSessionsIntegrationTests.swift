// Play On against the real Jellyfin of dev/jellyfin-test-server.sh: a second
// client of the same user, made here, is the device the music plays on. It
// signs in with a device of its own, opens the websocket Jellyfin sends
// commands over (without it the session is not controllable, measured;
// 12.4 refuses `api_key` there with 403, as on the audio routes) and
// says it plays audio; the kit's calls from the main test session must then
// arrive on that socket as Jellyfin's messages. Other agents share the
// server: the fake is found by its DeviceId, nothing counts sessions, and
// the fake signs out at the end.
//
// The socket is a few lines of POSIX here: Foundation's
// URLSessionWebSocketTask fails on Swift 6.2's Linux image with "WebSockets
// not supported by libcurl" (its libcurl is built without them).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Testing
@testable import JukeboxKit

/// A websocket client that only listens: the upgrade, then the server's
/// frames, which are never masked. Plain ws:// only, which the test server is.
final class ListeningSocket: @unchecked Sendable {
    private let fd: Int32

    init(host: String, port: Int, path: String) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        #if canImport(Glibc)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let address = info else {
            throw JellyfinError.transport("no address for \(host)")
        }
        defer { freeaddrinfo(info) }
        fd = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
        guard fd >= 0, connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 else {
            throw JellyfinError.transport("no connection to \(host):\(port)")
        }
        // A read gives up after 5 s rather than hang the test.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nUpgrade: websocket\r\n"
            + "Connection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        _ = request.withCString { send(fd, $0, strlen($0), 0) }
        // The 101 and its headers, up to the blank line.
        var head = Data()
        while !head.ends(with: "\r\n\r\n") { head.append(try read(1)) }
        guard String(decoding: head, as: UTF8.self).hasPrefix("HTTP/1.1 101") else {
            throw JellyfinError.transport("no upgrade: \(String(decoding: head, as: UTF8.self))")
        }
    }

    deinit { close(fd) }

    private func read(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var got = 0
        while got < count {
            let n = data.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + got, count - got, 0) }
            guard n > 0 else { throw JellyfinError.transport("the socket closed or timed out") }
            got += n
        }
        return data
    }

    /// The next text message (pings and the rest passed over).
    func receive() throws -> String {
        while true {
            let head = try read(2)
            let opcode = head[0] & 0x0f
            var length = Int(head[1] & 0x7f)
            if length == 126 {
                length = try read(2).reduce(0) { $0 << 8 | Int($1) }
            } else if length == 127 {
                length = try read(8).reduce(0) { $0 << 8 | Int($1) }
            }
            let payload = try read(length)
            if opcode == 1 { return String(decoding: payload, as: UTF8.self) }
            if opcode == 8 { throw JellyfinError.transport("the server closed the socket") }
        }
    }
}

private extension Data {
    func ends(with text: String) -> Bool { count >= text.utf8.count && suffix(text.utf8.count).elementsEqual(text.utf8) }
}

@Suite("Jellyfin: Play On on the real server", .serialized, .timeLimit(.minutes(1)),
       .enabled(if: JellyfinTestServer.url != nil))
struct JellyfinSessionsIntegrationTests {
    static let fakeDevice = "playon-kit-fake"

    struct Capabilities: Encodable, Sendable {
        var PlayableMediaTypes = ["Audio"]
        var SupportedCommands = ["SetVolume", "VolumeUp", "VolumeDown"]
        var SupportsMediaControl = true
    }

    /// The next message on the socket of `type` ("Play", "Playstate",
    /// "GeneralCommand"), its Data; keep-alives and the rest passed over.
    static func next(_ type: String, on socket: ListeningSocket) async throws -> [String: Any] {
        for _ in 0..<20 {
            let text = try await Task.detached { try socket.receive() }.value
            guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  object["MessageType"] as? String == type else { continue }
            return object["Data"] as? [String: Any] ?? [:]
        }
        throw JellyfinError.decoding("no \(type) message came")
    }

    /// A Play message's ids as text: Jellyfin sends strings, Emby 4.10 its
    /// numeric ids as JSON numbers ([378, 89, 279], measured).
    static func itemIDs(_ message: [String: Any]) -> [String]? {
        (message["ItemIds"] as? [Any])?.map { "\($0)" }
    }

    @Test("A second client with its socket is listed, and receives Play, Playstate and SetVolume")
    func remoteControl() async throws {
        let url = try #require(JellyfinTestServer.url)
        try await remoteControl(at: url, main: JellyfinTestServer.client(),
                                user: JellyfinTestServer.user, password: JellyfinTestServer.password, isEmby: false)
    }

    /// The same on the Emby of dev/emby-test-server.sh: its socket is
    /// `/embywebsocket?api_key=`, its Sessions API Jellyfin's.
    @Test("Emby: a second client with its socket is listed, and receives Play, Playstate and SetVolume",
          .enabled(if: EmbyTestServer.url != nil))
    func remoteControlOnEmby() async throws {
        let url = try #require(EmbyTestServer.url)
        let identity = EmbyTestServer.identity("play-on")
        let credentials = try await JellyfinClient(serverURL: url, identity: identity, isEmby: true)
            .signIn(username: EmbyTestServer.user, password: EmbyTestServer.password)
        let main = JellyfinClient(credentials: credentials, identity: identity, isEmby: true)
        try await remoteControl(at: url, main: main, user: EmbyTestServer.user, password: EmbyTestServer.password,
                                isEmby: true)
        await main.signOut()
    }

    func remoteControl(at url: URL, main: JellyfinClient, user: String, password: String, isEmby: Bool) async throws {
        let identity = ClientIdentity(clientName: "JukeboxKitTests", clientVersion: "1.0",
                                      deviceName: "Kit tests: Play On speaker", deviceID: Self.fakeDevice)
        let credentials = try await JellyfinClient(serverURL: url, identity: identity, isEmby: isEmby)
            .signIn(username: user, password: password)
        let fake = JellyfinClient(credentials: credentials, identity: identity, isEmby: isEmby)
        // Signed out whatever happens, so no fake session stays on the server.
        do {
            try await drive(main: main, fake: fake, server: url)
        } catch {
            await fake.signOut()
            throw error
        }
        await fake.signOut()
    }

    func drive(main: JellyfinClient, fake: JellyfinClient, server url: URL) async throws {
        let host = try #require(url.host)
        let socket = try ListeningSocket(host: host, port: url.port ?? 80,
                                         path: fake.sessionSocketPath(deviceID: Self.fakeDevice))
        try await fake.send("POST", "/Sessions/Capabilities/Full", json: Capabilities())

        // Listed once the server has both the socket and the capabilities.
        var listed: RemoteSession?
        for _ in 0..<25 where listed == nil {
            listed = try await main.remoteSessions().first { $0.deviceID == Self.fakeDevice }
            if listed == nil { try await Task.sleep(for: .milliseconds(200)) }
        }
        let session = try #require(listed, "the fake session with its socket is listed")
        #expect(session.deviceName == "Kit tests: Play On speaker")
        #expect(session.client == "JukeboxKitTests")

        let ids = try await main.tracks(TrackQuery(limit: 3)).items.map(\.id)
        try #require(ids.count == 3)
        try await main.play(ids, startIndex: 1, at: 5, onSession: session.id)
        let play = try await Self.next("Play", on: socket)
        #expect(Self.itemIDs(play) == ids)
        #expect(play["StartIndex"] as? Int == 1)
        #expect((play["StartPositionTicks"] as? NSNumber)?.int64Value == 50_000_000)
        #expect(play["PlayCommand"] as? String == "PlayNow")

        try await main.send(.pause, toSession: session.id)
        #expect(try await Self.next("Playstate", on: socket)["Command"] as? String == "Pause")
        try await main.seek(to: 12, onSession: session.id)
        let seek = try await Self.next("Playstate", on: socket)
        #expect(seek["Command"] as? String == "Seek")
        #expect((seek["SeekPositionTicks"] as? NSNumber)?.int64Value == 120_000_000)
        try await main.setVolume(0.3, onSession: session.id)
        let volume = try await Self.next("GeneralCommand", on: socket)
        #expect(volume["Name"] as? String == "SetVolume")
        #expect((volume["Arguments"] as? [String: Any])?["Volume"] as? String == "30")
        try await main.add([ids[0]], toSession: session.id)
        let add = try await Self.next("Play", on: socket)
        #expect(add["PlayCommand"] as? String == "PlayLast")
        #expect(Self.itemIDs(add) == [ids[0]])

        // The far client says what it plays, as a real one would: the kit
        // reads it back. (A start report counts a play; ids[1] is the
        // library's second by name, as good as any.)
        let report = PlaybackReport(trackID: ids[1], position: 5, isPaused: false, playSessionID: UUID().uuidString)
        await fake.reportStart(report)
        let playing = try await main.remoteSession(id: session.id)
        #expect(playing?.nowPlayingID == ids[1])
        await fake.reportStopped(report)
        JellyfinTestServer.measure("play-on: \(session.client) listed with its socket; Play, Playstate, GeneralCommand came")
    }
}
