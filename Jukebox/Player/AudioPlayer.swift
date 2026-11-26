// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// The one player: the shared queue (PlayQueue.swift: what plays next,
// shuffle and repeat, the radio's feed, Up Next's edits, what the server
// and the history are told) with AVQueuePlayer for its engine, streaming
// from the server with the next track preloaded, so albums play without a
// gap. In the background and on the lock screen (MPNowPlayingInfoCenter,
// MPRemoteCommandCenter, thumbs up and down there too while a station
// plays), AirPlay, interruptions and headphones handled as Music does.
// Linux's player (Linux/App/AudioPlayer.swift) is the same queue with
// GStreamer.
//
// How it is built: the engine only ever holds the current entry's item and
// the next one's, rebuilt whenever the queue's next entry changes
// (`enginePreload`). When the engine moves on by itself — the gapless case —
// its new current item is the preloaded one, and the queue follows
// (`engineCurrentItemChanged`).
//
// Offline, a song that streamed is left once what it had loaded runs out
// (`watchOfflineStall`); the rest of offline is the queue's.

import AVFoundation
import Foundation
import JukeboxKit
import MediaPlayer

// RepeatMode, QueueContext and QueueEntry are in PlayQueue.swift too.

final class AudioPlayer: PlayQueue {
    /// An entry's item in the engine, with the play session it streams as.
    private struct Loaded {
        let entryID: UUID
        let item: AVPlayerItem
        let playSessionID: String
        let statusObservation: NSKeyValueObservation
    }

    private let engine = AVQueuePlayer()
    private let network: NetworkCost
    /// The mobile network, a hotspot or Low Data Mode (NetworkCost).
    override var isNetworkExpensive: Bool { network.isExpensive }
    private let nowPlaying: NowPlayingInfo
    private var remote: RemoteCommands?
    /// Whether this player is the system's: Now Playing, the media keys,
    /// the lock screen. False only in the Mac's snapshots, set before the
    /// player is made (NowPlayingInfo.isOn says why).
    static var claimsSystemControls = true

    /// The current entry's item: set before the queue begins it, so while
    /// an entry finishes (`stoppedPosition`) it is still that entry's.
    private var playingLoaded: Loaded?
    private var preloaded: Loaded?
    private var resumeAfterInterruption = false
    private var isSeeking = false
    /// Where to go once the current item can seek: a queue taken over from
    /// another device starts part-way, and is asked to before it is ready.
    private var pendingSeek: TimeInterval?
    private var seekGeneration = 0
    private var observations: [NSKeyValueObservation] = []
    private var notificationTokens: [any NSObjectProtocol] = []
    private var timeObserver: Any?
    /// Offline, waiting on a song that streamed: left after a moment.
    private var stallTask: Task<Void, Never>?

    override init(settings: AppSettings, history: HistoryStore) {
        network = NetworkCost()
        nowPlaying = NowPlayingInfo()
        super.init(settings: settings, history: history)
        engine.actionAtItemEnd = .advance
        // The screenshot walks play the demo's tones to picture a song on
        // air; muted, so the simulator on the MacBook plays nothing out loud
        // ("zorg jij of xcode of de ci's runs voor een soort wachtmuziek op
        // mijn macbook?", the photographer, 24 November 2026).
        engine.isMuted = UserDefaults.standard.bool(forKey: "silentWalk")
        // AirPlay as a route for the sound, streamed from this device, so
        // the session stays here and the receiver never fetches the song
        // itself. Jukebox has no video, so nothing needs the external kind.
        // The Mac's picker routes this player (SystemControls), so the Mac
        // keeps the default.
        #if os(iOS)
        engine.allowsExternalPlayback = false
        #endif
        // Music's own session: playback, long-form (AirPlay routes it as
        // music, not as a sound effect), on its own when the phone is silent.
        // A Mac has no audio session: its apps simply play.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        #endif
        observeEngine()
        observeNotifications()
        nowPlaying.isOn = Self.claimsSystemControls
        if Self.claimsSystemControls { remote = RemoteCommands(player: self) }
    }

    #if os(macOS)
    /// In front again: the Play key is Jukebox's (NowPlayingInfo.claim).
    func claimNowPlaying() {
        nowPlaying.claim()
    }
    #endif

    /// The playing entry's item; none while nothing plays.
    private var playingItem: AVPlayerItem? {
        playing == nil ? nil : playingLoaded?.item
    }

    override func stop() {
        super.stop()
        isSeeking = false
        nowPlaying.clear()
        refreshRemoteFeedback()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The lock screen's thumbs: on while a station plays, filled for a
    /// track liked or disliked. The radio calls this after the listener's
    /// thumbs; the queue whenever the track or the queue changes.
    override func refreshRemoteFeedback() {
        let id = currentTrack?.id
        let station = context?.isRadio == true && id != nil
        let liked = id.map { radio?.liked.contains($0) == true } ?? false
        let disliked = id.map { radio?.disliked.contains($0) == true } ?? false
        remote?.update(hasTrack: id != nil, stationPlays: station, liked: liked, disliked: disliked)
    }

    #if os(macOS)
    /// The engine, for the Mac's AirPlay picker, which routes one player's
    /// sound rather than the system's (RoutePicker).
    var routedPlayer: AVPlayer { engine }
    #endif

    // MARK: The engine, for the queue

    override func engineReplace(with url: URL, entry: QueueEntry, playSessionID: String, play: Bool) {
        if !play { engine.pause() }
        engine.removeAllItems()
        preloaded = nil
        let loaded = makeLoaded(url, entryID: entry.id, playSessionID: playSessionID)
        engine.insert(loaded.item, after: nil)
        playingLoaded = loaded
    }

    override func engineStart(_ play: Bool) {
        guard play else { return }
        activateAudioSession()
        engine.play()
    }

    /// The engine holds the current item and the next entry's: rebuilt
    /// only when the next entry changed.
    override func enginePreload(_ wanted: QueueEntry?) {
        if let preloaded, preloaded.entryID == wanted?.id,
           engine.items().contains(where: { $0 === preloaded.item }) {
            return
        }
        if let preloaded { engine.remove(preloaded.item) }
        preloaded = nil
        let playSessionID = UUID().uuidString
        guard let wanted, let current = playingItem,
              engine.items().contains(where: { $0 === current }),
              let url = address(of: wanted, playSessionID: playSessionID) else { return }
        let loaded = makeLoaded(url, entryID: wanted.id, playSessionID: playSessionID)
        guard engine.canInsert(loaded.item, after: current) else { return }
        engine.insert(loaded.item, after: current)
        preloaded = loaded
    }

    override var engineHeldNext: UUID? { preloaded?.entryID }

    override var engineHasItem: Bool { engine.currentItem != nil }

    override func engineResume() {
        activateAudioSession()
        engine.play()
    }

    override func enginePause() {
        engine.pause()
    }

    override func engineSeek(to target: TimeInterval) {
        isSeeking = true
        // An item just loaded cannot seek yet (HandoffStore loads and seeks
        // in one go, playing or paused), and AVPlayer is not to be asked
        // before it is ready (Apple's QA1820): itemStatusChanged asks then.
        guard let item = playingItem, item.status == .readyToPlay else {
            pendingSeek = target
            return
        }
        pendingSeek = nil
        seekGeneration += 1
        let generation = seekGeneration
        PlayerSignals.seek(engine, to: target) { [weak self] in
            Task { @MainActor in self?.seekFinished(generation) }
        }
    }

    override func engineHalt() {
        engine.pause()
        engine.removeAllItems()
        preloaded = nil
    }

    override func engineVolume(_ level: Double) {
        engine.volume = Float(level)
    }

    /// The engine may be running already (a skip while it plays): the
    /// clock starts with the entry, and so may its reports.
    override func engineBegan() {
        if engine.timeControlStatus == .playing {
            playing?.startClock(Date())
            reportStartIfNeeded()
        }
        isSeeking = false
        pendingSeek = nil
    }

    /// Where the current track is, as exactly as the engine knows.
    override var position: TimeInterval {
        if isSeeking { return elapsed }
        return Self.seconds(engine.currentTime()).map { max(0, $0) } ?? elapsed
    }

    /// The finishing entry's own item: in the gapless move the engine's
    /// current time is already the next song's.
    override var stoppedPosition: TimeInterval {
        playingLoaded.flatMap { Self.seconds($0.item.currentTime()) } ?? elapsed
    }

    override var playingLength: TimeInterval {
        playingLoaded.flatMap { Self.seconds($0.item.duration) } ?? 0
    }

    override var engineIsPaused: Bool { engine.timeControlStatus == .paused }

    /// Settings' Mobile quality where the network costs something.
    override var streamQuality: StreamQuality {
        DataCost.quality(expensive: network.isExpensive, wifi: settings.wifiQuality, cellular: settings.cellularQuality)
    }

    private func makeLoaded(_ url: URL, entryID: UUID, playSessionID: String) -> Loaded {
        let item = AVPlayerItem(url: url)
        // On the mobile network a minute ahead, not the whole file AVPlayer
        // would fetch: a song skipped, or the next one held for the gapless
        // move and then passed over, costs that much of it (DataCost).
        if let ahead = DataCost.forwardBuffer(expensive: network.isExpensive) {
            item.preferredForwardBufferDuration = ahead
        }
        let itemID = ObjectIdentifier(item)
        let observation = PlayerSignals.observeStatus(of: item) { [weak self] in
            Task { @MainActor in self?.itemStatusChanged(itemID) }
        }
        return Loaded(entryID: entryID, item: item, playSessionID: playSessionID, statusObservation: observation)
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
        playingLoaded = next
        begin(queue[index], at: index, playSessionID: next.playSessionID)
        deliver(finished)
        checkRadioSupply()
    }

    private func engineStatusChanged() {
        let status = engine.timeControlStatus
        let justStarted = engineRuns(status == .playing)
        let buffering = status == .waitingToPlayAtSpecifiedRate
        if isBuffering != buffering { isBuffering = buffering }
        if buffering { watchOfflineStall() }
        // Playing while waiting for the network too: the button shows Pause.
        showPlaying(status != .paused, justStarted: justStarted)
        publishPlayback()
    }

    private func tick() {
        // The sleep timer's deadline and fade, before anything else.
        checkSleep()
        guard let playing, let item = playingItem, engine.currentItem === item else { return }
        if !isSeeking, let time = Self.seconds(engine.currentTime()) {
            let value = max(0, time)
            if abs(value - elapsed) > 0.01 { elapsed = value }
        }
        let known = Self.seconds(item.duration) ?? 0
        let length = known > 0 ? known : playing.entry.track.duration
        if abs(length - duration) > 0.5 {
            duration = length
            publishPlayback()
        }
        // Normalisation turned on or off in Settings takes effect at once.
        let wanted = Float(level(for: playing.entry.track))
        if engine.volume != wanted { engine.volume = wanted }
        if engine.timeControlStatus == .playing { reportWhilePlaying() }
    }

    private func seekFinished(_ generation: Int) {
        guard generation == seekGeneration else { return }
        isSeeking = false
        if let time = Self.seconds(engine.currentTime()) { elapsed = max(0, time) }
        reportProgress()
        publishPlayback()
    }

    private func itemStatusChanged(_ id: ObjectIdentifier) {
        let items = [playingItem, preloaded?.item].compactMap { $0 }
        guard let item = items.first(where: { ObjectIdentifier($0) == id }) else { return }
        // Ready, and a place to start from was waiting for that (seek).
        if item.status == .readyToPlay, let target = pendingSeek, item === playingItem {
            seek(to: target)
            return
        }
        guard item.status == .failed else { return }
        itemFailed(id)
    }

    private func itemDidEnd(_ id: ObjectIdentifier) {
        guard let item = playingItem, ObjectIdentifier(item) == id else { return }
        // Preloaded: the engine moves on by itself, and
        // engineCurrentItemChanged follows it. (Repeat One preloads nothing.)
        if repeatMode != .one, let preloaded, engine.items().contains(where: { $0 === preloaded.item }) { return }
        entryEnded()
    }

    private func itemFailed(_ id: ObjectIdentifier) {
        if let item = playingItem, ObjectIdentifier(item) == id {
            // Why, by kind (Stats); never the song or the error's words.
            entryFailed(reason: Stats.playbackFailure(item.error))
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
        #if os(iOS)
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
        #endif
    }

    #if os(iOS)
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
    #endif

    private func activateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    // MARK: The lock screen

    private var rate: Double { engine.timeControlStatus == .playing ? 1 : 0 }

    override func publishNowPlaying() {
        guard let playing, let currentIndex else {
            nowPlaying.clear()
            return
        }
        nowPlaying.show(playing.entry, index: currentIndex, count: queue.count, elapsed: position,
                        duration: duration, rate: rate, server: server)
    }

    private func publishPlayback() {
        nowPlaying.updatePlayback(elapsed: position, duration: duration, rate: rate)
    }

    // MARK: Offline

    /// The network went or came back (OfflineStore, through AppModel): what
    /// is preloaded is chosen again — offline the next song may be a later
    /// one, back online the very next again — and a song waiting on the
    /// network is watched. A stream stepped down for a slow network
    /// starts at the target again (`networkChanged`).
    func connectivityChanged() {
        networkChanged()
        preloadNext()
        if isBuffering { watchOfflineStall() }
    }

    /// Offline, a song that streams stops when what it had loaded runs out,
    /// and AVPlayer would wait for the network for ever: after three seconds
    /// of waiting it is left for the next song on the phone.
    private func watchOfflineStall() {
        guard let offline, offline.isOffline, let entry = current, !offline.has(entry.track.id) else { return }
        let entryID = entry.id
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.isBuffering, self.current?.id == entryID,
                  self.offline?.isOffline == true else { return }
            self.next()
        }
    }

    /// A CMTime's seconds, nil while it is not known (indefinite, NaN).
    private static func seconds(_ time: CMTime) -> TimeInterval? {
        let value = time.seconds
        return value.isFinite ? value : nil
    }
}
