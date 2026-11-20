// The Sonos rooms on the iPhone, the iPad and the Mac: "Huh daar staat wel
// weer mn sonos bij" (the photographer, 20 November 2026, seeing Spotify
// list his Sonos). Until then Apple's reached a Sonos only through AirPlay's
// own list, under the system's name, and Play On had none. Found by Bonjour
// (`_sonos._tcp`), as Linux finds it by Avahi; played by UPnP AV, every
// client's same code (Player/UPnPPlay.swift). No SSDP here: multicast from
// an iPhone needs an entitlement Apple grants by request, and every Sonos
// answers Bonjour. Bonjour looks only while Play On's list is open, so the
// local network prompt comes then, not at launch.

import Foundation
import Network

final class BonjourSonosFinder: PlayOnFinder {
    private var browser: NWBrowser?
    private var asked: Set<NWEndpoint> = []
    private var resolving: [NWConnection] = []
    private let rooms = UPnPRooms()

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        stop()
        rooms.start(found)
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for result in results where self.asked.insert(result.endpoint).inserted {
                    self.locate(result)
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        for connection in resolving { connection.cancel() }
        resolving = []
        asked = []
        rooms.stop()
    }

    /// Where the speaker's description is.
    private func locate(_ result: NWBrowser.Result) {
        // A Sonos says it in its TXT record ("location").
        if case let .bonjour(record) = result.metadata,
           let text = record.dictionary["location"], let location = URL(string: text) {
            rooms.consider(location)
            return
        }
        // Else from its address: a connection to the service says where it
        // is, and the description is on 1400 in plain http, whatever port
        // the service names (1443, its own https API), as on Linux.
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            // A link-local IPv6 address would need its interface in the URL.
            ip.version = .v4
        }
        let connection = NWConnection(to: result.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, let connection else { return }
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint,
                       let location = Self.location(of: host) {
                        self.rooms.consider(location)
                    }
                    connection.cancel()
                case .failed, .waiting:
                    connection.cancel()
                case .cancelled:
                    self.resolving.removeAll { $0 === connection }
                default:
                    break
                }
            }
        }
        resolving.append(connection)
        connection.start(queue: .main)
    }

    private static func location(of host: NWEndpoint.Host) -> URL? {
        let name: String
        switch host {
        case let .ipv4(address): name = "\(address)"
        case let .name(text, _): name = text
        default: return nil
        }
        // Without the interface an address may carry ("%en0").
        guard let bare = name.split(separator: "%").first else { return nil }
        return URL(string: "http://\(bare):1400/xml/device_description.xml")
    }
}
