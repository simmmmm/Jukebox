import Foundation
import Testing
@testable import JukeboxKit

@Suite struct CastProtocolTests {
    private func json(_ message: CastMessage) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(message.payload.utf8))) as? [String: Any] ?? [:]
    }

    private func incoming(_ source: String, _ namespace: String, _ payload: String) -> CastMessage {
        CastMessage(source: source, destination: "sender-jukebox", namespace: namespace, payload: payload)
    }

    @Test func encodesTheFieldsByHand() {
        let frame = CastFrame.encode(CastMessage(source: "s", destination: "d", namespace: "n", payload: "{}"))
        // 08 00 | 12 01 's' | 1a 01 'd' | 22 01 'n' | 28 00 | 32 02 '{' '}': 17 bytes.
        let body: [UInt8] = [0x08, 0x00, 0x12, 0x01, 0x73, 0x1A, 0x01, 0x64, 0x22, 0x01, 0x6E,
                             0x28, 0x00, 0x32, 0x02, 0x7B, 0x7D]
        #expect([UInt8](frame) == [0, 0, 0, 17] + body)
    }

    @Test func aLongPayloadHasAVarintLength() throws {
        let payload = String(repeating: "x", count: 300)
        var frame = CastFrame.encode(CastMessage(source: "a", destination: "b", namespace: "c", payload: payload))
        // 300 = 0xAC 0x02 as a varint.
        let bytes = [UInt8](frame)
        let at = bytes.firstIndex(of: 0x32)!
        #expect(bytes[at + 1] == 0xAC && bytes[at + 2] == 0x02)
        let back = try CastFrame.take(from: &frame)
        #expect(back.first?.payload == payload)
        #expect(frame.isEmpty)
    }

    @Test func framesSplitAnywhereComeWhole() throws {
        let one = CastMessage(source: "sender-0", destination: "receiver-0", namespace: "urn:x", payload: #"{"a":1}"#)
        let two = CastMessage(source: "x", destination: "y", namespace: "z", payload: "{}")
        let all = CastFrame.encode(one) + CastFrame.encode(two)
        for cut in 0...all.count {
            var buffer = Data(all.prefix(cut))
            var got = try CastFrame.take(from: &buffer)
            buffer.append(all.dropFirst(cut))
            got += try CastFrame.take(from: &buffer)
            #expect(got == [one, two])
            #expect(buffer.isEmpty)
        }
    }

    @Test func refusesWhatIsNotAReceiver() {
        var huge = Data([0x00, 0x10, 0x00, 0x01])
        #expect(throws: CastFrameError.tooLong(0x100001)) { try CastFrame.take(from: &huge) }
        var bad = Data([0, 0, 0, 2, 0x12, 0x05])
        #expect(throws: CastFrameError.malformed) { try CastFrame.take(from: &bad) }
    }

    @Test func aBrokenFrameIsAnErrorNotACrash() {
        let frames: [[UInt8]] = [
            // A string whose length is UInt64's top: once a trap in Int(_:).
            [0, 0, 0, 12, 0x32, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00],
            // Int.max: once an overflow in `at + count`.
            [0, 0, 0, 11, 0x32, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x00],
            // One byte longer than the frame.
            [0, 0, 0, 4, 0x32, 0x03, 0x7B, 0x7D],
            // A varint that never ends.
            [0, 0, 0, 3, 0x32, 0x80, 0x80],
            // An eleven-byte varint: more than 64 bits.
            [0, 0, 0, 11, 0x08, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80],
            // Fixed 64- and 32-bit fields cut short.
            [0, 0, 0, 3, 0x09, 0x00, 0x00],
            [0, 0, 0, 2, 0x0D, 0x00],
        ]
        for frame in frames {
            var buffer = Data(frame)
            #expect(throws: CastFrameError.malformed) { try CastFrame.take(from: &buffer) }
        }
        // Just past Cast's 64 KiB: refused before any of it is waited for.
        var long = Data([0x00, 0x01, 0x00, 0x01])
        #expect(throws: CastFrameError.tooLong(0x10001)) { try CastFrame.take(from: &long) }
    }

    @Test func skipsUnknownFieldsAndBinaryPayloads() throws {
        // A binary-payload frame (payload_type 1, payload_binary field 7).
        var binary = Data([0, 0, 0, 8, 0x08, 0x00, 0x28, 0x01, 0x3A, 0x02, 0x01, 0x02])
        #expect(try CastFrame.take(from: &binary).isEmpty)
        // An unknown varint field 9 before the payload.
        var extra = Data([0, 0, 0, 6, 0x48, 0x05, 0x32, 0x02, 0x7B, 0x7D])
        #expect(try CastFrame.take(from: &extra).first?.payload == "{}")
    }

    @Test func aConversation() throws {
        var session = CastSession()
        let start = session.start()
        #expect(start.map { json($0)["type"] as? String } == ["CONNECT", "LAUNCH"])
        #expect(json(start[1])["appId"] as? String == "CC1AD845")

        let media = CastMedia(url: URL(string: "http://music.local/a.mp3?ApiKey=t")!, contentType: "audio/mpeg",
                              title: "Song", artist: "Artist", album: "Album",
                              artworkURL: URL(string: "http://music.local/a.jpg"), duration: 180)
        // Asked before the receiver's app is up: held.
        #expect(session.load(media, at: 12, autoplay: true).isEmpty)

        let status = #"{"type":"RECEIVER_STATUS","requestId":2,"status":{"volume":{"level":0.4,"muted":false},"#
            + #""applications":[{"appId":"CC1AD845","transportId":"web-7","sessionId":"x"}]}}"#
        let flushed = session.receive(incoming("receiver-0", CastSession.receiver, status))
        #expect(session.volume == 0.4)
        #expect(flushed.map(\.destination) == ["web-7", "web-7"])
        #expect(json(flushed[0])["type"] as? String == "CONNECT")
        let load = json(flushed[1])
        #expect(load["type"] as? String == "LOAD")
        #expect(load["currentTime"] as? Double == 12)
        let item = load["media"] as? [String: Any]
        #expect(item?["contentId"] as? String == "http://music.local/a.mp3?ApiKey=t")
        #expect(item?["streamType"] as? String == "BUFFERED")
        #expect((item?["metadata"] as? [String: Any])?["metadataType"] as? Int == 3)
        #expect((item?["metadata"] as? [String: Any])?["albumName"] as? String == "Album")
        // Request ids go up.
        #expect((json(start[1])["requestId"] as? Int ?? 0) < (load["requestId"] as? Int ?? 0))

        // The same status again connects nothing twice.
        #expect(session.receive(incoming("receiver-0", CastSession.receiver, status)).isEmpty)

        // No media session yet: nothing to pause.
        #expect(session.pause().isEmpty)
        let playing = #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":5,"playerState":"PLAYING","#
            + #""currentTime":13.5,"media":{"duration":180.0}}]}"#
        _ = session.receive(incoming("web-7", CastSession.mediaNamespace, playing))
        #expect(session.media?.state == .playing)
        #expect(session.media?.currentTime == 13.5)
        #expect(session.media?.duration == 180)
        let pause = session.pause()
        #expect(json(pause[0])["mediaSessionId"] as? Int == 5)
        #expect(json(session.seek(to: 60)[0])["currentTime"] as? Double == 60)
        let volume = session.setVolume(1.5)
        #expect(volume[0].destination == "receiver-0")
        #expect((json(volume[0])["volume"] as? [String: Any])?["level"] as? Double == 1)

        let finished = #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":5,"playerState":"IDLE","#
            + #""idleReason":"FINISHED"}]}"#
        _ = session.receive(incoming("web-7", CastSession.mediaNamespace, finished))
        #expect(session.media?.state == .idle)
        #expect(session.media?.idleReason == "FINISHED")
        // The place is kept where a status leaves it out.
        #expect(session.media?.currentTime == 13.5)
        #expect(!session.isClosed)
    }

    @Test func pingIsAnsweredAndCloseIsHeard() {
        var session = CastSession()
        let pong = session.receive(incoming("receiver-0", CastSession.heartbeat, #"{"type":"PING"}"#))
        #expect(pong.count == 1 && json(pong[0])["type"] as? String == "PONG" && pong[0].destination == "receiver-0")
        #expect(json(session.ping())["type"] as? String == "PING")

        _ = session.start()
        let up = #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"t1"}]}}"#
        _ = session.receive(incoming("receiver-0", CastSession.receiver, up))
        _ = session.receive(incoming("t1", CastSession.connection, #"{"type":"CLOSE"}"#))
        #expect(session.isClosed)

        // Our app gone from the receiver (the TV went to something else).
        var other = CastSession()
        _ = other.start()
        _ = other.receive(incoming("receiver-0", CastSession.receiver, up))
        _ = other.receive(incoming("receiver-0", CastSession.receiver,
                                   #"{"type":"RECEIVER_STATUS","status":{"applications":[]}}"#))
        #expect(other.isClosed)

        var failing = CastSession()
        _ = failing.receive(incoming("t1", CastSession.mediaNamespace, #"{"type":"LOAD_FAILED","requestId":3}"#))
        #expect(failing.loadError == "LOAD_FAILED")
    }
}
