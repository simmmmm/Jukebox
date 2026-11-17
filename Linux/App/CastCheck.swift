// A check of the Chromecast's socket and conversation end to end, against a
// receiver given in JUKEBOX_CAST_DEVICE ("Name@host:port"; a fake one, as
// no Chromecast is on the machine that builds): JUKEBOX_CHECK=cast. It
// connects over TLS (GioCastSocket), launches the Default Media Receiver,
// loads JUKEBOX_CAST_URL, pauses, plays, seeks, sets the volume, and waits
// for the receiver to say the song finished. Exit 0 when all of that came.

import CAdw
import Foundation
import JukeboxKit

enum CastCheck {
    private static var session = CastSession()
    private static var socket: GioCastSocket?
    private static var buffer = Data()
    private static var step = 0
    private static var result: Int32 = 1
    private static var loop: OpaquePointer?

    static func run() -> Int32 {
        guard let device = AvahiCastFinder.testDevice, let (host, port) = AvahiCastFinder.split(device.address),
              let url = ProcessInfo.processInfo.environment["JUKEBOX_CAST_URL"].flatMap(URL.init(string:)) else {
            print("cast check: set JUKEBOX_CAST_DEVICE=Name@host:port and JUKEBOX_CAST_URL")
            return 1
        }
        let socket = GioCastSocket(host: host, port: port)
        self.socket = socket
        socket.received = { data in
            guard let data else { return finish("the connection closed at step \(step)", 1) }
            buffer.append(data)
            do {
                for message in try CastFrame.take(from: &buffer) {
                    print("cast check: <- \(message.namespace) \(message.payload.prefix(160))")
                    send(session.receive(message))
                    advance()
                }
            } catch {
                finish("a frame did not read: \(error)", 1)
            }
        }
        send(session.start())
        send(session.load(CastMedia(url: url, contentType: "audio/mpeg", title: "Check", artist: "Jukebox"),
                          at: 0, autoplay: true))
        g_timeout_add_seconds(5, { _ in
            MainActor.assumeIsolated { CastCheck.send([CastCheck.session.ping()]) }
            return 1
        }, nil)
        g_timeout_add_seconds(40, { _ in
            MainActor.assumeIsolated { CastCheck.finish("timed out at step \(CastCheck.step)", 1) }
            return 0
        }, nil)
        loop = g_main_loop_new(nil, 0)
        g_main_loop_run(loop)
        return result
    }

    private static func send(_ messages: [CastMessage]) {
        for message in messages {
            print("cast check: -> \(message.namespace) \(message.payload.prefix(160))")
            socket?.send(CastFrame.encode(message))
        }
    }

    /// One step at a time, each on the status that answers the last.
    private static func advance() {
        if session.isClosed { return finish("the receiver closed", 1) }
        if let error = session.loadError { return finish("the load failed: \(error)", 1) }
        guard let media = session.media else { return }
        switch (step, media.state) {
        case (0, .playing):
            step = 1
            send(session.pause())
        case (1, .paused):
            step = 2
            send(session.play())
        case (2, .playing):
            step = 3
            send(session.seek(to: 2))
            send(session.setVolume(0.5))
        case (3, .idle) where media.idleReason == "FINISHED":
            guard session.volume == 0.5 else { return finish("the volume was not 0.5 but \(String(describing: session.volume))", 1) }
            finish("loaded, paused, played, seeked, volume 0.5, finished", 0)
        default:
            break
        }
    }

    private static func finish(_ what: String, _ code: Int32) {
        print("cast check: \(code == 0 ? "ok" : "FAILED"), \(what)")
        result = code
        socket?.close()
        socket = nil
        if let loop { g_main_loop_quit(loop) }
    }
}
