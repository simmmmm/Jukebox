// What is played but not counted (Library/NotCounted.swift): a marked song,
// a song of a marked album, a song played from a marked playlist; kept and
// read again as it was; Private Listening's "until restart" never kept.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Not counted")
struct NotCountedTests {
    let carol = Track(id: "carol", name: "Silent Night", albumID: "xmas")
    let other = Track(id: "other", name: "Night Bus", albumID: "bus")

    @Test("Nothing marked: every play counts")
    func empty() {
        let marks = NotCounted()
        #expect(marks.counts(carol, playlistID: nil))
        #expect(marks.counts(carol, playlistID: "december"))
    }

    @Test("A song, its album, or the playlist it plays from")
    func marked() {
        var marks = NotCounted()
        marks.set(.init(kind: .album, id: "xmas", name: "Christmas"), counted: false)
        #expect(!marks.counts(carol, playlistID: nil))
        #expect(marks.counts(other, playlistID: nil))

        marks = NotCounted()
        marks.set(.init(kind: .song, id: "other", name: "Night Bus"), counted: false)
        #expect(!marks.counts(other, playlistID: nil))
        #expect(marks.counts(carol, playlistID: nil))

        marks = NotCounted()
        marks.set(.init(kind: .playlist, id: "december", name: "December"), counted: false)
        #expect(!marks.counts(other, playlistID: "december"))
        #expect(marks.counts(other, playlistID: nil))
        #expect(marks.counts(other, playlistID: "summer"))
    }

    @Test("Counted again, newest first, one entry per item, a song and an album of one id apart")
    func editing() {
        var marks = NotCounted()
        marks.set(.init(kind: .song, id: "x", name: "A"), counted: false)
        marks.set(.init(kind: .album, id: "x", name: "B"), counted: false)
        marks.set(.init(kind: .song, id: "x", name: "A"), counted: false)
        #expect(marks.items.map(\.key) == ["song:x", "album:x"])
        marks.set(.init(kind: .song, id: "x", name: "A"), counted: true)
        #expect(marks.items.map(\.key) == ["album:x"])
        #expect(!marks.contains(.song, "x"))
        #expect(marks.contains(.album, "x"))
    }

    @Test("Kept and read again")
    func codable() throws {
        var marks = NotCounted()
        marks.set(.init(kind: .playlist, id: "p", name: "Kerst"), counted: false)
        let data = try JSONEncoder().encode(marks)
        #expect(try JSONDecoder().decode(NotCounted.self, from: data) == marks)
    }

    @Test("Private Listening: only On is kept")
    func privateListening() {
        #expect(PrivateListening.restored("on") == .on)
        #expect(PrivateListening.restored("untilRestart") == .off)
        #expect(PrivateListening.restored(nil) == .off)
    }
}
