// The record player's measures, as plain arithmetic (Turntable.swift draws
// them): the deck's geometry; how the deck and the album's sleeve standing
// behind it share the room Now Playing gives them; and where the playing
// song lies on its album, which is where the needle goes. The photographer,
// 8 November 2026: "Kun je de platenspeler iets leuker maken, de hoes er
// achter zetten en de naald zetten op welk nummer het is van het album".
//
// Foundation only, no SwiftUI, so that it is checked on Linux as well as
// built on the Mac: dev/turntable-test.sh compiles it as it is, with the
// app's settings, beside dev/turntable-test.swift.

import Foundation

// MARK: - The deck

/// The deck's measures, in points, for a plinth `width` wide: where the
/// platter, the record and the arm are, the arm's angle for a place on the
/// record, and where the deck is seen once tipped back. Plain numbers,
/// `nonisolated`, as the arm's Shape reads them.
nonisolated struct TurntableGeometry: Equatable, Sendable {
    /// How far the deck is tipped back, in degrees, and the perspective it
    /// is seen in: sketch D's deck, seen from a little above and in front.
    static let tilt: Double = 46
    static let perspective: CGFloat = 0.4
    /// The plinth's depth to its width.
    static let depthRatio: CGFloat = 1.08
    /// The arm at rest beside the platter, off the record: degrees clockwise
    /// from straight down.
    static let parkedAngle: Double = -3

    let width: CGFloat

    init(width: CGFloat) {
        self.width = width
    }

    var depth: CGFloat { width * Self.depthRatio }
    /// The platter's and the record's centre, left of the middle to leave
    /// the arm its room on the right.
    var center: CGPoint { CGPoint(x: width * 0.44, y: depth * 0.5) }
    var platterRadius: CGFloat { width * 0.405 }
    var discRadius: CGFloat { width * 0.385 }
    var labelRadius: CGFloat { discRadius * 0.34 }
    var holeRadius: CGFloat { width * 0.011 }
    /// The arm's pivot, top right, and its length from the pivot to the
    /// stylus: about as far as from the pivot to the spindle, as a real
    /// arm's, so the stylus's arc crosses the record from rim to label.
    var pivot: CGPoint { CGPoint(x: width * 0.885, y: depth * 0.13) }
    var armLength: CGFloat { width * 0.56 }
    /// Where the stylus rides: the outermost groove, and the last one
    /// before the label.
    var outerGroove: CGFloat { discRadius * 0.94 }
    var innerGroove: CGFloat { labelRadius * 1.12 }

    /// The groove `place` (0 … 1) of the way from the outer groove to the
    /// label. The one measure of a place on the record: the arm goes to it
    /// and the bands between the album's songs are drawn at it.
    func grooveRadius(at place: Double) -> CGFloat {
        let p = CGFloat(min(1, max(0, place)))
        return outerGroove + (innerGroove - outerGroove) * p
    }

    /// The arm's angle, degrees clockwise from straight down, with the
    /// stylus in the groove `place` (0 … 1) of the way from the outer
    /// groove to the label. About 12° at the outer groove and 34° by the
    /// label.
    func armAngle(place: Double) -> Double {
        angle(toRadius: grooveRadius(at: place)) ?? (12 + 22 * min(1, max(0, place)))
    }

    /// Where the arm's circle about the pivot crosses the groove of
    /// `radius`: of the two crossings, the one nearer the arm's rest (the
    /// smaller angle). Nil when they do not cross.
    private func angle(toRadius radius: CGFloat) -> Double? {
        let dx = center.x - pivot.x
        let dy = center.y - pivot.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let length = armLength
        guard distance > 0, abs(distance - radius) <= length, length <= distance + radius else { return nil }
        let along = (length * length - radius * radius + distance * distance) / (2 * distance)
        let across = max(0, length * length - along * along).squareRoot()
        let ux = dx / distance
        let uy = dy / distance
        let baseX = pivot.x + along * ux
        let baseY = pivot.y + along * uy
        var best: Double?
        for side in [CGFloat(1), CGFloat(-1)] {
            let x = baseX - side * across * uy
            let y = baseY + side * across * ux
            let degrees = atan2(Double(pivot.x - x), Double(y - pivot.y)) * 180 / Double.pi
            best = min(best ?? degrees, degrees)
        }
        return best
    }

    /// A line across the deck `y` points from its middle (toward the
    /// listener when positive) as it is seen once the deck is tipped back:
    /// how far from the middle, and how much larger or smaller. As
    /// SwiftUI's rotation3DEffect draws it — a turn about the horizontal
    /// axis, then perspective with m34 = −perspective ÷ the larger side,
    /// here the depth. CI's screenshot of d227873 (iPhone 17 Pro) bears it
    /// out to a point: a plinth 319 wide was seen 279 wide at its far edge,
    /// 368 at its near edge and 244 deep, where this gives 279, 373 less its
    /// rounded corners, and 244.
    func seen(_ y: CGFloat) -> (offset: CGFloat, scale: CGFloat) {
        guard depth > 0 else { return (y, 1) }
        let radians = Self.tilt * Double.pi / 180
        let toward = Double(y) * sin(radians)
        let w = 1 - Double(Self.perspective) * toward / Double(depth)
        return (CGFloat(Double(y) * cos(radians) / w), CGFloat(1 / w))
    }

    /// The far edge, seen: above the middle (a negative offset), narrower.
    var farEdge: (offset: CGFloat, scale: CGFloat) { seen(-depth / 2) }
    /// The near edge, seen: below the middle, wider.
    var nearEdge: (offset: CGFloat, scale: CGFloat) { seen(depth / 2) }
}

// MARK: - The deck and the sleeve

/// How the deck and the album's sleeve standing behind it share `size`,
/// the room Now Playing gives the record player.
///
/// The sleeve is a square, upright, not tipped: the cover as if the record
/// had just come out of it. It stands behind the plinth's far edge with its
/// lower part hidden by the deck, and above the record, a little left of
/// the middle, clear of the arm's pivot. It is 0.66 of the plinth's width,
/// about the record's own width seen as far back as the far edge (0.77 ×
/// 0.87): drawn larger it spanned the whole far edge and read as a wall,
/// not a sleeve.
///
/// Room: the deck first. It is as wide as it fits, as before the sleeve;
/// the sleeve shows 60% of itself above the far edge when there is room
/// for that, and the deck gives up to a tenth of its width to make that
/// room. With less, less of the sleeve shows; under 30% (a strip, not a
/// sleeve) the sleeve is left out and the deck has all the room. On an
/// iPhone 17 Pro with a station's dial under the record (370 × 331) the
/// deck is 285 wide, a tenth less than alone, under a 188-point sleeve;
/// without the dial (370 × 374) it keeps all its 317 under a sleeve of 209;
/// on an iPhone SE (343 × 200 to 243) there is no room and no sleeve; in a
/// 13-inch iPad's left column, 705 under 466 (dev/turntable-test.sh, which
/// checks each of these on Linux).
nonisolated struct TurntableLayout: Equatable, Sendable {
    /// The sleeve's side, its shift from the middle (left is negative), and
    /// how much of it may show above the far edge: all in the plinth's
    /// widths, and as seen on the screen.
    static let sleeveSide: CGFloat = 0.66
    static let sleeveShift: CGFloat = -0.06
    static let sleeveShowing: ClosedRange<CGFloat> = 0.3...0.6
    /// The least of its width the deck keeps when it makes room for the
    /// sleeve.
    static let deckKeeps: CGFloat = 0.9
    /// The sleeve's shadow on the plinth, from a light high above and a
    /// little behind and to the left: as long as a fifth of the sleeve's
    /// height above the plinth, leaning right 0.6 of its length, as the
    /// arm's shadow falls (TonearmView's offset, 0.01 across and 0.016 down
    /// the deck).
    static let shadowLength: CGFloat = 0.2
    static let shadowLean: CGFloat = 0.6

    /// The deck, as wide as it is drawn.
    let deck: TurntableGeometry
    /// Where the deck's middle goes in `size`: rotation3DEffect tips it
    /// about its middle.
    let deckCenter: CGPoint
    /// The sleeve's square in `size`; nil when there is no room for it.
    let sleeve: CGRect?
    /// The sleeve's shadow on the plinth, in the plinth's own points; nil
    /// with no sleeve.
    let shadow: TurntableSleeveShadow?

    init(fitting size: CGSize) {
        // Per point of the plinth's width: the deck's seen edges scale with
        // it, and their scales not at all.
        let unit = TurntableGeometry(width: 1)
        let far = unit.farEdge
        let near = unit.nearEdge
        let deckHeight = near.offset - far.offset
        let room = CGSize(width: max(0, size.width), height: max(0, size.height))
        // The deck alone, as wide as fits: its near edge, the widest part,
        // within the width, and its seen depth within the height.
        let alone = min(room.width / near.scale, room.height / deckHeight)
        let side = Self.sleeveSide
        var width = max(alone * Self.deckKeeps,
                        min(alone, room.height / (deckHeight + side * Self.sleeveShowing.upperBound)))
        var showing: CGFloat = 0
        if width > 0 {
            showing = min(Self.sleeveShowing.upperBound, (room.height - deckHeight * width) / (side * width))
        }
        if showing < Self.sleeveShowing.lowerBound {
            width = alone
            showing = 0
        }

        // Sleeve and deck as one picture, in the middle of the room.
        let shown = side * width * showing
        let top = (room.height - deckHeight * width - shown) / 2
        let farEdgeY = top + shown
        deck = TurntableGeometry(width: width)
        deckCenter = CGPoint(x: room.width / 2, y: farEdgeY - far.offset * width)
        guard showing > 0 else {
            sleeve = nil
            shadow = nil
            return
        }
        let sleeveWidth = side * width
        let midX = room.width / 2 + Self.sleeveShift * width
        sleeve = CGRect(x: midX - sleeveWidth / 2, y: top, width: sleeveWidth, height: sleeveWidth)
        // The far edge's points on the plinth: back from the screen by the
        // far edge's scale. The shadow begins where the sleeve meets the
        // far edge and falls forward onto the plinth, short of the platter
        // (0.135 of the width in), which it never reaches: at most 0.6 ×
        // 0.66 × 0.2 ÷ 0.87 = 0.09.
        let toPlinth = 1 / far.scale
        let length = Self.shadowLength * shown * toPlinth
        shadow = TurntableSleeveShadow(left: width / 2 + (midX - sleeveWidth / 2 - room.width / 2) * toPlinth,
                                       right: width / 2 + (midX + sleeveWidth / 2 - room.width / 2) * toPlinth,
                                       length: length, lean: Self.shadowLean * length)
    }
}

/// The sleeve's hard shadow on the plinth, in the plinth's own points (its
/// far edge is y = 0): from `left` to `right` along the far edge, `length`
/// toward the listener, its near side `lean` to the right.
nonisolated struct TurntableSleeveShadow: Equatable, Sendable {
    let left: CGFloat
    let right: CGFloat
    let length: CGFloat
    let lean: CGFloat

    init(left: CGFloat, right: CGFloat, length: CGFloat, lean: CGFloat) {
        self.left = left
        self.right = right
        self.length = length
        self.lean = lean
    }
}

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

/// Where the playing song lies on its album, as the record shows it. The
/// songs of the playing song's disc, in disc and track order, are bands
/// from the outer groove (the first song) to the run-out by the label (the
/// last), each as wide as the song is long; the needle is in the playing
/// song's band and creeps inward through it as it plays.
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

    /// The needle's place, 0 … 1 from the outer groove to the label, with
    /// the playing song `progress` (0 … 1) of the way through: (the lengths
    /// of the side's songs before it + the time played) ÷ the side's
    /// length. The song's progress is the player's own (elapsed over its
    /// duration), so the needle stays in the song's band even where the
    /// player's length and the library's differ.
    func place(progress: Double) -> Double {
        start + (end - start) * min(1, max(0, progress))
    }

    /// The side of the song `id` among its album's songs, `album` in disc
    /// and track order (LibraryStore.tracks(inAlbum:)): its disc's songs
    /// only, as a record holds one disc. Nil — no bands, and the arm goes
    /// by the song alone — when the song is not among them, when it is its
    /// disc's only song, or when no length on its disc is known.
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
