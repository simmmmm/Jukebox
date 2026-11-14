// The tiles of a shelf or a grid: an album, a playlist, a mix, a station,
// an artist. A cover as wide as offered, its corners the one radius, one or
// two lines under it; each a NavigationLink or a button where it is used.
// In a wide window (the iPad's, the Mac's) each is Linux's tile (spec §8):
// the art, 8, the name in 15 medium, a fact in 13, and the whole tile lit
// under the pointer.

import JukeboxKit
import SwiftUI

struct AlbumTile: View {
    let album: Album
    var showsArtist = true

    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            WideTile(name: album.name, line: showsArtist ? album.artistLine : album.year.map(String.init)) {
                ArtworkView(album.artwork)
            }
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ArtworkView(album.artwork)
            Text(album.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if showsArtist {
                Text(album.artistLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let year = album.year {
                Text(String(year))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct PlaylistTile: View {
    let playlist: Playlist
    /// Covers of its first tracks, when it has no image of its own.
    var fallback: [Artwork] = []

    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            WideTile(name: playlist.name, line: playlist.trackCount.map { $0 == 1 ? "1 song" : "\($0) songs" }) {
                art
            }
        } else {
            compact
        }
    }

    @ViewBuilder
    private var art: some View {
        if let artwork = playlist.artwork {
            ArtworkView(artwork, placeholder: "music.note.list")
        } else if !fallback.isEmpty {
            CollageArtwork(artworks: fallback)
        } else {
            ArtworkView(nil, placeholder: "music.note.list")
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            art
            Text(playlist.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let count = playlist.trackCount {
                Text(count == 1 ? "1 song" : "\(count) songs")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A made-up playlist: its collage, square, and under it its title and its
/// artists — the names under the art, not on a scrim over it (tells.md, 5:
/// a mix's artists are its fact). No light of the arch's: a mix ends, and
/// the arch means a station (docs/BRAND.md).
struct MixCard: View {
    let mix: Mix

    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            // One line of its artists, as Linux's tile.
            WideTile(name: mix.title, line: mix.subtitle) {
                CollageArtwork(artworks: mix.artwork)
            }
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            CollageArtwork(artworks: mix.artwork)
                .padding(.bottom, Theme.Space.xs)
            Text(mix.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(mix.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A station: its arch over its seed's music, flat unless it is on the air;
/// its name under it as real text, which follows the reader's text size.
/// No subtitle: "Radiohead and artists like them" only repeats "Radiohead
/// Radio" (tells.md, 5). In a wide window a fact under it where the page
/// gives one ("Played Thursday"), as Linux's tile.
struct StationCard: View {
    let station: Station
    var fact: String?

    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            WideTile(name: station.title, line: fact) {
                StationArtwork(station: station)
            }
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            StationArtwork(station: station)
                .padding(.bottom, Theme.Space.xs)
            Text(station.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

struct ArtistTile: View {
    let artist: Artist

    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            // Square and left-aligned, as Linux's Artists.
            WideTile(name: artist.name, line: artist.albumCount.map { $0 == 1 ? "1 album" : "\($0) albums" }) {
                ArtworkView(artist.artwork, placeholder: "music.mic")
            }
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(spacing: Theme.Space.s) {
            ArtistAvatar(artist: artist)
            Text(artist.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A shelf that scrolls sideways, its tiles `width` wide, snapping to them,
/// starting at the page's margin and running off the right edge, so the
/// next tile peeks in (tells.md, 8). Wide, the tiles are 24 apart (spec §8),
/// with room above and below for their hover, which reaches 8 past them.
/// Under a pointer, as Linux's: no scrollbar, but ‹ and › at its ends when
/// there is more that way, on the middle of the art. A finger swipes.
struct Shelf<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    var width: CGFloat = 160
    /// The page's margin: the iPhone's, or DesktopMeasures' on a wide page.
    var margin: CGFloat = Theme.margin
    @ViewBuilder let tile: (Item) -> Tile

    @Environment(\.isWide) private var isWide
    @State private var reach = ShelfReach()
    @State private var isHovered = false

    // Spelled out: the private state would make the memberwise one private.
    init(items: [Item], width: CGFloat = 160, margin: CGFloat = Theme.margin,
         @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.width = width
        self.margin = margin
        self.tile = tile
    }

    var body: some View {
        let hover = isWide ? Theme.Space.s : 0
        let spacing = isWide ? Theme.Space.xl : Theme.Space.m
        let stride = width + spacing
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        tile(item).frame(width: width)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, hover)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, margin, for: .scrollContent)
            // Which tile is first, how many show, and is there more either
            // way: these change a tile at a time, not with every point. The
            // container is the width between the margins, as measured on
            // the Mac (15 November 2026): the offset runs from 0 to the
            // content's width less the container's.
            .onScrollGeometryChange(for: ShelfReach.self) { geometry in
                let offset = geometry.contentOffset.x + geometry.contentInsets.leading
                let end = geometry.contentSize.width - geometry.containerSize.width
                return ShelfReach(first: Int((offset / stride).rounded()),
                                  shown: Int(geometry.containerSize.width / stride),
                                  back: offset > 1,
                                  on: offset < end - 1)
            } action: { _, reach in
                self.reach = reach
            }
            .overlay(alignment: .top) {
                if isWide {
                    HStack(spacing: 0) {
                        if isHovered && reach.back {
                            arrow("chevron.left", "Scroll Back") { step(-1, proxy) }
                        }
                        Spacer(minLength: 0)
                        if isHovered && reach.on {
                            arrow("chevron.right", "Scroll On") { step(1, proxy) }
                        }
                    }
                    .padding(.horizontal, Theme.Space.s)
                    // On the middle of the art, the tile's square top.
                    .padding(.top, hover + width / 2 - 16)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .animation(.easeInOut(duration: 0.15), value: reach)
                }
            }
        }
        .onHover { isHovered = isWide && $0 }
        .padding(.vertical, -hover)
    }

    /// On by what shows less one tile, so the last one seen comes first.
    private func step(_ direction: Int, _ proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let target = min(max(reach.first + direction * max(1, reach.shown - 1), 0), items.count - 1)
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(items[target].id, anchor: .leading)
        }
    }

    /// 32 round, on the ground one step up, a soft shadow.
    private func arrow(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .desktopFont(13, weight: .semibold)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Theme.raised.opacity(0.9))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
}

/// Where a shelf is: its first tile, how many fit, and whether there is
/// more before and after.
private struct ShelfReach: Equatable {
    var first = 0
    var shown = 1
    var back = false
    var on = false
}
