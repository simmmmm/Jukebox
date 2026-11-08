// LRC, the text format of synced lyrics (LRCLIB's `syncedLyrics`, the .lrc
// files beside songs), as the kit's Lyrics. Read by hand rather than by
// regular expression: every form in the wild is a few characters to tell
// apart, and a song's lyrics are a few hundred lines.
//
// What it reads:
//   [01:23.45] a line            one time stamp; [mm:ss], [mm:ss.x…] and
//                                [mm:ss:xx] (centiseconds after a colon)
//   [00:12.00][01:30.00] chorus  several stamps: the line at each of them
//   [ar:…] [ti:…] [length:…]     metadata: dropped
//   [offset:+250]                milliseconds; plus shows the lines sooner
//   <00:12.30>word <00:12.80>…   word-level stamps (Enhanced LRC): removed,
//                                the words kept as one line
//   [01:40.00]                   an empty line: kept as a pause, see below
//
// An empty timed line is kept: it is where the singing stops, and Now
// Playing shows it as a beat ("♪"), as Music does. Without it, the last
// line sung before a long instrumental stays lit through all of it. Two
// empty lines in a row are one pause.

import Foundation

public enum LRCParser {
    /// LRC text as timed lines, sorted by time. Text without a single time
    /// stamp is read as plain lyrics instead, its metadata lines dropped.
    /// Nil when nothing is left.
    public static func parse(_ text: String) -> Lyrics? {
        var timed: [(start: TimeInterval, order: Int, text: String)] = []
        var untimed: [String] = []
        var offset: TimeInterval = 0

        for raw in lines(of: text) {
            let read = readLine(raw)
            switch read {
            case let .timed(stamps, words):
                for stamp in stamps {
                    timed.append((stamp, timed.count, words))
                }
            case let .metadata(key, value):
                if key == "offset", let milliseconds = Double(value.replacingOccurrences(of: "+", with: "")) {
                    offset = milliseconds / 1000
                }
            case let .untimed(words):
                untimed.append(words)
            }
        }

        guard !timed.isEmpty else { return plain(untimed.joined(separator: "\n")) }

        // Sorted by time, the file's order where two lines share a stamp
        // (a duet's two voices, written one under the other).
        timed.sort { $0.start != $1.start ? $0.start < $1.start : $0.order < $1.order }
        var result: [Lyrics.Line] = []
        for line in timed {
            let start = max(0, line.start - offset)
            if line.text.isEmpty, let last = result.last, last.text.isEmpty { continue }
            result.append(Lyrics.Line(start: start, text: line.text))
        }
        // Only pauses: no words at all.
        guard result.contains(where: { !$0.text.isEmpty }) else { return nil }
        // Every line at 0:00 is no timing at all, as Jellyfin's rule has it
        // (JellyfinDTO's asLyrics). The stamps as written decide, not the
        // times after the offset: "[offset:-500]" on such a file would put
        // every line at 0.5 s, and light only the last.
        if result.count > 1, timed.allSatisfy({ $0.start == 0 }) {
            return plain(result.map(\.text).joined(separator: "\n"))
        }
        return Lyrics(lines: result)
    }

    /// Plain lyrics as untimed lines: the text as written, stanzas kept
    /// apart by one empty line, the empty lines around it gone. Nil when
    /// there are no words.
    public static func plain(_ text: String) -> Lyrics? {
        var result: [Lyrics.Line] = []
        for raw in lines(of: text) {
            let words = raw.trimmingCharacters(in: .whitespaces)
            if words.isEmpty {
                // One empty line between stanzas, never two, never first.
                guard let last = result.last, !last.text.isEmpty else { continue }
            }
            result.append(Lyrics.Line(start: nil, text: words))
        }
        while let last = result.last, last.text.isEmpty { result.removeLast() }
        return result.isEmpty ? nil : Lyrics(lines: result)
    }

    // MARK: - One line

    enum ReadLine: Equatable {
        case timed([TimeInterval], String)
        case metadata(String, String)
        case untimed(String)
    }

    /// The stamps at the start of a line, and its words without word-level
    /// stamps; or its metadata tag; or, with no stamp, its words as they are.
    static func readLine(_ line: Substring) -> ReadLine {
        // A byte order mark at the start of a line, not only of the file:
        // files joined into one, or written twice over by a converter.
        var rest = line.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
        var stamps: [TimeInterval] = []
        while rest.first == "[", let close = rest.firstIndex(of: "]") {
            let inner = rest[rest.index(after: rest.startIndex)..<close]
            if let time = time(inner) {
                stamps.append(time)
                rest = rest[rest.index(after: close)...].drop(while: \.isWhitespace)
                continue
            }
            if stamps.isEmpty, let tag = metadata(inner) {
                return .metadata(tag.key, tag.value)
            }
            break
        }
        let words = stripWordStamps(rest)
        return stamps.isEmpty ? .untimed(words) : .timed(stamps, words)
    }

    /// "ar:Someone", "offset:+250", "length: 03:45": a key of letters (or
    /// "#", a comment), a colon, anything.
    static func metadata(_ inner: Substring) -> (key: String, value: String)? {
        guard let colon = inner.firstIndex(of: ":") else { return nil }
        let key = inner[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, key == "#" || key.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let value = inner[inner.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    /// "01:23.45" as 83.45 seconds. Minutes of any length ([105:02.00] in a
    /// long mix), seconds of one or two digits, a fraction after ".", ","
    /// or a second ":" read as a decimal fraction ("5" is half a second,
    /// "45" and "450" are the same).
    static func time(_ inner: Substring) -> TimeInterval? {
        let parts = inner.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3, let minutes = digits(parts[0], max: 4) else { return nil }
        let seconds: Substring
        var fraction: Substring = ""
        if parts.count == 3 {
            seconds = parts[1]
            fraction = parts[2]
        } else if let mark = parts[1].firstIndex(where: { $0 == "." || $0 == "," }) {
            seconds = parts[1][..<mark]
            fraction = parts[1][parts[1].index(after: mark)...]
        } else {
            seconds = parts[1]
        }
        guard let whole = digits(seconds, max: 2) else { return nil }
        var value = Double(minutes * 60 + whole)
        if !fraction.isEmpty {
            guard let part = digits(fraction, max: 6) else { return nil }
            value += Double(part) / pow(10, Double(fraction.count))
        }
        return value
    }

    /// One to `max` ASCII digits, as a number.
    static func digits(_ text: Substring, max: Int) -> Int? {
        guard !text.isEmpty, text.count <= max, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    /// The longest a stamp's brackets hold: "<9999:59.999999>" and a
    /// space or two around it.
    static let longestStamp = 20

    /// The words without "<00:12.30>" stamps (and the rare "[00:12.30]"
    /// inside a line), runs of spaces as one.
    static func stripWordStamps(_ words: Substring) -> String {
        var out = ""
        var rest = words[...]
        while let open = rest.firstIndex(where: { $0 == "<" || $0 == "[" }) {
            let closer: Character = rest[open] == "<" ? ">" : "]"
            // Its closer looked for only as far as a stamp can reach. When
            // each looked to the end of the line, a line of 20 000 "<" took
            // 5.2 s and 20 000 "<" before one ">" 16 s; now 0.04 s (debug
            // build, LRCParserTests). LRCLIB's lyrics are typed by anyone.
            guard let close = rest[open...].prefix(Self.longestStamp + 2).firstIndex(of: closer),
                  time(rest[rest.index(after: open)..<close]) != nil else {
                out += rest[...open]
                rest = rest[rest.index(after: open)...]
                continue
            }
            out += rest[..<open]
            out += " "
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lines split on "\n", "\r\n" and "\r", without a byte order mark.
    static func lines(of text: String) -> [Substring] {
        var text = text[...]
        if text.first == "\u{FEFF}" { text = text.dropFirst() }
        // "\r\n" is one Character in Swift, so this splits it once.
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }
}
