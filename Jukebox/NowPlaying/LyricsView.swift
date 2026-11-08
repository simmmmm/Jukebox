// The lyrics, in Now Playing's cover place, from Jellyfin (10.9 and later
// read them from the files and from .lrc files beside them). Synced lyrics
// follow the song as Music's do: the line being sung bright, the others
// dim, the view keeping it in sight, a tap on a line playing from there.
// Unsynced lyrics are the text, to read along.

import JukeboxKit
import SwiftUI

struct LyricsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AudioPlayer.self) private var player

    private enum Content: Equatable {
        case loading
        case lyrics(Lyrics)
        case unavailable
        case failed
    }

    @State private var content: Content = .loading

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .lyrics(lyrics):
                if lyrics.isSynced {
                    LyricsSyncedLines(lines: lyrics.lines)
                } else {
                    LyricsPlainText(lines: lyrics.lines)
                }
            case .unavailable:
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                       description: Text("Jellyfin has no lyrics for this song."))
            case .failed:
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                       description: Text("The lyrics could not be loaded from the server."))
            }
        }
        .task(id: player.currentTrack?.id) {
            await load(player.currentTrack?.id)
        }
    }

    private func load(_ trackID: ItemID?) async {
        guard let trackID else {
            content = .unavailable
            return
        }
        if let known = LyricsMemory.found[trackID] {
            content = .lyrics(known)
            return
        }
        if LyricsMemory.missing.contains(trackID) {
            content = .unavailable
            return
        }
        guard let client = app.client else {
            content = .unavailable
            return
        }
        content = .loading
        do {
            let lyrics = try await client.lyrics(trackID: trackID)
            guard !Task.isCancelled else { return }
            if let lyrics, !lyrics.lines.isEmpty {
                LyricsMemory.remember(lyrics, for: trackID)
                content = .lyrics(lyrics)
            } else {
                LyricsMemory.missing.insert(trackID)
                content = .unavailable
            }
        } catch {
            // Not remembered: the network may be back next time.
            guard !Task.isCancelled else { return }
            content = .failed
        }
    }
}

/// Lyrics fetched this launch, so turning to them again, or a song coming
/// round again on a station, does not ask the server twice.
private enum LyricsMemory {
    static var found: [ItemID: Lyrics] = [:]
    /// Tracks the server has no lyrics for.
    static var missing: Set<ItemID> = []

    static func remember(_ lyrics: Lyrics, for trackID: ItemID) {
        // A few hundred songs' lyrics are a few hundred kilobytes; past
        // that, start again rather than keep a whole evening's.
        if found.count >= 200 { found.removeAll() }
        found[trackID] = lyrics
    }
}

/// Timed lines: the one being sung bright, the view keeping it a third of
/// the way down, a tap on a line playing from there.
private struct LyricsSyncedLines: View {
    let lines: [Lyrics.Line]

    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(lines: [Lyrics.Line]) {
        self.lines = lines
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

    init(lines: [Lyrics.Line]) {
        self.lines = lines
    }

    var body: some View {
        ScrollView {
            Text(lines.map(\.text).joined(separator: "\n"))
                .font(.title3.weight(.semibold))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.xxl)
                .textSelection(.enabled)
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
