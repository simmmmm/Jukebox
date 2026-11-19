// A Sonos, and any UPnP (DLNA) renderer, in Play On on Linux: "hij vind
// bijv ook mijn sonos niet" (the photographer, 19 November 2026). The Mac,
// the iPad and the iPhone reach a Sonos by AirPlay, the system's own list;
// Linux has no AirPlay, so it finds the speaker and speaks UPnP AV to it
// itself (JukeboxKit's UPnP.swift), as it speaks castv2 to a Chromecast.
//
// Found two ways at once: Avahi's mDNS (`_sonos._tcp`, as the Chromecasts
// are found) and SSDP (ssdp.c), which also finds other renderers. A host
// firewall drops SSDP's answers (unicast replies to a multicast question
// are nothing it tracks; the photographer's ufw did, 19 November 2026), so
// a Sonos is found by mDNS there all the same.

import CGlue
import Foundation
import JukeboxKit

/// The Sonos rooms and the renderers on the network, while the list is
/// open. One row a Sonos group (rooms playing together), played through its
/// coordinator; a bonded surround or Sub is no row. JUKEBOX_UPNP_DEVICE (a
/// description's URL, on this computer) lists that one instead, for a test
/// against a fake renderer (dev/fake-upnp-renderer.py): then nothing on
/// the network is asked.
final class UPnPFinder: PlayOnFinder {
    private var avahi: OpaquePointer?
    private var ssdp: OpaquePointer?
    private var box: Unmanaged<UPnPFinder>?
    private var searching: Task<Void, Never>?
    private var found: (([PlayOnDevice]) -> Void)?
    /// Each start's own: an answer to an earlier look is dropped.
    private var generation = 0
    private var asked: Set<URL> = []
    private var descriptions: [URL: UPnPDescription] = [:]
    private var sonosAnswered = false
    private var sonos: [PlayOnDevice] = []
    private var renderers: [String: PlayOnDevice] = [:]

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        stop()
        self.found = found
        if let test = Self.testLocation {
            consider(test)
            return
        }
        let box = Unmanaged.passRetained(self)
        self.box = box
        avahi = jb_avahi_browse("_sonos._tcp", { _, _, _, host, _, removed, data in
            guard let data, removed == 0, let host else { return }
            let finder = Unmanaged<UPnPFinder>.fromOpaque(data).takeUnretainedValue()
            // A Sonos answers UPnP on 1400 in plain http, whatever port its
            // mDNS names (1443, its own https API).
            let name = String(cString: host)
            guard let location = URL(string: "http://\(name.contains(":") ? "[\(name)]" : name):1400/xml/device_description.xml")
            else { return }
            MainActor.assumeIsolated { finder.consider(location) }
        }, box.toOpaque())
        ssdp = jb_ssdp_open({ text, data in
            guard let text, let data, let answer = SSDP.parse(String(cString: text)) else { return }
            let finder = Unmanaged<UPnPFinder>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { finder.consider(answer.location) }
        }, box.toOpaque())
        // Asked again every 5 s while the list is open: UDP may lose a
        // question, and a speaker switched on later answers the next.
        searching = Task { [weak self] in
            while !Task.isCancelled {
                guard let ssdp = self?.ssdp else { return }
                jb_ssdp_search(ssdp, SSDP.search(SSDP.zonePlayer))
                jb_ssdp_search(ssdp, SSDP.search(SSDP.mediaRenderer))
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        generation += 1
        searching?.cancel()
        searching = nil
        if let avahi { jb_avahi_stop(avahi) }
        avahi = nil
        if let ssdp { jb_ssdp_close(ssdp) }
        ssdp = nil
        // Neither calls anything once stopped (cast.c, ssdp.c).
        box?.release()
        box = nil
        found = nil
        asked = []
        descriptions = [:]
        sonosAnswered = false
        sonos = []
        renderers = [:]
    }

    /// A description to read, once a look.
    private func consider(_ location: URL) {
        guard found != nil, asked.insert(location).inserted else { return }
        let generation = generation
        Task {
            guard let description = try? await UPnPRenderer.description(at: location),
                  generation == self.generation else { return }
            descriptions[location] = description
            if description.isSonos {
                await askSonos(location, generation)
            } else if let control = description.avTransport {
                renderers[description.udn] = PlayOnDevice(
                    id: "upnp-" + description.udn, name: description.name, kind: .upnp,
                    address: Self.address(control, description.renderingControl),
                    detail: description.modelName ?? description.manufacturer)
                tell()
            }
        }
    }

    /// Every Sonos knows all the rooms: the first that answers says them.
    private func askSonos(_ location: URL, _ generation: Int) async {
        guard !sonosAnswered, let groups = try? await UPnPRenderer.sonosGroups(at: location),
              generation == self.generation, !sonosAnswered else { return }
        sonosAnswered = true
        var rows: [PlayOnDevice] = []
        for group in groups {
            // The coordinator's own description says where it is played on.
            var description = descriptions[group.location]
            if description == nil { description = try? await UPnPRenderer.description(at: group.location) }
            guard generation == self.generation else { return }
            guard let description, let control = description.avTransport else { continue }
            descriptions[group.location] = description
            rows.append(PlayOnDevice(id: "sonos-" + group.coordinator, name: group.name, kind: .upnp,
                                     address: Self.address(control, description.renderingControl), detail: "Sonos"))
        }
        sonos = rows
        tell()
    }

    private func tell() {
        let others = renderers.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        found?(sonos + others)
    }

    /// The two control addresses in the device's one string.
    static func address(_ transport: URL, _ rendering: URL?) -> String {
        [transport.absoluteString, rendering?.absoluteString].compactMap { $0 }.joined(separator: " ")
    }

    static func renderer(for device: PlayOnDevice) -> UPnPRenderer? {
        let parts = device.address.split(separator: " ").map(String.init)
        guard let transport = parts.first.flatMap(URL.init(string:)) else { return nil }
        return UPnPRenderer(avTransport: transport, renderingControl: parts.dropFirst().first.flatMap(URL.init(string:)))
    }

    /// JUKEBOX_UPNP_DEVICE: a fake renderer's description, on this computer
    /// only, so a test never plays on a real speaker in the house.
    static var testLocation: URL? {
        guard let value = ProcessInfo.processInfo.environment["JUKEBOX_UPNP_DEVICE"],
              let url = URL(string: value), let host = url.host else { return nil }
        guard host == "127.0.0.1" || host == "localhost" || host == "::1" else {
            print("JUKEBOX_UPNP_DEVICE: only a renderer on this computer (127.0.0.1)")
            return nil
        }
        return url
    }
}

/// A renderer playing one song at a time, as the Chromecast does: the queue
/// gives it the next when one ends, so every rule and report stays the
/// queue's.
// ponytail: a moment's silence between songs (SetNextAVTransportURI would
// hand over the next in time); a group's volume is its coordinator's
// (Sonos's GroupRenderingControl sets the whole group's).
final class UPnPPlayer: RemotePlayer {
    let device: PlayOnDevice
    let reportsItself = false
    let capacity = 1
    private let renderer: UPnPRenderer
    private var wantsToPlay = false
    /// It played the song it holds: STOPPED is its end, not its start.
    private var sawPlaying = false
    private var loadFailed = false
    private var loadedAt = Date.distantPast
    /// Counted at every load, and set while one is under way: what the
    /// speaker says then may be of the song before (still PLAYING, then
    /// STOPPED by the new address), which would end the new one unheard.
    private var loads = 0
    private var loading: TimeInterval?

    init?(device: PlayOnDevice) {
        guard let renderer = UPnPFinder.renderer(for: device) else { return nil }
        self.device = device
        self.renderer = renderer
    }

    func load(_ entries: [RemoteEntry], at position: TimeInterval, play: Bool) async throws {
        guard let entry = entries.first else { return }
        let track = entry.track
        wantsToPlay = play
        sawPlaying = false
        loadFailed = false
        loads += 1
        loading = position
        defer {
            loading = nil
            loadedAt = Date()
        }
        let metadata = DIDLLite.metadata(url: entry.stream.url, contentType: entry.stream.contentType, title: track.name,
                                         artist: track.artistLine, album: track.albumName, artworkURL: entry.artworkURL,
                                         duration: track.duration > 0 ? track.duration : nil)
        do {
            try await renderer.load(entry.stream.url, metadata: metadata)
            if play { try await renderer.play() }
        } catch {
            loadFailed = true
            throw error
        }
        // Not every renderer seeks before it plays; where it will not, the
        // song starts from its start.
        if position > 1 { try? await renderer.seek(to: position) }
    }

    func append(_ entries: [RemoteEntry]) async throws {}

    func resume() async throws {
        wantsToPlay = true
        try await renderer.play()
    }

    func pause() async throws {
        wantsToPlay = false
        try await renderer.pause()
    }

    func seek(to position: TimeInterval) async throws { try await renderer.seek(to: position) }
    func setVolume(_ level: Double) async throws { try await renderer.setVolume(Int((level * 100).rounded())) }

    func stop() async {
        wantsToPlay = false
        try? await renderer.stop()
    }

    func status() async throws -> RemoteStatus {
        let load = loads
        let state = try await renderer.state()
        let position = try await renderer.position()
        let volume = try? await renderer.volume()
        var status = RemoteStatus(volume: volume.map { Double($0) / 100 })
        // A load under way, or one begun while it was asked: nothing it said
        // is of the song it is given.
        if let starting = loading ?? (load == loads ? nil : 0) {
            status.index = 0
            status.position = starting
            status.isBuffering = wantsToPlay
            return status
        }
        if loadFailed {
            status.failed = true
            return status
        }
        status.index = 0
        status.position = position.elapsed
        switch state {
        case .playing:
            status.isPlaying = true
            sawPlaying = true
        case .transitioning:
            status.isBuffering = true
        case .stopped, .noMedia:
            if wantsToPlay, sawPlaying {
                // Once: the queue loads the next, or stops.
                status.hasEnded = true
                sawPlaying = false
                wantsToPlay = false
            } else if wantsToPlay, Date().timeIntervalSince(loadedAt) > 20 {
                // Asked to play and never did: it could not fetch the song.
                status.failed = true
                wantsToPlay = false
            }
        case .paused, nil:
            break
        }
        return status
    }
}
