// Play On, on Jellyfin: the user's other Jellyfin clients (the web app on a
// TV, Jellyfin Media Player, another phone) play what Jukebox sends them,
// through the server's Sessions API. The server passes each command to the
// client over that client's websocket, so only a client with one open is
// listed: measured on 12.4 (17 November 2026), a session that only posted
// /Sessions/Capabilities/Full had SupportsRemoteControl false, and true
// once its socket was open. Another Jukebox is listed too, where it keeps
// its socket open (RemoteControl.swift). The far client reports its own
// plays to the server.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Another Jellyfin client of the same user that can be told what to play.
public struct RemoteSession: Sendable, Hashable, Identifiable {
    /// Jellyfin's session id.
    public var id: String
    public var deviceName: String
    /// "Jellyfin Web", "Jellyfin Media Player".
    public var client: String
    public var deviceID: String
    public var nowPlayingID: ItemID?
    public var position: TimeInterval
    public var isPaused: Bool
    /// 0...1; nil when the client says nothing of it.
    public var volume: Double?

    public init(id: String, deviceName: String, client: String, deviceID: String, nowPlayingID: ItemID? = nil,
                position: TimeInterval = 0, isPaused: Bool = false, volume: Double? = nil) {
        self.id = id
        self.deviceName = deviceName
        self.client = client
        self.deviceID = deviceID
        self.nowPlayingID = nowPlayingID
        self.position = position
        self.isPaused = isPaused
        self.volume = volume
    }
}

/// Jellyfin's Playstate commands, by their names in the route.
public enum RemoteCommand: String, Sendable {
    case pause = "Pause"
    case unpause = "Unpause"
    case stop = "Stop"
    case next = "NextTrack"
    case previous = "PreviousTrack"
}

extension JellyfinClient {
    /// GET /Sessions?controllableByUserId=: the sessions this user may
    /// control. Only those that take remote control and play audio, and
    /// never this device's own (the server leaves out the asking session,
    /// not its other tokens).
    public func remoteSessions() async throws -> [RemoteSession] {
        let user = try requireUser()
        let sessions = try await get([JellyfinSession].self, "/Sessions",
                                     query: [URLQueryItem(name: "controllableByUserId", value: user)], timeout: 10)
        return sessions.compactMap { session in
            guard session.supportsRemoteControl == true,
                  session.playableMediaTypes?.contains("Audio") == true,
                  session.deviceID != identity.deviceID else { return nil }
            return session.asRemoteSession()
        }
    }

    /// The session as it is now: what it plays, where, paused or not. Nil
    /// when it is gone (closed, or no longer controllable).
    public func remoteSession(id: String) async throws -> RemoteSession? {
        try await remoteSessions().first { $0.id == id }
    }

    /// POST /Sessions/{id}/Playing?playCommand=PlayNow: the list replaces
    /// what the session plays, from `startIndex` at `position`.
    public func play(_ itemIDs: [ItemID], startIndex: Int, at position: TimeInterval,
                     onSession id: String) async throws {
        var query = [URLQueryItem(name: "playCommand", value: "PlayNow"),
                     URLQueryItem(name: "itemIds", value: itemIDs.joined(separator: ",")),
                     URLQueryItem(name: "startIndex", value: String(startIndex))]
        if position > 0 {
            query.append(URLQueryItem(name: "startPositionTicks", value: String(JellyfinTicks.ticks(seconds: position))))
        }
        try await send("POST", "/Sessions/\(Self.segment(id))/Playing", query: query, timeout: 10)
    }

    /// playCommand=PlayLast: at the end of what the session plays.
    public func add(_ itemIDs: [ItemID], toSession id: String) async throws {
        try await send("POST", "/Sessions/\(Self.segment(id))/Playing",
                       query: [URLQueryItem(name: "playCommand", value: "PlayLast"),
                               URLQueryItem(name: "itemIds", value: itemIDs.joined(separator: ","))],
                       timeout: 10)
    }

    /// POST /Sessions/{id}/Playing/{command}.
    public func send(_ command: RemoteCommand, toSession id: String) async throws {
        try await send("POST", "/Sessions/\(Self.segment(id))/Playing/\(command.rawValue)", timeout: 10)
    }

    /// POST /Sessions/{id}/Playing/Seek?seekPositionTicks=.
    public func seek(to position: TimeInterval, onSession id: String) async throws {
        try await send("POST", "/Sessions/\(Self.segment(id))/Playing/Seek",
                       query: [URLQueryItem(name: "seekPositionTicks",
                                            value: String(JellyfinTicks.ticks(seconds: position)))],
                       timeout: 10)
    }

    /// POST /Sessions/{id}/Command, the general command SetVolume: its
    /// argument is a whole number 0–100, as a string.
    public func setVolume(_ level: Double, onSession id: String) async throws {
        let volume = Int((min(1, max(0, level)) * 100).rounded())
        try await send("POST", "/Sessions/\(Self.segment(id))/Command",
                       json: JellyfinGeneralCommand(name: "SetVolume", arguments: ["Volume": String(volume)]),
                       timeout: 10)
    }

    /// The websocket a client opens to be controllable, with its token and
    /// device: Jellyfin's `/socket?ApiKey=` (12.4 refuses `api_key` there
    /// with 403, measured), Emby's `/embywebsocket?api_key=` (what Emby's own
    /// clients open). Jukebox opens none itself: a far client does.
    public func sessionSocketPath(deviceID: String) -> String {
        var parts = URLComponents()
        parts.path = serverURL.path + (isEmby ? "/embywebsocket" : "/socket")
        parts.queryItems = [URLQueryItem(name: tokenKey, value: accessToken ?? ""),
                            URLQueryItem(name: "deviceId", value: deviceID)]
        return parts.string ?? parts.path
    }

    /// A cast device fetches the file itself, so Jellyfin is asked for what
    /// the Default Media Receiver surely plays, and the LOAD names its type
    /// before a byte is fetched. Jellyfin's tracks say only their container,
    /// not the codec inside an M4A (it may be ALAC), so: an MP3 as it is, a
    /// FLAC as it is, anything else Jellyfin's own MP3 at 320.
    ///
    /// Measured on 12.4 (17 November 2026, curl with no header): with
    /// `Container=mp3` the M4A (AAC) came as audio/mpeg 97 831 bytes, the
    /// FLAC as audio/mpeg 129 508, the MP3 as itself, audio/mpeg 113 059;
    /// with `mp3,aac,m4a|aac,mp4|aac,flac` the M4A came as audio/mp4, the
    /// FLAC as audio/flac 105 111, each its own bytes. Every answer 200.
    public func castURL(for track: Track) -> CastStream {
        let flac = track.container == "flac"
        var query = [
            URLQueryItem(name: "UserId", value: userID ?? ""),
            URLQueryItem(name: "DeviceId", value: identity.deviceID),
            URLQueryItem(name: "Container", value: flac ? "mp3,flac" : "mp3"),
            URLQueryItem(name: "TranscodingContainer", value: "mp3"),
            URLQueryItem(name: "TranscodingProtocol", value: "http"),
            URLQueryItem(name: "AudioCodec", value: "mp3"),
            URLQueryItem(name: "MaxStreamingBitrate", value: "320000"),
        ]
        if let accessToken, !accessToken.isEmpty {
            // Emby takes the token as `api_key` and refuses `ApiKey` (401).
            query.append(URLQueryItem(name: tokenKey, value: accessToken))
        }
        return CastStream(url: url("/Audio/\(Self.segment(track.id))/universal", query),
                          contentType: flac ? "audio/flac" : "audio/mpeg")
    }
}

// MARK: Jellyfin's shapes

/// The fields of a SessionInfo that Play On reads.
struct JellyfinSession: Decodable, Sendable {
    var id: String?
    var deviceName: String?
    var client: String?
    var deviceID: String?
    var supportsRemoteControl: Bool?
    var playableMediaTypes: [String]?
    var nowPlayingItem: JellyfinNowPlaying?
    var playState: JellyfinPlayState?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case deviceName = "DeviceName"
        case client = "Client"
        case deviceID = "DeviceId"
        case supportsRemoteControl = "SupportsRemoteControl"
        case playableMediaTypes = "PlayableMediaTypes"
        case nowPlayingItem = "NowPlayingItem"
        case playState = "PlayState"
    }

    func asRemoteSession() -> RemoteSession? {
        guard let id, !id.isEmpty else { return nil }
        return RemoteSession(id: id, deviceName: deviceName ?? client ?? "Jellyfin", client: client ?? "",
                             deviceID: deviceID ?? "", nowPlayingID: nowPlayingItem?.id,
                             position: JellyfinTicks.seconds(playState?.positionTicks) ?? 0,
                             isPaused: playState?.isPaused ?? false,
                             volume: playState?.volumeLevel.map { Double($0) / 100 })
    }
}

struct JellyfinNowPlaying: Decodable, Sendable {
    var id: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

struct JellyfinPlayState: Decodable, Sendable {
    var positionTicks: Int64?
    var isPaused: Bool?
    var volumeLevel: Int?

    enum CodingKeys: String, CodingKey {
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case volumeLevel = "VolumeLevel"
    }
}

struct JellyfinGeneralCommand: Encodable, Sendable {
    var name: String
    var arguments: [String: String]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case arguments = "Arguments"
    }
}
