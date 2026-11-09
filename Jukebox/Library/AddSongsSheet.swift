// Add Songs, from a playlist's page: a playlist was a dead end without it —
// made with New Playlist…, it could only be filled from other screens'
// menus, one album or song at a time. The library's songs by title, or what
// the search finds (ranked as Songs' filter ranks it); a tap on a row (its +)
// adds the song at the end of the playlist and turns the + into a
// checkmark; Done closes. The songs the playlist already has are checked
// from the start: Jellyfin 12.4 keeps a song added twice, so a second +
// by mistake would put it in twice.

import JukeboxKit
import SwiftUI

struct LibraryAddSongsSheet: View {
    let playlist: Playlist
    /// The songs in the playlist when the sheet opened.
    let songsInPlaylist: Set<ItemID>

    init(playlist: Playlist, songsInPlaylist: Set<ItemID>) {
        self.playlist = playlist
        self.songsInPlaylist = songsInPlaylist
    }

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Added while the sheet is open.
    @State private var added: Set<ItemID> = []
    /// On their way to the server.
    @State private var adding: Set<ItemID> = []
    @State private var errorMessage: String?

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = searching ? library.matchingTracks(query) : library.songsByTitle
        NavigationStack {
            List {
                ForEach(shown) { track in
                    LibraryAddSongRow(track: track, state: state(of: track)) {
                        add(track)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            // Always showing: finding the song is what the sheet is for.
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Find in Songs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if shown.isEmpty {
                    LibraryEmptyState(query: query, emptyTitle: "No Songs", emptySymbol: "music.note",
                                      emptyMessage: "Songs on your \(library.serverKind) server appear here.")
                }
            }
            .sensoryFeedback(.success, trigger: added)
            .libraryErrorAlert("Could Not Add to the Playlist", message: $errorMessage)
        }
    }

    private func state(of track: Track) -> LibraryAddSongState {
        if added.contains(track.id) || songsInPlaylist.contains(track.id) { return .added }
        if adding.contains(track.id) { return .adding }
        return .add
    }

    private func add(_ track: Track) {
        guard case .add = state(of: track) else { return }
        adding.insert(track.id)
        Task {
            do {
                try await library.add([track], to: playlist)
                added.insert(track.id)
                Stats.track(.playlistSongsAdded, ["from": "add_songs"])
            } catch {
                errorMessage = error.localizedDescription
            }
            adding.remove(track.id)
        }
    }
}

private enum LibraryAddSongState {
    case add
    case adding
    case added
}

/// A song in Add Songs: cover, title, artist, and at the end the + that
/// becomes a spinner while the server adds it, then a checkmark. The whole
/// row is the button, so the target is the row rather than the small glyph;
/// not a TrackRow, whose menu (Go to Album…) would open pages behind the
/// sheet.
private struct LibraryAddSongRow: View {
    let track: Track
    let state: LibraryAddSongState
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.Space.m) {
                ArtworkView(track.artwork, size: 48, cornerRadius: Theme.Radius.artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !track.artistLine.isEmpty {
                        Text(track.artistLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                mark
                    .frame(width: 32, height: 32)
            }
            .contentShape(.rect)
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch state {
        case .add:
            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Add")
        case .adding:
            ProgressView()
        case .added:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Added")
        }
    }
}
