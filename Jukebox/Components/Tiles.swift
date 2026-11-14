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
            LibraryTile(name: album.name, line: showsArtist ? album.artistLine : album.year.map(String.init)) {
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
            LibraryTile(name: playlist.name, line: playlist.trackCount.map { $0 == 1 ? "1 song" : "\($0) songs" }) {
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
            LibraryTile(name: mix.title, line: mix.subtitle, lines: 2) {
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
/// Radio" (tells.md, 5).
struct StationCard: View {
    let station: Station

    @Environment(\.isWide) private var isWide

    var body: some View {
        if isWide {
            LibraryTile(name: station.title) {
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
            LibraryTile(name: artist.name, line: artist.albumCount.map { $0 == 1 ? "1 album" : "\($0) albums" }) {
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
struct Shelf<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    var width: CGFloat = 160
    /// The page's margin: the iPhone's, or DesktopMeasures' on a wide page.
    var margin: CGFloat = Theme.margin
    @ViewBuilder let tile: (Item) -> Tile

    @Environment(\.isWide) private var isWide

    var body: some View {
        let hover = isWide ? Theme.Space.s : 0
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: isWide ? Theme.Space.xl : Theme.Space.m) {
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
        .padding(.vertical, -hover)
    }
}

/// A tile in a wide window, as Linux's (spec §8): the art as wide as the
/// tile, 8, the name in 15 medium, a fact under it in 13 at 60%. The whole
/// tile is lit under the pointer (TileHover).
struct LibraryTile<Art: View>: View {
    let name: String
    var line: String?
    var lines = 1
    @ViewBuilder let art: Art

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            art
                .padding(.bottom, Theme.Space.s)
            Text(name)
                .libraryFont(15, weight: .medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let line, !line.isEmpty {
                Text(line)
                    .libraryFont(13)
                    .foregroundStyle(.secondary)
                    .lineLimit(lines)
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

/// The desktop spec's sizes (§7) on a wide page: Linux's pixels as points,
/// the same on the Mac and the iPad ("ik wil dat de linux app en de apple
/// app 1:1 op elkaar lijken", the photographer, 14 November 2026), where
/// Apple's text styles differ by a quarter (the Mac's body is 13, the
/// iPad's 17). Scaled with the reader's text size, as a text style is.
private struct LibraryFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// 40 a page's title (serif), 24 a section's (serif), 17 an album's
    /// artist, 15 rows and tile names, 13 facts, second lines and times.
    func libraryFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(LibraryFont(size: size, weight: weight, design: design))
    }
}
