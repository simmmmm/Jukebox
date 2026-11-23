// Jukebox as a speaker the phone controls, like Spotify Connect: with
// Jellyfin or Emby, this device is listed in every other client's Play On
// (another Jukebox's, Jellyfin's own apps'), and what they send plays here.
// From features.md's second point, "Jukebox op de pc bedienen vanaf je
// telefoon (zoals Spotify Connect)", and the photographer, 13 November
// 2026: "net als bij spotify". No button: it is there while the app is
// open and signed in to a server that has it (`ServerCapability.remoteControl`).
//
// The socket is each platform's (`connect`): URLSession's on Apple's,
// libsoup's on Linux. The rest is here, one file for both (Package.swift's
// `shared`). On the iPhone the system suspends the app in the background
// unless it plays, and the socket with it: the phone is a speaker only
// while it plays or is open, and comes back when it opens again.
//
// The controller follows what this device tells the server (Play On's
// JellyfinSessionPlayer reads NowPlayingItem, PositionTicks, IsPaused and
// VolumeLevel once a second), so while controlled it says it at once on
// every change, as a progress report: a start report would count a play
// before it is heard (JellyfinClient.reportStart), a progress report does
// not (measured on 12.4, 18 November 2026). The queue's own reports go on
// as always and count the plays.

import Foundation
import JukeboxKit

/// A websocket's text, each platform's; callbacks on the main actor.
protocol CommandSocket: AnyObject {
    /// Each text message; nil once the socket closed or failed.
    var received: ((String?) -> Void)? { get set }
    func send(_ text: String)
    func close()
}

final class RemoteControl {
    /// The platform's socket to an address.
    var connect: ((URL) -> any CommandSocket)?
    private let player: PlayQueue
    private let library: LibraryStore

    var server: (any MusicServer)? {
        didSet {
            let before = oldValue as? JellyfinServer, now = server as? JellyfinServer
            guard before?.credentials != now?.credentials else { return }
            failures = 0
            restart()
        }
    }

    private var socket: (any CommandSocket)?
    private var keepAlive: Task<Void, Never>?
    private var again: Task<Void, Never>?
    private var reporting: Task<Void, Never>?
    private var keepAliveEvery: TimeInterval = 30
    private var failures = 0
    private var offered = false
    /// Since a command played something here: this device says what it
    /// plays on every change, for the controller to follow.
    private var isControlled = false
    private var lastSaid: (id: ItemID, paused: Bool, volume: Double, at: Date)?
    private var reportSession = UUID().uuidString
    private var songSince = Date.distantPast
    private var lastTrackID: ItemID?

    init(player: PlayQueue, library: LibraryStore) {
        self.player = player
        self.library = library
    }

    private var jellyfin: JellyfinServer? {
        guard let server = server as? JellyfinServer, server.capabilities.contains(.remoteControl) else { return nil }
        return server
    }

    /// The app came to the front again (the iPhone's socket may have died
    /// while it slept).
    func wake() {
        if socket == nil { failures = 0; restart() }
    }

    func stop() {
        again?.cancel()
        keepAlive?.cancel()
        reporting?.cancel()
        socket?.received = nil
        socket?.close()
        socket = nil
        isControlled = false
        lastSaid = nil
    }

    private func restart() {
        stop()
        guard let jellyfin, let url = jellyfin.client.sessionSocketURL, let connect else { return }
        // The socket's address carries the token: over plain http (ws://)
        // only while this device is on the server's network, as every call
        // to it (PlainHTTPGuard). Not known at once, it is asked off the
        // main thread; away, the socket waits as a closed one does.
        guard PlainHTTPGuard.mayFetchNow(url) else {
            again = Task { [weak self] in
                let home = await Task.detached { PlainHTTPGuard.mayFetch(url) }.value
                guard !Task.isCancelled, let self else { return }
                if home { self.restart() } else { self.closed() }
            }
            return
        }
        let socket = connect(url)
        self.socket = socket
        offered = false
        socket.received = { [weak self] text in
            guard let self, self.socket === socket else { return }
            guard let text else { return self.closed() }
            self.failures = 0
            // Once the socket answers, the server is told what this session
            // takes, so it is listed as controllable.
            if !self.offered { self.offered = true; self.offer() }
            if let command = RemoteControlMessage.parse(text) { self.perform(command) }
        }
        offer()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.keepAliveEvery ?? 30))
                guard !Task.isCancelled, let self else { return }
                self.socket?.send(RemoteControlMessage.keepAlive)
            }
        }
        reporting = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.sayWhatPlays()
            }
        }
    }

    private func offer() {
        guard let client = jellyfin?.client else { return }
        Task { try? await client.offerRemoteControl() }
    }

    /// Closed or failed: again after 5 s, then longer, up to a minute.
    private func closed() {
        socket = nil
        keepAlive?.cancel()
        reporting?.cancel()
        failures += 1
        let wait = min(60, 5 * pow(2, Double(min(failures - 1, 4))))
        again = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.restart()
        }
    }

    // MARK: Commands

    private func perform(_ command: RemoteControlCommand) {
        switch command {
        case let .keepAlive(seconds):
            keepAliveEvery = max(5, seconds / 2)
        case let .play(ids, startIndex, position, placement):
            Task { await play(ids, from: startIndex, at: position, placement: placement) }
        case .pause: player.pause()
        case .unpause: player.resume()
        case .playPause: player.togglePlayPause()
        case .stop:
            player.stop()
            isControlled = false
        case .next: player.next()
        case .previous: player.previous()
        case let .seek(seconds): player.seek(to: seconds)
        case let .setVolume(level): player.volume = level
        }
        lastSaid = nil
    }

    private func play(_ ids: [ItemID], from start: Int, at position: TimeInterval,
                      placement: RemoteControlCommand.Placement) async {
        // ponytail: songs not in the library are asked for one by one; a
        // controller sends 100 at most (Play On's capacity).
        var tracks: [Track] = []
        var index = 0
        for (i, id) in ids.enumerated() {
            var track = library.track(id: id)
            if track == nil { track = try? await server?.track(id: id) }
            guard let track else { continue }
            if i <= start { index = tracks.count }
            tracks.append(track)
        }
        guard !tracks.isEmpty else { return }
        isControlled = true
        lastSaid = nil
        switch placement {
        case .now:
            player.play(tracks, startingAt: index, context: QueueContext(.other, title: String(localized: "Played from another device")))
            if position > 1 {
                // Once the engine holds the song: a seek before has nothing to move.
                try? await Task.sleep(for: .milliseconds(500))
                player.seek(to: position)
            }
        case .next: player.playNext(tracks)
        case .last: player.addToQueue(tracks)
        }
    }

    /// While controlled: what plays, paused or not, where, at what level,
    /// at once on a change and every 5 s while it plays.
    private func sayWhatPlays() {
        guard isControlled, let client = jellyfin?.client, player.playingElsewhere == nil,
              let track = player.currentTrack else { return }
        let paused = !player.isPlaying
        let now = Date()
        // Each second for the first 3 s of a song: the queue's Stopped report
        // of the song before can land after this one's and empty the
        // session's NowPlayingItem (measured on 12.4), and the controller
        // would see nothing playing until the next.
        if track.id != lastTrackID {
            lastTrackID = track.id
            songSince = now
            reportSession = UUID().uuidString
        }
        let settling = now.timeIntervalSince(songSince) < 3
        if let last = lastSaid, last.id == track.id, last.paused == paused, last.volume == player.volume,
           !settling, paused || now.timeIntervalSince(last.at) < 5 {
            return
        }
        lastSaid = (track.id, paused, player.volume, now)
        let report = PlaybackReport(trackID: track.id, position: player.elapsed, isPaused: paused,
                                    playSessionID: reportSession, volume: player.volume)
        Task { await client.reportProgress(report) }
    }
}
