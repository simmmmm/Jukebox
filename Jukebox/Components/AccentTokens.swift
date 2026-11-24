// The accent the whole app wears: the playing cover's while a song plays,
// Copper and Glow while nothing does. The photographer, 24 November 2026:
// "wat is er eigenlijk gebeurt met de steunkleur pakken uit de albumart?",
// then "ik wil het wel even zien dat het overal is doorgevoerd, zolang de
// gekozen kleur voldoet aan wcag contrast". A preview, not yet decided.
//
// The cover's colour (CoverAccent) made readable on the grounds Tokens.swift
// names (CoverAccent.readable): by day on the paper, the raised ground, the
// cards, the menus and the notice, white on it; by night on Night, raised,
// the cards, the menus, the notice and Cabinet, Ink on it. Both or neither:
// one hue in two exposures, as Copper and Glow are (docs/BRAND.md), so a
// cover that cannot be read in one keeps the brand's in both.
//
// Foundation only, for both clients: Theme.swift's accent on the iPhone,
// the iPad and the Mac, Style.swift's CSS on Linux.

import Foundation
import JukeboxKit

nonisolated struct AccentTokens: Equatable, Sendable {
    /// Tokens.accent's place: the accent by day and by night.
    var accent: ColorPair
    /// Tokens.onAccent's: words on it, white by day, Ink by night, always.
    var onAccent: ColorPair
    /// Tokens.quietInk's: the quiet buttons' word.
    var quietInk: ColorPair

    /// Copper and Glow: nothing plays, or the cover has no colour that reads.
    static let brand = AccentTokens(accent: Tokens.accent, onAccent: Tokens.onAccent, quietInk: Tokens.quietInk)

    init(accent: ColorPair, onAccent: ColorPair, quietInk: ColorPair) {
        self.accent = accent
        self.onAccent = onAccent
        self.quietInk = quietInk
    }

    /// The cover's accent (nil: none of its own, or no cover) as the app's.
    init(cover: AccentColor?) {
        guard let cover, let day = CoverAccent.readable(cover, on: Self.day),
              let night = CoverAccent.readable(cover, on: Self.night) else {
            self = .brand
            return
        }
        self.init(accent: ColorPair(light: day.accent.hex, dark: night.accent.hex),
                  onAccent: Tokens.onAccent,
                  quietInk: ColorPair(light: day.quietInk.hex, dark: night.quietInk.hex))
    }

    /// Every ground of an appearance the accent lands on.
    private static func grounds(dark: Bool) -> [AccentColor] {
        var pairs = [Tokens.ground, Tokens.raised, Tokens.raisedLighter, Tokens.lifted, Tokens.notice, Tokens.field]
            .map { AccentColor(hex: $0.hex(dark: dark)) }
        // The room's (Now Playing in a wide window, its bar and panel over it
        // on Linux), by night.
        if dark { pairs.append(AccentColor(hex: Tokens.Arch.cabinet)) }
        return pairs
    }

    /// The quiet buttons' tint at rest, hovered and pressed (Linux's
    /// button.quiet), over the ground they stand on that reads least.
    private static func appearance(dark: Bool) -> AccentGrounds {
        let all = grounds(dark: dark)
        let onAccent = AccentColor(hex: Tokens.onAccent.hex(dark: dark))
        // By day the darkest ground, by night the lightest: where the word
        // has least contrast.
        let quiet = (dark ? all.max { $0.luminance < $1.luminance } : all.min { $0.luminance < $1.luminance }) ?? all[0]
        let rest = Tokens.ActionButton.quietTint
        return AccentGrounds(grounds: all, onAccent: onAccent, quietGround: quiet, quietTints: [rest, 0.18, 0.24])
    }

    static let day = appearance(dark: false)
    static let night = appearance(dark: true)
}
