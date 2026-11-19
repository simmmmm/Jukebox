// Several songs picked at once in a desktop list (Linux, the Mac's wide
// window), for the menu's Play Next, Add to Queue and Add to
// Playlist… on all of them: Ctrl (⌘) adds or takes away one, Shift picks
// the run from the last one picked. No new buttons ("ik wil alleen er voor
// waken dat we niet 10000 knopen krijgen. Alles is nu lekker clean", 18
// November 2026): a plain click plays as it always did, and forgets the
// picks. Shared by both clients, so the rules are one (Linux's QueueCheck
// checks them after every build).

import Foundation

/// The rows picked, by their place in the list (a playlist may hold a song
/// twice).
struct TrackPicks: Equatable {
    private(set) var rows: Set<Int> = []
    /// Where a Shift-click's run starts: the last row Ctrl-clicked.
    private var anchor: Int?

    enum Click {
        /// Ctrl or ⌘: this row in or out.
        case toggle
        /// Shift: every row from the anchor to this one.
        case extend
    }

    var isEmpty: Bool { rows.isEmpty }

    func contains(_ row: Int) -> Bool { rows.contains(row) }

    mutating func click(_ row: Int, _ kind: Click) {
        switch kind {
        case .toggle:
            if rows.remove(row) == nil { rows.insert(row) }
            anchor = row
        case .extend:
            let from = anchor ?? row
            rows = Set(min(from, row)...max(from, row))
            anchor = from
        }
    }

    mutating func clear() { self = TrackPicks() }

    /// A plain click (it plays): nothing picked, and a Shift-click after it
    /// runs from this row, as in Files.
    mutating func plain(_ row: Int) {
        rows = []
        anchor = row
    }

    /// What a menu on `row` acts on: every pick, in the list's order, when
    /// the row is one of two or more; the row alone otherwise.
    func tracks<Item>(at row: Int, in items: [Item]) -> [Item] {
        guard rows.count > 1, rows.contains(row) else { return items.indices.contains(row) ? [items[row]] : [] }
        return rows.sorted().filter { items.indices.contains($0) }.map { items[$0] }
    }
}
