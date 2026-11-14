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
            if server != nil { Task { await refresh() } }
        }
    }

    private let player: AudioPlayer
    private let radio: RadioController
    private let library: LibraryStore
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
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(player: AudioPlayer, radio: RadioController, library: LibraryStore, identity: ClientIdentity) {
        self.player = player
        self.radio = radio
        self.library = library
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
        offer = makeOffer(state, isOwn: isOwn)
        return taken
    }

    private func makeOffer(_ state: PlayState, isOwn: Bool) -> Offer? {
        guard let id = state.currentTrackID, let track = library.track(id: id) else { return nil }
        if isOwn {
            // This device's own last session, while nothing is loaded.
            return player.hasTrack ? nil : Offer(state: state, track: track, isOwn: true)
        }
        // Another device's, unless this one has done something since.
        if player.hasTrack, !hasYielded, let lastSavedAt, lastSavedAt >= state.updatedAt { return nil }
        return Offer(state: state, track: track, isOwn: false)
    }

    // MARK: Going on here

    /// The offered music, here: its queue from its song, where that was —
    /// or is by now, when the other device is still playing it.
    func continueHere() {
        guard let offer else { return }
        let state = offer.state
        // Songs this library does not have (removed since) are passed over.
        var tracks: [Track] = []
        var index = 0
        for (position, id) in state.trackIDs.enumerated() {
            guard let track = library.track(id: id) else { continue }
            if position == state.index { index = tracks.count }
            tracks.append(track)
        }
        guard !tracks.isEmpty else { return }
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
        player.play(tracks, startingAt: index, context: QueueContext(.other, title: title))
        // Offline, the player may have refused, or started another song (the
        // first one on the phone): then nothing was taken over.
        guard player.currentTrack?.id == tracks[index].id else { return }
        takenFrom = offer.isOwn ? nil : state.deviceID
        takenAt = offer.isOwn ? nil : Date()
        hasYielded = false
        self.offer = nil
        // Acted on: from here on that state is no longer news.
        lastSavedAt = Date()
        if position > 1 { player.seek(to: position) }
        // A station plays on as a station: it chooses what comes next.
        if let station = state.station { radio.continueStation(station) }
        save()
    }

    /// Signed out: nothing of that account's is offered to the next.
    func reset() {
        saveTask?.cancel()
        offer = nil
        lastSavedAt = nil
        takenFrom = nil
        takenAt = nil
        hasYielded = false
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
        // server for the next device, or this one's next launch.
        guard let server, !hasYielded, player.hasTrack else { return }
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
            guard !hasYielded, let index = player.currentIndex, player.hasTrack else { return }
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
