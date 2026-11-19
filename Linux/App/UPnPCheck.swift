// A check of Play On's UPnP side (UPnP.swift), JUKEBOX_CHECK=upnp:
// - with JUKEBOX_UPNP_DEVICE (a fake renderer's description on this
//   computer, dev/fake-upnp-renderer.py): found as a Sonos room, then a
//   song loaded, paused, played, sought, its volume set, and its end heard.
//   Exit 0 when all of that came.
// - without: only looks, 10 s, and prints what Avahi and SSDP found on the
//   network. Nothing is played on a real speaker, ever.

import CAdw
import Foundation
import JukeboxKit

enum UPnPCheck {
    private static var result: Int32 = 1
    private static var loop: OpaquePointer?
    private static let finder = UPnPFinder()

    static func run() -> Int32 {
        loop = g_main_loop_new(nil, 0)
        if UPnPFinder.testLocation == nil {
            finder.start { devices in
                for device in devices {
                    let host = UPnPFinder.renderer(for: device)?.avTransport.host ?? "?"
                    print("upnp check: found \(device.name) (\(device.detail ?? "")) at \(host)")
                }
            }
            g_timeout_add_seconds(10, { _ in
                MainActor.assumeIsolated { UPnPCheck.finish("looked for 10 s", 0) }
                return 0
            }, nil)
        } else {
            finder.start { devices in
                guard let device = devices.first else { return }
                print("upnp check: found \(device.name) (\(device.detail ?? "")), \(device.address)")
                Task { await play(on: device) }
            }
            g_timeout_add_seconds(60, { _ in
                MainActor.assumeIsolated { UPnPCheck.finish("timed out", 1) }
                return 0
            }, nil)
        }
        g_main_loop_run(loop)
        return result
    }

    private static func play(on device: PlayOnDevice) async {
        guard let player = UPnPPlayer(device: device) else { return finish("no control address", 1) }
        let track = Track(id: "check", name: "Check & Co", albumName: "Checks", artists: [ArtistRef(id: "a", name: "Jukebox")], duration: 6)
        let url = URL(string: "http://192.0.2.1:8096/Audio/check/universal?Container=mp3&api_key=t")!
        let entry = RemoteEntry(track: track, stream: CastStream(url: url, contentType: "audio/mpeg"), artworkURL: nil)
        do {
            try await player.load([entry], at: 0, play: true)
            guard try await waitFor(player, "playing", { $0.isPlaying }) else { return }
            try await player.pause()
            guard try await waitFor(player, "paused", { !$0.isPlaying && !$0.hasEnded }) else { return }
            try await player.resume()
            guard try await waitFor(player, "playing again", { $0.isPlaying }) else { return }
            try await player.seek(to: 2)
            guard try await waitFor(player, "at 2 s", { $0.position >= 2 }) else { return }
            try await player.setVolume(0.3)
            guard try await waitFor(player, "volume 0.3", { abs(($0.volume ?? 0) - 0.3) < 0.01 }) else { return }
            guard try await waitFor(player, "the end", { $0.hasEnded }, seconds: 20) else { return }
            await player.stop()
            finish("loaded, paused, played, sought, volume 0.3, ended", 0)
        } catch {
            finish("\(error)", 1)
        }
    }

    private static func waitFor(_ player: UPnPPlayer, _ what: String, _ test: (RemoteStatus) -> Bool,
                                seconds: Int = 5) async throws -> Bool {
        for _ in 0..<(seconds * 4) {
            let status = try await player.status()
            if test(status) {
                print("upnp check: \(what) (\(status.position) s)")
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        finish("never \(what)", 1)
        return false
    }

    private static func finish(_ what: String, _ code: Int32) {
        print("upnp check: \(code == 0 ? "ok" : "FAILED"), \(what)")
        result = code
        finder.stop()
        if let loop { g_main_loop_quit(loop) }
    }
}
