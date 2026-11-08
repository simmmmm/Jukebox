// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// This device's listening history (JukeboxKit's ListeningHistory) in
// Application Support, written a moment after each play so a crash loses at
// most one. The radio and the mixes read it; the player writes it.

import Foundation
import JukeboxKit
import Observation

@Observable
final class HistoryStore {
    private(set) var history = ListeningHistory()

    init() {
        fatalError("not built yet")
    }

    func record(_ event: PlayEvent) {
        fatalError("not built yet")
    }

    /// Recently heard tracks, newest first, at most `limit`, each once.
    func recentTrackIDs(limit: Int = 50) -> [ItemID] {
        fatalError("not built yet")
    }

    func clear() {
        fatalError("not built yet")
    }
}
