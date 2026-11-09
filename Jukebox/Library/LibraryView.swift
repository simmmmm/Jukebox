// The Library tab, as Music's: the kinds of things in it (Playlists,
// Artists, Albums, Songs, Genres, Favorites, Downloaded), then what was added lately
// as a grid of covers. On the first launch, while the server is read, the
// grid's place shows how far it is.
//
// A ScrollView rather than a List: the grid's covers are each a link, and
// links inside one List row share the row's tap.

import JukeboxKit
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let recent = Array(library.recentlyAddedAlbums.prefix(sizeClass == .regular ? 16 : 12))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    LibraryLinkRow(title: "Playlists", symbol: "music.note.list", route: .playlists)
                    LibraryLinkRow(title: "Artists", symbol: "music.mic", route: .artists)
                    LibraryLinkRow(title: "Albums", symbol: "square.stack", route: .albums)
                    LibraryLinkRow(title: "Songs", symbol: "music.note", route: .songs)
                    LibraryLinkRow(title: "Genres", symbol: "guitars", route: .genres)
                    LibraryLinkRow(title: "Favorites", symbol: "heart", route: .favorites)
                    // What is on the phone: what plays without a connection.
                    LibraryLinkRow(title: "Downloaded", symbol: "arrow.down.circle", route: .downloaded, isLast: true)
                }
                .padding(.bottom, Theme.Space.xl)

                if recent.isEmpty {
                    LibraryStatusView()
                        .padding(.top, Theme.Space.xl)
                } else {
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
    }

    /// Two columns on the iPhone, as Music has it; four where there is room.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.Space.l, alignment: .top),
              count: sizeClass == .regular ? 4 : 2)
    }
}

/// One of the Library's kinds: the accent symbol, the name, the chevron,
/// a separator under it as in a list.
private struct LibraryLinkRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let route: Route
    var isLast = false

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
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

/// Every album, the newest first.
struct RecentlyAddedView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let albums = library.recentlyAddedAlbums
        ScrollView {
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
