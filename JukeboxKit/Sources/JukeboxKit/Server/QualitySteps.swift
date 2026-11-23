// Adjust to the Connection: the quality chosen in Settings is the target,
// and while the network is too slow for it the next songs stream lower,
// climbing back once it holds. "Kan je ook zo maken dat de kwaliteit die je
// kiest het doel is, maar je ook lager kan krijgen met slechter internet?
// Misschien met een vinkje erbij" (the photographer, 24 November 2026).
//
// Per song, decided by the app: Jellyfin's HLS master has one variant, so
// there is no adaptive HLS to lean on (docs/SERVERS.md, "Adjust to the
// Connection"). The queue (PlayQueue) tells this what the engine waits for;
// this says what to ask the next stream at. Pure: the clock is a parameter.

import Foundation

public struct QualitySteps: Sendable, Equatable {
    /// Steps below the target, 0 at it.
    public private(set) var down = 0
    /// When the wait still going began, and whether it began mid-song.
    private var waitSince: Date?
    private var waitMidSong = false
    /// A slow sign in the song playing: at most one step down for it.
    private var slowThisSong = false
    /// Streamed songs in a row without a slow sign, since the last step.
    private var cleanSongs = 0
    private var hadSong = false
    /// The target last asked for, and whether the server makes Opus: a
    /// new target starts again at it.
    private var target: StreamQuality?
    private var opus = false

    /// A transcode's own start is about 2 s; AVPlayer waiting on HLS over
    /// a slow link never starts at all (30 s and more, measured).
    public static let slowStart: TimeInterval = 8
    /// Clean songs before one step back up.
    public static let climbAfter = 3

    public init() {}

    /// What to ask the next stream at: `target`, or a step or two lower,
    /// each about half the data. 128 kbit/s is the floor: Efficient (Opus)
    /// where the server makes it, Low elsewhere.
    public mutating func quality(for target: StreamQuality, opus: Bool) -> StreamQuality {
        if target != self.target || opus != self.opus {
            reset()
            self.target = target
            self.opus = opus
        }
        let ladder = Self.ladder(target, opus: opus)
        return ladder[min(down, ladder.count - 1)]
    }

    /// The engine began to wait. `midSong`: it had played this song a few
    /// seconds since it was loaded. True when this stepped down.
    public mutating func waitBegan(_ now: Date, midSong: Bool) -> Bool {
        guard waitSince == nil else { return false }
        waitSince = now
        waitMidSong = midSong
        return midSong ? slow() : false
    }

    /// The wait is over (it plays again, or the song was left while it
    /// waited). A start that took `slowStart` or more is a slow sign.
    /// True when this stepped down.
    public mutating func waitEnded(_ now: Date) -> Bool {
        guard let since = waitSince else { return false }
        waitSince = nil
        guard !waitMidSong, now.timeIntervalSince(since) >= Self.slowStart else { return false }
        return slow()
    }

    /// A streamed song began. The one before it counts as clean if it gave
    /// no slow sign; after `climbAfter` of those, one step back up. A wait
    /// still going (the engine moved on by itself) is the new song's now.
    public mutating func songBegan(_ now: Date) {
        if hadSong, !slowThisSong { cleanSongs += 1 }
        hadSong = true
        slowThisSong = false
        if waitSince != nil {
            waitSince = now
            waitMidSong = false
        }
        if cleanSongs >= Self.climbAfter, down > 0 {
            down -= 1
            cleanSongs = 0
        }
    }

    /// Back to the target: the network changed, or the target did.
    public mutating func reset() {
        self = QualitySteps()
    }

    private mutating func slow() -> Bool {
        cleanSongs = 0
        guard !slowThisSong else { return false }
        slowThisSong = true
        let floor = target.map { Self.ladder($0, opus: opus).count - 1 } ?? 2
        guard down < floor else { return false }
        down += 1
        return true
    }

    /// The target, then each step down, never above the target.
    static func ladder(_ target: StreamQuality, opus: Bool) -> [StreamQuality] {
        let floor: StreamQuality = opus ? .efficient : .low
        switch target {
        case .original, .high: return [target, .normal, floor]
        case .normal: return [.normal, floor]
        case .efficient, .low: return [target]
        }
    }
}
