// GNOME's own media controls — the clock's menu, the lock screen, the
// keyboard's Play and Next — through MPRIS (Linux/CGlue/mpris.c): what the
// lock screen and the remote commands are on the iPhone.

import CAdw
import CGlue
import Foundation
import JukeboxKit

enum Mpris {
    private static var lastElapsed: TimeInterval = 0
    /// The cover being fetched for the controls, so it is asked for once.
    private static var fetching: URL?

    static func start() {
        jb_mpris_start({ command, microseconds in
            MainActor.assumeIsolated {
                let player = app.player
                let seconds = Double(microseconds) / 1_000_000
                switch command {
                case JB_MPRIS_PLAY_PAUSE, JB_MPRIS_PLAY:
                    // Nothing loaded: the Play key goes on where this
                    // computer, or another device, left off, else plays
                    // Your Station (HandoffStore.playWithNothingLoaded).
                    if !player.hasTrack {
                        app.handoff.playWithNothingLoaded(from: "play_key")
                    } else if command == JB_MPRIS_PLAY {
                        player.resume()
                    } else {
                        player.togglePlayPause()
                    }
                case JB_MPRIS_PAUSE, JB_MPRIS_STOP: player.pause()
                case JB_MPRIS_NEXT: player.next()
                case JB_MPRIS_PREVIOUS: player.previous()
                case JB_MPRIS_SEEK_BY: player.seek(to: player.elapsed + seconds)
                case JB_MPRIS_SEEK_TO: player.seek(to: seconds)
                case JB_MPRIS_RAISE: gtk_window_present(ptr(MainWindow.window))
                // Quit is quit, also while the window is hidden and the
                // music plays on (MainWindow, hide on close).
                case JB_MPRIS_QUIT: MainWindow.quit()
                default: break
                }
            }
        }, { volume in
            // The slider in the shell's media controls, or an extension's:
            // the same volume as the bar's slider (PlayerBar.levelScale).
            MainActor.assumeIsolated {
                if app.player.playsOn != nil { app.player.setRemoteVolume(volume) } else { app.player.volume = volume }
            }
        })
        // The song and whether it plays, when either changes.
        observe(MainWindow.window) { publish() }
        // The volume, both ways with the bar's slider.
        observe(MainWindow.window) {
            let player = app.player
            jb_mpris_set_volume(player.playsOn != nil ? player.remoteVolume ?? 1 : player.volume)
        }
        // The clock: kept for whoever asks; told as a jump only when it is
        // one (a seek), as MPRIS wants.
        observe(MainWindow.window) {
            let elapsed = app.player.elapsed
            let jumped = abs(elapsed - lastElapsed) > 2
            lastElapsed = elapsed
            jb_mpris_set_position(gint64(elapsed * 1_000_000), jumped ? 1 : 0)
        }
    }

    private static func publish() {
        let player = app.player
        guard let entry = player.current else {
            jb_mpris_update("Stopped", nil, nil, nil, nil, nil, 0, 0, 0)
            return
        }
        let track = entry.track
        let cover = track.artwork.flatMap { app.server?.artworkURL($0, maxPixelSize: 440) }
        // The shell loads a cover from a file, not from the server (whose
        // address wants the session's token): the cover kept on disk. Not
        // there yet, it is fetched, and told again once it is; until then
        // the shell shows the app's icon. Once per cover: one that fails
        // is not asked for again and again.
        let file = cover.flatMap(ArtworkLoader.shared.file(for:))
        if let cover, file == nil, fetching != cover {
            fetching = cover
            Task { @MainActor in
                guard await ArtworkLoader.shared.texture(for: cover) != nil,
                      app.player.current?.id == entry.id else { return }
                publish()
            }
        }
        // D-Bus object paths take letters, digits and "_" only.
        let id = "/com/tijmen/Jukebox/track/" + entry.id.uuidString.replacingOccurrences(of: "-", with: "_")
        jb_mpris_update(player.isPlaying ? "Playing" : "Paused", id, track.name, track.artistLine,
                        track.albumName ?? "", file?.absoluteString ?? "",
                        gint64(player.duration * 1_000_000), player.upNext.isEmpty ? 0 : 1, 1)
    }
}
