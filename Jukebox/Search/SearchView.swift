// Search: the library in memory, so results come with each letter typed and
// without the network — artists, albums, songs and playlists, as Music lays
// them out. A song plays and goes on as its station: search is how one asks
// for a song, and the radio's way keeps the music going after it, as Music's
// Autoplay does. With nothing typed: the last searches, and the genres to
// browse.

import JukeboxKit
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(Navigator.self) private var navigator

    @State private var query = ""
    @State private var recents: [String] = []

    init() {}

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if term.isEmpty {
                SearchBrowse(recents: recents,
                             pick: { picked in query = picked },
                             remove: { removed in forget(removed) },
                             clear: { clearRecents() })
            } else {
                SearchResultsList(term: term, remember: { remember() })
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Artists, albums, songs")
        .onSubmit(of: .search) { remember() }
        // A result opened (an artist, an album, a genre…): the search was
        // worth keeping. NavigationLinks say nothing when tapped; the
        // search tab's path growing is that tap.
        .onChange(of: navigator.searchPath.count) { oldCount, newCount in
            if newCount > oldCount { remember() }
        }
        .task(id: app.credentials?.userID) {
            recents = SearchRecents.load(for: app.credentials?.userID)
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

// MARK: - Results

private struct SearchResultsList: View {
    let term: String
    let remember: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    /// This search has been counted (Stats): once, when the typing first
    /// rests, not at every letter. These results go when the field is
    /// emptied, and with them this; the next search counts again.
    @State private var isCounted = false

    init(term: String, remember: @escaping () -> Void) {
        self.term = term
        self.remember = remember
    }

    var body: some View {
        let results = library.search(term)
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
                            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                                remember()
                                Stats.track(.stationStarted, ["seed": "artist", "from": "search"])
                                radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))
                            }
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
                            // Offline, a song not on the phone says why: its
                            // station would not open with it.
                            guard !player.refusesOffline(track) else { return }
                            remember()
                            // The song first, then what sounds like it: the
                            // station of a song opens with that song.
                            Stats.track(.stationStarted, ["seed": "track", "from": "search"])
                            radio.start(.track(track.id))
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
        .overlay {
            if results.isEmpty {
                if isFirstLoad {
                    // Nothing found because nothing is here yet, not because
                    // the library lacks it.
                    ContentUnavailableView("Loading Your Library", systemImage: "square.stack",
                                           description: Text("Search finds your music once it has loaded."))
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
            VStack(alignment: .leading, spacing: 2) {
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
            VStack(alignment: .leading, spacing: 2) {
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
    @Environment(\.horizontalSizeClass) private var sizeClass

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
                    Label("Search Your Library", systemImage: "magnifyingglass")
                } description: {
                    Text("Find artists, albums, songs and playlists on your Jellyfin server.")
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                // SectionHeader's look, with Clear where See All would be.
                Text("Recent searches")
                    .font(.serif(.title2))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear") { clear() }
                    .accessibilityLabel("Clear Recent Searches")
            }
            .padding(.horizontal, Theme.margin)

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
            .padding(.leading, Theme.margin)
        }
    }

    private var genreSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Genres", route: .genres)
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
            .padding(.horizontal, Theme.margin)
        }
    }

    /// Two across on the iPhone, as Music's categories; four on the iPad.
    private var genreColumns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 2
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
