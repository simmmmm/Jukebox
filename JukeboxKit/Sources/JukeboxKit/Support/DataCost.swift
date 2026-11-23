// What a network that costs data changes, on every client: the mobile
// network, a phone's hotspot or Low Data Mode on Apple's systems, a metered
// connection on Linux. "streaming data kosten optimaliseren" (the
// photographer, 24 November 2026). docs/DATA.md has the numbers.

import Foundation

public enum DataCost {
    /// Settings' quality for the network the song starts on.
    public static func quality(expensive: Bool, wifi: StreamQuality, cellular: StreamQuality) -> StreamQuality {
        expensive ? cellular : wifi
    }

    /// The library is read again on a return to the window this long after
    /// the last read: a read costs what a launch's does, not every glance.
    public static let libraryRefreshAfter: TimeInterval = 5 * 60

    /// Whether a return to the window reads the whole library again. Never
    /// on a network that costs: a read of 20 000 songs is about 10 MB, and
    /// a phone comes back to the front many times an hour. A launch and
    /// pulling to refresh still read it. Nothing before the first read.
    public static func libraryRefreshIsDue(lastAsked: Date?, now: Date, expensive: Bool) -> Bool {
        guard let lastAsked, !expensive else { return false }
        return now.timeIntervalSince(lastAsked) >= libraryRefreshAfter
    }

    /// How far ahead of the playhead the player fetches on a network that
    /// costs, in seconds; nil leaves it to the player. A skipped song then
    /// costs at most this much of it, not the whole file AVPlayer would
    /// fetch, and the next song in the queue the same. A minute rides out
    /// a tunnel, and is longer than the longest crossfade (12 s).
    public static func forwardBuffer(expensive: Bool) -> TimeInterval? {
        expensive ? 60 : nil
    }
}
