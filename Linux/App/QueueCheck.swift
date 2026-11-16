// A check of the queue's rules (Jukebox/Player/PlayQueue.swift), the ones
// both players share, run with an engine that does nothing:
// dev/linux-errors.sh runs it after every build (JUKEBOX_CHECK=queue). Next
// and previous, repeat, Play Next and Add to Queue with Up Next's "Then",
// move and remove, shuffle and back, a station chosen again and trimmed.
// Nothing is sent (Stats off, no server) and nothing written (no song
// plays, so none is finished into the history).

import Foundation
import JukeboxKit

/// The queue with no engine: every song has an address, none plays.
private final class Bench: PlayQueue {
    override func address(of entry: QueueEntry, playSessionID: String) -> URL? {
        URL(fileURLWithPath: "/dev/null")
    }
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

        for what in failed { print("queue check failed: \(what)") }
        print("queue rules: \(checks - failed.count) of \(checks) checks pass")
        return failed.isEmpty ? 0 : 1
    }
}
