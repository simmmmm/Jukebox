// How two names are known to be the same artist, genre or title: Jellyfin,
// Last.fm and a file's tags spell them differently ("The Beatles" and
// "Beatles", "Beyoncé" and "Beyonce", "Simon & Garfunkel" and "Simon and
// Garfunkel", "Song (feat. X)" and "Song"). One key for all of them, so the
// radio can match Last.fm's similar artists to the library.

import Foundation

public enum NameKey {
    /// An artist's key: folded, without a leading "the", "&" as "and",
    /// punctuation and spaces gone.
    public static func artist(_ name: String) -> String {
        var s = fold(name)
        if s.hasPrefix("the ") { s.removeFirst(4) }
        let key = squeeze(s)
        guard key.isEmpty else { return key }
        // A name of punctuation only ("!!!", "†‡†") squeezes to nothing, and
        // all such artists would share one key and one station. Its own
        // spelling, lower case and without spaces, is the key instead — the
        // same rule as LibrarySnapshot's, so Artist.key and the snapshot agree.
        return String(String.UnicodeScalarView(name.lowercased().unicodeScalars.filter { !$0.properties.isWhitespace }))
    }

    /// A genre's key: "Hip-Hop", "hip hop" and "HipHop" are one.
    public static func genre(_ name: String) -> String {
        squeeze(fold(name))
    }

    /// A track title's key: without what is in brackets ("(Remastered
    /// 2011)", "[Live]") and without a "feat." part.
    public static func title(_ name: String) -> String {
        var s = fold(name)
        for (open, close) in [("(", ")"), ("[", "]")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                s.removeSubrange(a.lowerBound..<b.upperBound)
            }
        }
        for marker in [" feat. ", " feat ", " ft. ", " featuring ", " - "] {
            if let r = s.range(of: marker) { s = String(s[..<r.lowerBound]) }
        }
        return squeeze(s)
    }

    /// Lower case, without diacritics, "&" and "+" as "and".
    static func fold(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        return folded
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: " + ", with: " and ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Letters and digits only.
    static func squeeze(_ s: String) -> String {
        String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
