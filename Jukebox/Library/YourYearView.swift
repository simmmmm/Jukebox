// On Your Jukebox (first Your Year) on the iPhone, the iPad and the Mac:
// This Week, This Month or This Year in the system's segmented control, the
// period in serif as on a sleeve, the minutes and plays as a fact, where
// they come from, its days or months as bars, the artist and the song it
// was most, then the songs, artists, albums and genres it was made of.
// "Your year kun je on your jukebox van maken en het gewoon
// wekelijks/maandelijks/jaarlijks laten zien" (the photographer, 23
// November 2026), and his rule from before: "Niet teveel als Spotify qua
// ui": rows on the ground, no cards. A page of the library's
// (Route.yourYear): a row in the iPhone's Library, a place in the wide
// window's sidebar, the Mac's Account › On Your Jukebox. The music is
// content, not a setting (21 November 2026). YourYearLoader has the
// sources and the words. Linux's is YourYearPage, in its sidebar and
// primary menu.

import JukeboxKit
import SwiftUI

struct YourYearView: View {
    @Environment(AppModel.self) private var app
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @State private var period = YourYearLoader.firstPeriod
    @State private var made: YourYear?

    var body: some View {
        content
            .navigationTitle(YourYearLoader.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Each time it shows and each period chosen: a page kept in the
            // sidebar's stack would otherwise keep the morning's week all
            // day. A period chosen again before the last came in wins.
            .task(id: period) {
                let loaded = await YourYearLoader.load(period: period, server: app.server,
                                                       history: history.history, library: library)
                if !Task.isCancelled { made = loaded }
            }
    }

    @ViewBuilder private var content: some View {
        if let made {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        // In the list, not in a bar over it: the ground stays
                        // flat, and Linux's page has its buttons here too.
                        Picker("Period", selection: $period) {
                            ForEach(YourYear.Period.allCases, id: \.self) { period in
                                Text(verbatim: YourYearLoader.name(period)).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.bottom, Theme.Space.s)
                        Text(verbatim: YourYearLoader.heading(made))
                            .font(.serif(.largeTitle))
                        // Nothing played: the head as Linux's, its facts the
                        // one line, not a status page: "Los ze op" (the
                        // photographer, 20 November 2026).
                        Text(made.isEmpty ? String(localized: "Nothing played yet") : YourYearLoader.facts(made))
                            .foregroundStyle(.secondary)
                        SpreadBars(minutes: made.spread, labels: YourYearLoader.spreadLabels(made),
                                   name: YourYearLoader.spreadName(made))
                            .padding(.top, Theme.Space.m)
                    }
                    .padding(.vertical, Theme.Space.s)
                } footer: {
                    Text(YourYearLoader.source(made))
                }
                if let artist = made.artists.first, let song = made.songs.first {
                    // The artist and the song it was most, larger than the
                    // lists' rows, each with its cover (an artist's is its
                    // most played song's, as YourYear keeps it).
                    Section("Most played") {
                        top(artist, line: YourYearLoader.plays(artist))
                        top(song, line: [song.detail, YourYearLoader.plays(song)].compactMap { $0 }.joined(separator: " · "))
                    }
                }
                entries("Songs", made.songs, artwork: true)
                entries("Artists", made.artists, artwork: false)
                entries("Albums", made.albums, artwork: true)
                entries("Genres", made.genres, artwork: false)
            }
        } else {
            ProgressView()
        }
    }

    private func top(_ entry: YourYear.Entry, line: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            ArtworkView(entry.track?.artwork, size: 64, sleeve: entry.track.map(TitleSleeve.Words.init(track:)))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(verbatim: entry.name)
                    .font(.serif(.title2))
                    .lineLimit(2)
                Text(verbatim: line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func entries(_ title: LocalizedStringKey, _ list: [YourYear.Entry], artwork: Bool) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(Array(list.enumerated()), id: \.element.id) { rank, entry in
                    HStack(spacing: Theme.Space.m) {
                        Text(verbatim: "\(rank + 1)")
                            .font(.serif(.body))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        if artwork {
                            ArtworkView(entry.track?.artwork, size: 40, sleeve: entry.track.map(TitleSleeve.Words.init(track:)))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: entry.name).lineLimit(1)
                            if let detail = entry.detail {
                                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: Theme.Space.s)
                        Text(YourYearLoader.plays(entry))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// A bar a day of the week or the month, or a month of the year, each as
/// tall as its minutes; flat ground, the accent for the bars.
private struct SpreadBars: View {
    let minutes: [Int]
    let labels: [String]
    let name: String

    var body: some View {
        let most = max(1, minutes.max() ?? 1)
        HStack(alignment: .bottom, spacing: minutes.count > 12 ? 2 : Theme.Space.xs) {
            ForEach(minutes.indices, id: \.self) { index in
                VStack(spacing: Theme.Space.xs) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: max(1, 64 * CGFloat(minutes[index]) / CGFloat(most)))
                    // A month's day numbers stand under their bar and may
                    // be wider than it.
                    Text(verbatim: labels.indices.contains(index) ? labels[index] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: minutes.count > 12 ? .leading : .center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 88, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
    }
}
