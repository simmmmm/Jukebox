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
                                radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))
                            }
                        }
                    }
                } header: {
                    Eyebrow("Artists")
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
                    Eyebrow("Albums")
                }
            }

            if !results.tracks.isEmpty {
                Section {
                    ForEach(results.tracks) { track in
                        Button {
                            remember()
                            // The song first, then what sounds like it: the
                            // station of a song opens with that song.
                            radio.start(.track(track.id))
                        } label: {
                            TrackRow.standard(track)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Eyebrow("Songs")
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
                    Eyebrow("Playlists")
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
            ArtworkView(album.artwork, size: 48, cornerRadius: Theme.Radius.thumbnail)
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
            ArtworkView(playlist.artwork, size: 48, cornerRadius: Theme.Radius.thumbnail,
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
                // SectionHeader's look, with Clear where its chevron would be.
                Text("Recent Searches")
                    .font(.title2.bold())
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
            SectionHeader("Browse Genres", route: .genres)
            LazyVGrid(columns: genreColumns, spacing: Theme.Space.m) {
                ForEach(library.genres) { genre in
                    NavigationLink(value: Route.genre(genre)) {
                        SearchGenreTile(name: genre.name)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
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

/// A genre to browse: its name on a grey rounded tile. No colours of its
/// own — the accent (Copper, Glow) stays the only one.
private struct SearchGenreTile: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.headline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .bottomLeading)
            .padding(Theme.Space.m)
            .background(.quaternary, in: .rect(cornerRadius: Theme.Radius.card))
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
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
