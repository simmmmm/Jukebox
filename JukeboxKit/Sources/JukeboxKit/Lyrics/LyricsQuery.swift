// What LRCLIB is asked for one song: its artist, title, album and length,
// cleaned of what a library's tags carry and LRCLIB's records do not. A
// track's credits are "A; B" on a library whose tags Jellyfin did not split,
// or "A feat. B"; its title may be "Song (feat. B)". LRCLIB files a song
// under its main artist and its own title, so those are what is sent, and
// nothing else of the listener's library leaves the phone.

import Foundation

public struct LyricsQuery: Sendable, Hashable {
    public var artist: String
    public var title: String
    /// Nil when the track has no album.
    public var album: String?
    /// Seconds; 0 when the server did not know.
    public var duration: TimeInterval

    /// Cleans what it is given: the main artist of "A; B" or "A feat. B",
    /// the title without its "feat." part.
    public init(artist: String, title: String, album: String? = nil, duration: TimeInterval) {
        self.artist = Self.mainArtist(artist)
        self.title = Self.titleWithoutGuests(title)
        let album = album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.album = album.isEmpty ? nil : album
        self.duration = duration.isFinite ? max(0, duration) : 0
    }

    /// The track's own first performer (on a compilation the album artist
    /// is "Various Artists", whom LRCLIB does not know), else the album's
    /// artist. Nil without an artist or a title to ask for.
    public init?(track: Track) {
        let performer = track.artists.first { !Self.isVarious($0.name) && !Self.mainArtist($0.name).isEmpty }
        let fallback = track.albumArtist.flatMap { Self.isVarious($0.name) ? nil : $0 }
        guard let artist = performer ?? fallback else { return nil }
        self.init(artist: artist.name, title: track.name, album: track.albumName, duration: track.duration)
        guard !self.artist.isEmpty, !self.title.isEmpty else { return nil }
    }

    /// Whole seconds, as LRCLIB takes them (it matches within ±2).
    public var seconds: Int { Int(duration.rounded()) }

    /// The title for LRCLIB's search, which matches words: also without what
    /// is in brackets or after " - " ("Song (Remastered 2011)", "Song - Live
    /// at Paradiso"), so a record of the plain song is found and then told
    /// apart by its length. The title itself if that leaves nothing.
    public var searchTitle: String {
        var s = title
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                s.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        if let dash = s.range(of: " - ") { s = String(s[..<dash.lowerBound]) }
        let cleaned = Self.squeezeSpaces(s)
        return cleaned.isEmpty ? title : cleaned
    }

    /// What the cache keeps the answer under: the four fields, lower case,
    /// the length in whole seconds.
    public var cacheKey: String {
        [artist, title, album ?? "", String(seconds)]
            .map { $0.lowercased() }
            .joined(separator: "|")
    }

    // MARK: - Cleaning

    /// Where a list of artists is joined, and where a guest's part begins.
    /// Not "&", "and", "," or "/": "Simon & Garfunkel", "Earth, Wind & Fire"
    /// and "AC/DC" are one artist each.
    static let artistBreaks = [";", " feat. ", " feat ", " ft. ", " featuring ", " x "]

    static func mainArtist(_ name: String) -> String {
        squeezeSpaces(cut(name, atFirstOf: artistBreaks))
    }

    /// "Song (feat. B)", "Song [ft. B]", "Song feat. B" as "Song". Other
    /// brackets stay: "(Live)" is another recording, with other timing.
    static func titleWithoutGuests(_ title: String) -> String {
        var s = title
        let guests = ["feat.", "feat ", "ft.", "featuring ", "with "]
        for (open, close) in [("(", ")"), ("[", "]")] {
            var searchFrom = s.startIndex
            while let a = s.range(of: open, range: searchFrom..<s.endIndex),
                  let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                let inside = s[a.upperBound..<b.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                if guests.contains(where: { inside.hasPrefix($0) }) {
                    s.removeSubrange(a.lowerBound..<b.upperBound)
                    searchFrom = s.startIndex
                } else {
                    searchFrom = b.upperBound
                }
            }
        }
        return squeezeSpaces(cut(s, atFirstOf: [" feat. ", " feat ", " ft. ", " featuring "]))
    }

    /// The text before the first of `markers`, in any case.
    static func cut(_ text: String, atFirstOf markers: [String]) -> String {
        var end = text.endIndex
        for marker in markers {
            if let r = text.range(of: marker, options: .caseInsensitive), r.lowerBound < end {
                end = r.lowerBound
            }
        }
        return String(text[..<end])
    }

    static func isVarious(_ name: String) -> Bool {
        let key = NameKey.artist(name)
        return key == "variousartists" || key == "various" || key == "va"
    }

    static func squeezeSpaces(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
