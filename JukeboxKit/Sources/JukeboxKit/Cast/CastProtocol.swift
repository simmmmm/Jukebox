// Google Cast's own protocol (castv2), the sender's side, for the clients
// that have no Cast SDK of Google's: Linux, and the Mac (Google's sender
// SDKs are Android, iOS and Chrome only). A Chromecast listens on TLS port
// 8009; every message is a 4-byte big-endian length and a protobuf
// CastMessage, whose payload is JSON on a namespace. Jukebox needs six of
// the protobuf's fields and only string payloads, so they are encoded by
// hand here rather than with a protobuf library.
//
// No I/O: CastSession takes what came and says what to send. The platform
// owns the socket (Linux/App/Cast.swift: GIO's TLS), so this file is the
// same on every client and is tested on Linux (CastProtocolTests).
//
// The receiver is the Default Media Receiver (app id CC1AD845): Google's
// own, needing no registration, which plays an http(s) address of MP3, AAC
// or FLAC it fetches itself.

import Foundation

/// One castv2 envelope with a JSON (string) payload.
public struct CastMessage: Sendable, Hashable {
    public var source: String
    public var destination: String
    public var namespace: String
    public var payload: String

    public init(source: String, destination: String, namespace: String, payload: String) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }
}

public enum CastFrameError: Error, Sendable, Equatable {
    /// A frame longer than a receiver ever sends (64 KiB is Cast's own limit).
    case tooLong(Int)
    case malformed
}

public enum CastFrame {
    /// Cast's limit on a message: more is not a receiver talking.
    static let maximumLength = 64 * 1024

    /// 4-byte big-endian length, then the protobuf CastMessage:
    /// protocol_version (1, varint, CASTV2_1_0 = 0), source_id (2),
    /// destination_id (3), namespace (4), payload_type (5, STRING = 0),
    /// payload_utf8 (6).
    public static func encode(_ message: CastMessage) -> Data {
        var body = Data()
        body.append(contentsOf: [0x08, 0x00])
        appendString(2, message.source, to: &body)
        appendString(3, message.destination, to: &body)
        appendString(4, message.namespace, to: &body)
        body.append(contentsOf: [0x28, 0x00])
        appendString(6, message.payload, to: &body)
        let length = UInt32(body.count)
        var frame = Data([UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF),
                          UInt8(length & 0xFF)])
        frame.append(body)
        return frame
    }

    /// Every whole frame off the front of `buffer`; a partial one is left
    /// there for the next bytes. Unknown fields are skipped, and a frame
    /// with a binary payload (field 7, used by device authentication) is
    /// dropped: Jukebox sends and reads only JSON.
    public static func take(from buffer: inout Data) throws -> [CastMessage] {
        var messages: [CastMessage] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = Int(buffer[start]) << 24 | Int(buffer[start + 1]) << 16
                | Int(buffer[start + 2]) << 8 | Int(buffer[start + 3])
            guard length <= maximumLength else { throw CastFrameError.tooLong(length) }
            guard buffer.count >= 4 + length else { break }
            let body = Data(buffer[(start + 4)..<(start + 4 + length)])
            buffer = Data(buffer[(start + 4 + length)...])
            if let message = try decode(body) { messages.append(message) }
        }
        return messages
    }

    static func decode(_ body: Data) throws -> CastMessage? {
        let bytes = [UInt8](body)
        var at = 0
        var strings: [Int: String] = [:]
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard at < bytes.count, shift < 64 else { throw CastFrameError.malformed }
                let byte = bytes[at]
                at += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
        }
        while at < bytes.count {
            let key = try varint()
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                _ = try varint()
            case 2:
                let count = Int(try varint())
                guard count >= 0, at + count <= bytes.count else { throw CastFrameError.malformed }
                if field != 7 {
                    guard let text = String(bytes: bytes[at..<(at + count)], encoding: .utf8) else {
                        throw CastFrameError.malformed
                    }
                    strings[field] = text
                }
                at += count
            case 1:
                guard at + 8 <= bytes.count else { throw CastFrameError.malformed }
                at += 8
            case 5:
                guard at + 4 <= bytes.count else { throw CastFrameError.malformed }
                at += 4
            default:
                throw CastFrameError.malformed
            }
        }
        guard let payload = strings[6] else { return nil }
        return CastMessage(source: strings[2] ?? "", destination: strings[3] ?? "",
                           namespace: strings[4] ?? "", payload: payload)
    }

    private static func appendString(_ field: UInt8, _ text: String, to data: inout Data) {
        data.append(field << 3 | 2)
        var count = UInt64(text.utf8.count)
        while count >= 0x80 {
            data.append(UInt8(count & 0x7F) | 0x80)
            count >>= 7
        }
        data.append(UInt8(count))
        data.append(contentsOf: Array(text.utf8))
    }
}

/// What to play: an address the receiver fetches itself, token included.
public struct CastMedia: Sendable, Hashable {
    public var url: URL
    public var contentType: String
    public var title: String
    public var artist: String?
    public var album: String?
    public var artworkURL: URL?
    public var duration: TimeInterval?

    public init(url: URL, contentType: String, title: String, artist: String? = nil, album: String? = nil,
                artworkURL: URL? = nil, duration: TimeInterval? = nil) {
        self.url = url
        self.contentType = contentType
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
    }
}

/// The receiver's MEDIA_STATUS, the part a player needs.
public struct CastMediaStatus: Sendable, Hashable {
    public enum State: String, Sendable {
        case idle = "IDLE"
        case playing = "PLAYING"
        case paused = "PAUSED"
        case buffering = "BUFFERING"
    }

    public var state: State
    /// With `idle`: FINISHED (it played to the end), CANCELLED,
    /// INTERRUPTED (another load), ERROR.
    public var idleReason: String?
    public var currentTime: TimeInterval
    public var mediaSessionID: Int?
    public var duration: TimeInterval?
}

/// One sender's conversation with a receiver, without I/O: the platform
/// reads and writes the bytes, sending what each call returns, in order.
public struct CastSession: Sendable {
    public static let defaultMediaReceiver = "CC1AD845"
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let mediaNamespace = "urn:x-cast:com.google.cast.media"

    public private(set) var media: CastMediaStatus?
    public private(set) var volume: Double?
    public private(set) var isClosed = false
    public private(set) var loadError: String?

    let senderID: String
    /// The Default Media Receiver's session, once RECEIVER_STATUS named it.
    var transportID: String?
    var requestID = 0
    /// A LOAD asked for before the receiver's app was up.
    var waitingLoad: [String: any Sendable]?
    var launched = false

    public init(senderID: String = "sender-jukebox") {
        self.senderID = senderID
    }

    /// CONNECT to receiver-0, then LAUNCH the Default Media Receiver.
    public mutating func start() -> [CastMessage] {
        launched = true
        return [message(to: "receiver-0", Self.connection, ["type": "CONNECT"]),
                request(to: "receiver-0", Self.receiver, ["type": "LAUNCH", "appId": Self.defaultMediaReceiver])]
    }

    public mutating func receive(_ incoming: CastMessage) -> [CastMessage] {
        guard let data = incoming.payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return [] }
        switch type {
        case "PING":
            return [message(to: incoming.source, Self.heartbeat, ["type": "PONG"])]
        case "CLOSE":
            // The receiver's app closed our virtual connection (another
            // sender cast, or the TV was switched to something else).
            if incoming.source == transportID || incoming.source == "receiver-0" { isClosed = true }
            return []
        case "RECEIVER_STATUS":
            return receiverStatus(json["status"] as? [String: Any] ?? [:])
        case "MEDIA_STATUS":
            mediaStatus(json["status"] as? [[String: Any]] ?? [])
            return []
        case "LOAD_FAILED", "LOAD_CANCELLED", "INVALID_REQUEST":
            loadError = (json["reason"] as? String) ?? type
            return []
        default:
            return []
        }
    }

    public mutating func load(_ media: CastMedia, at position: TimeInterval, autoplay: Bool) -> [CastMessage] {
        var metadata: [String: any Sendable] = ["metadataType": 3, "title": media.title]
        if let artist = media.artist { metadata["artist"] = artist }
        if let album = media.album { metadata["albumName"] = album }
        if let artwork = media.artworkURL { metadata["images"] = [["url": artwork.absoluteString]] }
        var item: [String: any Sendable] = ["contentId": media.url.absoluteString,
                                            "contentType": media.contentType,
                                            "streamType": "BUFFERED", "metadata": metadata]
        if let duration = media.duration, duration > 0 { item["duration"] = duration }
        let body: [String: any Sendable] = ["type": "LOAD", "media": item, "autoplay": autoplay,
                                            "currentTime": max(0, position)]
        loadError = nil
        guard let transportID else {
            waitingLoad = body
            return []
        }
        return [request(to: transportID, Self.mediaNamespace, body)]
    }

    public mutating func play() -> [CastMessage] { mediaCommand(["type": "PLAY"]) }
    public mutating func pause() -> [CastMessage] { mediaCommand(["type": "PAUSE"]) }
    public mutating func stop() -> [CastMessage] { mediaCommand(["type": "STOP"]) }

    public mutating func seek(to position: TimeInterval) -> [CastMessage] {
        mediaCommand(["type": "SEEK", "currentTime": max(0, position)])
    }

    /// The receiver's own volume, 0...1: the TV's or the speaker's.
    public mutating func setVolume(_ level: Double) -> [CastMessage] {
        [request(to: "receiver-0", Self.receiver,
                 ["type": "SET_VOLUME", "volume": ["level": min(1, max(0, level))]])]
    }

    /// Every 5 s: a receiver closes a connection that has been quiet for 10.
    public func ping() -> CastMessage {
        message(to: "receiver-0", Self.heartbeat, ["type": "PING"])
    }

    // MARK: Inside

    private mutating func receiverStatus(_ status: [String: Any]) -> [CastMessage] {
        if let level = (status["volume"] as? [String: Any])?["level"] as? Double { volume = level }
        let apps = status["applications"] as? [[String: Any]] ?? []
        let ours = apps.first { $0["appId"] as? String == Self.defaultMediaReceiver }
        guard let transport = ours?["transportId"] as? String else {
            // The app we launched is gone (the TV went to something else).
            if transportID != nil { isClosed = true }
            return []
        }
        guard transport != transportID else { return [] }
        transportID = transport
        var out = [message(to: transport, Self.connection, ["type": "CONNECT"])]
        if let waiting = waitingLoad {
            waitingLoad = nil
            out.append(request(to: transport, Self.mediaNamespace, waiting))
        }
        return out
    }

    private mutating func mediaStatus(_ statuses: [[String: Any]]) {
        // An empty list: no media session (after STOP, or before any LOAD).
        guard let status = statuses.first else {
            media = nil
            return
        }
        let state = (status["playerState"] as? String).flatMap(CastMediaStatus.State.init) ?? .idle
        let duration = (status["media"] as? [String: Any])?["duration"] as? Double
        media = CastMediaStatus(state: state, idleReason: status["idleReason"] as? String,
                                currentTime: status["currentTime"] as? Double ?? media?.currentTime ?? 0,
                                mediaSessionID: status["mediaSessionId"] as? Int ?? media?.mediaSessionID,
                                duration: duration ?? media?.duration)
    }

    /// A command to the media session; nothing before there is one.
    private mutating func mediaCommand(_ body: [String: any Sendable]) -> [CastMessage] {
        guard let transportID, let session = media?.mediaSessionID else { return [] }
        var body = body
        body["mediaSessionId"] = session
        return [request(to: transportID, Self.mediaNamespace, body)]
    }

    private mutating func request(to destination: String, _ namespace: String,
                                  _ body: [String: any Sendable]) -> CastMessage {
        requestID += 1
        var body = body
        body["requestId"] = requestID
        return message(to: destination, namespace, body)
    }

    private func message(to destination: String, _ namespace: String, _ body: [String: any Sendable]) -> CastMessage {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        return CastMessage(source: senderID, destination: destination, namespace: namespace,
                           payload: String(decoding: data, as: UTF8.self))
    }
}
