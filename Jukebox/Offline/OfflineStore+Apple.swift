// What OfflineStore and OfflineDisk ask of Apple's systems: the network as
// NWPathMonitor tells it, Low Power Mode, and where the songs live
// (Application Support, out of the backups). The store, the disk and the
// words are one set of files for the iPhone, the iPad, the Mac and Linux
// (Package.swift's `shared`); Linux's answers to these are in
// Linux/App/Platform.swift.

import Foundation
import JukeboxKit
import Network

extension OfflineStore {
    /// Low Power Mode, now.
    nonisolated static var isLowPowerNow: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// The network and Low Power Mode, told to the store as they change
    /// (`pathChanged`, `powerChanged`). The store keeps what this returns.
    func watchSystem() -> AnyObject {
        let watch = OfflineSystemWatch()
        watch.monitor.pathUpdateHandler = Self.pathHandler { [weak self] path in
            Task { @MainActor in self?.pathChanged(path) }
        }
        watch.monitor.start(queue: DispatchQueue(label: "Jukebox.offline-network", qos: .utility))
        watch.powerToken = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.powerChanged(isLowPower: OfflineStore.isLowPowerNow)
            }
        }
        return watch
    }

    /// Made outside the main actor: the monitor calls it on its own queue.
    /// Low Data Mode (`isConstrained`) counts as expensive, as NetworkCost
    /// has it.
    private nonisolated static func pathHandler(_ update: @escaping @Sendable (OfflinePathState) -> Void)
        -> @Sendable (NWPath) -> Void {
        { path in
            update(OfflinePathState(isSatisfied: path.status == .satisfied,
                                    isExpensive: path.isExpensive || path.isConstrained))
        }
    }
}

/// The monitor and the power observer, kept by the store.
private final class OfflineSystemWatch {
    let monitor = NWPathMonitor()
    var powerToken: (any NSObjectProtocol)?
}

extension OfflinePaths {
    /// Application Support/Offline.
    nonisolated static var base: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support.appendingPathComponent("Offline", isDirectory: true)
    }
}

extension OfflineDisk {
    /// Made once a launch: the folder, kept out of backups (which a
    /// directory's flag does for everything in it).
    nonisolated static func prepareBase() {
        var base = OfflinePaths.base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? base.setResourceValues(values)
    }
}
