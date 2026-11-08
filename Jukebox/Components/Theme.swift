// Jukebox's few tokens and styles. The chrome is Apple's own (tab bar,
// navigation bars, lists, menus, sheets: HIG, native); what makes it a
// sibling of Numa lives in the content — white as the one accent (near-black
// in light mode, the design system's inversion), one filled button per
// screen and it is the accent, small grey spaced section labels, the eclipse.
// Numa's design system: "the chrome is the platform's own; the signatures
// make it Numa."

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

    /// The accent: white in dark mode, #141414 in light (the asset catalog's
    /// AccentColor). What is chosen, playing or touched.
    static let accent = Color.accentColor

    /// Text and glyphs on the accent.
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0x14 / 255, alpha: 1) : .white
    })

    /// Numa's `page` ground (#141414) for what is always dark — Now
    /// Playing's backdrop behind the artwork's colours.
    static let page = Color(white: 0x14 / 255)

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
