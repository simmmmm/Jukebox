// Jukebox's few tokens and styles. The chrome is Apple's own (tab bar,
// navigation bars, lists, menus, sheets: HIG, native); what makes it Jukebox
// lives in the content — the Arch (docs/BRAND.md): two tubes of light and a
// core, the arch only ever meaning a station; one accent, Copper in light
// mode and Glow in dark, one hue seen in two exposures; Cabinet, the warm
// dark the light stands in; one filled button per screen and it is the
// accent; small grey spaced section labels. The photographer, 8 November
// 2026: "Het heeft nu wel heel weinig eigen branding en je hergebruikt nu
// het numa logo daar mag je wel meer eigen vorm aan geven" — and, of the
// four directions drawn, "Die arch is leuk." A sibling of Numa in restraint
// and in care, no longer in its shapes.

import SwiftUI
import UIKit

enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        /// A cover in a row or a grid, as Music has it.
        static let artwork: CGFloat = 8
        /// A small cover in a list row.
        static let thumbnail: CGFloat = 6
        static let card: CGFloat = 14
        static let button: CGFloat = 12
    }

    /// A page's side margin, as Music and the system lists use.
    static let margin: CGFloat = 20

    /// The accent: Copper (#A84A17) in light mode, Glow (#FFB54D) in dark —
    /// the asset catalog's AccentColor. What is chosen, playing or touched:
    /// tint, selection, the one filled button. Copper is 5.7:1 on white and
    /// 5.2:1 on the grouped grey; Glow 12:1 on black and 9.7:1 on the dark
    /// grouped grey.
    static let accent = Color.accentColor

    /// Text and glyphs on the accent: white on Copper (5.7:1), Ink on Glow
    /// (9.9:1). Glow is a light colour: white on it would all but vanish.
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: 0x2A1505) : .white
    })

    /// A near-black (#141414) for what is always dark and takes its colours
    /// from elsewhere: Now Playing's backdrop behind the cover's own.
    static let page = Color(white: 0x14 / 255)

    /// The Arch's own colours (docs/BRAND.md, dev/brand/). Cabinet, Glow,
    /// Copper and Ink are the identity's; the tubes' colours are for art
    /// only — the icon, a station's artwork, the welcome — never for text.
    enum Arch {
        /// Cabinet, #1E0A07: the warm dark of a jukebox's cabinet, the
        /// ground the light stands in — the app icon, the welcome, Your
        /// Station's card, every lit core. Dark in light mode too.
        static let cabinet = Color(rgb: 0x1E0A07)
        /// The cabinet where its tubes light it, #4A1D0F: the top of a lit
        /// ground's gradient.
        static let cabinetHaze = Color(rgb: 0x4A1D0F)
        /// Glow, #FFB54D: the accent in dark mode (AccentColor's dark half).
        static let glow = Color(rgb: 0xFFB54D)
        /// Copper, #A84A17: the accent in light mode, Glow's own hue seen by
        /// day — from the Tonearm direction, in place of a redder ember that
        /// sat too near Last.fm's red.
        static let copper = Color(rgb: 0xA84A17)
        /// Ink, #2A1505: words and glyphs on Glow.
        static let ink = Color(rgb: 0x2A1505)
        /// Filament, #FFF4DE: the core's light, the brightest thing in the art.
        static let filament = Color(rgb: 0xFFF4DE)
        /// The mark's core: amber (#F7A136) on light grounds, where filament
        /// would vanish; a warm white (#FFF1D6) on dark ones.
        static let markCore = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: 0xFFF1D6) : UIColor(rgb: 0xF7A136)
        })

        // Art only.

        /// The outer tube, #F07E36, deepening to #D45A22 at its feet in the icon.
        static let outerTube = Color(rgb: 0xF07E36)
        static let outerTubeFoot = Color(rgb: 0xD45A22)
        /// The inner tube, #FFB44C, to #F49A30 at its feet.
        static let innerTube = Color(rgb: 0xFFB44C)
        static let innerTubeFoot = Color(rgb: 0xF49A30)
        /// The hot line down the middle of each tube, where the gas is brightest.
        static let outerTubeHeart = Color(rgb: 0xFFC08A)
        static let innerTubeHeart = Color(rgb: 0xFFE3AE)
        /// The core lit in art: #FFFBF0 at its top to #FFD58E at its foot,
        /// and its bloom.
        static let coreTop = Color(rgb: 0xFFFBF0)
        static let coreFoot = Color(rgb: 0xFFD58E)
        static let coreBloom = Color(rgb: 0xFFC46A)
        /// The light the tubes throw on the room around them, #FF8A2A.
        static let roomGlow = Color(rgb: 0xFF8A2A)
    }

    /// Numa's section label: 11 pt semibold, spaced, upper case, grey.
    static let eyebrow = Font.system(size: 11, weight: .semibold)
    static let eyebrowTracking: CGFloat = 1.1
}

/// Numa's small grey spaced label, between groups: "MADE FOR YOU".
struct Eyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow)
            .tracking(Theme.eyebrowTracking)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A shelf's header as Music has it — a bold title, a chevron when it goes
/// somewhere — with Numa's grey label above it when there is one.
struct SectionHeader<Destination: Hashable>: View {
    let title: String
    var eyebrow: String?
    var destination: Destination?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow { Eyebrow(eyebrow) }
            if let destination {
                NavigationLink(value: destination) {
                    HStack(spacing: 4) {
                        Text(title).font(.title2.bold()).foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(title).font(.title2.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.margin)
    }
}

extension SectionHeader where Destination == Route {
    init(_ title: String, eyebrow: String? = nil, route: Route? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        destination = route
    }
}

/// The one filled button of a screen (Play, Start Radio, Sign In): the
/// accent, with its own ink on it.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, Theme.Space.l)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.button))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: Theme.Radius.button))
    }
}

/// Every other button beside it (Shuffle): grey, flat.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, Theme.Space.l)
            .background(.quaternary, in: .rect(cornerRadius: Theme.Radius.button))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: Theme.Radius.button))
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Play and Shuffle side by side, under an album's or a playlist's header.
struct PlayShuffleButtons: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.prominent)
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.secondary)
        }
    }
}

// `nonisolated`: UIKit may ask a dynamic colour's provider for its colour
// off the main actor, and the app's own code is on the main actor by default.
extension Color {
    /// An sRGB colour by its hex, as the brand board names it: 0xA84A17.
    nonisolated init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

extension UIColor {
    /// UIKit's, for colours that change with the appearance.
    nonisolated convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

extension TimeInterval {
    /// "3:07", "1:02:15".
    var clock: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "42 minutes", "1 hour, 12 minutes".
    var spoken: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = self >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .full
        return formatter.string(from: self) ?? ""
    }
}
