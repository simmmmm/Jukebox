// What plays without counting (JukeboxKit's NotCounted): the songs, albums
// and playlists marked Don't Count Plays, one list an account in
// UserDefaults beside its recent stations, and Private Listening for the
// whole device. The photographer, 19 November 2026: "bijv voor kerstmuziek
// oid", and "een soort prive modus overall", on, off, or until the next
// restart.
//
// The player owns it (`player.notCounted`), so every screen that has the
// player has it, and the queue asks it in one place (PlayQueue.counts).
// Foundation only: Linux compiles it too (Package.swift's `shared`).

import Foundation
import JukeboxKit
import Observation

@Observable
final class NotCountedStore {
    private(set) var marks = NotCounted()

    /// Kept only when On; Until Restart is gone at the next launch.
    var privateListening: PrivateListening = .restored(UserDefaults.standard.string(forKey: NotCountedStore.privateKey)) {
        didSet {
            if privateListening == .on {
                UserDefaults.standard.set(PrivateListening.on.rawValue, forKey: NotCountedStore.privateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: NotCountedStore.privateKey)
            }
        }
    }

    var isPrivate: Bool { privateListening != .off }

    private static let privateKey = "privateListening"
    /// The account's UserDefaults key; nil while none is signed in.
    @ObservationIgnored private var key: String?

    init() {}

    /// Signed in, or switched to (AccountStores.open).
    func open(_ key: String) {
        self.key = key
        marks = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(NotCounted.self, from: $0) } ?? NotCounted()
    }

    /// The account put away; its marks stay for a sign-in again, as its
    /// history does.
    func close() {
        key = nil
        marks = NotCounted()
    }

    func isMarked(_ kind: NotCounted.Kind, _ id: ItemID) -> Bool {
        marks.contains(kind, id)
    }

    func set(_ kind: NotCounted.Kind, id: ItemID, name: String, counted: Bool) {
        marks.set(.init(kind: kind, id: id, name: name), counted: counted)
        guard let key else { return }
        if marks.items.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(marks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func toggle(_ kind: NotCounted.Kind, id: ItemID, name: String) {
        set(kind, id: id, name: name, counted: isMarked(kind, id))
    }

    /// A marked album's or playlist's page says so, quietly, at the end of
    /// its facts: "7 songs, 27 min · Not counted".
    func fact(_ facts: String, _ kind: NotCounted.Kind, _ id: ItemID) -> String {
        guard isMarked(kind, id) else { return facts }
        let mark = String(localized: "Not counted")
        return facts.isEmpty ? mark : "\(facts) · \(mark)"
    }

    /// Whether a play of `track`, from the playlist `playlistID`, counts.
    func counts(_ track: Track, playlistID: ItemID?) -> Bool {
        !isPrivate && marks.counts(track, playlistID: playlistID)
    }
}
