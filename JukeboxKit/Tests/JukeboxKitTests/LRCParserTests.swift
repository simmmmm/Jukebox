// LRCParser on every form of LRC LRCLIB and .lrc files have: one stamp and
// several, the fractions after "." and ":", metadata, the offset, word
// stamps, pauses, order, Windows line ends; and plain lyrics. The two songs
// are LyricsFixtures', written for these tests.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Lyrics: LRC")
struct LRCParserTests {
    /// Seconds as LRC writes them are not exact in binary; a millisecond
    /// is far below what the eye sees.
    func same(_ a: TimeInterval?, _ b: TimeInterval) -> Bool {
        guard let a else { return false }
        return abs(a - b) < 0.0005
    }

    @Test("The Dutch song: metadata dropped, offset applied, the chorus twice, pauses kept once")
    func dutchSong() throws {
        let lyrics = try #require(LRCParser.parse(LyricsFixtures.dutch))
        #expect(lyrics.isSynced)
        let lines = lyrics.lines
        // 4 verse, pause, 4 chorus, pause, 4 verse, 4 chorus, one pause of
        // two, 2 outro.
        #expect(lines.count == 21)
        #expect(lines.allSatisfy { $0.start != nil })
        // Nothing of the metadata is a line.
        #expect(!lines.contains { $0.text.contains("Kanaalzangers") || $0.text.contains("03:12") })

        // [offset:+250]: every line a quarter second sooner.
        #expect(lines[0].text == "De lantaarns gaan aan langs het water")
        #expect(same(lines[0].start, 12.15))
        #expect(lines[4].text.isEmpty)
        #expect(same(lines[4].start, 29.95))
        #expect(lines[5].text == "Hou me vast, de brug gaat open")
        #expect(same(lines[5].start, 40.95))

        // The chorus again at 1:32, after the second verse: sorted by time.
        #expect(lines[10].text == "De bakker slaapt nog, de kerk telt de uren")
        #expect(lines[14].text == "Hou me vast, de brug gaat open")
        #expect(same(lines[14].start, 91.95))
        #expect(lines[17].text == "Klinkt vannacht als een gezang")

        // [01:50.50] and [01:50.90] are one pause.
        #expect(lines[18].text.isEmpty)
        #expect(same(lines[18].start, 110.25))
        #expect(lines[19].text == "Langs het water, langs het water")
        #expect(lines[20].text == "Tot de ochtend ons vindt")

        let starts = lines.compactMap(\.start)
        #expect(starts == starts.sorted())
    }

    @Test("The English song: word stamps gone, every form of stamp, Windows line ends")
    func englishSong() throws {
        let lyrics = try #require(LRCParser.parse(LyricsFixtures.english))
        let lines = lyrics.lines
        #expect(lines.count == 10)
        #expect(!lines.contains { $0.text.contains("<") || $0.text.contains("\r") || $0.text.contains("\u{FEFF}") })

        #expect(lines[0].text == "We folded paper lanterns")
        #expect(same(lines[0].start, 8))
        #expect(lines[1].text == "and lit them one by one")
        #expect(same(lines[1].start, 11.5))
        // Spaces around the word stamps: one space between words.
        #expect(lines[2].text == "The river took the brightest")
        #expect(lines[3].text == "Down to where the night had gone")
        // [00:23.000]: a pause.
        #expect(lines[4].text.isEmpty)
        #expect(same(lines[4].start, 23))
        // [00:31.5]: half a second.
        #expect(lines[5].text == "Oh, hold the light (hold the light)")
        #expect(same(lines[5].start, 31.5))
        // Brackets that are not a time are words.
        #expect(lines[6].text == "Don't let the morning [laughs] in too soon")
        #expect(same(lines[6].start, 35.25))
        // [0:39.75], [00:44:10] (centiseconds after a colon), [01:02].
        #expect(same(lines[7].start, 39.75))
        #expect(same(lines[8].start, 44.10))
        #expect(lines[9].text == "Paper and the moon")
        #expect(same(lines[9].start, 62))
    }

    /// "01:02:03" is minutes, seconds and centiseconds, as the players
    /// that write a colon before the fraction mean it, not an hour, two
    /// minutes and three seconds: LRC has no hours, a long mix counts its
    /// minutes on past 60 ("105:02.00").
    @Test("Time stamps", arguments: [
        ("01:23.45", 83.45), ("01:23", 83), ("1:23.4", 83.4), ("01:23.456", 83.456),
        ("01:23:45", 83.45), ("01:23,45", 83.45), ("105:02.00", 6302), ("00:00.00", 0), (" 00:07.10 ", 7.1),
        ("1:02.3", 62.3), ("01:02:03", 62.03),
    ])
    func times(_ text: String, _ seconds: Double) throws {
        let time = try #require(LRCParser.time(text[...]))
        #expect(same(time, seconds))
    }

    @Test("Not time stamps", arguments: ["ar:Someone", "01", "aa:bb", "01:2x", "01:23.4a", "1:2:3:4", "-01:00", "", "01:123",
                                         "1:01:02.50", "-00:01.00", "00:-01.00"])
    func notTimes(_ text: String) {
        #expect(LRCParser.time(text[...]) == nil)
    }

    @Test("Several stamps on one line: the line at each, in time's order")
    func severalStamps() throws {
        let lyrics = try #require(LRCParser.parse("[00:30.00][00:10.00] Again\n[00:20.00]Between"))
        #expect(lyrics.lines == [
            Lyrics.Line(start: 10, text: "Again"),
            Lyrics.Line(start: 20, text: "Between"),
            Lyrics.Line(start: 30, text: "Again"),
        ])
    }

    @Test("Lines out of order are sorted; two at one time keep the file's order")
    func order() throws {
        let lyrics = try #require(LRCParser.parse("[00:05.00]Second voice\n[00:01.00]First\n[00:05.00]Second voice, answering"))
        #expect(lyrics.lines.map(\.text) == ["First", "Second voice", "Second voice, answering"])
    }

    @Test("A negative offset shows the lines later; a positive one never before 0:00")
    func offsets() throws {
        let later = try #require(LRCParser.parse("[offset:-500]\n[00:01.00]One"))
        #expect(same(later.lines[0].start, 1.5))
        let sooner = try #require(LRCParser.parse("[offset:+2000]\n[00:01.00]One\n[00:04.00]Two"))
        #expect(same(sooner.lines[0].start, 0))
        #expect(same(sooner.lines[1].start, 2))
        // Written after the lines, it still applies to all of them.
        let after = try #require(LRCParser.parse("[00:01.00]One\n[offset:100]"))
        #expect(same(after.lines[0].start, 0.9))
    }

    @Test("A negative stamp is not a time: the line is dropped, the others kept")
    func negativeStamp() throws {
        let lyrics = try #require(LRCParser.parse("[-00:01.00]Before the start\n[00:02.00]Two"))
        #expect(lyrics.lines == [Lyrics.Line(start: 2, text: "Two")])
    }

    @Test("Old Mac line ends, a byte order mark at a line's start, an offset written with spaces")
    func lineEnds() throws {
        let mac = try #require(LRCParser.parse("[00:01.00]One\r[00:02.00]Two\r"))
        #expect(mac.lines == [Lyrics.Line(start: 1, text: "One"), Lyrics.Line(start: 2, text: "Two")])
        // Two files joined into one, each with its mark.
        let joined = try #require(LRCParser.parse("\u{FEFF}\u{FEFF}[00:01.00]One\n\u{FEFF}[00:02.00]Two"))
        #expect(joined.lines == [Lyrics.Line(start: 1, text: "One"), Lyrics.Line(start: 2, text: "Two")])
        let spaced = try #require(LRCParser.parse("[offset: -250 ]\r\n[00:01.00]One"))
        #expect(same(spaced.lines[0].start, 1.25))
    }

    @Test("Every line at 0:00 and an offset: still no timing")
    func allAtZeroWithOffset() throws {
        let lyrics = try #require(LRCParser.parse("[offset:-500]\n[00:00.00]One\n[00:00.00]Two"))
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["One", "Two"])
    }

    /// LRCLIB's lyrics are typed by anyone. Before the closer was looked
    /// for only as far as a stamp reaches, these took 5.2 s ("<" alone)
    /// to 16 s ("<" before one ">"); now 0.04 s each (debug build).
    @Test("A very long line, of brackets that never close or close far away, is read at once")
    func longLines() throws {
        let n = 20_000
        let lines = [
            String(repeating: "<", count: n),
            String(repeating: "[", count: n),
            String(repeating: "<", count: n) + ">",
            "[00:01.00]" + String(repeating: "[", count: n) + "]",
            "[00:01.00]" + String(repeating: "<00:01.00>la ", count: n / 13),
        ]
        for line in lines {
            let start = ContinuousClock().now
            let lyrics = LRCParser.parse(line)
            let took = ContinuousClock().now - start
            print("LYRICS-MEASURE a line of \(line.count) characters (\(line.prefix(12))…): \(took)")
            #expect(took < .seconds(1))
            #expect(lyrics != nil)
        }
        // The words of the last kept, their stamps gone.
        let sung = try #require(LRCParser.parse(lines[4]))
        #expect(sung.lines.count == 1)
        #expect(!sung.lines[0].text.contains("<"))
        #expect(sung.lines[0].text.hasPrefix("la la la"))
    }

    @Test("10 000 lines, out of order: sorted, every one kept")
    func tenThousandLines() throws {
        // Written backwards, so the sort has all the work.
        let text = (0..<10_000).reversed().map { i in
            let centiseconds = i * 37
            let stamp = String(format: "[%02d:%02d.%02d]", centiseconds / 6_000, (centiseconds / 100) % 60, centiseconds % 100)
            return stamp + "Line \(i)"
        }.joined(separator: "\n")
        let start = ContinuousClock().now
        let lyrics = try #require(LRCParser.parse(text))
        let took = ContinuousClock().now - start
        print("LYRICS-MEASURE 10 000 lines (\(text.utf8.count) bytes): \(took)")
        #expect(took < .seconds(2))
        #expect(lyrics.lines.count == 10_000)
        #expect(lyrics.lines.first?.text == "Line 0")
        #expect(lyrics.lines.last?.text == "Line 9999")
        let starts = lyrics.lines.compactMap(\.start)
        #expect(starts == starts.sorted())
    }

    @Test("Lines without a stamp in a synced file are dropped")
    func untimedInSynced() throws {
        let lyrics = try #require(LRCParser.parse("[Chorus]\n[00:01.00]One\nA credit line\n[00:02.00]Two"))
        #expect(lyrics.lines.map(\.text) == ["One", "Two"])
    }

    @Test("Only pauses, only metadata, or nothing: no lyrics")
    func nothing() {
        #expect(LRCParser.parse("") == nil)
        #expect(LRCParser.parse("[00:01.00]\n[00:05.00] ") == nil)
        #expect(LRCParser.parse("[ar:Someone]\n[ti:Something]\n") == nil)
        #expect(LRCParser.plain("\n \n\n") == nil)
    }

    @Test("Without a single stamp, LRC is read as plain lyrics, its metadata dropped")
    func noStamps() throws {
        let lyrics = try #require(LRCParser.parse("[ar:Someone]\nFirst line\n\nSecond <00:01.00>line"))
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["First line", "", "Second line"])
    }

    @Test("Every line at 0:00 is no timing at all")
    func allAtZero() throws {
        let lyrics = try #require(LRCParser.parse("[00:00.00]One\n[00:00.00]Two"))
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["One", "Two"])
    }

    @Test("Plain lyrics: stanzas one empty line apart, none around them")
    func plain() throws {
        let lyrics = try #require(LRCParser.plain(LyricsFixtures.dutchPlain))
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == [
            "De lantaarns gaan aan langs het water",
            "Jij fietst voor mij uit door de mist",
            "",
            "Hou me vast, de brug gaat open",
            "Hou me vast, de nacht is lang",
        ])
        let windows = try #require(LRCParser.plain("One  \r\nTwo\r\n"))
        #expect(windows.lines.map(\.text) == ["One", "Two"])
    }
}
