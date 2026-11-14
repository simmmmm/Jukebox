// Which line of timed lyrics is being sung: the one rule both platforms'
// lyrics follow (the iPhone's LyricsView, Linux's panel), here once.

import Foundation

extension Lyrics {
    /// The last line that has begun at `elapsed`, a quarter second early: the
    /// line lights as it is sung, not after (the players' clocks tick every
    /// half second). Nil before the first line, and for untimed lyrics.
    public func lineIndex(at elapsed: TimeInterval) -> Int? {
        let now = elapsed + 0.25
        var found: Int?
        for (index, line) in lines.enumerated() {
            guard let start = line.start else { continue }
            if start > now { break }
            found = index
        }
        return found
    }
}
