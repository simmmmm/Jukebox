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
#if os(iOS)
import UIKit
#endif

enum Theme {
    enum Space {
        static let xs = Tokens.Space.xs
        static let s = Tokens.Space.s
        static let m = Tokens.Space.m
        static let l = Tokens.Space.l
        static let xl = Tokens.Space.xl
        static let xxl = Tokens.Space.xxl
    }

    enum Radius {
        /// The one radius (tells.md, 6): artwork of every size, and the one
        /// filled button. Nothing else Jukebox draws is rounded; the
        /// system's own controls keep theirs.
        // grid-ok: the brand's one radius (docs/BRAND.md), not a distance.
        static let artwork = Tokens.Radius.artwork
    }

    /// A page's side margin, as Music and the system lists use.
    static let margin = Tokens.margin

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
    ///
    /// While a song plays, its cover's accent in their place (AccentTokens,
    /// PlayingTint): read here, so every part that draws the accent follows.
    static var accent: Color { Color(PlayingAccent.shared.tokens.accent) }

    /// Text and glyphs on the accent: white on Copper (5.7:1), Ink on Glow
    /// (9.9:1). Glow is a light colour: white on it would all but vanish.
    static var onAccent: Color { Color(PlayingAccent.shared.tokens.onAccent) }
    /// The word on a quiet button's faint accent ground (ActionButtonStyle,
    /// Linux's button.quiet): by day a step darker than Copper, as Copper
    /// on its own 12 % tint read 4.0:1 on the raised ground; this reads 4.9
    /// at the least. By night Glow, 7.8 and up. "zorg dat ze goed zichtbaar
    /// zijn in dark en light mode" (the photographer, 20 November 2026).
    static var quietInk: Color { Color(PlayingAccent.shared.tokens.quietInk) }

    /// The ground the main screens stand on, flat (tells.md, 2): warm paper,
    /// #F6F3EE, by day, as a sleeve's card stock; #121110 by night, a black
    /// with a little warmth in it. No vignette, no gradient. Lists the
    /// system draws (Settings, the library's long lists) keep the system's
    /// own grounds.
    static let ground = Color(Tokens.ground)

    /// One step up from the ground, for the wide window's sidebar, panel
    /// and bar (the designer's spec, §1; Linux's Style.swift `raised`):
    /// #ECE7DF by day, #1B1918 by night.
    static let raised = Color(Tokens.raised)

    /// Home's music to go on with, beside Your Station on a wide page: a
    /// step lighter ("'where you left off' misschien in een lichtere tint",
    /// the photographer, 18 November 2026). By night one step up from
    /// raised, #242120; by day halfway back to the paper, #F1EDE6, as a
    /// step past it would no longer read as a card. Linux's `lighter`.
    static let raisedLighter = Color(Tokens.raisedLighter)

    /// Home's word that the server is out of reach: a soft warning, in the
    /// Arch's own amber rather than the system's yellow ("een warning
    /// dingetje met een zacht warning kleurtje in stijl van jukebox", the
    /// photographer, 20 November 2026). The mark core's amber, #F7A136, at
    /// 16% on the paper by day, #F6E6D1; Glow at 12% on the night by
    /// night, #2E2517. Copper on it 5.1:1, Glow 8.6:1. Linux's `notice`.
    static let notice = Color(Tokens.notice)

    /// The Arch's own colours (docs/BRAND.md). Cabinet, Glow,
    /// Copper and Ink are the identity's; the tubes' colours are for art
    /// only — the station on the air, the icon — never for text.
    enum Arch {
        /// Cabinet, #1E0A07: the warm dark of a jukebox's cabinet — the app
        /// icon, Now Playing's ground, a station's room until its cover's
        /// colour is known. Dark in light mode too.
        static let cabinet = Color(rgb: Tokens.Arch.cabinet)
        /// Glow, #FFB54D: the accent in dark mode (AccentColor's dark half),
        /// and the inner band of every arch.
        static let glow = Color(rgb: Tokens.Arch.glow)
        /// Copper, #A84A17: the accent in light mode, Glow's own hue seen by
        /// day, and the outer band of every arch.
        static let copper = Color(rgb: Tokens.Arch.copper)
        /// Ink, #2A1505: words and glyphs on Glow.
        static let ink = Color(rgb: Tokens.Arch.ink)
        /// The mark's core: amber (#F7A136) on light grounds, where a warm
        /// white would vanish; a warm white (#FFF1D6) on dark ones.
        static let markCore = Color(Tokens.Arch.markCore)

        // Art only: the station on the air, which alone is lit.

        /// The outer tube lit, #F07E36.
        static let outerTube = Color(rgb: Tokens.Arch.outerTube)
        /// The inner tube lit, #FFB44C.
        static let innerTube = Color(rgb: Tokens.Arch.innerTube)
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
    /// A Mac window has no navigation bar to style: there the pages' own
    /// titles are the serif ones.
    static func styleNavigationBars() {
        #if os(iOS)
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: serifUIFont(.largeTitle)]
        bar.titleTextAttributes = [.font: serifUIFont(.body)]
        #endif
    }

    #if os(iOS)

    /// The system font's serif design (New York) for `style`, at the size
    /// the default text size gives it, scaled for the reader's.
    private static func serifUIFont(_ style: UIFont.TextStyle) -> UIFont {
        let standard = UITraitCollection(preferredContentSizeCategory: .large)
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: standard)
        let serif = base.withDesign(.serif) ?? base
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: serif, size: 0))
    }
    #endif
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
            // Wide, Linux's: 13 in the accent.
            .desktopFont(Tokens.Size.fact13.size, phone: Theme.label)
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
/// Wide, 20, as Linux's panel's head.
struct ListHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .desktopFont(Tokens.Size.panelHead.size, design: .serif, phone: .serif(.title3))
            .foregroundStyle(.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// What a page says when it has nothing to show: one plain line of what to
/// do, in the facts' grey, on the margin where its content would start, 24
/// under what is above it. Linux's `emptyLine`, 1:1 (docs/design/SYSTEM.md,
/// Notices and empty states): "favourites heeft een vage empty state" (the
/// photographer, 14 November 2026). A whole window's state (loading, could
/// not load) stays the system's ContentUnavailableView.
struct EmptyLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .desktopFont(Tokens.Size.body15.size, phone: .subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Space.xl)
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
            .fill(Color.separatorLine)
            // grid-ok: a hairline is one pixel.
            .frame(height: 1 / displayScale)
            .frame(maxWidth: .infinity)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Every other action (Shuffle, Stop, New Picks): a word in the accent, no
/// ground under it — a text button, as the system's own are. Wide, Linux's
/// word: 40 tall, 15 bold, 8 either side of the word, so beside Play it
/// stands 24 from it.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isWide) private var isWide

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .desktopFont(Tokens.Size.body15.size, weight: .bold, phone: .body)
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, isWide ? Theme.Space.s : 0)
            .frame(minHeight: isWide ? 40 : 44)
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.4)
            .contentShape(.rect)
    }
}

/// A page's actions, side by side and the same size: Play filled, the
/// screen's one filled button, and beside it Shuffle (New Picks, Stop,
/// Continue) in the same shape on a faint ground of the accent. 36 tall,
/// 96 wide at least, 15 pt; on the iPhone 4 more above and below that are
/// not drawn, so a finger still has 44. Linux's page-button and quiet, 1:1.
/// The photographer, 18 November 2026, of the artist page: "bij de artiest
/// en op meerdere plekken de buttons allemaal een beetje gek", and of
/// Home: "buttons voelen ook erg groot icm met de rest".
struct ActionButtonStyle: ButtonStyle {
    let isFilled: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isWide) private var isWide

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .desktopFont(Tokens.Size.body15.size, weight: .bold, phone: .subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isFilled ? Theme.onAccent : Theme.quietInk)
            .padding(.horizontal, Theme.Space.l)
            .frame(minWidth: Tokens.ActionButton.minWidth, minHeight: Tokens.ActionButton.height)
            .background(isFilled ? Theme.accent : Theme.accent.opacity(Tokens.ActionButton.quietTint),
                        in: .rect(cornerRadius: Theme.Radius.artwork))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .padding(.vertical, isWide ? 0 : Theme.Space.xs)
            .contentShape(.rect)
            .fixedSize()
    }
}


extension View {
    /// A glyph as one of the head's squares after Play and Shuffle (the
    /// version filter, the download, the heart, the "…"): 36 square, at
    /// the filter's weight, on Shuffle's quiet ground, or on Play's filled
    /// one (`filled`, the filter while a kind is off). One kind of square,
    /// so they cannot drift apart: a thin glyph alone beside two filled
    /// buttons read as a stray one ("ik wil niet zo'n icoontje alleen zo
    /// dunnig", the photographer, 24 November 2026).
    func quietSquare(filled: Bool = false) -> some View {
        // Wide, 15 semibold, the size of Shuffle's word and of Linux's
        // 16 px glyphs: the Mac's .subheadline is 11, and its glyphs sat
        // small in the square.
        desktopFont(Tokens.Size.body15.size, weight: .semibold, phone: .subheadline.weight(.semibold))
            .frame(width: Tokens.ActionButton.height, height: Tokens.ActionButton.height)
            .background(filled ? Theme.accent : Theme.accent.opacity(Tokens.ActionButton.quietTint),
                        in: .rect(cornerRadius: Theme.Radius.artwork))
            .contentShape(.rect)
    }

    /// A menu's items with their SF Symbols on the Mac from macOS 26, as
    /// its own apps draw their menus there; SwiftUI's Mac menus show a
    /// Label's title alone unless told otherwise ("op ios heb je al die
    /// leuke icoontjes overal, waarom heeft mac dat niet?", the
    /// photographer, 24 November 2026). Older Macs' menus, as their own
    /// apps', without; the iPhone and the iPad show them anyway.
    @ViewBuilder func menuIcons() -> some View {
        #if os(macOS)
        if #available(macOS 26, *) {
            labelStyle(.titleAndIcon)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == ActionButtonStyle {
    /// Play, in a page's row of actions.
    static var action: ActionButtonStyle { ActionButtonStyle(isFilled: true) }
    /// The one filled button of a screen that is not Play (Sign In, Try
    /// Again): the same button, one size on every client, compact; Linux's
    /// suggested-action page-button. It was 40 wide and 44 full-width on
    /// the iPhone ("Los ze op", 20 November 2026).
    static var prominent: ActionButtonStyle { ActionButtonStyle(isFilled: true) }
    /// The quieter one beside it.
    static var quietAction: ActionButtonStyle { ActionButtonStyle(isFilled: false) }
}

/// A page's row: Play and Shuffle as a pair, the same size, on every page
/// that has them (an album's, an artist's, a playlist's, a genre's, a
/// mix's), on the iPhone and on a wide page. Start Radio is in the page's
/// "…", as Linux has it. Wide, 16 apart, as Linux's head.
struct PagePlayButtons: View {
    let play: () -> Void
    var shuffle: (() -> Void)?

    @Environment(\.isWide) private var isWide

    var body: some View {
        HStack(spacing: isWide ? Theme.Space.l : Theme.Space.m) {
            Button(action: play) {
                Text("Play")
            }
            .buttonStyle(.action)
            if let shuffle {
                Button(action: shuffle) {
                    Text("Shuffle")
                }
                .buttonStyle(.quietAction)
            }
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

// `nonisolated`: the system may ask a dynamic colour's provider for its
// colour off the main actor (Color(light:dark:), Platform.swift), and the
// app's own code is on the main actor by default.
extension Color {
    /// A token's pair (Tokens.swift): its day colour by day, its night one
    /// by night.
    nonisolated init(_ pair: ColorPair) {
        self.init(light: pair.light, dark: pair.dark)
    }

    /// An sRGB colour by its hex, as the brand board names it: 0xA84A17.
    nonisolated init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
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
