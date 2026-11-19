// Don't Count Plays and Private Listening on the iPhone, the iPad and the
// Mac (NotCountedStore, Linux's the same in Linux/App/NotCounted.swift).
// "kun je het ook mogelijk maken om nummers/albums/playlists niet te
// scrobblen? of mee te laten tellen voor die stats bijv voor kerstmuziek
// oid?", and "een soort prive modus overall" (19 November 2026). In the
// menus that were there, a line in Settings, and one quiet sign while
// Private Listening is on, so nobody forgets it.

import SwiftUI
import JukeboxKit

/// A song's, an album's or a playlist's menu item, ticked while marked.
struct DontCountToggle: View {
    let kind: NotCounted.Kind
    let id: ItemID
    let name: String

    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let store = player.notCounted
        Toggle(isOn: Binding(get: { store.isMarked(kind, id) },
                             set: { store.set(kind, id: id, name: name, counted: !$0) })) {
            Label("Don't Count Plays", systemImage: "eye.slash")
        }
    }
}

/// Off, On, Until Jukebox Restarts, the one chosen ticked.
struct PrivateListeningPicker: View {
    let store: NotCountedStore

    var body: some View {
        Picker(selection: Binding(get: { store.privateListening }, set: { store.privateListening = $0 })) {
            Text("Off").tag(PrivateListening.off)
            Text("On").tag(PrivateListening.on)
            Text("Until Jukebox Restarts").tag(PrivateListening.untilRestart)
        } label: {
            Label("Private Listening", systemImage: "eye.slash")
        }
    }
}

/// Private Listening as a submenu: the iPad's ≡ menu, the Mac's Controls.
struct PrivateListeningMenu: View {
    let store: NotCountedStore

    var body: some View {
        Menu {
            PrivateListeningPicker(store: store)
                .pickerStyle(.inline)
        } label: {
            Label("Private Listening", systemImage: "eye.slash")
        }
    }
}

/// Settings' section: Private Listening, then what is marked, each with
/// Count Again.
struct NotCountedSection: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let store = player.notCounted
        Section {
            PrivateListeningPicker(store: store)
            ForEach(store.marks.items, id: \.key) { item in
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(item.name)
                            .lineLimit(1)
                        Text(Self.kindName(item.kind))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Count Again") {
                        store.set(item.kind, id: item.id, name: item.name, counted: true)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }
            }
        } header: {
            Text("Not Counted")
        } footer: {
            Text("Plays without a count: your server is not told, so no play count and no scrobble, and Jukebox does not learn from them for the radio, the mixes or Your Year. Mark a song, an album or a playlist with Don't Count Plays in its menu.")
        }
    }

    static func kindName(_ kind: NotCounted.Kind) -> String {
        switch kind {
        case .song: String(localized: "Song")
        case .album: String(localized: "Album")
        case .playlist: String(localized: "Playlist")
        }
    }
}

/// The quiet sign while Private Listening is on: in the wide bar, a plain
/// glyph that turns it off.
struct PrivateListeningSign: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        if player.notCounted.isPrivate {
            Button {
                player.notCounted.privateListening = .off
            } label: {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Private Listening is on: plays are not counted. Click to turn it off.")
            .accessibilityLabel("Private Listening is on")
            .accessibilityHint("Turns it off")
        }
    }
}
