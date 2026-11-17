// Playing on another device, on every client: a Chromecast, another
// Jellyfin client of the same user, a Subsonic server's own jukebox. The
// photographer, 17 November 2026: "van mij mag chromecast er ook in hoor ik
// wil alleen er voor waken dat we niet 10000 knopen krijgen". So no new
// button: the place AirPlay has (Now Playing's route button, the wide bar's;
// on Linux the same place in its bar) opens one list, This device, AirPlay,
// what is found, and the player's own controls drive whatever plays.
//
// How it is built: the queue (PlayQueue) stays the truth, as with the
// engines. A remote player takes the current entry and, where it can hold
// more (`capacity`), the ones after it; the queue follows it as it follows
// a gapless engine (`remoteTick`, once a second): a move on by itself
// finishes the entry and begins the next, an end by itself goes on by the
// queue's rules (`entryEnded`). The server is told of the plays as before,
// except by a Jellyfin client, which tells it itself (`reportsItself`).
// Foundation only: Linux compiles this file as it is (Package.swift).
//
// Each platform brings its Chromecasts (`PlayOn.castFinder`, `castPlayer`):
// Linux and the Mac speak castv2 themselves (JukeboxKit's CastSession over
// GIO's TLS or Network's); the iPhone and the iPad use Google's Cast SDK.

import Foundation
import JukeboxKit
import Observation

/// Somewhere the music can play other than here.
struct PlayOnDevice: Identifiable, Hashable {
    enum Kind: String, Hashable { case chromecast, jellyfin, subsonicJukebox }
    let id: String
    let name: String
    let kind: Kind
    /// A Chromecast's "host:port"; a Jellyfin session's id; the server's id
    /// for its jukebox.
    let address: String
    /// A second line where the name alone does not say it ("Jellyfin Web").
    var detail: String? = nil

    /// Its `play_on` target (docs/STATS.md).
    var statsTarget: String {
        switch kind {
        case .chromecast: "chromecast"
        case .jellyfin: "jellyfin"
        case .subsonicJukebox: "subsonic_jukebox"
        }
    }
}

/// One source of devices.
protocol PlayOnFinder: AnyObject {
    /// Looks until `stop`, telling every change of what it found.
    func start(_ found: @escaping ([PlayOnDevice]) -> Void)
    func stop()
}

/// Bytes to and from a Chromecast; callbacks on the main actor.
protocol CastSocket: AnyObject {
    /// The bytes as they come; nil once the connection closed or failed.
    var received: ((Data?) -> Void)? { get set }
    func send(_ data: Data)
    func close()
}

/// A song for a remote player: the server's own id, and the plain file a
/// Chromecast fetches itself.
struct RemoteEntry {
    let track: Track
    let stream: CastStream
    let artworkURL: URL?
}

/// What a remote player says of itself.
struct RemoteStatus {
    /// Into what `load` and `append` gave it; nil when it holds nothing.
    var index: Int?
    var position: TimeInterval = 0
    var isPlaying = false
    var isBuffering = false
    /// It stopped by itself after its last entry.
    var hasEnded = false
    /// It could not play what it was given.
    var failed = false
    /// 0...1, where it says.
    var volume: Double?
}

/// A device the queue plays on, as an engine.
protocol RemotePlayer: AnyObject {
    var device: PlayOnDevice { get }
    /// It tells the server of its plays itself (a Jellyfin client), so the
    /// queue does not, or every play would count twice.
    var reportsItself: Bool { get }
    /// How many entries it holds at once: 1 plays one song and is given
    /// the next when it ends.
    var capacity: Int { get }
    /// Play `entries[0]` from `position`, the rest after it.
    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws
    func append(_ entries: [RemoteEntry]) async throws
    func resume() async throws
    func pause() async throws
    func seek(to position: TimeInterval) async throws
    func setVolume(_ level: Double) async throws
    func stop() async
    /// Throws once it is gone.
    func status() async throws -> RemoteStatus
}

// MARK: - The list

@Observable
final class PlayOn {
    /// What the finders see, while the list is open.
    private(set) var devices: [PlayOnDevice] = []
    /// Chromecasts, by the platform (Linux: Avahi; the Mac: Bonjour; the
    /// iPhone: Google's Cast SDK). Nil where there are none.
    @ObservationIgnored var castFinder: (any PlayOnFinder)?
    @ObservationIgnored var castPlayer: ((PlayOnDevice) -> (any RemotePlayer)?)?
    @ObservationIgnored weak var player: PlayQueue?
    @ObservationIgnored private var finders: [any PlayOnFinder] = []
    @ObservationIgnored private var found: [ObjectIdentifier: [PlayOnDevice]] = [:]

    /// The list opened: look, and only now, so no prompt for the local
    /// network comes at launch.
    func look() {
        stopLooking()
        var all: [any PlayOnFinder] = []
        if let castFinder { all.append(castFinder) }
        // Not offline: a device elsewhere plays from the server, not from
        // the songs on this one.
        if player?.offline?.isOffline != true, let server = player?.server {
            if let jellyfin = server as? JellyfinServer {
                all.append(JellyfinSessionFinder(client: jellyfin.client))
            } else if let subsonic = server as? SubsonicClient {
                all.append(SubsonicJukeboxFinder(client: subsonic))
            }
        }
        finders = all
        for finder in all {
            let key = ObjectIdentifier(finder)
            finder.start { [weak self] devices in
                guard let self else { return }
                self.found[key] = devices
                self.devices = self.finders.flatMap { self.found[ObjectIdentifier($0)] ?? [] }
            }
        }
    }

    func stopLooking() {
        for finder in finders { finder.stop() }
        finders = []
        found = [:]
        devices = []
    }

    /// Play here (nil) or on `device`.
    func choose(_ device: PlayOnDevice?) {
        guard let player, device?.id != player.playsOn?.id else { return }
        Stats.track(.playOn, ["target": device?.statsTarget ?? "this_device"])
        guard let device else {
            player.playHere()
            return
        }
        guard let remote = remotePlayer(for: device, server: player.server) else { return }
        player.play(on: remote)
    }

    /// Counted when the system's AirPlay list is opened from ours: which
    /// speaker is chosen there is the system's.
    func airPlayOpened() {
        Stats.track(.playOn, ["target": "airplay"])
    }

    private func remotePlayer(for device: PlayOnDevice, server: (any MusicServer)?) -> (any RemotePlayer)? {
        switch device.kind {
        case .chromecast:
            // The TV fetches the songs itself: it cannot reach a server on
            // this computer's own loopback.
            if let host = server?.credentials.serverURL.host?.lowercased(),
               host == "localhost" || host.hasPrefix("127.") || host == "::1" || host == "[::1]" {
                player?.showError("\(device.name) cannot reach a server at \(host): use its address on this network.")
                return nil
            }
            return castPlayer?(device)
        case .jellyfin:
            guard let jellyfin = server as? JellyfinServer else { return nil }
            return JellyfinSessionPlayer(device: device, client: jellyfin.client)
        case .subsonicJukebox:
            guard let subsonic = server as? SubsonicClient else { return nil }
            return SubsonicJukeboxPlayer(device: device, client: subsonic)
        }
    }
}

// MARK: - The queue, playing elsewhere

extension PlayQueue {
    /// Hand the queue to `remote`, from where it is now. The play goes on as
    /// the same play: no skip, no second count.
    func play(on remote: any RemotePlayer) {
        let old = self.remote
        let wasPlaying = isPlaying || wantsToPlay
        let position = elapsed
        // A Jellyfin client reports the song itself from now on: the server
        // hears that it stopped here.
        if remote.reportsItself, let playing, playing.startReported, let server = reportingServer {
            let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: false,
                                        playSessionID: playing.playSessionID)
            Task { await server.report(.stopped, report) }
        }
        engineHalt()
        engineRuns(false)
        self.remote = remote
        playsOn = remote.device
        remoteVolume = nil
        remoteFailures = 0
        if let old { Task { await old.stop() } }
        if let currentIndex {
            remoteLoad(from: currentIndex, at: position, play: wasPlaying)
        }
        startRemotePoll()
    }

    /// Back here, from where the remote is, playing if it played.
    func playHere() {
        guard let remote else { return }
        let wasPlaying = isPlaying || wantsToPlay
        let position = elapsed
        endRemote()
        Task { await remote.stop() }
        guard let entry = current, let playing,
              let url = address(of: entry, playSessionID: playing.playSessionID) else { return }
        engineReplace(with: url, entry: entry, playSessionID: playing.playSessionID, play: wasPlaying)
        wantsToPlay = wasPlaying
        engineStart(wasPlaying)
        if position > 1 { seek(to: position) }
        preloadNext()
    }

    /// The remote let go (gone, or the queue stopped): nothing elsewhere.
    func endRemote() {
        remotePoll?.cancel()
        remotePoll = nil
        remote = nil
        remoteHeld = []
        playsOn = nil
        remoteVolume = nil
    }

    /// The device's own level, set from the volume slider while it plays
    /// elsewhere; the listener's level here is not touched.
    func setRemoteVolume(_ level: Double) {
        let level = min(1, max(0, level))
        remoteVolume = level
        remoteDo { try await $0.setVolume(level) }
    }

    /// The entries the remote should hold from `index` on: one where the
    /// next must wait for the queue (Repeat One, the sleep timer's End of
    /// Song), else as many as it takes.
    private func remoteWindow(from index: Int, capacity: Int) -> [QueueEntry] {
        guard queue.indices.contains(index) else { return [] }
        let count = repeatMode == .one || sleepChoice == .endOfSong ? 1 : max(1, capacity)
        return Array(queue[index..<min(queue.count, index + count)])
    }

    /// `index` from its `position`, with what follows it.
    func remoteLoad(from index: Int, at position: TimeInterval, play: Bool) {
        guard let remote, let server else { return }
        let entries = remoteWindow(from: index, capacity: remote.capacity)
        guard !entries.isEmpty else { return }
        remoteHeld = entries.map(\.id)
        remoteSettled = Date().addingTimeInterval(1.5)
        let items = entries.map { remoteEntry($0, server: server) }
        remoteDo { try await $0.load(items, at: position, play: play) }
    }

    /// The queue changed (an edit, the radio's picks): what the remote holds
    /// from the current entry on is brought in line. Added songs are added;
    /// anything else loads it again from where it is.
    func remoteQueueChanged() {
        guard let remote, let server, let current, let currentIndex else { return }
        let wanted = remoteWindow(from: currentIndex, capacity: remote.capacity).map(\.id)
        guard let here = remoteHeld.firstIndex(of: current.id) else {
            remoteLoad(from: currentIndex, at: elapsed, play: wantsToPlay)
            return
        }
        let held = Array(remoteHeld[here...])
        if held == wanted { return }
        if wanted.count > held.count, Array(wanted.prefix(held.count)) == held {
            let more = wanted[held.count...].compactMap { id in queue.first { $0.id == id } }
            remoteHeld += more.map(\.id)
            let items = more.map { remoteEntry($0, server: server) }
            remoteDo { try await $0.append(items) }
        } else if held.count > wanted.count, Array(held.prefix(wanted.count)) == wanted {
            // It holds more than it should (Repeat One turned on): it is told
            // when the song ends, as the engines are.
            return
        } else {
            remoteLoad(from: currentIndex, at: elapsed, play: wantsToPlay)
        }
    }

    private func remoteEntry(_ entry: QueueEntry, server: any MusicServer) -> RemoteEntry {
        RemoteEntry(track: entry.track, stream: server.castURL(for: entry.track),
                    artworkURL: entry.track.artwork.map { server.artworkURL($0, maxPixelSize: 600) })
    }

    /// One call to the remote, in order after the ones before; a failure
    /// counts towards losing it (`remoteTick`).
    func remoteDo(_ call: @escaping (any RemotePlayer) async throws -> Void) {
        guard let remote else { return }
        let before = remoteCalls
        remoteCalls = Task { [weak self] in
            await before?.value
            do {
                try await call(remote)
            } catch {
                self?.remoteFailures += 1
            }
        }
    }

    private func startRemotePoll() {
        remotePoll?.cancel()
        remotePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.remoteTick()
            }
        }
    }

    /// Once a second: where the remote is, followed.
    private func remoteTick() async {
        guard let remote else { return }
        // The sleep timer runs on the player's ticks; the iPhone's engine,
        // empty now, gives none.
        checkSleep()
        let status: RemoteStatus
        do {
            status = try await remote.status()
        } catch {
            remoteFailures += 1
            if remoteFailures >= 3, self.remote === remote { lost(remote) }
            return
        }
        guard self.remote === remote else { return }
        remoteFailures = 0
        if let volume = status.volume { remoteVolume = volume }
        // Just loaded: what it says may still be the song before.
        let settling = Date() < remoteSettled
        if !settling, status.failed {
            entryFailed(reason: "network")
            // A TV fetches the songs itself, and trusts only certificates it
            // knows: a home server's own one it refuses, without a word.
            if remote.device.kind == .chromecast, server?.credentials.serverURL.scheme == "https" {
                showError("\(remote.device.name) could not play from the server: it needs the server's address on this network, with a certificate it trusts.")
            }
            return
        }
        // Moved on by itself, as a gapless engine does.
        if !settling, let index = status.index, let current, let here = remoteHeld.firstIndex(of: current.id),
           index > here, index < remoteHeld.count,
           let next = queue.firstIndex(where: { $0.id == remoteHeld[index] }) {
            let finished = finishCurrent()
            begin(queue[next], at: next, playSessionID: UUID().uuidString)
            deliver(finished)
            checkRadioSupply()
        }
        if !settling, status.hasEnded {
            remoteSettled = Date().addingTimeInterval(1.5)
            entryEnded()
            return
        }
        if isBuffering != status.isBuffering { isBuffering = status.isBuffering }
        let justStarted = engineRuns(status.isPlaying)
        showPlaying(status.isPlaying || (status.isBuffering && wantsToPlay), justStarted: justStarted)
        if abs(status.position - elapsed) > 0.5 { elapsed = status.position }
        if status.isPlaying { reportWhilePlaying() }
    }

    /// Gone (switched off, out of reach): here again, paused where it was.
    private func lost(_ remote: any RemotePlayer) {
        let name = remote.device.name
        wantsToPlay = false
        isPlaying = false
        playHere()
        pause()
        showError("Lost the connection to \(name).")
    }
}

// MARK: - Jellyfin's other clients

/// The user's other Jellyfin clients that take remote control (Jellyfin
/// Web, the Android app, a TV), asked every 5 s while the list is open.
final class JellyfinSessionFinder: PlayOnFinder {
    private let client: JellyfinClient
    private var task: Task<Void, Never>?

    init(client: JellyfinClient) {
        self.client = client
    }

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        let client = client
        task = Task {
            while !Task.isCancelled {
                if let sessions = try? await client.remoteSessions() {
                    found(sessions.map {
                        PlayOnDevice(id: "jellyfin-" + $0.id, name: $0.deviceName, kind: .jellyfin,
                                     address: $0.id, detail: $0.client)
                    })
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// A Jellyfin client plays the queue itself and reports its plays; it is
/// sent up to 100 songs at once (3.3 kB of ids, within a proxy's 8 kB line,
/// as JellyfinClient.idsPerRequest).
final class JellyfinSessionPlayer: RemotePlayer {
    let device: PlayOnDevice
    let reportsItself = true
    let capacity = 100
    private let client: JellyfinClient
    private var held: [ItemID] = []
    private var index: Int?
    private var wasPlaying = false

    init(device: PlayOnDevice, client: JellyfinClient) {
        self.device = device
        self.client = client
    }

    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws {
        held = entries.map(\.track.id)
        index = 0
        wasPlaying = false
        try await client.play(held, startIndex: 0, at: position, onSession: device.address)
        if !play { try await client.send(.pause, toSession: device.address) }
    }

    func append(_ entries: [RemoteEntry]) async throws {
        held += entries.map(\.track.id)
        try await client.add(entries.map(\.track.id), toSession: device.address)
    }

    func resume() async throws { try await client.send(.unpause, toSession: device.address) }
    func pause() async throws { try await client.send(.pause, toSession: device.address) }
    func seek(to position: TimeInterval) async throws { try await client.seek(to: position, onSession: device.address) }
    func setVolume(_ level: Double) async throws { try await client.setVolume(level, onSession: device.address) }

    func stop() async {
        try? await client.send(.stop, toSession: device.address)
    }

    func status() async throws -> RemoteStatus {
        guard let session = try await client.remoteSession(id: device.address) else {
            throw MusicServerError.notFound
        }
        var status = RemoteStatus(volume: session.volume)
        guard let id = session.nowPlayingID else {
            // Nothing playing after the last song played: the end.
            status.hasEnded = wasPlaying && index == held.count - 1
            status.index = index
            return status
        }
        // The same song can be in the queue twice: looked for from where
        // it was, forwards.
        let from = index ?? 0
        if from < held.count, let found = held[from...].firstIndex(of: id) { index = found }
        wasPlaying = true
        status.index = index
        status.position = session.position
        status.isPlaying = !session.isPaused
        return status
    }
}

// MARK: - A Subsonic server's jukebox

/// The server's own speakers, where the user has the jukebox role and the
/// server answers for it (Navidrome only with Jukebox.Enabled).
final class SubsonicJukeboxFinder: PlayOnFinder {
    private let client: SubsonicClient
    private var task: Task<Void, Never>?

    init(client: SubsonicClient) {
        self.client = client
    }

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        let client = client
        task = Task {
            guard await client.jukeboxAvailable(), !Task.isCancelled else { return }
            let credentials = client.credentials
            found([PlayOnDevice(id: "jukebox-" + credentials.serverID, name: "\(credentials.kind.displayName) Jukebox",
                                kind: .subsonicJukebox, address: credentials.serverID,
                                detail: credentials.serverURL.host)])
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

final class SubsonicJukeboxPlayer: RemotePlayer {
    let device: PlayOnDevice
    // ponytail: whether a jukebox's plays are scrobbled by the server is not
    // measured (no test server has one on); the app reports them.
    let reportsItself = false
    let capacity = 100
    private let client: SubsonicClient
    private var count = 0
    private var wantsToPlay = false
    private var index = 0

    init(device: PlayOnDevice, client: SubsonicClient) {
        self.device = device
        self.client = client
    }

    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws {
        count = entries.count
        index = 0
        wantsToPlay = play
        try await client.jukeboxSet(entries.map(\.track.id))
        if position > 1 { try await client.jukeboxSkip(to: 0, offset: position) }
        if play { try await client.jukeboxStart() }
    }

    func append(_ entries: [RemoteEntry]) async throws {
        count += entries.count
        try await client.jukeboxAdd(entries.map(\.track.id))
    }

    func resume() async throws {
        wantsToPlay = true
        try await client.jukeboxStart()
    }

    func pause() async throws {
        wantsToPlay = false
        try await client.jukeboxStop()
    }

    func seek(to position: TimeInterval) async throws {
        try await client.jukeboxSkip(to: index, offset: position)
    }

    func setVolume(_ level: Double) async throws { try await client.jukeboxGain(level) }

    func stop() async {
        try? await client.jukeboxStop()
        try? await client.jukeboxSet([])
    }

    func status() async throws -> RemoteStatus {
        let jukebox = try await client.jukeboxStatus()
        if let current = jukebox.currentIndex { index = current }
        var status = RemoteStatus(index: jukebox.currentIndex, position: jukebox.position,
                                  isPlaying: jukebox.playing, volume: jukebox.gain)
        // Stopped though it was asked to play, at the last song or past it.
        status.hasEnded = wantsToPlay && !jukebox.playing && (jukebox.currentIndex.map { $0 >= count - 1 } ?? true)
        if status.hasEnded { wantsToPlay = false }
        return status
    }
}

// MARK: - A Chromecast, spoken to by the app itself (Linux, the Mac)

/// The Default Media Receiver, one song at a time: the queue gives it the
/// next when one ends, so every rule and report stays the queue's.
// ponytail: a moment's silence between songs (the receiver fetches the
// next only once asked); its own queue (QUEUE_LOAD) when that matters.
final class CastPlayer: RemotePlayer {
    let device: PlayOnDevice
    let reportsItself = false
    let capacity = 1
    private let socket: any CastSocket
    private var session = CastSession()
    private var buffer = Data()
    private var closed = false
    private var heartbeat: Task<Void, Never>?

    init(device: PlayOnDevice, socket: any CastSocket) {
        self.device = device
        self.socket = socket
        socket.received = { [weak self] data in
            guard let self else { return }
            guard let data else {
                self.closed = true
                return
            }
            self.buffer.append(data)
            guard let messages = try? CastFrame.take(from: &self.buffer) else {
                self.closed = true
                self.socket.close()
                return
            }
            for message in messages { self.send(self.session.receive(message)) }
        }
        send(session.start())
        // The receiver drops a sender it has not heard from in a while.
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !self.closed else { return }
                self.send([self.session.ping()])
            }
        }
    }

    private func send(_ messages: [CastMessage]) {
        for message in messages { socket.send(CastFrame.encode(message)) }
    }

    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws {
        guard let entry = entries.first else { return }
        let track = entry.track
        let media = CastMedia(url: entry.stream.url, contentType: entry.stream.contentType, title: track.name,
                              artist: track.artistLine, album: track.albumName, artworkURL: entry.artworkURL,
                              duration: track.duration > 0 ? track.duration : nil)
        send(session.load(media, at: position, autoplay: play))
    }

    func append(_ entries: [RemoteEntry]) async throws {}
    func resume() async throws { send(session.play()) }
    func pause() async throws { send(session.pause()) }
    func seek(to position: TimeInterval) async throws { send(session.seek(to: position)) }
    func setVolume(_ level: Double) async throws { send(session.setVolume(level)) }

    func stop() async {
        send(session.stop())
        heartbeat?.cancel()
        closed = true
        socket.close()
    }

    func status() async throws -> RemoteStatus {
        if closed || session.isClosed { throw MusicServerError.transport("the cast device closed the connection") }
        var status = RemoteStatus(volume: session.volume)
        if session.loadError != nil { status.failed = true }
        guard let media = session.media else { return status }
        status.index = 0
        status.position = media.currentTime
        switch media.state {
        case .playing: status.isPlaying = true
        case .buffering: status.isBuffering = true
        case .paused: break
        case .idle:
            if media.idleReason == "FINISHED" { status.hasEnded = true }
            if media.idleReason == "ERROR" { status.failed = true }
        }
        return status
    }
}
