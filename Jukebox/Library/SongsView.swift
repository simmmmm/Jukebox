// Songs: every track by title, Shuffle All at the top, and a filter that
// ranks what it finds as search does. A tap plays the list as it is shown,
// from that song on.

import JukeboxKit
import SwiftUI

struct SongsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var query = ""

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shown = searching ? library.matchingTracks(query) : library.songsByTitle
        List {
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
            }
        }
        .listStyle(.plain)
        .navigationTitle("Songs")
        .searchable(text: $query, prompt: "Find in Songs")
        .overlay {
            if shown.isEmpty {
                LibraryEmptyState(query: query, emptyTitle: "No Songs", emptySymbol: "music.note",
                                  emptyMessage: "Songs on your \(library.serverKind) server appear here.")
            }
        }
        .refreshable { await library.refresh() }
    }

    private func context(searching: Bool) -> QueueContext {
        searching ? QueueContext(.search, title: query) : QueueContext(.songs, title: "Songs")
    }
}
