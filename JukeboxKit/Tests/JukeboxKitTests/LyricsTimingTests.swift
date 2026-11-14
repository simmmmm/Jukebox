// Lyrics.lineIndex(at:): the line lit as the song plays.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Lyrics: the line sung")
struct LyricsTimingTests {
    let lyrics = Lyrics(lines: [
        .init(start: 10, text: "one"),
        .init(start: nil, text: "no time of its own"),
        .init(start: 20, text: ""),
        .init(start: 30, text: "three"),
    ])

    @Test("Nothing before the first line, which lights a quarter second early")
    func first() {
        #expect(lyrics.lineIndex(at: 0) == nil)
        #expect(lyrics.lineIndex(at: 9.7) == nil)
        #expect(lyrics.lineIndex(at: 9.75) == 0)
    }

    @Test("The last line begun; a line without a time is passed over, a pause is a line")
    func later() {
        #expect(lyrics.lineIndex(at: 15) == 0)
        #expect(lyrics.lineIndex(at: 20) == 2)
        #expect(lyrics.lineIndex(at: 29.8) == 3)
        #expect(lyrics.lineIndex(at: 3600) == 3)
    }

    @Test("Untimed lyrics have no line sung")
    func untimed() {
        let plain = Lyrics(lines: [.init(start: nil, text: "a"), .init(start: nil, text: "b")])
        #expect(plain.lineIndex(at: 60) == nil)
    }
}
