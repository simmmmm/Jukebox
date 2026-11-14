// Search: the library in memory, so results come with each letter typed and
// without the network — artists, albums, songs and playlists, as Music lays
// them out. A song plays and goes on as its station: search is how one asks
// for a song, and the radio's way keeps the music going after it, as Music's
// Autoplay does. With nothing typed: the last searches, and the genres to
// browse.
//
// In a wide window (the iPad, the Mac) Search is a place of the sidebar and
// Linux's search page, 1:1 ("ik wil dat de linux app en de apple app 1:1 op
// elkaar lijken", the photographer, 14 November 2026): the field at the top
// of the page, holding the keys when the place shows; under it shelves of
// artists, albums and playlists, then the songs, at the page's margin and
// tile (DesktopMeasures, by the page's own width).

import JukeboxKit
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator
    @Environment(\.isWide) private var isWide

    @State private var query = ""
    @State private var recents: [String] = []
    /// Wide, the place is for typing: the field has the keys when it shows.
    @FocusState private var isFieldFocused: Bool
    /// The wide page's own width, for the field's margin.
    @State private var width: CGFloat = 0

    init() {}

    var body: some View {
        Group {
            if isWide {
                widePage
            } else {
                compact
            }
        }
        .navigationTitle("Search")
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
            SearchResultsList(term: term, remember: { remember() })
        }
    }

    private var compact: some View {
        content
            .searchable(text: $query, prompt: "Artists, albums, songs")
            .onSubmit(of: .search) { remember() }
            // A result opened (an artist, an album, a genre…): the search
            // was worth keeping. NavigationLinks say nothing when tapped;
            // the search tab's path growing is that tap.
            .onChange(of: navigator.searchPath.count) { oldCount, newCount in
                if newCount > oldCount { remember() }
            }
    }

    /// Linux's page: its search entry at the top, 24 down, at the page's
    /// margin; what it finds under it. Its results keep the search
    /// themselves as they open (SearchResultsList).
    private var widePage: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, isFocused: $isFieldFocused, submit: { remember() })
                .padding(.horizontal, DesktopMeasures.page(width: Int(width)).side)
                .padding(.top, Theme.Space.xl)
            content
        }
        .background(Theme.ground)
        .onPageWidth($width)
        // Back from a result, the search stays as it was, unfocused.
        .onAppear {
            if query.isEmpty { isFieldFocused = true }
        }
    }

    private func remember() {
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

/// Linux's search entry on the page: a magnifier, the words, and a clear
/// button once something is typed, on the ground one step up, with the
/// system's own corners for a field. Return keeps the search.
private struct SearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $text, prompt: Text("Artists, albums, songs, playlists"))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit(submit)
                .desktopFont(15)
                // A search field to VoiceOver and to the screenshot walk.
                .accessibilityAddTraits(.isSearchField)
                .accessibilityIdentifier("search.field")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 36)
        .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: Theme.Space.s))
    }
}

// MARK: - Results

private struct SearchResultsList: View {
    let term: String
    let remember: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(\.isWide) private var isWide
    /// This search has been counted (Stats): once, when the typing first
    /// rests, not at every letter. These results go when the field is
    /// emptied, and with them this; the next search counts again.
    @State private var isCounted = false
    /// The wide page's own width, for its measures.
    @State private var width: CGFloat = 0

    init(term: String, remember: @escaping () -> Void) {
        self.term = term
        self.remember = remember
    }

    var body: some View {
        let results = library.search(term)
        Group {
            if isWide {
                page(results)
            } else {
                list(results)
            }
        }
        .overlay(alignment: isWide ? .topLeading : .center) {
            if results.isEmpty {
                if isFirstLoad {
                    // Nothing found because nothing is here yet, not because
                    // the library lacks it.
                    ContentUnavailableView("Loading Your Library", systemImage: "square.stack",
                                           description: Text("Search finds your music once it has loaded."))
                } else if isWide {
                    // Linux's one plain line under the field.
                    PagePlainLine("Nothing in your library matches “\(term)”. Try part of a title or a name.")
                        .padding(.horizontal, DesktopMeasures.page(width: Int(width)).side)
                } else {
                    ContentUnavailableView.search(text: term)
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

    /// Linux's search page: shelves at the page's tile, the songs as every
    /// wide page's rows, everything at the page's margin. A result opens through
    /// the navigator, which keeps the search as it goes.
    private func page(_ results: SearchResults) -> some View {
        let measures = DesktopMeasures.page(width: Int(width))
        let margin = measures.side
        let tile = CGFloat(measures.tile)
        return ScrollView {
            // The spec's 40 between a page's sections.
            VStack(alignment: .leading, spacing: 40) {
                if !results.artists.isEmpty {
                    pageSection("Artists", margin: margin) {
                        Shelf(items: results.artists, width: tile, margin: margin) { artist in
                            Button {
                                open(.artist(artist))
                            } label: {
                                ArtistTile(artist: artist)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { artistMenu(artist) }
                        }
                    }
                }
                if !results.albums.isEmpty {
                    pageSection("Albums", margin: margin) {
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
                }
                if !results.playlists.isEmpty {
                    pageSection("Playlists", margin: margin) {
                        Shelf(items: results.playlists, width: tile, margin: margin) { playlist in
                            Button {
                                open(.playlist(playlist))
                            } label: {
                                PlaylistTile(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !results.tracks.isEmpty {
                    // Songs' rows, as every wide page's (TrackRow's 64), 8
                    // under their heading.
                    pageSection("Songs", margin: margin, below: Theme.Space.s) {
                        PageTrackRows(tracks: results.tracks, play: { track in
                            startStation(from: track)
                        })
                        .padding(.horizontal, margin)
                    }
                }
            }
            // Linux's: a section title 40 below the field, 40 at the foot.
            .padding(.vertical, 40)
        }
        .background(Theme.ground)
        .scrollDismissesKeyboard(.immediately)
        .onPageWidth($width)
    }

    /// A section of the wide page: its heading (PageSectionTitle) at the
    /// page's margin, 16 above what it holds (8 above rows), as Linux's.
    private func pageSection<Content: View>(_ title: String.LocalizationValue, margin: CGFloat,
                                            below: CGFloat = Theme.Space.l,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PageSectionTitle(String(localized: title), above: 0, below: below)
                .padding(.horizontal, margin)
            content()
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
                            artistMenu(artist)
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

    private func artistMenu(_ artist: Artist) -> some View {
        Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
            remember()
            Stats.track(.stationStarted, ["seed": "artist", "from": "search"])
            radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))
        }
    }

    @ViewBuilder private func albumMenu(_ album: Album) -> some View {
        let tracks = library.tracks(inAlbum: album.id)
        if !tracks.isEmpty {
            Button("Play", systemImage: "play") {
                remember()
                player.play(tracks, context: QueueContext(.album(album.id), title: album.name))
            }
        }
        Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
            remember()
            Stats.track(.stationStarted, ["seed": "album", "from": "search"])
            radio.start(.album(album.id))
        }
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
            ArtworkView(album.artwork, size: 48, cornerRadius: Theme.Radius.artwork)
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
    @Environment(\.isWide) private var isWide
    /// The page's own width, for the wide page's measures.
    @State private var width: CGFloat = 0

    init(recents: [String], pick: @escaping (String) -> Void, remove: @escaping (String) -> Void,
         clear: @escaping () -> Void) {
        self.recents = recents
        self.pick = pick
        self.remove = remove
        self.clear = clear
    }

    var body: some View {
        ScrollView {
            // The spec's 40 between a wide page's sections.
            VStack(alignment: .leading, spacing: isWide ? 40 : Theme.Space.xxl) {
                if !recents.isEmpty {
                    recentSection
                }
                if !library.genres.isEmpty {
                    genreSection
                }
            }
            // Wide, 40 under the page's field, as the results' first title.
            .padding(.vertical, isWide ? 40 : Theme.Space.l)
        }
        .background(Theme.ground)
        .scrollDismissesKeyboard(.immediately)
        .onPageWidth($width)
        .overlay {
            if recents.isEmpty && library.genres.isEmpty {
                ContentUnavailableView {
                    Label("Search Your Library", systemImage: "magnifyingglass")
                } description: {
                    Text("Find artists, albums, songs and playlists on your \(library.serverKind) server.")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                // SectionHeader's look, with Clear where See All would be;
                // wide, a page's section title.
                Text("Recent searches")
                    .desktopFont(24, design: .serif, phone: .serif(.title2))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") { clear() }
                    .desktopFont(15, phone: nil)
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
                        .desktopFont(15, phone: nil)
                        .padding(.vertical, Theme.Space.m)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "xmark", role: .destructive) {
                            remove(term)
                        }
                    }
                    Divider()
                }
            }
            .padding(.leading, margin)
            // Wide, the rows end at the page's margin too, as Linux's do.
            .padding(.trailing, isWide ? margin : 0)
        }
    }

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // Wide, a page's section title at the page's margin; Genres is
            // the sidebar's too, so no See All.
            if isWide {
                PageSectionTitle(String(localized: "Genres"), above: 0, below: Theme.Space.xs)
                    .padding(.horizontal, margin)
            } else {
                SectionHeader("Genres", route: .genres)
            }
            LazyVGrid(columns: genreColumns, spacing: 0) {
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
                    }
                }
            }
            .padding(.horizontal, margin)
        }
    }

    /// The page's margin: the iPhone's, or DesktopMeasures' by the page's
    /// own width.
    private var margin: CGFloat {
        isWide ? DesktopMeasures.page(width: Int(width)).side : Theme.margin
    }

    /// Two across on the iPhone, as Music's categories; wide, as many as
    /// the page's tiles would take, so a genre is as wide as an album.
    private var genreColumns: [GridItem] {
        var count = 2
        if isWide {
            let page = DesktopMeasures.page(width: Int(width))
            let gap = Int(Theme.Space.m)
            count = max(2, (Int(width) - 2 * page.margin + gap) / (page.tile + gap))
        }
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Space.m), count: count)
    }
}

/// A genre to browse: its name on the ground over a hairline, no tile
/// (tells.md, 6). No colours of its own — the accent (Copper, Glow) stays
/// the only one.
private struct SearchGenreTile: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: name)
                .desktopFont(15, phone: nil)
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
