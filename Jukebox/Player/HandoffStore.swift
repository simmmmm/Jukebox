// From one device to another: what this device plays is kept on the
// listener's server (JukeboxKit's PlayState), and what another device kept
// there is offered here — "Playing on tijmen-pc", "Continue Here". The
// photographer, 13 November 2026: "ik wil ook dat de ios app en de linux app
// van elkaar kunnen zien wat ze afspelen net als bij spotify zodat ik verder
// kan waar ik gebleven was als ik wegga van mijn pc".
//
// One file for the iPhone and for Linux (Package.swift's `shared`): it only
// watches the player and asks the server, so nothing in it is a platform's.
//
// Saved: when the song changes, on pause and resume, and every half minute
// while music plays — so the server is at most half a minute behind, and
// exact after a pause. Read: every 15 s while the app runs (one small
// request), and before every save, which is how a device learns the music
// was taken over from it, and stops rather than save over that. A phone in a pocket with nothing playing asks nothing: the
// system has the app asleep.
//
// At launch, with Settings' "Continue Where You Left Off" on (the default),
// the first music to go on with is not a notice: it waits in the player,
// paused, at its song and place, and Play is Continue Here. The
// photographer, 14 November 2026, of "Where you left off · Continue": "ik
// denk dat het nummer gewoon onderin de player al klaar moet staan".

import Foundation
import JukeboxKit
import Observation

@Observable
final class HandoffStore {
    /// Music to go on with: another device's, or what this one played
    /// before it was closed. Nil when there is none, or its song is not in
    /// the library.
    private(set) var offer: Offer?

    struct Offer: Equatable {
        let state: PlayState
        /// The song it is at.
        let track: Track
        /// Kept by this device itself (its own last session).
        let isOwn: Bool

        /// "Playing on tijmen-pc", "Left off on tijmen-pc", "Where you left off".
        var heading: String {
            if isOwn { return String(localized: "Where you left off") }
            if state.isLive() { return String(localized: "Playing on \(state.deviceName)") }
            return String(localized: "Left off on \(state.deviceName)")
        }
    }

    var server: (any MusicServer)? {
        didSet {
            // The same account again (the server said more of itself since
            // sign-in, AppModel.use): nothing here starts over.
            let before = oldValue?.credentials, now = server?.credentials
            guard before?.serverID != now?.serverID || before?.userID != now?.userID else { return }
            offer = nil
            lastSavedAt = nil
            hasYielded = false
            ready = nil
            mayMakeReady = true
            if server != nil { Task { await refresh() } }
        }
    }

    private let player: AudioPlayer
    private let radio: RadioController
    private let library: LibraryStore
    private let settings: AppSettings
    private let identity: ClientIdentity

    /// When this device last saved, by its own clock: another device's
    /// state is news only when it is newer.
    @ObservationIgnored private var lastSavedAt: Date?
    /// The music was taken over from here: this device has stopped, and
    /// keeps quiet about that, or its save would cover the other's.
    @ObservationIgnored private var hasYielded = false
    /// Taken over from that device, and when: said in every save from then
    /// on (PlayState.takenAt has why).
    @ObservationIgnored private var takenFrom: String?
    @ObservationIgnored private var takenAt: Date?
    /// The taking-over this device last gave way to, by its time, kept
    /// across launches: each is obeyed once. Without it a device that had
    /// given the music away stopped again at every Play, for as long as the
    /// other's state said "taken from you".
    @ObservationIgnored private var obeyedTakeover: TimeInterval {
        get { UserDefaults.standard.double(forKey: "handoffObeyedTakeover") }
        set { UserDefaults.standard.set(newValue, forKey: "handoffObeyedTakeover") }
    }
    /// The music waiting in the player, paused, since launch, until Play
    /// (or other music) — `entry` its song in the queue. Nothing is saved
    /// meanwhile: the state it came from stays on the server as it was.
    @ObservationIgnored private var ready: (state: PlayState, isOwn: Bool, entry: UUID)?
    /// Nothing has been in the player since launch: the first music to go
    /// on with may wait there. Once only — music stopped by hand is not
    /// brought back a quarter of a minute later.
    @ObservationIgnored private var mayMakeReady = true
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(player: AudioPlayer, radio: RadioController, library: LibraryStore, settings: AppSettings,
         identity: ClientIdentity) {
        self.player = player
        self.radio = radio
        self.library = library
        self.settings = settings
        self.identity = identity
    }

    /// Once, at launch: watch the player, and ask the server now and then.
    func start() {
        guard loop == nil else { return }
        watchPlayer()
        loop = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                ticks += 1
                // Every other round while music plays: the half minute.
                // (`save` reads first, so this is a look at the server too.)
                if ticks % 2 == 0, self.player.isPlaying {
                    self.save()
                } else {
                    await self.refresh()
                }
            }
        }
    }

    // MARK: Reading

    /// What the server has now; and whether the music was taken from here.
    func refresh() async {
        guard let server else { return }
        guard let state = try? await server.playState() else {
            // No answer is not "nothing": what was offered stays.
            return
        }
        guard server.credentials == self.server?.credentials else { return }
        read(state)
    }

    /// What another device (or this one, last time) kept: offered, and
    /// obeyed when it says the music went there. True when it did.
    @discardableResult
    private func read(_ state: PlayState) -> Bool {
        let isOwn = state.isOwn(identity)
        var taken = false
        if !isOwn, state.takenFrom == identity.deviceID, let at = state.takenAt?.timeIntervalSince1970,
           abs(at - obeyedTakeover) > 0.001 {
            // "Continue Here" on the other device, not seen before: the
            // music is there now. Seen is seen, playing or not: a later
            // Play here is this device's own.
            obeyedTakeover = at
            if player.isPlaying {
                taken = true
                hasYielded = true
                player.pause()
            }
        }
        var made = makeOffer(state, isOwn: isOwn)
        // At launch, in the player rather than on Home. Not what plays on
        // another device right now: that is said, "Playing on …".
        if let first = made, mayMakeReady, settings.resumeOnLaunch, !player.hasTrack,
           first.isOwn || !first.state.isLive() {
            mayMakeReady = false
            if goOn(with: first, playing: false) { made = nil }
        }
        offer = made
        return taken
    }

    private func makeOffer(_ state: PlayState, isOwn: Bool) -> Offer? {
        guard let id = state.currentTrackID, let track = library.track(id: id) else { return nil }
        if isOwn {
            // This device's own last session, while nothing is loaded.
            return player.hasTrack ? nil : Offer(state: state, track: track, isOwn: true)
        }
        // Another device's, unless this one has done something since, or
        // has it waiting in the player: then only a newer save is news.
        if player.hasTrack, !hasYielded, let lastSavedAt, lastSavedAt >= state.updatedAt { return nil }
        if let ready, ready.state.deviceID == state.deviceID, state.updatedAt <= ready.state.updatedAt { return nil }
        return Offer(state: state, track: track, isOwn: false)
    }

    // MARK: Going on here

    /// The offered music, here: its queue from its song, where that was —
    /// or is by now, when the other device is still playing it.
    func continueHere() {
        guard let offer, goOn(with: offer, playing: true) else { return }
        self.offer = nil
    }

    // MARK: Play with nothing loaded

    /// Play with nothing in the player, on a desktop (Linux's Play key and
    /// Space, the Mac's Space and its Play key): the music to go on with if
    /// there is some, else Your Station. A computer's Play is always the
    /// listener's own hand, so it may start music. Never on the iPhone: a
    /// car or headphones send Play by themselves when they connect, and
    /// Apple's HIG lets that only resume (RemoteCommands.swift).
    func playWithNothingLoaded(from: String) {
        guard !player.hasTrack else { return }
        if let offer, goOn(with: offer, playing: true) {
            self.offer = nil
            return
        }
        startYourStation(from: from)
    }

    /// Your Station, from outside the window (the keys above, the Mac's
    /// Dock menu, GNOME's launcher menu); played on if it is already the one
    /// in the player. `from` is `station_started`'s (docs/STATS.md).
    func startYourStation(from: String) {
        // Before the library is in, the station would have nothing to choose from.
        guard !library.tracks.isEmpty else { return }
        let station = radio.station(for: .personal)
        if player.context?.station?.id == station.id {
            player.resume()
            return
        }
        Stats.track(.stationStarted, ["seed": "personal", "from": from])
        radio.start(station)
    }

    /// The offer's queue in the player, at its song and place. Playing, it
    /// is taken over now; paused, it waits for Play (`ready`), which takes
    /// it over then. False when the player would not have it.
    private func goOn(with offer: Offer, playing: Bool) -> Bool {
        let state = offer.state
        // Songs this library does not have (removed since) are passed over.
        var tracks: [Track] = []
        var index = 0
        for (position, id) in state.trackIDs.enumerated() {
            guard let track = library.track(id: id) else { continue }
            if position == state.index { index = tracks.count }
            tracks.append(track)
        }
        guard !tracks.isEmpty else { return false }
        var position = state.position
        // Another device's, still playing: it played on since it was saved.
        // (This device's own last session did not: the app was closed.)
        if !offer.isOwn, state.isLive() {
            position += Date().timeIntervalSince(state.updatedAt)
            if tracks[index].duration > 0, position > tracks[index].duration - 2 {
                position = 0
                if index + 1 < tracks.count { index += 1 }
            }
        }
        let title = state.title ?? state.station?.title ?? String(localized: "Continued")
        // The saved queue keeps only its title. One that is a playlist marked
        // Don't Count Plays goes on as that playlist, so the Christmas music
        // taken up after a restart is still not counted.
        // ponytail: by name; a PlayState with the playlist's id if names clash.
        let marked = player.notCounted.marks.items.first { $0.kind == .playlist && $0.name == title }
        let context = marked.map { QueueContext(.playlist($0.id), title: title) } ?? QueueContext(.other, title: title)
        player.play(tracks, startingAt: index, context: context, paused: !playing)
        // Offline, the player may have refused, or started another song (the
        // first one on the phone): then nothing was taken over.
        guard let entry = player.current, entry.track.id == tracks[index].id else { return false }
        hasYielded = false
        ready = nil
        if position > 1 { player.seek(to: position) }
        if playing {
            takeOver(state, isOwn: offer.isOwn)
            save()
        } else {
            ready = (state, offer.isOwn, entry.id)
        }
        return true
    }

    /// Gone on with here: said in this device's saves from now on, and a
    /// station plays on as a station (it chooses what comes next). For
    /// music waiting paused, at Play: a station started earlier would have
    /// played at once (continueAsRadio plays). One the listener started on
    /// it meanwhile (Start Radio) stays.
    private func takeOver(_ state: PlayState, isOwn: Bool) {
        takenFrom = isOwn ? nil : state.deviceID
        takenAt = isOwn ? nil : Date()
        // Acted on: from here on that state is no longer news.
        lastSavedAt = Date()
        if let station = state.station, player.context?.isRadio != true { radio.continueStation(station) }
    }

    /// Signed out: nothing of that account's is offered to the next.
    func reset() {
        saveTask?.cancel()
        offer = nil
        lastSavedAt = nil
        takenFrom = nil
        takenAt = nil
        hasYielded = false
        ready = nil
        mayMakeReady = true
    }

    // MARK: Saving

    /// The song, or whether it plays, changed: save a moment later (a skip
    /// through five songs is one save).
    private func watchPlayer() {
        withObservationTracking {
            _ = player.current?.id
            _ = player.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.playerChanged()
                self.watchPlayer()
            }
        }
    }

    private func playerChanged() {
        if player.hasTrack { mayMakeReady = false }
        // Play on the music waiting since launch (or Next, or a song of its
        // queue): Continue Here, from where it was. Other music started
        // instead is only that.
        if player.isPlaying, let ready {
            self.ready = nil
            // Acted on either way: that state is no longer news, nor offered
            // again before this device's own save covers it.
            lastSavedAt = Date()
            if player.queue.contains(where: { $0.id == ready.entry }) { takeOver(ready.state, isOwn: ready.isOwn) }
        }
        // Playing again, by the listener's own hand: this device's music.
        if player.isPlaying { hasYielded = false }
        if player.hasTrack, offer?.isOwn == true { offer = nil }
        saveTask?.cancel()
        // A pause is saved at once: a phone paused in a pocket is put to
        // sleep by the system within moments.
        guard player.isPlaying else {
            save()
            return
        }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        // Nothing loaded is not saved: what was left off stays on the
        // server for the next device, or this one's next launch. Nor music
        // only waiting in the player: it is that same state still.
        guard let server, !hasYielded, player.hasTrack, ready == nil else { return }
        Task {
            // Read before writing: another device may have taken the music
            // over since this one last looked, and a save now would cover
            // that with this device's, which is about to stop.
            if let there = try? await server.playState(), server.credentials == self.server?.credentials {
                if read(there) { return }
                // Paused here, and another device has saved since: the
                // pause is old news, theirs is what the next device wants.
                if !player.isPlaying, !there.isOwn(identity),
                   there.updatedAt > (lastSavedAt ?? .distantPast) { return }
            }
            guard !hasYielded, ready == nil, let index = player.currentIndex, player.hasTrack else { return }
            let now = Date()
            let state = PlayState(deviceID: identity.deviceID, deviceName: identity.deviceName, updatedAt: now,
                                  isPlaying: player.isPlaying, queue: player.queue.map(\.track.id), index: index,
                                  position: player.elapsed, title: player.context?.title,
                                  station: player.context?.station, takenFrom: takenFrom, takenAt: takenAt)
            lastSavedAt = now
            // A save that fails is only a save missed: the next comes soon.
            try? await server.savePlayState(state)
        }
    }
}
