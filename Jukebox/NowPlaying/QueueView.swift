// The queue, in Now Playing's cover place, as Music's: where it plays from,
// shuffle, repeat and Autoplay, then Up Next — reordered in Edit, a swipe
// to remove one, Clear for all — and the History of what played, dimmed.
// A tap on any song plays it. While a station plays, every song in Up Next
// says why the radio chose it — the one place the radio's reasons are
// shown (docs/design/tells.md, 5) — and there is no shuffle or repeat: the radio
// chooses the order, and keeps choosing as it is listened to. In their place
// a "…" keeps the station as a playlist: a station that played well is gone
// once another starts, and this is how an evening of it stays.
//
// In the iPad's and the Mac's panel (`inPanel`) it is Up Next as Linux's
// panel has it (UpNextList, shared): where it plays from at the top (the
// album's cover and title, or the station's mark, name and dial), a
// hairline, the song playing and the ones to come, "Then", and a foot that
// counts them ("6 songs · 27 min"), then the History of what played,
// dimmed, as the iPhone's. Shuffle and repeat are in the bar there.
// A song is dragged to where it goes, or moved and removed from its menu.

import JukeboxKit
import SwiftUI

struct QueueView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator
    @Environment(MixStore.self) private var mixes

    /// The wide layout's panel, rather than Now Playing's cover place.
    private let inPanel: Bool

    // The iPhone's Edit mode, for reordering and removing. A Mac's list
    // has none: there a song is dragged to where it goes.
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
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
    /// Songs to come picked with ⌘ or ⇧ in the panel (TrackPicks), as on a
    /// page, for the menu on all of them. By place: they go when the list
    /// changes.
    @State private var panelPicks = TrackPicks()

    init(inPanel: Bool = false) {
        self.inPanel = inPanel
    }

    var body: some View {
        Group {
            if inPanel {
                panelList
            } else {
                phoneList
            }
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

    @ViewBuilder private var phoneList: some View {
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
                        .contextMenu {
                            upNextMenu(entry).menuIcons()
                        }
                        .modifier(RemoveSwipe { remove(entry) })
                        .queueRow(song: true)
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
                            .queueRow(song: true)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        // The list fades out at its edges rather than being cut off.
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.97),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        #if os(iOS)
        .onChange(of: upNext.isEmpty) { _, isEmpty in
            // Nothing left to reorder: out of Edit, or its Done would be gone.
            if isEmpty { editMode = .inactive }
        }
        #endif
    }

    // MARK: The panel

    /// Up Next as the wide layout's panel shows it, from UpNextList, as
    /// Linux's panel does.
    private var panelList: some View {
        // The songs queued from elsewhere come under "Then", as on Linux:
        // one queue (PlayQueue) keeps which ones they are on both.
        let items = UpNextList.items(current: player.current, upNext: player.upNext, context: player.context,
                                     currentIndex: player.currentIndex, added: player.addedIDs,
                                     autoplay: settings.autoplay, repeatMode: player.repeatMode,
                                     played: player.played)
        let head = UpNextList.head(player.context, playing: player.currentTrack, library: library, mixes: mixes)
        // The head above the list, not a row of it, as Linux's panel has
        // it: a row, the Mac's list lit it edge to edge under the pointer
        // ("er zit hier een rare hover op in mac", the photographer, 24
        // November 2026).
        return VStack(spacing: 0) {
            if let head {
                panelHead(head)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.l)
                    .overlay(alignment: .bottom) {
                        Hairline(inset: 0)
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.bottom, Theme.Space.m)
            }
            panelSongs(items)
        }
    }

    private func panelSongs(_ items: [UpNextList.Item]) -> some View {
        List {
            ForEach(Array(items.enumerated()), id: \.element.panelKey) { i, item in
                panelItem(item, at: i, in: items)
                    .moveDisabled(!item.isUpcoming)
                    .deleteDisabled(!item.isUpcoming)
            }
            // The list's places count the playing row and the words too;
            // the queue's count only the songs to come.
            .onMove { source, destination in
                let offsets = IndexSet(source.compactMap { upNextOffset(items[$0]) })
                let target = items[..<destination].filter(\.isUpcoming).count
                player.moveUpcoming(fromOffsets: offsets, toOffset: target)
            }
            .onDelete { places in
                player.removeUpcoming(atOffsets: IndexSet(places.compactMap { upNextOffset(items[$0]) }))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .onChange(of: items.map(\.panelKey)) { panelPicks.clear() }
    }

    /// Where it plays from: an album's, a playlist's or a mix's cover and
    /// title with its artist; or a station's mark (the one lit arch a
    /// screen is the hero's, so here it is flat), its name and its dial.
    /// An album's head: its title sleeve when it has no cover, as Linux's.
    private var albumSleeve: TitleSleeve.Words? {
        guard case let .album(id)? = player.context?.kind, let album = library.album(id: id) else { return nil }
        return TitleSleeve.Words(album: album)
    }

    @ViewBuilder private func panelHead(_ head: UpNextList.Head) -> some View {
        switch head {
        case let .collection(title, line, cover, collage):
            HStack(spacing: Theme.Space.m) {
                if let collage {
                    CollageArtwork(artworks: collage, size: 48)
                } else {
                    ArtworkView(cover, size: 48, sleeve: albumSleeve)
                }
                // Linux's panel-head: the serif, 20; the line 13.
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .desktopFont(Tokens.Size.panelHead.size, design: .serif)
                        .lineLimit(1)
                    if !line.isEmpty {
                        Text(line)
                            .desktopFont(Tokens.Size.fact13.size)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Playing from \(title)"))
        case let .station(station):
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.m) {
                    ArchMark(size: 24, style: .template)
                        .foregroundStyle(Theme.accent)
                    Text(station.title)
                        .desktopFont(Tokens.Size.panelHead.size, design: .serif)
                        .lineLimit(1)
                        .accessibilityLabel(Text("Playing from \(station.title)"))
                    Spacer(minLength: 0)
                    stationMenu(station)
                }
                .frame(minHeight: 48)
                // The dial, above the songs it chooses.
                RadioDial()
            }
        }
    }

    @ViewBuilder private func panelItem(_ item: UpNextList.Item, at i: Int, in items: [UpNextList.Item]) -> some View {
        switch item {
        case let .song(entry, number, style, playing, words):
            QueuePanelRow(entry: entry, number: number, style: style, playing: playing, words: words)
                .contentShape(.rect)
                // Picked: lit as a page's picked rows (TrackRow), never the
                // accent, which means on air.
                .background {
                    RoundedRectangle(cornerRadius: Theme.Space.s)
                        .fill(Color.primary.opacity(item.isUpcoming && panelPicks.contains(i) ? 0.1 : 0))
                        .padding(.horizontal, -Theme.Space.s)
                }
                // The iPad's list swipes as the iPhone's; on a Mac a
                // trackpad's two fingers do.
                .modifier(RemoveSwipe(isOn: !playing && style != .played) { remove(entry) })
                .onTapGesture {
                    // ⌘ or ⇧ picks a song to come, as on a page (heldPick:
                    // the Mac's keys); a plain tap forgets the picks.
                    if let kind = heldPick() {
                        if item.isUpcoming { panelPicks.click(i, kind) }
                        return
                    }
                    if item.isUpcoming { panelPicks.plain(i) } else { panelPicks.clear() }
                    #if !os(macOS)
                    if !playing { player.skip(to: entry) }
                    #endif
                }
                #if os(macOS)
                // On a Mac a double-click plays, as on Linux: "ik zou liever
                // zelfs dubbelklik hebben zodat je niet perongeluk je nummer
                // uit zet" (the photographer, 24 November 2026). Beside the
                // click rather than before it, so a click picks at once,
                // while ⌘ or ⇧ is still held. The iPad's tap plays.
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    if !playing { player.skip(to: entry) }
                })
                #endif
                .contextMenu {
                    panelMenu(entry, playing: playing, picked: pickedEntries(at: i, in: items)).menuIcons()
                }
                // Played: there, but quieter than what is to come.
                .opacity(style == .played ? 0.5 : 1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(playing ? [] : .isButton)
                .accessibilityHint(playing ? "" : "Plays this song")
                // VoiceOver's activate, as a tap: the gesture alone is not one.
                .accessibilityAction {
                    if !playing { player.skip(to: entry) }
                }
                .panelRow()
        case .then:
            panelWords("Then")
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xs)
                .panelRow()
        case .history:
            panelWords("History")
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xs)
                .accessibilityAddTraits(.isHeader)
                .panelRow()
        case let .note(text):
            panelWords(text)
                .panelRow()
        case let .foot(text):
            panelWords(text)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.l)
                .panelRow()
        }
    }

    /// "Then", Autoplay's note, the foot: a fact, small and quiet.
    private func panelWords(_ text: String) -> some View {
        Text(text)
            .desktopFont(Tokens.Size.fact13.size)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A song's menu: moved or taken out for the ones to come (a Mac's list
    /// has no Edit), then what every song has. Found by id when chosen: the
    /// list may have moved since.
    @ViewBuilder private func panelMenu(_ entry: QueueEntry, playing: Bool, picked: [QueueEntry]) -> some View {
        if picked.count > 1 {
            // Several: what the queue does with them all, as with one, then
            // what every song has (TrackMenu for several). On a station,
            // taking them out teaches it once a song (PlayQueue.removeUpcoming).
            let ids = Set(picked.map(\.id))
            TrackMenu(track: entry.track, picked: picked.map(\.track), pickedPlace: PickedPlace(
                moveToTop: { player.moveUpcoming(fromOffsets: upNextOffsets(ids), toOffset: 0) },
                moveToBottom: { player.moveUpcoming(fromOffsets: upNextOffsets(ids), toOffset: player.upNext.count) },
                remove: { player.removeUpcoming(atOffsets: upNextOffsets(ids)) },
                removeWord: "Remove from Queue"))
        } else {
            singlePanelMenu(entry, playing: playing)
        }
    }

    /// The songs to come picked with the row at `i`, two or more; else none.
    private func pickedEntries(at i: Int, in items: [UpNextList.Item]) -> [QueueEntry] {
        guard items[i].isUpcoming, panelPicks.contains(i) else { return [] }
        return panelPicks.tracks(at: i, in: items).compactMap { item -> QueueEntry? in
            guard item.isUpcoming, case let .song(entry, _, _, _, _) = item else { return nil }
            return entry
        }
    }

    /// Found by id when chosen: the list may have moved since.
    private func upNextOffsets(_ ids: Set<UUID>) -> IndexSet {
        IndexSet(player.upNext.indices.filter { ids.contains(player.upNext[$0].id) })
    }

    @ViewBuilder private func singlePanelMenu(_ entry: QueueEntry, playing: Bool) -> some View {
        if !playing, let at = player.upNext.firstIndex(where: { $0.id == entry.id }) {
            Section {
                Button("Move Up", systemImage: "arrow.up") {
                    move(entry, by: -1)
                }
                .disabled(at == 0)
                Button("Move Down", systemImage: "arrow.down") {
                    move(entry, by: 1)
                }
                .disabled(at == player.upNext.count - 1)
                Button("Remove from Queue", systemImage: "minus.circle", role: .destructive) {
                    remove(entry)
                }
                stationItems(entry)
            }
        }
        TrackMenu(track: entry.track)
    }

    /// The iPhone's long press on a song of Up Next: taken out, and on a
    /// station what else the station should know, then what every song has.
    @ViewBuilder private func upNextMenu(_ entry: QueueEntry) -> some View {
        Section {
            Button("Remove from Queue", systemImage: "minus.circle", role: .destructive) {
                remove(entry)
            }
            stationItems(entry)
        }
        TrackMenu(track: entry.track)
    }

    /// A song the station chose, before it plays: as Spotify's and
    /// Pandora's stations have it, "not this artist here" and "never this
    /// song". Taking it out is already a lesson for the station
    /// (PlayQueue.removeUpcoming); these say more.
    @ViewBuilder private func stationItems(_ entry: QueueEntry) -> some View {
        if entry.reason != nil, player.context?.station != nil {
            if let artist = entry.track.artists.first?.name ?? entry.track.primaryArtist?.name {
                Button("Don’t Play \(artist) Here", systemImage: "person.crop.circle.badge.xmark") {
                    radio.removeArtistFromStation(of: entry.track)
                }
            }
            Button("Dislike", systemImage: "hand.thumbsdown") {
                radio.dislike(entry.track)
            }
        }
    }

    /// Found by id: the list may have moved since the row was drawn.
    private func remove(_ entry: QueueEntry) {
        if let at = upNextOffset(entry) { player.removeUpcoming(atOffsets: [at]) }
    }

    private func move(_ entry: QueueEntry, by step: Int) {
        guard let at = upNextOffset(entry), player.upNext.indices.contains(at + step) else { return }
        // Before the place it goes: one past the next song to go down.
        player.moveUpcoming(fromOffsets: [at], toOffset: step > 0 ? at + 2 : at - 1)
    }

    private func upNextOffset(_ entry: QueueEntry) -> Int? {
        player.upNext.firstIndex { $0.id == entry.id }
    }

    private func upNextOffset(_ item: UpNextList.Item) -> Int? {
        guard case let .song(entry, _, _, playing, _) = item, !playing else { return nil }
        return upNextOffset(entry)
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
            .menuIcons()
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                let songs = stationSongs()
                guard !songs.isEmpty else { return }
                // Now Playing presents the sheet (NowPlayingView).
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: songs)
            }
            .menuIcons()
        } label: {
            Image(systemName: "ellipsis")
                .desktopFont(Tokens.Size.body15.size, weight: .semibold, phone: .body.weight(.semibold), wide: inPanel)
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
                    #if os(iOS)
                    editMode = .inactive
                    #endif
                    player.clearUpcoming()
                }
                .buttonStyle(.borderless)
                #if os(iOS)
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .buttonStyle(.borderless)
                #endif
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func row(_ entry: QueueEntry) -> some View {
        TrackRow(entry.track, subtitle: entry.track.artistLine, reason: entry.reason, showsMenu: false)
            .contentShape(.rect)
            // A double-click plays on a Mac, as in the panel; a tap on the
            // iPhone and the iPad.
            #if os(macOS)
            .onTapGesture(count: 2) {
                player.skip(to: entry)
            }
            #else
            .onTapGesture {
                player.skip(to: entry)
            }
            #endif
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
    /// A row on Now Playing's backdrop: no ground, no separator, the page's
    /// margins. A song's row (`song`) is as tall as TrackRow makes it, 60
    /// (Tokens.Row), with nothing above and under it, as in every song list.
    func queueRow(song: Bool = false) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: song ? 0 : 6, leading: Theme.Space.xl,
                                      bottom: song ? 0 : 6, trailing: Theme.Space.xl))
    }

    /// A row of the panel: on its ground, no separator, 16 from its sides;
    /// its height its own (Linux's measures: 48, 64 with a cover, 72 on a
    /// station).
    func panelRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.l, bottom: 0, trailing: Theme.Space.l))
    }
}

private extension UpNextList.Item {
    /// Its place in the list: a song by its entry, the words by what they are.
    var panelKey: String {
        switch self {
        case let .song(entry, _, _, _, _): entry.id.uuidString
        case .then: "then"
        case .history: "history"
        case .note: "note"
        case .foot: "foot"
        }
    }

    /// A song still to come: what can be moved and taken out.
    var isUpcoming: Bool {
        if case let .song(_, _, style, playing, _) = self { return !playing && style != .played }
        return false
    }
}

/// A song of the panel's Up Next, as Linux's: numbered (an album or a
/// playlist; its guests after the title), with its cover (songs queued from
/// elsewhere), or with its cover and the radio's reason (a station). The
/// playing one has the bars for its number and its title in the accent: the
/// only accent row.
private struct QueuePanelRow: View {
    let entry: QueueEntry
    let number: Int?
    let style: UpNextList.Style
    let playing: Bool
    let words: String

    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let track = entry.track
        HStack(spacing: Theme.Space.m) {
            if style == .numbered {
                Group {
                    if playing {
                        bars
                    } else {
                        Text(number.map(String.init) ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                // Linux's queue row: the number and the title 15, the rest 13.
                .desktopFont(Tokens.Size.body15.size)
                .frame(width: 24, alignment: .trailing)
            } else {
                ArtworkView(track.artwork, size: 48, sleeve: TitleSleeve.Words(track: track))
            }

            VStack(alignment: .leading, spacing: 0) {
                if style == .numbered {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        title(track)
                        if !words.isEmpty {
                            fact(words)
                        }
                    }
                } else {
                    title(track)
                    fact(words)
                    if style == .station, let reason = entry.reason {
                        // Why the radio chose it: here and nowhere else.
                        // Linux's faint, 40 %.
                        Text(reasonText(reason))
                            .desktopFont(Tokens.Size.fact13.size)
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)

            if playing && style == .station {
                bars
            } else {
                Text(track.duration.clock)
                    .desktopFont(Tokens.Size.fact13.size)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: style == .numbered ? 48 : style == .station ? 72 : 64)
    }

    private func title(_ track: Track) -> some View {
        Text(track.name)
            .desktopFont(Tokens.Size.body15.size)
            .foregroundStyle(playing ? Theme.accent : Color.primary)
            .lineLimit(1)
    }

    private func fact(_ text: String) -> some View {
        Text(text)
            .desktopFont(Tokens.Size.fact13.size)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The playing song's mark, as its row on an album's page has it.
    private var bars: some View {
        Image(systemName: "waveform")
            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Playing")
    }

    /// The kit's words, but for the server's own mix (TrackRow's rule).
    private func reasonText(_ reason: PickReason) -> String {
        if case .instantMix = reason {
            return String(localized: "From \(library.serverKind)’s mix")
        }
        return reason.text
    }
}

/// A song of Up Next swiped out, all the way across, from either side:
/// Music's queue takes a song out to the left (the trailing edge), and the
/// photographer reaches for the right ("nummers naar rechts kunt slepen om
/// ze er uit te halen", 20 November 2026), so both do it. Declared on both
/// edges: a row with swipe actions of its own no longer gets the swipe
/// `onDelete` gives, which Edit keeps.
private struct RemoveSwipe: ViewModifier {
    var isOn = true
    let remove: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if isOn { button }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if isOn { button }
            }
    }

    private var button: some View {
        Button(role: .destructive, action: remove) {
            Label("Remove", systemImage: "minus.circle")
        }
    }
}
