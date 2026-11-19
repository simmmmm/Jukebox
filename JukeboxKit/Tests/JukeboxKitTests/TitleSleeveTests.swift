// TitleSleeve with a made-up measure: a letter 0.55 of the size wide, a
// space 0.25, an ideograph or an emoji a whole size. The sleeve always fits:
// every line within the margin, the lines and the artist inside the square,
// for long titles and one word, CJK, emoji, no title, at every side the
// apps draw a cover.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Artwork: a sleeve for an album without a cover")
struct TitleSleeveTests {
    static func measure(_ text: String, _ face: TitleSleeve.Face, _ size: Double) -> Double {
        text.reduce(0) { width, character in
            if character == " " { return width + 0.25 * size }
            if TitleSleeve.isIdeographic(character) || character.unicodeScalars.first!.properties.isEmojiPresentation {
                return width + size
            }
            return width + 0.55 * size
        }
    }

    func layout(_ title: String, _ artist: String = "Belle and Sebastian", side: Double = 200) -> TitleSleeve.Layout {
        TitleSleeve.layout(TitleSleeve.Words(title: title, artist: artist, key: title), side: side, measure: Self.measure)
    }

    /// Every line within the inner square, and everything above its foot.
    func expectFits(_ layout: TitleSleeve.Layout, side: Double, _ comment: Comment? = nil) {
        let inner = side - 2 * layout.padding
        for line in layout.lines {
            #expect(Self.measure(line, .title, layout.titleSize) <= inner + 0.001, comment)
        }
        #expect(layout.lines.count <= TitleSleeve.maxLines, comment)
        let titleFoot = layout.padding + Double(layout.lines.count) * layout.lineHeight
        #expect(titleFoot <= side - layout.padding + 0.001 || layout.isInitial, comment)
        if let artist = layout.artist {
            #expect(Self.measure(artist, .artist, layout.artistSize) <= inner + 0.001, comment)
            #expect(layout.artistTop >= titleFoot, comment)
            #expect(layout.artistTop + layout.artistSize * TitleSleeve.artistLeading <= side - layout.padding + 0.001, comment)
        }
    }

    static let sides: [Double] = [32, 40, 48, 56, 64, 96, 120, 160, 200, 260, 300, 600]
    static let titles = [
        "Stories from the City, Stories from the Sea",
        "Blue",
        "A",
        "Supercalifragilisticexpialidocious",
        "The Boy with the Arab Strap",
        "Songs in the Key of Life, Volume One and Volume Two, with the Extra Songs",
        "千と千尋の神隠し サウンドトラック",
        "🎸🔥 Live",
        "👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦",
        "Ágætis byrjun",
    ]

    @Test("Every title fits at every side")
    func alwaysFits() {
        for side in Self.sides {
            for title in Self.titles {
                expectFits(layout(title, side: side), side: side, "\(title) at \(side)")
            }
        }
    }

    @Test("A short title is set large, a long one smaller, on its words")
    func largestThatFits() {
        let short = layout("Blue")
        #expect(short.titleSize == TitleSleeve.steps[0] * 200 * 0.84)
        #expect(short.lines == ["Blue"])
        let long = layout("Stories from the City, Stories from the Sea")
        #expect(long.titleSize < short.titleSize)
        #expect((2...4).contains(long.lines.count))
        // Broken on its words: every word of the title whole on some line.
        #expect(long.lines.joined(separator: " ") == "Stories from the City, Stories from the Sea")
    }

    @Test("A word too long for any step is broken inside, then cut short")
    func breaksInsideAWord() {
        let one = layout("Supercalifragilisticexpialidocious")
        #expect(one.lines.count >= 2)
        #expect(one.lines.joined() == "Supercalifragilisticexpialidocious")
        let much = layout(String(repeating: "Antidisestablishmentarianism", count: 4), side: 120)
        #expect(much.lines.last?.hasSuffix(TitleSleeve.ellipsis) == true)
        expectFits(much, side: 120)
    }

    @Test("CJK breaks between ideographs; emoji stay whole")
    func scripts() {
        let cjk = layout("千と千尋の神隠しサウンドトラック")
        #expect(cjk.lines.count > 1)
        #expect(cjk.lines.joined() == "千と千尋の神隠しサウンドトラック")
        let family = "👨‍👩‍👧‍👦"
        let emoji = layout(String(repeating: family, count: 12), side: 120)
        for line in emoji.lines {
            for character in line.replacingOccurrences(of: TitleSleeve.ellipsis, with: "") {
                #expect(String(character) == family)
            }
        }
    }

    @Test("No title: the artist is the title; neither: a plain sleeve")
    func emptyTitle() {
        let artistOnly = layout("", "Sufjan Stevens")
        #expect(artistOnly.lines.joined(separator: " ") == "Sufjan Stevens")
        #expect(artistOnly.artist == nil)
        let nothing = layout("  ", "")
        #expect(nothing.lines.isEmpty)
        #expect(nothing.artist == nil)
    }

    @Test("Thumbnails: no artist line; a long title becomes its first letter")
    func thumbnails() {
        let blue = layout("Blue", side: 40)
        #expect(blue.artist == nil)
        #expect(blue.lines == ["Blue"])
        #expect(!blue.isInitial)
        let long = layout("stories from the City, Stories from the Sea", side: 40)
        #expect(long.isInitial)
        #expect(long.lines == ["S"])
        // From 96 the artist shows; under it not.
        #expect(layout("Blue", side: 95).artist == nil)
        #expect(layout("Blue", side: 96).artist == "Belle and Sebastian")
    }

    @Test("The artist is one line, cut short")
    func artistCut() {
        let sleeve = layout("Blue", String(repeating: "Godspeed You! Black Emperor ", count: 4), side: 160)
        #expect(sleeve.artist?.hasSuffix(TitleSleeve.ellipsis) == true)
        expectFits(sleeve, side: 160)
    }

    @Test("The print: the same for the same album, every ink readable on its ground")
    func prints() {
        // Pinned, so the clients and later builds agree: FNV-1a of the id.
        #expect(TitleSleeve.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(TitleSleeve.print(for: "4bd72c149d5469b943672ef90a6239e4") == TitleSleeve.print(for: "4bd72c149d5469b943672ef90a6239e4"))
        let picked = Set((0..<40).map { TitleSleeve.print(for: "album \($0)") })
        #expect(picked.count == TitleSleeve.prints.count)
        func color(_ hex: UInt32) -> AccentColor {
            AccentColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                        blue: Double(hex & 0xFF) / 255)
        }
        for print in TitleSleeve.prints {
            #expect(color(print.title).contrast(with: color(print.ground)) >= 4.5)
            #expect(color(print.artist).contrast(with: color(print.ground)) >= 4.5)
        }
    }

    @Test("A song's sleeve is its album's")
    func songsAlbum() {
        let album = Album(id: "a1", name: "If You're Feeling Sinister", artists: [ArtistRef(id: nil, name: "Belle and Sebastian")])
        let track = Track(id: "t1", name: "The Stars of Track and Field", albumID: "a1", albumName: "If You're Feeling Sinister",
                          artists: [ArtistRef(id: nil, name: "Belle and Sebastian")],
                          albumArtist: ArtistRef(id: nil, name: "Belle and Sebastian"))
        #expect(TitleSleeve.Words(album: album) == TitleSleeve.Words(track: track))
    }
}
