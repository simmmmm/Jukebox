// Search: the library in memory, so results come with each letter typed and
// without the network — artists, albums, songs and playlists, as Music lays
// them out. A song plays and goes on as its station: search is how one asks
// for a song, and the radio's way keeps the music going after it, as Music's
// Autoplay does. With nothing typed: the last searches, and the genres to
// browse.
//
// In a wide window (the iPad, the Mac) the field is the window bar's, on
// every page ("ik wil die searchbar gewoon bovenin de vensterbar hebben",
// the photographer, 14 November 2026), and this is the page it searches on,
// the same as Linux's: its title; with nothing typed the recent searches;
// with something, shelves of artists, albums and playlists, then the songs,
// at the page's margin and tile (DesktopMeasures, by the page's own width).

import JukeboxKit
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator
    @Environment(\.isWide) private var isWide

    /// The iPhone's field. Wide, the bar's: `navigator.searchQuery`.
    @State private var query = ""
    @State private var recents: [String] = []
    @FocusState private var isFieldFocused: Bool

    init() {}

    var body: some View {
        Group {
            if isWide {
                widePage
            } else {
                compact
                    .navigationTitle("Search")
            }
        }
        .task(id: app.credentials?.userID) {
            recents = SearchRecents.load(for: app.credentials?.userID)
        }
    }

    private var term: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var content: some View {
        if term.isEmpty {
            SearchBrowse(recents: recents,
                         pick: { picked in query = picked },
                         remove: { removed in forget(removed) },
                         clear: { clearRecents() })
        } else {
            SearchResultsList(term: term, remember: { remember(query) })
        }
    }

    private var compact: some View {
        content
            #if os(iOS)
            // Always shown under the title, not tucked away until the page
            // is pulled down: "En het zoekveld moet wel meteen zichtbaar zijn
            // nu moet je eerst een stukje omhoog scrollen" (the photographer,
            // 20 November 2026).
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Artists, albums, songs")
            #else
            .searchable(text: $query, prompt: "Artists, albums, songs")
            #endif
            // Search's tab tapped again on its first page (Navigator.select):
            // the field, and the keyboard. The first tap leaves it down.
            .searchFocused($isFieldFocused)
            .onChange(of: navigator.searchRequests) { _, _ in
                isFieldFocused = true
            }
            .onSubmit(of: .search) { remember(query) }
            // A result opened (an artist, an album, a genre…): the search
            // was worth keeping. NavigationLinks say nothing when tapped;
            // the search tab's path growing is that tap.
            .onChange(of: navigator.searchPath.count) { oldCount, newCount in
                if newCount > oldCount { remember(query) }
            }
    }

    /// The page the bar's field searches on, one spec with Linux's (the
    /// photographer, 14 November 2026). A search is kept as a recent one
    /// when Return is pressed in the field or a result is opened.
    private var widePage: some View {
        let typed = navigator.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return WidePage(title: "Search") { page, _ in
            PageTitle("Search")
                .padding(.horizontal, page.side)
            if typed.isEmpty {
                recentRows(page)
            } else {
                SearchResultsList(term: typed, page: page, remember: { remember(navigator.searchQuery) })
            }
        }
        .onChange(of: navigator.searchSubmits) { _, _ in
            remember(navigator.searchQuery)
        }
    }

    /// The last eight searches, newest first, as plain rows: one fills the
    /// bar's field with it, and so searches. None yet: what the field is for.
    @ViewBuilder private func recentRows(_ page: DesktopMeasures.Page) -> some View {
        if recents.isEmpty {
            PagePlainLine("Search your artists, albums, songs and playlists.")
                .padding(.horizontal, page.side)
        } else {
            HStack(alignment: .firstTextBaseline) {
                PageSectionTitle(String(localized: "Recent searches"), below: Theme.Space.s)
                Spacer(minLength: Theme.Space.m)
                Button("Clear") { clearRecents() }
                    .buttonStyle(.plain)
                    .desktopFont(Tokens.Size.body15.size)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Recent Searches")
            }
            .padding(.horizontal, page.side)
            ForEach(recents.prefix(8), id: \.self) { term in
                Button {
                    navigator.searchQuery = term
                } label: {
                    Text(verbatim: term)
                        .desktopFont(Tokens.Size.body15.size)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        // 40 a row, as Linux's.
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove", systemImage: "xmark", role: .destructive) {
                        forget(term)
                    }
                    .menuIcons()
                }
                .padding(.horizontal, page.side)
            }
        }
    }

    private func remember(_ query: String) {
        let updated = SearchRecents.adding(query, to: recents)
        guard updated != recents else { return }
        recents = updated
        SearchRecents.save(updated, for: app.credentials?.userID)
    }

    private func forget(_ term: String) {
        recents.removeAll { $0 == term }
        SearchRecents.save(recents, for: app.credentials?.userID)
    }

    private func clearRecents() {
        recents = []
        SearchRecents.save([], for: app.credentials?.userID)
    }
}

// MARK: - Results

private struct SearchResultsList: View {
    let term: String
    /// The wide page's measures: its sections, in the page's scroll. Nil:
    /// the iPhone's list.
    let page: DesktopMeasures.Page?
    let remember: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    /// This search has been counted (Stats): once, when the typing first
    /// rests, not at every letter. These results go when the field is
    /// emptied, and with them this; the next search counts again.
    @State private var isCounted = false

    init(term: String, page: DesktopMeasures.Page? = nil, remember: @escaping () -> Void) {
        self.term = term
        self.page = page
        self.remember = remember
    }

    var body: some View {
        // Wide, 20 of each, as Linux's; the iPhone's list as it was.
        let results = page == nil ? library.search(term) : library.search(term, limit: 20)
        Group {
            if let page {
                sections(results, page)
            } else {
                list(results)
                    .overlay {
                        if results.isEmpty {
                            if isFirstLoad {
                                // Nothing found because nothing is here yet, not
                                // because the library lacks it.
                                ContentUnavailableView("Loading your music", systemImage: "square.stack",
                                                       description: Text("Search finds your music once it has loaded."))
                            } else {
                                ContentUnavailableView.search(text: term)
                            }
                        }
                    }
            }
        }
        // How much a search finds, in buckets; never what was typed.
        .task(id: term) {
            guard !isCounted else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isCounted = true
            Stats.track(.searchUsed, ["results": Stats.resultCount(results.artists.count + results.albums.count + results.tracks.count + results.playlists.count)])
        }
    }

    // MARK: Wide

    /// The wide page's: each kind only when it has matches, at most 20 of
    /// each, Artists, Albums and Playlists as shelves at the page's tile,
    /// then the songs as every wide page's rows, all at the page's margin
    /// (one spec with Linux's). A result opens through the navigator, which
    /// keeps the search as it goes.
    private func sections(_ results: SearchResults, _ page: DesktopMeasures.Page) -> some View {
        let margin = page.side
        let tile = CGFloat(page.tile)
        return VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                // While the library still loads, its status.
                PageEmptyLine("Nothing found for “\(term)”.")
                    .padding(.horizontal, margin)
            }
            if !results.artists.isEmpty {
                PageSectionTitle(String(localized: "Artists"))
                    .padding(.horizontal, margin)
                Shelf(items: results.artists, width: tile, margin: margin) { artist in
                    Button {
                        open(.artist(artist))
                    } label: {
                        // Round, and the name alone, as Linux's Search.
                        WideTile(name: artist.name) {
                            ArtistAvatar(artist: artist)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { artistMenu(artist).menuIcons() }
                }
            }
            if !results.albums.isEmpty {
                PageSectionTitle(String(localized: "Albums"))
                    .padding(.horizontal, margin)
                Shelf(items: results.albums, width: tile, margin: margin) { album in
                    Button {
                        open(.album(album))
                    } label: {
                        AlbumTile(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { albumMenu(album) }
                }
            }
            if !results.playlists.isEmpty {
                PageSectionTitle(String(localized: "Playlists"))
                    .padding(.horizontal, margin)
                Shelf(items: results.playlists, width: tile, margin: margin) { playlist in
                    Button {
                        open(.playlist(playlist))
                    } label: {
                        PlaylistTile(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !results.tracks.isEmpty {
                // TrackRow's 64, 8 under their heading; the artist and the
                // album under the title, as Linux's.
                PageSectionTitle(String(localized: "Songs"), below: Theme.Space.s)
                    .padding(.horizontal, margin)
                PageTrackRows(tracks: results.tracks,
                              subtitle: { [$0.artistLine, $0.albumName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") },
                              play: { track in
                    startStation(from: track)
                })
                .padding(.horizontal, margin)
            }
        }
    }

    private func open(_ route: Route) {
        remember()
        navigator.open(route)
    }

    // MARK: Compact

    private func list(_ results: SearchResults) -> some View {
        List {
            if !results.artists.isEmpty {
                Section {
                    ForEach(results.artists) { artist in
                        NavigationLink(value: Route.artist(artist)) {
                            HStack(spacing: Theme.Space.m) {
                                ArtistAvatar(artist: artist, size: 44)
                                Text(artist.name)
                                    .lineLimit(1)
                            }
                        }
                        .contextMenu {
                            artistMenu(artist).menuIcons()
                        }
                    }
                } header: {
                    ListHeading("Artists")
                }
            }

            if !results.albums.isEmpty {
                Section {
                    ForEach(results.albums) { album in
                        NavigationLink(value: Route.album(album)) {
                            SearchAlbumRow(album: album)
                        }
                        .contextMenu {
                            albumMenu(album)
                        }
                    }
                } header: {
                    ListHeading("Albums")
                }
            }

            if !results.tracks.isEmpty {
                Section {
                    ForEach(results.tracks) { track in
                        Button {
                            startStation(from: track)
                        } label: {
                            TrackRow.standard(track)
                        }
                        .buttonStyle(.plain)
                        .trackListRow()
                    }
                } header: {
                    ListHeading("Songs")
                }
            }

            if !results.playlists.isEmpty {
                Section {
                    ForEach(results.playlists) { playlist in
                        NavigationLink(value: Route.playlist(playlist)) {
                            SearchPlaylistRow(playlist: playlist)
                        }
                    }
                } header: {
                    ListHeading("Playlists")
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: Both

    private func startStation(from track: Track) {
        // Offline, a song not on the phone says why: its station would not
        // open with it.
        guard !player.refusesOffline(track) else { return }
        remember()
        // The song first, then what sounds like it: the station of a song
        // opens with that song.
        Stats.track(.stationStarted, ["seed": "track", "from": "search"])
        radio.start(.track(track.id))
    }

    /// Start Radio, then the link, as an artist's tile in Artists.
    @ViewBuilder private func artistMenu(_ artist: Artist) -> some View {
        Section {
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                remember()
                Stats.track(.stationStarted, ["seed": "artist", "from": "search"])
                radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))
            }
        }
        Section {
            ShareMenuItem(item: .artist(artist))
        }
    }

    /// The one album menu every tile and row has, as Linux's albumMenu.
    private func albumMenu(_ album: Album) -> some View {
        LibraryAlbumMenu(album: album)
    }

    private var isFirstLoad: Bool {
        guard library.tracks.isEmpty else { return false }
        if case .loading = library.state { return true }
        return false
    }
}

private struct SearchAlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ArtworkView(album.artwork, size: 48, cornerRadius: Theme.Radius.artwork, sleeve: TitleSleeve.Words(album: album))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(album.name)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Radiohead · 2000"
    private var subtitle: String {
        var parts: [String] = []
        if !album.artistLine.isEmpty { parts.append(album.artistLine) }
        if let year = album.year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }
}

private struct SearchPlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ArtworkView(playlist.artwork, size: 48, cornerRadius: Theme.Radius.artwork,
                        placeholder: "music.note.list")
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(playlist.name)
                    .lineLimit(1)
                if let count = playlist.trackCount {
                    Text(count == 1 ? "1 song" : "\(count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Nothing typed

private struct SearchBrowse: View {
    let recents: [String]
    let pick: (String) -> Void
    let remove: (String) -> Void
    let clear: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(RadioController.self) private var radio

    init(recents: [String], pick: @escaping (String) -> Void, remove: @escaping (String) -> Void,
         clear: @escaping () -> Void) {
        self.recents = recents
        self.pick = pick
        self.remove = remove
        self.clear = clear
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                if !recents.isEmpty {
                    recentSection
                }
                if !library.genres.isEmpty {
                    genreSection
                }
            }
            .padding(.vertical, Theme.Space.l)
        }
        .background(Theme.ground)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if recents.isEmpty && library.genres.isEmpty {
                ContentUnavailableView {
                    Label("Search your library", systemImage: "magnifyingglass")
                } description: {
                    Text("Find artists, albums, songs and playlists on your \(library.serverKind) server.")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                // SectionHeader's look, with Clear where See All would be.
                Text("Recent searches")
                    .desktopFont(Tokens.Size.sectionTitle.size, design: .serif, phone: .serif(.title2))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") { clear() }
                    .desktopFont(Tokens.Size.body15.size, phone: nil)
                    .accessibilityLabel("Clear Recent Searches")
            }
            .padding(.horizontal, margin)

            VStack(spacing: 0) {
                ForEach(recents, id: \.self) { term in
                    Button {
                        pick(term)
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(verbatim: term)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .desktopFont(Tokens.Size.body15.size, phone: nil)
                        .padding(.vertical, Theme.Space.m)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "xmark", role: .destructive) {
                            remove(term)
                        }
                        .menuIcons()
                    }
                    Divider()
                }
            }
            .padding(.leading, margin)
        }
    }

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Genres", route: .genres)
            // Two across, as Music's categories.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m), count: 2),
                      spacing: 0) {
                ForEach(library.genres) { genre in
                    NavigationLink(value: Route.genre(genre)) {
                        SearchGenreTile(name: genre.name)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                            Stats.track(.stationStarted, ["seed": "genre", "from": "search"])
                            radio.start(.genre(key: genre.key, name: genre.name))
                        }
                        .menuIcons()
                    }
                }
            }
            .padding(.horizontal, margin)
        }
    }

    private var margin: CGFloat { Theme.margin }
}

/// A genre to browse: its name on the ground over a hairline, no tile
/// (tells.md, 6). No colours of its own — the accent (Copper, Glow) stays
/// the only one.
private struct SearchGenreTile: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: name)
                .desktopFont(Tokens.Size.body15.size, phone: nil)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Divider()
        }
        .contentShape(.rect)
    }
}

// MARK: - Recent searches

/// The last ten searches, newest first, one list per user on this device,
/// in UserDefaults: what was typed, not what it found, so a search typed
/// again finds what the library has now.
private enum SearchRecents {
    static let limit = 10

    static func load(for userID: String?) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(for: userID)) ?? []
    }

    static func save(_ terms: [String], for userID: String?) {
        UserDefaults.standard.set(terms, forKey: key(for: userID))
    }

    /// `term` on top; the same search typed differently ("radiohead",
    /// "Radiohead") kept once, as last typed.
    static func adding(_ term: String, to terms: [String]) -> [String] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return terms }
        var result = terms.filter {
            $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        result.insert(term, at: 0)
        return Array(result.prefix(limit))
    }

    private static func key(for userID: String?) -> String {
        "recentSearches." + (userID ?? "")
    }
}
