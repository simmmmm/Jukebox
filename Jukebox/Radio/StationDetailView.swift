// A station's own page, as Music shows a playlist: its arch, what it is,
// Play, and the songs it would start with, so the listener sees what the
// radio made of it before anything plays. The photographer, 8 November
// 2026: "Als je nu klikt op een tegel van radio begint er meteen van alles
// te spelen ipv dat je kan zien wat je van de playlist gemaakt hebt." So a
// station's tile opens this page; its long press, and the explicit Play
// buttons on Home and Radio, still play at once.
//
// Play plays exactly the list shown, song for song: the radio keeps the
// session that chose it (RadioController.preview, start(_:preview:from:)).
// New Picks draws another list as near the station; the dial chooses again
// from nearer home or further out. Once the station is on the air the page
// shows what plays and what the radio has queued, which a skip or a thumbs
// changes as it is listened to.

import JukeboxKit
import SwiftUI

struct StationDetailView: View {
    let station: Station

    init(station: Station) {
        self.station = station
    }

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The songs the station would start with; nil until they are chosen
    /// (and while it is on the air, when the player's queue is shown).
    @State private var picks: [RadioPick]?
    /// What `picks` were chosen for.
    @State private var chosenFor: StationPreviewKey?
    /// The draw New Picks made on this page; until then the station's own
    /// (RadioController.pageSeed), the same each time its page opens while
    /// the app runs. So a list chosen again because the library or the
    /// graph moved stays much as it was, and going back and opening the
    /// station again shows the list seen before, not another.
    @State private var randomSeed: UInt64?
    /// New Picks is choosing: the list dims until the new one is there.
    @State private var isDrawing = false
    /// A drag of the dial sends every step; the list waits for it to rest.
    @State private var isDragging = false
    @State private var showsTitle = false
    // Save as Playlist, as a mix's and the queue's.
    @State private var isNaming = false
    @State private var playlistName = ""
    @State private var suggestedName = ""
    @State private var songsToSave: [Track] = []
    @State private var isSaving = false
    @State private var saved: Playlist?
    @State private var saveError: String?

    var body: some View {
        let onAir = isOnAir
        List {
            header(onAir: onAir)
                .listRowInsets(EdgeInsets(top: Theme.Space.l, leading: Theme.margin,
                                          bottom: Theme.Space.l, trailing: Theme.margin))
                .listRowSeparator(.hidden)
            if onAir {
                onAirRows
            } else {
                previewRows
            }
        }
        .listStyle(.plain)
        // The name in the bar only once the header, which shows it large,
        // has scrolled away, as Music's playlist pages do.
        .navigationTitle(showsTitle ? station.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 300
        } action: { _, isPast in
            showsTitle = isPast
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Save as Playlist…", systemImage: "music.note.list") {
                        askToSave()
                    }
                    .disabled(isSaving)
                    Button("Add to Playlist…", systemImage: "text.badge.plus") {
                        let songs = shownSongs
                        guard !songs.isEmpty else { return }
                        navigator.addToPlaylist = AddToPlaylistRequest(tracks: songs)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .disabled(shownSongs.isEmpty)
            }
        }
        .task(id: previewKey) {
            await choose(previewKey)
        }
        // The confirmation, with the name to change if the listener likes.
        .alert("Save as Playlist", isPresented: $isNaming) {
            TextField("Playlist Name", text: $playlistName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A playlist with these \(songsToSave.count) songs, on your Jellyfin server, to keep after the station has moved on.")
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

    // MARK: The header

    private func header(onAir: Bool) -> some View {
        VStack(spacing: Theme.Space.s) {
            StationArtwork(station: station, size: 240, cornerRadius: Theme.Radius.card)
                .overlay(alignment: .topTrailing) {
                    if onAir {
                        StationOnAirBadge()
                            .padding(Theme.Space.m)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .padding(.bottom, Theme.Space.m)
            Text(station.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = station.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Plays on for as long as you listen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            // As wide as on an iPhone on the iPad too: a dial across a
            // whole iPad held sideways is a long way from one end to the other.
            VStack(spacing: Theme.Space.s) {
                buttons(onAir: onAir)
                    .padding(.top, Theme.Space.m)
                dial
                    .padding(.top, Theme.Space.s)
            }
            .frame(maxWidth: Self.controlsWidth)
        }
        .frame(maxWidth: .infinity)
    }

    private static let controlsWidth: CGFloat = 480

    /// The page's one filled button, Play, and New Picks beside it; on the
    /// air, Play or Pause, and Stop.
    @ViewBuilder
    private func buttons(onAir: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            if onAir {
                Button {
                    // Its first songs are being chosen (it was started from
                    // somewhere else): nothing to pause yet.
                    guard !radio.isStarting else { return }
                    player.togglePlayPause()
                } label: {
                    if radio.isStarting {
                        ProgressView()
                            .tint(Theme.onAccent)
                            .accessibilityLabel("Starting")
                    } else if player.isPlaying {
                        Label("Pause", systemImage: "pause.fill")
                    } else {
                        Label("Play", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.prominent)
                Button {
                    // The station first, so the song that stops is not taken
                    // as a skip; then the music. As the Radio tab's card does.
                    radio.stop()
                    player.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.secondary)
            } else {
                Button {
                    play(from: 0)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.prominent)
                // Nothing in the library fits the station: nothing to play.
                .disabled(picks?.isEmpty == true)
                .accessibilityHint("Plays these songs, then more like them")
                Button {
                    newPicks()
                } label: {
                    Label("New Picks", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
                .disabled(picks?.isEmpty != false || isDrawing)
                .accessibilityHint("Chooses other songs for this station")
            }
        }
    }

    /// Familiar ⟷ Adventurous, as on the Radio tab's card: the radio's one
    /// dial (AppSettings.adventurousness), so it is where it was left for
    /// every station. Let go, the list is chosen again; a station on the
    /// air chooses its songs ahead again (as Settings' dial does, whichever
    /// station that is).
    @ViewBuilder
    private var dial: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // The dial's words in the accent, as on the Radio tab's card.
            Text(RadioDial.phrase(settings.adventurousness))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: RadioDial.phrase(settings.adventurousness))
                .accessibilityHidden(true)
            Slider(value: $settings.adventurousness, in: 0...1, onEditingChanged: { editing in
                isDragging = editing
                if !editing { radio.adventurousnessChanged() }
            })
            .tint(Theme.accent)
            .accessibilityLabel("Adventurousness")
            .accessibilityValue(RadioDial.spoken(settings.adventurousness))
            HStack {
                Text("Familiar")
                Spacer()
                Text("Adventurous")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .onChange(of: settings.adventurousness) { _, _ in
            // Steps without a drag (VoiceOver's swipes, another dial).
            if !isDragging { radio.adventurousnessChanged() }
        }
    }

    // MARK: The songs

    /// What the station would play, before it plays.
    @ViewBuilder
    private var previewRows: some View {
        if let picks, picks.isEmpty {
            ContentUnavailableView {
                Label("Nothing to Play", systemImage: "dot.radiowaves.left.and.right")
            } description: {
                Text("Nothing in your library fits this station yet.")
            }
            .listRowSeparator(.hidden)
        } else {
            Eyebrow("Up First")
                .padding(.top, Theme.Space.s)
                .listRowSeparator(.hidden)
            if let picks {
                // By place, not by song: a library of a few songs repeats
                // them, and the list would have the same song twice.
                ForEach(Array(picks.enumerated()), id: \.offset) { index, pick in
                    Button {
                        play(from: index)
                    } label: {
                        TrackRow(pick.track, subtitle: pick.track.artistLine, reason: pick.reason)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays the station from this song")
                }
                .opacity(isDrawing ? 0.4 : 1)
            } else {
                StationPlaceholderRows()
            }
            footer
        }
    }

    /// The station on the air: the song playing, then what the radio has
    /// queued after it.
    @ViewBuilder
    private var onAirRows: some View {
        if radio.isStarting {
            Eyebrow("Up First")
                .padding(.top, Theme.Space.s)
                .listRowSeparator(.hidden)
            StationPlaceholderRows()
        } else {
            if let current = player.current {
                Eyebrow("Now Playing")
                    .padding(.top, Theme.Space.s)
                    .listRowSeparator(.hidden)
                Button {
                    navigator.isNowPlayingPresented = true
                } label: {
                    TrackRow(current.track, subtitle: current.track.artistLine, reason: current.reason)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows Now Playing")
            }
            let upNext = player.upNext
            if !upNext.isEmpty {
                Eyebrow("Up Next")
                    .padding(.top, Theme.Space.l)
                    .listRowSeparator(.hidden)
                ForEach(upNext) { entry in
                    Button {
                        player.skip(to: entry)
                    } label: {
                        TrackRow(entry.track, subtitle: entry.track.artistLine, reason: entry.reason)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays this song")
                }
            }
            footer
        }
    }

    private var footer: some View {
        Text("The radio keeps choosing as you listen: a skip or a thumbs changes what comes next.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Theme.Space.s)
            .listRowSeparator(.hidden)
    }

    // MARK: Choosing

    private var previewKey: StationPreviewKey {
        StationPreviewKey(randomSeed: randomSeed ?? radio.pageSeed(for: station),
                          inputs: radio.previewInputs,
                          dial: isDragging ? nil : settings.adventurousness,
                          playing: player.currentTrack?.id, isOnAir: isOnAir)
    }

    /// By id: the station the page was opened with and the one on the air
    /// can differ in their covers (one built by the mixes, one by the radio).
    private var isOnAir: Bool {
        radio.stationOnAir(player: player)?.id == station.id
    }

    private func choose(_ key: StationPreviewKey) async {
        if key.isOnAir {
            // What played is the player's now; off the air again, the page
            // chooses afresh, with what was just heard left out.
            picks = nil
            chosenFor = nil
            isDrawing = false
            return
        }
        // The dial is being dragged: the list waits for it to rest.
        guard key.dial != nil else { return }
        if chosenFor == key, let picks, radio.isPreviewCurrent(station, picks) { return }
        if let chosenFor, chosenFor != key, chosenFor.randomSeed == key.randomSeed {
            // The library, the graph, the dial or the song playing moved:
            // a moment's wait, so a dial moved step by step, or a snapshot
            // and the graph after it, choose once.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        let chosen = await radio.preview(station, randomSeed: key.randomSeed)
        // A newer key chooses its own list.
        if Task.isCancelled { return }
        withAnimation(reduceMotion ? nil : .default) {
            picks = chosen
            isDrawing = false
        }
        chosenFor = key
    }

    private func newPicks() {
        isDrawing = true
        // The station's draw from now on, so its page opened again shows
        // these new picks.
        randomSeed = radio.drawPageSeed(for: station)
    }

    /// From the song tapped (or the first): the list as shown, kept by the
    /// radio. Not chosen yet, the station starts as from anywhere else.
    private func play(from index: Int) {
        if let picks, !picks.isEmpty {
            radio.start(station, preview: picks, from: index)
        } else {
            radio.start(station)
        }
    }

    // MARK: Saving

    /// The songs on the page: the list, or on the air the song playing and
    /// what is queued. Each once, and none with a thumbs down, as the
    /// queue's Save as Playlist keeps them.
    private var shownSongs: [Track] {
        let tracks: [Track]
        if isOnAir {
            tracks = ([player.current].compactMap { $0 } + player.upNext).map(\.track)
        } else {
            tracks = (picks ?? []).map(\.track)
        }
        var seen: Set<ItemID> = []
        return tracks.filter { !radio.disliked.contains($0.id) && seen.insert($0.id).inserted }
    }

    private func askToSave() {
        let songs = shownSongs
        guard !songs.isEmpty else { return }
        songsToSave = songs
        // "Radiohead Radio, 8 Nov 2026": the station as it was that day.
        suggestedName = "\(station.title), \(Date().formatted(date: .abbreviated, time: .omitted))"
        playlistName = suggestedName
        isNaming = true
    }

    private func save() {
        let typed = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? suggestedName : typed
        let tracks = songsToSave
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

/// What a station's page chose its list for: when it moves, the list is
/// chosen again. A plain value, off the main actor, as `.task(id:)` takes it.
nonisolated private struct StationPreviewKey: Hashable, Sendable {
    let randomSeed: UInt64
    /// RadioController.previewInputs: the library's snapshot, the graph.
    let inputs: Int
    /// The dial; nil while it is dragged.
    let dial: Double?
    /// The song playing, which the list leaves out. The next one could be
    /// further down the list, and Play would then start the station afresh
    /// rather than play what is shown (RadioController.start(_:preview:from:)):
    /// so the list is chosen again. Not left to the library: a skip does not
    /// move it, and a song heard to the end only half a minute later.
    let playing: ItemID?
    let isOnAir: Bool
}

/// Grey rows where the songs will be, while they are chosen, so the page
/// does not jump when they come.
private struct StationPlaceholderRows: View {
    var body: some View {
        ForEach(0..<6, id: \.self) { _ in
            HStack(spacing: Theme.Space.m) {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                    .fill(.quaternary)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A song of the station")
                    Text("Its artist")
                        .font(.subheadline)
                    Text("Why the radio chose it")
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
        .listRowSeparator(.hidden)
    }
}
