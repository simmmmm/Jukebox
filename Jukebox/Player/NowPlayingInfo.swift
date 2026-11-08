// What the lock screen, Control Center, the Dynamic Island, CarPlay and a
// watch show: the track, its cover, where it is and where it is in the
// queue. Elapsed time is sent at changes only (start, pause, seek); the
// system runs the clock on from the rate in between.

import Foundation
import JukeboxKit
import MediaPlayer
import UIKit

final class NowPlayingInfo {
    private var info: [String: Any] = [:]
    private var entryID: UUID?
    /// The cover being shown, and its image once loaded: kept across the
    /// updates of one track, and across tracks of one album.
    private var artwork: Artwork?
    private var artworkImage: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    /// A new track, or the same one with its place in the queue changed.
    func show(_ entry: QueueEntry, index: Int, count: Int, elapsed: TimeInterval, duration: TimeInterval,
              rate: Double, client: JellyfinClient?) {
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
            loadArtwork(client: client)
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
        artworkTask?.cancel()
        artworkTask = nil
        info = [:]
        entryID = nil
        artwork = nil
        artworkImage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func publish() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The cover at 600 pixels, from the app's own image cache when it is
    /// there (it usually is: the screen that started the music drew it).
    private func loadArtwork(client: JellyfinClient?) {
        guard let artwork, let client else { return }
        let url = client.imageURL(artwork, maxPixelSize: 600)
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
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
