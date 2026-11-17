// Chromecasts on the iPhone, the iPad and the Mac: the app speaks castv2
// itself, as Linux does, JukeboxKit's CastSession over Network's TLS, the
// receivers found by Bonjour. No Google Cast SDK: the photographer, 17
// November 2026, "Doe zonder" (it would have sent Google diagnostics and a
// device id, and asked for its own Cast button). The protocol is the kit's,
// tested on Linux; this is the socket and the browser (PlayOn.swift has the
// player). Bonjour looks only while Play On's list is open, so the local
// network prompt comes then, not at launch.

import Foundation
import Network

/// `_googlecast._tcp` by Bonjour, while Play On's list is open.
final class BonjourCastFinder: PlayOnFinder {
    private var browser: NWBrowser?

    func start(_ found: @escaping ([PlayOnDevice]) -> Void) {
        stop()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            let devices = results.compactMap { result -> PlayOnDevice? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                var text: [String: String] = [:]
                if case let .bonjour(record) = result.metadata { text = record.dictionary }
                // fn is the name the owner gave it ("Living Room TV"), id
                // its own; the service's name is where it is.
                return PlayOnDevice(id: text["id"] ?? name, name: text["fn"] ?? name, kind: .chromecast, address: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            MainActor.assumeIsolated { found(devices) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// TLS to the receiver's service, its certificate accepted: a Chromecast's
/// is its own, signed by Google's device CA, never a public one.
final class NetworkCastSocket: CastSocket {
    var received: ((Data?) -> Void)?
    private let connection: NWConnection

    init(service: String) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in
            complete(true)
        }, .main)
        connection = NWConnection(to: .service(name: service, type: "_googlecast._tcp", domain: "local.", interface: nil),
                                  using: NWParameters(tls: tls))
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { self?.received?(nil) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, !data.isEmpty { self.received?(data) }
                if isComplete || error != nil {
                    self.received?(nil)
                    return
                }
                self.receive()
            }
        }
    }

    func send(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        received = nil
        connection.cancel()
    }
}
