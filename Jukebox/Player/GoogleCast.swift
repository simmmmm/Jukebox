// Chromecasts on the iPhone and the iPad, through Google's own Cast SDK
// (ci/google-cast.sh fetches the pinned build from Google; docs/RELEASE.md).
// No cast button of Google's: Play On's list (SystemControls.swift) is the
// one place, and the SDK is set up only when that list first opens, so its
// local network prompt comes when the listener asks to look, not at launch.
// Its analytics logging is off; what it still collects is in its own
// privacy manifest (docs/STATS.md, The App Store).
//
// The player is PlayOn.swift's model: the Default Media Receiver plays one
// song, the queue gives it the next when it ends.

#if os(iOS) && canImport(GoogleCast)
import Foundation
import GoogleCast
import JukeboxKit

enum GoogleCast {
    /// Once, as Play On first opens.
    static func setUp() {
        guard !GCKCastContext.isSharedInstanceInitialized() else { return }
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        // The phone's volume buttons move the TV's while it plays there.
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        options.disableDiscoveryAutostart = true
        options.disableAnalyticsLogging = true
        GCKCastContext.setSharedInstanceWith(options)
    }
}

/// The receivers Google's SDK finds, while the list is open.
final class GoogleCastFinder: NSObject, PlayOnFinder, GCKDiscoveryManagerListener {
    private var found: (([PlayOnDevice]) -> Void)?

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        GoogleCast.setUp()
        self.found = found
        let manager = GCKCastContext.sharedInstance().discoveryManager
        manager.add(self)
        manager.startDiscovery()
        report()
    }

    func stop() {
        guard found != nil else { return }
        found = nil
        let manager = GCKCastContext.sharedInstance().discoveryManager
        manager.remove(self)
        manager.stopDiscovery()
    }

    func didUpdateDeviceList() {
        report()
    }

    private func report() {
        let manager = GCKCastContext.sharedInstance().discoveryManager
        let devices = (0..<manager.deviceCount).map { manager.device(at: $0) }.map { device in
            PlayOnDevice(id: device.deviceID, name: device.friendlyName ?? device.modelName ?? "Chromecast",
                         kind: .chromecast, address: device.deviceID)
        }
        found?(devices)
    }
}

/// One receiver, through a session of Google's SDK.
final class GoogleCastPlayer: NSObject, RemotePlayer, GCKSessionManagerListener {
    let device: PlayOnDevice
    let reportsItself = false
    let capacity = 1
    private var session: GCKCastSession?
    /// A load asked for before the session has started.
    private var waiting: (() -> Void)?
    private var gone = false

    init(device: PlayOnDevice) {
        self.device = device
        super.init()
        let context = GCKCastContext.sharedInstance()
        context.sessionManager.add(self)
        if let found = context.discoveryManager.device(withUniqueID: device.address) {
            context.sessionManager.startSession(with: found)
        } else {
            gone = true
        }
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        self.session = session
        waiting?()
        waiting = nil
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKCastSession,
                        withError error: Error) {
        gone = true
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKCastSession, withError error: Error?) {
        if session === self.session { gone = true }
    }

    private var client: GCKRemoteMediaClient? { session?.remoteMediaClient }

    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws {
        guard let entry = entries.first else { return }
        let send = { [weak self] in
            guard let self, let client = self.client else { return }
            let track = entry.track
            let metadata = GCKMediaMetadata(metadataType: .musicTrack)
            metadata.setString(track.name, forKey: kGCKMetadataKeyTitle)
            metadata.setString(track.artistLine, forKey: kGCKMetadataKeyArtist)
            if let album = track.albumName { metadata.setString(album, forKey: kGCKMetadataKeyAlbumTitle) }
            if let artwork = entry.artworkURL { metadata.addImage(GCKImage(url: artwork, width: 600, height: 600)) }
            let builder = GCKMediaInformationBuilder(contentURL: entry.stream.url)
            builder.streamType = .buffered
            builder.contentType = entry.stream.contentType
            builder.metadata = metadata
            let options = GCKMediaLoadOptions()
            options.playPosition = position
            options.autoplay = play
            client.loadMedia(builder.build(), with: options)
        }
        if client != nil { send() } else { waiting = send }
    }

    func append(_ entries: [RemoteEntry]) async throws {}
    func resume() async throws { client?.play() }
    func pause() async throws { client?.pause() }

    func seek(to position: TimeInterval) async throws {
        let options = GCKMediaSeekOptions()
        options.interval = position
        client?.seek(with: options)
    }

    func setVolume(_ level: Double) async throws {
        session?.setDeviceVolume(Float(level))
    }

    func stop() async {
        client?.stop()
        let manager = GCKCastContext.sharedInstance().sessionManager
        manager.remove(self)
        manager.endSession()
        gone = true
    }

    func status() async throws -> RemoteStatus {
        if gone { throw MusicServerError.transport("the cast session ended") }
        var status = RemoteStatus(volume: session.map { Double($0.currentDeviceVolume) })
        guard let client, let media = client.mediaStatus else { return status }
        status.index = 0
        status.position = client.approximateStreamPosition()
        switch media.playerState {
        case .playing: status.isPlaying = true
        case .buffering, .loading: status.isBuffering = true
        case .idle:
            if media.idleReason == .finished { status.hasEnded = true }
            if media.idleReason == .error { status.failed = true }
        default: break
        }
        return status
    }
}
#endif
