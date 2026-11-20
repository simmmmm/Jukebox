// The mini player, three ways in one build, to be tried on the phone: "Kun je
// een soort debug versie maken met alle drie de versies: Spotify, glas en
// plaat" (the photographer, 20 November 2026). Each is its design branch's,
// as it was there:
//
//   - Spotify (MiniPlayerSpotify.swift, mini-bar-spotify): a glass block
//     with square corners, and under it Jukebox's own tabs on a fade and a
//     blur from the screen's foot; the system's tab bar hidden.
//   - Glas (MiniPlayerGlass.swift, mini-bar-inline): the player and the
//     tabs as one piece of glass; the system's tab bar hidden.
//   - Plaat (MiniPlayerRecord.swift, mini-bar-free-b): the system's tab bar,
//     the song above it on a ground of the cover's colour under an arch,
//     the record on the tab bar's shoulder.
//
// Settings › Library › Player Bar (test) chooses, and the choice holds at
// once, on every tab; `-miniBarVariant spotify|glas|plaat` at launch does
// the same (UserDefaults' argument domain), for the walk.
//
// The tabs' alone (the iPhone, a narrow iPad window). The wide window, the
// iPad's and the Mac's, has the player's bar across its foot instead, as
// Linux's (PlayerBar), so this is never there.

import JukeboxKit
import SwiftUI

#if os(iOS)
/// Which of the three, in UserDefaults. Plaat until another is chosen: the
/// one on main's way. "glass" and "record" are read too, as "glas" and
/// "plaat".
enum MiniBarVariant: RawRepresentable, CaseIterable, Identifiable {
    case spotify
    case glass
    case record

    static let key = "miniBarVariant"

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "spotify": self = .spotify
        case "glas", "glass": self = .glass
        case "plaat", "record": self = .record
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .spotify: "spotify"
        case .glass: "glas"
        case .record: "plaat"
        }
    }

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .spotify: "Spotify"
        case .glass: "Glass"
        case .record: "Record"
        }
    }

    /// Plaat keeps the system's tab bar; the other two draw their own.
    var hidesSystemTabBar: Bool {
        self != .record
    }
}

/// Each tab's foot: the chosen player, and with Spotify and Glas the tabs,
/// in the page's safe area. One inset whatever is chosen, so a change swaps
/// what is in it and never the page above (nor the Settings sheet that page
/// shows, where the choice is made).
struct MiniBarFoot: ViewModifier {
    @AppStorage(MiniBarVariant.key) private var variant: MiniBarVariant = .record
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio

    /// The keyboard up (Search): Spotify's and Glas's tabs go, as the
    /// system's bar went behind it. Here, not in the foot: Glas's is gone
    /// altogether while the keyboard is up and nothing plays, and would not
    /// hear it go down.
    @State private var isKeyboardUp = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                switch variant {
                case .spotify:
                    SpotifyTabFoot(isKeyboardUp: isKeyboardUp)
                case .glass:
                    GlassTabFoot(isKeyboardUp: isKeyboardUp)
                case .record:
                    RecordMiniPlayerBar()
                }
            }
            // Plaat's song comes and goes with the page making room for it.
            .animation(.easeInOut(duration: 0.25), value: recordIsShown)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardUp = false
            }
    }

    private var recordIsShown: Bool {
        variant == .record && RecordMiniPlayerBar.isShown(player: player, radio: radio)
    }
}

/// The tabs, Jukebox's own, for Spotify and Glas: the symbol over its name,
/// the tab shown in the accent (Copper by day, Glow by night), the others
/// quiet, on the fade or in the glass their foot gives them. Tapped again,
/// the tab's page goes back to its first, as the system's tab bar does.
struct TabRow: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings

    private struct Item {
        let tab: AppTab
        let title: LocalizedStringKey
        let symbol: String
        /// The walk finds the tab by this (JukeboxUITests).
        let id: String
    }

    private var items: [Item] {
        [
            Item(tab: .home, title: "Home", symbol: "house.fill", id: "tab.home"),
            Item(tab: .radio, title: "Radio", symbol: "dot.radiowaves.left.and.right", id: "tab.radio"),
            Item(tab: .library, title: "Library", symbol: "square.stack.fill", id: "tab.library"),
            Item(tab: .search, title: "Search", symbol: "magnifyingglass", id: "tab.search"),
        ]
        .filter { MainTabView.shows($0.tab, settings: settings, navigator: navigator) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                button(item)
            }
        }
        .padding(.horizontal, Theme.Space.s)
        // The two lines fit the row up to here, as the block's.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func button(_ item: Item) -> some View {
        let isShown = navigator.tab == item.tab
        return Button {
            if isShown {
                navigator.path(for: item.tab).wrappedValue = NavigationPath()
            } else {
                navigator.tab = item.tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: item.symbol)
                    .font(.title3)
                    // One height for the four symbols, so the names line up.
                    .frame(height: 26)
                Text(item.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isShown ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .accessibilityIdentifier(item.id)
    }
}
#endif
