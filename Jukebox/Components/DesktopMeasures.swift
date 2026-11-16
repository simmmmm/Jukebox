// The desktop's measures, from the designer's spec
// (build/design-round/2027/spec.md): the player's bar's three zones, the
// sidebar and the panel, and the page's table. Foundation only, so Linux's
// window (GTK) and the iPad's and the Mac's (SwiftUI) lay out by the same
// numbers. Whole points: each platform converts at its edge.

import Foundation

/// `nonisolated`, as GTK's layout callbacks that read it are.
nonisolated enum DesktopMeasures {
    /// The sidebar of places, at every width (spec §4).
    static let sidebar = 240
    /// The panel of Up next or the lyrics, at every width, so it stays on
    /// the grid (spec §3).
    static let panel = 360

    // MARK: - The player's bar

    /// The middle zone's share of the bar, and its least and most.
    static let middleShare = 0.4
    static let middleLeast = 304
    static let middleMost = 640

    /// The bar's three zones, side by side: their widths.
    nonisolated struct Zones: Equatable, Sendable {
        var start: Int
        var middle: Int
        var end: Int
    }

    /// The middle zone a share of the bar, in the bar's own middle; the two
    /// outer ones what is left, half each. So the middle is the window's
    /// middle, whatever the song's title ("ook klopt er geen fuck van deze
    /// verhoudingen", the photographer, 14 November 2026). The spec's rule
    /// (§2): 40 % of the width, down to the 8 grid, at least 304 and at most
    /// 640 (from 1600 the sides take the rest). Narrower than the outer
    /// zones' least (`sides`) allows, the middle gives way, down to its own
    /// content's least (`middle`).
    static func zones(width: Int, sides: Int = 0, middle least: Int = 0) -> Zones {
        var middle = min(max(Int(Double(width) * middleShare) / 8 * 8, middleLeast), middleMost)
        middle = min(middle, width - 2 * sides)
        middle = max(middle, least)
        let start = (width - middle) / 2
        return Zones(start: start, middle: middle, end: width - start - middle)
    }

    // MARK: - The page

    /// A page's measures: its margin, the size of its tiles, and Played
    /// lately's columns.
    nonisolated struct Page: Equatable, Sendable {
        var margin: Int
        var tile: Int
        var columns: Int
    }

    /// The spec's table (§5), by the page's own width, not the window's: the
    /// panel opened beside a page keeps its proportions. Each row from the
    /// width it starts at, narrowest first.
    static let pages: [(from: Int, page: Page)] = [
        (0, Page(margin: 24, tile: 160, columns: 1)),
        (720, Page(margin: 32, tile: 160, columns: 2)),
        (1000, Page(margin: 40, tile: 176, columns: 2)),
        (1600, Page(margin: 40, tile: 192, columns: 3)),
    ]

    static func page(width: Int) -> Page {
        pages.last { width >= $0.from }?.page ?? pages[0].page
    }
}
