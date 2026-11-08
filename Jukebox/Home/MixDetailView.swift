// A mix Jukebox made up, as Music shows a playlist: its collage with the
// title set on it, what it is, Play and Shuffle, a station that plays on
// from it, and its songs. Saved as a playlist it stays on the server after
// today's mixes have made way for tomorrow's.

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

    @State private var showsTitle = false
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

            ForEach(Array(mix.tracks.enumerated()), id: \.offset) { index, track in
                Button {
                    player.playMix(mix, from: index)
                } label: {
                    TrackRow.standard(track)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        // The name in the bar only once the header, which shows it large,
        // has scrolled away, as Music's playlist pages do.
        .navigationTitle(showsTitle ? mix.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 300
        } action: { _, isPast in
            showsTitle = isPast
        }
        .toolbar {
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
            CollageArtwork(artworks: mix.artwork, size: 240, cornerRadius: Theme.Radius.card)
                .overlay(alignment: .bottomLeading) {
                    // The title on the collage, as the mix's card on Home has it.
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                        Text(mix.title)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(Theme.Space.l)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                }
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .padding(.bottom, Theme.Space.m)
            Text(mix.subtitle)
                .font(.title3)
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
                radio.start(mix.stationSeed)
            } label: {
                Label("Start Radio", systemImage: "dot.radiowaves.left.and.right")
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
