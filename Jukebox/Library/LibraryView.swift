// The Library tab, as Music's: the kinds of things in it (Playlists,
// Artists, Albums, Songs, Genres, Favorites, Downloaded), then what was added lately
// as a grid of covers. On the first launch, while the server is read, the
// grid's place shows how far it is. A kind Settings › Pages has off has no
// row, Recently Added no grid; its page is still reached from Home and
// Search.
//
// A ScrollView rather than a List: the grid's covers are each a link, and
// links inside one List row share the row's tap.

import JukeboxKit
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.isWide) private var isWide
    @State private var isShowingSettings = false

    var body: some View {
        let recent = Array(library.recentlyAddedAlbums.prefix(isWide ? 16 : 12))
        let kinds = Self.kinds.filter { kind in kind.page.map { settings.shows($0) } ?? true }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !kinds.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(kinds, id: \.route) { kind in
                            LibraryLinkRow(title: kind.title, symbol: kind.symbol, route: kind.route,
                                           isLast: kind.route == kinds.last?.route)
                        }
                    }
                    .padding(.bottom, Theme.Space.xl)
                }

                if recent.isEmpty {
                    LibraryStatusView()
                        .padding(.top, Theme.Space.xl)
                } else if settings.shows(.recentlyAdded) {
                    SectionHeader("Recently added", route: .recentlyAdded)
                        .padding(.bottom, Theme.Space.m)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.xl) {
                        ForEach(recent) { album in
                            LibraryAlbumLink(album: album)
                        }
                    }
                    .padding(.horizontal, Theme.margin)
                }
            }
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(Theme.ground)
        .navigationTitle("Library")
        .refreshable { await library.refresh() }
        // The profile as on Home and Radio, so Settings is a tap away on
        // every tab: "profiel mag ook gewoon op radio en library staan"
        // (the photographer, 20 November 2026). A wide window has it in
        // the sidebar's menu.
        .toolbar {
            if !isWide {
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Settings", systemImage: "person.crop.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }

    /// The rows, in Music's order, each with its switch in Settings › Pages.
    private static let kinds: [LibraryKind] = [
        LibraryKind(title: "Playlists", symbol: "music.note.list", route: .playlists, page: .playlists),
        LibraryKind(title: "Artists", symbol: "music.mic", route: .artists, page: .artists),
        LibraryKind(title: "Albums", symbol: "square.stack", route: .albums, page: .albums),
        LibraryKind(title: "Songs", symbol: "music.note", route: .songs, page: .songs),
        LibraryKind(title: "Genres", symbol: "guitars", route: .genres, page: .genres),
        LibraryKind(title: "Favorites", symbol: "heart", route: .favorites, page: .favorites),
        // What is on the phone: what plays without a connection.
        LibraryKind(title: "Downloaded", symbol: "arrow.down.circle", route: .downloaded, page: .downloaded),
        // The year's music, out of Settings: content, not a setting. No
        // switch in Settings › Pages, as Home has none.
        LibraryKind(title: "Your Year", symbol: "calendar", route: .yourYear, page: nil),
    ]

    /// Two columns on the iPhone, as Music has it; four where there is room.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Space.l, alignment: .top),
              count: isWide ? 4 : 2)
    }
}

private struct LibraryKind {
    let title: LocalizedStringKey
    let symbol: String
    let route: Route
    /// Its switch in Settings › Pages; nil, always there.
    let page: AppSettings.Page?
}

/// One of the Library's kinds: the accent symbol, the name, the chevron,
/// a separator under it as in a list.
private struct LibraryLinkRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let route: Route
    var isLast = false

    /// The symbols' column, 32 at the default size: it grows with the
    /// title3 glyph under Larger Text, so the glyph never runs into the name.
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 32

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Space.m)
            .padding(.horizontal, Theme.margin)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(LibraryRowButtonStyle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.leading, Theme.margin + 32 + Theme.Space.l)
            }
        }
    }
}

/// A list row's grey highlight while it is pressed.
private struct LibraryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
    }
}

/// Every album, the newest first. Wide, as Albums: the page's tiles.
struct RecentlyAddedView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    private var wide: some View {
        let albums = library.recentlyAddedAlbums
        return WidePage(title: "Recently Added") { page, width in
            PageTitle("Recently Added")
                .padding(.horizontal, page.side)
            if albums.isEmpty {
                PageEmptyLine("Albums added to your \(library.serverKind) server appear here.")
                    .padding(.horizontal, page.side)
            } else {
                LibraryAlbumGrid(albums: albums, page: page, width: width)
                    .padding(.top, Theme.Space.xl)
            }
        }
        .refreshable { await library.refresh() }
    }

    private var compact: some View {
        let albums = library.recentlyAddedAlbums
        return ScrollView {
            LibraryAlbumGrid(albums: albums)
                .padding(.vertical, Theme.Space.l)
        }
        .navigationTitle("Recently Added")
        .overlay {
            if albums.isEmpty {
                LibraryStatusView(emptyTitle: "No Albums", emptySymbol: "square.stack",
                                  emptyMessage: "Albums added to your \(library.serverKind) server appear here.")
            }
        }
        .refreshable { await library.refresh() }
    }
}
