// The lyrics, in Now Playing's cover place: the server's (Jellyfin 10.9 and
// later reads them from the files and from .lrc files beside them), and
// when it has none, LRCLIB's (LyricsFinder), with a line under them saying
// so. Synced lyrics follow the song as Music's do: the line being sung
// bright, the others dim, the view keeping it in sight, a tap on a line
// playing from there. Unsynced lyrics are the text, to read along.

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

    @State private var content: Content = .loading

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .lyrics(lyrics, fromLRCLIB):
                if lyrics.isSynced {
                    LyricsSyncedLines(lines: lyrics.lines, credit: fromLRCLIB)
                } else {
                    LyricsPlainText(lines: lyrics.lines, credit: fromLRCLIB)
                }
            case .instrumental:
                ContentUnavailableView("Instrumental", systemImage: "pianokeys")
            case .unavailable:
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                       description: unavailableDescription)
            case let .failed(server):
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                       description: failedDescription(server: server))
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

    private var unavailableDescription: Text {
        if settings.findLyricsOnline {
            return Text("Neither your server nor LRCLIB has lyrics for this song.")
        }
        return Text("Jellyfin has no lyrics for this song.")
    }

    private func failedDescription(server: Bool) -> Text {
        if server {
            return Text("The lyrics could not be loaded from the server.")
        }
        return Text("The lyrics could not be loaded from LRCLIB.")
    }

    private func load(_ track: Track?) async {
        guard let track, let client = app.client else {
            content = .unavailable
            return
        }
        let online = settings.findLyricsOnline
        let finder = LyricsFinder.shared
        if let known = finder.known(track, online: online) {
            show(known)
        } else {
            content = .loading
            let answer = await finder.lyrics(for: track, client: client, online: online)
            guard !Task.isCancelled else { return }
            show(answer)
        }
        // While the lyrics are open, the next song's too, so they are there
        // the moment it starts. While they are closed nothing is asked: no
        // traffic the listener did not ask for.
        guard !Task.isCancelled else { return }
        finder.prefetch(player.upNext.first?.track, client: client, online: online)
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

/// Under LRCLIB's lyrics: where they are from. Its listeners wrote them.
private struct LyricsCredit: View {
    init() {}

    var body: some View {
        Text("Lyrics from LRCLIB")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Timed lines: the one being sung bright, the view keeping it a third of
/// the way down, a tap on a line playing from there.
private struct LyricsSyncedLines: View {
    let lines: [Lyrics.Line]
    /// LRCLIB's: the credit under the last line.
    let credit: Bool

    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(lines: [Lyrics.Line], credit: Bool) {
        self.lines = lines
        self.credit = credit
    }

    var body: some View {
        let current = currentLine(at: player.elapsed)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        lineButton(line, isCurrent: index == current)
                            .id(index)
                    }
                    if credit {
                        LyricsCredit()
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
                .font(.title.bold())
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(isCurrent ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.tertiary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
        .accessibilityHint("Plays from this line")
    }

    /// The last line that has begun. A quarter second early: the line
    /// lights as it is sung, not after (the player's clock ticks every half
    /// second).
    private func currentLine(at elapsed: TimeInterval) -> Int? {
        let now = elapsed + 0.25
        var found: Int?
        for (index, line) in lines.enumerated() {
            guard let start = line.start else { continue }
            if start <= now {
                found = index
            } else {
                break
            }
        }
        return found
    }
}

/// Untimed lyrics: the words, to read along.
private struct LyricsPlainText: View {
    let lines: [Lyrics.Line]
    /// LRCLIB's: the credit under the words.
    let credit: Bool

    init(lines: [Lyrics.Line], credit: Bool) {
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
                if credit {
                    LyricsCredit()
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.xxl)
            // Past the edge's fade, so the credit can be read at the end.
            .padding(.bottom, credit ? Theme.Space.xxl * 2 : Theme.Space.xxl)
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
