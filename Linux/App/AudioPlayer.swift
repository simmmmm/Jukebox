// Linux's player: the shared queue (Jukebox/Player/PlayQueue.swift) with
// GStreamer for its engine, as the iPhone's is with AVQueuePlayer. The
// queue's rules — what plays next, shuffle and repeat, the radio's feed,
// what the server is told and when, what a play is — are that file's, so
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

/// The next song's address, for GStreamer's thread to take when it asks.
nonisolated final class Handover: @unchecked Sendable {
    private let lock = NSLock()
    private var uri: String?
    private var taken = false
    /// The loaded address's own stream start, not yet heard. GStreamer can
    /// ask for the next address before it: a short song over a quick
    /// network is all fetched at once, and "about-to-finish" comes as it
    /// starts, while its own start still waits on the main loop. Taken for
    /// the next song's, that start moved the queue on one song early.
    private var ownStartDue = false

    /// An address loaded by hand: nothing offered yet, and the next stream
    /// start is its own.
    func loaded() {
        lock.lock(); defer { lock.unlock() }
        uri = nil
        taken = false
        ownStartDue = true
    }

    func offer(_ uri: String?) {
        lock.lock(); defer { lock.unlock() }
        self.uri = uri
        taken = false
    }

    /// A stream started: whether it is the taken address's (gapless), not
    /// the loaded one's own start.
    func started() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if ownStartDue {
            ownStartDue = false
            return false
        }
        return taken
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

final class AudioPlayer: PlayQueue {
    private let engine: UnsafeMutablePointer<GstElement>
    private let handover = Handover()
    /// The entry whose address `handover` holds, with its play session.
    private var offered: (entryID: UUID, playSessionID: String)?
    /// Where to go once the stream can seek (a queue taken over from
    /// another device starts part-way).
    private var pendingSeek: TimeInterval?

    override init(settings: AppSettings, history: HistoryStore) {
        gst_init(nil, nil)
        // playbin3 since GStreamer 1.22 is the one that is looked after;
        // playbin where a distribution's is older.
        engine = gst_element_factory_make("playbin3", "player") ?? gst_element_factory_make("playbin", "player")!
        super.init(settings: settings, history: history)
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

    override func stop() {
        super.stop()
        isBuffering = false
    }

    /// The network went or came back (OfflineStore, through AppModel): the
    /// next song waiting for GStreamer is chosen again, offline perhaps a
    /// later one, back online the very next again.
    func connectivityChanged() {
        if !handover.wasTaken() {
            handover.offer(nil)
            offered = nil
        }
        preloadNext()
    }

    // MARK: The engine, for the queue

    override func engineReplace(with url: URL, entry: QueueEntry, playSessionID: String, play: Bool) {
        // NULL drops what the bus still held of the stream before.
        gst_element_set_state(engine, GST_STATE_NULL)
        handover.loaded()
        offered = nil
        jb_set_string(engine, "uri", url.absoluteString)
        pendingSeek = nil
    }

    override func engineStart(_ play: Bool) {
        gst_element_set_state(engine, play ? GST_STATE_PLAYING : GST_STATE_PAUSED)
    }

    /// The entry after the current one waits in `handover` for GStreamer
    /// to ask for it.
    override func enginePreload(_ entry: QueueEntry?) {
        guard let entry else {
            if !handover.wasTaken() {
                handover.offer(nil)
                offered = nil
            }
            return
        }
        // Already offered, or already taken (it will play next whatever
        // the queue now says: the queue follows it when it starts).
        if offered?.entryID == entry.id || handover.wasTaken() { return }
        let playSessionID = UUID().uuidString
        guard let url = address(of: entry, playSessionID: playSessionID) else { return }
        offered = (entry.id, playSessionID)
        handover.offer(url.absoluteString)
    }

    override var engineHeldNext: UUID? { handover.wasTaken() ? offered?.entryID : nil }

    override func engineResume() {
        gst_element_set_state(engine, GST_STATE_PLAYING)
    }

    override func enginePause() {
        gst_element_set_state(engine, GST_STATE_PAUSED)
    }

    override func engineSeek(to target: TimeInterval) {
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

    override func engineHalt() {
        gst_element_set_state(engine, GST_STATE_NULL)
        handover.offer(nil)
        offered = nil
        // In NULL GStreamer says nothing more, so not that it stopped.
        isPlaying = false
    }

    /// playbin's one volume: the listener's level times the song's.
    override func engineVolume(_ level: Double) {
        jb_set_double(engine, "volume", level)
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
            // The stream ended with nothing taken to follow it.
            if playing != nil { entryEnded() }
        case GST_MESSAGE_ERROR:
            let text = jb_message_error(message)
            let words = text.map { String(cString: $0) } ?? ""
            g_free(text)
            if playing != nil { entryFailed(reason: Stats.playbackFailure(words)) }
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
    /// the queue follows. GStreamer may ask what follows a short song
    /// before that song's start is heard here, with nothing offered yet:
    /// then the song ends, and the next loads by hand (`entryEnded`), a
    /// moment's gap in the right order.
    private func streamStarted() {
        guard handover.started(), let offered,
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
        let justStarted = engineRuns(state == GST_STATE_PLAYING)
        // Where a queue taken over from another device was left: a stream
        // can seek once it is paused or playing.
        if state == GST_STATE_PAUSED || state == GST_STATE_PLAYING, let target = pendingSeek {
            pendingSeek = nil
            gst_element_seek_simple(engine, GST_FORMAT_TIME,
                                    GstSeekFlags(GST_SEEK_FLAG_FLUSH.rawValue | GST_SEEK_FLAG_KEY_UNIT.rawValue),
                                    jb_seconds(target))
        }
        // Playing while waiting for the network too: the button shows Pause.
        showPlaying(playing != nil && (state == GST_STATE_PLAYING || (isBuffering && wantsToPlay)),
                    justStarted: justStarted)
    }

    private func tick() {
        // The sleep timer's deadline and fade, before anything else.
        checkSleep()
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
        engineVolume(level(for: playing.entry.track))
        if isPlaying, !isBuffering { reportWhilePlaying() }
    }
}
