// Linux's player: the iPhone's AudioPlayer (Jukebox/Player/AudioPlayer.swift)
// with GStreamer where that has AVQueuePlayer. The same queue of the same
// entries (PlayQueue.swift), the same names and the same rules — what the
// server is told and when, what a play is, what the radio hears of it — so
// the shared RadioController drives either, and a screen written for one
// reads the same on the other. Songs kept on the machine (the shared
// OfflineStore) play from their files, online too, and offline only they
// play, as on the iPhone. What Linux leaves out: the lock screen.
//
// How it is built: the queue is the truth; `playbin3` plays one address at
// a time. For albums without a gap GStreamer asks, a moment before a song
// ends, what comes next ("about-to-finish", on its own thread): the next
// entry's address waits for it in `handover`, and when the new stream
// starts the queue follows, as it follows AVQueuePlayer on the iPhone.

import CGlue
import CGst
import Foundation
import JukeboxKit
import Observation

/// The next song's address, for GStreamer's thread to take when it asks.
private nonisolated final class Handover: @unchecked Sendable {
    private let lock = NSLock()
    private var uri: String?
    private var taken = false

    func offer(_ uri: String?) {
        lock.lock(); defer { lock.unlock() }
        self.uri = uri
        taken = false
    }

    /// GStreamer's: the address, once.
    func take() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let uri, !taken else { return nil }
        taken = true
        return uri
    }

    /// Whether GStreamer took it, asked once the next stream has started.
    func wasTaken() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return taken
    }
}

@Observable
final class AudioPlayer {
    /// Everything, played and to come, in play order.
    private(set) var queue: [QueueEntry] = []
    /// Into `queue`; nil when nothing is loaded.
    private(set) var currentIndex: Int?
    private(set) var context: QueueContext?
    /// The entries queued from elsewhere (Play Next, Add to Queue): Up
    /// next shows the ones at the end under "Then". Kept here, not in the
    /// shared QueueEntry, so the iPhone's queue is untouched.
    private(set) var addedIDs: Set<UUID> = []
    private(set) var isPlaying = false
    /// Waiting for the network.
    private(set) var isBuffering = false
    /// Seconds into the current track.
    private(set) var elapsed: TimeInterval = 0
    /// The current track's length, seconds.
    private(set) var duration: TimeInterval = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off {
        didSet { offerNext() }
    }
    /// The last error, for a moment in the player's bar ("Could not play …").
    private(set) var errorMessage: String?

    var server: (any MusicServer)?
    @ObservationIgnored weak var radio: RadioController?
    @ObservationIgnored var library: LibraryStore?
    /// Songs on the machine (AppModel's): their files play, and offline
    /// only they do.
    @ObservationIgnored weak var offline: OfflineStore?

    // MARK: Inside

    /// The current entry's play: what the server and the history are told.
    private struct Playing {
        let entry: QueueEntry
        let playSessionID: String
        var stationID: String?
        /// Seconds actually heard: the clock runs only while it plays.
        var heard: TimeInterval = 0
        var playingSince: Date?
        var didPlay = false
        var nowPlayingReported = false
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

    private struct Finished {
        let track: Track
        let listened: TimeInterval
        let stationID: String?
    }

    /// The listener's level, 0...1, kept across launches. It multiplies the
    /// song's loudness gain (`loudness(for:)`), so normalising never undoes it.
    var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1 {
        didSet {
            volume = min(1, max(0, volume))
            UserDefaults.standard.set(volume, forKey: "volume")
            applyVolume()
        }
    }

    private let settings: AppSettings
    private let history: HistoryStore
    private let engine: UnsafeMutablePointer<GstElement>
    private let handover = Handover()

    @ObservationIgnored private var playing: Playing?
    /// The entry whose address `handover` holds, with its play session.
    @ObservationIgnored private var offered: (entryID: UUID, playSessionID: String)?
    @ObservationIgnored private var originalOrder: [UUID]?
    @ObservationIgnored private var wantsToPlay = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var isAskingRadio = false
    @ObservationIgnored private var isGoingBack = false
    @ObservationIgnored private var errorGeneration = 0
    /// Where to go once the stream can seek (a queue taken over from
    /// another device starts part-way).
    @ObservationIgnored private var pendingSeek: TimeInterval?

    init(settings: AppSettings, history: HistoryStore) {
        self.settings = settings
        self.history = history
        gst_init(nil, nil)
        // playbin3 since GStreamer 1.22 is the one that is looked after;
        // playbin where a distribution's is older.
        engine = gst_element_factory_make("playbin3", "player") ?? gst_element_factory_make("playbin", "player")!
        // Music only: a file with a cover as video would open a window.
        jb_set_int(engine, "flags", 0x2 | 0x10 | 0x100)   // audio, soft-volume, buffering
        // JUKEBOX_AUDIO_SINK=fakesink plays to nowhere, in time (the tests).
        if let name = ProcessInfo.processInfo.environment["JUKEBOX_AUDIO_SINK"],
           let sink = gst_element_factory_make(name, "sink") {
            jb_set_bool(sink, "sync", 1)
            jb_set_object(engine, "audio-sink", sink)
        }
        watchEngine()
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
    /// anything but 0. `paused`: loaded, waiting for Play (HandoffStore's
    /// music from last time, at launch).
    func play(_ tracks: [Track], startingAt index: Int = 0, context: QueueContext, shuffled: Bool = false,
              paused: Bool = false) {
        guard !tracks.isEmpty else { return }
        var tracks = tracks
        var index = index
        if let offline, offline.isOffline {
            // As the iPhone's: made ready unasked, nothing; else the songs on
            // the machine, in their order, from the first of them (Play) or
            // the one clicked; one clicked that is not here says why.
            guard !paused else { return }
            let start = min(max(index, 0), tracks.count - 1)
            let here = tracks.filter { offline.canPlay($0.id) }
            guard !here.isEmpty else {
                showError(tracks.count == 1 ? OfflineText.notOnPhone(tracks[0]) : OfflineText.noneOnPhone)
                return
            }
            if offline.canPlay(tracks[start].id) {
                index = tracks[..<start].filter { offline.canPlay($0.id) }.count
            } else if start == 0 {
                index = 0
            } else {
                showError(OfflineText.notOnPhone(tracks[start]))
                return
            }
            tracks = here
            Stats.track(.offlinePlayStarted, ["from": Stats.source(context.kind)])
        }
        // Music only made ready has not started.
        if !paused { Stats.track(.playStarted, ["from": Stats.source(context.kind), "shuffled": shuffled]) }
        // Anything but a station ends the station that played.
        if !context.isRadio { radio?.stop() }
        let entries = tracks.map { QueueEntry(track: $0) }
        let start = min(max(index, 0), entries.count - 1)
        currentIndex = nil
        self.context = context
        addedIDs = []
        if shuffled {
            var rest = entries
            let first = rest.remove(at: index == 0 ? Int.random(in: entries.indices) : start)
            rest.shuffle()
            queue = [first] + rest
            originalOrder = entries.map(\.id)
            isShuffled = true
            load(0, play: !paused)
        } else {
            queue = entries
            originalOrder = nil
            isShuffled = false
            load(start, play: !paused)
        }
    }

    /// The radio's picks as a new queue (RadioController calls this).
    func playRadio(_ picks: [RadioPick], station: Station) {
        guard !picks.isEmpty else { return }
        Stats.track(.playStarted, ["from": "station", "shuffled": false])
        if offline?.isOffline == true { Stats.track(.offlinePlayStarted, ["from": "station"]) }
        currentIndex = nil
        context = QueueContext(.radio(station), title: station.title)
        addedIDs = []
        queue = picks.map { QueueEntry(track: $0.track, reason: $0.reason) }
        originalOrder = nil
        isShuffled = false
        // The radio chooses the order (the iPhone's playRadio says why).
        repeatMode = .off
        load(0, play: true)
    }

    /// "Start Radio" on the song that plays: it goes on from where it is,
    /// as the station's first, and the picks replace what came after it.
    func continueAsRadio(_ picks: [RadioPick], station: Station) {
        guard let currentIndex, queue.indices.contains(currentIndex) else {
            playRadio(picks, station: station)
            return
        }
        context = QueueContext(.radio(station), title: station.title)
        queue = Array(queue[...currentIndex]) + picks.map { QueueEntry(track: $0.track, reason: $0.reason) }
        originalOrder = nil
        isShuffled = false
        repeatMode = .off
        playing?.stationID = station.id
        queueChanged()
        resume()
    }

    /// The radio's further picks at the end of the queue.
    func appendRadio(_ picks: [RadioPick]) {
        if !picks.isEmpty {
            let entries = picks.map { QueueEntry(track: $0.track, reason: $0.reason) }
            queue.append(contentsOf: entries)
            if isShuffled { originalOrder?.append(contentsOf: entries.map(\.id)) }
            trimLongRadioHistory()
        }
        offerNext()
    }

    @discardableResult
    func removeUpcomingRadioPicks() -> [ItemID] {
        removeUpcomingRadioPicks(keepingNext: false)
    }

    /// Drop everything after the current track that the radio chose, so it
    /// can choose again; with `keepingNext` the entry GStreamer already
    /// took as the next one stays.
    @discardableResult
    func removeUpcomingRadioPicks(keepingNext: Bool) -> [ItemID] {
        guard let currentIndex else { return [] }
        var start = currentIndex + 1
        if keepingNext, let offered, handover.wasTaken(), start < queue.count, queue[start].id == offered.entryID {
            start += 1
        }
        guard start < queue.count else { return [] }
        let upcoming = queue[start...]
        let removed = upcoming.filter { $0.reason != nil }
        guard !removed.isEmpty else { return [] }
        queue = Array(queue[..<start]) + upcoming.filter { $0.reason == nil }
        offerNext()
        return removed.map(\.track.id)
    }

    func playNext(_ tracks: [Track]) {
        guard let tracks = playableNow(tracks) else { return }
        guard let currentIndex, hasTrack else {
            play(tracks, context: QueueContext(.other, title: "Up Next"))
            return
        }
        let entries = tracks.map { QueueEntry(track: $0) }
        addedIDs.formUnion(entries.map(\.id))
        queue.insert(contentsOf: entries, at: currentIndex + 1)
        if isShuffled, var order = originalOrder {
            let at = order.firstIndex(of: queue[currentIndex].id).map { $0 + 1 } ?? order.count
            order.insert(contentsOf: entries.map(\.id), at: at)
            originalOrder = order
        }
        queueChanged()
    }

    func addToQueue(_ tracks: [Track]) {
        guard let tracks = playableNow(tracks) else { return }
        guard hasTrack else {
            play(tracks, context: QueueContext(.other, title: "Up Next"))
            return
        }
        let entries = tracks.map { QueueEntry(track: $0) }
        addedIDs.formUnion(entries.map(\.id))
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
        if playing == nil {
            load(currentIndex, play: true)
            return
        }
        wantsToPlay = true
        gst_element_set_state(engine, GST_STATE_PLAYING)
    }

    func pause() {
        wantsToPlay = false
        gst_element_set_state(engine, GST_STATE_PAUSED)
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
        // Just loaded, the stream cannot seek yet (a queue taken over from
        // another device starts part-way): `stateChanged` goes there once
        // it can.
        var state = GST_STATE_NULL
        gst_element_get_state(engine, &state, nil, 0)
        guard state == GST_STATE_PAUSED || state == GST_STATE_PLAYING else {
            pendingSeek = target
            return
        }
        gst_element_seek_simple(engine, GST_FORMAT_TIME,
                                GstSeekFlags(GST_SEEK_FLAG_FLUSH.rawValue | GST_SEEK_FLAG_KEY_UNIT.rawValue),
                                jb_seconds(target))
        reportProgress()
    }

    func skip(to entry: QueueEntry) {
        guard let index = queue.firstIndex(where: { $0.id == entry.id }) else { return }
        if let offline, !offline.canPlay(entry.track.id) {
            showError(OfflineText.notOnPhone(entry.track))
            return
        }
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
        gst_element_set_state(engine, GST_STATE_NULL)
        handover.offer(nil)
        offered = nil
        currentIndex = nil
        queue = []
        context = nil
        elapsed = 0
        duration = 0
        isPlaying = false
        isBuffering = false
        isShuffled = false
        originalOrder = nil
        deliver(finished)
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

    /// Offsets into `upNext`, as List's onMove gives them (the iPhone's
    /// AudioPlayer, the same meaning).
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

    // MARK: For the radio and the screens

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

    /// The iPhone's lock screen shows the radio's thumbs; Linux has none to
    /// refresh. Here because the shared RadioController calls it.
    func refreshRemoteFeedback() {}

    /// The network went or came back (OfflineStore, through AppModel): the
    /// next song waiting for GStreamer is chosen again, offline perhaps a
    /// later one, back online the very next again.
    func connectivityChanged() {
        if !handover.wasTaken() {
            handover.offer(nil)
            offered = nil
        }
        offerNext()
    }

    // MARK: Loading

    /// Make `index` the current entry, from its start.
    private func load(_ index: Int, play: Bool) {
        guard queue.indices.contains(index) else { return }
        // Offline, a song not on the machine cannot play: the next one that
        // is, in its place; none, and the music stops here.
        guard let start = playableIndex(from: index) else {
            noMoreOnMachine()
            return
        }
        let entry = queue[start]
        let playSessionID = UUID().uuidString
        guard let url = address(of: entry, playSessionID: playSessionID) else {
            showError("Not signed in to a server.")
            return
        }
        let finished = finishCurrent()
        gst_element_set_state(engine, GST_STATE_NULL)
        handover.offer(nil)
        offered = nil
        jb_set_string(engine, "uri", url.absoluteString)
        wantsToPlay = play
        pendingSeek = nil
        begin(entry, at: start, playSessionID: playSessionID)
        gst_element_set_state(engine, play ? GST_STATE_PLAYING : GST_STATE_PAUSED)
        deliver(finished)
        checkRadioSupply()
    }

    /// Back to an entry before the current one. Going back is not "not
    /// this": the station is not told the track left was skipped.
    private func goBack(to index: Int) {
        // Offline, back to the nearest song before it that is on the
        // machine; none, and the song playing starts again.
        guard let target = playableIndex(atOrBefore: index) else {
            if playing != nil {
                seek(to: 0)
            } else if let currentIndex {
                load(currentIndex, play: true)
            }
            return
        }
        isGoingBack = true
        load(target, play: true)
        isGoingBack = false
    }

    /// `entry` is current now, its address already the engine's.
    private func begin(_ entry: QueueEntry, at index: Int, playSessionID: String) {
        currentIndex = index
        playing = Playing(entry: entry, playSessionID: playSessionID, stationID: context?.station?.id)
        elapsed = 0
        duration = entry.track.duration
        applyVolume(for: entry.track)
        offerNext()
    }

    /// The entry after the current one, by the queue and the repeat mode,
    /// waits in `handover` for GStreamer to ask for it.
    private func offerNext() {
        guard repeatMode != .one, let currentIndex, playing != nil,
              let next = indexAfter(currentIndex, wrapping: repeatMode == .all) else {
            if !handover.wasTaken() {
                handover.offer(nil)
                offered = nil
            }
            return
        }
        let entry = queue[next]
        // Already offered, or already taken (it will play next whatever
        // the queue now says: the queue follows it when it starts).
        if offered?.entryID == entry.id || handover.wasTaken() { return }
        let playSessionID = UUID().uuidString
        guard let url = address(of: entry, playSessionID: playSessionID) else { return }
        offered = (entry.id, playSessionID)
        handover.offer(url.absoluteString)
    }

    /// Where the entry's song is: its file when it is on the machine
    /// (always, online too: nothing to fetch, it starts at once), else the
    /// server's stream. Nil signed out.
    private func address(of entry: QueueEntry, playSessionID: String) -> URL? {
        if let file = offline?.localURL(for: entry.track.id) { return file }
        return server?.streamURL(for: entry.track, quality: settings.wifiQuality, playSessionID: playSessionID)
    }

    private func indexAfter(_ index: Int, wrapping: Bool) -> Int? {
        guard let offline, offline.isOffline else {
            if index + 1 < queue.count { return index + 1 }
            if wrapping, !queue.isEmpty { return 0 }
            return nil
        }
        // Offline, the next song that is on the machine: once round the queue at most.
        var at = index
        for _ in 0..<queue.count {
            if at + 1 < queue.count {
                at += 1
            } else if wrapping {
                at = 0
            } else {
                return nil
            }
            if offline.canPlay(queue[at].track.id) { return at }
        }
        return nil
    }

    /// `tracks` as far as they can play now: offline, those on the machine;
    /// nil, and why, briefly, when none of them can.
    private func playableNow(_ tracks: [Track]) -> [Track]? {
        guard !tracks.isEmpty else { return nil }
        guard let offline, offline.isOffline else { return tracks }
        let here = tracks.filter { offline.canPlay($0.id) }
        guard !here.isEmpty else {
            showError(tracks.count == 1 ? OfflineText.notOnPhone(tracks[0]) : OfflineText.noneOnPhone)
            return nil
        }
        return here
    }

    /// `index`, or offline the first entry from it on that is on the machine.
    private func playableIndex(from index: Int) -> Int? {
        guard let offline, offline.isOffline else { return index }
        return (index..<queue.count).first { offline.canPlay(queue[$0].track.id) }
    }

    /// `index`, or offline the last entry up to it that is on the machine.
    private func playableIndex(atOrBefore index: Int) -> Int? {
        guard let offline, offline.isOffline else { return index }
        guard queue.indices.contains(index) else { return nil }
        return stride(from: index, through: 0, by: -1).first { offline.canPlay(queue[$0].track.id) }
    }

    /// Offline, nothing from here on is on the machine: the music stops
    /// where it is, and says why.
    private func noMoreOnMachine() {
        let finished = finishCurrent()
        wantsToPlay = false
        gst_element_set_state(engine, GST_STATE_NULL)
        handover.offer(nil)
        offered = nil
        isPlaying = false
        deliver(finished)
        showError(OfflineText.nothingFurther)
    }

    /// The server's loudness for the song, as a volume: only ever softer.
    private func loudness(for track: Track) -> Double {
        guard settings.normalizeVolume, let gain = track.normalizationGain else { return 1 }
        return min(1, pow(10, gain / 20))
    }

    /// playbin's one volume: the listener's level times the song's.
    private func applyVolume(for track: Track? = nil) {
        guard let track = track ?? playing?.entry.track else { return }
        jb_set_double(engine, "volume", volume * loudness(for: track))
    }

    private func queueChanged() {
        offerNext()
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

    private func trimLongRadioHistory() {
        guard context?.isRadio == true, let currentIndex, currentIndex > 200 else { return }
        let drop = currentIndex - 100
        self.currentIndex = currentIndex - drop
        queue.removeFirst(drop)
    }

    // MARK: Ending

    /// The current entry stops being current: the server is told, and what
    /// was heard is returned for `deliver`.
    private func finishCurrent() -> Finished? {
        guard var playing else { return nil }
        self.playing = nil
        playing.stopClock(Date())
        if playing.startReported, let server {
            let report = PlaybackReport(trackID: playing.entry.track.id, position: elapsed, isPaused: false,
                                        playSessionID: playing.playSessionID)
            if let offline, offline.holdsReports(of: report.playSessionID) {
                // Told to the server, after its start, once it answers.
                offline.holdStop(report)
            } else {
                Task { await server.report(.stopped, report) }
            }
        }
        guard playing.didPlay else { return nil }
        var track = playing.entry.track
        if track.duration <= 0, duration > 0 { track.duration = duration }
        return Finished(track: track, listened: playing.heard, stationID: playing.stationID)
    }

    private func deliver(_ finished: Finished?) {
        guard let finished else { return }
        let now = Date()
        let outcome = PlayOutcome.of(listened: finished.listened, duration: finished.track.duration)
        Stats.track(.trackEnded, ["outcome": outcome.rawValue, "station": finished.stationID != nil])
        history.record(PlayEvent(track: finished.track, date: now, listened: finished.listened,
                                 outcome: outcome, stationID: finished.stationID))
        if outcome == .completed {
            library?.notePlayed(finished.track.id, at: now)
        }
        // Only to the station it played on, and not a skip made by going back.
        if let stationID = finished.stationID, let radio, radio.station?.id == stationID,
           !(isGoingBack && outcome == .skipped) {
            radio.trackEnded(finished.track, listened: finished.listened)
        }
    }

    /// Nothing after the current entry.
    private func queueEnded() {
        if context?.isRadio == true {
            radio?.playerNeedsMore()
            if let currentIndex, currentIndex + 1 < queue.count {
                load(currentIndex + 1, play: true)
                return
            }
        } else if repeatMode == .off, settings.autoplay, let radio, let last = currentTrack {
            // Autoplay: an album or a playlist plays on as a station from
            // its last track.
            let finished = finishCurrent()
            wantsToPlay = false
            gst_element_set_state(engine, GST_STATE_NULL)
            isPlaying = false
            deliver(finished)
            radio.autoplay(after: last)
            return
        }
        // The end: the last track stays, paused at its start.
        if let currentIndex { load(currentIndex, play: false) }
    }

    // MARK: What the engine says

    private func watchEngine() {
        let box = Unmanaged.passUnretained(self).toOpaque()
        // On GStreamer's own thread, a moment before a song ends: the next
        // address, if one waits. Nothing of the player is touched there.
        let handover = Unmanaged.passRetained(self.handover).toOpaque()
        g_signal_connect_data(engine, "about-to-finish", unsafeBitCast({ engine, data in
            guard let engine, let data else { return }
            let handover = Unmanaged<Handover>.fromOpaque(data).takeUnretainedValue()
            if let uri = handover.take() { jb_set_string(engine, "uri", uri) }
        } as @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void, to: GCallback.self),
                              handover, nil, GConnectFlags(rawValue: 0))
        // Messages on the main loop: the player lives as long as the app.
        let bus = gst_element_get_bus(engine)
        gst_bus_add_watch(bus, { _, message, data in
            guard let message, let data else { return 1 }
            let player = Unmanaged<AudioPlayer>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { player.engineSaid(message) }
            return 1
        }, box)
        gst_object_unref(bus)
        g_timeout_add(500, { data in
            guard let data else { return 0 }
            let player = Unmanaged<AudioPlayer>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { player.tick() }
            return 1
        }, box)
    }

    private func engineSaid(_ message: UnsafeMutablePointer<GstMessage>) {
        switch jb_message_type(message) {
        case GST_MESSAGE_EOS:
            trackDidEnd()
        case GST_MESSAGE_ERROR:
            let text = jb_message_error(message)
            let words = text.map { String(cString: $0) } ?? ""
            g_free(text)
            trackFailed(words)
        case GST_MESSAGE_STREAM_START:
            streamStarted()
        case GST_MESSAGE_BUFFERING:
            var percent: Int32 = 100
            gst_message_parse_buffering(message, &percent)
            let buffering = percent < 100
            if isBuffering != buffering { isBuffering = buffering }
            // As GStreamer asks of its applications: wait, paused, for a
            // stream that has run dry, and go on when it has filled.
            if wantsToPlay { gst_element_set_state(engine, buffering ? GST_STATE_PAUSED : GST_STATE_PLAYING) }
        case GST_MESSAGE_STATE_CHANGED:
            guard jb_message_is_from(message, engine) != 0 else { return }
            var old = GST_STATE_NULL, new = GST_STATE_NULL
            gst_message_parse_state_changed(message, &old, &new, nil)
            stateChanged(to: new)
        default:
            break
        }
    }

    /// A stream began. The one `load` asked for, or — GStreamer having
    /// taken the next address by itself — the next entry's: gapless, and
    /// the queue follows.
    private func streamStarted() {
        guard handover.wasTaken(), let offered,
              let index = queue.firstIndex(where: { $0.id == offered.entryID }) else { return }
        let finished = finishCurrent()
        self.offered = nil
        handover.offer(nil)
        begin(queue[index], at: index, playSessionID: offered.playSessionID)
        playing?.startClock(Date())
        reportStartIfNeeded()
        deliver(finished)
        checkRadioSupply()
    }

    private func stateChanged(to state: GstState) {
        let now = Date()
        var justStarted = false
        if state == GST_STATE_PLAYING {
            consecutiveFailures = 0
            playing?.startClock(now)
            justStarted = reportStartIfNeeded()
        } else {
            playing?.stopClock(now)
        }
        // Where a queue taken over from another device was left: a stream
        // can seek once it is paused or playing.
        if state == GST_STATE_PAUSED || state == GST_STATE_PLAYING, let target = pendingSeek {
            pendingSeek = nil
            gst_element_seek_simple(engine, GST_FORMAT_TIME,
                                    GstSeekFlags(GST_SEEK_FLAG_FLUSH.rawValue | GST_SEEK_FLAG_KEY_UNIT.rawValue),
                                    jb_seconds(target))
        }
        // Playing while waiting for the network too: the button shows Pause.
        let playingNow = playing != nil && (state == GST_STATE_PLAYING || (isBuffering && wantsToPlay))
        if isPlaying != playingNow {
            isPlaying = playingNow
            if !justStarted { reportProgress() }
        }
    }

    private func tick() {
        guard let playing else { return }
        var position: gint64 = 0
        if pendingSeek == nil, gst_element_query_position(engine, GST_FORMAT_TIME, &position) != 0 {
            let value = max(0, jb_from_nanoseconds(position))
            if abs(value - elapsed) > 0.01 { elapsed = value }
        }
        var total: gint64 = 0
        let known = gst_element_query_duration(engine, GST_FORMAT_TIME, &total) != 0 ? jb_from_nanoseconds(total) : 0
        let length = known > 0 ? known : playing.entry.track.duration
        if abs(length - duration) > 0.5 { duration = length }
        // Normalisation turned on or off in Preferences takes effect at once.
        applyVolume()
        if isPlaying, !isBuffering {
            if !playing.startReported {
                reportStartIfNeeded()
            } else if Date().timeIntervalSince(playing.lastProgress) >= 10 {
                reportProgress()
            }
        }
    }

    /// The stream ended with nothing taken to follow it.
    private func trackDidEnd() {
        guard playing != nil, let currentIndex else { return }
        if repeatMode == .one {
            load(currentIndex, play: true)
        } else if let next = indexAfter(currentIndex, wrapping: repeatMode == .all) {
            load(next, play: true)
        } else {
            queueEnded()
        }
    }

    private func trackFailed(_ words: String) {
        guard let playing else { return }
        let reason = Stats.playbackFailure(words)
        Stats.track(.playbackError, ["reason": reason])
        // The network: is the server still there? If not, offline, and the
        // next song is one on the machine.
        if reason == "network" { offline?.checkServer() }
        showError("Could not play “\(playing.entry.track.name)”.")
        consecutiveFailures += 1
        // Five in a row is the server or the network, not a file: stop
        // there rather than run through the whole queue.
        guard consecutiveFailures < 5, let currentIndex,
              let next = indexAfter(currentIndex, wrapping: repeatMode == .all), next != currentIndex else {
            let finished = finishCurrent()
            wantsToPlay = false
            gst_element_set_state(engine, GST_STATE_NULL)
            isPlaying = false
            deliver(finished)
            return
        }
        // Paused (music waiting at launch, HandoffStore), the next waits too.
        load(next, play: wantsToPlay)
    }

    // MARK: Telling the server

    /// The play counted (`played`), once it is not a skip by PlayOutcome's
    /// rule; the first call is also the moment the entry began, when
    /// `nowPlaying` goes. The iPhone's reportStartIfNeeded has the reasons.
    @discardableResult
    private func reportStartIfNeeded() -> Bool {
        reportNowPlayingIfNeeded()
        guard var playing, !playing.startReported else { return false }
        let now = Date()
        var heard = playing.heard
        if let since = playing.playingSince { heard += max(0, now.timeIntervalSince(since)) }
        var length = playing.entry.track.duration
        if length <= 0 { length = duration }
        guard PlayOutcome.of(listened: heard, duration: length) != .skipped else { return false }
        playing.startReported = true
        playing.lastProgress = now
        self.playing = playing
        guard let server else { return true }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: elapsed, isPaused: false,
                                    playSessionID: playing.playSessionID)
        if let offline, offline.holdsReports(of: report.playSessionID) {
            // Offline: kept, and sent when the server answers, so the play
            // is counted (and scrobbled) all the same.
            offline.holdStart(report)
        } else {
            Task { await server.report(.played, report) }
        }
        return true
    }

    private func reportNowPlayingIfNeeded() {
        guard var playing, !playing.nowPlayingReported else { return }
        playing.nowPlayingReported = true
        self.playing = playing
        guard let server else { return }
        // Not offline, where nothing would hear it, nor kept for later,
        // when it would be over.
        if let offline, offline.holdsReports(of: playing.playSessionID) { return }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: elapsed, isPaused: false,
                                    playSessionID: playing.playSessionID)
        Task { await server.report(.nowPlaying, report) }
    }

    private func reportProgress() {
        guard let playing, playing.startReported else { return }
        self.playing?.lastProgress = Date()
        guard let server else { return }
        // Offline the server hears of the play when it is back; how far it
        // got on the way is not kept.
        if let offline, offline.holdsReports(of: playing.playSessionID) { return }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: elapsed, isPaused: !isPlaying,
                                    playSessionID: playing.playSessionID)
        Task { await server.report(.progress, report) }
    }
}
