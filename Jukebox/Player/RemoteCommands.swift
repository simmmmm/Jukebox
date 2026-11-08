// The lock screen's, Control Center's, the headphones' and the car's
// buttons. Thumbs up and down ("More Like This", "Less Like This") are on
// only while a station plays: they are the radio's feedback, and mean
// nothing to an album. Each handler hops to the main actor rather than
// assuming it is there, and answers at once.

import Foundation
import JukeboxKit
import MediaPlayer

final class RemoteCommands {
    private var targets: [Any] = []

    init(player: AudioPlayer) {
        let center = MPRemoteCommandCenter.shared()

        targets.append(center.playCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.resume() }
            return .success
        })
        targets.append(center.pauseCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.pause() }
            return .success
        })
        targets.append(center.togglePlayPauseCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.togglePlayPause() }
            return .success
        })
        targets.append(center.nextTrackCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.next() }
            return .success
        })
        targets.append(center.previousTrackCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.previous() }
            return .success
        })
        targets.append(center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in player?.seek(to: position) }
            return .success
        })

        center.likeCommand.localizedTitle = String(localized: "More Like This")
        center.likeCommand.localizedShortTitle = String(localized: "More Like This")
        targets.append(center.likeCommand.addTarget { [weak player] _ in
            Task { @MainActor in
                guard let player, let track = player.currentTrack else { return }
                player.radio?.like(track)
            }
            return .success
        })
        center.dislikeCommand.localizedTitle = String(localized: "Less Like This")
        center.dislikeCommand.localizedShortTitle = String(localized: "Less Like This")
        targets.append(center.dislikeCommand.addTarget { [weak player] _ in
            Task { @MainActor in
                guard let player, let track = player.currentTrack else { return }
                player.radio?.dislike(track)
            }
            return .success
        })

        // Next and previous, not 15-second jumps: this is music.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.bookmarkCommand.isEnabled = false
        update(hasTrack: false, stationPlays: false, liked: false, disliked: false)
    }

    func update(hasTrack: Bool, stationPlays: Bool, liked: Bool, disliked: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = hasTrack
        center.pauseCommand.isEnabled = hasTrack
        center.togglePlayPauseCommand.isEnabled = hasTrack
        center.nextTrackCommand.isEnabled = hasTrack
        center.previousTrackCommand.isEnabled = hasTrack
        center.changePlaybackPositionCommand.isEnabled = hasTrack
        center.likeCommand.isEnabled = stationPlays
        center.dislikeCommand.isEnabled = stationPlays
        center.likeCommand.isActive = stationPlays && liked
        center.dislikeCommand.isActive = stationPlays && disliked
    }
}
