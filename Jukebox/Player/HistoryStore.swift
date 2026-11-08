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

    private let url: URL
    /// One writer, in order: a slow write can never land after a newer one.
    private let writer = DispatchQueue(label: "Jukebox.history", qos: .utility)
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        url = Self.fileURL()
        // Read at once, on launch, so the first mixes and the first station
        // already know what was heard. The file is at most 20 000 small
        // events (ListeningHistory.limit), a few megabytes.
        history = ListeningHistory.load(from: url)
    }

    func record(_ event: PlayEvent) {
        history.append(event)
        scheduleSave()
    }

    /// A thumb taken back: the track's newest event goes, if it is that
    /// thumb. A thumbs down left in keeps the song off every station for
    /// half a year (TasteData.thumbsDownDays), whatever the button shows.
    func removeLatest(_ outcome: PlayOutcome, of trackID: ItemID) {
        guard history.removeLatest(outcome, of: trackID) else { return }
        scheduleSave()
    }

    /// Recently heard tracks, newest first, at most `limit`, each once.
    func recentTrackIDs(limit: Int = 50) -> [ItemID] {
        guard limit > 0 else { return [] }
        var seen = Set<ItemID>()
        var ids: [ItemID] = []
        for event in history.events.reversed() {
            // Heard: a skip, or a thumbs down, is not.
            if event.outcome == .skipped || event.outcome == .disliked { continue }
            if seen.insert(event.trackID).inserted {
                ids.append(event.trackID)
                if ids.count >= limit { break }
            }
        }
        return ids
    }

    func clear() {
        saveTask?.cancel()
        saveTask = nil
        history = ListeningHistory()
        saveNow()
    }

    /// Two seconds after the last play, so a burst of skips is one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        let snapshot = history
        let url = self.url
        writer.async {
            try? snapshot.save(to: url)
        }
    }

    private static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Jukebox", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
