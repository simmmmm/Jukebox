// A track in any list — an album's (its number), a playlist's or Songs'
// (its cover), Up Next (with why the radio chose it) — and the menu every
// track has, in a long press and behind its "…".

import JukeboxKit
import SwiftUI

struct TrackRow: View {
    enum Leading {
        case artwork
        case number(Int?)
        case none
    }

    let track: Track
    var leading: Leading = .artwork
    /// The second line; nil leaves it out (an album's own rows).
    var subtitle: String?
    var reason: PickReason?
    var showsMenu = true

    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var app

    init(_ track: Track, leading: Leading = .artwork, subtitle: String? = nil, reason: PickReason? = nil,
         showsMenu: Bool = true) {
        self.track = track
        self.leading = leading
        self.subtitle = subtitle
        self.reason = reason
        self.showsMenu = showsMenu
    }

    /// Artwork, title, artist: the usual row.
    static func standard(_ track: Track) -> TrackRow {
        TrackRow(track, subtitle: track.artistLine)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            switch leading {
            case .artwork:
                ArtworkView(track.artwork, size: 48, cornerRadius: Theme.Radius.thumbnail)
            case let .number(number):
                Group {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text(number.map(String.init) ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 24, alignment: .center)
            case .none:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(track.name)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if library.isFavorite(track.id) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Favourite")
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let reason {
                    Text(reason.text)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if isCurrent && showsArtwork {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Playing")
            }
            if showsMenu {
                Menu {
                    TrackMenu(track: track)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("More")
            }
        }
        .contentShape(.rect)
        .contextMenu {
            TrackMenu(track: track)
        } preview: {
            // Passed in explicitly: the preview is drawn in a hosting
            // controller of its own, and its cover (ArtworkView) needs the
            // AppModel's client. Were the environment not carried into it,
            // every long press on a song would crash.
            TrackPreview(track: track)
                .environment(app)
        }
    }

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    private var showsArtwork: Bool {
        if case .artwork = leading { return true }
        return false
    }
}

/// The long press's preview: the cover, the title, the artist.
private struct TrackPreview: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ArtworkView(track.artwork, size: 240)
            Text(track.name).font(.headline).lineLimit(2)
            Text(track.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(Theme.Space.l)
        .frame(width: 272)
    }
}

/// What can be done with a track, as Music orders it.
struct TrackMenu: View {
    let track: Track

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext([track])
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.addToQueue([track])
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                radio.start(.track(track.id))
            }
        }
        Section {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: [track])
            }
            let favorite = library.isFavorite(track.id)
            Button(favorite ? "Undo Favourite" : "Favourite", systemImage: favorite ? "heart.slash" : "heart") {
                Task { await library.toggleFavorite(track.id) }
            }
        }
        Section {
            if let albumID = track.albumID, let album = library.album(id: albumID) {
                Button("Go to Album", systemImage: "square.stack") {
                    navigator.open(.album(album))
                }
            }
            if let ref = track.primaryArtist, let artist = library.artist(ref) {
                Button("Go to Artist", systemImage: "music.mic") {
                    navigator.open(.artist(artist))
                }
            }
        }
    }
}
