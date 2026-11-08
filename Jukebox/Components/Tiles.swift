// The tiles of a shelf or a grid: an album, a playlist, a mix, a station,
// an artist. A cover as wide as offered, one or two lines under it, as Music
// draws them; each a NavigationLink or a button where it is used.

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

/// A made-up playlist: its collage with the title set on it, Music's daily
/// mixes' way, and its subtitle under it. Square, and no light of the
/// arch's: a mix ends, and lit means endless (docs/BRAND.md).
struct MixCard: View {
    let mix: Mix

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            CollageArtwork(artworks: mix.artwork, cornerRadius: Theme.Radius.card)
                .overlay(alignment: .bottomLeading) {
                    ZStack(alignment: .bottomLeading) {
                        // A scrim from the bottom, black to clear, so white
                        // words read over a white cover too: over white, 3.7:1
                        // where a two-line title starts (large text asks
                        // 3:1), 5.9:1 behind a one-line title, more below.
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0), location: 0.3),
                            .init(color: .black.opacity(0.4), location: 0.55),
                            .init(color: .black.opacity(0.8), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        Text(mix.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                            .lineLimit(2)
                            .padding(Theme.Space.m)
                    }
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                }
            Text(mix.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A station: its arch, lit, over its seed's music; its name under it as
/// real text, which follows the reader's text size.
struct StationCard: View {
    let station: Station

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            StationArtwork(station: station, cornerRadius: Theme.Radius.card)
            Text(station.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let subtitle = station.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
/// starting at the page's margin.
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
