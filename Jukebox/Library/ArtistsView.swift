// Artists: every album artist, alphabetical in letter sections ("The"
// ignored, as Music does), and an artist's page — Play and Shuffle, their
// station, their most played songs, their albums, the albums they are a
// guest on, who sounds like them, and what Jellyfin knows about them.
// Top Songs is called Songs until one of them has been played or is a
// favorite: before that the order is only the newest album's, and "Top"
// would claim a ranking there is not.
//
// In a wide window, as Linux's: the artists as a grid of the page's tiles;
// an artist's page as an album's (06-artist), the photo 224 at the left
// with the name at its foot, then the songs in rows and the albums in tiles.

import JukeboxKit
import SwiftUI

struct ArtistsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RadioController.self) private var radio
    @Environment(\.isWide) private var isWide
    @State private var query = ""

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    /// Linux's Artists: a grid of tiles by name, no letters.
    private var wide: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let artists = searching ? library.matchingArtists(query) : library.artistsByName
        return WidePage(title: "Artists") { page, width in
            PageTitle("Artists")
                .padding(.horizontal, page.side)
            if artists.isEmpty {
                Group {
                    if searching {
                        PagePlainLine("Nothing in Artists matches “\(query)”.")
                    } else {
                        PageEmptyLine("Artists on your \(library.serverKind) server appear here.")
                    }
                }
                .padding(.horizontal, page.side)
            } else {
                TileGrid(items: artists, page: page, width: width) { artist in
                    NavigationLink(value: Route.artist(artist)) {
                        ArtistTile(artist: artist)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        menu(artist).menuIcons()
                    }
                }
                .padding(.top, Theme.Space.xl)
            }
        }
        // No find field when wide: Linux's pages have none, Search is a place.
        .refreshable { await library.refresh() }
    }

    private var compact: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let found = searching ? library.matchingArtists(query) : []
        let sections = searching ? [] : Self.makeSections(library.artistsByName)
        let showsEmptyState = searching ? found.isEmpty : sections.isEmpty
        return List {
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
                                  emptyMessage: "Artists on your \(library.serverKind) server appear here.")
            }
        }
        .refreshable { await library.refresh() }
    }

    private func link(_ artist: Artist) -> some View {
        NavigationLink(value: Route.artist(artist)) {
            LibraryArtistRow(artist: artist)
        }
        .contextMenu {
            menu(artist).menuIcons()
        }
    }

    /// An artist's tile or row: their station, then their link, in a
    /// song's sections (SYSTEM.md, Menus), as Linux's.
    @ViewBuilder
    private func menu(_ artist: Artist) -> some View {
        Section {
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "artist", "from": "menu"])
                radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))
            }
        }
        Section {
            ShareMenuItem(item: .artist(artist))
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
    /// The server's own idea of who is alike (Jellyfin's /Similar, a
    /// Subsonic server's getArtistInfo2, from Last.fm there), for when the
    /// radio's graph knows nobody near this artist yet.
    @State private var serverSimilar: [Artist] = []
    @State private var showsWholeOverview = false
    @Environment(\.isWide) private var isWide

    var body: some View {
        let shown = library.artist(id: artist.id) ?? artist
        Group {
            if isWide {
                wide(shown)
            } else {
                compact(shown)
            }
        }
        .toolbar {
            // Wide, the head has its own "…".
            if !isWide {
                ToolbarItem(placement: .barTrailing) {
                    Menu {
                        menu(shown).menuIcons()
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
        .task(id: artist.id) { await loadServerSimilar() }
    }

    /// Linux's artist page (06-artist): the head (the photo, the name, how
    /// many albums and songs, Play, the heart, "…"), the top songs in rows,
    /// then the albums, the ones they are a guest on and who sounds like
    /// them in tiles, and what the server knows of them.
    private func wide(_ shown: Artist) -> some View {
        let albums = library.albums(by: shown)
        let appearances = library.appearances(of: shown)
        let topQueue = library.topTracks(by: shown, limit: 25)
        let top = Array(topQueue.prefix(5))
        let similar = similarArtists(to: shown)
        let isRanked = library.hasPlaysOrFavorites(by: shown)
        let songs = library.tracks(by: shown).count
        // "3 albums · 22 songs".
        var counts: [String] = []
        if albums.count == 1 { counts.append(String(localized: "1 album")) }
        if albums.count > 1 { counts.append(String(localized: "\(albums.count) albums")) }
        if songs > 0 { counts.append(LibraryText.songs(songs)) }
        let facts = counts.joined(separator: " · ")
        return WidePage(title: shown.name, hasHead: true) { page, _ in
            PageHead(page: page, title: shown.name, facts: facts) { size in
                ArtworkView(shown.artwork, size: size, placeholder: "music.mic")
            } actions: {
                // Play and Shuffle, as the iPhone's page and Linux's head.
                PagePlayButtons(play: { playAll(shown, shuffled: false) },
                                shuffle: { playAll(shown, shuffled: true) })
                    .disabled(songs == 0)
                HStack(spacing: Theme.Space.s) {
                    HeartButton(item: .artist(shown.id))
                    MoreMenu {
                        menu(shown).menuIcons()
                    }
                }
            }

            if !top.isEmpty {
                Group {
                    PageSectionTitle(isRanked ? String(localized: "Top songs") : String(localized: "Songs"),
                                     below: Theme.Space.s)
                    PageTrackRows(tracks: top, subtitle: { $0.albumName }, play: { track in
                        let i = topQueue.firstIndex(where: { $0.id == track.id }) ?? 0
                        player.play(topQueue, startingAt: i,
                                    context: QueueContext(.artist(shown.id), title: shown.name))
                    })
                }
                .padding(.horizontal, page.side)
            }

            if !albums.isEmpty {
                wideShelf(String(localized: "Albums"), albums: albums, showsArtist: false, page: page)
            }
            if !appearances.isEmpty {
                wideShelf(String(localized: "Appears on"), albums: appearances, showsArtist: true, page: page)
            }
            if !similar.isEmpty {
                PageSectionTitle(String(localized: "Similar artists"))
                    .padding(.horizontal, page.side)
                Shelf(items: similar, width: CGFloat(page.tile), margin: page.side) { other in
                    NavigationLink(value: Route.artist(other)) {
                        ArtistTile(artist: other)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let overview = shown.overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PageSectionTitle(String(localized: "About"), below: 0)
                    Text(overview)
                        .desktopFont(Tokens.Size.body15.size)
                        .foregroundStyle(.secondary)
                        .lineLimit(showsWholeOverview ? nil : 4)
                        .frame(maxWidth: 640, alignment: .leading)
                    WordButton(showsWholeOverview ? "Less" : "More", inline: true) {
                        showsWholeOverview.toggle()
                    }
                }
                .padding(.horizontal, page.side)
            }
        }
    }

    private func wideShelf(_ title: String, albums: [Album], showsArtist: Bool,
                           page: DesktopMeasures.Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PageSectionTitle(title)
                .padding(.horizontal, page.side)
            Shelf(items: albums, width: CGFloat(page.tile), margin: page.side) { album in
                LibraryAlbumLink(album: album, showsArtist: showsArtist)
            }
        }
    }

    private func compact(_ shown: Artist) -> some View {
        let albums = library.albums(by: shown)
        let appearances = library.appearances(of: shown)
        let topQueue = library.topTracks(by: shown, limit: 25)
        let top = Array(topQueue.prefix(5))
        let similar = similarArtists(to: shown)
        let hasTracks = !topQueue.isEmpty
        let isRanked = library.hasPlaysOrFavorites(by: shown)

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header(shown)

                // Under the centred photo and name, centred too; Start Radio
                // in the "…" above.
                PagePlayButtons(play: { playAll(shown, shuffled: false) },
                                shuffle: { playAll(shown, shuffled: true) })
                    .disabled(!hasTracks)
                    .frame(maxWidth: .infinity)

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
                                // Its own 60 (Tokens.Row), nothing round it.
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
        // In a song's order (SYSTEM.md, Menus): playing it, keeping it,
        // its links; Linux's ⋮ the same.
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
                Task { await library.toggleFavorite(.artist(shown.id)) }
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "artist", "from": "menu"])
                radio.start(seed(for: shown))
            }
        }
        ShareMenuItem(item: .artist(shown))
    }

    private func seed(for shown: Artist) -> StationSeed {
        .artist(key: shown.key, name: shown.name, id: shown.id)
    }

    private func playAll(_ shown: Artist, shuffled: Bool) {
        let tracks = library.tracks(by: shown)
        guard !tracks.isEmpty else { return }
        player.play(tracks, context: QueueContext(.artist(shown.id), title: shown.name), shuffled: shuffled)
    }

    /// LibraryStore's, shared with Linux's artist page.
    private func similarArtists(to shown: Artist) -> [Artist] {
        library.similarArtists(to: shown, graph: radio.graph, fromServer: serverSimilar)
    }

    private func loadServerSimilar() async {
        serverSimilar = await library.serverSimilarArtists(to: artist)
    }
}
