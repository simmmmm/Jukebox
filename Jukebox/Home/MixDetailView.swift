// A mix Jukebox made up, as Music shows a playlist: its collage, its title
// in the serif under it (not on a scrim over it), its artists and length,
// Play and Shuffle, a station that plays on from it, and its songs. Saved as
// a playlist it stays on the server after today's mixes have made way for
// tomorrow's; downloaded (the bar's arrow) it stays on the phone as it was
// today, in Library › Downloaded.

import JukeboxKit
import SwiftUI

struct MixDetailView: View {
    let mix: Mix

    init(mix: Mix) {
        self.mix = mix
    }

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(OfflineStore.self) private var offline

    @State private var showsTitle = false
    @State private var isConfirmingRemoval = false
    @State private var isNaming = false
    @State private var playlistName = ""
    @State private var isSaving = false
    @State private var saved: Playlist?
    @State private var saveError: String?

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets(top: Theme.Space.l, leading: Theme.margin,
                                          bottom: Theme.Space.l, trailing: Theme.margin))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(Array(mix.tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    guard !player.refusesOffline(track) else { return }
                    player.playMix(mix, from: index)
                } label: {
                    TrackRow.standard(track)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .pageGround()
        // The name in the bar only once the header, which shows it large,
        // has scrolled away, as Music's playlist pages do.
        .navigationTitle(showsTitle ? mix.title : "")
        .navigationBarTitleDisplayMode(.inline)
        // Which kinds of mix are opened (Stats): the kind, never the title.
        .countsOnce { Stats.track(.mixOpened, ["kind": mix.kind.rawValue]) }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 300
        } action: { _, isPast in
            showsTitle = isPast
        }
        .toolbar {
            if offline.offersDownload(for: .mix(mix.id)) {
                ToolbarItem(placement: .topBarTrailing) {
                    OfflineDownloadButton(collection: OfflineCollection(mix: mix), isConfirmingRemoval: $isConfirmingRemoval)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section {
                        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                            player.playNext(mix.tracks)
                        }
                        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                            player.addToQueue(mix.tracks)
                        }
                    }
                    Section {
                        Button("Save as Playlist…", systemImage: "music.note.list") {
                            playlistName = defaultName
                            isNaming = true
                        }
                        .disabled(isSaving)
                        Button("Add to Playlist…", systemImage: "text.badge.plus") {
                            navigator.addToPlaylist = AddToPlaylistRequest(tracks: mix.tracks)
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .disabled(mix.tracks.isEmpty)
            }
        }
        .offlineRemovalDialog($isConfirmingRemoval, for: .mix(mix.id), name: mix.title)
        // The confirmation, with the name to change if the listener likes.
        .alert("Save as Playlist", isPresented: $isNaming) {
            TextField("Playlist Name", text: $playlistName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A playlist with these \(mix.tracks.count) songs, on your Jellyfin server, to keep after today’s mixes change.")
        }
        .alert("Playlist Saved", isPresented: presence($saved), presenting: saved) { playlist in
            Button("Show Playlist") {
                navigator.open(.playlist(playlist))
            }
            Button("OK", role: .cancel) {}
        } message: { playlist in
            Text("“\(playlist.name)” is in your playlists now.")
        }
        .alert("Could Not Save the Playlist", isPresented: presence($saveError), presenting: saveError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Space.s) {
            CollageArtwork(artworks: mix.artwork, size: 240)
                .padding(.bottom, Theme.Space.m)
            Text(mix.title)
                .font(.serif(.title))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(mix.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(HomeText.summary(count: mix.tracks.count, duration: mix.duration))
                .font(.footnote)
                .foregroundStyle(.secondary)
            PlayShuffleButtons(play: { player.playMix(mix) },
                               shuffle: { player.playMix(mix, shuffled: true) })
                .padding(.top, Theme.Space.m)
                .disabled(mix.tracks.isEmpty)
            Button {
                Stats.track(.stationStarted, ["seed": Stats.seed(mix.stationSeed), "from": "menu"])
                radio.start(mix.stationSeed)
            } label: {
                Text("Start Radio")
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Plays on from this mix, for as long as you listen")
        }
        .frame(maxWidth: .infinity)
    }

    /// "Daily Mix 1, 8 Nov 2026": the mix of that day, as it was.
    private var defaultName: String {
        "\(mix.title), \(Date().formatted(date: .abbreviated, time: .omitted))"
    }

    private func save() {
        let typed = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? defaultName : typed
        let tracks = mix.tracks
        isSaving = true
        Task {
            do {
                saved = try await library.createPlaylist(named: name, with: tracks)
                Stats.track(.playlistCreated, ["from": "mix"])
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// An alert's "is it shown" for an optional it presents.
    private func presence<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { isShown in
                if !isShown { value.wrappedValue = nil }
            }
        )
    }
}
