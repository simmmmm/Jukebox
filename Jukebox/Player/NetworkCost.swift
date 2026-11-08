// Whether the network costs something — the mobile network, a phone's
// hotspot, Low Data Mode — so the player can stream at Settings' "Mobile"
// quality there and at "Wi-Fi" quality otherwise. NWPathMonitor answers on
// its own queue; the latest answer is kept here, on the main actor, and read
// each time a track is loaded.

import Foundation
import Network

final class NetworkCost {
    private(set) var isExpensive = false
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = Self.handler { [weak self] expensive in
            Task { @MainActor in self?.isExpensive = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "Jukebox.network-cost", qos: .utility))
    }

    /// Made outside the main actor: the monitor calls it on its own queue.
    /// Low Data Mode (`isConstrained`) counts as expensive, as Music treats it.
    nonisolated private static func handler(_ update: @escaping @Sendable (Bool) -> Void) -> @Sendable (NWPath) -> Void {
        { path in update(path.isExpensive || path.isConstrained) }
    }
}
