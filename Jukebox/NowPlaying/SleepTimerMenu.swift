// The sleep timer, in Now Playing's ⋮ (and the Full Player's), as Linux's
// (Linux/App/PlayerBar.swift), and Controls › Sleep Timer in the Mac's menu
// bar. Asked for with what other players have that Jukebox lacked: "maak ze
// allemaal maar". It had a moon of its own beside ⋮ until the photographer,
// 18 November 2026: "verstop dat maantje ff in dat more menutje, heb je ook
// niet een eenvoudiger icoon". While it runs, the menu's entry says when it
// stops and a small moon stands in ⋮'s own glyph: no button of its own.
// The timer itself is the queue's (PlayQueue.setSleepTimer), so the
// iPhone, the Mac and Linux keep one.

import SwiftUI

/// The choices, the one set ticked.
struct SleepTimerPicker: View {
    let player: PlayQueue

    var body: some View {
        Picker("Sleep Timer", selection: Binding(get: { player.sleepChoice },
                                                 set: { player.setSleepTimer($0) })) {
            Text("Off").tag(SleepChoice?.none)
            ForEach(player.sleepChoices, id: \.self) { choice in
                Text(player.sleepTitle(choice)).tag(SleepChoice?.some(choice))
            }
        }
        .pickerStyle(.inline)
    }
}

/// Sleep Timer in a ⋮, with the choices under it: "Sleep Timer · Stops at
/// 23:41" while it runs, "Sleep Timer · End of Album" while it waits. Its
/// own section, after the song's, so the song's menu (TrackMenu) keeps its
/// order and what is added beside Favorite stays there.
struct SleepTimerItem: View {
    let player: PlayQueue

    var body: some View {
        Section {
            Menu {
                SleepTimerPicker(player: player)
            } label: {
                Label(Self.title(player), systemImage: "moon")
            }
            .accessibilityIdentifier("nowPlaying.sleepTimer")
        }
    }

    /// When it stops rather than a countdown: a menu's words are set when
    /// ⋮ is drawn, and ⋮ drawn again every second could close the menu
    /// under the finger. A time stays true. Linux's says the same.
    static func title(_ player: PlayQueue) -> String {
        let name = String(localized: "Sleep Timer")
        if let deadline = player.sleepDeadline {
            return "\(name) · " + String(localized: "Stops at \(deadline.formatted(date: .omitted, time: .shortened))")
        }
        if let choice = player.sleepChoice {
            return "\(name) · \(player.sleepTitle(choice))"
        }
        return name
    }
}

/// ⋮'s glyph, and before it a small moon while the timer is set: the one
/// sign of it outside the menu.
struct MoreGlyph: View {
    let player: PlayQueue
    let font: Font
    let ink: Color
    let side: CGFloat

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if player.sleepChoice != nil {
                Image(systemName: "moon.fill")
                    .font(.caption2)
                    .foregroundStyle(ink.opacity(0.6))
            }
            Image(systemName: "ellipsis")
                .font(font)
                .foregroundStyle(ink)
        }
        .frame(minWidth: side, minHeight: side)
        .contentShape(.rect)
    }
}
