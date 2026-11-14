// The lyrics, in Now Playing's cover place: the server's (Jellyfin 10.9 and
// later, and Navidrome, read them from the files and from .lrc files beside
// them), and
// when it has none, LRCLIB's (LyricsFinder), with a line under them saying
// so. Synced lyrics follow the song as Music's do: the line being sung
// bright, the others dim, the view keeping it in sight, a tap on a line
// playing from there. Unsynced lyrics are the text, to read along.
//
// In the iPad's and the Mac's panel (`inPanel`) they read as Linux's
// (Linux/App/Panel.swift, the designer's spec §3): smaller and closer
// together ("Kun je de lyrics ook wat nicer opmaken, iets dichter op
// elkaar", the photographer, 14 November 2026), the other lines at 40 %,
// where they came from always under them, and a quiet line where there are
// none rather than a status page.

import JukeboxKit
import SwiftUI

struct LyricsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(AppSettings.self) private var settings

    private enum Content: Equatable {
        case loading
        case lyrics(Lyrics, fromLRCLIB: Bool)
        case instrumental
        case unavailable
        case failed(server: Bool)
    }

    /// The wide layout's panel, rather than Now Playing's cover place.
    private let inPanel: Bool

    @State private var content: Content = .loading

    init(inPanel: Bool = false) {
        self.inPanel = inPanel
    }

    var body: some View {
        Group {
            switch content {
            case .loading:
                if inPanel {
                    // Nothing for the moment it takes, as on Linux.
                    Color.clear
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case let .lyrics(lyrics, fromLRCLIB):
                if lyrics.isSynced {
                    LyricsSyncedLines(lyrics: lyrics, credit: credit(fromLRCLIB: fromLRCLIB), inPanel: inPanel)
                } else {
                    LyricsPlainText(lines: lyrics.lines, credit: credit(fromLRCLIB: fromLRCLIB))
                }
            case .instrumental:
                if inPanel {
                    quiet(Text("Instrumental"))
                } else {
                    ContentUnavailableView("Instrumental", systemImage: "pianokeys")
                }
            case .unavailable:
                if inPanel {
                    quiet(Text("No lyrics for this song"))
                } else {
                    ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                           description: unavailableDescription)
                }
            case let .failed(server):
                if inPanel {
                    quiet(failedDescription(server: server))
                } else {
                    ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                           description: failedDescription(server: server))
                }
            }
        }
        // Settings, where LRCLIB is turned on and off, cannot open over Now
        // Playing, so the song alone says when to ask again.
        .task(id: player.currentTrack?.id) {
            await load(player.currentTrack)
        }
        // Each time the panel opens (Stats); the songs' answers in `show`.
        .countsScreen("lyrics")
    }

    /// Under the lyrics: LRCLIB's, whose listeners wrote them; in the panel
    /// the server's too ("Lyrics from Jellyfin").
    private func credit(fromLRCLIB: Bool) -> String? {
        if fromLRCLIB { return "LRCLIB" }
        return inPanel ? app.serverKindName : nil
    }

    /// The panel's line where there are no lyrics: quiet, at the top.
    private func quiet(_ text: Text) -> some View {
        text
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.Space.xl)
    }

    private var unavailableDescription: Text {
        if settings.findLyricsOnline {
            return Text("Neither your server nor LRCLIB has lyrics for this song.")
        }
        return Text("\(app.serverKindName) has no lyrics for this song.")
    }

    private func failedDescription(server: Bool) -> Text {
        if server {
            return Text("The lyrics could not be loaded from the server.")
        }
        return Text("The lyrics could not be loaded from LRCLIB.")
    }

    private func load(_ track: Track?) async {
        guard let track, let server = app.server else {
            content = .unavailable
            return
        }
        let online = settings.findLyricsOnline
        let finder = LyricsFinder.shared
        if let known = finder.known(track, online: online) {
            show(known)
        } else {
            content = .loading
            let answer = await finder.lyrics(for: track, server: server, online: online)
            guard !Task.isCancelled else { return }
            show(answer)
        }
        // While the lyrics are open, the next song's too, so they are there
        // the moment it starts. While they are closed nothing is asked: no
        // traffic the listener did not ask for.
        guard !Task.isCancelled else { return }
        finder.prefetch(player.upNext.first?.track, server: server, online: online)
    }

    private func show(_ answer: LyricsAnswer) {
        // Where a song's lyrics came from, and whether timed (Stats).
        Stats.track(.lyricsShown, Stats.lyrics(answer))
        switch answer {
        case let .lyrics(lyrics, fromLRCLIB):
            content = .lyrics(lyrics, fromLRCLIB: fromLRCLIB)
        case .instrumental:
            content = .instrumental
        case .notFound:
            content = .unavailable
        case let .failed(server):
            content = .failed(server: server)
        }
    }
}

/// Under the lyrics: where they are from ("LRCLIB", "Jellyfin").
private struct LyricsCredit: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Text("Lyrics from \(source)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Timed lines: the one being sung bright, the view keeping it a third of
/// the way down, a tap on a line playing from there.
private struct LyricsSyncedLines: View {
    let lyrics: Lyrics
    /// Where they are from, under the last line; nil for none.
    let credit: String?
    let inPanel: Bool

    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(lyrics: Lyrics, credit: String?, inPanel: Bool) {
        self.lyrics = lyrics
        self.credit = credit
        self.inPanel = inPanel
    }

    var body: some View {
        // The line sung (JukeboxKit's, as Linux's panel has it).
        let current = lyrics.lineIndex(at: player.elapsed)
        ScrollViewReader { proxy in
            ScrollView {
                // In the panel 20 between lines, as Linux's: closer than
                // Now Playing's 24.
                VStack(alignment: .leading, spacing: inPanel ? Theme.Space.l + Theme.Space.xs : Theme.Space.xl) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        lineButton(line, isCurrent: index == current)
                            .id(index)
                    }
                    if let credit {
                        LyricsCredit(credit)
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                // Room above the first line and below the last, so either
                // can come to the reading place.
                .padding(.vertical, 120)
            }
            .scrollIndicators(.hidden)
            .onChange(of: current, initial: true) { _, line in
                guard let line else { return }
                if reduceMotion {
                    proxy.scrollTo(line, anchor: Self.readingPlace)
                } else {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(line, anchor: Self.readingPlace)
                    }
                }
            }
        }
        .mask {
            LyricsEdgeFade()
        }
    }

    /// A third of the way down: what is sung next stays in view under it.
    private static let readingPlace = UnitPoint(x: 0.5, y: 0.33)

    private func lineButton(_ line: Lyrics.Line, isCurrent: Bool) -> some View {
        Button {
            guard let start = line.start else { return }
            player.seek(to: start)
            if !player.isPlaying { player.resume() }
        } label: {
            // An empty line is an instrumental break; Music shows it as a beat.
            Text(line.text.isEmpty ? "♪" : line.text)
                // The panel's as Linux's (600, 18 on 24): the headline's
                // semibold, the line sung in full and the rest at 40 %.
                .font(inPanel ? .headline : .title.bold())
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(lineStyle(isCurrent: isCurrent))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
        .accessibilityHint("Plays from this line")
    }

    private func lineStyle(isCurrent: Bool) -> AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(HierarchicalShapeStyle.primary) }
        return inPanel ? AnyShapeStyle(Color.primary.opacity(0.4)) : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
    }
}

/// Untimed lyrics: the words, to read along.
private struct LyricsPlainText: View {
    let lines: [Lyrics.Line]
    /// Where they are from, under the words; nil for none.
    let credit: String?

    init(lines: [Lyrics.Line], credit: String?) {
        self.lines = lines
        self.credit = credit
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(lines.map(\.text).joined(separator: "\n"))
                    .font(.title3.weight(.semibold))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let credit {
                    LyricsCredit(credit)
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.xxl)
            // Past the edge's fade, so the credit can be read at the end.
            .padding(.bottom, credit != nil ? Theme.Space.xxl * 2 : Theme.Space.xxl)
        }
        .scrollIndicators(.hidden)
        .mask {
            LyricsEdgeFade()
        }
    }
}

/// Lines fade out at the top and the bottom rather than being cut off.
private struct LyricsEdgeFade: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.08),
            .init(color: .black, location: 0.9),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}
