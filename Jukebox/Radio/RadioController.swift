// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// The radio in the app: one RadioSession (JukeboxKit) for the station that
// plays, fed into the player a few tracks ahead. A station starts within a
// moment from the library alone; Jellyfin's Instant Mix and, with a key,
// Last.fm's similar tracks join it as they arrive. Feedback — a skip, a
// thumbs up or down, a track heard to the end — goes to the session, and
// after a skip or a thumbs the tracks ahead are chosen again.
//
// The photographer's favourite part ("ik vind vooral de radiofunctie echt
// belangrijk", 8 November 2026), so it is built to feel instant: the first
// four tracks come from the library in memory, chosen off the main actor,
// and the first one plays before the network has been asked anything. What
// Jellyfin and Last.fm add changes only the tracks not yet loaded.

import Foundation
import JukeboxKit
import Observation

@Observable
final class RadioController {
    /// The station playing, if one is.
    private(set) var station: Station?
    /// Starting: the first tracks are being chosen.
    private(set) var isStarting = false
    /// The graph from the library and Last.fm, as far as it is known.
    private(set) var graph = SimilarityGraph()
    /// Liked and disliked in this session, for the thumbs' state.
    private(set) var liked: Set<ItemID> = []
    private(set) var disliked: Set<ItemID> = []

    var client: JellyfinClient?

    private let player: AudioPlayer
    private let library: LibraryStore
    private let history: HistoryStore
    private let settings: AppSettings

    @ObservationIgnored private var session: RadioSession?
    @ObservationIgnored private var service: SimilarityService?
    /// Bumped by every start and stop: work for an older station, still
    /// arriving, is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sourceTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var graphTask: Task<Void, Never>?
    @ObservationIgnored private var enrichTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var dialTask: Task<Void, Never>?
    @ObservationIgnored private var isWatchingLibrary = false
    /// Set while the radio itself moves the player on (a thumbs down skips
    /// the track): that skip is the listener's thumbs, already acted on.
    @ObservationIgnored private var isHandlingFeedback = false

    init(player: AudioPlayer, library: LibraryStore, history: HistoryStore, settings: AppSettings) {
        self.player = player
        self.library = library
        self.history = history
        self.settings = settings
    }

    /// After sign-in: the graph from the library, then Last.fm in the
    /// background when there is a key.
    func prepare() {
        if service == nil { service = makeService() }
        rebuildGraph()
        watchLibrary()
    }

    func start(_ seed: StationSeed) {
        start(station(for: seed))
    }

    func start(_ station: Station) {
        begin(station, excluding: nil)
    }

    /// Music's Autoplay, from the player when an album or a playlist ends:
    /// a station from its last track that does not play that track again.
    func autoplay(after track: Track) {
        begin(station(for: .track(track.id)), excluding: track.id)
    }

    private func begin(_ station: Station, excluding excluded: ItemID?) {
        generation += 1
        let generation = self.generation
        cancelSources()
        let previous = (station: self.station, session: self.session)
        self.station = station
        session = nil
        isStarting = true

        // Everything the first picks need, as values, so they are chosen
        // off the main actor while the screen stays responsive.
        let snapshot = library.snapshot
        // The library's index is built after its tracks arrive; a station
        // started in that moment builds its own rather than find nothing.
        let fallback = snapshot.isEmpty ? library.tracks : []
        let events = history.history
        let graph = self.graph
        let radioSettings = RadioSettings(adventurousness: settings.adventurousness)
        let now = Date()

        Task { [weak self] in
            let (session, picks, index) = await Task.detached(priority: .userInitiated) {
                () async -> (RadioSession, [RadioPick], LibrarySnapshot) in
                let index = snapshot.isEmpty && !fallback.isEmpty ? LibrarySnapshot(tracks: fallback) : snapshot
                let taste = TasteProfile(snapshot: index, history: events, now: now)
                // Heard anywhere in the last hours: it waits (RadioSettings).
                let recent = events.trackIDs(since: now.addingTimeInterval(-radioSettings.noRepeatHours * 3600))
                var session = RadioSession(station: station, snapshot: index, taste: taste, graph: graph,
                                           settings: radioSettings, recentlyPlayed: recent)
                var picks = session.next(4)
                if let excluded {
                    // Handed out and dropped, so the session never offers it again here.
                    picks.removeAll { $0.track.id == excluded }
                    if picks.count < 4 { picks += session.next(4 - picks.count) }
                }
                return (session, picks, index)
            }.value
            guard let self, self.generation == generation else { return }
            self.isStarting = false
            guard !picks.isEmpty else {
                // Nothing fits (an empty or still-loading library): whatever
                // played goes on as it was.
                self.station = previous.station
                self.session = previous.session
                if self.library.tracks.isEmpty {
                    if case .loading = self.library.state {
                        self.player.showError("Your library is still loading.")
                    } else {
                        self.player.showError("There is no music in your library yet.")
                    }
                } else {
                    self.player.showError("Could not find anything to play on \(station.title).")
                }
                return
            }
            self.session = session
            // The track that was playing ends here; it belongs to whatever
            // played before, not to this station.
            self.isHandlingFeedback = true
            self.player.playRadio(picks, station: station)
            self.isHandlingFeedback = false
            self.gatherSources(for: station, in: index, generation: generation)
        }
    }

    func stop() {
        generation += 1
        cancelSources()
        dialTask?.cancel()
        dialTask = nil
        station = nil
        session = nil
        isStarting = false
    }

    /// The player is this many tracks from the end of a station's queue.
    func playerNeedsMore() {
        guard !isStarting, session != nil else { return }
        let picks = session?.next(3) ?? []
        if !picks.isEmpty { player.appendRadio(picks) }
    }

    /// From the player, for every track of a station that ended: heard to
    /// the end, or left after `listened` seconds.
    func trackEnded(_ track: Track, listened: TimeInterval) {
        guard session != nil else { return }
        switch PlayOutcome.of(listened: listened, duration: track.duration) {
        case .completed:
            session?.record(.finished(track.id))
        case .skipped:
            session?.record(.skipped(track.id, after: listened))
            // A skip says "not this": what comes next is chosen again with
            // that known, at once.
            if !isHandlingFeedback { rechooseUpcoming(keepingNext: false) }
        case .partial:
            // Left halfway: the session weighs it by how long was heard; not
            // enough to throw away what is queued.
            session?.record(.skipped(track.id, after: listened))
        case .liked, .disliked:
            break
        }
    }

    /// Thumbs up. A second time takes the thumb back, as Music's Love does;
    /// what the session learnt from the first stays.
    func like(_ track: Track) {
        if liked.contains(track.id) {
            liked.remove(track.id)
            player.refreshRemoteFeedback()
            return
        }
        liked.insert(track.id)
        disliked.remove(track.id)
        session?.record(.liked(track.id))
        // Kept in the history too, so the taste remembers it tomorrow.
        history.record(PlayEvent(track: track, date: Date(), listened: 0, outcome: .liked, stationID: station?.id))
        player.refreshRemoteFeedback()
        rechooseUpcoming(keepingNext: false)
    }

    /// Thumbs down: skip it if it plays, and less like it from here.
    func dislike(_ track: Track) {
        let isCurrent = player.currentTrack?.id == track.id
        if disliked.contains(track.id), !isCurrent {
            disliked.remove(track.id)
            player.refreshRemoteFeedback()
            return
        }
        disliked.insert(track.id)
        liked.remove(track.id)
        session?.record(.disliked(track.id))
        history.record(PlayEvent(track: track, date: Date(), listened: 0, outcome: .disliked, stationID: station?.id))
        if isCurrent {
            isHandlingFeedback = true
            player.next()
            isHandlingFeedback = false
        }
        player.refreshRemoteFeedback()
        rechooseUpcoming(keepingNext: false)
    }

    /// The dial moved: the tracks ahead are chosen again.
    func adventurousnessChanged() {
        session?.settings.adventurousness = settings.adventurousness
        // A slider sends every step of a drag: choose again once it rests.
        dialTask?.cancel()
        dialTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.rechooseUpcoming(keepingNext: false)
        }
    }

    /// Settings changed the Last.fm key.
    func lastFMKeyChanged() {
        enrichTask?.cancel()
        enrichTask = nil
        service = makeService()
        rebuildGraph()
    }

    /// The station seed for a track, artist, album …, named and with
    /// artwork, for "Start Radio" buttons.
    func station(for seed: StationSeed) -> Station {
        Station(seed: seed, snapshot: library.snapshot)
    }

    // MARK: Feeding the station

    /// The sources beyond the library, each applied as it arrives, without
    /// holding up the first track.
    private func gatherSources(for station: Station, in index: LibrarySnapshot, generation: Int) {
        if let client, let seedID = instantMixSeed(for: station.seed) {
            sourceTasks.append(Task { [weak self] in
                let tracks = (try? await client.instantMix(seedID: seedID, limit: 100)) ?? []
                guard let self, self.generation == generation, !tracks.isEmpty else { return }
                self.addCandidates(tracks.map(\.id), weight: 0.5, reason: .instantMix)
            })
        }
        guard settings.hasLastFM, let service else { return }
        switch station.seed {
        case let .track(id):
            guard let track = index.track(id: id) else { return }
            sourceTasks.append(Task { [weak self] in
                let neighbors = await service.similarTracks(to: track, in: index)
                guard let self, self.generation == generation, !neighbors.isEmpty else { return }
                self.addCandidates(neighbors.map(\.key), weight: 0.8, reason: .similarTrack(track.name))
            })
        case let .artist(key, name, _):
            // An artist's station leans on the songs people know them by.
            guard let artist = index.artist(key: key) else { return }
            sourceTasks.append(Task { [weak self] in
                let top = await service.topTracks(artist: artist, in: index, limit: 10)
                guard let self, self.generation == generation, !top.isEmpty else { return }
                self.addCandidates(top.map(\.id), weight: 0.6, reason: .byArtist(name))
            })
        default:
            break
        }
    }

    private func addCandidates(_ ids: [ItemID], weight: Double, reason: PickReason) {
        guard session != nil else { return }
        session?.addCandidates(ids, weight: weight, reason: reason)
        // The track playing and the one loaded after it stay; the rest
        // benefit from what just arrived.
        rechooseUpcoming(keepingNext: true)
    }

    /// The radio's tracks after the current one go back to the session and
    /// are chosen again with what it knows now.
    private func rechooseUpcoming(keepingNext: Bool) {
        guard session != nil, let station, player.context?.station?.id == station.id else { return }
        let removed = player.removeUpcomingRadioPicks(keepingNext: keepingNext)
        session?.returnUnplayed(removed)
        let picks = session?.next(max(3, removed.count)) ?? []
        player.appendRadio(picks)
    }

    /// The item Jellyfin's Instant Mix starts from, when the seed has one.
    private func instantMixSeed(for seed: StationSeed) -> ItemID? {
        switch seed {
        case let .track(id):
            return id
        case let .artist(_, _, id):
            return id
        case let .album(id):
            return id
        case let .genre(_, name):
            return library.genre(named: name)?.id
        case let .collection(id, _, trackIDs):
            // A playlist is a Jellyfin item; a made-up mix is not, so it
            // starts from its first track.
            return Self.isJellyfinID(id) ? id : trackIDs.first
        case .decade, .personal, .discovery, .favorites:
            return nil
        }
    }

    /// Jellyfin's ids are GUIDs, 32 hex digits, with or without dashes.
    private static func isJellyfinID(_ id: String) -> Bool {
        let digits = id.filter { $0 != "-" }
        return digits.count == 32 && digits.allSatisfy(\.isHexDigit)
    }

    private func cancelSources() {
        for task in sourceTasks { task.cancel() }
        sourceTasks = []
    }

    // MARK: The graph

    private func makeService() -> SimilarityService {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = caches
            .appendingPathComponent("Jukebox", isDirectory: true)
            .appendingPathComponent("similarity", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = settings.lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return SimilarityService(directory: directory, lastFM: settings.hasLastFM ? LastFMClient(apiKey: key) : nil)
    }

    /// The library's own edges at once (with what Last.fm said before, from
    /// disk), then Last.fm's for the artists the listener likes most.
    private func rebuildGraph() {
        guard let service else { return }
        let snapshot = library.snapshot
        graphTask?.cancel()
        graphTask = Task { [weak self] in
            let graph = await service.graph(for: snapshot)
            guard !Task.isCancelled, let self, self.service === service else { return }
            self.graph = graph
            self.enrich(snapshot, with: service)
        }
    }

    /// One enrichment at a time: a newer one waits for the one before, so
    /// Last.fm is never asked twice over at once.
    private func enrich(_ snapshot: LibrarySnapshot, with service: SimilarityService) {
        guard settings.hasLastFM, !snapshot.isEmpty else { return }
        let events = history.history
        let previous = enrichTask
        previous?.cancel()
        enrichTask = Task { [weak self] in
            _ = await previous?.value
            guard !Task.isCancelled else { return }
            let priority = await Task.detached(priority: .utility) {
                TasteProfile(snapshot: snapshot, history: events, now: Date()).topArtists(150)
            }.value
            let graph = await service.enrich(snapshot: snapshot, priority: priority)
            guard !Task.isCancelled, let self, self.service === service else { return }
            self.graph = graph
        }
    }

    /// The library sets its snapshot when its tracks change (the cache at
    /// launch, then the server): the graph follows.
    private func watchLibrary() {
        guard !isWatchingLibrary else { return }
        isWatchingLibrary = true
        observeSnapshot()
    }

    private func observeSnapshot() {
        withObservationTracking {
            _ = library.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in self?.snapshotChanged() }
        }
    }

    private func snapshotChanged() {
        observeSnapshot()
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            // It can be set twice in a moment; build once.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.rebuildGraph()
        }
    }
}
