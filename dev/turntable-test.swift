// Now Playing's arithmetic, checked on Linux (dev/turntable-test.sh):
// Jukebox/NowPlaying/TurntableMeasures.swift as the app has it. Where the
// playing song lies on its album (the photographer, 8 November 2026: "de
// naald zetten op welk nummer het is van het album"), the giant record under
// the page (sketch D2, "the side as land": its numbers on the iPhone and the
// iPad as sketch E drew them, the playing band under the anchor, the land
// moving on one band, the grooves played), where the sleeve and its record
// go on each device, and the one clock that turns them.

import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   " : "FAIL ", what)
    if !ok { failures += 1 }
}
func near(_ a: Double, _ b: Double, _ e: Double = 1e-9) -> Bool { abs(a - b) <= e }
func near(_ a: CGFloat, _ b: CGFloat, _ e: CGFloat) -> Bool { abs(a - b) <= e }
func f(_ x: Double, _ d: Int = 4) -> String { String(format: "%.\(d)f", x) }
func f(_ x: CGFloat, _ d: Int = 1) -> String { String(format: "%.\(d)f", Double(x)) }

// 1. Ten songs of varied lengths; song 4.
let lengths: [Double] = [212, 185, 340, 248, 96, 421, 203, 267, 158, 389]
let album = lengths.enumerated().map { TurntableSong(id: "s\($0.offset + 1)", disc: 1, length: $0.element) }
let total = lengths.reduce(0, +)
print("ten songs, total \(Int(total)) s")
let side = TurntableSide.of("s4", in: album)!
print("bands:", side.bands.map { f($0) }.joined(separator: " "))
check(side.bands.count == 9, "nine bands between ten songs")
check(side.bands == side.bands.sorted() && side.bands.allSatisfy { $0 > 0 && $0 < 1 }, "bands rise inside 0 … 1")
check(near(side.start, (212 + 185 + 340) / total), "song 4 starts at (212+185+340)/\(Int(total)) = \(f(side.start))")
check(near(side.end, (212 + 185 + 340 + 248) / total), "song 4 ends at \(f(side.end))")
check(side.disc == nil, "one disc: no disc number")
let first = TurntableSide.of("s1", in: album)!, last = TurntableSide.of("s10", in: album)!
check(first.start == 0 && near(first.end, 212 / total), "the first song from the outer groove")
check(near(last.start, (total - 389) / total) && last.end == 1, "the last song to the label")

// 2. One-song albums, and songs not on the album.
check(TurntableSide.of("x", in: [TurntableSong(id: "x", disc: nil, length: 300)]) == nil, "a one-song album has no side")
check(TurntableSide.of("x", in: []) == nil, "an unknown album has no side")
check(TurntableSide.of("nope", in: album) == nil, "a song not on the album has no side")
check(TurntableSide.of("a", in: [TurntableSong(id: "a", disc: 1, length: 0), TurntableSong(id: "b", disc: 1, length: 0)]) == nil,
      "no lengths known: no side")
check(TurntableSide.alone.bands.isEmpty && TurntableSide.alone.start == 0 && TurntableSide.alone.end == 1,
      "a song alone is one band, the whole side")

// 3. Two discs: disc 2's songs only, and its number.
let two = [TurntableSong(id: "d1a", disc: 1, length: 200), TurntableSong(id: "d1b", disc: 1, length: 300),
           TurntableSong(id: "d1c", disc: 1, length: 250),
           TurntableSong(id: "d2a", disc: 2, length: 180), TurntableSong(id: "d2b", disc: 2, length: 420),
           TurntableSong(id: "d2c", disc: 2, length: 600)]
let disc2 = TurntableSide.of("d2b", in: two)!
print("two discs, d2b: bands", disc2.bands.map { f($0) }, "start", f(disc2.start), "end", f(disc2.end), "disc", disc2.disc as Any)
check(disc2.bands.count == 2 && near(disc2.bands[0], 180.0 / 1200) && near(disc2.bands[1], 600.0 / 1200), "disc 2's own bands: 180/1200, 600/1200")
check(near(disc2.start, 0.15) && near(disc2.end, 0.5) && disc2.disc == 2, "d2b from 0.15 to 0.5, \"Disc 2\"")
let disc1 = TurntableSide.of("d1a", in: two)!
check(disc1.bands.count == 2 && disc1.start == 0 && disc1.disc == 1, "disc 1 likewise, \"Disc 1\"")
let lone = [TurntableSong(id: "p", disc: 1, length: 200), TurntableSong(id: "q", disc: 1, length: 200),
            TurntableSong(id: "r", disc: 2, length: 200)]
check(TurntableSide.of("r", in: lone) == nil, "a disc of one song has no side")
let unnumbered = [TurntableSong(id: "u", disc: nil, length: 100), TurntableSong(id: "v", disc: 1, length: 300)]
check(TurntableSide.of("u", in: unnumbered)?.disc == nil, "no disc number counts as disc 1")

// 4. An unknown length counts as the average of the known.
let gap = [TurntableSong(id: "g1", disc: 1, length: 100), TurntableSong(id: "g2", disc: 1, length: 0),
           TurntableSong(id: "g3", disc: 1, length: 300)]
let gapSide = TurntableSide.of("g2", in: gap)!
check(near(gapSide.start, 100.0 / 600) && near(gapSide.end, 300.0 / 600), "an unknown length counts as the average (200 s)")

// 5. The land, as sketch E drew it: its numbers on the two screens it drew.
let phone = LandGeometry(screen: CGSize(width: 402, height: 874), wide: false)
print("land, iPhone 17 Pro: grooves from \(f(phone.outerRadius)) to \(f(phone.innerRadius)), centre at x \(f(phone.centerX)), pitch \(f(phone.pitch))")
check(near(phone.outerRadius, 1440, 1) && near(phone.innerRadius, 420, 1) && near(phone.centerX, 300, 0.01) && phone.pitch == 5.2,
      "iPhone 17 Pro: 1440 to 420, centre 300 from the left, a groove every 5.2 (sketch E)")
let pad = LandGeometry(screen: CGSize(width: 1180, height: 820), wide: true)
print("land, iPad 11-inch sideways: grooves from \(f(pad.outerRadius)) to \(f(pad.innerRadius)), centre at x \(f(pad.centerX))")
check(near(pad.outerRadius, 1900, 1) && near(pad.innerRadius, 700, 1) && near(pad.centerX, 820, 0.01) && pad.pitch == 5.6,
      "iPad sideways: 1900 to 700, centre 820 from the left, every 5.6 (sketch E)")

// The sketch's own album: Velvet Songs, song 5, the anchor at (201, 420).
let velvet: [Double] = [214, 198, 241, 187, 262, 229, 203, 276]
let velvetSongs = velvet.enumerated().map { TurntableSong(id: "v\($0.offset)", disc: 1, length: $0.element) }
let five = TurntableSide.of("v4", in: velvetSongs)!, six = TurntableSide.of("v5", in: velvetSongs)!
let anchor = CGPoint(x: 201, y: 420)
let y5 = phone.centerY(anchor: anchor, start: five.start), y6 = phone.centerY(anchor: anchor, start: six.start)
print("Velvet Songs on the iPhone: the centre \(f(y5)) down for song 5, \(f(y6)) for song 6 (sketch E's gif_frames.py: 1381.5 and 1233.0)")
check(near(y5, 1381.5, 0.5) && near(y6, 1233.0, 0.5), "the centre where sketch E's gif has it, for songs 5 and 6")
func distance(_ x: CGFloat, _ y: CGFloat, _ p: CGPoint) -> CGFloat {
    ((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)).squareRoot()
}
check(near(distance(phone.centerX, y5, anchor), phone.radius(at: five.start), 0.001), "song 5's band passes through the anchor")
check(near(distance(phone.centerX, y6, anchor), phone.radius(at: six.start), 0.001), "and on the next song, song 6's does")
check(y6 < y5, "the next song: the land moves up one band")
check(near(phone.radius(at: five.end), phone.radius(at: six.start), 1e-9), "song 6's band begins where song 5's ends")
check(phone.innerRadius > abs(anchor.x - phone.centerX), "every band reaches the anchor")

let rings = phone.rings(bands: five.bands)
let grooves = rings.filter { $0.kind == .groove || $0.kind == .strong }
let edges = rings.filter { $0.kind == .edge }
print("rings: \(grooves.count) grooves, \(edges.count) edges between songs, a run-out at \(f(rings.last!.radius))")
check(zip(rings, rings.dropFirst()).allSatisfy { $0.radius > $1.radius }, "outermost first, each inside the last")
check(edges.count == velvet.count - 1, "an edge between every two songs")
check(rings.last!.kind == .runOut && near(rings.last!.radius, phone.innerRadius - 60, 0.001), "the run-out inside the last song")
check(grooves.first!.radius == phone.outerRadius && grooves.first!.kind == .strong, "the first groove at the rim, a strong one")
let fiveGrooves = phone.grooves(from: five.start, to: five.end)
print("song 5's band: \(fiveGrooves.count) grooves from \(f(fiveGrooves.first!)) to \(f(fiveGrooves.last!))")
check(near(fiveGrooves.first!, phone.radius(at: five.start) - 13, 0.001), "a song's grooves start half the land inside its start")
check(fiveGrooves.last! > phone.radius(at: five.end) + 13, "and stop half the land short of its end")
let alone = phone.rings(bands: [])
check(alone.filter { $0.kind == .edge }.isEmpty && alone.filter { $0.kind != .runOut }.count > 190,
      "a song alone: one band of grooves, rim to run-out")

// The grooves played: none at the start, all at the end, whole grooves.
check(phone.playedGrooves(from: five.start, to: five.end, progress: 0) == 0, "at the start, no groove of song 5 is played")
check(phone.playedGrooves(from: five.start, to: five.end, progress: 1) == fiveGrooves.count, "at the end, all of them")
var steps = 0, previous = -1, rising = true
for second in 0...262 {
    let n = phone.playedGrooves(from: five.start, to: five.end, progress: Double(second) / 262)
    if n < previous { rising = false }
    if n != previous { steps += 1 }
    previous = n
}
check(rising, "the played grooves only grow as the song plays")
print("song 5 (262 s): the played grooves change \(steps) times, once in \(f(262.0 / Double(steps), 1)) s")
check(steps <= fiveGrooves.count + 1, "they change once a groove, not twice a second")
if let ring = phone.playedRing(from: five.start, to: five.end, count: 10) {
    let inside = fiveGrooves.filter { $0 < ring.outer && $0 > ring.inner }
    check(inside.count == 10 && near(ring.outer - fiveGrooves[0], 2.6, 0.001) && near(fiveGrooves[9] - ring.inner, 2.6, 0.001),
          "the played ring holds ten grooves, its edges half a pitch beyond them")
} else {
    check(false, "the played ring of ten grooves")
}
check(phone.playedRing(from: five.start, to: five.end, count: 0) == nil, "no grooves played: no ring")
let firstSide = TurntableSide.of("v0", in: velvetSongs)!
check(phone.playedGrooves(from: firstSide.start, to: firstSide.end, progress: 0) == 1,
      "the first song: its first groove is the rim, played from the start")

// The bitmap, per device: one per album and screen, never per frame.
for (name, w, h, wide) in [("iPhone SE", 375.0, 667.0, false), ("iPhone 17 Pro", 402.0, 874.0, false),
                           ("iPhone 17 Pro Max", 440.0, 956.0, false), ("iPad 11-inch upright", 820.0, 1180.0, false),
                           ("iPad 11-inch sideways", 1180.0, 820.0, true), ("iPad 13-inch sideways", 1376.0, 1032.0, true)] {
    let g = LandGeometry(screen: CGSize(width: w, height: h), wide: wide)
    let pixels = (g.diameter * g.bitmapScale).rounded(.up)
    let megabytes = Double(pixels * pixels * 4) / 1_048_576
    print("\(name): the land \(f(g.diameter, 0)) points across, \(f(pixels, 0)) pixels (\(f(g.bitmapScale, 2)) a point), \(f(megabytes, 1)) MB")
    check(pixels <= 2900 && g.bitmapScale <= 0.75, "\(name): the bitmap within 2900 pixels and 0.75 a point")
}

// 6. The sleeve and its record, on each device.
func sleeve(_ name: String, _ w: CGFloat, _ h: CGFloat, wide: Bool) -> SleeveLayout {
    let layout = SleeveLayout(room: CGSize(width: w, height: h), wide: wide, margin: 24)
    let s = layout.sleeve
    print("\(name) \(f(w, 0))×\(f(h, 0)): sleeve \(f(s.width)) at (\(f(s.minX)), \(f(s.minY))), record \(f(layout.recordDiameter)) across at x \(f(layout.recordCenter.x)), its right edge at \(f(layout.recordCenter.x + layout.recordDiameter / 2))")
    check(s.width == s.height && s.minY >= -0.001 && s.maxY <= h + 0.001, "\(name): a square within the height")
    check(near(layout.recordCenter.y, s.midY, 0.001) && near(layout.recordDiameter, s.width * 0.955, 0.001),
          "\(name): the record level with the sleeve, a little smaller")
    if wide {
        check(layout.recordCenter.x + layout.recordDiameter / 2 <= w + 0.001 && s.minX >= -0.001, "\(name): all of the record shows")
    } else {
        check(near(s.minX, 24, 0.001), "\(name): the sleeve at the margin")
    }
    return layout
}
let pro = sleeve("iPhone 17 Pro", 402, 330, wide: false)
check(near(pro.sleeve.width, 284, 0.5) && near(pro.recordCenter.x, 316, 0.5) && near(pro.recordDiameter, 271, 0.5),
      "iPhone 17 Pro: a sleeve of 284 and a record of 271 whose centre is 8 beyond it (sketch E)")
check(near(402 - pro.sleeve.maxX, 94, 0.5), "iPhone 17 Pro: 94 points of the record show before the screen's edge")
_ = sleeve("iPhone SE", 375, 210, wide: false)
_ = sleeve("iPhone 17 Pro Max", 440, 380, wide: false)
_ = sleeve("iPad 11-inch sideways, left column", 628, 680, wide: true)
_ = sleeve("iPad 13-inch sideways, left column", 824, 890, wide: true)
_ = sleeve("iPad upright", 560, 620, wide: false)
let nothing = sleeve("nothing yet", 0, 0, wide: false)
check(nothing.sleeve.width == 0, "no room: no sleeve")

// 7. The motion: sketch H1 at half, "33⅓" calmed ("oogt een beetje onrustig").
print("motion: the label \(f(RecordMotion.labelDegreesPerSecond, 0))° a second, the land \(f(RecordMotion.landRevolutionsPerMinute, 2)) a minute (\(f(RecordMotion.landDegreesPerSecond, 0))° a second), pin \(RecordMotion.landPinOffset), oval \(RecordMotion.landOvalPercent)%, \(f(RecordMotion.frameRate, 0)) frames a second")
check(near(RecordMotion.labelDegreesPerSecond * 10, 360), "the label: a turn in 10 s")
check(near(RecordMotion.landDegreesPerSecond, 200), "the land: 33⅓ a minute is 200° a second")
check(RecordMotion.landTurns, "off its centre and a little oval (sketch H1): the land is turned, and its lines dance")
check(RecordMotion.landPinOffset.x == 1.5 && RecordMotion.landPinOffset.y == 0, "the pin 1.5 pt off the centre")
check(near(RecordMotion.landOvalPercent, 0.4), "0.4% wider than high: 1.002 across, 0.998 down")
check(RecordMotion.frameRate == 30, "30 frames a second while the land turns: 6.7° a frame")
check(RecordMotion.frameRate <= 30 && RecordMotion.landFrameRate <= 30, "never more than 30 frames a second")

// The clock: turns, coasts to a stop, holds; both records from one clock.
var clock = RecordClock()
let t0 = Date(timeIntervalSinceReferenceDate: 1000)
check(!clock.isMoving && clock.turned(at: t0) == 0, "at rest at first")
clock.start(at: t0)
check(clock.isMoving && near(clock.turned(at: t0.addingTimeInterval(5)), 5), "turning: five seconds in five seconds")
check(near(clock.labelAngle(at: t0.addingTimeInterval(5)), 180) && near(clock.landAngle(at: t0.addingTimeInterval(5)), 1000.0.truncatingRemainder(dividingBy: 360)),
      "the label half a turn in 5 s, the land 1000° (280°)")
clock.stop(at: t0.addingTimeInterval(10), coasts: true)
check(clock.isMoving && near(clock.turned(at: t0.addingTimeInterval(10)), 10), "a pause: it coasts from where it was")
check(near(clock.turned(at: t0.addingTimeInterval(20)), 10.4), "and stops half as far on as full speed would go (0.4 s)")
clock.settle(at: t0.addingTimeInterval(20))
check(!clock.isMoving && near(clock.turned(at: t0.addingTimeInterval(100)), 10.4), "settled, it holds")
clock.start(at: t0.addingTimeInterval(100))
clock.stop(at: t0.addingTimeInterval(101), coasts: false)
check(!clock.isMoving && near(clock.turned(at: t0.addingTimeInterval(200)), 11.4), "stopped without a coast (Low Power, the app away): at once")
clock.start(at: t0.addingTimeInterval(300))
clock.stop(at: t0.addingTimeInterval(301), coasts: true)
clock.start(at: t0.addingTimeInterval(301.4))
check(near(clock.turned(at: t0.addingTimeInterval(301.4)), 11.4 + 1 + 0.4 - 0.16 / 1.6), "played again while coasting: from where the coast had got to")

print(failures == 0 ? "all good" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
