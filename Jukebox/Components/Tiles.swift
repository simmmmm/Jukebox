// The tiles of a shelf or a grid: an album, a playlist, a mix, a station,
// an artist. A cover as wide as offered, its corners the one radius, one or
// two lines under it; each a NavigationLink or a button where it is used.

import JukeboxKit
import SwiftUI

struct AlbumTile: View {
    let album: Album
    var showsArtist = true

    var body: some View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let artwork = playlist.artwork {
                ArtworkView(artwork, placeholder: "music.note.list")
            } else if !fallback.isEmpty {
                CollageArtwork(artworks: fallback)
            } else {
                ArtworkView(nil, placeholder: "music.note.list")
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            CollageArtwork(artworks: mix.artwork)
                .padding(.bottom, 2)
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            StationArtwork(station: station)
                .padding(.bottom, 2)
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

    var body: some View {
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
/// next tile peeks in (tells.md, 8).
struct Shelf<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    var width: CGFloat = 160
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.Space.m) {
                ForEach(items) { item in
                    tile(item).frame(width: width)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }
}
