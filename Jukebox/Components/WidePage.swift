// The parts of a wide page (the iPad's, the Mac's), one set for every page:
// Home, Radio, a mix's and a station's, the library's, Search, Downloaded.
// As Linux's pages, 1:1 ("ik wil dat de linux app en de apple app 1:1 op
// elkaar lijken", the photographer, 14 November 2026): Linux/App/Pages.swift,
// Parts.swift and Style.swift, spec §5, §7 and §8. Six parts of the app once
// had six of their own; one set, so they cannot drift apart.

import JukeboxKit
import SwiftUI

extension DesktopMeasures.Page {
    /// The page's margin, in points.
    var side: CGFloat { CGFloat(margin) }
    /// An album's, an artist's or a playlist's cover at the head of its
    /// page: 224, and 160 on a page under 720 (spec §5, Album).
    var cover: CGFloat { margin == 24 ? 160 : 224 }
}

extension View {
    /// The page's own width, for DesktopMeasures.page(width:): by the
    /// page's width, not the window's, the panel opened beside a page keeps
    /// its proportions (spec §5).
    func onPageWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { measured in
            width.wrappedValue = measured
        }
    }

    /// A row of a wide page that is a List (a playlist's, a mix's, a
    /// station's, for their order and their menus): on the page's margin
    /// and its ground, with no separator, as Linux's rows; its height its
    /// own (TrackRow's wide form is 64, 48 numbered).
    func pageRow(_ page: DesktopMeasures.Page) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: page.side, bottom: 0, trailing: page.side))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// A wide page: one scrolling column on the page's flat ground, and the
/// bar's title once the page's own has scrolled under it. Every wide page
/// starts here, its title or head 24 under the bar at the page's margin, so
/// each starts where the others do (Linux's Artists once had a container of
/// its own and sat 24 higher: "artists heeft opeens een andere pagina
/// container als de andere?", 14 November 2026). `content` gets the page's
/// measures and its width.
struct WidePage<Content: View>: View {
    /// The bar's title, once the page's own has scrolled away.
    let title: String
    /// The page opens with a head (a cover, the title at its foot) rather
    /// than a title alone.
    var hasHead = false
    let content: (DesktopMeasures.Page, CGFloat) -> Content

    /// The default row of the table until the page has been measured.
    @State private var width: CGFloat = 1000

    // Spelled out: the private state would make the memberwise one private.
    init(title: String, hasHead: Bool = false,
         @ViewBuilder content: @escaping (DesktopMeasures.Page, CGFloat) -> Content) {
        self.title = title
        self.hasHead = hasHead
        self.content = content
    }

    var body: some View {
        let page = DesktopMeasures.page(width: Int(width))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content(page, width)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 40)
        }
        .pageGround()
        .onPageWidth($width)
        // The title's foot: 24 under the bar and 48 tall, or the cover's.
        .libraryScrolledTitle(title, after: hasHead ? page.cover + Theme.Space.xl : 72)
    }
}

/// A wide page's title in the serif, 40, 24 under the bar; at most one fact
/// under it, 4 below. The caller puts it on the page's margin.
struct PageTitle: View {
    let title: String
    var fact: String?

    init(_ title: String, fact: String? = nil) {
        self.title = title
        self.fact = fact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .desktopFont(40, design: .serif)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let fact, !fact.isEmpty {
                Text(fact)
                    .desktopFont(13)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Theme.Space.xl)
    }
}

/// A section's heading on a wide page: sentence case in the serif, 24, a
/// fact beside it, 12 on, in 13 ("Made at 06:00"); 40 above it and 16 to
/// what it heads (8 to rows). The caller puts it on the page's margin.
/// No See All: as on Linux, the sidebar goes there.
struct PageSectionTitle: View {
    let title: String
    var fact: String?
    var above: CGFloat = 40
    var below: CGFloat = Theme.Space.l

    init(_ title: String, fact: String? = nil, above: CGFloat = 40, below: CGFloat = Theme.Space.l) {
        self.title = title
        self.fact = fact
        self.above = above
        self.below = below
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(title)
                .desktopFont(24, design: .serif)
                .accessibilityAddTraits(.isHeader)
            if let fact, !fact.isEmpty {
                Text(fact)
                    .desktopFont(13)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, above)
        .padding(.bottom, below)
    }
}

/// What a wide page says when it has nothing: one plain line of what to
/// do, 24 under the title, on the margin, not a status page in the middle
/// ("favourites heeft een vage empty state", the photographer, 14 November
/// 2026). While the library is still loading, or could not, its status in
/// place of the line: the progress, Try Again.
struct PageEmptyLine: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch library.state {
        case .loading, .failed:
            LibraryStatusView()
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
        case .empty, .loaded:
            PagePlainLine(text)
        }
    }
}

/// One plain line in 15 at 60%, 24 under what is above it.
struct PagePlainLine: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .desktopFont(15)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Theme.Space.xl)
    }
}

/// Tiles as Linux's grid (GtkGridView): as many columns as the page's tile
/// and its 24 of gap fit, sharing the width evenly, each tile at its
/// column's start, from the page's margin. Each tile carries its gap at its
/// end, so the last column's sits in the right margin.
struct TileGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let page: DesktopMeasures.Page
    let width: CGFloat
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        let size = CGFloat(page.tile)
        let gap = Theme.Space.xl
        // At least one: the first pass may measure nothing.
        let count = max(1, Int((width - 2 * page.side + gap) / (size + gap)))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .topLeading), count: count),
                  alignment: .leading, spacing: gap) {
            ForEach(items) { item in
                tile(item)
                    .frame(width: size)
            }
        }
        .padding(.leading, page.side)
        .padding(.trailing, page.side - gap)
    }
}

/// The head of an album's, an artist's, a playlist's or a genre's page
/// (spec §5, Album; Linux's Pages.heading): the cover at the left, and 32
/// beside it, at its foot, the title in the serif 40, the lead (an album's
/// artist) in 17, the facts in 13, and 24 under them the one Play and the
/// rest, 16 apart. 24 under the bar, on the page's margin.
struct PageHead<Art: View, Actions: View>: View {
    let page: DesktopMeasures.Page
    let title: String
    var lead: String?
    /// The lead as a link: an album's artist opens their page.
    var leadAction: (() -> Void)?
    let facts: String
    @ViewBuilder let art: (CGFloat) -> Art
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.xxl) {
            art(page.cover)
                .frame(width: page.cover, height: page.cover)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .desktopFont(40, design: .serif)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                if let lead, !lead.isEmpty {
                    Group {
                        if let leadAction {
                            Button(action: leadAction) {
                                Text(lead)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows the artist")
                        } else {
                            Text(lead)
                        }
                    }
                    .desktopFont(17)
                    .lineLimit(1)
                    .padding(.top, Theme.Space.xs)
                }
                if !facts.isEmpty {
                    Text(facts)
                        .desktopFont(13)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, Theme.Space.xs)
                }
                HStack(spacing: Theme.Space.l) {
                    actions
                }
                .padding(.top, Theme.Space.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Theme.Space.xl)
        .padding(.horizontal, page.side)
    }
}

/// The hairline 32 under a head and 24 over its rows.
struct PageRule: View {
    let page: DesktopMeasures.Page

    var body: some View {
        Hairline(inset: 0)
            .padding(.top, Theme.Space.xxl)
            .padding(.bottom, Theme.Space.xl)
            .padding(.horizontal, page.side)
    }
}

/// A head's Play, the page's one filled button, and Shuffle, a word in the
/// accent beside it (Linux's playButton and wordButton): 15 bold.
struct PagePlayButtons: View {
    let play: () -> Void
    var shuffle: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Button(action: play) {
                Text("Play")
                    .desktopFont(15, weight: .bold)
            }
            .buttonStyle(.prominent)
            .fixedSize()
            if let shuffle {
                WordButton("Shuffle", action: shuffle)
            }
        }
    }
}

/// Every other action on a wide page: a word in the accent, 15 bold.
struct WordButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .desktopFont(15, weight: .bold)
        }
        .buttonStyle(.secondary)
        .fixedSize()
    }
}

/// A head's heart, 32: filled and in the accent when given.
struct HeartButton: View {
    let item: ItemRef

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let given = library.isFavorite(item.id)
        Button {
            Task { await library.toggleFavorite(item) }
        } label: {
            Image(systemName: given ? "heart.fill" : "heart")
                .desktopFont(15)
                .foregroundStyle(given ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(given ? Text("Undo Favorite") : Text("Favorite"))
    }
}

/// A head's "…", 32: the rest of what can be done with what the page shows.
/// A plain glyph, without the Mac's pop-up button around it.
struct MoreMenu<Items: View>: View {
    @ViewBuilder let items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: "ellipsis")
                .desktopFont(15, weight: .semibold)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
    }
}

/// A tile in a wide window, as Linux's (spec §8): the art as wide as the
/// tile, 8, the name in 15 medium, a fact under it in 13 at 60%. The whole
/// tile is lit under the pointer (TileHover).
struct WideTile<Art: View>: View {
    let name: String
    var line: String?
    @ViewBuilder let art: Art

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            art
                .padding(.bottom, Theme.Space.s)
            Text(name)
                .desktopFont(15, weight: .medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let line, !line.isEmpty {
                Text(line)
                    .desktopFont(13)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .modifier(TileHover())
        .accessibilityElement(children: .combine)
    }
}

/// The pointer over a tile (the Mac's, the iPad's): the whole tile lit, 8
/// past it on every side, its corners concentric with the art's, so the
/// light sits on the tile — on Linux a hover that did not was "fucking
/// raar" (the photographer, 14 November 2026).
private struct TileHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork + Theme.Space.s)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
                    .padding(-Theme.Space.s)
            }
            .onHover { isHovered = $0 }
    }
}

/// The desktop spec's sizes (§7) on a wide surface, the one way a wide
/// surface sets its type: Linux's pixels as points, the same on the Mac and
/// the iPad ("ik wil dat de linux app en de apple app 1:1 op elkaar
/// lijken", the photographer, 14 November 2026), where Apple's text styles
/// differ by a quarter (the Mac's body is 13, the iPad's 17). Scaled with
/// the reader's text size, as a text style is: a title as the large title,
/// the rest as the body.
private struct DesktopFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    /// A view the iPhone shares: its own font (nil, none) wherever the
    /// surface is not wide.
    let isShared: Bool
    let phone: Font?
    /// Whether the surface is wide, when it knows better than its size
    /// class (the iPad's sheets are compact); else the environment's.
    let wide: Bool?

    @Environment(\.isWide) private var isWide

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, isShared: Bool, phone: Font?, wide: Bool?) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: size >= 24 ? .largeTitle : .body)
        self.weight = weight
        self.design = design
        self.isShared = isShared
        self.phone = phone
        self.wide = wide
    }

    func body(content: Content) -> some View {
        let desktop = Font.system(size: size, weight: weight, design: design)
        return content.font(!isShared || (wide ?? isWide) ? desktop : phone)
    }
}

extension View {
    /// Linux's sizes (Style.swift): 40 a page's title, 32 the station on
    /// the air's, 24 a section's (the three in the serif), 20 the panel's
    /// head, 18 the sidebar's name and the lyrics, 17 an album's artist, 15
    /// rows, tile names and the buttons, 13 facts, second lines and times.
    func desktopFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(DesktopFont(size: size, weight: weight, design: design, isShared: false, phone: nil, wide: nil))
    }

    /// The same, in a view the iPhone shares: Linux's size where the
    /// surface is wide, the iPhone's own `phone` elsewhere, as it was (nil:
    /// none, the system's body, for a view that had no font of its own and
    /// no ancestor's).
    func desktopFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                     phone: Font?, wide: Bool? = nil) -> some View {
        modifier(DesktopFont(size: size, weight: weight, design: design, isShared: true, phone: phone, wide: wide))
    }
}
