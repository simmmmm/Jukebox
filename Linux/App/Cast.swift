// Chromecasts on Linux: the socket (TLS with GIO) and finding them (Avahi),
// in C in CGlue/cast.c. Google has no Cast SDK for Linux; JukeboxKit's
// CastSession speaks the protocol over this socket, as on the Mac.

import CGlue
import Foundation

/// A Chromecast's TLS connection, port 8009 as Avahi says. Asynchronous on
/// GLib's main loop, so `received` comes on the main actor.
final class GioCastSocket: CastSocket {
    var received: ((Data?) -> Void)?
    private var cast: OpaquePointer?
    /// Unmanaged's box for C, released at close.
    private var box: Unmanaged<GioCastSocket>?

    init(host: String, port: UInt16) {
        // Held by C until close: the callbacks find it there.
        let box = Unmanaged.passRetained(self)
        self.box = box
        cast = jb_cast_connect(host, port, { bytes, length, data in
            guard let data else { return }
            let socket = Unmanaged<GioCastSocket>.fromOpaque(data).takeUnretainedValue()
            let chunk = bytes.map { Data(bytes: $0, count: Int(length)) }
            MainActor.assumeIsolated {
                socket.received?(chunk)
                if chunk == nil { socket.close() }
            }
        }, box.toOpaque())
    }

    func send(_ data: Data) {
        guard let cast else { return }
        data.withUnsafeBytes { raw in
            jb_cast_send(cast, raw.bindMemory(to: UInt8.self).baseAddress, gsize(raw.count))
        }
    }

    func close() {
        if let cast { jb_cast_close(cast) }
        cast = nil
        received = nil
        box?.release()
        box = nil
    }
}

/// The Chromecasts Avahi sees, by their mDNS name. JUKEBOX_CAST_DEVICE
/// ("Name@host:port") lists one more at once, for a test against a fake
/// receiver (as JUKEBOX_AUDIO_SINK is for the sound): then Avahi is not
/// asked at all.
final class AvahiCastFinder: PlayOnFinder {
    private var avahi: OpaquePointer?
    private var box: Unmanaged<AvahiCastFinder>?
    private var devices: [String: PlayOnDevice] = [:]
    private var found: (([PlayOnDevice]) -> Void)?

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        stop()
        self.found = found
        if let device = Self.testDevice {
            found([device])
            return
        }
        let box = Unmanaged.passRetained(self)
        self.box = box
        avahi = jb_avahi_browse({ service, id, name, host, port, removed, data in
            guard let data, let service else { return }
            let finder = Unmanaged<AvahiCastFinder>.fromOpaque(data).takeUnretainedValue()
            let key = String(cString: service)
            let device = removed == 0 ? PlayOnDevice(id: id.map { String(cString: $0) } ?? key,
                                                     name: name.map { String(cString: $0) } ?? key,
                                                     kind: .chromecast,
                                                     address: AvahiCastFinder.address(host.map { String(cString: $0) } ?? "", port))
                : nil
            MainActor.assumeIsolated { finder.change(key, to: device) }
        }, box.toOpaque())
    }

    func stop() {
        if let avahi { jb_avahi_stop(avahi) }
        avahi = nil
        // ponytail: C may still hold the pointer for a late reply (cast.c's
        // jb_avahi_stop), and it calls nothing once stopped; the box is let
        // go here all the same, so a late reply never touches it.
        box?.release()
        box = nil
        found = nil
        devices = [:]
    }

    // ponytail: Avahi tells one ItemRemove per network interface; the first
    // takes the device away though another interface may still see it.
    private func change(_ key: String, to device: PlayOnDevice?) {
        guard let found else { return }
        if devices[key] == device { return }
        devices[key] = device
        found(devices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    /// An IPv6 host goes in brackets, so "host:port" splits at the last colon.
    private static func address(_ host: String, _ port: UInt16) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    /// "Name@host:port" from JUKEBOX_CAST_DEVICE.
    static var testDevice: PlayOnDevice? {
        guard let value = ProcessInfo.processInfo.environment["JUKEBOX_CAST_DEVICE"],
              let at = value.lastIndex(of: "@") else { return nil }
        let address = String(value[value.index(after: at)...])
        return PlayOnDevice(id: "test-" + address, name: String(value[..<at]), kind: .chromecast, address: address)
    }

    /// "host:port" or "[v6]:port" as the socket wants them.
    static func split(_ address: String) -> (host: String, port: UInt16)? {
        guard let colon = address.lastIndex(of: ":"), let port = UInt16(address[address.index(after: colon)...])
        else { return nil }
        var host = String(address[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return (host, port)
    }
}

// TEMP: PlayOn.swift's, removed at merge
struct PlayOnDevice: Identifiable, Hashable {
    enum Kind: String, Hashable { case chromecast, jellyfin, subsonicJukebox }
    let id: String
    let name: String
    let kind: Kind
    /// A Chromecast's "host:port"; a Jellyfin session's id; the server's id for its jukebox.
    let address: String
}

/// One source of devices (main actor, the app's default).
protocol PlayOnFinder: AnyObject {
    /// Looks until `stop`, telling every change of what it found.
    func start(_ found: @escaping ([PlayOnDevice]) -> Void)
    func stop()
}

/// Bytes to and from a Chromecast; callbacks on the main actor.
protocol CastSocket: AnyObject {
    /// The bytes as they come; nil once the connection closed or failed.
    var received: ((Data?) -> Void)? { get set }
    func send(_ data: Data)
    func close()
}
