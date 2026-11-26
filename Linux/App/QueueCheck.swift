// A check of the queue's rules (Jukebox/Player/PlayQueue.swift), the ones
// both players share, run with an engine that does nothing:
// dev/linux-errors.sh runs it after every build (JUKEBOX_CHECK=queue). Next
// and previous, repeat, Play Next and Add to Queue with Up Next's "Then",
// move and remove, shuffle and back, a station chosen again and trimmed,
// the sleep timer, album gain; and Linux's volume, the stream's.
// Nothing is sent (Stats off, no server) and nothing written (no song
// plays, so none is finished into the history).

import CGst
import Foundation
import JukeboxKit

/// A device elsewhere that takes everything and says nothing.
private final class SilentRemote: RemotePlayer {
    let device = PlayOnDevice(id: "check", name: "Check", kind: .chromecast, address: "")
    var reportsItself: Bool { false }
    var capacity: Int { 1 }
    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws {}
    func append(_ entries: [RemoteEntry]) async throws {}
    func resume() async throws {}
    func pause() async throws {}
    func seek(to position: TimeInterval) async throws {}
    func setVolume(_ level: Double) async throws {}
    func stop() async {}
    func status() async throws -> RemoteStatus { RemoteStatus() }
}

/// The queue with no engine: every song has an address, none plays.
private final class Bench: PlayQueue {
    /// What the engine was told to hold next, and at what quality.
    var held: UUID?
    var heldAt: StreamQuality?
    /// A network that costs data, where Adjust to the Connection works.
    var costly = false
    override var isNetworkExpensive: Bool { costly }

    /// Streamed, as the queue's own would ask it (`noteSound`).
    override func address(of entry: QueueEntry, playSessionID: String) -> URL? {
        noteSound(of: entry, streamedAt: streamingQuality)
        return URL(fileURLWithPath: "/dev/null")
    }

    override func enginePreload(_ entry: QueueEntry?) {
        held = entry?.id
        heldAt = entry == nil ? nil : streamingQuality
        if let entry { _ = address(of: entry, playSessionID: "held") }
    }

    /// The target, whatever this machine's settings say.
    override var streamQuality: StreamQuality { .original }
}

enum QueueCheck {
    static func run() -> Int32 {
        UserDefaults.standard.set(false, forKey: Stats.key)
        var failed: [String] = []
        var checks = 0
        func expect(_ ok: Bool, _ what: String) {
            checks += 1
            if !ok { failed.append(what) }
        }
        func ids(_ entries: [QueueEntry]) -> [ItemID] { entries.map(\.track.id) }
        let tracks = (1...5).map { Track(id: "t\($0)", name: "Song \($0)", duration: 200) }
        let album = QueueContext(.album("a"), title: "Album")
        let q = Bench(settings: AppSettings(), history: HistoryStore())

        q.play(tracks, context: album)
        expect(q.currentIndex == 0 && q.upNext.count == 4, "an album starts at its first")
        q.next()
        expect(q.currentIndex == 1, "Next")
        q.previous()
        expect(q.currentIndex == 0, "Previous in the first 3 s goes back")
        q.previous()
        expect(q.currentIndex == 0, "Previous on the first stays")
        q.repeatMode = .all
        q.previous()
        expect(q.currentIndex == 4, "Previous on the first, Repeat All: the last")
        q.next()
        expect(q.currentIndex == 0, "Next on the last, Repeat All: the first")
        q.repeatMode = .off
        q.skip(to: q.queue[4])
        q.next()
        expect(q.currentIndex == 4, "Next on the last: it stays, at its start")
        q.cycleRepeat()
        q.cycleRepeat()
        expect(q.repeatMode == .one, "Repeat: off, all, one")
        q.cycleRepeat()
        expect(q.repeatMode == .off, "and off again")

        // Play Next after the playing song, Add to Queue at the end: only
        // the queued songs at the end come under "Then".
        q.play(tracks, context: album)
        q.playNext([Track(id: "x", name: "X")])
        q.addToQueue([Track(id: "y", name: "Y")])
        expect(ids(q.upNext) == ["x", "t2", "t3", "t4", "t5", "y"], "Play Next, Add to Queue")
        var underThen: [ItemID] = []
        var seenThen = false
        for row in UpNextList.items(current: q.current, upNext: q.upNext, context: q.context,
                                    currentIndex: q.currentIndex, added: q.addedIDs, autoplay: false,
                                    repeatMode: q.repeatMode) {
            if case .then = row { seenThen = true }
            if seenThen, case let .song(entry, _, style, _, _) = row, style == .covered { underThen.append(entry.track.id) }
        }
        expect(underThen == ["y"], "\"Then\": the song added at the end")

        q.moveUpcoming(fromOffsets: [0], toOffset: 3)
        expect(ids(q.upNext) == ["t2", "t3", "x", "t4", "t5", "y"], "Move: before the offset given")
        q.removeUpcoming(atOffsets: [1])
        expect(ids(q.upNext) == ["t2", "x", "t4", "t5", "y"], "Remove")

        let order = ids(q.queue)
        q.toggleShuffle()
        expect(q.isShuffled && q.current?.track.id == "t1" && Set(ids(q.queue)) == Set(order),
               "Shuffle keeps the playing song and every other")
        q.toggleShuffle()
        expect(!q.isShuffled && ids(q.queue) == order, "and back to the order it had")

        q.play(tracks, startingAt: 2, context: album, shuffled: true)
        expect(q.isShuffled && q.current?.track.id == "t3" && q.queue.count == 5, "shuffled, from the song asked for")
        q.addToQueue([Track(id: "y", name: "Y")])
        q.toggleShuffle()
        expect(ids(q.upNext) == ["t1", "t2", "t4", "t5", "y"], "unshuffled: the album's order, then what was added")

        // A station: the radio's order, chosen again around what the
        // listener queued, and its played part trimmed on a long evening.
        let station = Station(id: "s", seed: .track("t1"), title: "Song 1 Radio")
        func picks(_ tracks: [Track]) -> [RadioPick] { tracks.map { RadioPick(track: $0, reason: .discovery, score: 1) } }
        q.repeatMode = .one
        q.playRadio(picks(tracks), station: station)
        expect(q.context?.isRadio == true && q.repeatMode == .off && q.currentIndex == 0, "a station: its first, no repeat")
        q.playNext([Track(id: "x", name: "X")])
        let removed = q.removeUpcomingRadioPicks()
        expect(removed == ["t2", "t3", "t4", "t5"] && ids(q.upNext) == ["x"], "chosen again: what was queued stays")
        q.appendRadio(picks((1...250).map { Track(id: "r\($0)", name: "R\($0)") }))
        q.skip(to: q.queue[205])
        let playing = q.current?.id
        q.appendRadio(picks([Track(id: "z", name: "Z")]))
        expect(q.currentIndex == 100 && q.current?.id == playing && q.queue.last?.track.id == "z",
               "a long station keeps the last hundred played")

        // The volume, clamped to 0...1 (it crashed the app once its own
        // didSet set it again under @Observable, 16 November 2026).
        let volume = q.volume
        q.volume = 0.5
        expect(q.volume == 0.5, "Volume 0.5")
        q.volume = 2
        expect(q.volume == 1, "Volume above 1: 1")
        q.volume = -1
        expect(q.volume == 0, "Volume below 0: 0")
        q.volume = volume

        // The sleep timer: a timer of minutes fades over its last seconds
        // and pauses at its deadline, the volume whole again; End of Song
        // holds nothing after the song and waits for it to end; End of
        // Queue beats Repeat All; Off stops nothing. The engine "plays".
        let start = Date()
        let whole = q.level(for: tracks[0])
        q.play(tracks, context: album)
        q.isPlaying = true
        q.setSleepTimer(.minutes(15), now: start)
        q.checkSleep(now: start.addingTimeInterval(14 * 60))
        expect(q.sleepChoice == .minutes(15) && q.sleepLeft == 60 && q.wantsToPlay, "15 minutes: one left after 14")
        q.checkSleep(now: start.addingTimeInterval(15 * 60 - PlayQueue.sleepFade / 2))
        expect(abs(q.level(for: tracks[0]) - whole / 2) < 0.001, "half as loud halfway through its fade")
        q.checkSleep(now: start.addingTimeInterval(15 * 60 + 0.5))
        expect(q.sleepChoice == nil && q.sleepLeft == nil && !q.wantsToPlay && q.level(for: tracks[0]) == whole,
               "at its deadline: paused, the volume whole again")

        q.play(tracks, context: album)
        q.setSleepTimer(.endOfSong)
        expect(q.held == nil, "End of Song: nothing held after the song")
        q.checkSleep(now: start.addingTimeInterval(24 * 3600))
        expect(q.sleepChoice == .endOfSong && q.wantsToPlay, "End of Song waits for the song, however long")
        q.entryEnded()
        expect(q.currentIndex == 1 && !q.wantsToPlay && q.sleepChoice == nil && q.held == q.queue[2].id,
               "and then the next waits, paused, and is held again")

        q.play(tracks, startingAt: 4, context: album)
        q.repeatMode = .all
        q.setSleepTimer(.endOfQueue)
        expect(q.sleepTitle(.endOfQueue) == "End of Album" && q.held == nil, "End of Album: Repeat All does not go round")
        q.entryEnded()
        expect(q.currentIndex == 4 && !q.wantsToPlay && q.sleepChoice == nil, "and at its end it stops there")
        q.repeatMode = .off

        q.play(tracks, context: album)
        q.setSleepTimer(.minutes(15), now: start)
        q.setSleepTimer(nil)
        q.checkSleep(now: start.addingTimeInterval(16 * 60))
        expect(q.sleepChoice == nil && q.sleepDeadline == nil && q.wantsToPlay, "Off: nothing stops")
        q.playRadio(picks(tracks), station: station)
        expect(!q.sleepChoices.contains(.endOfQueue), "a station has no end to wait for")
        q.isPlaying = false

        // Crossfade (4 s: 2 out, 2 in), through `level(for:)` as the sleep
        // timer's fade: never between songs that follow each other on
        // their album; across albums the tail fades and the next, come on
        // by itself, fades in; a move by hand cuts.
        let saved = q.settings.crossfade
        q.settings.crossfade = 4
        func song(_ id: String, album: String, _ number: Int) -> Track {
            var track = Track(id: id, name: id, duration: 200)
            track.albumID = album
            track.trackNumber = number
            return track
        }
        let mixed = [song("a1", album: "A", 1), song("a2", album: "A", 2), song("b1", album: "B", 1)]
        q.play(mixed, context: QueueContext(.songs, title: "Songs"))
        q.elapsed = 198.5
        expect(q.level(for: mixed[0]) == whole, "Crossfade: the next on its album, no fade")
        q.entryEnded()
        q.elapsed = 198.5
        expect(abs(q.level(for: mixed[1]) - whole / 2) < 0.001, "across albums: half as loud halfway through its fade")
        q.entryEnded()
        q.elapsed = 1
        expect(q.currentIndex == 2 && abs(q.level(for: mixed[2]) - whole / 2) < 0.001, "and the next fades in")
        q.play(mixed, startingAt: 1, context: QueueContext(.songs, title: "Songs"))
        q.elapsed = 198.5
        q.next()
        q.elapsed = 0
        expect(q.level(for: mixed[2]) == whole, "a skip by hand cuts")
        q.play(mixed, startingAt: 1, context: QueueContext(.songs, title: "Songs"))
        q.isPlaying = true
        q.setSleepTimer(.minutes(15), now: start)
        q.elapsed = 198.5
        q.checkSleep(now: start.addingTimeInterval(15 * 60 - PlayQueue.sleepFade / 2))
        expect(abs(q.level(for: mixed[1]) - whole / 4) < 0.001, "the sleep timer's fade and the crossfade together")
        q.setSleepTimer(nil)
        q.isPlaying = false
        // Playing on another device, the device has the volume: no fade.
        q.play(mixed, startingAt: 1, context: QueueContext(.songs, title: "Songs"))
        q.playingElsewhere = SilentRemote()
        q.elapsed = 198.5
        expect(q.level(for: mixed[1]) == whole, "Crossfade: none while it plays elsewhere")
        q.playingElsewhere = nil
        q.settings.crossfade = saved

        q.stop()
        expect(q.queue.isEmpty && !q.hasTrack && q.context == nil, "Stop")

        // Linux's gapless handover (AudioPlayer.swift): GStreamer took the
        // next address before the loaded song's own start was heard (a
        // short song, all fetched at once). That start is still the loaded
        // song's; only the one after it is the next's.
        let handover = Handover()
        handover.loaded()
        handover.offer("next")
        _ = handover.take()
        expect(!handover.started() && handover.started(), "a short song's own start is not the next one's")

        // Songs added on the server play without a relaunch: back at the
        // window, a library read a while ago is read again
        // (LibraryStore.refreshIfStale); one just read, or not yet, is not.
        let now = Date()
        expect(LibraryStore.isStale(now.addingTimeInterval(-LibraryStore.staleAfter), now: now),
               "a library read a while ago is read again")
        expect(!LibraryStore.isStale(now.addingTimeInterval(-60), now: now), "nor one read a minute ago")
        expect(!LibraryStore.isStale(nil, now: now), "nor one not read yet")

        // Album gain while the album is heard as one, the song's own
        // otherwise, and the song's when the album has none.
        let song = Track(id: "g", name: "G", albumID: "a", normalizationGain: -9)
        func gain(_ context: QueueContext?, shuffled: Bool = false, oneAlbum: Bool = false, album: Double? = -6) -> Double? {
            PlayQueue.gain(for: song, albumGain: album, context: context, isShuffled: shuffled, queueIsItsAlbum: oneAlbum)
        }
        expect(gain(album) == -6, "an album in order plays at its album gain")
        expect(gain(album, shuffled: true) == -9, "shuffled, at the song's")
        expect(gain(album, shuffled: true, oneAlbum: true) == -6, "a queue of one album, at the album's")
        expect(gain(QueueContext(.playlist("p"), title: "P")) == -9, "a playlist, at the song's")
        expect(gain(album, album: nil) == -9, "no album gain: the song's")

        // Songs picked in a list (TrackPicks): Ctrl one by one, Shift a run,
        // the menu on a pick for all of them, on another row for that row.
        var picks = TrackPicks()
        picks.plain(1)
        picks.click(3, .extend)
        expect(picks.rows == [1, 2, 3], "Shift after a plain click picks the run from it")
        picks.click(2, .toggle)
        picks.click(0, .toggle)
        expect(picks.rows == [0, 1, 3], "Ctrl takes one out and puts one in")
        expect(picks.tracks(at: 3, in: tracks).map(\.id) == ["t1", "t2", "t4"], "the menu on a pick is for every pick, in order")
        expect(picks.tracks(at: 4, in: tracks).map(\.id) == ["t5"], "and on another row for that row")
        expect(picks.moved(tracks, toTop: true).map(\.id).prefix(4) == ["t1", "t2", "t4", "t3"], "Move to Top takes the picks up, in order")
        expect(picks.moved(tracks, toTop: false).map(\.id).suffix(3) == ["t1", "t2", "t4"], "Move to Bottom takes them down, in order")
        expect(picks.moved(tracks, toTop: true).count == tracks.count, "and loses none")
        picks.click(4, .extend)
        expect(picks.rows == [0, 1, 2, 3, 4], "Shift runs from the last Ctrl-click")
        picks.clear()
        expect(picks.isEmpty && picks.tracks(at: 9, in: tracks).isEmpty, "cleared, and a row past the end is nothing")

        // Don't Count Plays (NotCountedStore, PlayQueue.counts): a marked
        // song plays, but its play is neither told to the server nor kept
        // in the history. No account is open, so nothing is written.
        let heard = HistoryStore()
        let c = Bench(settings: AppSettings(), history: heard)
        c.notCounted.set(.song, id: "t2", name: "Song 2", counted: false)
        c.play(tracks, context: album)
        c.engineRuns(true)
        c.playing?.heard = 150
        // Private Listening is the machine's own (UserDefaults): read, never
        // set here. On, nothing counts.
        expect(c.reportStartIfNeeded() != c.notCounted.isPrivate, "an unmarked song counts")
        c.next()
        c.engineRuns(true)
        c.playing?.heard = 150
        expect(c.current?.track.id == "t2" && !c.reportStartIfNeeded(), "a marked song plays, not told to the server")
        c.next()
        expect(heard.history.events.map(\.trackID) == (c.notCounted.isPrivate ? [] : ["t1"]), "nor kept in the history")
        c.stop()

        // Adjust to the Connection (QualitySteps): a wait mid-song asks the
        // next song lower at once, the one already held too; three songs
        // without a wait ask it at the target again.
        // The switch as it starts, whatever this machine's settings say.
        let a = Bench(settings: AppSettings(defaults: UserDefaults(suiteName: "jukebox-queue-check") ?? .standard),
                      history: HistoryStore())
        a.play(tracks, context: album)
        a.bufferingChanged(true, now: Date().addingTimeInterval(10))
        a.bufferingChanged(false, now: Date().addingTimeInterval(11))
        expect(a.streamingQuality == .original, "on Wi-Fi a wait mid-song changes nothing")
        a.costly = true
        a.play(tracks, context: album)
        a.isBuffering = true
        a.isBuffering = false
        expect(a.streamingQuality == .original, "a wait as a song starts is its start, not a slow network")
        a.bufferingChanged(true, now: Date().addingTimeInterval(10))
        a.bufferingChanged(false, now: Date().addingTimeInterval(11))
        expect(a.streamingQuality == .normal && a.heldAt == .normal, "a wait mid-song: the next song, already held, is asked lower")
        for _ in 1...4 { a.next() }
        expect(a.current?.track.id == "t5" && a.streamingQuality == .original, "three songs without a wait: the target again")
        a.play(tracks, context: album)
        a.isBuffering = true
        a.next()
        a.bufferingChanged(false, now: Date().addingTimeInterval(9))
        expect(a.streamingQuality == .normal, "a song left while it waited: the next one's start, 9 s, steps down")
        a.stop()

        // Now Playing's "Lossless": the song playing as the engine was
        // given it, the one held next too, never elsewhere.
        let flac = (1...3).map { Track(id: "f\($0)", name: "Flac \($0)", duration: 200, container: "flac") }
        let l = Bench(settings: AppSettings(defaults: UserDefaults(suiteName: "jukebox-queue-check") ?? .standard),
                      history: HistoryStore())
        l.costly = true
        l.play(flac, context: album)
        expect(l.playsLossless, "a FLAC streamed as it is plays lossless")
        l.playsOn = PlayOnDevice(id: "check", name: "Check", kind: .chromecast, address: "")
        expect(!l.playsLossless, "nothing while it plays elsewhere")
        l.playsOn = nil
        expect(l.playsLossless, "and here again, as it was given")
        // One song on Repeat All: the entry held next is the one playing.
        l.play([flac[0]], context: album)
        l.repeatMode = .all
        l.bufferingChanged(true, now: Date().addingTimeInterval(10))
        l.bufferingChanged(false, now: Date().addingTimeInterval(11))
        expect(l.streamingQuality == .normal && l.playsLossless,
               "a step down: the song playing stays as it was given, though held again lower after itself")
        l.begin(l.queue[0], at: 0, playSessionID: "again")
        expect(!l.playsLossless, "round again by itself, as held at Normal: converted")
        l.repeatMode = .off
        l.play(tracks, context: album)
        expect(!l.playsLossless, "a song of no known container is not")
        l.stop()

        // Linux's engine (AudioPlayer.swift): the listener's volume is the
        // stream's, GNOME's per-app volume, both ways; the song's gain is
        // in Jukebox's own `volume` element, never in the stream.
        setenv("JUKEBOX_AUDIO_SINK", "fakesink", 1)
        let engineSettings = AppSettings()
        let player = AudioPlayer(settings: engineSettings, history: HistoryStore())
        player.volume = 0.5
        expect(abs(player.streamVolume - 0.125) < 0.0001, "the listener's volume is the stream's, cubic as GNOME's")
        player.streamVolume = 0.027
        while g_main_context_iteration(nil, 0) != 0 {}
        expect(abs(player.volume - 0.3) < 0.001, "GNOME's slider moves the listener's volume")
        engineSettings.normalizeVolume = true
        player.begin(QueueEntry(track: Track(id: "g", name: "G", normalizationGain: -6)), at: 0, playSessionID: "c")
        expect(abs(player.effectsVolume - 0.501) < 0.001, "the song's gain in Jukebox's own volume")
        expect(abs(player.streamVolume - 0.027) < 0.0001 && abs(player.volume - 0.3) < 0.001,
               "and never in the stream")
        engineSettings.normalizeVolume = false

        // Play On's question about the speaker's key (PlayOn.needsKeyNotice):
        // a Subsonic token once per account, an API key and Jellyfin never.
        if let defaults = UserDefaults(suiteName: "jukebox-queue-check") {
            defaults.removeObject(forKey: "playOn.keyAccepted")
            let identity = ClientIdentity(clientVersion: "1", deviceName: "Check", deviceID: "check")
            func server(_ kind: ServerKind, _ secret: ServerSecret) -> any MusicServer {
                MusicServers.open(ServerCredentials(kind: kind, serverURL: URL(string: "https://music.example.com")!,
                                                    serverID: "s", serverName: "S", userID: "u", userName: "anna",
                                                    secret: secret), identity: identity)
            }
            let token = server(.subsonic(flavour: .navidrome), .subsonicToken(token: "t", salt: "s"))
            expect(PlayOn.needsKeyNotice(token, defaults: defaults), "a Subsonic token asks before its first cast")
            PlayOn.acceptKey(token, defaults: defaults)
            expect(!PlayOn.needsKeyNotice(token, defaults: defaults), "and once Cast Anyway, not again")
            expect(!PlayOn.needsKeyNotice(server(.subsonic(flavour: .navidrome), .subsonicAPIKey("k")), defaults: defaults)
                   && !PlayOn.needsKeyNotice(server(.jellyfin, .jellyfinToken("j")), defaults: defaults),
                   "an API key and Jellyfin's session never ask")
            defaults.removeObject(forKey: "playOn.keyAccepted")
        }

        for what in failed { print("queue check failed: \(what)") }
        print("queue rules: \(checks - failed.count) of \(checks) checks pass")
        return failed.isEmpty ? 0 : 1
    }
}
