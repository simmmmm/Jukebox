// UPnP AV, the speakers that are no Chromecast: a Sonos above all ("hij
// vind bijv ook mijn sonos niet", the photographer, 19 November 2026), and
// any DLNA MediaRenderer that comes with the same few calls. Apple's
// clients reach a Sonos by AirPlay; Linux has no AirPlay, so it speaks to
// the speaker itself, as it speaks castv2 to a Chromecast.
//
// The speaker is found by SSDP (an M-SEARCH on 239.255.255.250:1900) or,
// for a Sonos, by mDNS (`_sonos._tcp`, through Avahi): a host firewall that
// drops unicast answers to a multicast question lets mDNS through (measured
// on the photographer's machine, 19 November 2026: SSDP heard nothing, Avahi
// listed "Living Room"). Its description says its name and where its
// AVTransport and RenderingControl answer; it is told a plain URL with
// DIDL-Lite metadata (SetAVTransportURI), then Play, Pause, Seek, and asked
// where it is (GetPositionInfo, GetTransportInfo) once a second.
//
// No sockets here but HTTP: the platform sends the M-SEARCH and hears the
// answers (Linux/CGlue/ssdp.c). Foundation only, tested on Linux (UPnPTests).
// No XMLParser either (FoundationXML would bring libxml2 into the Linux
// build): what a speaker says is a few flat elements, read by `UPnPXML`.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - SSDP

public enum SSDP {
    public static let host = "239.255.255.250"
    public static let port: UInt16 = 1900
    /// A Sonos speaker (its root device).
    public static let zonePlayer = "urn:schemas-upnp-org:device:ZonePlayer:1"
    /// Any DLNA renderer (a Sonos answers this too, for its embedded one).
    public static let mediaRenderer = "urn:schemas-upnp-org:device:MediaRenderer:1"

    /// The question, for `target`; devices answer within `wait` seconds.
    public static func search(_ target: String, wait: Int = 2) -> String {
        "M-SEARCH * HTTP/1.1\r\nHOST: \(host):\(port)\r\nMAN: \"ssdp:discover\"\r\nMX: \(wait)\r\nST: \(target)\r\n\r\n"
    }

    public struct Answer: Sendable, Hashable {
        /// Its description.
        public var location: URL
        public var target: String
        public var usn: String
    }

    /// An answer to an M-SEARCH (or a NOTIFY alive): nil for anything else.
    public static func parse(_ text: String) -> Answer? {
        // By scalars: "\r\n" is one Character to Swift.
        let lines = text.unicodeScalars.split { $0 == "\n" || $0 == "\r" }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first?.uppercased(),
              first.hasPrefix("HTTP/1.1 200") || first.hasPrefix("NOTIFY ") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if first.hasPrefix("NOTIFY "), headers["NTS"]?.lowercased() != "ssdp:alive" { return nil }
        guard let location = headers["LOCATION"].flatMap(URL.init(string:)),
              location.scheme == "http" || location.scheme == "https" else { return nil }
        return Answer(location: location, target: headers["ST"] ?? headers["NT"] ?? "", usn: headers["USN"] ?? "")
    }

    /// An answer to one of our own M-SEARCHes, as a finder takes it: a 200
    /// for a target that was asked for, whose description is on the address
    /// the answer came from (`sender`, as the socket says it), in the house.
    /// Anything else on the socket is nil: an unasked answer would have
    /// Jukebox fetch an address of someone else's choosing.
    public static func answer(_ text: String, searched targets: [String], from sender: String) -> Answer? {
        guard text.uppercased().hasPrefix("HTTP/1.1 200"), let answer = parse(text),
              targets.contains(answer.target), UPnPAddress.isLocal(answer.location),
              let host = answer.location.host, UPnPAddress.bare(host) == UPnPAddress.bare(sender) else { return nil }
        return answer
    }
}

// MARK: - Where a speaker may be

/// A speaker is in the house: a description, its URLBase and its control
/// addresses are only ever on a private, link-local or loopback address
/// (loopback for the fake renderer of the checks), never a name or the
/// internet.
enum UPnPAddress {
    /// The host as compared: lowercased, without IPv6's brackets or zone.
    static func bare(_ host: String) -> String {
        var name = host.lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        if let zone = name.firstIndex(of: "%") { name = String(name[..<zone]) }
        return name
    }

    static func isLocal(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host else { return false }
        let name = bare(host)
        if name == "localhost" || name == "::1" { return true }
        if name.contains(":") {
            // fe80::/10 (link-local) and fc00::/7 (unique local), by the
            // first group written out in full.
            guard let first = name.split(separator: ":", omittingEmptySubsequences: false).first,
                  first.count == 4 else { return false }
            return ["fe8", "fe9", "fea", "feb", "fc", "fd"].contains { first.hasPrefix($0) }
        }
        // Four plain decimals; anything else (a name, 0x…, one big number)
        // is not taken.
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { part -> Int? in
            guard (1...3).contains(part.count), part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part).flatMap { $0 <= 255 ? $0 : nil }
        }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    static func sameHost(_ one: URL, _ other: URL) -> Bool {
        guard let a = one.host, let b = other.host else { return false }
        return bare(a) == bare(b)
    }
}

// MARK: - Reading what a speaker says

/// Just enough XML for UPnP: elements by their local name (any prefix), the
/// text inside, a start tag's attributes, the five entities.
enum UPnPXML {
    struct Tag {
        var name: String
        var attributes: [String: String]
        var isClosing: Bool
        var isSelfClosing: Bool
        /// Where the tag is, `<` to `>`.
        var range: Range<String.Index>
    }

    /// Every tag in order; comments, declarations and CDATA are skipped.
    static func tags(in xml: String) -> [Tag] {
        var found: [Tag] = []
        var at = xml.startIndex
        while let open = xml[at...].firstIndex(of: "<") {
            let rest = xml[xml.index(after: open)...]
            if rest.hasPrefix("!--") {
                guard let end = xml.range(of: "-->", range: open..<xml.endIndex) else { break }
                at = end.upperBound
                continue
            }
            guard let close = xml[open...].firstIndex(of: ">") else { break }
            at = xml.index(after: close)
            let inside = xml[xml.index(after: open)..<close]
            if inside.hasPrefix("?") || inside.hasPrefix("!") { continue }
            let isClosing = inside.hasPrefix("/")
            let isSelfClosing = inside.hasSuffix("/")
            var body = Substring(inside)
            if isClosing { body = body.dropFirst() }
            if isSelfClosing { body = body.dropLast() }
            let nameEnd = body.firstIndex { $0.isWhitespace } ?? body.endIndex
            let qualified = body[..<nameEnd]
            let name = qualified.split(separator: ":").last.map(String.init) ?? ""
            found.append(Tag(name: name, attributes: attributes(body[nameEnd...]), isClosing: isClosing,
                             isSelfClosing: isSelfClosing, range: open..<at))
        }
        return found
    }

    private static func attributes(_ text: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var rest = text
        while let equals = rest.firstIndex(of: "=") {
            let name = rest[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var after = rest[rest.index(after: equals)...].drop { $0.isWhitespace }
            guard let quote = after.first, quote == "\"" || quote == "'" else { break }
            after = after.dropFirst()
            guard let end = after.firstIndex(of: quote) else { break }
            let local = name.split(separator: ":").last.map(String.init) ?? name
            result[local] = unescape(String(after[..<end]))
            rest = after[after.index(after: end)...]
        }
        return result
    }

    /// The raw inside of every element called `name`, outermost first.
    static func elements(_ name: String, in xml: String) -> [Substring] {
        let all = tags(in: xml)
        var found: [Substring] = []
        var index = 0
        while index < all.count {
            let tag = all[index]
            guard tag.name == name, !tag.isClosing else {
                index += 1
                continue
            }
            if tag.isSelfClosing {
                found.append(xml[tag.range.upperBound..<tag.range.upperBound])
                index += 1
                continue
            }
            var depth = 1
            var end = index + 1
            while end < all.count {
                let other = all[end]
                if other.name == name, !other.isSelfClosing { depth += other.isClosing ? -1 : 1 }
                if depth == 0 { break }
                end += 1
            }
            guard end < all.count else { break }
            found.append(xml[tag.range.upperBound..<all[end].range.lowerBound])
            index = end + 1
        }
        return found
    }

    /// The first `name`'s text, its entities read.
    static func text(_ name: String, in xml: some StringProtocol) -> String? {
        elements(name, in: String(xml)).first.map { unescape(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Each child element's name and text, one level down.
    static func children(of xml: some StringProtocol) -> [(name: String, text: String)] {
        let xml = String(xml)
        let all = tags(in: xml)
        var result: [(String, String)] = []
        var depth = 0
        var opened: Tag?
        for tag in all {
            if tag.isSelfClosing {
                if depth == 0 { result.append((tag.name, "")) }
                continue
            }
            if tag.isClosing {
                depth -= 1
                if depth == 0, let start = opened {
                    result.append((start.name, unescape(String(xml[start.range.upperBound..<tag.range.lowerBound]))))
                    opened = nil
                }
            } else {
                if depth == 0 { opened = tag }
                depth += 1
            }
        }
        return result
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(character)
            }
        }
        return out
    }

    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";"), rest.distance(from: amp, to: semi) <= 10 else {
                out += "&"
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let entity = rest[rest.index(after: amp)..<semi]
            switch entity {
            case "amp": out += "&"
            case "lt": out += "<"
            case "gt": out += ">"
            case "quot": out += "\""
            case "apos": out += "'"
            default:
                let number = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16)
                    : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
                if let number, let scalar = Unicode.Scalar(number) { out.unicodeScalars.append(scalar) } else { out += "&\(entity);" }
            }
            rest = rest[rest.index(after: semi)...]
        }
        return out + rest
    }
}

// MARK: - A device's description

public struct UPnPDescription: Sendable, Hashable {
    /// The root device's own id, "uuid:" taken off (a Sonos: RINCON_…).
    public var udn: String
    public var friendlyName: String
    /// A Sonos speaker's room, the name its owner gave it.
    public var roomName: String?
    public var manufacturer: String?
    public var modelName: String?
    public var avTransport: URL?
    public var renderingControl: URL?

    public var isSonos: Bool { udn.hasPrefix("RINCON_") || manufacturer?.hasPrefix("Sonos") == true }
    /// What the list calls it: a Sonos by its room ("192.168.2.8 - Sonos One
    /// SL - RINCON_…" is its friendlyName).
    public var name: String { roomName.flatMap { $0.isEmpty ? nil : $0 } ?? friendlyName }

    /// The description at `location`; nil when it is no UPnP device.
    public init?(xml: String, location: URL) {
        guard let udn = UPnPXML.text("UDN", in: xml) else { return nil }
        self.udn = udn.hasPrefix("uuid:") ? String(udn.dropFirst(5)) : udn
        friendlyName = UPnPXML.text("friendlyName", in: xml) ?? location.host ?? udn
        roomName = UPnPXML.text("roomName", in: xml)
        manufacturer = UPnPXML.text("manufacturer", in: xml)
        modelName = UPnPXML.text("modelName", in: xml)
        // The device's own host only: a description that sends its
        // controls elsewhere would have the song's address, token and all,
        // posted there.
        let base = UPnPXML.text("URLBase", in: xml).flatMap { URL(string: $0) }
            .flatMap { UPnPAddress.sameHost($0, location) ? $0 : nil } ?? location
        // Every service of every device: a Sonos has its renderer as an
        // embedded MediaRenderer, a plain renderer at its root.
        for service in UPnPXML.elements("service", in: xml) {
            guard let type = UPnPXML.text("serviceType", in: service),
                  let control = UPnPXML.text("controlURL", in: service),
                  let url = URL(string: control, relativeTo: base)?.absoluteURL,
                  UPnPAddress.sameHost(url, location) else { continue }
            if type.contains(":service:AVTransport:"), avTransport == nil { avTransport = url }
            if type.contains(":service:RenderingControl:"), renderingControl == nil { renderingControl = url }
        }
    }
}

// MARK: - Sonos rooms

/// Sonos rooms playing together: one row in the list, played on through
/// its coordinator. A bonded surround or Sub is no row of its own.
public struct SonosGroup: Sendable, Hashable {
    /// The coordinator's id (RINCON_…).
    public var coordinator: String
    /// The coordinator's description.
    public var location: URL
    /// Its rooms, the coordinator's first.
    public var rooms: [String]

    public var name: String { rooms.joined(separator: " + ") }

    /// From the topology GetZoneGroupState answers with (its ZoneGroupState
    /// value, its entities read once): the ZoneGroup elements, inside a
    /// ZoneGroupState of their own on S2, bare on S1.
    public static func groups(fromZoneGroupState state: String) -> [SonosGroup] {
        var groups: [SonosGroup] = []
        var current: (coordinator: String, members: [(id: String, room: String, location: URL)])?
        func close() {
            guard let group = current, !group.members.isEmpty else { return }
            let lead = group.members.first { $0.id == group.coordinator } ?? group.members[0]
            var rooms = [lead.room]
            for member in group.members where !rooms.contains(member.room) { rooms.append(member.room) }
            groups.append(SonosGroup(coordinator: lead.id, location: lead.location, rooms: rooms))
        }
        for tag in UPnPXML.tags(in: state) where !tag.isClosing {
            switch tag.name {
            case "ZoneGroup":
                close()
                current = (tag.attributes["Coordinator"] ?? "", [])
            case "ZoneGroupMember":
                // Invisible: one half of a stereo pair, a bonded surround.
                guard tag.attributes["Invisible"] != "1", let id = tag.attributes["UUID"],
                      let location = tag.attributes["Location"].flatMap(URL.init(string:)) else { continue }
                current?.members.append((id, tag.attributes["ZoneName"] ?? id, location))
            default:
                break
            }
        }
        close()
        return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - SOAP

public enum UPnPError: Error, Sendable, Equatable {
    /// The device said no: UPnP's errorCode and its words.
    case fault(code: Int?, description: String?)
    case http(Int)
    case unreadable
    /// An address outside the house (UPnPAddress), or a redirect away from
    /// the device asked.
    case notLocal
}

public enum UPnPSOAP {
    public static let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"
    public static let renderingControl = "urn:schemas-upnp-org:service:RenderingControl:1"
    public static let zoneGroupTopology = "urn:schemas-upnp-org:service:ZoneGroupTopology:1"

    /// The envelope for `action`, the arguments in order, each escaped.
    public static func envelope(_ action: String, service: String, _ arguments: [(String, String)]) -> String {
        let body = arguments.map { "<\($0.0)>\(UPnPXML.escape($0.1))</\($0.0)>" }.joined()
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
            + "<s:Body><u:\(action) xmlns:u=\"\(service)\">\(body)</u:\(action)></s:Body></s:Envelope>"
    }

    /// The SOAPACTION header.
    public static func header(_ action: String, service: String) -> String { "\"\(service)#\(action)\"" }

    /// The values the device answered `action` with, entities read; a
    /// fault throws.
    public static func values(in response: String, action: String) throws -> [String: String] {
        if let fault = UPnPXML.elements("Fault", in: response).first {
            throw UPnPError.fault(code: UPnPXML.text("errorCode", in: fault).flatMap { Int($0) },
                                  description: UPnPXML.text("errorDescription", in: fault)
                                      ?? UPnPXML.text("faultstring", in: fault))
        }
        guard let answer = UPnPXML.elements(action + "Response", in: response).first else { throw UPnPError.unreadable }
        return Dictionary(UPnPXML.children(of: answer).map { ($0.name, $0.text) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The song as a renderer is told of it, DIDL-Lite: what a Sonos shows in
/// its own app, and the `res` with the type it is about to fetch.
public enum DIDLLite {
    public static func metadata(url: URL, contentType: String, title: String, artist: String?, album: String?,
                                artworkURL: URL?, duration: TimeInterval?) -> String {
        func element(_ name: String, _ value: String?) -> String {
            guard let value, !value.isEmpty else { return "" }
            return "<\(name)>\(UPnPXML.escape(value))</\(name)>"
        }
        let length = duration.map { " duration=\"\(UPnPTime.string($0)).000\"" } ?? ""
        return "<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\""
            + " xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">"
            + "<item id=\"jukebox\" parentID=\"-1\" restricted=\"1\">"
            + element("dc:title", title) + element("dc:creator", artist) + element("upnp:artist", artist)
            + element("upnp:album", album) + element("upnp:albumArtURI", artworkURL?.absoluteString)
            + "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
            + "<res protocolInfo=\"http-get:*:\(UPnPXML.escape(contentType)):*\"\(length)>\(UPnPXML.escape(url.absoluteString))</res>"
            + "</item></DIDL-Lite>"
    }
}

/// UPnP's "H:MM:SS" (with a fraction at times), both ways.
public enum UPnPTime {
    public static func string(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
    }

    /// Nil for "NOT_IMPLEMENTED" and the like.
    public static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - Talking to one

/// A renderer's two services, called over HTTP.
public struct UPnPRenderer: Sendable {
    public var avTransport: URL
    public var renderingControl: URL?

    public init(avTransport: URL, renderingControl: URL?) {
        self.avTransport = avTransport
        self.renderingControl = renderingControl
    }

    public enum State: String, Sendable {
        case playing = "PLAYING"
        case paused = "PAUSED_PLAYBACK"
        case stopped = "STOPPED"
        case transitioning = "TRANSITIONING"
        case noMedia = "NO_MEDIA_PRESENT"
    }

    public struct Position: Sendable, Equatable {
        public var elapsed: TimeInterval
        public var duration: TimeInterval?
    }

    public func load(_ url: URL, metadata: String) async throws {
        _ = try await transport("SetAVTransportURI", [("CurrentURI", url.absoluteString),
                                                      ("CurrentURIMetaData", metadata)])
    }

    public func play() async throws { _ = try await transport("Play", [("Speed", "1")]) }
    public func pause() async throws { _ = try await transport("Pause", []) }
    public func stop() async throws { _ = try await transport("Stop", []) }

    public func seek(to seconds: TimeInterval) async throws {
        _ = try await transport("Seek", [("Unit", "REL_TIME"), ("Target", UPnPTime.string(seconds))])
    }

    /// Nil for a state UPnP does not name (a vendor's own).
    public func state() async throws -> State? {
        let values = try await transport("GetTransportInfo", [])
        return values["CurrentTransportState"].flatMap(State.init(rawValue:))
    }

    public func position() async throws -> Position {
        let values = try await transport("GetPositionInfo", [])
        return Position(elapsed: values["RelTime"].flatMap(UPnPTime.seconds) ?? 0,
                        duration: values["TrackDuration"].flatMap(UPnPTime.seconds))
    }

    /// 0...100, the Master channel's; nil without RenderingControl.
    public func volume() async throws -> Int? {
        guard let renderingControl else { return nil }
        let values = try await Self.call(renderingControl, UPnPSOAP.renderingControl, "GetVolume",
                                         [("InstanceID", "0"), ("Channel", "Master")])
        return values["CurrentVolume"].flatMap { Int($0) }
    }

    public func setVolume(_ level: Int) async throws {
        guard let renderingControl else { return }
        _ = try await Self.call(renderingControl, UPnPSOAP.renderingControl, "SetVolume",
                                [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", String(min(100, max(0, level))))])
    }

    private func transport(_ action: String, _ arguments: [(String, String)]) async throws -> [String: String] {
        try await Self.call(avTransport, UPnPSOAP.avTransport, action, [("InstanceID", "0")] + arguments)
    }

    /// One action. A device on the same network answers at once: 5 s is gone.
    public static func call(_ url: URL, _ service: String, _ action: String, _ arguments: [(String, String)],
                            transport: any HTTPTransport = URLSessionTransport()) async throws -> [String: String] {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue(UPnPSOAP.header(action, service: service), forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(UPnPSOAP.envelope(action, service: service, arguments).utf8)
        let response = try await send(request, transport)
        let text = String(decoding: response.body, as: UTF8.self)
        // A fault comes as a 500 with its reason in the body.
        if response.status != 200, !text.contains("Fault") { throw UPnPError.http(response.status) }
        return try UPnPSOAP.values(in: text, action: action)
    }

    /// The description at `location`.
    public static func description(at location: URL,
                                   transport: any HTTPTransport = URLSessionTransport()) async throws -> UPnPDescription {
        let response = try await send(URLRequest(url: location, timeoutInterval: 5), transport)
        guard response.status == 200 else { throw UPnPError.http(response.status) }
        guard let description = UPnPDescription(xml: String(decoding: response.body, as: UTF8.self), location: location)
        else { throw UPnPError.unreadable }
        return description
    }

    /// More than any description or answer a speaker gives (a Sonos's
    /// description is some 30 KB).
    static let maximumBytes = 256 * 1024

    /// Every request to a speaker: only to an address in the house, its
    /// redirects as RedirectPolicy lets them go (URLSessionTransport) and
    /// answered by the host asked, and no bigger than a speaker's answer
    /// (checked once it is in: Linux's URLSession cannot safely be stopped
    /// mid-way, HTTPTransport.swift).
    static func send(_ request: URLRequest, _ transport: any HTTPTransport) async throws -> HTTPResponse {
        guard let url = request.url, UPnPAddress.isLocal(url) else { throw UPnPError.notLocal }
        let response = try await transport.send(request)
        if let final = response.url, !UPnPAddress.sameHost(final, url) { throw UPnPError.notLocal }
        guard response.body.count <= maximumBytes else { throw UPnPError.unreadable }
        return response
    }

    /// The rooms of the Sonos system the speaker at `location` is in.
    public static func sonosGroups(at location: URL) async throws -> [SonosGroup] {
        guard let control = URL(string: "/ZoneGroupTopology/Control", relativeTo: location)?.absoluteURL else {
            throw UPnPError.unreadable
        }
        let values = try await call(control, UPnPSOAP.zoneGroupTopology, "GetZoneGroupState", [])
        return SonosGroup.groups(fromZoneGroupState: values["ZoneGroupState"] ?? "")
    }
}
