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
    /// The wide page's own width, for its measures.
    @State private var width: CGFloat = 0

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
            }
        }
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

    /// The albums, playlists and mixes as covers, each with its one fact
    /// under its name; then the kept songs on hairlines. Shuffle All is the
    /// page's one filled button.
    private func page(albums: [OfflineCollection], playlists: [OfflineCollection], mixes: [OfflineCollection],
                      kept: [Track]) -> some View {
        let measures = DesktopMeasures.page(width: Int(width))
        return ScrollView {
            // The spec's 40 between a page's sections.
            VStack(alignment: .leading, spacing: 40) {
                if offline.songCount > 0 {
                    Button("Shuffle All") {
                        shuffleAll(kept: kept)
                    }
                    .buttonStyle(.prominent)
                    .fixedSize()
                }
                grid("Albums", albums, tile: CGFloat(measures.tile))
                grid("Playlists", playlists, tile: CGFloat(measures.tile))
                grid("Mixes", mixes, tile: CGFloat(measures.tile))
                if !kept.isEmpty {
                    pageSection("Songs you play") {
                        LazyVStack(spacing: 0) {
                            ForEach(kept) { track in
                                Button {
                                    play(track, in: kept)
                                } label: {
                                    // Rows of 64: the cover 48 and 8 above and below.
                                    TrackRow.standard(track)
                                        .padding(.vertical, Theme.Space.s)
                                }
                                .buttonStyle(.plain)
                                Hairline(inset: 48 + Theme.Space.m)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, CGFloat(measures.margin))
            .padding(.vertical, Theme.Space.xl)
        }
        .background(Theme.ground)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { measured in
            width = measured
        }
    }

    /// One kind of download as a grid of covers, at least a tile wide.
    @ViewBuilder
    private func grid(_ title: LocalizedStringKey, _ collections: [OfflineCollection], tile: CGFloat) -> some View {
        if !collections.isEmpty {
            pageSection(title) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tile), spacing: Theme.Space.xl, alignment: .top)],
                          alignment: .leading, spacing: Theme.Space.xl) {
                    ForEach(collections) { collection in
                        NavigationLink(value: Self.route(for: collection)) {
                            DownloadedTile(collection: collection)
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
        }
    }

    /// A heading in the serif 16 above what it holds, as Linux's section
    /// titles.
    private func pageSection<Content: View>(_ title: LocalizedStringKey,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(title)
                .font(.serif(.title2))
                .accessibilityAddTraits(.isHeader)
            content()
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

/// A download on the wide page: its cover as wide as the tile, its name,
/// and the row's one fact under it, as Library's tiles have the artist.
private struct DownloadedTile: View {
    let collection: OfflineCollection

    @Environment(OfflineStore.self) private var offline

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            DownloadedCover(collection: collection, size: nil)
                .padding(.bottom, Theme.Space.xs)
            Text(collection.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(offline.fact(of: collection))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(.rect)
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

extension OfflineStore {
    /// A download's one fact: how far it is, what it waits for, or how
    /// many songs and how large.
    fileprivate func fact(of collection: OfflineCollection) -> String {
        switch state(of: collection.reason) {
        case let .downloading(fraction: fraction, waiting: waiting):
            if let waiting { return OfflineText.waiting(waiting) }
            return String(localized: "Downloading, \(OfflineText.percent(fraction))")
        case .downloaded, .notDownloaded:
            let total = Set(collection.trackIDs).count
            let here = songsOnPhone(of: collection)
            let size = bytes(of: collection).formatted(.byteCount(style: .file))
            // Some songs the server would not give: how many came.
            if here < total { return String(localized: "\(here) of \(total) songs, \(size)") }
            return "\(LibraryText.songs(total)), \(size)"
        }
    }
}
