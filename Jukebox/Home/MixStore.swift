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

    /// Bumped by every build and by `reset`: a build that ends after a newer
    /// one began, or after a sign-out, is dropped rather than shown.
    @ObservationIgnored private var generation = 0

    init() {}

    func rebuild(library: LibraryStore, history: HistoryStore, settings: AppSettings) async {
        // Everything the generator needs, as values, taken here on the main
        // actor; the work itself runs elsewhere so Home scrolls while it
        // is made.
        let snapshot = library.snapshot
        // Nothing to make mixes from yet (the first load has not ended):
        // the next load, or Home appearing, asks again.
        guard !snapshot.isEmpty else { return }
        let events = history.history
        let now = Date()
        generation += 1
        let generation = self.generation
        isBuilding = true

        let (newMixes, newStations) = await Task.detached(priority: .userInitiated) {
            () -> ([Mix], [Station]) in
            let taste = TasteProfile(snapshot: snapshot, history: events, now: now)
            // The library's own edges: the radio's graph with Last.fm in it
            // lives in RadioController, which this store is not handed.
            let graph = SimilarityGraph.fromLibrary(snapshot)
            let generator = MixGenerator(snapshot: snapshot, taste: taste, history: events, graph: graph, now: now)
            return (generator.mixes(), generator.suggestedStations())
        }.value

        guard generation == self.generation else { return }
        mixes = newMixes
        stations = newStations
        builtAt = now
        isBuilding = false
    }

    /// Rebuild when the last build is from another day, older than `maxAge`,
    /// or older than the library (Home calls this when it appears and when
    /// the library has loaded).
    func rebuildIfStale(library: LibraryStore, history: HistoryStore, settings: AppSettings,
                        maxAge: TimeInterval = 3 * 3600) async {
        // The build under way is as fresh as one more would be.
        guard !isBuilding else { return }
        if let builtAt {
            let now = Date()
            // The mixes are seeded by the date: a new morning is a new set,
            // even when the last one is only an hour old.
            let sameDay = Calendar.current.isDate(builtAt, inSameDayAs: now)
            // Made from the cached library at launch, then the server's came
            // in (LibraryStore.open loads it behind the cache): New Arrivals
            // and play counts are the server's now, so the mixes are made again.
            let libraryIsNewer = library.lastLoaded.map { $0 > builtAt } ?? false
            if sameDay && now.timeIntervalSince(builtAt) < maxAge && !libraryIsNewer { return }
        }
        await rebuild(library: library, history: history, settings: settings)
    }

    func reset() {
        generation += 1
        mixes = []
        stations = []
        isBuilding = false
        builtAt = nil
    }
}
