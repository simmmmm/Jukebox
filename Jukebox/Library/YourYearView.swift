// Your Year on the iPhone, the iPad and the Mac: the year in serif as on a
// sleeve, the minutes and plays as a fact, where they come from, the months
// as bars, then the songs, artists, albums and genres it was made of.
// A page of the library's (Route.yourYear): a row in the iPhone's Library,
// a place in the wide window's sidebar, the Mac's Account › Your Year. It
// was a button in Settings, and left it: the year's music is content, not
// a setting (21 November 2026). YourYearLoader has the sources. Linux's
// is YourYearPage, in its sidebar and primary menu.

import JukeboxKit
import SwiftUI

struct YourYearView: View {
    @Environment(AppModel.self) private var app
    @Environment(LibraryStore.self) private var library
    @Environment(HistoryStore.self) private var history
    @State private var year: YourYear?

    var body: some View {
        content
            .navigationTitle("Your Year")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // Each time it shows: a page kept in the sidebar's stack would
            // otherwise keep the morning's year all day.
            .task {
                year = await YourYearLoader.load(year: YourYearLoader.year(), server: app.server,
                                                 history: history.history, library: library)
            }
    }

    @ViewBuilder private var content: some View {
        if let year {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text(verbatim: String(year.year))
                            .font(.serif(.largeTitle))
                        // Nothing played: the year's head as Linux's, its
                        // facts the one line, not a status page: "Los ze
                        // op" (the photographer, 20 November 2026).
                        Text(year.isEmpty ? String(localized: "Nothing played yet") : YourYearLoader.facts(year))
                            .foregroundStyle(.secondary)
                        MonthBars(minutes: year.months)
                            .padding(.top, Theme.Space.m)
                    }
                    .padding(.vertical, Theme.Space.s)
                } footer: {
                    Text(YourYearLoader.source(year))
                }
                entries("Songs", year.songs, artwork: true)
                entries("Artists", year.artists, artwork: false)
                entries("Albums", year.albums, artwork: true)
                entries("Genres", year.genres, artwork: false)
            }
        } else {
            ProgressView()
        }
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

/// Twelve bars, January first, each as tall as its month's minutes; flat
/// ground, the accent for the bars.
private struct MonthBars: View {
    let minutes: [Int]

    var body: some View {
        let most = max(1, minutes.max() ?? 1)
        let letters = YourYearLoader.monthLetters
        HStack(alignment: .bottom, spacing: Theme.Space.xs) {
            ForEach(0..<12, id: \.self) { month in
                VStack(spacing: Theme.Space.xs) {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: max(1, 64 * CGFloat(minutes[month]) / CGFloat(most)))
                    Text(verbatim: letters.indices.contains(month) ? letters[month] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 88, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Minutes by month"))
    }
}
