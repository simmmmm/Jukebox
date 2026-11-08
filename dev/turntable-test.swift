// The record player's arithmetic, checked on Linux (dev/turntable-test.sh):
// Jukebox/NowPlaying/TurntableMeasures.swift as the app has it. Where the
// needle goes on an album's side, from the photographer's "de naald zetten op
// welk nummer het is van het album" (8 November 2026): ten songs with song 4
// at 30%, albums of one song, two discs, unknown lengths. And how the deck
// and the sleeve behind it share the record's room on each device.

import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   " : "FAIL ", what)
    if !ok { failures += 1 }
}
func near(_ a: Double, _ b: Double, _ e: Double = 1e-9) -> Bool { abs(a - b) <= e }
func f(_ x: Double, _ d: Int = 4) -> String { String(format: "%.\(d)f", x) }
func f(_ x: CGFloat, _ d: Int = 1) -> String { String(format: "%.\(d)f", Double(x)) }

// 1. Ten songs of varied lengths; song 4 at 30%.
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
let place = side.place(progress: 0.3)
let expected = (212 + 185 + 340 + 0.3 * 248) / total
check(near(place, expected), "song 4 at 30%: (737 + 74.4) / \(Int(total)) = \(f(place))")
let band = side.bands.firstIndex(where: { $0 > place }) ?? side.bands.count
check(band == 3, "the needle is in band \(band + 1) of 10 (song 4)")
let g = TurntableGeometry(width: 285)
let a0 = g.armAngle(place: side.start), a1 = g.armAngle(place: side.end), a = g.armAngle(place: place)
print("arm on a 285-point deck: song 4 from \(f(a0, 2))° to \(f(a1, 2))°, at 30% \(f(a, 2))°;",
      "groove radius \(f(g.grooveRadius(at: place), 2)) between \(f(g.grooveRadius(at: side.start), 2)) and \(f(g.grooveRadius(at: side.end), 2))")
check(a0 < a && a < a1, "the arm's angle is inside song 4's band")
check(near(g.armAngle(place: 0), g.armAngle(place: -1)) && near(g.armAngle(place: 1), g.armAngle(place: 2)), "places outside 0 … 1 are held to it")
check(near(side.place(progress: 0), side.start) && near(side.place(progress: 1), side.end), "progress 0 and 1 are the band's edges")
let first = TurntableSide.of("s1", in: album)!, last = TurntableSide.of("s10", in: album)!
check(first.start == 0 && near(first.end, 212 / total), "the first song from the outer groove")
check(near(last.start, (total - 389) / total) && last.end == 1, "the last song to the label")

// 2. One-song albums, and songs not on the album.
check(TurntableSide.of("x", in: [TurntableSong(id: "x", disc: nil, length: 300)]) == nil, "a one-song album has no side")
check(TurntableSide.of("x", in: []) == nil, "an unknown album has no side")
check(TurntableSide.of("nope", in: album) == nil, "a song not on the album has no side")
check(TurntableSide.of("a", in: [TurntableSong(id: "a", disc: 1, length: 0), TurntableSong(id: "b", disc: 1, length: 0)]) == nil,
      "no lengths known: no side")

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

// 5. The layout.
func show(_ name: String, _ w: CGFloat, _ h: CGFloat) -> TurntableLayout {
    let layout = TurntableLayout(fitting: CGSize(width: w, height: h))
    let d = layout.deck
    let far = d.farEdge, nearEdge = d.nearEdge
    let farY = layout.deckCenter.y + far.offset, nearY = layout.deckCenter.y + nearEdge.offset
    var line = "\(name) \(f(w, 0))×\(f(h, 0)): deck \(f(d.width)), seen \(f(nearY - farY)) high, far edge at \(f(farY))"
    if let s = layout.sleeve {
        line += ", sleeve \(f(s.width)) showing \(f(farY - s.minY)) (\(Int(((farY - s.minY) / s.height * 100).rounded()))%)"
        line += ", shadow \(f(layout.shadow!.length)) deep"
    } else {
        line += ", no sleeve"
    }
    print(line)
    let topY = layout.sleeve?.minY ?? farY
    check(topY >= -0.01 && nearY <= h + 0.01, "\(name): all of it within the height")
    check(nearEdge.scale * d.width <= w + 0.01, "\(name): the near edge within the width")
    if let s = layout.sleeve {
        let farLeft = layout.deckCenter.x - far.scale * d.width / 2, farRight = layout.deckCenter.x + far.scale * d.width / 2
        check(s.maxY > farY + 0.3 * s.height, "\(name): the sleeve's lower part is behind the deck")
        check(s.minX > farLeft + 6 && s.maxX < farRight - 6, "\(name): its corners are hidden by the plinth, clear of its rounded ones")
        check(layout.shadow!.length < d.center.y - d.platterRadius, "\(name): its shadow stops short of the platter")
        check(abs((farY - layout.deckCenter.y) - far.offset) < 0.001, "\(name): the sleeve's foot is on the far edge")
    }
    return layout
}
// The record's room on each: the iPhone 17 Pro's measured on CI's screenshot
// of d227873 (370 × 331 with a station's dial; the volume, 43 points lower,
// leaves 374), the others worked out from Now Playing's layout.
let pro = show("iPhone 17 Pro, a station", 370, 331)
_ = show("iPhone 17 Pro, no station", 370, 374)
let se = show("iPhone SE, a station", 343, 200)
_ = show("iPhone SE, no station", 343, 243)
_ = show("iPhone 17 Pro Max, a station", 408, 400)
_ = show("iPad 13-inch, left column", 824, 915)
_ = show("iPad 11-inch, left column", 628, 703)
_ = show("iPad mini, left column", 581, 627)
_ = show("iPad portrait", 528, 940)
_ = show("nothing yet", 0, 0)
check(pro.sleeve != nil && se.sleeve == nil, "a sleeve on the 17 Pro, none on the SE")

print(failures == 0 ? "all good" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
