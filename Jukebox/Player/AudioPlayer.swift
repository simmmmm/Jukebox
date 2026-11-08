// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// The one player: a queue of tracks streamed from Jellyfin through
// AVQueuePlayer (the next track preloaded, so albums play without a gap),
// in the background and on the lock screen (MPNowPlayingInfoCenter,
// MPRemoteCommandCenter, thumbs up and down there too while a station
// plays), AirPlay, interruptions and headphones handled as Music does.
// It tells Jellyfin what plays (so play counts are right on every client),
// writes each play to the history, and asks the radio for more when a
// station's queue runs low.
//
// How it is built: the queue (`queue`, `currentIndex`) is the truth; the
// engine (AVQueuePlayer) only ever holds the current entry's item and the
// next one's, rebuilt whenever the next entry changes (an edit, shuffle,
// repeat, the radio choosing again). When the engine moves on by itself —
// the gapless case — its new current item is the preloaded one, and the
// queue follows. Every entry that stops being current is "finished" once:
// Jellyfin is told it stopped, the history gets how long it was heard
// (time while playing, so a seek does not count), the radio its feedback.

import AVFoundation
import Foundation
import JukeboxKit
import MediaPlayer
import Observation

enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one
}

/// What the queue was started from: its name in Now Playing ("Playing from
/// Kid A") and whether a station plays.
struct QueueContext: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case album(ItemID)
        case artist(ItemID)
        case playlist(ItemID)
        case mix(String)
        case genre(String)
        case songs
        case favorites
        case search
        case radio(Station)
        case other
    }

    var kind: Kind
    var title: String

    init(_ kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }

    var station: Station? {
        if case let .radio(station) = kind { return station }
        return nil
    }

    var isRadio: Bool { station != nil }
}

/// One place in the queue: the same track can be in it twice.
struct QueueEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let track: Track
    /// Why the radio chose it, shown under it in Up Next.
    let reason: PickReason?

    init(track: Track, reason: PickReason? = nil) {
        id = UUID()
        self.track = track
        self.reason = reason
    }
}

@Observable
final class AudioPlayer {
    /// Everything, played and to come, in play order.
    private(set) var queue: [QueueEntry] = []
    /// Into `queue`; nil when nothing is loaded.
    private(set) var currentIndex: Int?
    private(set) var context: QueueContext?
    private(set) var isPlaying = false
    /// Waiting for the network.
    private(set) var isBuffering = false
    /// Seconds into the current track.
    private(set) var elapsed: TimeInterval = 0
    /// The current track's length, seconds.
    private(set) var duration: TimeInterval = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off {
        // Repeat One keeps nothing preloaded; Repeat All preloads the first
        // entry after the last.
        didSet { preloadNext() }
    }
    /// The last error, for a moment in Now Playing ("Could not play …").
    private(set) var errorMessage: String?

    var client: JellyfinClient?
    /// Set by AppModel; the radio this player asks for more.
    @ObservationIgnored weak var radio: RadioController?
    /// Set by AppModel; told when a track was heard to the end, so play
    /// counts and "Recently Played" move without asking the server.
    @ObservationIgnored var library: LibraryStore?

    // MARK: Inside

    /// An entry's item in the engine, with the play session it streams as.
    private struct Loaded {
        let entryID: UUID
        let item: AVPlayerItem
        let playSessionID: String
        let statusObservation: NSKeyValueObservation
    }

    /// The current entry's play: what Jellyfin and the history are told.
    private struct Playing {
        let entry: QueueEntry
        let loaded: Loaded
        /// The station it began on, kept: the context can change before it ends.
        let stationID: String?
        /// Seconds actually heard: the clock runs only while the engine plays.
        var heard: TimeInterval = 0
        var playingSince: Date?
        /// It played at all; one never started (loaded, then replaced) is
        /// neither a play nor a skip.
        var didPlay = false
        var startReported = false
        var lastProgress = Date.distantPast

        mutating func startClock(_ now: Date) {
            if playingSince == nil { playingSince = now }
            didPlay = true
        }

        mutating func stopClock(_ now: Date) {
            guard let since = playingSince else { return }
            heard += max(0, now.timeIntervalSince(since))
            playingSince = nil
        }
    }

    /// An entry that stopped being current, for the history and the radio.
    private struct Finished {
        let track: Track
        let listened: TimeInterval
        let stationID: String?
    }

    private let settings: AppSettings
    private let history: HistoryStore
    private let engine = AVQueuePlayer()
    private let network: NetworkCost
    private let nowPlaying: NowPlayingInfo
    @ObservationIgnored private var remote: RemoteCommands?

    @ObservationIgnored private var playing: Playing?
    @ObservationIgnored private var preloaded: Loaded?
    /// Every entry's id in the order before shuffling, to go back to.
    @ObservationIgnored private var originalOrder: [UUID]?
    /// What the listener asked for, whatever the engine is doing (it pauses
    /// itself for a call): what an interruption's end goes back to.
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var isAskingRadio = false
    /// Set while the listener goes back to an earlier entry (`goBack`).
    @ObservationIgnored private var isGoingBack = false
    @ObservationIgnored private var errorGeneration = 0
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?

    init(settings: AppSettings, history: HistoryStore) {
        self.settings = settings
        self.history = history
        network = NetworkCost()
        nowPlaying = NowPlayingInfo()
        engine.actionAtItemEnd = .advance
        // Music's own session: playback, long-form (AirPlay routes it as
        // music, not as a sound effect), on its own when the phone is silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        observeEngine()
        observeNotifications()
        remote = RemoteCommands(player: self)
    }

    var current: QueueEntry? { currentIndex.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var currentTrack: Track? { current?.track }
    /// After the current one, in order.
    var upNext: [QueueEntry] {
        guard let currentIndex else { return queue }
        return Array(queue[(currentIndex + 1)...])
    }
    /// Before the current one, oldest first.
    var played: [QueueEntry] {
        guard let currentIndex else { return [] }
        return Array(queue[..<currentIndex])
    }
    var hasTrack: Bool { current != nil }

    // MARK: Starting

    /// Replace the queue with `tracks` and play from `index`; shuffled
    /// starts at a random track unless `index` is given explicitly as
    /// anything but 0.
    func play(_ tracks: [Track], startingAt index: Int = 0, context: QueueContext, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        // Anything but a station ends the station that played.
        if !context.isRadio { radio?.stop() }
        let entries = tracks.map { QueueEntry(track: $0) }
        let start = min(max(index, 0), entries.count - 1)
        // The index first, then the queue: `upNext` is never out of range.
        currentIndex = nil
        self.context = context
        if shuffled {
            var rest = entries
            let first = rest.remove(at: index == 0 ? Int.random(in: entries.indices) : start)
            rest.shuffle()
            queue = [first] + rest
            originalOrder = entries.map(\.id)
            isShuffled = true
            load(0, play: true)
        } else {
            queue = entries
            originalOrder = nil
            isShuffled = false
            load(start, play: true)
        }
    }

    /// The radio's picks as a new queue (RadioController calls this).
    func playRadio(_ picks: [RadioPick], station: Station) {
        guard !picks.isEmpty else { return }
        currentIndex = nil
        context = QueueContext(.radio(station), title: station.title)
        queue = picks.map { QueueEntry(track: $0.track, reason: $0.reason) }
        originalOrder = nil
        isShuffled = false
        // The radio chooses the order: a Repeat One left on from an album
        // would play its first song for ever, and Up Next has no repeat
        // button while a station plays to turn it off again.
        repeatMode = .off
        load(0, play: true)
    }

    /// The radio's further picks at the end of the queue.
    func appendRadio(_ picks: [RadioPick]) {
        if !picks.isEmpty {
            let entries = picks.map { QueueEntry(track: $0.track, reason: $0.reason) }
            queue.append(contentsOf: entries)
            if isShuffled { originalOrder?.append(contentsOf: entries.map(\.id)) }
            trimLongRadioHistory()
        }
        preloadNext()
        publishNowPlaying()
    }

    /// Drop everything after the current track that the radio chose, so it
    /// can choose again after feedback; returns those tracks' ids.
    @discardableResult
    func removeUpcomingRadioPicks() -> [ItemID] {
        removeUpcomingRadioPicks(keepingNext: false)
    }

    /// The same, but with `keepingNext` the entry right after the current
    /// one stays when it is already loaded in the engine: what the radio
    /// uses when new sources arrive, so a track about to start is not
    /// swapped for no reason the listener gave.
    @discardableResult
    func removeUpcomingRadioPicks(keepingNext: Bool) -> [ItemID] {
        guard let currentIndex else { return [] }
        var start = currentIndex + 1
        if keepingNext, let preloaded, start < queue.count, queue[start].id == preloaded.entryID {
            start += 1
        }
        guard start < queue.count else { return [] }
        let upcoming = queue[start...]
        let removed = upcoming.filter { $0.reason != nil }
        guard !removed.isEmpty else { return [] }
        queue = Array(queue[..<start]) + upcoming.filter { $0.reason == nil }
        preloadNext()
        return removed.map(\.track.id)
    }

    func playNext(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard let currentIndex, hasTrack else {
            play(tracks, context: QueueContext(.other, title: "Up Next"))
            return
        }
        let entries = tracks.map { QueueEntry(track: $0) }
        queue.insert(contentsOf: entries, at: currentIndex + 1)
        if isShuffled, var order = originalOrder {
            let at = order.firstIndex(of: queue[currentIndex].id).map { $0 + 1 } ?? order.count
            order.insert(contentsOf: entries.map(\.id), at: at)
            originalOrder = order
        }
        queueChanged()
    }

    func addToQueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard hasTrack else {
            play(tracks, context: QueueContext(.other, title: "Up Next"))
            return
        }
        let entries = tracks.map { QueueEntry(track: $0) }
        queue.append(contentsOf: entries)
        if isShuffled { originalOrder?.append(contentsOf: entries.map(\.id)) }
        queueChanged()
    }

    // MARK: Transport

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard let currentIndex else { return }
        // Nothing in the engine (the queue ended, or an error stopped it):
        // load the current entry again.
        if playing == nil || engine.currentItem == nil {
            load(currentIndex, play: true)
            return
        }
        wantsToPlay = true
        activateAudioSession()
        engine.play()
    }

    func pause() {
        wantsToPlay = false
        engine.pause()
    }

    func next() {
        guard let currentIndex else { return }
        // Repeat One repeats a track that ends, not one that is skipped.
        if let next = indexAfter(currentIndex, wrapping: repeatMode == .all) {
            load(next, play: true)
        } else {
            queueEnded()
        }
    }

    /// Back to the start of the track after 3 s, else the track before.
    func previous() {
        guard let currentIndex else { return }
        if elapsed > 3 || (currentIndex == 0 && repeatMode != .all) {
            if playing == nil { load(currentIndex, play: true) } else { seek(to: 0) }
        } else if currentIndex > 0 {
            goBack(to: currentIndex - 1)
        } else {
            goBack(to: queue.count - 1)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard playing != nil else { return }
        let upper = duration > 0 ? duration : max(seconds, 0)
        let target = max(0, min(seconds, upper))
        elapsed = target
        isSeeking = true
        seekGeneration += 1
        let generation = seekGeneration
        PlayerSignals.seek(engine, to: target) { [weak self] in
            Task { @MainActor in self?.seekFinished(generation) }
        }
    }

    func skip(to entry: QueueEntry) {
        guard let index = queue.firstIndex(where: { $0.id == entry.id }) else { return }
        if let currentIndex, index < currentIndex {
            goBack(to: index)
        } else {
            load(index, play: true)
        }
    }

    func toggleShuffle() {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return }
        let head = Array(queue[...currentIndex])
        var upcoming = Array(queue[(currentIndex + 1)...])
        if isShuffled {
            // Back to the order it had: what is still to come, in album or
            // playlist order again.
            if let order = originalOrder {
                var rank: [UUID: Int] = [:]
                for (position, id) in order.enumerated() { rank[id] = position }
                upcoming = upcoming.enumerated()
                    .sorted { a, b in
                        let ra = rank[a.element.id] ?? Int.max
                        let rb = rank[b.element.id] ?? Int.max
                        return ra != rb ? ra < rb : a.offset < b.offset
                    }
                    .map { $0.element }
            }
            originalOrder = nil
            isShuffled = false
        } else {
            originalOrder = queue.map(\.id)
            upcoming.shuffle()
            isShuffled = true
        }
        queue = head + upcoming
        queueChanged()
    }

    /// off → all → one → off.
    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func stop() {
        let finished = finishCurrent()
        wantsToPlay = false
        engine.pause()
        engine.removeAllItems()
        preloaded = nil
        currentIndex = nil
        queue = []
        context = nil
        elapsed = 0
        duration = 0
        isShuffled = false
        originalOrder = nil
        isSeeking = false
        nowPlaying.clear()
        refreshRemoteFeedback()
        deliver(finished)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Editing Up Next

    /// Offsets into `upNext`.
    func removeUpcoming(atOffsets offsets: IndexSet) {
        let base = (currentIndex ?? -1) + 1
        let indices = offsets.map { base + $0 }.filter { queue.indices.contains($0) }.sorted(by: >)
        guard !indices.isEmpty else { return }
        for index in indices { queue.remove(at: index) }
        queueChanged()
    }

    /// Offsets into `upNext`, as List's onMove gives them.
    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (currentIndex ?? -1) + 1
        guard base <= queue.count else { return }
        var upcoming = Array(queue[base...])
        let moving: [Int] = source.filter { upcoming.indices.contains($0) }
        guard !moving.isEmpty else { return }
        let entries = moving.map { upcoming[$0] }
        let target = destination - moving.filter { $0 < destination }.count
        for index in moving.sorted(by: >) { upcoming.remove(at: index) }
        upcoming.insert(contentsOf: entries, at: max(0, min(target, upcoming.count)))
        queue = Array(queue[..<base]) + upcoming
        queueChanged()
    }

    func clearUpcoming() {
        guard let currentIndex else {
            queue = []
            return
        }
        guard currentIndex + 1 < queue.count else { return }
        queue.removeSubrange((currentIndex + 1)...)
        queueChanged()
    }

    // MARK: For the radio and Now Playing

    /// An error to show for a moment ("Could not play …").
    func showError(_ message: String) {
        errorMessage = message
        errorGeneration += 1
        let generation = errorGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.errorGeneration == generation else { return }
            self.errorMessage = nil
        }
    }

    /// The lock screen's thumbs: on while a station plays, filled for a
    /// track liked or disliked. The radio calls this after the listener's
    /// thumbs; the player itself whenever the track or the queue changes.
    func refreshRemoteFeedback() {
        let id = currentTrack?.id
        let station = context?.isRadio == true && id != nil
        let liked = id.map { radio?.liked.contains($0) == true } ?? false
        let disliked = id.map { radio?.disliked.contains($0) == true } ?? false
        remote?.update(hasTrack: id != nil, stationPlays: station, liked: liked, disliked: disliked)
    }

    // MARK: Loading

    /// Make `index` the current entry, from its start, in a fresh engine.
    private func load(_ index: Int, play: Bool) {
        guard queue.indices.contains(index) else { return }
        let entry = queue[index]
        guard let loaded = makeLoaded(entry) else {
            showError("Not signed in to a server.")
            return
        }
        let finished = finishCurrent()
        if !play { engine.pause() }
        engine.removeAllItems()
        preloaded = nil
        engine.insert(loaded.item, after: nil)
        wantsToPlay = play
        begin(entry, at: index, loaded: loaded)
        if play {
            activateAudioSession()
            engine.play()
        }
        deliver(finished)
        checkRadioSupply()
    }

    /// Back to an entry before the current one. Going back is not "not
    /// this": the station is not told the track left was skipped, which
    /// would drop it from Up Next and count against its artist.
    private func goBack(to index: Int) {
        isGoingBack = true
        load(index, play: true)
        isGoingBack = false
    }

    /// `entry` is current now, with `loaded` already in the engine.
    private func begin(_ entry: QueueEntry, at index: Int, loaded: Loaded) {
        currentIndex = index
        var playing = Playing(entry: entry, loaded: loaded, stationID: context?.station?.id)
        let isRunning = engine.timeControlStatus == .playing
        if isRunning { playing.startClock(Date()) }
        self.playing = playing
        if isRunning { reportStartIfNeeded() }
        elapsed = 0
        duration = entry.track.duration
        isSeeking = false
        engine.volume = volume(for: entry.track)
        preloadNext()
        publishNowPlaying()
        refreshRemoteFeedback()
    }

    /// The entry the engine should hold after the current one, by the
    /// queue and the repeat mode.
    private func entryToPreload() -> QueueEntry? {
        guard repeatMode != .one, let currentIndex,
              let next = indexAfter(currentIndex, wrapping: repeatMode == .all) else { return nil }
        return queue[next]
    }

    /// The engine holds the current item and the next entry's: rebuilt
    /// only when the next entry changed.
    private func preloadNext() {
        let wanted = entryToPreload()
        if let preloaded, preloaded.entryID == wanted?.id,
           engine.items().contains(where: { $0 === preloaded.item }) {
            return
        }
        if let preloaded { engine.remove(preloaded.item) }
        preloaded = nil
        guard let wanted, let current = playing?.loaded.item,
              engine.items().contains(where: { $0 === current }),
              let loaded = makeLoaded(wanted),
              engine.canInsert(loaded.item, after: current) else { return }
        engine.insert(loaded.item, after: current)
        preloaded = loaded
    }

    private func makeLoaded(_ entry: QueueEntry) -> Loaded? {
        guard let client else { return nil }
        let playSessionID = UUID().uuidString
        let quality = network.isExpensive ? settings.cellularQuality : settings.wifiQuality
        let url = client.streamURL(trackID: entry.track.id, quality: quality, playSessionID: playSessionID)
        let item = AVPlayerItem(url: url)
        let itemID = ObjectIdentifier(item)
        let observation = PlayerSignals.observeStatus(of: item) { [weak self] in
            Task { @MainActor in self?.itemStatusChanged(itemID) }
        }
        return Loaded(entryID: entry.id, item: item, playSessionID: playSessionID, statusObservation: observation)
    }

    private func indexAfter(_ index: Int, wrapping: Bool) -> Int? {
        if index + 1 < queue.count { return index + 1 }
        if wrapping, !queue.isEmpty { return 0 }
        return nil
    }

    /// Jellyfin's measured loudness, as a volume: only ever softer, since
    /// the engine cannot go above 1.
    private func volume(for track: Track) -> Float {
        guard settings.normalizeVolume, let gain = track.normalizationGain else { return 1 }
        return Float(min(1, pow(10, gain / 20)))
    }

    private func queueChanged() {
        preloadNext()
        publishNowPlaying()
        checkRadioSupply()
    }

    /// A station's queue keeps a few tracks ahead: at two or fewer, the
    /// radio is asked for more.
    private func checkRadioSupply() {
        guard context?.isRadio == true, !isAskingRadio, let currentIndex,
              queue.count - currentIndex - 1 <= 2 else { return }
        isAskingRadio = true
        radio?.playerNeedsMore()
        isAskingRadio = false
    }

    /// A station plays for hours; the played part of its queue is kept to
    /// the last hundred or so.
    private func trimLongRadioHistory() {
        guard context?.isRadio == true, let currentIndex, currentIndex > 200 else { return }
        let drop = currentIndex - 100
        // The index first: it is never past the end of the queue.
        self.currentIndex = currentIndex - drop
        queue.removeFirst(drop)
    }

    // MARK: Ending

    /// The current entry stops being current: Jellyfin is told, and what
    /// was heard is returned for `deliver` (called once the next entry is
    /// set up, so the radio sees the queue as it now is).
    private func finishCurrent() -> Finished? {
        guard var playing else { return nil }
        self.playing = nil
        playing.stopClock(Date())
        if playing.startReported, let client {
            let position = Self.seconds(playing.loaded.item.currentTime()) ?? elapsed
            let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: false,
                                        playSessionID: playing.loaded.playSessionID)
            Task { await client.reportStopped(report) }
        }
        guard playing.didPlay else { return nil }
        var track = playing.entry.track
        if track.duration <= 0, let known = Self.seconds(playing.loaded.item.duration), known > 0 {
            track.duration = known
        }
        return Finished(track: track, listened: playing.heard, stationID: playing.stationID)
    }

    private func deliver(_ finished: Finished?) {
        guard let finished else { return }
        let now = Date()
        let outcome = PlayOutcome.of(listened: finished.listened, duration: finished.track.duration)
        history.record(PlayEvent(track: finished.track, date: now, listened: finished.listened,
                                 outcome: outcome, stationID: finished.stationID))
        if outcome == .completed {
            library?.notePlayed(finished.track.id, at: now)
        }
        // Only to the station it played on: a track of the station before
        // says nothing about this one. Nor a skip made by going back.
        if let stationID = finished.stationID, let radio, radio.station?.id == stationID,
           !(isGoingBack && outcome == .skipped) {
            radio.trackEnded(finished.track, listened: finished.listened)
        }
    }

    /// Nothing after the current entry.
    private func queueEnded() {
        if context?.isRadio == true {
            // The radio is a few tracks ahead; if it is not, ask once more.
            radio?.playerNeedsMore()
            if let currentIndex, currentIndex + 1 < queue.count {
                load(currentIndex + 1, play: true)
                return
            }
        } else if repeatMode == .off, settings.autoplay, let radio, let last = currentTrack {
            // Music's Autoplay: an album or a playlist plays on as a station
            // from its last track.
            let finished = finishCurrent()
            wantsToPlay = false
            engine.pause()
            engine.removeAllItems()
            preloaded = nil
            deliver(finished)
            radio.autoplay(after: last)
            return
        }
        // The end: the last track stays, paused at its start, as Music leaves it.
        if let currentIndex { load(currentIndex, play: false) }
    }

    // MARK: What the engine says

    private func observeEngine() {
        observations.append(PlayerSignals.observeCurrentItem(of: engine) { [weak self] in
            Task { @MainActor in self?.engineCurrentItemChanged() }
        })
        observations.append(PlayerSignals.observeTimeControlStatus(of: engine) { [weak self] in
            Task { @MainActor in self?.engineStatusChanged() }
        })
        timeObserver = PlayerSignals.every(0.5, on: engine) { [weak self] in
            // Asked for on the main queue.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// The engine moved on by itself: gapless, to the preloaded entry.
    private func engineCurrentItemChanged() {
        guard let next = preloaded, let item = engine.currentItem, item === next.item,
              let index = queue.firstIndex(where: { $0.id == next.entryID }) else { return }
        let finished = finishCurrent()
        preloaded = nil
        begin(queue[index], at: index, loaded: next)
        deliver(finished)
        checkRadioSupply()
    }

    private func engineStatusChanged() {
        let status = engine.timeControlStatus
        let now = Date()
        var justStarted = false
        if status == .playing {
            consecutiveFailures = 0
            playing?.startClock(now)
            justStarted = reportStartIfNeeded()
        } else {
            playing?.stopClock(now)
        }
        let buffering = status == .waitingToPlayAtSpecifiedRate
        if isBuffering != buffering { isBuffering = buffering }
        // Playing while waiting for the network too: the button shows Pause.
        let playingNow = status != .paused
        if isPlaying != playingNow {
            isPlaying = playingNow
            // Paused or resumed, so Jellyfin's dashboard shows it.
            if !justStarted { reportProgress() }
        }
        publishPlayback()
    }

    private func tick() {
        guard let playing, engine.currentItem === playing.loaded.item else { return }
        if !isSeeking, let time = Self.seconds(engine.currentTime()) {
            let value = max(0, time)
            if abs(value - elapsed) > 0.01 { elapsed = value }
        }
        let known = Self.seconds(playing.loaded.item.duration) ?? 0
        let length = known > 0 ? known : playing.entry.track.duration
        if abs(length - duration) > 0.5 {
            duration = length
            publishPlayback()
        }
        // Normalisation turned on or off in Settings takes effect at once.
        let level = volume(for: playing.entry.track)
        if engine.volume != level { engine.volume = level }
        if engine.timeControlStatus == .playing {
            if !playing.startReported {
                reportStartIfNeeded()
            } else if Date().timeIntervalSince(playing.lastProgress) >= 10 {
                reportProgress()
            }
        }
    }

    private func seekFinished(_ generation: Int) {
        guard generation == seekGeneration else { return }
        isSeeking = false
        if let time = Self.seconds(engine.currentTime()) { elapsed = max(0, time) }
        reportProgress()
        publishPlayback()
    }

    private func itemStatusChanged(_ id: ObjectIdentifier) {
        let items = [playing?.loaded.item, preloaded?.item].compactMap { $0 }
        guard let item = items.first(where: { ObjectIdentifier($0) == id }), item.status == .failed else { return }
        itemFailed(id)
    }

    private func itemDidEnd(_ id: ObjectIdentifier) {
        guard let playing, ObjectIdentifier(playing.loaded.item) == id, let currentIndex else { return }
        if repeatMode == .one {
            load(currentIndex, play: true)
            return
        }
        // Preloaded: the engine moves on by itself, and
        // engineCurrentItemChanged follows it.
        if let preloaded, engine.items().contains(where: { $0 === preloaded.item }) { return }
        if let next = indexAfter(currentIndex, wrapping: repeatMode == .all) {
            load(next, play: true)
        } else {
            queueEnded()
        }
    }

    private func itemFailed(_ id: ObjectIdentifier) {
        if let playing, ObjectIdentifier(playing.loaded.item) == id {
            showError("Could not play “\(playing.entry.track.name)”.")
            consecutiveFailures += 1
            // Five in a row is the server or the network, not a file: stop
            // there rather than run through the whole queue.
            guard consecutiveFailures < 5, let currentIndex,
                  let next = indexAfter(currentIndex, wrapping: repeatMode == .all), next != currentIndex else {
                let finished = finishCurrent()
                wantsToPlay = false
                engine.pause()
                deliver(finished)
                return
            }
            load(next, play: true)
        } else if let preloaded, ObjectIdentifier(preloaded.item) == id {
            // Tried again, fresh, when its turn comes (itemDidEnd loads it).
            engine.remove(preloaded.item)
            self.preloaded = nil
        }
    }

    // MARK: What the system says

    private func observeNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                     object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            MainActor.assumeIsolated {
                guard let self else { return }
                self.itemDidEnd(id)
            }
        })
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                                     object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            MainActor.assumeIsolated {
                guard let self else { return }
                self.itemFailed(id)
            }
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                                     object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                self.interruption(type: type, options: options)
            }
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                     object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                self.routeChanged(reason: reason)
            }
        })
    }

    /// A call, an alarm, Siri: paused by the system; resumed when it says
    /// so and the music was playing before.
    private func interruption(type rawType: UInt?, options rawOptions: UInt?) {
        guard let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            resumeAfterInterruption = wantsToPlay
            wantsToPlay = false
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            if resumeAfterInterruption, options.contains(.shouldResume) { resume() }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
    }

    /// Headphones out, or a Bluetooth speaker gone: pause, never blare
    /// from the phone's speaker.
    private func routeChanged(reason rawReason: UInt?) {
        guard let rawReason, AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else {
            return
        }
        pause()
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: Telling Jellyfin and the lock screen

    /// Jellyfin's "now playing", once the entry has played long enough not
    /// to be a skip by PlayOutcome's rule. Jellyfin counts the play at the
    /// start report (measured on 12.4, JellyfinClient.reportStart): sent at
    /// once, every skip would gain a play count, and the next library load
    /// would cancel that skip in the radio's taste. tick() asks again while
    /// it plays.
    @discardableResult
    private func reportStartIfNeeded() -> Bool {
        guard var playing, !playing.startReported else { return false }
        let now = Date()
        var heard = playing.heard
        if let since = playing.playingSince { heard += max(0, now.timeIntervalSince(since)) }
        // The length deliver() judges the play by.
        var length = playing.entry.track.duration
        if length <= 0 { length = Self.seconds(playing.loaded.item.duration) ?? 0 }
        guard PlayOutcome.of(listened: heard, duration: length) != .skipped else { return false }
        playing.startReported = true
        playing.lastProgress = now
        self.playing = playing
        guard let client else { return true }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: false,
                                    playSessionID: playing.loaded.playSessionID)
        Task { await client.reportStart(report) }
        return true
    }

    private func reportProgress() {
        guard let playing, playing.startReported else { return }
        self.playing?.lastProgress = Date()
        guard let client else { return }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: position,
                                    isPaused: engine.timeControlStatus == .paused,
                                    playSessionID: playing.loaded.playSessionID)
        Task { await client.reportProgress(report) }
    }

    /// Where the current track is, as exactly as the engine knows.
    private var position: TimeInterval {
        if isSeeking { return elapsed }
        return Self.seconds(engine.currentTime()).map { max(0, $0) } ?? elapsed
    }

    private var rate: Double { engine.timeControlStatus == .playing ? 1 : 0 }

    private func publishNowPlaying() {
        guard let playing, let currentIndex else {
            nowPlaying.clear()
            return
        }
        nowPlaying.show(playing.entry, index: currentIndex, count: queue.count, elapsed: position,
                        duration: duration, rate: rate, client: client)
    }

    private func publishPlayback() {
        nowPlaying.updatePlayback(elapsed: position, duration: duration, rate: rate)
    }

    /// A CMTime's seconds, nil while it is not known (indefinite, NaN).
    private static func seconds(_ time: CMTime) -> TimeInterval? {
        let value = time.seconds
        return value.isFinite ? value : nil
    }
}
