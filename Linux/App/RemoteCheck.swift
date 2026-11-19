// A check of this device as a speaker the phone controls (RemoteControl),
// end to end through libsoup's socket, against the Jellyfin or Emby in
// JUKEBOX_REMOTE_URL (user test/test; never one with anyone's music on it):
// JUKEBOX_CHECK=remote. A speaker session opens its socket and is listed to
// a second session, the "phone", which plays three songs from the second,
// skips, pauses, sets the volume; the speaker's queue must follow, and the
// phone must read back what the speaker plays. Exit 0 when it all came.
// Both sessions sign out at the end. The queue has no engine (no sound).

import CAdw
import Foundation
import JukeboxKit

/// The queue with no engine: every song has an address, none plays.
private final class SilentQueue: PlayQueue {
    override func address(of entry: QueueEntry, playSessionID: String) -> URL? {
        URL(fileURLWithPath: "/dev/null")
    }
}

enum RemoteCheck {
    static let idleSeconds = Int(ProcessInfo.processInfo.environment["JUKEBOX_REMOTE_IDLE"] ?? "") ?? 0

    static func run() -> Int32 {
        guard let typed = ProcessInfo.processInfo.environment["JUKEBOX_REMOTE_URL"] else {
            print("remote check: set JUKEBOX_REMOTE_URL to a test Jellyfin or Emby")
            return 1
        }
        UserDefaults.standard.set(false, forKey: Stats.key)
        let loop = g_main_loop_new(nil, 0)
        var result: Int32 = 1
        // The main actor's work runs from GLib's loop (main.swift).
        let handle = mainQueueHandleForCheck()
        g_unix_fd_add(handle, G_IO_IN, { handle, _, _ in
            var count: UInt64 = 0
            _ = read(handle, &count, MemoryLayout<UInt64>.size)
            drainMainQueueForCheck(nil)
            return 1
        }, nil)
        Task { @MainActor in
            result = await check(typed)
            g_main_loop_quit(loop)
        }
        // A minute for the check, more when it waits idle first.
        g_timeout_add_seconds(guint(60 + idleSeconds), { _ in
            print("remote check: FAILED, timed out")
            exit(1)
        }, nil)
        g_main_loop_run(loop)
        return result
    }

    private static func check(_ typed: String) async -> Int32 {
        func identity(_ name: String) -> ClientIdentity {
            ClientIdentity(clientName: "Jukebox", clientVersion: "check", deviceName: "Remote check: \(name)",
                           deviceID: "jukebox-remote-check-\(name)")
        }
        var opened: [any MusicServer] = []
        let code = await body(typed, identity: identity, opened: &opened)
        // Signed out whatever happened, so no check session stays on the server.
        for server in opened { await server.signOut() }
        return code
    }

    private static func body(_ typed: String, identity: (String) -> ClientIdentity,
                             opened: inout [any MusicServer]) async -> Int32 {
        do {
            func open(_ name: String) async throws -> any MusicServer {
                let found = try await MusicServers.detect(typed, identity: identity(name))
                var credentials = try await MusicServers.signIn(to: found, identity: identity(name))
                    .signIn(username: "test", password: "test")
                let server = MusicServers.open(credentials, identity: identity(name))
                credentials.capabilities = try await server.currentCapabilities()
                let asked = MusicServers.open(credentials, identity: identity(name))
                opened.append(asked)
                return asked
            }
            let speaker = try await open("speaker")
            let phone = try await open("phone")
            guard speaker.capabilities.contains(.remoteControl), let phoneClient = (phone as? JellyfinServer)?.client else {
                print("remote check: FAILED, the server does not offer remote control")
                return 1
            }

            let queue = SilentQueue(settings: AppSettings(), history: HistoryStore())
            queue.server = speaker
            let remote = RemoteControl(player: queue, library: LibraryStore())
            remote.connect = { SoupCommandSocket(url: $0) }
            remote.server = speaker

            var session: RemoteSession?
            for _ in 0..<50 where session == nil {
                session = try await phoneClient.remoteSessions().first { $0.deviceID == "jukebox-remote-check-speaker" }
                if session == nil { try await Task.sleep(for: .milliseconds(200)) }
            }
            guard let session else {
                print("remote check: FAILED, the speaker was not listed to the phone")
                return 1
            }
            print("remote check: listed as \(session.deviceName) (\(session.client))")
            if idleSeconds > 0 {
                // JUKEBOX_REMOTE_IDLE: the socket left alone past the server's
                // lost-socket time (about 60 s), kept by the keep-alives alone.
                print("remote check: idle for \(idleSeconds) s")
                try await Task.sleep(for: .seconds(idleSeconds))
            }

            func until(_ what: String, _ ok: () -> Bool) async throws {
                for _ in 0..<50 where !ok() { try await Task.sleep(for: .milliseconds(100)) }
                guard ok() else { throw MusicServerError.server(status: 0, message: "no \(what)") }
                print("remote check: \(what)")
            }
            let ids = try await phoneClient.tracks(TrackQuery(limit: 3)).items.map(\.id)
            try await phoneClient.play(ids, startIndex: 1, at: 0, onSession: session.id)
            try await until("Play came: the queue holds the three, at the second") {
                queue.queue.map(\.track.id) == ids && queue.currentTrack?.id == ids[1]
            }
            try await phoneClient.send(.next, toSession: session.id)
            try await until("Next came") { queue.currentTrack?.id == ids[2] }
            try await phoneClient.setVolume(0.25, onSession: session.id)
            try await until("SetVolume came") { abs(queue.volume - 0.25) < 0.01 }
            try await phoneClient.add([ids[0]], toSession: session.id)
            try await until("PlayLast came") { queue.queue.count == 4 }
            // What the speaker said of itself, read by the phone.
            var seen: RemoteSession?
            for _ in 0..<30 {
                seen = try await phoneClient.remoteSession(id: session.id)
                if seen?.nowPlayingID == ids[2] { break }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard seen?.nowPlayingID == ids[2] else {
                print("remote check: FAILED, the phone does not see what the speaker plays")
                return 1
            }
            print("remote check: the phone sees the speaker play the third, volume \(seen?.volume ?? -1)")
            remote.stop()
            queue.stop()
            print("remote check: ok")
            return 0
        } catch {
            print("remote check: FAILED, \(error)")
            return 1
        }
    }
}

@_silgen_name("_dispatch_get_main_queue_handle_4CF")
private func mainQueueHandleForCheck() -> Int32

@_silgen_name("_dispatch_main_queue_callback_4CF")
private func drainMainQueueForCheck(_ message: UnsafeMutableRawPointer?)
