// Playlists: the listener's own, on the server (so every app of that server
// has them), made here with New Playlist…, filled with the playlist's own Add
// Songs (the library's songs, found by name, a + on each) or from any
// menu's Add to Playlist…, edited in place: swipe to remove a song, Edit to
// reorder, Delete Playlist behind the "…". A playlist's songs are read from
// the server each time its page appears, and again when Add Songs closes or
// a song is added from elsewhere (Now Playing's menu): playlists change in
// other apps too, and a page that missed a song it was just given looks
// broken. Download in the bar puts the playlist on the phone; a downloaded
// playlist follows what the server says it holds each time its page reads
// it, and offline its page shows the songs it was downloaded with.
//
// A playlist the server would not let this user change — someone else's,
// shared on a Subsonic server (`Playlist.isReadOnly`) — plays and downloads
// like any other, with nothing offered that the server would refuse: no
// Delete, no Add Songs, no Edit, and it is not among Add to Playlist's
// choices. Reordering is offered where the server can (Jellyfin; a Subsonic
// server from API 1.14, ServerCapability.playlistReorder).
//
// In a wide window, as Linux's (08-playlists): the playlists as a grid of
// the page's tiles, New Playlist… in the toolbar; a playlist's page with
// the cover at the left and its title at the foot, the songs in rows. On
// the Mac a song is dragged to its place and removed from its menu (a
// right-click); the iPad keeps Edit.

import JukeboxKit
import SwiftUI

struct PlaylistsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.isWide) private var isWide
    @State private var isNaming = false
    @State private var newName = ""
    @State private var pendingDelete: Playlist?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isWide {
                wide
            } else {
                compact
            }
        }
        .alert("New Playlist", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { create() }
        } message: {
            Text("Then add songs with Add Songs on its page, or from any song’s or album’s menu.")
        }
        .confirmationDialog("Delete Playlist?", isPresented: isConfirmingDelete, titleVisibility: .visible,
                            presenting: pendingDelete) { playlist in
            Button("Delete “\(playlist.name)”", role: .destructive) {
                delete(playlist)
            }
        } message: { _ in
            Text("It is deleted from your \(library.serverKind) server, for every app. Its songs stay in your library.")
        }
        .libraryErrorAlert("Could Not Change Playlists", message: $errorMessage)
    }

    /// Linux's Playlists: a grid of tiles; Delete in an own one's menu.
    private var wide: some View {
        WidePage(title: "Playlists") { page, width in
            PageTitle("Playlists")
                .padding(.horizontal, page.side)
            if library.playlists.isEmpty {
                PageEmptyLine("Make one with New Playlist…, or add songs to one from any song’s menu.")
                    .padding(.horizontal, page.side)
            } else {
                TileGrid(items: library.playlists, page: page, width: width) { playlist in
                    NavigationLink(value: Route.playlist(playlist)) {
                        PlaylistTile(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !playlist.isReadOnly {
                            Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                                pendingDelete = playlist
                            }
                        }
                    }
                }
                .padding(.top, Theme.Space.xl)
            }
        }
        .toolbar {
            ToolbarItem(placement: .barTrailing) {
                Button {
                    newName = ""
                    isNaming = true
                } label: {
                    Label("New Playlist…", systemImage: "plus")
                }
            }
        }
        .refreshable { await library.refresh() }
    }

    private var compact: some View {
        List {
            Button {
                newName = ""
                isNaming = true
            } label: {
                Label("New Playlist…", systemImage: "plus")
            }

            ForEach(library.playlists) { playlist in
                row(playlist)
            }

            if library.playlists.isEmpty {
                LibraryStatusView(emptyTitle: "No Playlists", emptySymbol: "music.note.list",
                                  emptyMessage: "Make one with New Playlist…, or add songs to one from any song’s menu.")
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Playlists")
        .refreshable { await library.refresh() }
    }

    /// Someone else's playlist opens and plays; only the listener's own
    /// can be deleted.
    @ViewBuilder
    private func row(_ playlist: Playlist) -> some View {
        if playlist.isReadOnly {
            NavigationLink(value: Route.playlist(playlist)) {
                LibraryPlaylistRow(playlist: playlist)
            }
        } else {
            NavigationLink(value: Route.playlist(playlist)) {
                LibraryPlaylistRow(playlist: playlist)
            }
            .swipeActions {
                // Red by tint, not by the destructive role: with the role,
                // List slides the row away as deleted at once, before the
                // dialog below has asked.
                Button("Delete", systemImage: "trash") {
                    pendingDelete = playlist
                }
                .tint(.red)
            }
            .contextMenu {
                Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                    pendingDelete = playlist
                }
            }
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func create() {
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? String(localized: "New Playlist") : typed
        Task {
            do {
                let playlist = try await library.createPlaylist(named: name, with: [])
                Stats.track(.playlistCreated, ["from": "library"])
                // Into it at once, as Music does: the next thing is filling it.
                navigator.open(.playlist(playlist))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ playlist: Playlist) {
        Task {
            do {
                try await library.delete(playlist)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist

    init(playlist: Playlist) {
        self.playlist = playlist
    }

    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(OfflineStore.self) private var offline
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isWide) private var isWide
    /// The page's own width, for its measures (wide).
    @State private var width: CGFloat = 1000
    /// Nil until the server has answered.
    @State private var entries: [LibraryPlaylistEntry]?
    @State private var isConfirmingRemoval = false
    @State private var loadError: String?
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false
    @State private var isAddingSongs = false
    /// Counts loads, so an answer that a later load has overtaken is dropped.
    @State private var loadCount = 0
    /// Choose Picture… where the server and the user may (PlaylistPicture).
    @State private var picturesAllowed = false
    @State private var isChoosingPicture = false
    /// Songs picked with ⌘ or ⇧ in the wide list (TrackPicks).
    @State private var picks = TrackPicks()

    var body: some View {
        let shown = library.playlists.first(where: { $0.id == playlist.id }) ?? playlist
        let tracks = entries?.map(\.track) ?? []

        Group {
            if isWide {
                wide(shown, tracks: tracks)
            } else {
                compact(shown, tracks: tracks)
            }
        }
        .toolbar {
            if !shown.isReadOnly {
                ToolbarItem(placement: .barTrailing) {
                    Button {
                        isAddingSongs = true
                    } label: {
                        Label("Add Songs", systemImage: "plus")
                    }
                    .disabled(entries == nil)
                }
                // The iPhone's Edit mode. A Mac's list has none: there a
                // song is dragged to where it goes.
                #if os(iOS)
                ToolbarItem(placement: .barTrailing) {
                    // Off only while loading: after the last song is removed in
                    // edit mode, Done must still be there to leave it.
                    EditButton()
                        .disabled(entries == nil)
                }
                #endif
            }
            if offline.offersDownload(for: .playlist(playlist.id)) {
                ToolbarItem(placement: .barTrailing) {
                    OfflineDownloadButton(collection: OfflineCollection(playlist: shown, tracks: tracks),
                                          isConfirmingRemoval: $isConfirmingRemoval)
                }
            }
            // Wide, the head has its own "…".
            if !isWide {
                ToolbarItem(placement: .barTrailing) {
                    Menu {
                        moreItems(shown, tracks: tracks)
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
        .confirmationDialog("Delete “\(shown.name)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                deletePlaylist(shown)
            }
        } message: {
            Text("It is deleted from your \(library.serverKind) server, for every app. Its songs stay in your library.")
        }
        .libraryErrorAlert("Could Not Change the Playlist", message: $errorMessage)
        .offlineRemovalDialog($isConfirmingRemoval, for: .playlist(playlist.id), name: shown.name)
        .sheet(isPresented: $isAddingSongs, onDismiss: { Task { await load() } }) {
            LibraryAddSongsSheet(playlist: shown, songsInPlaylist: Set(tracks.map(\.id)))
        }
        // Every time the page appears, not only the first: songs added from
        // Now Playing or another app while it was covered are shown.
        .task(id: playlist.id) { await load() }
        .task(id: playlist.id) { picturesAllowed = await library.playlistCoversAllowed() }
        .playlistPicturePicker(isPresented: $isChoosingPicture, for: shown, failed: $errorMessage)
        // A song added from a menu while the page is open (Add to Playlist…
        // changes the count at once); not while Add Songs is open, which
        // reloads once when it closes.
        .onChange(of: shown.trackCount) { _, count in
            guard !isAddingSongs, let entries, count != entries.count else { return }
            Task { await load() }
        }
        .refreshable { await load() }
    }

    /// Linux's playlist page: the head (the cover, the title at its foot,
    /// how many songs and how long, Play, Shuffle, "…"), a hairline, the
    /// songs in rows. A List still, for the order: on the Mac a song is
    /// dragged to its place, and its menu has Remove from Playlist; the iPad
    /// keeps Edit.
    private func wide(_ shown: Playlist, tracks: [Track]) -> some View {
        let page = DesktopMeasures.page(width: Int(width))
        let count = entries?.count ?? shown.trackCount ?? 0
        let duration = entries == nil ? (shown.duration ?? 0) : LibraryText.totalDuration(tracks)
        return List {
            Group {
                PageHead(page: page, title: shown.name,
                         facts: LibraryText.length(count: count, duration: duration)) { size in
                    cover(shown, tracks: tracks, size: size)
                } actions: {
                    PagePlayButtons(play: { play(tracks, from: 0, playlist: shown, shuffled: false) },
                                    shuffle: { play(tracks, from: 0, playlist: shown, shuffled: true) })
                        .disabled(tracks.isEmpty)
                    MoreMenu {
                        moreItems(shown, tracks: tracks)
                    }
                }
                PageRule(page: page)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            if let entries {
                ForEach(entries) { entry in
                    let i = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
                    Button {
                        if let kind = heldPick() { picks.click(i, kind); return }
                        picks.plain(i)
                        guard !player.refusesOffline(entry.track) else { return }
                        play(tracks, from: i, playlist: shown, shuffled: false)
                    } label: {
                        TrackRow(entry.track, subtitle: entry.track.artistLine,
                                 removal: shown.isReadOnly ? nil : { removeEntry(entry.id, from: shown) })
                    }
                    .buttonStyle(.plain)
                    .picking { picks.click(i, $0) }
                    .environment(\.pickedTracks, picks.contains(i) ? picks.tracks(at: i, in: tracks) : [])
                }
                .onDelete(perform: deleteAction(shown))
                .onMove(perform: moveAction(shown))
                .pageRow(page)

                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        PagePlainLine(shown.isReadOnly ? "No songs yet."
                                      : "Add songs from your library, or choose Add to Playlist… in any song’s or album’s menu.")
                        if !shown.isReadOnly {
                            WordButton("Add Songs") {
                                isAddingSongs = true
                            }
                        }
                    }
                    .pageRow(page)
                }
            } else if let loadError {
                VStack(alignment: .leading, spacing: 0) {
                    PagePlainLine("\(loadError)")
                    WordButton("Try Again") {
                        self.loadError = nil
                        Task { await load() }
                    }
                }
                .pageRow(page)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .pageRow(page)
            }
        }
        .listStyle(.plain)
        .onChange(of: entries?.map(\.id)) { picks.clear() }
        .pageGround()
        .onPageWidth($width)
        .libraryScrolledTitle(shown.name, after: page.cover + Theme.Space.xl)
    }

    private func compact(_ shown: Playlist, tracks: [Track]) -> some View {
        List {
            header(shown, tracks: tracks)
                .listRowInsets(EdgeInsets(top: Theme.Space.l, leading: Theme.margin,
                                          bottom: Theme.Space.l, trailing: Theme.margin))
                .listRowSeparator(.hidden)

            if let entries {
                ForEach(entries) { entry in
                    Button {
                        guard !player.refusesOffline(entry.track) else { return }
                        let i = entries.firstIndex(where: { $0.id == entry.id }) ?? 0
                        play(tracks, from: i, playlist: shown, shuffled: false)
                    } label: {
                        TrackRow.standard(entry.track)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteAction(shown))
                .onMove(perform: moveAction(shown))

                if entries.isEmpty {
                    if shown.isReadOnly {
                        ContentUnavailableView("No Songs Yet", systemImage: "music.note.list")
                            .listRowSeparator(.hidden)
                    } else {
                        ContentUnavailableView {
                            Label("No Songs Yet", systemImage: "music.note.list")
                        } description: {
                            Text("Add songs from your library, or choose Add to Playlist… in any song’s or album’s menu.")
                        } actions: {
                            Button("Add Songs") {
                                isAddingSongs = true
                            }
                            .buttonStyle(.secondary)
                            .fixedSize()
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            } else if let loadError {
                ContentUnavailableView {
                    Label("Could Not Load the Playlist", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") {
                        self.loadError = nil
                        Task { await load() }
                    }
                }
                .listRowSeparator(.hidden)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .libraryScrolledTitle(shown.name, after: 280)
    }

    /// The page's "…": in the toolbar on the iPhone, in the head when wide.
    @ViewBuilder
    private func moreItems(_ shown: Playlist, tracks: [Track]) -> some View {
        Section {
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "collection", "from": "menu"])
                radio.start(seed(for: shown, tracks: tracks))
            }
            .disabled(tracks.isEmpty)
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
        if picturesAllowed, !shown.isReadOnly {
            Section {
                Button("Choose Picture…", systemImage: "photo") {
                    isChoosingPicture = true
                }
            }
        }
        if !shown.isReadOnly {
            Section {
                Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
    }

    private func header(_ shown: Playlist, tracks: [Track]) -> some View {
        let count = entries?.count ?? shown.trackCount ?? 0
        let duration = entries == nil ? (shown.duration ?? 0) : LibraryText.totalDuration(tracks)
        return VStack(spacing: Theme.Space.s) {
            cover(shown, tracks: tracks)
                .padding(.bottom, Theme.Space.m)
            Text(shown.name)
                .font(.serif(.title))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(LibraryText.summary(count: count, duration: duration))
                .font(.footnote)
                .foregroundStyle(.secondary)
            // Start Radio is in the "…" above.
            PagePlayButtons(play: { play(tracks, from: 0, playlist: shown, shuffled: false) },
                            shuffle: { play(tracks, from: 0, playlist: shown, shuffled: true) })
                .padding(.top, Theme.Space.m)
                .disabled(tracks.isEmpty)
        }
        .frame(maxWidth: .infinity)
    }

    /// The playlist's own image when the server has made one (Jellyfin's,
    /// Navidrome's mosaic), else the covers of its first albums.
    @ViewBuilder
    private func cover(_ shown: Playlist, tracks: [Track], size: CGFloat = 240) -> some View {
        let covers = Self.firstCovers(of: tracks)
        if let artwork = shown.artwork {
            ArtworkView(artwork, size: size, placeholder: "music.note.list")
        } else if covers.isEmpty {
            ArtworkView(nil, size: size, placeholder: "music.note.list")
        } else {
            CollageArtwork(artworks: covers, size: size)
        }
    }

    private func seed(for shown: Playlist, tracks: [Track]) -> StationSeed {
        .collection(id: shown.id, name: shown.name, trackIDs: tracks.map(\.id))
    }

    private func play(_ tracks: [Track], from index: Int, playlist shown: Playlist, shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        player.play(tracks, startingAt: index, context: QueueContext(.playlist(shown.id), title: shown.name),
                    shuffled: shuffled)
    }

    private func load() async {
        loadCount += 1
        let mine = loadCount
        let saved = offline.collection(for: .playlist(playlist.id))?.tracks
        // Offline, the songs it was downloaded with, without asking a server
        // that cannot answer.
        if offline.isOffline, let saved {
            entries = Self.makeEntries(from: saved)
            loadError = nil
            return
        }
        do {
            let tracks = try await library.tracks(in: playlist)
            guard mine == loadCount else { return }
            entries = Self.makeEntries(from: tracks)
            loadError = nil
            // Downloaded: what came in or went out on the server follows.
            let shown = library.playlists.first(where: { $0.id == playlist.id }) ?? playlist
            offline.playlistLoaded(shown, tracks: tracks)
        } catch {
            // Leaving the page cancels its load: that is no failure to show.
            guard mine == loadCount, !Task.isCancelled else { return }
            // The server away: the downloaded songs, as offline.
            if entries == nil, let saved {
                entries = Self.makeEntries(from: saved)
                loadError = nil
                return
            }
            // Songs already shown stay; only an empty page says it failed.
            if entries == nil {
                loadError = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Swipe to remove, but not from someone else's playlist.
    private func deleteAction(_ shown: Playlist) -> ((IndexSet) -> Void)? {
        guard !shown.isReadOnly else { return nil }
        return { offsets in remove(at: offsets, from: shown) }
    }

    /// The move handles in Edit, where the server can reorder.
    private func moveAction(_ shown: Playlist) -> ((IndexSet, Int) -> Void)? {
        guard !shown.isReadOnly, library.can(.playlistReorder) else { return nil }
        return { source, destination in move(from: source, to: destination, in: shown) }
    }

    /// Remove from Playlist in a song's menu (wide), as a swipe would.
    private func removeEntry(_ id: String, from shown: Playlist) {
        guard let i = entries?.firstIndex(where: { $0.id == id }) else { return }
        remove(at: IndexSet(integer: i), from: shown)
    }

    /// Gone from the list at once; back from the server if it said no.
    private func remove(at offsets: IndexSet, from shown: Playlist) {
        guard var current = entries else { return }
        let removed = offsets.filter { current.indices.contains($0) }.map { current[$0].track }
        current.remove(atOffsets: offsets)
        entries = current
        // Jellyfin 12.4 removes every place of a song that is in the
        // playlist twice (its entry id is the song's own): then the page
        // shows what the server kept.
        let wasTwice = removed.contains { gone in current.contains { $0.track.id == gone.id } }
        Task {
            do {
                try await library.remove(removed, from: shown)
                if wasTwice { await load() }
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int, in shown: Playlist) {
        guard var current = entries, let from = source.first, current.indices.contains(from) else { return }
        let moved = current[from]
        current.move(fromOffsets: source, toOffset: destination)
        entries = current
        // List's destination counts the row's old place; the server wants
        // the place it ends up in (Jellyfin's, and the kit's for Subsonic).
        guard let newIndex = current.firstIndex(where: { $0.id == moved.id }) else { return }
        Task {
            do {
                try await library.move(moved.track, in: shown, to: newIndex)
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }

    private func deletePlaylist(_ shown: Playlist) {
        Task {
            do {
                try await library.delete(shown)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func makeEntries(from tracks: [Track]) -> [LibraryPlaylistEntry] {
        // A song can be in a playlist twice, and on Jellyfin 12.4 both places
        // carry the song's own id as their entry id: the second is told
        // apart by a count, so the list's ids stay unique.
        var seen: [String: Int] = [:]
        var entries: [LibraryPlaylistEntry] = []
        entries.reserveCapacity(tracks.count)
        for track in tracks {
            let base = track.playlistEntryID ?? track.id
            let earlier = seen[base] ?? 0
            seen[base] = earlier + 1
            entries.append(LibraryPlaylistEntry(id: earlier == 0 ? base : "\(base)#\(earlier)", track: track))
        }
        return entries
    }

    private static func firstCovers(of tracks: [Track]) -> [Artwork] {
        var seen = Set<Artwork>()
        var covers: [Artwork] = []
        for track in tracks {
            guard let artwork = track.artwork, seen.insert(artwork).inserted else { continue }
            covers.append(artwork)
            if covers.count == 4 { break }
        }
        return covers
    }
}

/// One place in a playlist.
private struct LibraryPlaylistEntry: Identifiable {
    let id: String
    let track: Track
}

/// "Add to Playlist…" from any menu: a new playlist with these songs, or one
/// of the listener's; a tap adds and closes.
struct AddToPlaylistSheet: View {
    let tracks: [Track]

    init(tracks: [Track]) {
        self.tracks = tracks
    }

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isWide) private var isWide
    @State private var isNaming = false
    @State private var newName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newName = ""
                        isNaming = true
                    } label: {
                        Label("New Playlist…", systemImage: "plus")
                    }
                }
                if !ownPlaylists.isEmpty {
                    Section("Playlists") {
                        ForEach(ownPlaylists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                LibraryPlaylistRow(playlist: playlist)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isWorking)
            .overlay {
                if isWorking { ProgressView() }
            }
            .alert("New Playlist", isPresented: $isNaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { create() }
            } message: {
                Text("It starts with \(LibraryText.songs(tracks.count)).")
            }
            .libraryErrorAlert("Could Not Add to the Playlist", message: $errorMessage)
        }
        // A Mac's sheet is only as big as its list asks: room for the list.
        .frame(minWidth: isWide ? 400 : nil, minHeight: isWide ? 480 : nil)
        .presentationDetents([.medium, .large])
    }

    /// Only playlists the server lets this user add to.
    private var ownPlaylists: [Playlist] {
        library.playlists.filter { !$0.isReadOnly }
    }

    private func add(to playlist: Playlist) {
        isWorking = true
        Task {
            do {
                try await library.add(tracks, to: playlist)
                Stats.track(.playlistSongsAdded, ["from": "add_to_playlist"])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func create() {
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? String(localized: "New Playlist") : typed
        isWorking = true
        Task {
            do {
                try await library.createPlaylist(named: name, with: tracks)
                Stats.track(.playlistCreated, ["from": "add_to_playlist"])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

extension View {
    /// An OK alert for a change the server refused; `message` nil hides it.
    func libraryErrorAlert(_ title: LocalizedStringKey, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil },
                                          set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
