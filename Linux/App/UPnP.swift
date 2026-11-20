// A Sonos, and any UPnP (DLNA) renderer, found on Linux: "hij vind bijv
// ook mijn sonos niet" (the photographer, 19 November 2026). What a speaker
// is, and playing on it, every client shares (Jukebox/Player/UPnPPlay.swift);
// this is Linux's way of finding them.
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
/// open (UPnPRooms makes the rows). JUKEBOX_UPNP_DEVICE (a
/// description's URL, on this computer) lists that one instead, for a test
/// against a fake renderer (dev/fake-upnp-renderer.py): then nothing on
/// the network is asked.
final class UPnPFinder: PlayOnFinder {
    private var avahi: OpaquePointer?
    private var ssdp: OpaquePointer?
    private var box: Unmanaged<UPnPFinder>?
    private var searching: Task<Void, Never>?
    private let rooms = UPnPRooms()

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        stop()
        rooms.start(found)
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
        searching?.cancel()
        searching = nil
        if let avahi { jb_avahi_stop(avahi) }
        avahi = nil
        if let ssdp { jb_ssdp_close(ssdp) }
        ssdp = nil
        // Neither calls anything once stopped (cast.c, ssdp.c).
        box?.release()
        box = nil
        rooms.stop()
    }

    private func consider(_ location: URL) { rooms.consider(location) }

    /// Its control addresses, for UPnPCheck.
    static func renderer(for device: PlayOnDevice) -> UPnPRenderer? { UPnPRooms.renderer(for: device) }

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
