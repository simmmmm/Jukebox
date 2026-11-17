// The queue and its rules, on every platform: what plays and in what order,
// shuffle and repeat, the radio's feed, Up Next's edits, and what the
// server, the history and the radio are told. The AudioPlayer of the iPhone,
// the iPad and the Mac (AVQueuePlayer, Jukebox/Player/AudioPlayer.swift) and
// Linux's (GStreamer, Linux/App/AudioPlayer.swift) are this class with an
// engine: each overrides the `engine…` methods at the end and tells the
// queue what its engine did. Until 15 November 2026 each kept its own copy
// of these rules, and Up Next's "Then" was Linux's alone. Foundation only:
// Package.swift compiles this file for Linux as it is.
//
// How it is built: the queue (`queue`, `currentIndex`) is the truth; the
// engine holds the current entry and the next one (`entryToPreload`), so
// albums play without a gap. When the engine moves on by itself, the queue
// follows. Every entry that stops being current is "finished" once: the
// server is told it stopped, the history gets how long it was heard (time
// while playing, so a seek does not count), the radio its feedback.
//
// Songs on the device (OfflineStore) always play from their file: no data,
// and they start at once. Offline — no network, or a server that does not
// answer — only those can play: a list starts at its first song on the
// device, the others are passed over in the queue, and a tap on one that is
// not there says so. The reports the server would have had wait in the
// store until it answers again.
//
// The server is a MusicServer, Jellyfin or Subsonic, told the moments of a
// play by PlaybackEvent (docs/SERVERS.md, "Playback reports"): `nowPlaying`
// when the entry starts to play, `played` once it is not a skip (where every
// server counts the play: one rule, the app's, on all of them), `progress`
// and `stopped` after that only. Jellyfin hears nothing at `nowPlaying` (its
// start report counts a play); a Subsonic server shows the song as playing.

import Foundation
import JukeboxKit
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

/// What the sleep timer waits for before the music stops.
enum SleepChoice: Hashable, Sendable {
    case minutes(Int)
    case endOfSong
    /// The album's, the playlist's or the queue's last song; not on a
    /// station, which has no end.
    case endOfQueue

    /// Its `sleep_timer_set` value (docs/STATS.md).
    var statsValue: String {
        switch self {
        case let .minutes(minutes): "\(minutes)"
        case .endOfSong: "end_of_song"
        case .endOfQueue: "end_of_queue"
        }
    }
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
class PlayQueue {
    /// Everything, played and to come, in play order.
    private(set) var queue: [QueueEntry] = []
    /// Into `queue`; nil when nothing is loaded.
    private(set) var currentIndex: Int?
    private(set) var context: QueueContext?
    /// The entries queued from elsewhere (Play Next, Add to Queue): Up Next
    /// shows the ones at its end under "Then" (UpNextList).
    private(set) var addedIDs: Set<UUID> = []
    /// Set by the platform's AudioPlayer, as its engine says.
    var isPlaying = false
    /// Waiting for the network. The engine's, as `isPlaying`.
    var isBuffering = false
    /// Seconds into the current track. The engine's, as `isPlaying`.
    var elapsed: TimeInterval = 0
    /// The current track's length, seconds. The engine's, as `isPlaying`.
    var duration: TimeInterval = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off {
        // Repeat One keeps nothing preloaded; Repeat All preloads the first
        // entry after the last.
        didSet { preloadNext() }
    }
    /// The last error, for a moment in Now Playing or the bar ("Could not play …").
    private(set) var errorMessage: String?
    /// The listener's level, 0...1, kept across launches. Linux's and the
    /// Mac's sliders set it (VolumeControl); the iPhone's volume is the
    /// phone's own, so there it stays 1. It multiplies the song's loudness
    /// (`level(for:)`), so normalising never undoes it.
    var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1 {
        didSet {
            // @Observable keeps this didSet on its own storage, so setting
            // `volume` here runs it again: the clamp sets it once, and only
            // when out of range, else it never stops (Linux's slider crashed).
            guard (0...1).contains(volume) else { volume = min(1, max(0, volume)); return }
            UserDefaults.standard.set(volume, forKey: "volume")
            // At once, not at the clock's next tick: a slider is being moved.
            if let playing { engineVolume(level(for: playing.entry.track)) }
        }
    }

    /// The sleep timer set, nil off (`setSleepTimer`).
    private(set) var sleepChoice: SleepChoice?
    /// When a timer of minutes stops the music: a date, not a Timer, as
    /// iOS may suspend a Timer while the app plays in the background. The
    /// player's own ticks look at it (`checkSleep`).
    private(set) var sleepDeadline: Date?
    /// The seconds left on a timer of minutes, whole, for Linux's label;
    /// set on the ticks, only when it changes. SwiftUI counts down from
    /// `sleepDeadline` itself, paused too, when the iPhone's ticks rest.
    private(set) var sleepLeft: TimeInterval?

    var server: (any MusicServer)?
    /// Set by AppModel; the radio this player asks for more.
    @ObservationIgnored weak var radio: RadioController?
    /// Set by AppModel; told when a track was heard to the end, so play
    /// counts and "Recently Played" move without asking the server.
    @ObservationIgnored var library: LibraryStore?
    /// Set by AppModel: what is on the device, and whether only that can play.
    @ObservationIgnored weak var offline: OfflineStore?

    // MARK: Inside

    /// The current entry's play: what the server and the history are told.
    struct Playing {
        let entry: QueueEntry
        /// What the engine streams it as; the server's reports name it.
        let playSessionID: String
        /// The station it began on, kept: the context can change before it
        /// ends. Changed only by `continueAsRadio`, whose station the song
        /// then belongs to.
        var stationID: String?
        /// Seconds actually heard: the clock runs only while the engine plays.
        var heard: TimeInterval = 0
        var playingSince: Date?
        /// It played at all; one never started (loaded, then replaced) is
        /// neither a play nor a skip.
        var didPlay = false
        /// `nowPlaying` went: the server shows it as playing (Subsonic).
        var nowPlayingReported = false
        /// `played` went: the server counted the play.
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
    struct Finished {
        let track: Track
        let listened: TimeInterval
        let stationID: String?
    }

    let settings: AppSettings
    private let history: HistoryStore

    /// The current entry's play; its clock runs as the engine says.
    @ObservationIgnored var playing: Playing?
    /// Every entry's id in the order before shuffling, to go back to.
    @ObservationIgnored private var originalOrder: [UUID]?
    /// What the listener asked for, whatever the engine is doing (it pauses
    /// itself for a call, or waits for the network): what goes on after.
    @ObservationIgnored var wantsToPlay = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var isAskingRadio = false
    /// Set while the listener goes back to an earlier entry (`goBack`).
    @ObservationIgnored private var isGoingBack = false
    @ObservationIgnored private var errorGeneration = 0
    /// The sleep timer's fade, 1 to 0 over its last `sleepFade` seconds;
    /// in `level(for:)`, so the listener's own volume is never touched.
    @ObservationIgnored private var sleepFadeLevel: Double = 1
    static let sleepFade: TimeInterval = 8

    init(settings: AppSettings, history: HistoryStore) {
        self.settings = settings
        self.history = history
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
        // Siri's start, or the page's kind (Stats); taken at once, so a play
        // that does not start leaves nothing for the next.
        let from = Stats.takeFrom(context.kind)
        guard !tracks.isEmpty else { return }
        var tracks = tracks
        var index = index
        if let offline, offline.isOffline {
            // Made ready unasked: offline, nothing, rather than another song
            // or an error no one asked for (Home's notice still offers it).
            guard !paused else { return }
            // Offline, the songs on the device, in their order. Play (from
            // the top) starts at the first of them; a song tapped further
            // down that is not on the device says why, and nothing changes.
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
            // That music is played offline, and from what kind of thing (Stats).
            Stats.track(.offlinePlayStarted, ["from": from])
        }
        // What music is started from, by its kind (Stats); never the album.
        // Music only made ready has not started.
        if !paused { Stats.track(.playStarted, ["from": from, "shuffled": shuffled]) }
        // Anything but a station ends the station that played.
        if !context.isRadio { radio?.stop() }
        let entries = tracks.map { QueueEntry(track: $0) }
        let start = min(max(index, 0), entries.count - 1)
        // The index first, then the queue: `upNext` is never out of range.
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
        // The radio chooses the order: a Repeat One left on from an album
        // would play its first song for ever, and Up Next has no repeat
        // button while a station plays to turn it off again.
        repeatMode = .off
        // A station has no end to wait for.
        if sleepChoice == .endOfQueue { endSleep() }
        load(0, play: true)
    }

    /// "Start Radio" on the song that plays (RadioController calls this):
    /// the song goes on from where it is, as the station's first, and the
    /// picks replace what came after it. Through `playRadio` it started
    /// again from 0:00, and the part already heard went to the history as
    /// a skip (or a half listen) of the very song the station was asked for.
    func continueAsRadio(_ picks: [RadioPick], station: Station) {
        guard let currentIndex, queue.indices.contains(currentIndex) else {
            playRadio(picks, station: station)
            return
        }
        context = QueueContext(.radio(station), title: station.title)
        // What was played before it stays, as Up Next's history; nothing is
        // shuffled on a station.
        queue = Array(queue[...currentIndex]) + picks.map { QueueEntry(track: $0.track, reason: $0.reason) }
        originalOrder = nil
        isShuffled = false
        // As in playRadio: the radio chooses the order.
        repeatMode = .off
        if sleepChoice == .endOfQueue { endSleep() }
        // Its end, heard or skipped, is the station's feedback now (deliver).
        playing?.stationID = station.id
        queueChanged()
        refreshRemoteFeedback()
        // Starting a station plays, as playRadio does: from where it is
        // when paused, or loaded again when the engine has nothing.
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
    /// one stays when the engine already holds it: what the radio uses when
    /// new sources arrive, so a track about to start is not swapped for no
    /// reason the listener gave.
    @discardableResult
    func removeUpcomingRadioPicks(keepingNext: Bool) -> [ItemID] {
        guard let currentIndex else { return [] }
        var start = currentIndex + 1
        if keepingNext, let held = engineHeldNext, start < queue.count, queue[start].id == held {
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
        // A deadline that passed while paused (the iPhone's ticks rest
        // then): the timer is over, not a reason to stop again at once.
        if let sleepDeadline, sleepDeadline <= Date() { endSleep() }
        // Nothing in the engine (the queue ended, or an error stopped it):
        // load the current entry again.
        if playing == nil || !engineHasItem {
            load(currentIndex, play: true)
            return
        }
        wantsToPlay = true
        engineResume()
    }

    func pause() {
        wantsToPlay = false
        enginePause()
    }

    func next() {
        guard let currentIndex else { return }
        // Repeat One repeats a track that ends, not one that is skipped.
        if let next = indexAfter(currentIndex, wrapping: wraps) {
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
        engineSeek(to: target)
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

    /// Nothing loaded, nothing queued. Each platform's AudioPlayer adds
    /// what its system shows of the player.
    func stop() {
        let finished = finishCurrent()
        wantsToPlay = false
        engineHalt()
        currentIndex = nil
        queue = []
        context = nil
        elapsed = 0
        duration = 0
        isShuffled = false
        originalOrder = nil
        endSleep()
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

    /// The lock screen's thumbs, on Apple's platforms (AudioPlayer
    /// overrides it); Linux has none. The radio calls it after the
    /// listener's thumbs; the queue whenever the track or the queue changes.
    func refreshRemoteFeedback() {}

    /// The system's Now Playing, on Apple's platforms (AudioPlayer
    /// overrides it): the song, its place in the queue, its time. Linux's
    /// MPRIS follows the player by itself.
    func publishNowPlaying() {}

    // MARK: Loading

    /// Make `index` the current entry, from its start, in a fresh engine.
    private func load(_ index: Int, play: Bool) {
        guard queue.indices.contains(index) else { return }
        // Offline, a song not on the device cannot play: the next one that
        // is, in its place; none, and the music stops here.
        guard let start = playableIndex(from: index) else {
            noMorePlayable()
            return
        }
        let entry = queue[start]
        let playSessionID = UUID().uuidString
        guard let url = address(of: entry, playSessionID: playSessionID) else {
            showError("Not signed in to a server.")
            return
        }
        let finished = finishCurrent()
        engineReplace(with: url, entry: entry, playSessionID: playSessionID, play: play)
        wantsToPlay = play
        begin(entry, at: start, playSessionID: playSessionID)
        engineStart(play)
        deliver(finished)
        checkRadioSupply()
    }

    /// Back to an entry before the current one. Going back is not "not
    /// this": the station is not told the track left was skipped, which
    /// would drop it from Up Next and count against its artist.
    private func goBack(to index: Int) {
        // Offline, back to the nearest song before it that is on the
        // device; none, and the song playing starts again.
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

    /// `entry` is current now, already the engine's: loaded by `load`, or
    /// moved on to by the engine itself (gapless).
    func begin(_ entry: QueueEntry, at index: Int, playSessionID: String) {
        currentIndex = index
        playing = Playing(entry: entry, playSessionID: playSessionID, stationID: context?.station?.id)
        engineBegan()
        elapsed = 0
        duration = entry.track.duration
        engineVolume(level(for: entry.track))
        preloadNext()
        publishNowPlaying()
        refreshRemoteFeedback()
    }

    /// The entry the engine should hold after the current one, by the
    /// queue and the repeat mode.
    private var entryToPreload: QueueEntry? {
        // End of Song: nothing held, so the song ends by itself and
        // `entryEnded` stops there.
        guard repeatMode != .one, sleepChoice != .endOfSong, let currentIndex, playing != nil,
              let next = indexAfter(currentIndex, wrapping: wraps) else { return nil }
        return queue[next]
    }

    /// Repeat All goes round, unless the sleep timer waits for the end.
    private var wraps: Bool { repeatMode == .all && sleepChoice != .endOfQueue }

    /// The engine is told the next entry whenever it may have changed (an
    /// edit, shuffle, repeat, the radio choosing again).
    func preloadNext() {
        enginePreload(entryToPreload)
    }

    /// Where the entry's song is: its file when it is on the device
    /// (always, online too: nothing to fetch, it starts at once), else the
    /// server's stream. Nil signed out.
    func address(of entry: QueueEntry, playSessionID: String) -> URL? {
        if let file = offline?.localURL(for: entry.track.id) { return file }
        return server?.streamURL(for: entry.track, quality: streamQuality, playSessionID: playSessionID)
    }

    private func indexAfter(_ index: Int, wrapping: Bool) -> Int? {
        guard let offline, offline.isOffline else {
            if index + 1 < queue.count { return index + 1 }
            if wrapping, !queue.isEmpty { return 0 }
            return nil
        }
        // Offline, the next song that is on the device: once round the queue at most.
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

    /// `tracks` as far as they can play now: offline, those on the device;
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

    /// `index`, or offline the first entry from it on that is on the device.
    private func playableIndex(from index: Int) -> Int? {
        guard let offline, offline.isOffline else { return index }
        return (index..<queue.count).first { offline.canPlay(queue[$0].track.id) }
    }

    /// `index`, or offline the last entry up to it that is on the device.
    private func playableIndex(atOrBefore index: Int) -> Int? {
        guard let offline, offline.isOffline else { return index }
        guard queue.indices.contains(index) else { return nil }
        return stride(from: index, through: 0, by: -1).first { offline.canPlay(queue[$0].track.id) }
    }

    /// Offline, nothing from here on is on the device: the music stops
    /// where it is, and says why.
    private func noMorePlayable() {
        let finished = finishCurrent()
        wantsToPlay = false
        engineHalt()
        deliver(finished)
        showError(OfflineText.nothingFurther)
    }

    /// The engine's one volume: the listener's level times the server's
    /// loudness for the song (Jellyfin's NormalizationGain, a Subsonic
    /// server's ReplayGain), which is only ever softer, since an engine
    /// cannot go above 1.
    func level(for track: Track) -> Double {
        let volume = volume * sleepFadeLevel
        guard settings.normalizeVolume, let gain = track.normalizationGain else { return volume }
        return volume * min(1, pow(10, gain / 20))
    }

    private func queueChanged() {
        preloadNext()
        publishNowPlaying()
        checkRadioSupply()
    }

    /// A station's queue keeps a few tracks ahead: at two or fewer, the
    /// radio is asked for more.
    func checkRadioSupply() {
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

    /// The current entry stops being current: the server is told, and what
    /// was heard is returned for `deliver` (called once the next entry is
    /// set up, so the radio sees the queue as it now is).
    func finishCurrent() -> Finished? {
        guard var playing else { return nil }
        // Where it stopped and how long it is, as its engine knows, read
        // while the engine still holds it.
        let position = stoppedPosition
        let length = playingLength
        self.playing = nil
        playing.stopClock(Date())
        if playing.startReported, let server {
            let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: false,
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
        if track.duration <= 0, length > 0 { track.duration = length }
        return Finished(track: track, listened: playing.heard, stationID: playing.stationID)
    }

    func deliver(_ finished: Finished?) {
        guard let finished else { return }
        let now = Date()
        let outcome = PlayOutcome.of(listened: finished.listened, duration: finished.track.duration)
        // Heard to the end, partly, or skipped, and whether on a station (Stats).
        Stats.track(.trackEnded, ["outcome": outcome.rawValue, "station": finished.stationID != nil])
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
        } else if repeatMode == .off, sleepChoice != .endOfQueue, settings.autoplay, let radio, let last = currentTrack {
            // Music's Autoplay: an album or a playlist plays on as a station
            // from its last track.
            let finished = finishCurrent()
            wantsToPlay = false
            engineHalt()
            deliver(finished)
            radio.autoplay(after: last)
            return
        }
        // The end: the last track stays, paused at its start, as Music leaves it.
        if sleepChoice == .endOfQueue { endSleep() }
        if let currentIndex { load(currentIndex, play: false) }
    }

    // MARK: What the engine says

    /// The engine began or stopped running: the play's clock follows, and
    /// the first moments may count already. True when `played` went now.
    @discardableResult
    func engineRuns(_ running: Bool) -> Bool {
        let now = Date()
        guard running else {
            playing?.stopClock(now)
            return false
        }
        consecutiveFailures = 0
        playing?.startClock(now)
        return reportStartIfNeeded()
    }

    /// What the play button shows; a change goes to the server (paused or
    /// resumed, for its dashboard), unless `played` just went.
    func showPlaying(_ playingNow: Bool, justStarted: Bool) {
        guard isPlaying != playingNow else { return }
        isPlaying = playingNow
        if !justStarted { reportProgress() }
    }

    /// The current entry's stream ended, with nothing after it in the
    /// engine: the next by the repeat mode.
    func entryEnded() {
        guard let currentIndex else { return }
        if sleepChoice == .endOfSong {
            // The song ended by itself, its own fade: the next waits, paused
            // at its start, for the morning.
            endSleep()
            load(indexAfter(currentIndex, wrapping: wraps) ?? currentIndex, play: false)
        } else if repeatMode == .one {
            load(currentIndex, play: true)
        } else if let next = indexAfter(currentIndex, wrapping: wraps) {
            load(next, play: true)
        } else {
            queueEnded()
        }
    }

    /// The current entry could not play; `reason` is its kind
    /// (Stats.playbackFailure), never the song or the error's words.
    func entryFailed(reason: String) {
        guard let playing else { return }
        Stats.track(.playbackError, ["reason": reason])
        // The network: is the server still there? If not, offline, and the
        // next song is one on the device.
        if reason == "network" { offline?.checkServer() }
        showError("Could not play “\(playing.entry.track.name)”.")
        consecutiveFailures += 1
        // Five in a row is the server or the network, not a file: stop
        // there rather than run through the whole queue.
        guard consecutiveFailures < 5, let currentIndex,
              let next = indexAfter(currentIndex, wrapping: repeatMode == .all), next != currentIndex else {
            let finished = finishCurrent()
            wantsToPlay = false
            engineHalt()
            deliver(finished)
            return
        }
        // Paused (music waiting at launch, HandoffStore), the next waits too.
        load(next, play: wantsToPlay)
    }

    // MARK: The sleep timer

    /// What the timer offers now: End of Queue not on a station.
    var sleepChoices: [SleepChoice] {
        var choices: [SleepChoice] = [15, 30, 45, 60].map { .minutes($0) }
        if hasTrack { choices.append(.endOfSong) }
        if hasTrack, context?.isRadio != true { choices.append(.endOfQueue) }
        return choices
    }

    /// "30 Minutes", "End of Album".
    func sleepTitle(_ choice: SleepChoice) -> String {
        switch choice {
        case .minutes(60): return "1 Hour"
        case let .minutes(minutes): return "\(minutes) Minutes"
        case .endOfSong: return "End of Song"
        case .endOfQueue:
            switch context?.kind {
            case .album: return "End of Album"
            case .playlist: return "End of Playlist"
            default: return "End of Queue"
            }
        }
    }

    /// The listener sets the timer, or turns it off (nil).
    func setSleepTimer(_ choice: SleepChoice?, now: Date = Date()) {
        // What was chosen, coarsely (Stats); a timer ending by itself is
        // not counted.
        Stats.track(.sleepTimerSet, ["value": choice?.statsValue ?? "off"])
        endSleep()
        sleepChoice = choice
        if case let .minutes(minutes) = choice {
            sleepDeadline = now.addingTimeInterval(TimeInterval(minutes * 60))
            sleepLeft = TimeInterval(minutes * 60)
        }
        preloadNext()
    }

    /// On the player's ticks: the volume fades over the timer's last
    /// seconds, and at its deadline the music pauses and the volume is the
    /// listener's again.
    func checkSleep(now: Date = Date()) {
        guard let sleepDeadline else { return }
        let left = sleepDeadline.timeIntervalSince(now)
        let shown = max(0, left.rounded(.up))
        if sleepLeft != shown { sleepLeft = shown }
        guard left <= Self.sleepFade else { return }
        if left > 0 {
            // Paused in the fade, it waits where it was.
            guard isPlaying else { return }
            sleepFadeLevel = left / Self.sleepFade
            if let playing { engineVolume(level(for: playing.entry.track)) }
            return
        }
        // Paused first, then the volume back, so nothing is heard loud.
        if isPlaying { pause() }
        endSleep()
    }

    /// The timer off, without a word to Stats; the volume whole again.
    private func endSleep() {
        guard sleepChoice != nil || sleepDeadline != nil else { return }
        let wasEndOfSong = sleepChoice == .endOfSong
        sleepChoice = nil
        sleepDeadline = nil
        sleepLeft = nil
        sleepFadeLevel = 1
        if let playing { engineVolume(level(for: playing.entry.track)) }
        if wasEndOfSong { preloadNext() }
    }

    // MARK: Telling the server

    /// The play counted (`played`), once the entry has played long enough
    /// not to be a skip by PlayOutcome's rule. Jellyfin counts the play at
    /// its start report (measured on 12.4, JellyfinClient.reportStart), a
    /// Subsonic server at `scrobble submission=true`: sent at once, every
    /// skip would gain a play count, and the next library load would cancel
    /// that skip in the radio's taste. `reportWhilePlaying` asks again.
    /// Called only while the engine plays, so the first call is also the
    /// moment the entry began: `nowPlaying` goes then.
    @discardableResult
    func reportStartIfNeeded() -> Bool {
        reportNowPlayingIfNeeded()
        guard var playing, !playing.startReported else { return false }
        let now = Date()
        var heard = playing.heard
        if let since = playing.playingSince { heard += max(0, now.timeIntervalSince(since)) }
        // The length deliver() judges the play by.
        var length = playing.entry.track.duration
        if length <= 0 { length = playingLength }
        guard PlayOutcome.of(listened: heard, duration: length) != .skipped else { return false }
        playing.startReported = true
        playing.lastProgress = now
        self.playing = playing
        guard let server else { return true }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: false,
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

    /// The server's "now playing" as the entry begins to play, before it
    /// counts: a Subsonic server lists it as playing (Jellyfin is told
    /// nothing here). Once an entry; not offline, where nothing would hear
    /// it, and not kept for later, when it would be over.
    private func reportNowPlayingIfNeeded() {
        guard var playing, !playing.nowPlayingReported else { return }
        playing.nowPlayingReported = true
        self.playing = playing
        guard let server else { return }
        if let offline, offline.holdsReports(of: playing.playSessionID) { return }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: false,
                                    playSessionID: playing.playSessionID)
        Task { await server.report(.nowPlaying, report) }
    }

    func reportProgress() {
        guard let playing, playing.startReported else { return }
        self.playing?.lastProgress = Date()
        guard let server else { return }
        // Offline the server hears of the play when it is back; how far it
        // got on the way is not kept.
        if let offline, offline.holdsReports(of: playing.playSessionID) { return }
        let report = PlaybackReport(trackID: playing.entry.track.id, position: position, isPaused: engineIsPaused,
                                    playSessionID: playing.playSessionID)
        Task { await server.report(.progress, report) }
    }

    /// Every half second while the engine plays: the play counted once it
    /// is not a skip, then the server's progress every 10 s.
    func reportWhilePlaying() {
        guard let playing else { return }
        if !playing.startReported {
            reportStartIfNeeded()
        } else if Date().timeIntervalSince(playing.lastProgress) >= 10 {
            reportProgress()
        }
    }

    // MARK: The engine's (each platform's AudioPlayer overrides these)

    /// Hold `entry` alone, from its start, at `url`; `play` follows in
    /// `engineStart`, once the queue has begun it.
    func engineReplace(with url: URL, entry: QueueEntry, playSessionID: String, play: Bool) {}
    /// Play what `engineReplace` loaded, or hold it paused.
    func engineStart(_ play: Bool) {}
    /// Hold `entry` ready after the current one, for the gapless move; nil
    /// none. Called whenever it may have changed.
    func enginePreload(_ entry: QueueEntry?) {}
    /// The entry the engine has already taken as the next, which the radio
    /// leaves in place (`removeUpcomingRadioPicks(keepingNext:)`).
    var engineHeldNext: UUID? { nil }
    /// False when the engine let go of the current entry by itself.
    var engineHasItem: Bool { true }
    func engineResume() {}
    func enginePause() {}
    /// After `elapsed` is the target.
    func engineSeek(to seconds: TimeInterval) {}
    /// Nothing in the engine: stopped, or nothing more to play.
    func engineHalt() {}
    func engineVolume(_ level: Double) {}
    /// The new current entry's `playing` is set; `elapsed` is still the last.
    func engineBegan() {}
    /// Where the current track is, as exactly as the engine knows: for the
    /// reports.
    var position: TimeInterval { elapsed }
    /// Where the current entry stopped, for its `stopped` report.
    var stoppedPosition: TimeInterval { elapsed }
    /// The current entry's length as the engine found it, for a track whose
    /// server gave none.
    var playingLength: TimeInterval { duration }
    var engineIsPaused: Bool { !isPlaying }
    /// What the server streams at.
    var streamQuality: StreamQuality { settings.wifiQuality }
}
