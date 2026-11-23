// Adjust to the Connection (Server/QualitySteps.swift): a slow sign steps
// the next songs down, three clean songs step them back up.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Quality steps: the target, lower while the network is slow")
struct QualityStepsTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("Each step about halves the data, never above the target; 128 is the floor")
    func ladder() {
        #expect(QualitySteps.ladder(.original, opus: true) == [.original, .normal, .efficient])
        #expect(QualitySteps.ladder(.high, opus: false) == [.high, .normal, .low])
        #expect(QualitySteps.ladder(.normal, opus: true) == [.normal, .efficient])
        #expect(QualitySteps.ladder(.efficient, opus: true) == [.efficient])
        #expect(QualitySteps.ladder(.low, opus: true) == [.low])
    }

    @Test("A wait mid-song steps down at once, once per song")
    func midSong() {
        var steps = QualitySteps()
        let r1 = steps.quality(for: .original, opus: true)
        #expect(r1 == .original)
        steps.songBegan(t0)
        let r2 = steps.waitBegan(t0 + 30, midSong: true)
        #expect(r2)
        let r3 = steps.waitEnded(t0 + 31)
        #expect(!r3)
        let r4 = steps.waitBegan(t0 + 60, midSong: true)
        #expect(!r4, "a second wait in the same song")
        _ = steps.waitEnded(t0 + 61)
        let r5 = steps.quality(for: .original, opus: true)
        #expect(r5 == .normal)
        steps.songBegan(t0 + 200)
        let r6 = steps.waitBegan(t0 + 230, midSong: true)
        #expect(r6)
        let r7 = steps.quality(for: .original, opus: true)
        #expect(r7 == .efficient)
        steps.songBegan(t0 + 400)
        let r8 = steps.waitBegan(t0 + 430, midSong: true)
        #expect(!r8, "the floor")
        let r9 = steps.quality(for: .original, opus: false)
        #expect(r9 == .original, "another server: the target again")
    }

    @Test("A start's wait is slow only from 8 s, judged when it ends or the song is left")
    func start() {
        var steps = QualitySteps()
        _ = steps.quality(for: .high, opus: false)
        steps.songBegan(t0)
        let r10 = steps.waitBegan(t0, midSong: false)
        #expect(!r10)
        let r11 = steps.waitEnded(t0 + 2)
        #expect(!r11, "a transcode's own start")
        #expect(steps.down == 0)
        steps.songBegan(t0 + 10)
        _ = steps.waitBegan(t0 + 10, midSong: false)
        let r12 = steps.waitEnded(t0 + 40)
        #expect(r12, "HLS that never started")
        let r13 = steps.quality(for: .high, opus: false)
        #expect(r13 == .normal)
    }

    @Test("Three clean songs climb one step; a slow sign starts the count again")
    func climb() {
        var steps = QualitySteps()
        _ = steps.quality(for: .original, opus: true)
        steps.songBegan(t0)
        _ = steps.waitBegan(t0 + 30, midSong: true)
        _ = steps.waitEnded(t0 + 31)
        steps.songBegan(t0 + 100)
        steps.songBegan(t0 + 200)
        _ = steps.waitBegan(t0 + 230, midSong: true)  // at the floor's way: down to 2
        _ = steps.waitEnded(t0 + 231)
        #expect(steps.down == 2)
        for i in 3...5 { steps.songBegan(t0 + Double(i) * 100) }
        #expect(steps.down == 2, "two clean so far")
        steps.songBegan(t0 + 600)
        #expect(steps.down == 1)
        let r14 = steps.quality(for: .original, opus: true)
        #expect(r14 == .normal)
    }

    @Test("A wait the engine carries into the next song is that song's, not mid-song")
    func straddle() {
        var steps = QualitySteps()
        _ = steps.quality(for: .original, opus: true)
        steps.songBegan(t0)
        _ = steps.waitBegan(t0 + 195, midSong: false)
        steps.songBegan(t0 + 200)
        let r15 = steps.waitEnded(t0 + 203)
        #expect(!r15, "3 s into the new song")
        #expect(steps.down == 0)
    }

    @Test("A new target, or a reset, starts again at the target")
    func reset() {
        var steps = QualitySteps()
        _ = steps.quality(for: .original, opus: true)
        steps.songBegan(t0)
        _ = steps.waitBegan(t0 + 30, midSong: true)
        let r16 = steps.quality(for: .normal, opus: true)
        #expect(r16 == .normal)
        steps.songBegan(t0 + 100)
        _ = steps.waitBegan(t0 + 130, midSong: true)
        let r17 = steps.quality(for: .normal, opus: true)
        #expect(r17 == .efficient)
        steps.reset()
        let r18 = steps.quality(for: .normal, opus: true)
        #expect(r18 == .normal)
        let r19 = steps.quality(for: .low, opus: true)
        #expect(r19 == .low)
    }
}
