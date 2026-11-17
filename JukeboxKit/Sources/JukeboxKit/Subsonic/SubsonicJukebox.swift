// Play On, on a Subsonic server: its jukebox, the server playing through
// its own sound card (`jukeboxControl`, API 1.2.0). Only for a user with
// the jukebox role, on a server that has it switched on: Navidrome keeps it
// off unless `Jukebox.Enabled` is set, and answers with an error then.

import Foundation

/// What the server's jukebox is doing.
public struct JukeboxStatus: Sendable, Hashable {
    /// Into the jukebox's list; nil when it has none (the server says -1).
    public var currentIndex: Int?
    public var playing: Bool
    /// 0...1.
    public var gain: Double
    /// Seconds into the current song; the API counts whole seconds.
    public var position: TimeInterval

    public init(currentIndex: Int?, playing: Bool, gain: Double, position: TimeInterval) {
        self.currentIndex = currentIndex
        self.playing = playing
        self.gain = gain
        self.position = position
    }
}

extension SubsonicClient {
    /// The user's `jukeboxRole`, and a status call that answers: a server
    /// may grant the role with its jukebox off. False on any error, so a
    /// server without it is simply not offered.
    public func jukeboxAvailable() async -> Bool {
        let user = credentials.userName.isEmpty ? credentials.userID : credentials.userName
        guard let body = try? await call("getUser", [URLQueryItem(name: "username", value: user)], timeout: 10),
              body.user?.jukeboxRole == true else { return false }
        return (try? await jukeboxStatus()) != nil
    }

    public func jukeboxStatus() async throws -> JukeboxStatus {
        try await jukebox("status")
    }

    /// action=set: the list replaces the jukebox's own.
    public func jukeboxSet(_ ids: [ItemID]) async throws {
        _ = try await jukebox("set", ids.map { URLQueryItem(name: "id", value: $0) })
    }

    /// action=add: at the end of the jukebox's list.
    public func jukeboxAdd(_ ids: [ItemID]) async throws {
        _ = try await jukebox("add", ids.map { URLQueryItem(name: "id", value: $0) })
    }

    /// action=skip: to `index` in the list, `offset` whole seconds into it.
    public func jukeboxSkip(to index: Int, offset: TimeInterval) async throws {
        _ = try await jukebox("skip", [URLQueryItem(name: "index", value: String(max(0, index))),
                                       URLQueryItem(name: "offset", value: String(Int(max(0, offset))))])
    }

    public func jukeboxStart() async throws {
        _ = try await jukebox("start")
    }

    public func jukeboxStop() async throws {
        _ = try await jukebox("stop")
    }

    /// action=setGain, 0...1.
    public func jukeboxGain(_ gain: Double) async throws {
        _ = try await jukebox("setGain", [URLQueryItem(name: "gain", value: String(min(1, max(0, gain))))])
    }

    /// Every action answers with the jukebox's status.
    private func jukebox(_ action: String, _ query: [URLQueryItem] = []) async throws -> JukeboxStatus {
        let body = try await call("jukeboxControl", [URLQueryItem(name: "action", value: action)] + query,
                                  timeout: 10)
        let status = body.jukeboxStatus
        let index = status?.currentIndex ?? -1
        return JukeboxStatus(currentIndex: index < 0 ? nil : index, playing: status?.playing ?? false,
                             gain: status?.gain ?? 1, position: TimeInterval(max(0, status?.position ?? 0)))
    }
}
