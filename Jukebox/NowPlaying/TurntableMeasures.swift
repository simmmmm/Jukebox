// Now Playing's measures, as plain arithmetic (SleeveRecord.swift and
// NowPlayingGround.swift draw them): where the playing song lies on its
// album; the giant record under the page, sketch D2's "side as land"; where
// the sleeve and its record go; how fast things turn, all in one place; and
// the clock that turns them.
//
// The photographer, 8 November 2026, of sketch E: "Dus ik denk dat d1 en d2
// vooral d2 het best gaan werken. D1 is reduced motion/batterij besparing d2
// normaal. F1 toch net iets te extreem denk". So D2 is Now Playing: the
// album's side as a record far larger than the screen, its grooves sweeping
// across the page as a horizon, one band per song, the playing song's band
// starting under the sleeve. D1, the same page on a still wall, is
// NowPlayingGround's and CoverWall's.
//
// Foundation only, no SwiftUI, so that it is checked on Linux as well as
// built on the Mac: dev/turntable-test.sh compiles it as it is, with the
// app's settings, beside dev/turntable-test.swift. (The file keeps the
// turntable's name: the record player it measured before D2 is gone, the
// album's side it worked out is not.)

import Foundation

// MARK: - The album's side

/// One of an album's songs, as the record needs it.
nonisolated struct TurntableSong: Equatable, Sendable {
    let id: String
    /// Its disc; nil counts as the first, as the library sorts them
    /// (LibraryIndex.inDiscOrder).
    let disc: Int?
    /// Seconds; 0 when the library does not know.
    let length: Double

    init(id: String, disc: Int?, length: Double) {
        self.id = id
        self.disc = disc
        self.length = length
    }
}

/// Where the playing song lies on its album. The songs of the playing
/// song's disc, in disc and track order, are bands from the outer groove
/// (the first song) to the run-out by the label (the last), each as wide as
/// the song is long: on the record half out of the sleeve, and on the land
/// under the page, whose playing band starts under the sleeve.
nonisolated struct TurntableSide: Equatable, Sendable {
    /// Where one song ends and the next begins, each 0 … 1 of the way from
    /// the outer groove to the label: one fewer than the songs.
    let bands: [Double]
    /// The playing song's band: where it begins and where it ends.
    let start: Double
    let end: Double
    /// The disc's number when the album has more than one ("Disc 2"); nil
    /// when it has one.
    let disc: Int?

    init(bands: [Double], start: Double, end: Double, disc: Int?) {
        self.bands = bands
        self.start = start
        self.end = end
        self.disc = disc
    }

    /// A song alone (no album, or the only song of its disc): one band, the
    /// whole side.
    static let alone = TurntableSide(bands: [], start: 0, end: 1, disc: nil)

    /// The side of the song `id` among its album's songs, `album` in disc
    /// and track order (LibraryStore.tracks(inAlbum:)): its disc's songs
    /// only, as a record holds one disc. Nil — the song alone — when the
    /// song is not among them, when it is its disc's only song, or when no
    /// length on its disc is known.
    static func of(_ id: String, in album: [TurntableSong]) -> TurntableSide? {
        guard let playing = album.first(where: { $0.id == id }) else { return nil }
        let disc = playing.disc ?? 1
        let songs = album.filter { ($0.disc ?? 1) == disc }
        guard songs.count > 1, let index = songs.firstIndex(where: { $0.id == id }) else { return nil }
        // A song whose length the library does not know counts as the
        // disc's average, so its band is not squeezed to nothing.
        let known = songs.map(\.length).filter { $0 > 0 }
        guard !known.isEmpty else { return nil }
        let average = known.reduce(0, +) / Double(known.count)
        let lengths = songs.map { $0.length > 0 ? $0.length : average }
        let total = lengths.reduce(0, +)
        var bands: [Double] = []
        var before = 0.0
        for length in lengths.dropLast() {
            before += length
            bands.append(before / total)
        }
        let discs = Set(album.map { $0.disc ?? 1 })
        return TurntableSide(bands: bands,
                             start: index == 0 ? 0 : bands[index - 1],
                             end: index == bands.count ? 1 : bands[index],
                             disc: discs.count > 1 ? disc : nil)
    }
}

// MARK: - The land

/// One ring of the land: a groove, every fifth a little stronger as a
/// record's grooves catch the light unevenly; the faint light edge where a
/// song's grooves end and the smooth land before the next begins; the
/// run-out's edge by the giant label.
nonisolated struct LandRing: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case groove
        case strong
        case edge
        case runOut
    }

    let radius: CGFloat
    let kind: Kind

    init(radius: CGFloat, kind: Kind) {
        self.radius = radius
        self.kind = kind
    }
}

/// D2's ground: the album's side as a record far larger than the screen,
/// its centre below the screen and to the right, so its grooves cross the
/// page as gentle arcs, a horizon. One band of grooves per song of the
/// album, as wide as the song is long, a smooth land between two songs; the
/// playing song's band starts just above its title, under the sleeve, and
/// its grooves played so far are a tone lighter (NowPlayingGround). When the
/// next song plays, the land moves on one band, so the new song's band
/// starts where the last one's did.
///
/// The numbers are sketch E's (its D2, final.py): on the iPhone 17 Pro, 402
/// by 874, the record's grooves run from 1440 points from its centre to 420,
/// its centre 300 from the left, a groove every 5.2 points; on the iPad
/// sideways, 1180 by 820, from 1900 to 700, its centre 820 from the left,
/// every 5.6. Other screens take the same in proportion to their diagonal
/// (and the width, for the centre); the pitch is a texture, and stays.
nonisolated struct LandGeometry: Equatable, Sendable {
    /// The smooth land between two songs' grooves.
    static let land: CGFloat = 26
    /// The run-out's edge, this far inside the last song's grooves.
    static let runOut: CGFloat = 60
    /// How far the playing song's band starts above its title (sketch E:
    /// 28 points on the iPhone, 30 on the iPad).
    static let aboveTitle: CGFloat = 28
    /// The bitmap the land is drawn into, once per album and screen: at
    /// most 0.75 pixels a point (its grooves are 1.5 points wide, dark on
    /// dark; drawn at 0.71 and shown at 3 they are as clear as drawn at 3,
    /// a little softer) and at most 2900 pixels a side, 34 MB. A side of
    /// 2880 points (the iPhone 17 Pro's land) is 2160 pixels, 19 MB.
    static let bitmapDensity: CGFloat = 0.75
    static let bitmapMostPixels: CGFloat = 2900

    /// The outer groove (the first song's start) and the last song's end,
    /// from the centre.
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    /// The centre's distance from the screen's left edge.
    let centerX: CGFloat
    /// From one groove to the next.
    let pitch: CGFloat

    init(outerRadius: CGFloat, innerRadius: CGFloat, centerX: CGFloat, pitch: CGFloat) {
        self.outerRadius = outerRadius
        self.innerRadius = innerRadius
        self.centerX = centerX
        self.pitch = pitch
    }

    /// For a screen of `size`, upright (`wide` false: the iPhone, the iPad
    /// upright) or the iPad sideways.
    init(screen size: CGSize, wide: Bool) {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let diagonal = (width * width + height * height).squareRoot()
        if wide {
            // 1180 by 820: a diagonal of 1437.
            self.init(outerRadius: diagonal * 1900 / 1437, innerRadius: diagonal * 700 / 1437,
                      centerX: width * 820 / 1180, pitch: 5.6)
        } else {
            // 402 by 874: a diagonal of 962.
            self.init(outerRadius: diagonal * 1440 / 962, innerRadius: diagonal * 420 / 962,
                      centerX: width * 300 / 402, pitch: 5.2)
        }
    }

    /// The record's whole width, in points: the bitmap's side.
    var diameter: CGFloat { outerRadius * 2 }

    /// Pixels a point for the bitmap.
    var bitmapScale: CGFloat {
        min(Self.bitmapDensity, Self.bitmapMostPixels / max(1, diameter))
    }

    /// The radius of a place on the side, 0 (the first song's start) … 1
    /// (the last song's end).
    func radius(at place: Double) -> CGFloat {
        let p = CGFloat(min(1, max(0, place)))
        return outerRadius - (outerRadius - innerRadius) * p
    }

    /// Where the centre goes, down the screen, for the band that starts at
    /// `start` to pass through `anchor`: the land moves, the anchor stays.
    func centerY(anchor: CGPoint, start: Double) -> CGFloat {
        let r = radius(at: start)
        let dx = anchor.x - centerX
        return anchor.y + max(0, r * r - dx * dx).squareRoot()
    }

    /// Every ring of the side whose songs end at `bands` (TurntableSide;
    /// none: one song), outermost first.
    func rings(bands: [Double]) -> [LandRing] {
        let bounds = [0] + bands + [1]
        var rings: [LandRing] = []
        for k in 0..<(bounds.count - 1) {
            let isLast = k == bounds.count - 2
            for (i, r) in grooves(from: bounds[k], to: bounds[k + 1]).enumerated() {
                rings.append(LandRing(radius: r, kind: i.isMultiple(of: 5) ? .strong : .groove))
            }
            if !isLast {
                rings.append(LandRing(radius: radius(at: bounds[k + 1]) + Self.land / 2 - 1, kind: .edge))
            }
        }
        rings.append(LandRing(radius: innerRadius - Self.runOut, kind: .runOut))
        return rings
    }

    /// The grooves of the song from `start` to `end`, outermost first: from
    /// half the land inside its start (none above the first song) to half
    /// the land short of its end (none below the last).
    func grooves(from start: Double, to end: Double) -> [CGFloat] {
        let top = radius(at: start) - (start > 0 ? Self.land / 2 : 0)
        let bottom = radius(at: end) + (end < 1 ? Self.land / 2 : 0)
        var radii: [CGFloat] = []
        var r = top
        while r > bottom {
            radii.append(r)
            r -= pitch
        }
        return radii
    }

    /// How many of the song's grooves are played with the song `progress`
    /// (0 … 1) of the way through: those a groove's place in the band has
    /// reached. Counted in whole grooves, so the lighter grooves change only
    /// when the song reaches the next one — on a song of four minutes in a
    /// band of 28 grooves, once in nine seconds.
    func playedGrooves(from start: Double, to end: Double, progress: Double) -> Int {
        let a0 = radius(at: start)
        let a1 = radius(at: end)
        guard a0 > a1 else { return 0 }
        let reached = a0 - (a0 - a1) * CGFloat(min(1, max(0, progress)))
        return grooves(from: start, to: end).filter { $0 >= reached }.count
    }

    /// The ring that holds the first `count` grooves of the song from
    /// `start`, as the radii of its outer and inner edges: each half a
    /// pitch beyond the grooves, so its edges fall between grooves and
    /// never cut one.
    func playedRing(from start: Double, to end: Double, count: Int) -> (outer: CGFloat, inner: CGFloat)? {
        let radii = grooves(from: start, to: end)
        guard count > 0, let first = radii.first else { return nil }
        let last = radii[min(count, radii.count) - 1]
        return (first + pitch / 2, last - pitch / 2)
    }
}

// MARK: - The sleeve

/// Where the album's sleeve and its record go in the room Now Playing gives
/// them: sketch E's sleeve, the record half out of its open edge.
///
/// Upright (the iPhone), the sleeve stands at the page's margin and the
/// record runs off the screen's right edge, showing a third of the sleeve's
/// width (94 of 284 points on the iPhone 17 Pro, as sketch E). On the iPad
/// sideways the whole record shows, and sleeve and record are centred in
/// their column. Either way the sleeve is as large as that allows, and
/// square; in the middle of the room's height.
nonisolated struct SleeveLayout: Equatable, Sendable {
    /// The record across, to the sleeve's side: a record is a little
    /// smaller than its sleeve.
    static let recordSide: CGFloat = 0.955
    /// The record's centre beyond the sleeve's open edge.
    static let recordBeyond: CGFloat = 8
    /// Upright: how much of the sleeve's width the record shows beyond it
    /// before the screen's edge.
    static let peek: CGFloat = 94.0 / 284.0

    /// The sleeve's square, in the room's points.
    let sleeve: CGRect
    /// The record: its centre and its width.
    let recordCenter: CGPoint
    let recordDiameter: CGFloat

    init(room size: CGSize, wide: Bool, margin: CGFloat) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let side: CGFloat
        let left: CGFloat
        if wide {
            // The sleeve, then the record's half beyond its centre.
            let span = 1 + Self.recordSide / 2
            side = max(0, min((width - Self.recordBeyond) / span, height))
            left = (width - (side * span + Self.recordBeyond)) / 2
        } else {
            side = max(0, min((width - margin) / (1 + Self.peek), height))
            left = margin
        }
        sleeve = CGRect(x: left, y: (height - side) / 2, width: side, height: side)
        recordDiameter = side * Self.recordSide
        recordCenter = CGPoint(x: left + side + Self.recordBeyond, y: sleeve.midY)
    }
}

// MARK: - How it moves

/// The motion of Now Playing, all of it, in one place. The record half out
/// of the sleeve turns its label; the land under the page is a record too,
/// and will sway as it turns once its next round (sketch H) gives it a pin
/// off its centre and a shape not quite round. Until then it is round and
/// pinned at its centre, and turning it would change no pixel: it is not
/// turned (`landTurns`), and only the label moves.
nonisolated enum RecordMotion {
    /// The label: a turn in 10 s, far slower than a real 33⅓ (1.8 s a
    /// turn) — the photographer, of the first turning record: "mag ie nog
    /// veel zachter draaien hoor".
    static let labelDegreesPerSecond: Double = 36
    /// The land: a real record's speed.
    static let landRevolutionsPerMinute: Double = 100.0 / 3
    /// The land's pin, off the record's true centre, in points: right and
    /// down. Sketch H1, "33⅓": a record "net niet helemaal rond", so "de
    /// lijnen dansen" (the photographer, 8 November 2026; and of the still
    /// land in the first build, 9 November: "Achtergrond lijkt niet echt te
    /// draaien?"). H1's 3 pt and 0.8% swayed the grooves under the words
    /// ±4.5–5.5 pt at 27–35 pt/s: "nog net iets teveel beweging, oogt
    /// daardoor een beetje onrustig". Half of it, H2's quiet sway: ±2.3–2.8
    /// pt, at most 17 pt/s, about half a groove each way.
    static let landPinOffset = CGPoint(x: 1.5, y: 0)
    /// How oval the land is: its width over its height, less one, in per
    /// cent: 1.002 across and 0.998 down. The oval does the dancing: it
    /// bends the lines twice a turn, the left and the right of the screen
    /// out of step.
    static let landOvalPercent: Double = 0.4
    /// Frames a second while the label alone turns: at 36° a second a frame
    /// turns it 1.8°, which reads as smooth, for a third fewer frames than
    /// 30.
    static let labelFrameRate: Double = 20
    /// Frames a second while the land turns too: at 33⅓ a minute that is
    /// 6.7° a frame, the most the page asks for.
    static let landFrameRate: Double = 30
    /// How long the turning takes to stop when the music pauses.
    static let coastSeconds: Double = 0.8
    /// How long the land takes to move on one band when the song changes,
    /// eased.
    static let slideSeconds: Double = 0.6

    /// Whether turning the land shows: a round record pinned at its centre
    /// looks the same at every angle.
    static var landTurns: Bool {
        landPinOffset != .zero || landOvalPercent != 0
    }

    static var landDegreesPerSecond: Double {
        landRevolutionsPerMinute * 360 / 60
    }

    /// The one timeline's rate.
    static var frameRate: Double {
        landTurns ? landFrameRate : labelFrameRate
    }
}

/// How far the records have turned, as seconds of turning at full speed:
/// the label's angle is that times its speed, the land's times its own, so
/// one clock turns both and they stop together. Turning, it runs with the
/// time; paused, it coasts to a stop over `RecordMotion.coastSeconds`
/// (evenly slower, so half as far as full speed would go); at rest it
/// holds.
nonisolated struct RecordClock: Equatable, Sendable {
    /// Turned until the last start or stop.
    private(set) var base: Double = 0
    /// When it began to turn; nil while it rests or coasts.
    private(set) var since: Date?
    /// When it began to coast; nil unless it coasts.
    private(set) var coastStart: Date?

    init() {}

    /// Turning or coasting: the timeline runs.
    var isMoving: Bool { since != nil || coastStart != nil }

    func turned(at date: Date) -> Double {
        if let since {
            return base + max(0, date.timeIntervalSince(since))
        }
        if let coastStart {
            let seconds = RecordMotion.coastSeconds
            let t = min(max(0, date.timeIntervalSince(coastStart)), seconds)
            return base + t - t * t / (2 * seconds)
        }
        return base
    }

    /// The label's angle and the land's, in degrees, 0 ..< 360.
    func labelAngle(at date: Date) -> Double {
        (turned(at: date) * RecordMotion.labelDegreesPerSecond).truncatingRemainder(dividingBy: 360)
    }

    func landAngle(at date: Date) -> Double {
        (turned(at: date) * RecordMotion.landDegreesPerSecond).truncatingRemainder(dividingBy: 360)
    }

    /// Starts turning, from wherever it is: at rest, or still coasting.
    mutating func start(at date: Date) {
        base = turned(at: date)
        coastStart = nil
        since = date
    }

    /// Stops: coasting when `coasts` and it was turning, else at once.
    mutating func stop(at date: Date, coasts: Bool) {
        let wasTurning = since != nil
        base = turned(at: date)
        since = nil
        coastStart = wasTurning && coasts ? date : nil
    }

    /// The coast is over: at rest where it ended.
    mutating func settle(at date: Date) {
        guard since == nil else { return }
        base = turned(at: date)
        coastStart = nil
    }
}
