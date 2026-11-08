// Library › Downloaded: what is on the phone, so what plays without a
// connection — the albums, playlists and mixes chosen, newest first, each
// with how far it is or what it takes; then the songs Keep Songs I Play holds.
// Shuffle All plays everything here. A swipe removes a download, asked first.

import JukeboxKit
import SwiftUI
import UIKit

struct DownloadedView: View {
    @Environment(OfflineStore.self) private var offline
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var pendingRemoval: OfflineCollection?

    var body: some View {
        let collections = offline.collections
        let albums = collections.filter { if case .album = $0.item { return true } else { return false } }
        let playlists = collections.filter { if case .playlist = $0.item { return true } else { return false } }
        let mixes = collections.filter { if case .mix = $0.item { return true } else { return false } }
        let kept = keptTracks
        List {
            if offline.songCount > 0 {
                Button {
                    shuffleAll(kept: kept)
                } label: {
                    Label("Shuffle All", systemImage: "shuffle")
                        .font(.body.weight(.semibold))
                }
            }
            section("Albums", albums)
            section("Playlists", playlists)
            section("Mixes", mixes)
            if !kept.isEmpty {
                Section {
                    ForEach(kept) { track in
                        Button {
                            guard !player.refusesOffline(track) else { return }
                            let at = kept.firstIndex(where: { $0.id == track.id }) ?? 0
                            player.play(kept, startingAt: at, context: QueueContext(.other, title: "Downloaded"))
                        } label: {
                            TrackRow.standard(track)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    ListHeading("Songs you play")
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Downloaded")
        .overlay {
            if collections.isEmpty && kept.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download an album, a playlist or a mix with \(Image(systemName: "arrow.down.circle")) on its page. Keep Songs I Play, in Settings, keeps what you play often.")
                }
            }
        }
        .confirmationDialog(Text("Remove from this \(UIDevice.current.model)?"), isPresented: isConfirmingRemoval,
                            titleVisibility: .visible, presenting: pendingRemoval) { collection in
            Button("Remove “\(collection.title)”", role: .destructive) {
                offline.remove(collection.reason)
            }
        } message: { _ in
            Text("It still plays from your server. Songs another download holds stay.")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ collections: [OfflineCollection]) -> some View {
        if !collections.isEmpty {
            Section {
                ForEach(collections) { collection in
                    NavigationLink(value: Self.route(for: collection)) {
                        DownloadedRow(collection: collection)
                    }
                    .swipeActions {
                        // Red by tint, not by the destructive role: with the
                        // role, List slides the row away before the dialog
                        // has asked (as Playlists has it).
                        Button("Remove", systemImage: "trash") {
                            pendingRemoval = collection
                        }
                        .tint(.red)
                    }
                }
            } header: {
                ListHeading(title)
            }
        }
    }

    /// The songs the keep holds, by title; those the library no longer has
    /// are left out.
    private var keptTracks: [Track] {
        offline.keptTrackIDs.compactMap { library.track(id: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    /// Everything on the phone, once each, shuffled.
    private func shuffleAll(kept: [Track]) {
        var seen = Set<ItemID>()
        var tracks: [Track] = []
        for track in offline.collections.flatMap(\.tracks) + kept where offline.has(track.id) {
            if seen.insert(track.id).inserted { tracks.append(track) }
        }
        player.play(tracks, context: QueueContext(.other, title: "Downloaded"), shuffled: true)
    }

    private static func route(for collection: OfflineCollection) -> Route {
        switch collection.item {
        case let .album(album): return .album(album)
        case let .playlist(playlist): return .playlist(playlist)
        case let .mix(mix): return .mix(mix.mix(tracks: collection.tracks))
        }
    }
}

/// A download in the list: its cover, its name, and one fact — how far it
/// is, what it waits for, or how many songs and how large.
private struct DownloadedRow: View {
    let collection: OfflineCollection

    @Environment(OfflineStore.self) private var offline

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .lineLimit(1)
                Text(fact)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var cover: some View {
        switch collection.item {
        case let .album(album):
            ArtworkView(album.artwork, size: 56, cornerRadius: Theme.Radius.artwork)
        case let .playlist(playlist):
            ArtworkView(playlist.artwork ?? collection.tracks.first?.artwork, size: 56,
                        cornerRadius: Theme.Radius.artwork, placeholder: "music.note.list")
        case let .mix(mix):
            CollageArtwork(artworks: mix.artwork, size: 56)
        }
    }

    private var fact: String {
        switch offline.state(of: collection.reason) {
        case let .downloading(fraction: fraction, waiting: waiting):
            if let waiting { return OfflineText.waiting(waiting) }
            return String(localized: "Downloading, \(OfflineText.percent(fraction))")
        case .downloaded, .notDownloaded:
            let total = Set(collection.trackIDs).count
            let here = offline.songsOnPhone(of: collection)
            let size = offline.bytes(of: collection).formatted(.byteCount(style: .file))
            // Some songs the server would not give: how many came.
            if here < total { return String(localized: "\(here) of \(total) songs, \(size)") }
            return "\(LibraryText.songs(total)), \(size)"
        }
    }
}
