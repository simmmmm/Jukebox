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
/// mixes' way, and its subtitle under it.
struct MixCard: View {
    let mix: Mix

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            CollageArtwork(artworks: mix.artwork, cornerRadius: Theme.Radius.card)
                .overlay(alignment: .bottomLeading) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        Text(mix.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
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

/// A station: the eclipse over its seed, its name under it.
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
