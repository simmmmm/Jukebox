// The queue, in Now Playing's cover place, as Music's: where it plays from,
// shuffle, repeat and Autoplay, then Up Next — reordered in Edit, a swipe
// to remove one, Clear for all — and the History of what played, dimmed.
// A tap on any song plays it. While a station plays, every song in Up Next
// says why the radio chose it — the one place the radio's reasons are
// shown (docs/design/tells.md, 5) — and there is no shuffle or repeat: the radio
// chooses the order, and keeps choosing as it is listened to. In their place
// a "…" keeps the station as a playlist: a station that played well is gone
// once another starts, and this is how an evening of it stays.

import JukeboxKit
import SwiftUI

struct QueueView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator

    @State private var editMode: EditMode = .inactive
    /// Save as Playlist: the name in the alert's field, the one it started
    /// with, and the songs as they were when it was asked for (the radio
    /// adds more while the alert is open; the alert's count stays true).
    @State private var isNaming = false
    @State private var playlistName = ""
    @State private var suggestedName = ""
    @State private var songsToSave: [Track] = []
    @State private var isSaving = false
    @State private var saved: Playlist?
    @State private var saveError: String?

    init() {}

    var body: some View {
        let upNext = player.upNext
        let history = Array(player.played.reversed())
        let station = player.context?.station

        List {
            Section {
                playingFrom(station)
                    .queueRow()
                if station != nil {
                    // The station's dial, here above the songs it chooses,
                    // which change as it moves. It stood in the volume's
                    // place on Now Playing, swapped in as a station began —
                    // the photographer, 9 November 2026: "Dat is hele
                    // matige ux." The station's name there opens this.
                    RadioDial()
                        .queueRow()
                }
                upNextTitle(isEmpty: upNext.isEmpty)
                    .queueRow()
            }

            Section {
                ForEach(upNext) { entry in
                    row(entry)
                        .queueRow()
                }
                .onMove { source, destination in
                    player.moveUpcoming(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    player.removeUpcoming(atOffsets: offsets)
                }
            }

            if let note = footnote(station: station, isEmpty: upNext.isEmpty) {
                Section {
                    note
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .queueRow()
                }
            }

            if !history.isEmpty {
                Section {
                    ListHeading("History")
                        .padding(.top, Theme.Space.l)
                        .queueRow()
                    ForEach(history) { entry in
                        row(entry)
                            // Played: there, but quieter than what is to come.
                            .opacity(0.5)
                            .queueRow()
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        // The list fades out at its edges rather than being cut off.
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.97),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .onChange(of: upNext.isEmpty) { _, isEmpty in
            // Nothing left to reorder: out of Edit, or its Done would be gone.
            if isEmpty { editMode = .inactive }
        }
        // The confirmation, with the name to change if the listener likes,
        // as a mix's Save as Playlist asks it.
        .alert("Save as Playlist", isPresented: $isNaming) {
            TextField("Playlist Name", text: $playlistName)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            saveMessage
        }
        .alert("Playlist Saved", isPresented: presence($saved), presenting: saved) { playlist in
            Button("Show Playlist") {
                // Closes Now Playing and opens it in the tab underneath.
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
        // Each time the panel opens (Stats).
        .countsScreen("queue")
    }

    // MARK: Rows

    private func playingFrom(_ station: Station?) -> some View {
        HStack(spacing: Theme.Space.m) {
            if let station {
                StationArtwork(station: station, size: 40, cornerRadius: Theme.Radius.artwork)
            }
            // Where it plays from, by its name in the serif: no label over
            // it (tells.md, 4).
            Text(player.context?.title ?? "")
                .font(.serif(.title3))
                .lineLimit(1)
                .accessibilityLabel(Text("Playing from \(player.context?.title ?? "")"))
            Spacer(minLength: 0)
            if let station {
                stationMenu(station)
            } else {
                HStack(spacing: Theme.Space.s) {
                    QueueToggle(symbol: "shuffle", isOn: player.isShuffled, label: "Shuffle") {
                        player.toggleShuffle()
                    }
                    QueueToggle(symbol: player.repeatMode == .one ? "repeat.1" : "repeat",
                                isOn: player.repeatMode != .off, label: "Repeat") {
                        player.cycleRepeat()
                    }
                    .accessibilityValue(repeatValue)
                    // Music's Autoplay: when this ends, a station from its
                    // last song plays on (AppSettings.autoplay).
                    QueueToggle(symbol: "infinity", isOn: settings.autoplay, label: "Autoplay") {
                        settings.autoplay.toggle()
                    }
                }
            }
        }
        .padding(.bottom, Theme.Space.s)
    }

    /// Where shuffle and repeat are for an album: what can be done with the
    /// station's songs as a whole.
    private func stationMenu(_ station: Station) -> some View {
        Menu {
            Button("Save as Playlist…", systemImage: "music.note.list") {
                askToSave(station)
            }
            .disabled(isSaving)
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                let songs = stationSongs()
                guard !songs.isEmpty else { return }
                // Now Playing presents the sheet (NowPlayingView).
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: songs)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 32)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        // Borderless: in a list row, only this answers its tap.
        .buttonStyle(.borderless)
        .accessibilityLabel("More")
    }

    private func upNextTitle(isEmpty: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
            ListHeading("Up next")
            Spacer(minLength: 0)
            if !isEmpty {
                Button("Clear") {
                    editMode = .inactive
                    player.clearUpcoming()
                }
                .buttonStyle(.borderless)
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func row(_ entry: QueueEntry) -> some View {
        TrackRow(entry.track, subtitle: entry.track.artistLine, reason: entry.reason, showsMenu: false)
            .contentShape(.rect)
            .onTapGesture {
                player.skip(to: entry)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Plays this song")
            .accessibilityAction {
                player.skip(to: entry)
            }
    }

    /// Under Up Next: what happens when it runs out. Nothing for a station:
    /// its reasons say enough.
    private func footnote(station: Station?, isEmpty: Bool) -> Text? {
        if station != nil {
            return nil
        }
        if isEmpty {
            return settings.autoplay
                ? Text("Nothing up next. Autoplay plays on with music like this song.")
                : Text("Nothing up next.")
        }
        return settings.autoplay ? Text("Then Autoplay plays on with music like the last song.") : nil
    }

    // MARK: Saving the station

    private func askToSave(_ station: Station) {
        let songs = stationSongs()
        guard !songs.isEmpty else { return }
        songsToSave = songs
        // "Radiohead Radio, 8 Nov 2026": the station of that evening.
        suggestedName = "\(station.title), \(Date().formatted(date: .abbreviated, time: .omitted))"
        playlistName = suggestedName
        isNaming = true
    }

    /// The station as it was heard: what played, what plays and what is up
    /// next, in that order. Each song once (Previous and a tap in History
    /// play one again), and none with a thumbs down: the listener said no
    /// to those, and a playlist kept for the good ones should not hold them.
    private func stationSongs() -> [Track] {
        var entries = player.played
        if let current = player.current { entries.append(current) }
        entries += player.upNext
        var seen: Set<ItemID> = []
        return entries.map(\.track).filter { track in
            !radio.disliked.contains(track.id) && seen.insert(track.id).inserted
        }
    }

    /// One Text: an alert shows its message from a Text, not from a
    /// choice between two.
    private var saveMessage: Text {
        if songsToSave.count == 1 {
            return Text("A playlist with this station’s song, on your \(library.serverKind) server.")
        }
        return Text("A playlist with this station’s \(songsToSave.count) songs, on your \(library.serverKind) server: what played, what plays now and what is up next.")
    }

    private func save() {
        let typed = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? suggestedName : typed
        let tracks = songsToSave
        isSaving = true
        Task {
            do {
                saved = try await library.createPlaylist(named: name, with: tracks)
                Stats.track(.playlistCreated, ["from": "queue"])
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

    private var repeatValue: String {
        switch player.repeatMode {
        case .off: String(localized: "Off")
        case .all: String(localized: "All")
        case .one: String(localized: "One")
        }
    }
}

/// Shuffle, Repeat, Autoplay: a plain glyph, in the accent when on.
private struct QueueToggle: View {
    let symbol: String
    let isOn: Bool
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                // The tint: Now Playing's cover colour.
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 32)
                .contentShape(.rect)
        }
        // Borderless: in a list row, only this button answers its tap.
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private extension View {
    /// A row on Now Playing's backdrop: no ground, no separator, the page's margins.
    func queueRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: Theme.Space.xl, bottom: 6, trailing: Theme.Space.xl))
    }
}
