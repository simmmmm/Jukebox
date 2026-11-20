// Jukebox's tokens: every colour, distance, size and duration the clients
// share, as plain numbers, in one place. Foundation only, so the iPhone,
// the iPad and the Mac (Theme.swift), the widget (JukeboxWidget.swift) and
// Linux (Linux/App/Style.swift, Drawings.swift) all read these same values:
// a colour changes here and changes everywhere. docs/design/SYSTEM.md
// names each one and where it is used.
//
// Why one file: the clients kept drifting apart ("We blijven teveel parity
// hebben", the photographer, 20 November 2026), and each held its own hex
// values: the quiet button's ink was changed in two places the same day.

import Foundation

/// A colour by day and by night, each an sRGB hex: 0xA84A17.
nonisolated struct ColorPair: Equatable, Sendable {
    let light: UInt32
    let dark: UInt32

    /// The one for the appearance.
    func hex(dark isDark: Bool) -> UInt32 { isDark ? dark : light }
}

nonisolated enum Tokens {
    // MARK: Colour

    /// The one accent, Copper by day and Glow by night: one hue in two
    /// exposures. What is chosen, playing or touched; the filled button.
    static let accent = ColorPair(light: Arch.copper, dark: Arch.glow)
    /// Words and glyphs on the accent: white on Copper (5.7:1), Ink on
    /// Glow (9.9:1).
    static let onAccent = ColorPair(light: 0xFFFFFF, dark: Arch.ink)
    /// The quiet button's word, on the accent at 12 %: a step darker than
    /// Copper by day (4.9:1 at the least), Glow by night (7.8 and up). "zorg
    /// dat ze goed zichtbaar zijn in dark en light mode" (20 November 2026).
    static let quietInk = ColorPair(light: 0x953F12, dark: Arch.glow)
    /// The ground the main screens stand on, flat: Paper and Night.
    static let ground = ColorPair(light: Arch.paper, dark: Arch.night)
    /// One step up: the wide window's sidebar, panel and bar; Home's cards.
    static let raised = ColorPair(light: 0xECE7DF, dark: 0x1B1918)
    /// A step lighter than raised: Home's music to go on with ("misschien in
    /// een lichtere tint", 18 November 2026).
    static let raisedLighter = ColorPair(light: 0xF1EDE6, dark: 0x242120)
    /// Menus, popovers and dialogs, lifted off the page: just lighter than
    /// the paper by day, raisedLighter by night ("kunnen we de achtergrond
    /// kleur van deze popups gelijkmaken aan de kleuren van jukebox", 20
    /// November 2026).
    static let lifted = ColorPair(light: 0xFBF9F5, dark: 0x242120)
    /// A soft warning (the server out of reach), in the Arch's amber: the
    /// mark core's at 16 % on the paper, Glow at 12 % on the night.
    static let notice = ColorPair(light: 0xF6E6D1, dark: 0x2E2517)

    /// The Arch's own colours (docs/BRAND.md). The tubes' are for art only:
    /// the station on the air, the icon; never for text.
    enum Arch {
        static let copper: UInt32 = 0xA84A17
        static let glow: UInt32 = 0xFFB54D
        static let ink: UInt32 = 0x2A1505
        static let cabinet: UInt32 = 0x1E0A07
        static let paper: UInt32 = 0xF6F3EE
        static let night: UInt32 = 0x121110
        /// The flat mark's core: amber on light grounds, a warm white on dark.
        static let markCore = ColorPair(light: 0xF7A136, dark: 0xFFF1D6)
        static let outerTube: UInt32 = 0xF07E36
        static let innerTube: UInt32 = 0xFFB44C
    }

    // MARK: Space and shape

    /// The 4-point grid ("zorg dat alles past op een 4pt grid", 14 November
    /// 2026).
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// A page's side margin on the iPhone, as Music and the system lists.
    static let margin: CGFloat = 20

    enum Radius {
        /// The one radius: artwork, and the one filled button and its twin.
        // grid-ok: a radius, the brand's 6 and concentric with it, not a distance.
        static let artwork: CGFloat = 6
        /// A tile's hover, 8 past its art: concentric, 6 + 8.
        // grid-ok: a radius, the brand's 6 and concentric with it, not a distance.
        static let tileHover: CGFloat = 14
        /// Home's cards, 12 in from their art: 6 + 12.
        // grid-ok: a radius, the brand's 6 and concentric with it, not a distance.
        static let card: CGFloat = 18
    }

    /// The filled button and its quiet twin: 36 tall, 96 wide at the least
    /// ("buttons voelen ook erg groot", 18 November 2026).
    enum ActionButton {
        static let height: CGFloat = 36
        static let minWidth: CGFloat = 96
        /// The quiet twin's ground: the accent at this opacity.
        static let quietTint = 0.12
    }

    // MARK: Type

    /// The wide window's sizes, in points (pixels on Linux), each with its
    /// line height: the designer's spec, §7. The iPhone uses the text
    /// styles these stand for, so Dynamic Type works.
    enum Size {
        /// A page's own title, serif (.largeTitle on the iPhone).
        static let pageTitle = (size: 40, line: 48)
        /// A hero's title, serif: a station's, an album's head.
        static let heroTitle = (size: 32, line: 40)
        /// A section's heading, serif (.title2).
        static let sectionTitle = (size: 24, line: 32)
        /// The panel's head and a list's heading, serif (.title3).
        static let panelHead = (size: 20, line: 28)
        static let brandName = (size: 18, line: 24)
        static let body17 = (size: 17, line: 24)
        /// Rows and buttons (.body / .subheadline).
        static let body15 = (size: 15, line: 20)
        /// Facts (.footnote).
        static let fact13 = (size: 13, line: 16)
    }

    // MARK: Motion

    /// How long things take, in seconds. Short and plain: no springs on the
    /// chrome.
    enum Motion {
        /// What appears under the pointer: a row's Remove.
        static let quick = 0.15
        /// A fade or a hover: shelf arrows, the bar over the room.
        static let standard = 0.2
        /// Lyrics' lines lighting up.
        static let slow = 0.3
    }
}
