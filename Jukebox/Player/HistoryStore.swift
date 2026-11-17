// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// This device's listening history (JukeboxKit's ListeningHistory) in
// Application Support, written a moment after each play so a crash loses at
// most one. The radio and the mixes read it; the player writes it.
//
// One file an account (AccountFiles.history): the radio's learning and
// Home's mixes are of that account's library, and another server's
// artists and ids would only mislead them.

import Foundation
import JukeboxKit
import Observation

@Observable
final class HistoryStore {
    private(set) var history = ListeningHistory()

    /// The account's file; nil while none is signed in, and nothing is kept.
    @ObservationIgnored private var url: URL?
    /// One writer, in order: a slow write can never land after a newer one.
    private let writer = DispatchQueue(label: "Jukebox.history", qos: .utility)
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {}

    /// Signed in, or switched to: the account's history, read at once so
    /// the first mixes and the first station already know what was heard.
    /// The file is at most 20 000 small events (ListeningHistory.limit), a
    /// few megabytes.
    func open(_ file: URL) {
        close()
        url = file
        history = ListeningHistory.load(from: file)
    }

    /// The account put away: what is not yet written goes to its own file
    /// first. The file stays, also at a sign-out: signing in again finds the
    /// radio's learning where it was.
    func close() {
        if saveTask != nil { saveNow() }
        url = nil
        history = ListeningHistory()
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
        saveTask?.cancel()
        saveTask = nil
        guard let url else { return }
        let snapshot = history
        writer.async {
            try? snapshot.save(to: url)
        }
    }

    /// Waits for the writes under way: a file moved or read after this is
    /// the one last written (the migration, AccountCheck).
    func flush() {
        writer.sync {}
    }
}
