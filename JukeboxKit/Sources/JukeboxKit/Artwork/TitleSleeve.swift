// A sleeve for an album the server has no cover for: the photographer, 19
// November 2026, "Ook emptystate van een album waarvan we de art niet hebben
// ff een leukere plaathoes maken met de naam er op groot en eronder de
// artiest maar wel dat t altijd past". So a printed sleeve, as a typographic
// record cover: one flat ground, the album's title in the serif as large as
// it fits, the artist small under it in the sans, both at the margin.
//
// The rule is here, Foundation only, so every client sets the same sleeve:
// SwiftUI on Apple (ArtworkView.swift's TitleSleeveFace), cairo and Pango on
// Linux (Drawings.swift's Draw.titleSleeve). Each measures with its own
// fonts (New York there, the system's serif here), so a line may break a
// word earlier on one than on the other; the steps, limits and colours are
// the same.
//
//   1. The words: the album's title and artist. No title: the artist is the
//      title. Neither: the ground alone, a plain sleeve.
//   2. The print: one of five, by a stable hash (FNV-1a) of the album's id,
//      so the same album is the same sleeve on every screen and neighbours
//      mostly differ. Flat grounds of the brand's own (Cabinet, Land, its
//      grooves played, the raised paper, a card) with Glow, Copper, Paper or
//      Ink as the ink; the same by day and by night, as a printed sleeve is.
//   3. Inside a margin of 8% of the side, the title at the largest of eight
//      steps (40% of the inner side down to 10.5%, none under 7 points) at
//      which it wraps on its words into at most four lines and, with the
//      artist under it, fits the square.
//   4. None fits: the smallest step, words that are too wide broken between
//      their characters (graphemes, so an emoji or an accent stays whole),
//      and what is still too much cut short with an ellipsis.
//   5. The artist on one line under the title, cut short with an ellipsis;
//      only on a sleeve of 96 points or more, at 7.5% of the inner side (8
//      at least). Smaller, it would be a smudge.
//   6. A thumbnail under 56 points (a row, the player's bar): the title
//      alone, in at most two lines on its words; if it does not fit, its
//      first letter, large.
//
// CJK has no spaces: a line may break before or after any ideograph or
// kana, as those scripts break.

import Foundation

public enum TitleSleeve {
    // MARK: The words

    public struct Words: Hashable, Sendable {
        public let title: String
        public let artist: String
        /// What picks the print: the album's id, so a song's sleeve is its
        /// album's.
        public let key: String

        public init(title: String, artist: String, key: String) {
            let title = Self.clean(title), artist = Self.clean(artist)
            // No title: the artist is the title (1).
            self.title = title.isEmpty ? artist : title
            self.artist = title.isEmpty ? "" : artist
            self.key = key
        }

        public init(album: Album) {
            self.init(title: album.name, artist: album.artistLine, key: album.id)
        }

        /// The song's album's sleeve; a song on no album, its own name.
        public init(track: Track) {
            let album = track.albumName.flatMap { $0.isEmpty ? nil : $0 }
            self.init(title: album ?? track.name, artist: track.albumArtist?.name ?? track.artistLine,
                      key: track.albumID ?? album ?? track.id)
        }

        /// A playlist without an image: its name.
        public init(playlist: Playlist) {
            self.init(title: playlist.name, artist: "", key: playlist.id)
        }

        public var isEmpty: Bool { title.isEmpty }

        private static func clean(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }

    // MARK: The print

    /// A ground and its two inks, each 0xRRGGBB.
    public struct Print: Hashable, Sendable {
        public let ground: UInt32
        public let title: UInt32
        public let artist: UInt32
    }

    /// The brand's grounds with its inks (BRAND.md, "Colours"): Glow on
    /// Cabinet, Paper on Land and on its grooves played, Copper on the
    /// raised paper, Ink on a card. Every ink 4.5:1 or more on its ground
    /// (TitleSleeveTests).
    public static let prints: [Print] = [
        Print(ground: 0x1E0A07, title: 0xFFB54D, artist: 0xE9DFD3),
        Print(ground: 0x211A17, title: 0xF6F3EE, artist: 0xC9BFB4),
        Print(ground: 0x3F3127, title: 0xF6F3EE, artist: 0xD9CFC4),
        Print(ground: 0xF1EDE6, title: 0xA84A17, artist: 0x2A1505),
        Print(ground: 0xE3D9C6, title: 0x2A1505, artist: 0x5A4636),
    ]

    public static func print(for key: String) -> Print {
        prints[Int(stableHash(key) % UInt64(prints.count))]
    }

    /// FNV-1a: the same number for the same key on every client and at
    /// every launch (Swift's own hash is seeded anew each time).
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return hash
    }

    // MARK: The measures

    /// The margin, a share of the side.
    public static let margin = 0.08
    /// The title's sizes, largest first, as shares of the inner side.
    public static let steps: [Double] = [0.40, 0.33, 0.27, 0.22, 0.18, 0.15, 0.125, 0.105]
    /// No title under this, in points.
    public static let leastTitle = 7.0
    public static let maxLines = 4
    /// A title line's height, of its size: set close, as on a sleeve.
    public static let leading = 1.08
    /// The artist: a share of the inner side, at least `leastArtist`
    /// points, and only from `artistSide`.
    public static let artistShare = 0.075
    public static let leastArtist = 8.0
    public static let artistSide = 96.0
    public static let artistLeading = 1.25
    /// Under this side, a thumbnail (6).
    public static let tinySide = 56.0
    public static let tinyLines = 2
    /// The first letter's size, of the inner side.
    public static let initialShare = 0.6
    public static let ellipsis = "\u{2026}"

    public enum Face: Sendable {
        /// The serif, regular: the title.
        case title
        /// The sans, regular: the artist.
        case artist
    }

    /// How wide `text` is in `face` at `size` points, as the client draws it.
    public typealias Measure = (_ text: String, _ face: Face, _ size: Double) -> Double

    /// Where everything goes on a sleeve of `side` points, from its top left
    /// corner. Each title line is drawn as it is, one line, from its top.
    public struct Layout: Equatable, Sendable {
        public var print: Print
        public var padding: Double
        public var titleSize: Double
        public var lineHeight: Double
        public var lines: [String]
        /// Nil: no artist line.
        public var artist: String?
        public var artistSize: Double
        /// The artist line's top.
        public var artistTop: Double
        /// The title is its first letter (6).
        public var isInitial: Bool

        public func lineTop(_ index: Int) -> Double { padding + Double(index) * lineHeight }
    }

    public static func layout(_ words: Words, side: Double, measure: Measure) -> Layout {
        let padding = side * margin
        let inner = side - 2 * padding
        let tiny = side < tinySide
        var layout = Layout(print: print(for: words.key), padding: padding, titleSize: 0, lineHeight: 0,
                            lines: [], artist: nil, artistSize: 0, artistTop: 0, isInitial: false)
        guard !words.isEmpty, inner > 0 else { return layout }

        let showsArtist = !tiny && side >= artistSide && !words.artist.isEmpty
        let artistSize = max(leastArtist, inner * artistShare)
        let tokens = Self.tokens(words.title)
        let sizes = steps.map { $0 * inner }.filter { $0 >= leastTitle }
        let lineLimit = tiny ? tinyLines : maxLines

        /// The room the title has at `size`, under it the artist.
        func titleRoom(_ size: Double) -> Double {
            showsArtist ? inner - gap(size, artistSize) - artistSize * artistLeading : inner
        }

        func place(_ lines: [String], size: Double) {
            layout.lines = lines
            layout.titleSize = size
            layout.lineHeight = size * leading
            if showsArtist {
                layout.artist = fitted(words.artist, face: .artist, size: artistSize, width: inner, measure: measure)
                layout.artistSize = artistSize
                layout.artistTop = padding + Double(lines.count) * size * leading + gap(size, artistSize)
            }
        }

        // 3: the largest step at which it wraps on its words.
        for size in sizes {
            guard let lines = wrap(tokens, size: size, width: inner, breakWords: false, measure: measure),
                  lines.count <= lineLimit, Double(lines.count) * size * leading <= titleRoom(size) else { continue }
            place(lines, size: size)
            return layout
        }

        // 6: a thumbnail's first letter.
        if tiny || sizes.isEmpty {
            let first = words.title.first.map { String($0).uppercased() } ?? ""
            let size = inner * initialShare
            layout.lines = [first]
            layout.titleSize = size
            layout.lineHeight = size * leading
            layout.isInitial = true
            return layout
        }

        // 4: the smallest step, words broken, then cut short.
        let size = sizes[sizes.count - 1]
        var lines = wrap(tokens, size: size, width: inner, breakWords: true, measure: measure) ?? []
        let room = max(1, min(lineLimit, Int((titleRoom(size) / (size * leading)).rounded(.down))))
        if lines.count > room {
            lines = Array(lines.prefix(room - 1))
                + [cut(lines[room - 1], face: .title, size: size, width: inner, measure: measure)]
        }
        place(lines, size: size)
        return layout
    }

    static func gap(_ titleSize: Double, _ artistSize: Double) -> Double {
        max(artistSize * 0.6, titleSize * 0.25)
    }

    // MARK: Wrapping

    /// A run of the title that is never broken on its words: a word, or one
    /// ideograph. `spaced`: a space stands between it and the one before.
    struct Token: Equatable {
        var text: String
        var spaced: Bool
    }

    static func tokens(_ title: String) -> [Token] {
        var tokens: [Token] = []
        var word = ""
        var spaced = false
        func flush() {
            if !word.isEmpty { tokens.append(Token(text: word, spaced: spaced && !tokens.isEmpty)) }
            word = ""
            spaced = false
        }
        for character in title {
            if character.isWhitespace {
                flush()
                spaced = true
            } else if isIdeographic(character) {
                let wasSpaced = spaced
                flush()
                tokens.append(Token(text: String(character), spaced: wasSpaced && !tokens.isEmpty))
            } else {
                word.append(character)
            }
        }
        flush()
        return tokens
    }

    /// Han, kana and the CJK punctuation and full-width forms: scripts
    /// that break between any two characters.
    static func isIdeographic(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first?.value else { return false }
        return (0x3000...0x30FF).contains(scalar) || (0x3400...0x4DBF).contains(scalar)
            || (0x4E00...0x9FFF).contains(scalar) || (0xF900...0xFAFF).contains(scalar)
            || (0xFF00...0xFFEF).contains(scalar) || (0x20000...0x2FFFF).contains(scalar)
    }

    /// The tokens in lines no wider than `width`, greedily. A token wider
    /// than a line: nil, or with `breakWords` broken between its characters.
    static func wrap(_ tokens: [Token], size: Double, width: Double, breakWords: Bool, measure: Measure) -> [String]? {
        var lines: [String] = []
        var current = ""
        for token in tokens {
            if measure(token.text, .title, size) > width {
                guard breakWords else { return nil }
                if !current.isEmpty { lines.append(current) }
                current = ""
                for character in token.text {
                    let longer = current + String(character)
                    if current.isEmpty || measure(longer, .title, size) <= width {
                        current = longer
                    } else {
                        lines.append(current)
                        current = String(character)
                    }
                }
                continue
            }
            if current.isEmpty {
                current = token.text
                continue
            }
            let longer = current + (token.spaced ? " " : "") + token.text
            if measure(longer, .title, size) <= width {
                current = longer
            } else {
                lines.append(current)
                current = token.text
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// `text` on one line: as it is if it fits, else cut short.
    static func fitted(_ text: String, face: Face, size: Double, width: Double, measure: Measure) -> String {
        measure(text, face, size) <= width ? text : cut(text, face: face, size: size, width: width, measure: measure)
    }

    /// `text` shortened, a character at a time, until it fits with an ellipsis.
    static func cut(_ text: String, face: Face, size: Double, width: Double, measure: Measure) -> String {
        var kept = text
        while !kept.isEmpty, measure(kept + ellipsis, face, size) > width {
            kept.removeLast()
            while kept.last?.isWhitespace == true { kept.removeLast() }
        }
        return kept + ellipsis
    }
}
