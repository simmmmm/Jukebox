// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// The radio in the app: one RadioSession (JukeboxKit) for the station that
// plays, fed into the player fifteen tracks ahead. A station starts within a
// moment from the library alone; the server's mix (Jellyfin's Instant Mix, a
// Subsonic server's similar songs), an artist's top songs where the server
// has them (Subsonic's getTopSongs) and, with a key, Last.fm's similar
// tracks join it as they arrive. Feedback — a skip, a
// thumbs up or down, a track heard to the end — goes to the session, and
// after a skip or a thumbs the tracks ahead are chosen again.
//
// The photographer's favourite part ("ik vind vooral de radiofunctie echt
// belangrijk", 8 November 2026), so it is built to feel instant: the first
// four tracks come from the library in memory, chosen off the main actor,
// and the first one plays before the network has been asked anything. What
// the server and Last.fm add changes only the tracks not yet loaded.
//
// A station's page (StationDetailView) shows what the station would play
// before it plays: "Als je nu klikt op een tegel van radio begint er meteen
// van alles te spelen ipv dat je kan zien wat je van de playlist gemaakt
// hebt" (the photographer, 8 November 2026). `preview` chooses those songs
// as `begin` chooses a station's first, and keeps the session that chose
// them; `start(_:preview:from:)` plays that very session, so Play plays the
// list the page shows, song for song.
//
// Offline — no network, or a server that does not answer (OfflineStore) —
// the radio chooses from the songs on the phone alone, as only those can
// play: the photographer, of the offline proposal ("offline speelt de app
// alleen wat op de telefoon staat, ook de radio"), "Alle drie". A station
// on the air when the network goes is chosen again from them at once, and
// from the whole library when it comes back; the server's mix and Last.fm
// are not asked while offline.

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
    private(set) var graph = SimilarityGraph() {
        didSet { previewInputs += 1 }
    }
    /// Liked and disliked in this session, for the thumbs' state.
    private(set) var liked: Set<ItemID> = []
    private(set) var disliked: Set<ItemID> = []
    /// Stations started, newest first, each once, at most 20; kept in
    /// UserDefaults by account ("recentStations.<account>", JSON,
    /// AccountFiles), so they are there after a relaunch and a switch back.
    private(set) var recentStations: [Station] = []
    /// Moves whenever what a station's preview is chosen from changes (the
    /// library's snapshot, the graph): a station's page then chooses its
    /// list again, rather than show one that Play would no longer play.
    private(set) var previewInputs = 0
    /// What the listener plays at this hour, for Your Station's card (and
    /// CarPlay's first row, and Linux's): "Weekday mornings: Jazz and Folk".
    /// Nil until the history shows a pattern for now (TasteProfile.timeFact):
    /// the card then says what it said before. `refreshYourStationFact`
    /// works it out again.
    private(set) var yourStationFact: TimeFact?
    /// Why Last.fm says nothing now (`SimilarityService.trouble`), for the
    /// quiet line by Enhance Radio with Last.fm in Settings › Radio
    /// (Preferences › Radio on Linux) and on a station's page; nil while it
    /// answers, and when it is off. Before, a refused key or a Last.fm out
    /// of reach left the radio on the library alone without a word ("doe ze
    /// allemaal", the photographer, 23 November 2026).
    private(set) var lastFMTrouble: LastFMTrouble?

    var server: (any MusicServer)?
    /// Set by AppModel: offline, what the radio may choose from.
    @ObservationIgnored weak var offline: OfflineStore?

    private let player: AudioPlayer
    private let library: LibraryStore
    private let history: HistoryStore
    private let settings: AppSettings

    @ObservationIgnored private var session: RadioSession?
    @ObservationIgnored private var service: SimilarityService?
    /// The account's: where its recent stations are kept, and what Last.fm
    /// said of its library (its answers name the library's songs by id).
    @ObservationIgnored private var recentStationsKey: String?
    @ObservationIgnored private var similarityDirectory: URL?
    /// Bumped by every start and stop: work for an older station, still
    /// arriving, is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sourceTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var graphTask: Task<Void, Never>?
    @ObservationIgnored private var enrichTask: Task<Void, Never>?
    /// Asks Last.fm again once it has rested (`SimilarityService.retryAt`).
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    @ObservationIgnored private var dialTask: Task<Void, Never>?
    @ObservationIgnored private var factTask: Task<Void, Never>?
    @ObservationIgnored private var isWatchingLibrary = false
    /// Set while the radio itself moves the player on (a thumbs down skips
    /// the track): that skip is the listener's thumbs, already acted on.
    @ObservationIgnored private var isHandlingFeedback = false
    /// The station was started from its page and still plays the songs the
    /// page showed: what the server's mix and Last.fm add then shapes the songs
    /// after those, not those. The listener's own skip, thumbs or dial
    /// chooses them again, as the page's footer says it will.
    @ObservationIgnored private var keepsShownPicks = false
    /// The stations' pages' previews, by station and draw ("<id> <seed>"),
    /// each with the session that chose it. A few, not one: each tab keeps
    /// its own stack, and a page under another tab's must still play what
    /// it shows, also when it is the same station's (Your Station's page on
    /// Home and on Radio): by station alone, the page chosen last took the
    /// other's place, and Play there started the station afresh.
    @ObservationIgnored private var previews: [String: KeptPreview] = [:]
    /// The newest preview asked for, by the same key: an older one that
    /// arrives after it is not kept, as it is not what the page shows.
    @ObservationIgnored private var latestPreview: [String: Int] = [:]
    @ObservationIgnored private var previewCount = 0
    /// The draw New Picks made for a station, by station id, while the app
    /// runs (`pageSeed(for:)`).
    @ObservationIgnored private var pageSeeds: [String: UInt64] = [:]
    /// The library's songs that are on the phone, as a snapshot, with what
    /// it was made from: made again only when one of those moved.
    @ObservationIgnored private var onPhone: OnPhoneSnapshot?
    /// The library as the radio reads it, with Last.fm's tags as genres
    /// (SimilarityService.radioSnapshot), and the snapshot it was made from:
    /// "Tags are the radio's weakest link" (build/research/radio.md, 4.4;
    /// "doe alles", the photographer, 18 November 2026).
    @ObservationIgnored private var tagged: (source: LibrarySnapshot, radio: LibrarySnapshot)?
    /// The listener's Last.fm plays of library songs, for the clock, when
    /// Settings has their Last.fm name (SimilarityService.scrobbles).
    @ObservationIgnored private var scrobbles = ListeningHistory()

    /// What the radio chooses from online: the library with its tags, once
    /// they are made for the library as it is now; else the library itself.
    private var radioSnapshot: LibrarySnapshot {
        let snapshot = library.snapshot
        if let tagged, tagged.source.isSameSnapshot(as: snapshot) { return tagged.radio }
        return snapshot
    }

    private struct OnPhoneSnapshot {
        let revision: Int
        let count: Int
        let loaded: Date?
        let snapshot: LibrarySnapshot
    }

    init(player: AudioPlayer, library: LibraryStore, history: HistoryStore, settings: AppSettings) {
        self.player = player
        self.library = library
        self.history = history
        self.settings = settings
    }

    /// Signed in, or switched to: the account's recent stations, and its
    /// own Last.fm answers for the graph `prepare` makes.
    func open(_ account: ServerCredentials) {
        close()
        recentStationsKey = AccountFiles.recentStationsKey(account)
        similarityDirectory = AccountFiles.similarity(account)
        recentStations = Self.loadRecentStations(recentStationsKey)
    }

    /// After sign-in: the graph from the library, then Last.fm in the
    /// background when there is a key.
    func prepare() {
        if service == nil { service = makeService() }
        rebuildGraph()
        watchLibrary()
        refreshYourStationFact()
    }

    /// Your Station's fact for now, from the library and this device's
    /// history, off the main actor (a TasteProfile: some 30 ms on 20 000
    /// tracks). At sign-in and when the library changes; a screen showing
    /// the card calls it as it appears, as the hour moves on.
    func refreshYourStationFact() {
        let snapshot = radioSnapshot
        let events = history.history
        let scrobbles = self.scrobbles
        factTask?.cancel()
        factTask = Task { [weak self] in
            let fact = await Task.detached(priority: .utility) {
                TasteProfile(snapshot: snapshot, history: events, scrobbles: scrobbles, now: Date()).timeFact
            }.value
            guard !Task.isCancelled, let self else { return }
            if self.yourStationFact != fact { self.yourStationFact = fact }
        }
    }

    func start(_ seed: StationSeed) {
        start(station(for: seed))
    }

    func start(_ station: Station) {
        // "Start Radio" on the song that plays (Now Playing's "…", the mini
        // player, a track's menu, Search): the song goes on where it is, as
        // the station's first, rather than start again from 0:00 with the
        // part already heard written down as a skip of it.
        if case let .track(id) = station.seed, player.currentTrack?.id == id {
            begin(station, excluding: id, continuing: true)
        } else {
            begin(station, excluding: nil, continuing: false)
        }
    }

    /// A station that was on the air on another device, taken over with
    /// its queue (HandoffStore): the song that plays goes on where it is,
    /// and the station chooses what comes after it, as it would have there.
    func continueStation(_ station: Station) {
        begin(station, excluding: player.currentTrack?.id, continuing: true)
    }

    /// Music's Autoplay, from the player when an album or a playlist ends:
    /// a station from its last track that does not play that track again.
    /// That track is still the player's current one, but it has ended: the
    /// station starts after it, never continues it.
    func autoplay(after track: Track) {
        Stats.track(.stationStarted, ["seed": "track", "from": "autoplay"])
        begin(station(for: .track(track.id)), excluding: track.id, continuing: false)
    }

    /// - Parameter continuing: the station is the song that plays, which
    ///   goes on (`excluded` is its id); else the station's first pick
    ///   replaces it.
    /// - Parameter shown: a station's page's songs from the one tapped on,
    ///   when its list is no longer the kept one: they play first, and the
    ///   station chooses what comes after them.
    private func begin(_ station: Station, excluding excluded: ItemID?, continuing: Bool, shown: [RadioPick] = []) {
        generation += 1
        let generation = self.generation
        cancelSources()
        let previous = (station: self.station, session: self.session)
        self.station = station
        session = nil
        isStarting = true
        keepsShownPicks = !shown.isEmpty

        // The song playing reaches the history only when it ends: until
        // then an artist or album station could open with it, the song
        // that was just interrupted for the station.
        let inputs = startInputs(playingNow: continuing ? nil : player.currentTrack?.id, shown: shown.map(\.id))
        let randomSeed = UInt64.random(in: 0...UInt64.max)

        Task { [weak self] in
            let (session, picks, index) = await Task.detached(priority: .userInitiated) {
                () async -> (RadioSession, [RadioPick], LibrarySnapshot) in
                let made = inputs.session(for: station, randomSeed: randomSeed)
                var session = made.session
                var picks = session.next(4)
                if let excluded {
                    // Handed out and dropped, so the session never offers it again here.
                    picks.removeAll { $0.track.id == excluded }
                    if picks.count < 4 { picks += session.next(4 - picks.count) }
                }
                return (session, picks, made.index)
            }.value
            guard let self, self.generation == generation else { return }
            self.isStarting = false
            guard !picks.isEmpty || !shown.isEmpty else {
                // Nothing fits (an empty or still-loading library): whatever
                // played goes on as it was.
                self.station = previous.station
                self.session = previous.session
                if self.offline?.isOffline == true {
                    self.player.showError(OfflineText.nothingForStation(station.title))
                } else if self.library.tracks.isEmpty {
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
            self.remember(station)
            self.isHandlingFeedback = true
            if continuing, self.player.currentTrack?.id == excluded {
                // The song goes on where it is; the picks come after it.
                self.player.continueAsRadio(shown.dropFirst() + picks, station: station)
            } else {
                // The track that was playing ends here; it belongs to
                // whatever played before, not to this station. So too the
                // song "Start Radio" was asked on, if it ended or was
                // skipped while the first picks were chosen.
                self.player.playRadio(shown + picks, station: station)
            }
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
        keepsShownPicks = false
    }

    /// At sign-out (AppModel): nothing of this account's radio stays — the
    /// station, the thumbs, the stations started, Last.fm's answers. The
    /// next account may be on another server, where those tracks and
    /// stations mean nothing.
    func reset() {
        if let recentStationsKey { UserDefaults.standard.removeObject(forKey: recentStationsKey) }
        if let similarityDirectory { try? FileManager.default.removeItem(at: similarityDirectory) }
        close()
    }

    /// Another account switched to (AppModel): this one's radio is put
    /// away, its recent stations kept for when it is back.
    func close() {
        stop()
        graphTask?.cancel()
        enrichTask?.cancel()
        graphTask = nil
        enrichTask = nil
        retryTask?.cancel()
        retryTask = nil
        lastFMTrouble = nil
        factTask?.cancel()
        factTask = nil
        yourStationFact = nil
        service = nil
        graph = SimilarityGraph()
        onPhone = nil
        tagged = nil
        scrobbles = ListeningHistory()
        liked = []
        disliked = []
        recentStations = []
        previews = [:]
        latestPreview = [:]
        pageSeeds = [:]
        recentStationsKey = nil
        similarityDirectory = nil
        player.refreshRemoteFeedback()
    }

    /// How many songs a station keeps ahead: enough to see what is coming
    /// and take one out before it plays ("ik wil dat de radio queue langer
    /// wordt", the photographer, 20 November 2026), a screen of the queue
    /// and a little more. Not more: each skip, thumb or turn of the dial
    /// chooses them all again (`rechooseUpcoming`), and what is queued
    /// counts as heard for the rules (an artist's three songs apart).
    static let ahead = 15
    /// Below this many ahead, the queue asks for more (PlayQueue), and gets
    /// as many as make `ahead` again: five at a time rather than one.
    static let refillBelow = 11

    /// The player is this many tracks from the end of a station's queue.
    func playerNeedsMore() {
        guard !isStarting, session != nil else { return }
        let picks = session?.next(max(3, Self.ahead - player.upNext.count)) ?? []
        if !picks.isEmpty { player.appendRadio(picks) }
    }

    /// The listener took songs the radio chose out of Up Next before they
    /// played (PlayQueue.removeUpcoming: the swipe, the menu). The session
    /// learns it as a strong skip of each (RadioFeedback.removed), so more
    /// like them stays out; songs already queued that this now rules out go
    /// too, and the rest stay where they are, as the listener is looking at
    /// them. The queue is topped up at its end.
    func removedFromUpcoming(_ ids: [ItemID]) {
        guard session != nil, let station, player.context?.station?.id == station.id else { return }
        Stats.track(.radioFeedback, ["kind": "remove"])
        for id in ids { session?.record(.removed(id)) }
        // Handed out and not heard: the rules count them no longer.
        session?.returnUnplayed(ids)
        let queued = player.upNext.filter { $0.reason != nil }.map(\.track.id)
        let out = session?.ruledOut(queued) ?? []
        let removed = player.removeUpcomingRadioPicks(Set(out))
        session?.returnUnplayed(removed)
        let picks = session?.next(max(0, Self.ahead - player.upNext.count)) ?? []
        if !picks.isEmpty { player.appendRadio(picks) }
    }

    /// The listener's "Not This Artist" on a song of a station's Up Next:
    /// that artist leaves this station (RadioFeedback.removedArtist), the
    /// song and the others of theirs queued go, and the queue is topped up.
    /// Only this station's: on another, or tomorrow, they are welcome.
    func removeArtistFromStation(of track: Track) {
        guard session != nil, let station, player.context?.station?.id == station.id else { return }
        Stats.track(.radioFeedback, ["kind": "removeArtist"])
        session?.record(.removedArtist(track.id))
        let queued = player.upNext.filter { $0.reason != nil }.map(\.track.id)
        let out = Set(session?.ruledOut(queued) ?? []).union([track.id])
        let removed = player.removeUpcomingRadioPicks(out)
        session?.returnUnplayed(removed)
        let picks = session?.next(max(0, Self.ahead - player.upNext.count)) ?? []
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
            if isHandlingFeedback {
                session?.record(.skipped(track.id, after: listened))
            } else {
                // A skip says "not this": what comes next is chosen again
                // with that known, at once. Told once what was queued is
                // back, so the skip is marked where the station then stands
                // (with fifteen ahead, told first it kept 0.98^14 of what
                // came before: RadioQueueTests).
                rechooseUpcoming(keepingNext: false) { $0.record(.skipped(track.id, after: listened)) }
                // The listener's skip, not the one a thumbs down made (counted as that).
                Stats.track(.radioFeedback, ["kind": "skip"])
            }
        case .partial:
            // Left halfway: the session weighs it by how long was heard; not
            // enough to throw away what is queued.
            session?.record(.skipped(track.id, after: listened))
        case .liked, .disliked:
            break
        }
    }

    /// Thumbs up. A second time takes the thumb back, as Music's Love does,
    /// and out of the history, so tomorrow's taste does not count it; what
    /// this station's session learnt from the first stays. Only while the
    /// like is the track's newest event (ListeningHistory.removeLatest): a
    /// like taken back after the song ended stays in the history.
    func like(_ track: Track) {
        Stats.track(.radioFeedback, ["kind": liked.contains(track.id) ? "undo" : "like"])
        if liked.contains(track.id) {
            liked.remove(track.id)
            history.removeLatest(.liked, of: track.id)
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

    /// Thumbs down: skip it if it plays, and less like it from here. A
    /// second time takes it back, out of the history too: a thumbs down left
    /// there keeps the song off every station for half a year
    /// (TasteData.thumbsDownDays), whatever the button shows. That second
    /// tap is on the song playing: Now Playing's thumbs (and the lock
    /// screen's) are the current song's, and a disliked song is current
    /// again when the listener went back to it (Previous, Up Next) or
    /// nothing came after it to skip to. So it takes the thumb back there
    /// too, rather than skip the song again.
    func dislike(_ track: Track) {
        let isCurrent = player.currentTrack?.id == track.id
        Stats.track(.radioFeedback, ["kind": disliked.contains(track.id) ? "undo" : "dislike"])
        if disliked.contains(track.id) {
            disliked.remove(track.id)
            history.removeLatest(.disliked, of: track.id)
            player.refreshRemoteFeedback()
            return
        }
        disliked.insert(track.id)
        liked.remove(track.id)
        session?.record(.disliked(track.id))
        // The station as it was before the skip, which can move the player
        // on to something else.
        let stationID = station?.id
        if isCurrent {
            isHandlingFeedback = true
            player.next()
            isHandlingFeedback = false
        }
        // Written after the skip, whose own event (the seconds heard) the
        // player writes as the song stops: so the thumb is the song's newest
        // event, and taking it back finds it.
        history.record(PlayEvent(track: track, date: Date(), listened: 0, outcome: .disliked, stationID: stationID))
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

    /// Settings changed the Last.fm key, the listener's Last.fm name, or
    /// Enhance Radio with Last.fm. Without a key, or switched off, the
    /// files' genres and this device's history alone. Off, a station's
    /// questions still waiting for their turn are dropped too, so no call
    /// leaves after the switch (each waits for its slot, then checks).
    func lastFMKeyChanged() {
        if !settings.hasLastFM { cancelSources() }
        enrichTask?.cancel()
        enrichTask = nil
        retryTask?.cancel()
        retryTask = nil
        lastFMTrouble = nil
        tagged = nil
        scrobbles = ListeningHistory()
        previewInputs += 1
        service = makeService()
        rebuildGraph()
        refreshYourStationFact()
    }

    /// The station seed for a track, artist, album …, named and with
    /// artwork, for "Start Radio" buttons.
    func station(for seed: StationSeed) -> Station {
        Station(seed: seed, snapshot: library.snapshot)
    }

    // MARK: A station's page

    /// The songs `station` would start with, for its page: chosen off the
    /// main actor exactly as `begin` chooses a station's first (the same
    /// library, taste, graph, dial, and what was heard lately, the song
    /// playing now too), only more of them. The session that chose them is
    /// kept, so `start(_:preview:from:)` plays these and no others. The
    /// same `randomSeed` with the same library gives the same songs: a page
    /// chooses with its station's draw (`pageSeed(for:)`), so a list chosen
    /// again because the library or the graph moved, or the page opened
    /// again, stays much as it was; New Picks is a new seed, another list as
    /// near the station.
    func preview(_ station: Station, count: Int = 25,
                 randomSeed: UInt64 = UInt64.random(in: 0...UInt64.max)) async -> [RadioPick] {
        previewCount += 1
        let request = previewCount
        let slot = "\(station.id) \(randomSeed)"
        latestPreview[slot] = request
        let inputs = startInputs(playingNow: player.currentTrack?.id)
        let stamp = previewInputs
        let (session, picks, index) = await Task.detached(priority: .userInitiated) {
            () async -> (RadioSession, [RadioPick], LibrarySnapshot) in
            let made = inputs.session(for: station, randomSeed: randomSeed)
            var session = made.session
            let picks = session.next(count)
            return (session, picks, made.index)
        }.value
        // A newer one was asked for while this was chosen: that one is what
        // the page will show.
        guard latestPreview[slot] == request else { return picks }
        previews[slot] = KeptPreview(station: station.id, request: request, picks: picks.map(\.id),
                                     session: session, index: index, inputs: stamp,
                                     adventurousness: inputs.settings.adventurousness)
        // A session holds some ten numbers for every track (reckoned, not
        // measured: under 2 MB for 20 000): the newest four pages' are
        // enough, one per tab.
        while previews.count > Self.keptPreviewLimit,
              let oldest = previews.min(by: { $0.value.request < $1.value.request })?.key {
            previews[oldest] = nil
        }
        return picks
    }

    /// Whether Play on a page showing `picks` would play them: they are the
    /// kept preview, and nothing it was chosen from has moved since.
    func isPreviewCurrent(_ station: Station, _ picks: [RadioPick]) -> Bool {
        keptPreview(of: station, matching: picks) != nil
    }

    /// The station from its page: `picks` from `index` on, as the page
    /// showed them, when they are its kept preview and it is not stale (the
    /// library, the graph and the dial as they were). Else they play all
    /// the same, with a session made now to choose what comes after them:
    /// "als ik nu dubbelklik op identikit om het af te spelen speelt er
    /// elke keer een heel ander nummer af" (the photographer, 16 November
    /// 2026) — a list that had started its station once was no longer the
    /// kept one, and every click on it after that started the station anew
    /// with other songs.
    func start(_ station: Station, preview picks: [RadioPick], from index: Int = 0) {
        guard picks.indices.contains(index) else {
            start(station)
            return
        }
        let tapped = picks[index]
        let current = player.currentTrack?.id
        // The song is this station's, and playing: a second click on it.
        if tapped.id == current, !isStarting, stationOnAir(player: player)?.id == station.id {
            player.resume()
            return
        }
        // The song playing was left out when these were chosen. Another
        // playing now, further down the list, would come round twice.
        let comesRoundTwice = current.map { id in picks[(index + 1)...].contains { $0.id == id } } ?? false
        guard !comesRoundTwice, let found = keptPreview(of: station, matching: picks) else {
            let shown = picks[index...].filter { $0.id != current || $0.id == tapped.id }
            begin(station, excluding: tapped.id, continuing: tapped.id == current, shown: shown)
            return
        }
        let kept = found.kept
        previews[found.slot] = nil
        generation += 1
        let generation = self.generation
        cancelSources()
        // A dial moved a moment ago would choose these again as they start.
        dialTask?.cancel()
        dialTask = nil

        var session = kept.session
        // The songs above the one tapped were handed out, not heard: back,
        // so the station can still play them later.
        if index > 0 { session.returnUnplayed(picks[..<index].map(\.id)) }
        self.station = station
        self.session = session
        isStarting = false
        keepsShownPicks = true
        remember(station)
        isHandlingFeedback = true
        if tapped.id == current {
            // A song station's own song, playing already: it goes on where
            // it is, as "Start Radio" on it does.
            player.continueAsRadio(Array(picks[(index + 1)...]), station: station)
        } else {
            player.playRadio(Array(picks[index...]), station: station)
        }
        isHandlingFeedback = false
        gatherSources(for: station, in: kept.index, generation: generation)
    }

    /// A station's draw for its page: the same each time its page opens
    /// while the app runs, so the list the listener looked at is the one
    /// they come back to (measured on the kit's made-up library of 60
    /// artists: chosen again after another song has played, on average 19
    /// to 24 of the 25 stay in their place, by station), until New Picks
    /// draws another (`drawPageSeed(for:)`). Before that, the id's hash,
    /// which Swift seeds anew at every launch: the same until the app is
    /// closed, another after, and nothing to store.
    func pageSeed(for station: Station) -> UInt64 {
        pageSeeds[station.id] ?? UInt64(bitPattern: Int64(station.id.hashValue))
    }

    /// New Picks: another draw, the station's own from now on.
    func drawPageSeed(for station: Station) -> UInt64 {
        let seed = UInt64.random(in: 0...UInt64.max)
        pageSeeds[station.id] = seed
        return seed
    }

    private static let keptPreviewLimit = 4

    /// What a station's page showed, with the session that chose it.
    private struct KeptPreview {
        /// The station's id.
        let station: String
        let request: Int
        let picks: [ItemID]
        let session: RadioSession
        let index: LibrarySnapshot
        /// `previewInputs` and the dial when it was chosen: if either has
        /// moved, the station would now choose otherwise.
        let inputs: Int
        let adventurousness: Double
    }

    /// The kept preview that is `picks`, with its key, when nothing it was
    /// chosen from has moved since.
    private func keptPreview(of station: Station, matching picks: [RadioPick]) -> (slot: String, kept: KeptPreview)? {
        let ids = picks.map(\.id)
        let inputs = previewInputs
        let dial = settings.adventurousness
        guard let found = previews.first(where: {
            $0.value.station == station.id && $0.value.picks == ids
                && $0.value.inputs == inputs && $0.value.adventurousness == dial
        }) else { return nil }
        return (found.key, found.value)
    }

    /// What a station's first songs are chosen from, now: offline, the
    /// songs on the phone alone.
    private func startInputs(playingNow: ItemID?, shown: [ItemID] = []) -> RadioStartInputs {
        let phone = offline?.isOffline == true ? onPhoneSnapshot() : nil
        let snapshot = phone ?? radioSnapshot
        return RadioStartInputs(snapshot: snapshot,
                                // The library's index is built after its
                                // tracks arrive; a station started in that
                                // moment builds its own rather than find
                                // nothing. Not offline: none on the phone is none.
                                fallback: phone == nil && snapshot.isEmpty ? library.tracks : [],
                                history: history.history,
                                scrobbles: scrobbles,
                                graph: graph,
                                settings: RadioSettings(adventurousness: settings.adventurousness),
                                now: Date(),
                                playingNow: [playingNow].compactMap { $0 } + shown)
    }

    // MARK: Recent stations

    private static let recentStationLimit = 20

    /// A station that started goes first, once: started again, it moves up
    /// rather than show twice. Autoplay's stations too, since they played.
    private func remember(_ station: Station) {
        var stations = recentStations.filter { $0.id != station.id }
        stations.insert(station, at: 0)
        if stations.count > Self.recentStationLimit {
            stations.removeLast(stations.count - Self.recentStationLimit)
        }
        recentStations = stations
        if let recentStationsKey, let data = try? JSONEncoder().encode(stations) {
            UserDefaults.standard.set(data, forKey: recentStationsKey)
        }
    }

    /// What was kept; none when nothing was, or it no longer decodes (a
    /// Station of an older build).
    private static func loadRecentStations(_ key: String?) -> [Station] {
        guard let key, let data = UserDefaults.standard.data(forKey: key),
              let stations = try? JSONDecoder().decode([Station].self, from: data) else { return [] }
        return Array(stations.prefix(recentStationLimit))
    }

    // MARK: Feeding the station

    /// The sources beyond the library, each applied as it arrives, without
    /// holding up the first track.
    private func gatherSources(for station: Station, in index: LibrarySnapshot, generation: Int) {
        // Offline neither answers, and the station chooses from the phone.
        if offline?.isOffline == true { return }
        // Not asked of a server without one (a Subsonic server before API
        // 1.11): the library's own picks carry the station, as they do when
        // a mix comes back empty (Navidrome without its agents, a genre
        // Jellyfin has no item for). Nor with a Last.fm key: then Last.fm's
        // similar artists and songs lead, and on his library the server's
        // mix moved a station by nothing at Familiar and under 0.02 at any
        // dial (docs/RADIO.md, "The server's mix"). "er klopt toch nog steeds geen fuck van deze
        // radio zo? gorillaz?? cocteau twins?" (the photographer, 20
        // November 2026): all three were Jellyfin's mix, on a station
        // Last.fm knew.
        if !settings.hasLastFM, let server, server.capabilities.contains(.instantMix), let seed = mixSeed(for: station.seed) {
            sourceTasks.append(Task { [weak self] in
                let tracks = (try? await server.instantMix(from: seed, limit: 100)) ?? []
                guard let self, self.generation == generation, !tracks.isEmpty else { return }
                self.addCandidates(tracks.map(\.id), weight: 0.5, reason: .instantMix)
            })
        }
        let lastFM = settings.hasLastFM ? service : nil
        switch station.seed {
        case let .track(id):
            guard let lastFM, let track = index.track(id: id) else { return }
            sourceTasks.append(Task { [weak self] in
                let neighbors = await lastFM.similarTracks(to: track, in: index)
                await self?.noteTrouble(of: lastFM)
                guard let self, self.generation == generation, !neighbors.isEmpty else { return }
                self.addCandidates(neighbors.map(\.key), weight: 0.8, reason: .similarTrack(track.name))
            })
        case let .artist(key, name, _):
            // An artist's station leans on the songs people know them by:
            // the server's top songs where it has them (a Subsonic server's,
            // from Last.fm there), else, or when it had none (Navidrome
            // without its agents answers nothing), the app's own Last.fm.
            guard let artist = index.artist(key: key) else { return }
            let topServer = server?.capabilities.contains(.topSongs) == true ? server : nil
            guard topServer != nil || lastFM != nil else { return }
            sourceTasks.append(Task { [weak self] in
                var top: [Track] = []
                if let topServer { top = (try? await topServer.topSongs(of: artist, limit: 10)) ?? [] }
                if top.isEmpty, let lastFM {
                    top = await lastFM.topTracks(artist: artist, in: index, limit: 10)
                    await self?.noteTrouble(of: lastFM)
                }
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
        // Started from its page, the station plays the songs the page
        // showed: what arrives now chooses the songs after them.
        guard !keepsShownPicks else { return }
        // The track playing and the one loaded after it stay; the rest
        // benefit from what just arrived.
        rechooseUpcoming(keepingNext: true)
    }

    /// The radio's tracks after the current one go back to the session and
    /// are chosen again with what it knows now. All of them: a station
    /// started from its page has some twenty queued, and a skip says "not
    /// this" of what is ahead too. As many again, so the queue the listener
    /// saw keeps its length.
    /// `learning`: what to tell the session once the queued are back.
    private func rechooseUpcoming(keepingNext: Bool, learning: ((inout RadioSession) -> Void)? = nil) {
        // The listener's skip, thumbs or dial: the page's songs make way.
        if !keepingNext { keepsShownPicks = false }
        guard session != nil, let station, player.context?.station?.id == station.id else {
            if session != nil, let learning { learning(&session!) }
            return
        }
        let removed = player.removeUpcomingRadioPicks(keepingNext: keepingNext)
        session?.returnUnplayed(removed)
        if session != nil, let learning { learning(&session!) }
        let picks = session?.next(max(removed.count, Self.ahead - player.upNext.count)) ?? []
        player.appendRadio(picks)
    }

    /// What the server's mix starts from, when the seed has anything. The
    /// seed says what it is, so no id is guessed at (Jellyfin's GUIDs were,
    /// before Subsonic's ids, which are not).
    private func mixSeed(for seed: StationSeed) -> MixSeed? {
        switch seed {
        case let .track(id):
            return MixSeed.track(id)
        case let .artist(_, _, id):
            guard let id else { return nil }
            return MixSeed.artist(id)
        case let .album(id):
            return MixSeed.album(id)
        case let .genre(_, name):
            // A genre split out of a joined tag ("Shoegaze" of "Rock;
            // Shoegaze") has a made-up id ("genre:" and its key,
            // LibraryIndex.libraryGenres): no item on Jellyfin, so its mix
            // gives nothing and the library's own picks carry the station;
            // a Subsonic server mixes a genre by its name.
            var serverID: ItemID?
            if let id = library.genre(named: name)?.id, !id.hasPrefix(LibraryIndex.syntheticGenrePrefix) {
                serverID = id
            }
            return MixSeed.genre(name: name, id: serverID)
        case let .collection(id, _, trackIDs):
            // A playlist is the server's; a mix Home made up is not, so it
            // starts from its first track.
            if library.playlists.contains(where: { $0.id == id }) { return MixSeed.playlist(id) }
            guard let first = trackIDs.first else { return nil }
            return MixSeed.track(first)
        case .decade, .personal, .discovery, .favorites:
            return nil
        }
    }

    private func cancelSources() {
        for task in sourceTasks { task.cancel() }
        sourceTasks = []
    }

    // MARK: Offline

    /// The network went or came back (OfflineStore, through AppModel). The
    /// stations' pages choose again; a station on the air gets a session
    /// made from what can play now — offline the songs on the phone, back
    /// online the whole library — and its songs ahead are chosen from that.
    /// The song playing stays. What this station's session had learnt from
    /// skips and thumbs goes with the old session; the history keeps the
    /// thumbs, and what was heard lately still waits (noRepeatHours).
    func connectivityChanged() {
        previewInputs += 1
        guard !isStarting, let station, session != nil, player.context?.station?.id == station.id else { return }
        generation += 1
        let generation = self.generation
        cancelSources()
        keepsShownPicks = false
        let inputs = startInputs(playingNow: player.currentTrack?.id)
        let randomSeed = UInt64.random(in: 0...UInt64.max)
        Task { [weak self] in
            let (made, index) = await Task.detached(priority: .userInitiated) {
                () async -> (RadioSession, LibrarySnapshot) in
                let made = inputs.session(for: station, randomSeed: randomSeed)
                return (made.session, made.index)
            }.value
            guard let self, self.generation == generation, self.station?.id == station.id else { return }
            var session = made
            let removed = self.player.removeUpcomingRadioPicks()
            let picks = session.next(max(removed.count, Self.ahead - self.player.upNext.count))
            self.session = session
            self.player.appendRadio(picks)
            self.gatherSources(for: station, in: index, generation: generation)
        }
    }

    /// The songs on the phone changed: offline, the stations' pages choose
    /// again from what is there now.
    func offlineSongsChanged() {
        if offline?.isOffline == true { previewInputs += 1 }
    }

    /// The library's songs that are on the phone, as a snapshot for the
    /// radio: made here, on the main actor, only when what it is made from
    /// moved (not measured on a phone yet: one look-up a song of the
    /// library, then the index of those on the phone), else the one made
    /// before.
    private func onPhoneSnapshot() -> LibrarySnapshot {
        guard let offline else { return library.snapshot }
        let revision = offline.revision
        let count = library.tracks.count
        let loaded = library.lastLoaded
        if let made = onPhone, made.revision == revision, made.count == count, made.loaded == loaded {
            return made.snapshot
        }
        let snapshot = LibrarySnapshot(tracks: library.tracks.filter { offline.has($0.id) })
        onPhone = OnPhoneSnapshot(revision: revision, count: count, loaded: loaded, snapshot: snapshot)
        return snapshot
    }

    // MARK: The graph

    /// None while no account is open (`open`). The listener's key, else the
    /// app's (`AppSettings.lastFMKey`); a new service for each, so a key
    /// Last.fm refused (`keyRejected`) stays that key's alone.
    private func makeService() -> SimilarityService? {
        guard let directory = similarityDirectory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = settings.lastFMKey
        return SimilarityService(directory: directory, lastFM: settings.hasLastFM ? LastFMClient(apiKey: key) : nil,
                                 user: settings.lastFMUser)
    }

    /// The library's own edges at once (with what Last.fm said before, from
    /// disk, its tags too), then Last.fm's for the artists the listener
    /// likes most.
    private func rebuildGraph() {
        guard let service else { return }
        let snapshot = library.snapshot
        graphTask?.cancel()
        graphTask = Task { [weak self] in
            let radio = await service.radioSnapshot(for: snapshot)
            let graph = await service.graph(for: radio)
            guard !Task.isCancelled, let self, self.service === service else { return }
            self.tagged = (snapshot, radio)
            self.graph = graph
            self.enrich(snapshot, with: service)
        }
    }

    /// One enrichment at a time: a newer one waits for the one before, so
    /// Last.fm is never asked twice over at once. The listener's scrobbles
    /// first (a few requests, and the clock's cold start), then who sounds
    /// like whom, then the artists' tags.
    private func enrich(_ snapshot: LibrarySnapshot, with service: SimilarityService) {
        guard settings.hasLastFM, !snapshot.isEmpty else { return }
        let events = history.history
        let previous = enrichTask
        previous?.cancel()
        enrichTask = Task { [weak self] in
            _ = await previous?.value
            guard !Task.isCancelled else { return }
            let plays = await service.scrobbles(for: snapshot)
            guard !Task.isCancelled, let self, self.service === service else { return }
            if plays.events != self.scrobbles.events {
                self.scrobbles = plays
                self.previewInputs += 1
                self.refreshYourStationFact()
            }
            let priority = await Task.detached(priority: .utility) {
                TasteProfile(snapshot: snapshot, history: events, now: Date()).topArtists(150)
            }.value
            let before = await service.radioSnapshot(for: snapshot)
            let graph = await service.enrich(snapshot: before, priority: priority)
            guard !Task.isCancelled, self.service === service else { return }
            self.graph = graph
            let radio = await service.enrichTags(snapshot: snapshot, priority: priority)
            let radioGraph = await service.graph(for: radio)
            guard !Task.isCancelled, self.service === service else { return }
            await self.noteTrouble(of: service)
            guard self.library.snapshot.isSameSnapshot(as: snapshot) else { return }
            self.tagged = (snapshot, radio)
            self.graph = radioGraph
            self.refreshYourStationFact()
        }
    }

    /// What the round left Last.fm at: said in Settings and on a station's
    /// page, and, after "rate limit" or no answer, the next round once it
    /// has rested (a minute, then longer each time, at most an hour). A
    /// refused key is not asked again until the app is opened again or the
    /// key changes.
    private func noteTrouble(of service: SimilarityService) async {
        let trouble = await service.trouble
        let retryAt = await service.retryAt
        guard self.service === service else { return }
        if lastFMTrouble != trouble { lastFMTrouble = trouble }
        retryTask?.cancel()
        retryTask = nil
        guard let retryAt else { return }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, retryAt.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.service === service else { return }
            self.enrich(self.library.snapshot, with: service)
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
        previewInputs += 1
        snapshotTask?.cancel()
        snapshotTask = Task { [weak self] in
            // It can be set twice in a moment; build once.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.rebuildGraph()
            self?.refreshYourStationFact()
        }
    }
}

// Moved from Home/HomeParts.swift, so Linux lights the same station at the
// same moments as the iPhone (build/design-round/drawings/spec.md).
extension RadioController {
    /// The station on the air: one is starting, or the player is playing
    /// its queue. `station` alone can outlive the music (the player was
    /// stopped from the lock screen), so the player's context decides.
    func stationOnAir(player: AudioPlayer) -> Station? {
        guard let station else { return nil }
        if isStarting || player.context?.station?.id == station.id { return station }
        return nil
    }
}

/// Everything a station's first songs are chosen from, taken on the main
/// actor as values, so the choosing runs off it while the screen stays
/// responsive. `begin` and a page's preview both choose from one of these,
/// in the same way, so the page shows what the station plays.
nonisolated private struct RadioStartInputs: Sendable {
    let snapshot: LibrarySnapshot
    /// The library's tracks while its index is not built yet, else none.
    let fallback: [Track]
    let history: ListeningHistory
    /// The listener's Last.fm plays, for the clock; empty without a name.
    let scrobbles: ListeningHistory
    let graph: SimilarityGraph
    let settings: RadioSettings
    let now: Date
    /// The song playing, and a page's songs about to: they reach the
    /// history only when they end.
    let playingNow: [ItemID]

    func session(for station: Station, randomSeed: UInt64) -> (session: RadioSession, index: LibrarySnapshot) {
        let index = snapshot.isEmpty && !fallback.isEmpty ? LibrarySnapshot(tracks: fallback) : snapshot
        let taste = TasteProfile(snapshot: index, history: history, scrobbles: scrobbles, now: now)
        // Heard anywhere in the last hours: it waits (RadioSettings).
        var recent = history.trackIDs(since: now.addingTimeInterval(-settings.noRepeatHours * 3600))
        recent.formUnion(playingNow)
        let session = RadioSession(station: station, snapshot: index, taste: taste, graph: graph,
                                   settings: settings, recentlyPlayed: recent, randomSeed: randomSeed)
        return (session, index)
    }
}
