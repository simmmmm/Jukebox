// The queue, in Now Playing's cover place, as Music's: where it plays from,
// shuffle, repeat and Autoplay, then Up Next — reordered in Edit, a swipe
// to remove one, Clear for all — and the History of what played, dimmed.
// A tap on any song plays it. While a station plays, every song in Up Next
// says why the radio chose it, and there is no shuffle or repeat: the radio
// chooses the order, and keeps choosing as it is listened to.

import JukeboxKit
import SwiftUI

struct QueueView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppSettings.self) private var settings

    @State private var editMode: EditMode = .inactive

    var body: some View {
        let upNext = player.upNext
        let history = Array(player.played.reversed())
        let station = player.context?.station

        List {
            Section {
                playingFrom(station)
                    .queueRow()
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
                    Text("History")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
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
    }

    // MARK: Rows

    private func playingFrom(_ station: Station?) -> some View {
        HStack(spacing: Theme.Space.m) {
            if let station {
                StationArtwork(station: station, size: 40, cornerRadius: Theme.Radius.thumbnail)
            }
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Playing From")
                Text(player.context?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if station == nil {
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

    private func upNextTitle(isEmpty: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
            Text("Up Next")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
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

    /// Under Up Next: what happens when it runs out.
    private func footnote(station: Station?, isEmpty: Bool) -> Text? {
        if station != nil {
            return Text("The radio keeps choosing as you listen")
        }
        if isEmpty {
            return settings.autoplay
                ? Text("Nothing up next. Autoplay plays on with music like this song.")
                : Text("Nothing up next.")
        }
        return settings.autoplay ? Text("Then Autoplay plays on with music like the last song.") : nil
    }

    private var repeatValue: String {
        switch player.repeatMode {
        case .off: String(localized: "Off")
        case .all: String(localized: "All")
        case .one: String(localized: "One")
        }
    }
}

/// Shuffle, Repeat, Autoplay: a glyph on a faint tile, brighter when on.
private struct QueueToggle: View {
    let symbol: String
    let isOn: Bool
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 32)
                .background(Color.white.opacity(isOn ? 0.24 : 0.08), in: .rect(cornerRadius: Theme.Radius.thumbnail))
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
