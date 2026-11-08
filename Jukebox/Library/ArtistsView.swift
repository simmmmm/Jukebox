// Artists: every album artist, alphabetical in letter sections ("The"
// ignored, as Music does), and an artist's page — Play and Shuffle, their
// station, their most played songs, their albums, the albums they are a
// guest on, who sounds like them, and what Jellyfin knows about them.
// Top Songs is called Songs until one of them has been played or is a
// favorite: before that the order is only the newest album's, and "Top"
// would claim a ranking there is not.

import JukeboxKit
import SwiftUI

struct ArtistsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let found = searching ? library.matchingArtists(query) : []
        let sections = searching ? [] : Self.makeSections(library.artistsByName)
        let showsEmptyState = searching ? found.isEmpty : sections.isEmpty
        List {
            if searching {
                ForEach(found) { artist in
                    link(artist)
                }
            } else {
                ForEach(sections) { section in
                    Section(section.letter) {
                        ForEach(section.artists) { artist in
                            link(artist)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Artists")
        .searchable(text: $query, prompt: "Find in Artists")
        .overlay {
            if showsEmptyState {
                LibraryEmptyState(query: query, emptyTitle: "No Artists", emptySymbol: "music.mic",
                                  emptyMessage: "Artists on your Jellyfin server appear here.")
            }
        }
        .refreshable { await library.refresh() }
    }

    private func link(_ artist: Artist) -> some View {
        NavigationLink(value: Route.artist(artist)) {
            LibraryArtistRow(artist: artist)
        }
    }

    /// A to Z, then "#" for names that start with a digit, a sign or
    /// another script, at the end as in Music.
    private static func makeSections(_ artists: [Artist]) -> [LibraryArtistSection] {
        var byLetter: [String: [Artist]] = [:]
        var letters: [String] = []
        for artist in artists {
            let letter = LibraryIndex.sectionLetter(artist.name)
            if byLetter[letter] == nil { letters.append(letter) }
            byLetter[letter, default: []].append(artist)
        }
        let ordered = letters.filter { $0 != "#" }.sorted() + (letters.contains("#") ? ["#"] : [])
        return ordered.map { LibraryArtistSection(letter: $0, artists: byLetter[$0] ?? []) }
    }
}

private struct LibraryArtistSection: Identifiable {
    let letter: String
    let artists: [Artist]
    var id: String { letter }
}

struct ArtistDetailView: View {
    let artist: Artist

    init(artist: Artist) {
        self.artist = artist
    }

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    /// Jellyfin's own idea of who is alike, for when the radio's graph
    /// knows nobody near this artist yet.
    @State private var jellyfinSimilar: [Artist] = []
    @State private var showsWholeOverview = false

    var body: some View {
        let shown = library.artist(id: artist.id) ?? artist
        let albums = library.albums(by: shown)
        let appearances = library.appearances(of: shown)
        let topQueue = library.topTracks(by: shown, limit: 25)
        let top = Array(topQueue.prefix(5))
        let similar = similarArtists(to: shown)
        let hasTracks = !topQueue.isEmpty
        let isRanked = library.hasPlaysOrFavorites(by: shown)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header(shown)

                VStack(spacing: Theme.Space.m) {
                    PlayShuffleButtons(play: { playAll(shown, shuffled: false) },
                                       shuffle: { playAll(shown, shuffled: true) })
                    LibraryRadioButton(seed: seed(for: shown))
                }
                .disabled(!hasTracks)
                .padding(.horizontal, Theme.margin)

                if !top.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        SectionHeader(isRanked ? String(localized: "Top songs") : String(localized: "Songs"))
                        VStack(spacing: 0) {
                            ForEach(top.indices, id: \.self) { i in
                                Button {
                                    guard !player.refusesOffline(top[i]) else { return }
                                    player.play(topQueue, startingAt: i,
                                                context: QueueContext(.artist(shown.id), title: shown.name))
                                } label: {
                                    TrackRow(top[i], subtitle: top[i].albumName)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, Theme.Space.xs)
                                if i < top.count - 1 {
                                    Divider().padding(.leading, 48 + Theme.Space.m)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.margin)
                    }
                }

                if !albums.isEmpty {
                    shelf("Albums", albums: albums, showsArtist: false)
                }
                if !appearances.isEmpty {
                    shelf("Appears on", albums: appearances, showsArtist: true)
                }

                if !similar.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader("Similar artists")
                        Shelf(items: similar, width: 120) { other in
                            NavigationLink(value: Route.artist(other)) {
                                ArtistTile(artist: other)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let overview = shown.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        ListHeading("About")
                        Text(overview)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(showsWholeOverview ? nil : 4)
                        Button(showsWholeOverview ? "Less" : "More") {
                            showsWholeOverview.toggle()
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.margin)
                }
            }
            .padding(.bottom, Theme.Space.xxl)
        }
        .libraryScrolledTitle(shown.name, after: 240)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    menu(shown)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .task(id: artist.id) { await loadJellyfinSimilar() }
    }

    private func header(_ shown: Artist) -> some View {
        // A joined tag split, as Genres lists it: "Rock · Shoegaze", not
        // "Rock; Shoegaze".
        let genres = LibraryIndex.genreNames(shown.genres)
        return VStack(spacing: Theme.Space.m) {
            ArtistAvatar(artist: shown, size: 180)
            Text(shown.name)
                .font(.serif(.largeTitle))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if !genres.isEmpty {
                Text(genres.prefix(3).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.l)
        .padding(.horizontal, Theme.margin)
    }

    private func shelf(_ title: String, albums: [Album], showsArtist: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title)
            Shelf(items: albums) { album in
                LibraryAlbumLink(album: album, showsArtist: showsArtist)
            }
        }
    }

    @ViewBuilder
    private func menu(_ shown: Artist) -> some View {
        let favorite = library.isFavorite(shown.id)
        let tracks = library.tracks(by: shown)
        Section {
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "artist", "from": "menu"])
                radio.start(seed(for: shown))
            }
        }
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(tracks)
            }
            .disabled(tracks.isEmpty)
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.addToQueue(tracks)
            }
            .disabled(tracks.isEmpty)
        }
        Section {
            Button(favorite ? "Undo Favorite" : "Favorite", systemImage: favorite ? "heart.slash" : "heart") {
                Task { await library.toggleFavorite(shown.id) }
            }
        }
    }

    private func seed(for shown: Artist) -> StationSeed {
        .artist(key: shown.key, name: shown.name, id: shown.id)
    }

    private func playAll(_ shown: Artist, shuffled: Bool) {
        let tracks = library.tracks(by: shown)
        guard !tracks.isEmpty else { return }
        player.play(tracks, context: QueueContext(.artist(shown.id), title: shown.name), shuffled: shuffled)
    }

    /// The radio's graph first (the library's own edges, and Last.fm's with
    /// a key); Jellyfin's similar artists when the graph knows nobody.
    /// Only artists in the library: a tile must open a page with music.
    private func similarArtists(to shown: Artist) -> [Artist] {
        var result: [Artist] = []
        var seen: Set<ItemID> = [shown.id]
        for neighbor in radio.graph.similarArtists(to: shown.key, limit: 40) {
            guard let ref = library.snapshot.artist(key: neighbor.key),
                  let found = library.artist(ref),
                  seen.insert(found.id).inserted else { continue }
            result.append(found)
            if result.count == 12 { break }
        }
        if result.isEmpty {
            return jellyfinSimilar.filter { $0.id != shown.id }
        }
        return result
    }

    private func loadJellyfinSimilar() async {
        guard let client = library.client else { return }
        let found = (try? await client.similarArtists(artistID: artist.id, limit: 20)) ?? []
        var seen = Set<ItemID>()
        jellyfinSimilar = found.compactMap { candidate in
            guard let own = library.artist(id: candidate.id) ?? library.artist(candidate.ref),
                  seen.insert(own.id).inserted else { return nil }
            return own
        }
    }
}
