// The mini player, three ways in one build, to be tried on the phone: "Kun je
// een soort debug versie maken met alle drie de versies: Spotify, glas en
// plaat" (the photographer, 20 November 2026). Each is its design branch's,
// as it was there:
//
//   - Spotify (MiniPlayerSpotify.swift, mini-bar-spotify): a glass block
//     with square corners, and under it Jukebox's own tabs on a fade and a
//     blur from the screen's foot; the system's tab bar hidden.
//   - Glas (MiniPlayerGlass.swift, mini-bar-inline): the player and the
//     tabs as one piece of glass; the system's tab bar hidden. The one he
//     chose on the phone (20 November 2026), and so the default; worked on
//     since on mini-bar-glas.
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
/// Which of the three, in UserDefaults. Glas until another is chosen: of
/// the three tried on the phone, the one he chose (20 November 2026), the
/// other two kept for now to compare again. "glass" and "record" are read
/// too, as "glas" and "plaat".
enum MiniBarVariant: RawRepresentable, CaseIterable, Identifiable {
    case spotify
    case glass
    case record

    static let key = "miniBarVariant"
    /// The one default, for every @AppStorage that reads the choice: the
    /// foot, the system tab bar's hiding and the picker must agree, or the
    /// system's bar shows under Glas's own tabs.
    static let standard = MiniBarVariant.glass

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
    @AppStorage(MiniBarVariant.key) private var variant: MiniBarVariant = .standard
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
/// the tab shown in the accent (Copper by day, Glow by night). Tapped again,
/// Navigator.select: back to the tab's first page, and on Search's first
/// page into its field.
///
/// On Spotify's fade the others are quiet (secondary). In Glas's glass
/// (`onGlass`) they are as iOS 26's own tab bar has them: the others in the
/// label's colour, the one shown in the accent on a pill of its own, its
/// round the glass's less the 4 between them.
struct TabRow: View {
    @Environment(Navigator.self) private var navigator
    @Environment(AppSettings.self) private var settings

    var onGlass = false

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
        .padding(.horizontal, onGlass ? Theme.Space.xs : Theme.Space.s)
        .padding(.vertical, onGlass ? Theme.Space.xs : 0)
        // The two lines fit the row up to here, as the block's.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func button(_ item: Item) -> some View {
        let isShown = navigator.tab == item.tab
        let others: AnyShapeStyle = onGlass ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        return Button {
            navigator.select(item.tab)
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
            .foregroundStyle(isShown ? AnyShapeStyle(Theme.accent) : others)
            .frame(maxWidth: .infinity,
                   minHeight: onGlass ? GlassTabFoot.tabsHeight - 2 * Theme.Space.xs : 49)
            .background {
                if onGlass, isShown {
                    Capsule().fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .accessibilityIdentifier(item.id)
    }
}

/// The cover the three bars show, and the label on Glas's and Plaat's
/// records. The song's own cover first; when it has none (no artwork, or the
/// server answered without one) and it plays from a station or a mix, the
/// artwork the app makes for that station or mix, as Home's On air card and
/// Played lately show it; else the album's title sleeve. At 44 points a
/// sleeve is its first letter, and that "S" was all the bar showed of a
/// station: "het zelfgemaakte album art niet zichtbaar" (the photographer,
/// 20 November 2026).
struct MiniPlayerCover: View {
    let size: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.artwork

    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(MixStore.self) private var mixes
    @Environment(\.displayScale) private var displayScale

    /// The url the server had no cover for, once asked.
    @State private var missingURL: URL?

    var body: some View {
        Group {
            if player.currentTrack == nil, radio.isStarting, let station = radio.station {
                // A station chosen while nothing played.
                StationArtwork(station: station, size: size, cornerRadius: cornerRadius)
            } else if hasNoCover, let station = player.context?.station {
                StationArtwork(station: station, size: size, cornerRadius: cornerRadius)
            } else if hasNoCover, let mix {
                CollageArtwork(artworks: mix.artwork, size: size, cornerRadius: cornerRadius)
            } else {
                ArtworkView(player.currentTrack?.artwork, size: size, cornerRadius: cornerRadius,
                            sleeve: player.currentTrack.map(TitleSleeve.Words.init(track:)))
            }
        }
        // The same download as ArtworkView's (ImagePipeline joins the two),
        // to learn whether the server has a cover at all.
        .task(id: url) {
            guard let url else { return }
            let image = await ImagePipeline.shared.image(for: url)
            guard !Task.isCancelled else { return }
            if image == nil, ImagePipeline.shared.isMissing(url) { missingURL = url }
        }
    }

    private var url: URL? {
        guard let artwork = player.currentTrack?.artwork, let server = app.server else { return nil }
        return server.artworkURL(artwork, maxPixelSize: ImagePipeline.bucket(Int(size * displayScale)))
    }

    private var hasNoCover: Bool {
        guard player.currentTrack != nil else { return false }
        guard let url else { return true }
        return missingURL == url || ImagePipeline.shared.isMissing(url)
    }

    private var mix: Mix? {
        guard case let .mix(id)? = player.context?.kind else { return nil }
        return mixes.mixes.first { $0.id == id }
    }
}
#endif
