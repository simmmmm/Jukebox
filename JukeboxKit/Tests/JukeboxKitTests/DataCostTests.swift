// DataCost: what a network that costs data changes (docs/DATA.md).

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Data cost")
struct DataCostTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The quality follows the network the song starts on")
    func quality() {
        #expect(DataCost.quality(expensive: true, wifi: .original, cellular: .normal) == .normal)
        #expect(DataCost.quality(expensive: false, wifi: .original, cellular: .normal) == .original)
    }

    @Test("A return to the window reads the library after five minutes, never on a network that costs")
    func libraryRefresh() {
        let old = now.addingTimeInterval(-DataCost.libraryRefreshAfter)
        #expect(DataCost.libraryRefreshIsDue(lastAsked: old, now: now, expensive: false))
        #expect(!DataCost.libraryRefreshIsDue(lastAsked: old, now: now, expensive: true))
        #expect(!DataCost.libraryRefreshIsDue(lastAsked: now.addingTimeInterval(-24 * 3600), now: now, expensive: true))
        #expect(!DataCost.libraryRefreshIsDue(lastAsked: now.addingTimeInterval(-60), now: now, expensive: false))
        #expect(!DataCost.libraryRefreshIsDue(lastAsked: nil, now: now, expensive: false))
    }

    @Test("A network that costs holds a minute ahead, longer than the longest crossfade; Wi-Fi is the player's")
    func forwardBuffer() throws {
        let ahead = try #require(DataCost.forwardBuffer(expensive: true))
        #expect(ahead >= 12 && ahead <= 60)
        #expect(DataCost.forwardBuffer(expensive: false) == nil)
    }
}
