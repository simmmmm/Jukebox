// The wide layout's panel beside the page, on the iPad and the Mac: Up Next
// or the song's words, as PanelState says, in WideShell's own pane. The
// photographer of Feishin's panel, 14 November 2026: "Als optionele
// toevoegingen. Wat wij echter niet moeten doen is het een hele drukke app
// maken" — so it is closed until the bar's buttons open it, and the lit
// button is the way out: no close button here (the designer's spec, §3).
// Its head is Linux's (Linux/App/Panel.swift) in the Apple clients' own
// form: 48 tall, at its start the system's segmented control where Linux
// has GNOME's tabs.

import SwiftUI

struct PanelView: View {
    @Environment(PanelState.self) private var panel
    @Environment(AudioPlayer.self) private var player
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
            HStack(spacing: 0) {
                // The system's segmented control, not Linux's GNOME tabs:
                // "zijn die twee buttons hier now playing en lyrics niet
                // gnome hig?" (the photographer, 24 November 2026). The
                // panel's name, Now Playing ("moet up next niet trouwens
                // gewoon 'now playing' worden", 15 November 2026); its
                // list's own headings stay. Without lyrics to be had at
                // all, Now Playing alone, as one segment.
                Picker("Panel", selection: chosen) {
                    Text("Now Playing").tag(PanelState.Content.upNext)
                    if offersLyrics {
                        // Off for a song with none, as the bar's button
                        // (LyricsFinder.hasNone).
                        Text("Lyrics").tag(PanelState.Content.lyrics)
                            .disabled(songHasNoLyrics)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
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
        // None for this song, once that is known: Up Next.
        .onChange(of: songHasNoLyrics, initial: true) { _, none in
            if none && panel.content == .lyrics { panel.content = .upNext }
        }
    }

    private var songHasNoLyrics: Bool {
        LyricsFinder.shared.hasNone(player.currentTrack, online: settings.findLyricsOnline)
    }

    private var inRoom: Bool {
        navigator.isNowPlayingPresented
    }

    /// What the head's segments choose: Lyrics never for a song with none,
    /// should a disabled segment still be clicked.
    private var chosen: Binding<PanelState.Content> {
        Binding(get: { panel.content },
                set: { content in
                    if content == .lyrics && songHasNoLyrics { return }
                    panel.content = content
                })
    }

    /// The server's lyrics, or LRCLIB's when Settings allow it, as the bar's
    /// Lyrics button has it.
    private var offersLyrics: Bool {
        app.can(.lyrics) || settings.findLyricsOnline
    }
}
