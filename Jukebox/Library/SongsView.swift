// Songs: every track by title, Shuffle All at the top, and a filter that
// ranks what it finds as search does. A tap plays the list as it is shown,
// from that song on.
//
// In a wide window, as Linux's (07-songs): the title, how many, Shuffle as a
// word, then the rows with their covers and lengths.

import JukeboxKit
import SwiftUI

struct SongsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(\.isWide) private var isWide
    @State private var query = ""

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    private var wide: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = searching ? library.matchingTracks(query) : library.songsByTitle
        return WidePage(title: "Songs") { page, _ in
            Group {
                PageTitle("Songs", fact: shown.isEmpty ? nil : LibraryText.songs(shown.count))
                if shown.isEmpty {
                    if searching {
                        PagePlainLine("Nothing in Songs matches “\(query)”.")
                    } else {
                        PageEmptyLine("Songs on your \(library.serverKind) server appear here.")
                    }
                } else {
                    // On the fact's left edge, as Linux's word under it: 8 in,
                    // it read as a stray button ("hier zit nog een rare knop
                    // op mac", the photographer, 24 November 2026).
                    WordButton(searching ? "Shuffle These" : "Shuffle", inline: true) {
                        player.play(shown, context: context(searching: searching), shuffled: true)
                    }
                    PageTrackRows(tracks: shown, play: { track in
                        let i = shown.firstIndex(where: { $0.id == track.id }) ?? 0
                        player.play(shown, startingAt: i, context: context(searching: searching))
                    })
                    .padding(.top, Theme.Space.xl)
                }
            }
            .padding(.horizontal, page.side)
        }
        // No find field when wide: Linux's pages have none, Search is a place.
        .refreshable { await library.refresh() }
    }

    private var compact: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = searching ? library.matchingTracks(query) : library.songsByTitle
        return List {
            // None: Linux's line where the rows would start, as the wide
            // page's; the library loading, or not loaded, keeps its status.
            if shown.isEmpty && !searching && settled {
                EmptyLine("Songs on your \(library.serverKind) server appear here.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if !shown.isEmpty {
                Button {
                    player.play(shown, context: context(searching: searching), shuffled: true)
                } label: {
                    Label(searching ? "Shuffle These" : "Shuffle All", systemImage: "shuffle")
                        .font(.body.weight(.semibold))
                }
            }
            ForEach(shown) { track in
                Button {
                    // Offline, a song not on the phone says why rather than play.
                    guard !player.refusesOffline(track) else { return }
                    let i = shown.firstIndex(where: { $0.id == track.id }) ?? 0
                    player.play(shown, startingAt: i, context: context(searching: searching))
                } label: {
                    TrackRow.standard(track)
                }
                .buttonStyle(.plain)
                .trackListRow()
            }
        }
        .listStyle(.plain)
        .navigationTitle("Songs")
        .searchable(text: $query, prompt: "Find in Songs")
        .overlay {
            if shown.isEmpty && (searching || !settled) {
                LibraryEmptyState(query: query)
            }
        }
        .refreshable { await library.refresh() }
    }

    /// Loaded, or loaded with nothing: not loading and not failed.
    private var settled: Bool {
        library.state == .loaded || library.state == .empty
    }

    private func context(searching: Bool) -> QueueContext {
        searching ? QueueContext(.search, title: query) : QueueContext(.songs, title: "Songs")
    }
}
