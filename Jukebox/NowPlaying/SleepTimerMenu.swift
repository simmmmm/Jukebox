// The sleep timer, where a listener in bed looks for it: a moon beside Now
// Playing's ⋮ (Podcasts keeps its moon in its player too), as Linux's
// (Linux/App/PlayerBar.swift), and Controls › Sleep Timer in the Mac's
// menu bar. Asked for with what other players have that Jukebox lacked:
// "maak ze allemaal maar". The timer itself is the queue's
// (PlayQueue.setSleepTimer), so the iPhone, the Mac and Linux keep one.

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

/// The moon, filled while the timer runs, with the time left before it, or
/// what it waits for (beside the menu, not in its label: the Mac draws a
/// menu's label once).
struct SleepTimerMenu: View {
    let player: PlayQueue
    let font: Font
    let ink: Color
    let side: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let left = Self.left(player.sleepDeadline) {
                Text(timerInterval: left, countsDown: true)
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(ink)
            } else if let choice = player.sleepChoice, player.sleepDeadline == nil {
                // What it waits for: "End of Album".
                Text(player.sleepTitle(choice))
                    .font(font)
                    .foregroundStyle(ink)
            }
            Menu {
                SleepTimerPicker(player: player)
            } label: {
                Image(systemName: player.sleepChoice == nil ? "moon.zzz" : "moon.zzz.fill")
                    .font(font)
                    .foregroundStyle(ink)
                    .frame(width: side, height: side)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Sleep Timer")
            .accessibilityIdentifier("nowPlaying.sleepTimer")
        }
    }

    /// From now to the deadline; nil without one, or once it is past (a
    /// range the wrong way round would trap).
    private static func left(_ deadline: Date?) -> ClosedRange<Date>? {
        let now = Date()
        guard let deadline, deadline > now else { return nil }
        return now...deadline
    }
}
