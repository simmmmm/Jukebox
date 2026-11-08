// CONTRACT — signatures fixed; bodies the home agent's (docs/ARCHITECTURE.md).
//
// Home's made-up playlists and suggested stations (JukeboxKit's
// MixGenerator), made off the main actor from the library, the history and
// the similarity graph; again when the library loads, after a while of
// listening, and on a new day.

import Foundation
import JukeboxKit
import Observation

@Observable
final class MixStore {
    private(set) var mixes: [Mix] = []
    private(set) var stations: [Station] = []
    private(set) var isBuilding = false
    private(set) var builtAt: Date?

    init() {}

    func rebuild(library: LibraryStore, history: HistoryStore, settings: AppSettings) async {
        fatalError("not built yet")
    }

    /// Rebuild when the last build is from another day or older than
    /// `maxAge` (Home calls this when it appears).
    func rebuildIfStale(library: LibraryStore, history: HistoryStore, settings: AppSettings,
                        maxAge: TimeInterval = 3 * 3600) async {
        fatalError("not built yet")
    }

    func reset() { fatalError("not built yet") }
}
