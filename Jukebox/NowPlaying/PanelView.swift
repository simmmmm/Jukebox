// The wide layout's panel beside the page, on the iPad and the Mac: Up Next
// or the song's words, as PanelState says, in WideShell's own pane. The
// photographer of Feishin's panel, 14 November 2026: "Als optionele
// toevoegingen. Wat wij echter niet moeten doen is het een hele drukke app
// maken" — so it is closed until the bar's buttons open it, and the lit
// button is the way out: no close button here (the designer's spec, §3).
// Its head is Linux's (Linux/App/Panel.swift), 1:1: 48 tall, the two tabs at
// its start, the chosen one on a faint fill in full and the other at 60 %.

import SwiftUI

struct PanelView: View {
    @Environment(PanelState.self) private var panel
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(Navigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme

    init() {}

    var body: some View {
        // One at a time: the lyrics are asked for only while they show.
        Group {
            switch panel.content {
            case .upNext:
                QueueView(inPanel: true)
            case .lyrics:
                LyricsView(inPanel: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: Theme.Space.xs) {
                // The panel's name, Now Playing ("moet up next niet
                // trouwens gewoon 'now playing' worden", the photographer,
                // 15 November 2026); its list's own headings stay.
                tab("Now Playing", .upNext)
                if offersLyrics {
                    tab("Lyrics", .lyrics)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 48)
        }
        // The bar's ground; over Now Playing's room the room's, dark.
        .background(PlayerBar.groundFor(inRoom: inRoom).ignoresSafeArea())
        .environment(\.colorScheme, inRoom ? .dark : colorScheme)
        // No lyrics to be had at all: Up Next, and no Lyrics tab.
        .onChange(of: offersLyrics, initial: true) { _, offers in
            if !offers && panel.content == .lyrics { panel.content = .upNext }
        }
    }

    private var inRoom: Bool {
        navigator.isNowPlayingPresented
    }

    /// One of the head's two tabs.
    private func tab(_ title: LocalizedStringKey, _ content: PanelState.Content) -> some View {
        let isChosen = panel.content == content
        return Button {
            panel.content = content
        } label: {
            Text(title)
                // Linux's panel-tab: 15 at 600.
                .desktopFont(15, weight: .semibold)
                .foregroundStyle(isChosen ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .padding(.horizontal, Theme.Space.l)
                .frame(height: 32)
                .background(isChosen ? Color.primary.opacity(0.1) : Color.clear, in: .rect(cornerRadius: Theme.Space.s))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// The server's lyrics, or LRCLIB's when Settings allow it, as the bar's
    /// Lyrics button has it.
    private var offersLyrics: Bool {
        app.can(.lyrics) || settings.findLyricsOnline
    }
}
