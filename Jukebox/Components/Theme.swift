// Jukebox's few tokens and styles. The chrome is Apple's own (tab bar,
// navigation bars, lists, menus, sheets: HIG, native); what makes it Jukebox
// lives in the content — the Arch (docs/BRAND.md): two bands and a core,
// the arch only ever meaning a station; one accent, Copper in light mode and
// Glow in dark, one hue seen in two exposures; titles in New York, as on
// record sleeves; flat grounds; one radius. The photographer, 8 November
// 2026: "Het heeft nu wel heel weinig eigen branding" — then, of the Arch's
// first build, "Ik vind het nogsteeds wel heel erg op Apple Music lijken …
// zo laat het wel heel erg weinig eigen smaak toe" and "Kun je het design
// iets minder ai maken?" The rules that came of it are docs/design/tells.md:
// light means on air, flat grounds, a serif for titles, sentence-case
// headings, facts rather than slogans, nothing rounded but artwork and the
// system's controls, one filled button a screen.

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
        /// The one radius (tells.md, 6): artwork of every size, and the one
        /// filled button. Nothing else Jukebox draws is rounded; the
        /// system's own controls keep theirs.
        static let artwork: CGFloat = 6
    }

    /// A page's side margin, as Music and the system lists use.
    static let margin: CGFloat = 20

    /// The accent: Copper (#A84A17) in light mode, Glow (#FFB54D) in dark —
    /// the same pair as the asset catalog's AccentColor. What is chosen,
    /// playing or touched: tint, selection, the one filled button, a text
    /// button. Copper is 5.7:1 on white and 5.2:1 on the grouped grey; Glow
    /// 12:1 on black and 9.7:1 on the dark grouped grey.
    ///
    /// Spelled out rather than `Color.accentColor`: on the build with the
    /// Aptabase package (run 22's screenshots) `Color.accentColor` drew the
    /// system's blue, though the catalog and its build setting were as
    /// before. JukeboxApp tints the whole app with this too.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: 0xFFB54D) : UIColor(rgb: 0xA84A17)
    })

    /// Text and glyphs on the accent: white on Copper (5.7:1), Ink on Glow
    /// (9.9:1). Glow is a light colour: white on it would all but vanish.
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: 0x2A1505) : .white
    })

    /// The ground the main screens stand on, flat (tells.md, 2): warm paper,
    /// #F6F3EE, by day, as a sleeve's card stock; #121110 by night, a black
    /// with a little warmth in it. No vignette, no gradient. Lists the
    /// system draws (Settings, the library's long lists) keep the system's
    /// own grounds.
    static let ground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: 0x121110) : UIColor(rgb: 0xF6F3EE)
    })

    /// The Arch's own colours (docs/BRAND.md, dev/brand/). Cabinet, Glow,
    /// Copper and Ink are the identity's; the tubes' colours are for art
    /// only — the station on the air, the icon — never for text.
    enum Arch {
        /// Cabinet, #1E0A07: the warm dark of a jukebox's cabinet — the app
        /// icon, Now Playing's ground, a station's room until its cover's
        /// colour is known. Dark in light mode too.
        static let cabinet = Color(rgb: 0x1E0A07)
        /// Glow, #FFB54D: the accent in dark mode (AccentColor's dark half),
        /// and the inner band of every arch.
        static let glow = Color(rgb: 0xFFB54D)
        /// Copper, #A84A17: the accent in light mode, Glow's own hue seen by
        /// day, and the outer band of every arch.
        static let copper = Color(rgb: 0xA84A17)
        /// Ink, #2A1505: words and glyphs on Glow.
        static let ink = Color(rgb: 0x2A1505)
        /// The mark's core: amber (#F7A136) on light grounds, where a warm
        /// white would vanish; a warm white (#FFF1D6) on dark ones.
        static let markCore = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: 0xFFF1D6) : UIColor(rgb: 0xF7A136)
        })

        // Art only: the station on the air, which alone is lit.

        /// The outer tube lit, #F07E36.
        static let outerTube = Color(rgb: 0xF07E36)
        /// The inner tube lit, #FFB44C.
        static let innerTube = Color(rgb: 0xFFB44C)
    }

    /// The one small label a screen may have ("On air"): sentence case, in
    /// the accent, as light means on air.
    static let label = Font.subheadline.weight(.semibold)

    /// The navigation bars' titles in New York too, as every title in the
    /// content is: the large title at the large title's size, the inline
    /// one at the body's, both at regular weight. Set once, at launch
    /// (JukeboxApp), through UIKit's appearance proxy: SwiftUI has no
    /// modifier for the bar's own title font. The sizes follow the
    /// reader's text size (UIFontMetrics), as the system's own titles do.
    static func styleNavigationBars() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serifUIFont(.largeTitle)]
        bar.titleTextAttributes = [.font: serifUIFont(.body)]
    }

    /// The system font's serif design (New York) for `style`, at the size
    /// the default text size gives it, scaled for the reader's.
    private static func serifUIFont(_ style: UIFont.TextStyle) -> UIFont {
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: standard)
        let serif = base.withDesign(.serif) ?? base
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: serif, size: 0))
    }
}

extension Font {
    /// A title in New York, the system's serif, at regular weight and at a
    /// text style's size, so it follows Dynamic Type: as on a sleeve, the
    /// title is set and everything else is SF (tells.md, 3).
    static func serif(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif, weight: .regular)
    }
}

/// The one small label a screen may have — "On air" — in sentence case and
/// in the accent: light means on air. Every other heading is a
/// SectionHeader, in the serif.
struct Eyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.label)
            .foregroundStyle(Theme.accent)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A section's heading on the page's ground: its title in the serif, in
/// sentence case ("Mixes", "Played lately"), with a fact at its end when
/// there is one ("Made at 06:00"), and See All when it goes somewhere.
struct SectionHeader<Destination: Hashable>: View {
    let title: String
    var fact: String?
    var destination: Destination?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(title)
                .font(.serif(.title2))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let fact {
                Text(fact)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let destination {
                NavigationLink(value: destination) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("See All \(title)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.margin)
    }
}

extension SectionHeader where Destination == Route {
    init(_ title: String, fact: String? = nil, route: Route? = nil) {
        self.title = title
        self.fact = fact
        destination = route
    }
}

/// A heading inside a List (a section's, a group of rows'): the serif, in
/// sentence case, as SectionHeader is on a page. The list gives its margins.
struct ListHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.serif(.title3))
            .foregroundStyle(.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A hairline between things on the ground, from `inset` to the trailing
/// edge, in place of a card (tells.md, 6): content sits on the page,
/// separated by hairlines and space.
struct Hairline: View {
    var inset: CGFloat

    init(inset: CGFloat = Theme.margin) {
        self.inset = inset
    }

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Not Divider: in a row's overlay it takes the row's axis and draws
        // a vertical line down the list (the photographer's phone, Played
        // lately: "Er zit een streep doorheen"). One pixel high, always.
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1 / displayScale)
            .frame(maxWidth: .infinity)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// The one filled button of a screen (Play, Sign In): a plain rectangle in
/// the accent, 6 pt corners, its own ink on it. No glow, no shadow, and no
/// icon unless the word needs one. Callers that want it compact give it
/// `.fixedSize()`.
struct ProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, Theme.Space.xl)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.artwork))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(.rect)
    }
}

/// Every other action (Shuffle, Stop, New Picks): a word in the accent, no
/// ground under it — a text button, as the system's own are.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.4)
            .contentShape(.rect)
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { ProminentButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Play and Shuffle side by side, under an album's or a playlist's header:
/// the page's one filled button, and Shuffle as a word beside it.
struct PlayShuffleButtons: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xl) {
            Button(action: play) {
                Text("Play")
            }
            .buttonStyle(.prominent)
            .fixedSize()
            Button(action: shuffle) {
                Text("Shuffle")
            }
            .buttonStyle(.secondary)
        }
    }
}

extension View {
    /// The page's flat ground (Theme.ground) under a ScrollView or a List:
    /// the List's own ground hidden, Theme.ground in its place, to the
    /// screen's edges. A List's rows then need `.listRowBackground(Color.clear)`.
    func pageGround() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.ground)
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
