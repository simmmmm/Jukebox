// What the lock screen, Control Center, the Dynamic Island, CarPlay and a
// watch show: the track, its cover, where it is and where it is in the
// queue. Elapsed time is sent at changes only (start, pause, seek); the
// system runs the clock on from the rate in between.

import Foundation
import JukeboxKit
import MediaPlayer

final class NowPlayingInfo {
    private var info: [String: Any] = [:]
    private var entryID: UUID?
    /// The cover being shown, and its image once loaded: kept across the
    /// updates of one track, and across tracks of one album.
    private var artwork: Artwork?
    private var artworkImage: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    /// Off in the Mac's snapshots (JukeboxSnapshots), which run on the
    /// photographer's own laptop for every push: a second Jukebox telling
    /// the system it is the one playing took the Play key from the real
    /// app, and when it quit the key had no one left and opened Music
    /// ("jukebox stond gewoon open en play opende apple music", 21 November 2026).
    var isOn = true

    /// A new track, or the same one with its place in the queue changed.
    func show(_ entry: QueueEntry, index: Int, count: Int, elapsed: TimeInterval, duration: TimeInterval,
              rate: Double, server: (any MusicServer)?) {
        let track = entry.track
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = track.name
        info[MPMediaItemPropertyArtist] = track.artistLine
        if let album = track.albumName {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        entryID = entry.id

        if track.artwork != artwork {
            artwork = track.artwork
            artworkImage = nil
            artworkTask?.cancel()
            artworkTask = nil
            loadArtwork(server: server)
        }
        if let artworkImage {
            info[MPMediaItemPropertyArtwork] = artworkImage
        }
        self.info = info
        publish()
    }

    /// Playing, paused, sought, or the length became known.
    func updatePlayback(elapsed: TimeInterval, duration: TimeInterval, rate: Double) {
        guard entryID != nil else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        publish()
    }

    func clear() {
        guard isOn else { return }
        artworkTask?.cancel()
        artworkTask = nil
        info = [:]
        entryID = nil
        artwork = nil
        artworkImage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(macOS)
        // Paused, not stopped: the Mac's Play key with nothing loaded starts
        // the music to go on with or Your Station (RemoteCommands), so
        // Jukebox stays the player the key goes to.
        MPNowPlayingInfoCenter.default().playbackState = .paused
        #endif
    }

    #if os(macOS)
    /// Jukebox the Mac's Now Playing app again, when it comes to the front.
    /// macOS sends the Play key to the app that last told it so; one that
    /// quit (another player, or the snapshots) leaves no one, and the key
    /// opens Music. Told afresh, not the same again, which the system skips.
    /// While it plays it is the one already.
    func claim() {
        guard isOn, (info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0) == 0 else { return }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        if entryID == nil {
            center.playbackState = .paused
        } else {
            publish()
        }
    }
    #endif

    private func publish() {
        guard isOn else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        // The Mac's Control Centre and media keys go by the state the app
        // says it is in; the iPhone takes it from the audio session.
        let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
        #endif
    }

    /// The cover at 600 pixels, from the app's own image cache when it is
    /// there (it usually is: the screen that started the music drew it).
    private func loadArtwork(server: (any MusicServer)?) {
        guard let artwork, let server else { return }
        let url = server.artworkURL(artwork, maxPixelSize: 600)
        if let image = ImagePipeline.shared.cached(url) {
            artworkImage = Self.makeArtwork(image)
            return
        }
        artworkTask = Task { [weak self] in
            guard let image = await ImagePipeline.shared.image(for: url), !Task.isCancelled,
                  let self, self.artwork == artwork, self.entryID != nil else { return }
            let made = Self.makeArtwork(image)
            self.artworkImage = made
            self.info[MPMediaItemPropertyArtwork] = made
            self.publish()
        }
    }

    /// Made outside the main actor: the system asks for the image on its own
    /// thread, so the handler holds the image itself, not this object.
    nonisolated private static func makeArtwork(_ image: PlatformImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
