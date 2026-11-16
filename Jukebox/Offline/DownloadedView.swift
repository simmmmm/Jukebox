// Library › Downloaded: what is on the phone, so what plays without a
// connection — the albums, playlists and mixes chosen, newest first, each
// with how far it is or what it takes; then the songs Keep Songs I Play holds.
// Shuffle All plays everything here. A swipe removes a download, asked first.
// In a wide window (the iPad, the Mac) a page of covers instead, at the
// page's margin and tile (DesktopMeasures), as Library's albums are; a
// download's menu removes it there, as a swipe does in the list.

import JukeboxKit
import SwiftUI

struct DownloadedView: View {
    @Environment(OfflineStore.self) private var offline
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(\.isWide) private var isWide
    @State private var pendingRemoval: OfflineCollection?

    var body: some View {
        let collections = offline.collections
        let albums = collections.filter { if case .album = $0.item { return true } else { return false } }
        let playlists = collections.filter { if case .playlist = $0.item { return true } else { return false } }
        let mixes = collections.filter { if case .mix = $0.item { return true } else { return false } }
        let kept = keptTracks
        Group {
            if isWide {
                page(albums: albums, playlists: playlists, mixes: mixes, kept: kept)
            } else {
                list(albums: albums, playlists: playlists, mixes: mixes, kept: kept)
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
            }
        }
        .confirmationDialog(Text("Remove from this \(Device.model)?"), isPresented: isConfirmingRemoval,
                            titleVisibility: .visible, presenting: pendingRemoval) { collection in
            Button("Remove “\(collection.title)”", role: .destructive) {
                offline.remove(collection.reason)
            }
        } message: { _ in
            Text("It still plays from your server. Songs another download holds stay.")
        }
    }

    // MARK: Wide

    /// A wide page as every other (WidePage): the title; Shuffle All, the
    /// page's one filled button; the albums, playlists and mixes as grids
    /// of covers, each with its one fact under its name; then the kept
    /// songs as rows. Nothing here: one plain line of what to do.
    private func page(albums: [OfflineCollection], playlists: [OfflineCollection], mixes: [OfflineCollection],
                      kept: [Track]) -> some View {
        WidePage(title: String(localized: "Downloaded")) { page, width in
            PageTitle(String(localized: "Downloaded"))
                .padding(.horizontal, page.side)
            if offline.collections.isEmpty && kept.isEmpty {
                PagePlainLine("Download an album, a playlist or a mix with \(Image(systemName: "arrow.down.circle")) on its page. Keep Songs I Play, in Settings, keeps what you play often.")
                    .padding(.horizontal, page.side)
            }
            if offline.songCount > 0 {
                Button("Shuffle All") {
                    shuffleAll(kept: kept)
                }
                .buttonStyle(.prominent)
                .fixedSize()
                .padding(.top, Theme.Space.xl)
                .padding(.horizontal, page.side)
            }
            grid("Albums", albums, page: page, width: width)
            grid("Playlists", playlists, page: page, width: width)
            grid("Mixes", mixes, page: page, width: width)
            if !kept.isEmpty {
                PageSectionTitle(String(localized: "Songs you play"), below: Theme.Space.s)
                    .padding(.horizontal, page.side)
                PageTrackRows(tracks: kept, play: { track in
                    play(track, in: kept)
                })
                .padding(.horizontal, page.side)
            }
        }
    }

    /// One kind of download as a grid of covers at the page's tile.
    @ViewBuilder
    private func grid(_ title: String.LocalizationValue, _ collections: [OfflineCollection],
                      page: DesktopMeasures.Page, width: CGFloat) -> some View {
        if !collections.isEmpty {
            PageSectionTitle(String(localized: title))
                .padding(.horizontal, page.side)
            TileGrid(items: collections, page: page, width: width) { collection in
                NavigationLink(value: Self.route(for: collection)) {
                    WideTile(name: collection.title, line: offline.fact(of: collection)) {
                        DownloadedCover(collection: collection, size: nil)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                        pendingRemoval = collection
                    }
                }
            }
        }
    }

    // MARK: Compact

    private func list(albums: [OfflineCollection], playlists: [OfflineCollection], mixes: [OfflineCollection],
                      kept: [Track]) -> some View {
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
                            play(track, in: kept)
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

    private func play(_ track: Track, in kept: [Track]) {
        guard !player.refusesOffline(track) else { return }
        let at = kept.firstIndex(where: { $0.id == track.id }) ?? 0
        player.play(kept, startingAt: at, context: QueueContext(.other, title: "Downloaded"))
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
            DownloadedCover(collection: collection, size: 56)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(collection.title)
                    .lineLimit(1)
                Text(offline.fact(of: collection))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An album's cover, a playlist's (or its first song's), a mix's collage:
/// `size` square, or as wide as offered.
private struct DownloadedCover: View {
    let collection: OfflineCollection
    let size: CGFloat?

    var body: some View {
        switch collection.item {
        case let .album(album):
            ArtworkView(album.artwork, size: size, cornerRadius: Theme.Radius.artwork)
        case let .playlist(playlist):
            ArtworkView(playlist.artwork ?? collection.tracks.first?.artwork, size: size,
                        cornerRadius: Theme.Radius.artwork, placeholder: "music.note.list")
        case let .mix(mix):
            CollageArtwork(artworks: mix.artwork, size: size)
        }
    }
}
