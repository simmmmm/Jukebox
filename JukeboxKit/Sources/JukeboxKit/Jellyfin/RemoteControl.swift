// Jukebox as a device other clients control, like Spotify Connect: from the
// phone on the sofa, the computer on the speakers pauses, skips, plays
// something else. The other side of Play On (JellyfinSessions.swift): a
// session that tells the server it takes commands and keeps its websocket
// open is listed in every other client's Play On (Jukebox's, Jellyfin's
// own), and the server passes their commands over that socket.
//
// The kit has what both platforms share: the socket's address, what this
// session says it can do, and the messages read into commands. The socket
// itself is each platform's (URLSession's on Apple's; libsoup on Linux,
// where Foundation's has no websockets).
//
// Measured on Jellyfin 12.4 and Emby 4.10 (18 November 2026,
// JellyfinRemoteControlTests): after /Sessions/Capabilities/Full with
// SupportsMediaControl and the socket open, the session is listed as
// controllable to the same user's other sessions; the commands arrive as
// below. Emby sends ItemIds as numbers.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A command from another client, read from the session's socket.
public enum RemoteControlCommand: Sendable, Equatable {
    public enum Placement: String, Sendable {
        /// Replace what plays.
        case now = "PlayNow"
        /// After the current song.
        case next = "PlayNext"
        /// At the end.
        case last = "PlayLast"
    }

    case play(ids: [ItemID], startIndex: Int, position: TimeInterval, placement: Placement)
    case pause
    case unpause
    case playPause
    case stop
    case next
    case previous
    case seek(TimeInterval)
    /// 0...1.
    case setVolume(Double)
    /// The server wants a KeepAlive at least this often, seconds.
    case keepAlive(TimeInterval)
}

public enum RemoteControlMessage {
    /// What this session sends the server to be listed, and what it can be
    /// told: only what `parse` reads and the app carries out.
    public static let supportedCommands = ["SetVolume"]

    /// The text to send every so often, so the server keeps the socket.
    public static let keepAlive = #"{"MessageType":"KeepAlive"}"#

    /// A message as a command; nil for anything else (the server's own
    /// news: sessions, library changes, its keep-alives answered).
    public static func parse(_ text: String) -> RemoteControlCommand? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["MessageType"] as? String else { return nil }
        let data = object["Data"]
        switch type {
        case "ForceKeepAlive":
            // Kept within what a server means: the app sleeps this long,
            // and a Duration holds neither 1e300 seconds nor NaN.
            let seconds = (data as? NSNumber)?.doubleValue ?? 60
            return .keepAlive(seconds.isFinite ? min(600, max(10, seconds)) : 60)
        case "Play":
            guard let data = data as? [String: Any], let list = data["ItemIds"] as? [Any] else { return nil }
            // Each id the library does not have is asked of the server one
            // by one; a controller sends 100 at most (Play On's capacity).
            let ids = list.prefix(500).map { "\($0)" }.filter { !$0.isEmpty }
            guard !ids.isEmpty else { return nil }
            let placement = (data["PlayCommand"] as? String).flatMap(RemoteControlCommand.Placement.init) ?? .now
            let start = (data["StartIndex"] as? NSNumber)?.intValue ?? 0
            let ticks = (data["StartPositionTicks"] as? NSNumber)?.int64Value
            return .play(ids: ids, startIndex: min(max(0, start), ids.count - 1),
                         position: JellyfinTicks.seconds(ticks) ?? 0, placement: placement)
        case "Playstate":
            guard let data = data as? [String: Any], let command = data["Command"] as? String else { return nil }
            switch command {
            case "Pause": return .pause
            case "Unpause": return .unpause
            case "PlayPause": return .playPause
            case "Stop": return .stop
            case "NextTrack": return .next
            case "PreviousTrack": return .previous
            case "Seek":
                let ticks = (data["SeekPositionTicks"] as? NSNumber)?.int64Value
                return JellyfinTicks.seconds(ticks).map { .seek($0) }
            default: return nil
            }
        case "GeneralCommand":
            guard let data = data as? [String: Any], data["Name"] as? String == "SetVolume",
                  let arguments = data["Arguments"] as? [String: Any] else { return nil }
            let text = arguments["Volume"].map { "\($0)" } ?? ""
            guard let level = Double(text) else { return nil }
            return .setVolume(min(1, max(0, level / 100)))
        default:
            return nil
        }
    }
}

struct JellyfinSessionCapabilities: Encodable, Sendable {
    var PlayableMediaTypes = ["Audio"]
    var SupportedCommands = RemoteControlMessage.supportedCommands
    var SupportsMediaControl = true
}

extension JellyfinClient {
    /// The websocket to open: ws or wss as the server's own address is.
    public var sessionSocketURL: URL? {
        guard var parts = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        let path = sessionSocketPath(deviceID: identity.deviceID)
        guard let socket = URLComponents(string: path) else { return nil }
        parts.path = socket.path
        parts.percentEncodedQuery = socket.percentEncodedQuery
        return parts.url
    }

    /// Tells the server this session plays audio and takes commands: with
    /// the socket open, it is then listed to the user's other clients.
    public func offerRemoteControl() async throws {
        try await send("POST", "/Sessions/Capabilities/Full", json: JellyfinSessionCapabilities(), timeout: 10)
    }
}
