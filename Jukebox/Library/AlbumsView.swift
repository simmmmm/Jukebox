// Albums: the grid of covers, sorted as the listener chose (kept between
// launches), and an album's page as Music draws it — the cover large, the
// artist in the accent to go to them, Play and Shuffle, the album's station
// under them (as an artist's page has it: "ik vind vooral de radiofunctie
// echt belangrijk"), the songs by disc, how long it all is, and More by the
// artist at the end. Download in the bar puts it on the phone
// (OfflineDownloadButton); offline, a downloaded album the library has not
// indexed shows the songs it was downloaded with.

import JukeboxKit
import SwiftUI

struct AlbumsView: View {
    @Environment(LibraryStore.self) private var library
    @AppStorage("library.albumSort") private var sort: LibraryAlbumSort = .title
    @State private var query = ""

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let albums = searching ? library.matchingAlbums(query) : library.albums(sortedBy: sort)
        ScrollView {
            LibraryAlbumGrid(albums: albums)
                .padding(.vertical, Theme.Space.l)
        }
        .navigationTitle("Albums")
        .searchable(text: $query, prompt: "Find in Albums")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Text("Title").tag(LibraryAlbumSort.title)
                        Text("Artist").tag(LibraryAlbumSort.artist)
                        Text("Year").tag(LibraryAlbumSort.year)
                        Text("Recently Added").tag(LibraryAlbumSort.recentlyAdded)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .overlay {
            if albums.isEmpty {
                LibraryEmptyState(query: query, emptyTitle: "No Albums", emptySymbol: "square.stack",
                                  emptyMessage: "Albums on your \(library.serverKind) server appear here.")
            }
        }
        .refreshable { await library.refresh() }
    }
}

struct AlbumDetailView: View {
    let album: Album

    init(album: Album) {
        self.album = album
    }

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator
    @Environment(OfflineStore.self) private var offline
    /// The album's songs from the server, for an album the library has not
    /// indexed (found by search before the library has loaded).
    @State private var fetched: [Track]?
    @State private var isConfirmingRemoval = false

    var body: some View {
        let shown = library.album(id: album.id) ?? album
        let found = shownSongs()
        let tracks = found.tracks
        let isLoading = found.isLoading
        let discs = Self.splitIntoDiscs(tracks)
        let moreBy = isLoading ? nil : moreByArtist(shown)

        List {
            header(shown, tracks: tracks)
                .listRowInsets(EdgeInsets(top: Theme.Space.l, leading: Theme.margin,
                                          bottom: Theme.Space.l, trailing: Theme.margin))
                .listRowSeparator(.hidden)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if discs.count > 1 {
                ForEach(discs) { disc in
                    Section {
                        ForEach(disc.tracks) { track in
                            row(track, in: tracks, album: shown)
                        }
                    } header: {
                        ListHeading("Disc \(disc.number)")
                    }
                }
            } else {
                ForEach(tracks) { track in
                    row(track, in: tracks, album: shown)
                }
            }

            if !tracks.isEmpty {
                footer(shown, tracks: tracks)
                    .listRowSeparator(.hidden)
            }

            if let artist = moreBy {
                NavigationLink(value: Route.artist(artist)) {
                    HStack(spacing: Theme.Space.m) {
                        ArtistAvatar(artist: artist, size: 44)
                        Text("More by \(artist.name)")
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
                .listRowSeparator(.hidden, edges: .top)
            }
        }
        .listStyle(.plain)
        .libraryScrolledTitle(shown.name)
        .toolbar {
            // Not when the server does not let this account download,
            // unless the album is on the phone already, to remove it.
            if offline.offersDownload(for: .album(album.id)) {
                ToolbarItem(placement: .topBarTrailing) {
                    OfflineDownloadButton(collection: OfflineCollection(album: shown, tracks: tracks),
                                          isConfirmingRemoval: $isConfirmingRemoval)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    LibraryAlbumMenu(album: shown, tracks: tracks)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .offlineRemovalDialog($isConfirmingRemoval, for: .album(album.id), name: shown.name)
        .task(id: album.id) { await fetchIfNeeded() }
    }

    private func header(_ shown: Album, tracks: [Track]) -> some View {
        VStack(spacing: Theme.Space.s) {
            ArtworkView(shown.artwork, size: 260)
                .padding(.bottom, Theme.Space.m)
            Text(shown.name)
                .font(.serif(.title))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if !shown.artistLine.isEmpty {
                Button {
                    goToArtist(shown)
                } label: {
                    Text(shown.artistLine)
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the artist")
            }
            if let detail = Self.detailLine(shown) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Theme.Space.m) {
                PlayShuffleButtons(play: { play(tracks, from: 0, album: shown, shuffled: false) },
                                   shuffle: { play(tracks, from: 0, album: shown, shuffled: true) })
                LibraryRadioButton(seed: .album(shown.id))
            }
            .padding(.top, Theme.Space.m)
            .disabled(tracks.isEmpty)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ track: Track, in tracks: [Track], album shown: Album) -> some View {
        Button {
            guard !player.refusesOffline(track) else { return }
            let i = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
            play(tracks, from: i, album: shown, shuffled: false)
        } label: {
            TrackRow(track, leading: .number(track.trackNumber), subtitle: Self.subtitle(of: track, on: shown))
        }
        .buttonStyle(.plain)
    }

    private func footer(_ shown: Album, tracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let year = shown.year {
                Text(String(year))
            }
            Text(LibraryText.summary(count: tracks.count, duration: LibraryText.totalDuration(tracks)))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.s)
    }

    private func play(_ tracks: [Track], from index: Int, album shown: Album, shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        player.play(tracks, startingAt: index, context: QueueContext(.album(shown.id), title: shown.name),
                    shuffled: shuffled)
    }

    private func goToArtist(_ shown: Album) {
        guard let ref = shown.primaryArtist, let artist = library.artist(ref) else { return }
        navigator.open(.artist(artist))
    }

    /// The album artist, for More by at the end, when the library has them;
    /// not Various Artists, whose page is every compilation at once.
    private func moreByArtist(_ shown: Album) -> Artist? {
        guard let ref = shown.primaryArtist, let artist = library.artist(ref),
              artist.key != NameKey.artist("Various Artists") else { return nil }
        return artist
    }

    /// The album's songs: the library's; else those the server gave this
    /// page; else, offline, those it was downloaded with. Loading while none
    /// of them is there yet.
    private func shownSongs() -> (tracks: [Track], isLoading: Bool) {
        let own = library.tracks(inAlbum: album.id)
        if !own.isEmpty { return (own, false) }
        if let fetched, !fetched.isEmpty { return (fetched, false) }
        let saved = offline.collection(for: .album(album.id))?.tracks ?? []
        if !saved.isEmpty { return (saved, false) }
        return (fetched ?? [], fetched == nil)
    }

    private func fetchIfNeeded() async {
        guard library.tracks(inAlbum: album.id).isEmpty, fetched == nil else { return }
        guard let server = library.server else {
            fetched = []
            return
        }
        do {
            let tracks = try await server.albumTracks(albumID: album.id)
            fetched = tracks.sorted(by: LibraryIndex.inDiscOrder)
        } catch {
            fetched = []
        }
    }

    /// "Rock, Shoegaze · 1997": the album's genres, a joined tag split as
    /// Genres lists them (two at most), and its year, when known.
    private static func detailLine(_ album: Album) -> String? {
        var parts: [String] = []
        let genres = LibraryIndex.genreNames(album.genres).prefix(2)
        if !genres.isEmpty { parts.append(genres.joined(separator: ", ")) }
        if let year = album.year { parts.append(String(year)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A song's artists only when they are not the album's (a guest, a
    /// compilation), as Music shows them.
    private static func subtitle(of track: Track, on album: Album) -> String? {
        let trackKeys = Set(track.artists.map(\.key))
        guard !trackKeys.isEmpty, trackKeys != Set(album.artists.map(\.key)) else { return nil }
        return track.artistLine
    }

    private static func splitIntoDiscs(_ tracks: [Track]) -> [Disc] {
        var result: [Disc] = []
        for track in tracks {
            let number = track.discNumber ?? 1
            if let last = result.indices.last, result[last].number == number {
                result[last].tracks.append(track)
            } else {
                result.append(Disc(number: number, tracks: [track]))
            }
        }
        return result
    }

    private struct Disc: Identifiable {
        let number: Int
        var tracks: [Track]
        var id: Int { number }
    }
}
