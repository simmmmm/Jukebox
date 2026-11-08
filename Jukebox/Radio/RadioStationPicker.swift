// "Start a Station": any artist, song, album or genre in the library as a
// station's seed, found as one types — the library is in memory, so the
// answer is instant — with the stations Jukebox suggests and every genre
// before anything is typed. Choosing one starts it and closes the sheet;
// the Radio tab then shows it on the air. Section headers are Numa's small
// grey spaced labels (Eyebrow), as Search's and Settings' are.

import JukeboxKit
import SwiftUI

struct RadioStationPicker: View {
    @Environment(LibraryStore.self) private var library
    @Environment(RadioController.self) private var radio
    @Environment(MixStore.self) private var mixes
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    var body: some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let found = search(term)
        NavigationStack {
            List {
                if term.isEmpty {
                    suggestions
                } else {
                    results(found)
                }
            }
            .listStyle(.plain)
            .overlay {
                if !term.isEmpty && found.isEmpty {
                    ContentUnavailableView.search(text: term)
                }
            }
            .navigationTitle("Start a Station")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Artists, Songs, Albums, Genres")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Before anything is typed

    @ViewBuilder
    private var suggestions: some View {
        // Your Station, Discovery and Loved are on the Radio page itself.
        let suggested = Array(mixes.stations.filter { !Self.isOnRadioPage($0.seed) }.prefix(12))
        if !suggested.isEmpty {
            Section {
                ForEach(suggested) { station in
                    RadioPickerRow(title: station.title, subtitle: station.subtitle,
                                   action: { startStation(station) }) {
                        StationArtwork(station: station, size: 40, cornerRadius: Theme.Radius.thumbnail)
                    }
                }
            } header: {
                Eyebrow("Suggested")
            }
        }
        if !library.genres.isEmpty {
            Section {
                ForEach(library.genres) { genre in
                    RadioPickerRow(title: genre.name,
                                   action: { startSeed(.genre(key: genre.key, name: genre.name)) }) {
                        RadioPickerGlyph(systemImage: "guitars")
                    }
                }
            } header: {
                Eyebrow("Genres")
            }
        }
    }

    // MARK: Found

    private struct Found {
        var artists: [Artist] = []
        var tracks: [Track] = []
        var albums: [Album] = []
        var genres: [Genre] = []

        var isEmpty: Bool { artists.isEmpty && tracks.isEmpty && albums.isEmpty && genres.isEmpty }
    }

    private func search(_ term: String) -> Found {
        guard !term.isEmpty else { return Found() }
        let results = library.search(term, limit: 6)
        // The library's search has no genres; there are a few hundred at
        // most, so a plain match is enough.
        let genres = library.genres.filter { $0.name.localizedStandardContains(term) }
        return Found(artists: results.artists, tracks: results.tracks, albums: results.albums,
                     genres: Array(genres.prefix(6)))
    }

    @ViewBuilder
    private func results(_ found: Found) -> some View {
        if !found.artists.isEmpty {
            Section {
                ForEach(found.artists) { artist in
                    RadioPickerRow(title: artist.name,
                                   action: { startSeed(.artist(key: artist.key, name: artist.name, id: artist.id)) }) {
                        ArtistAvatar(artist: artist, size: 40)
                    }
                }
            } header: {
                Eyebrow("Artists")
            }
        }
        if !found.tracks.isEmpty {
            Section {
                ForEach(found.tracks) { track in
                    RadioPickerRow(title: track.name, subtitle: track.artistLine,
                                   action: { startSeed(.track(track.id)) }) {
                        ArtworkView(track.artwork, size: 40, cornerRadius: Theme.Radius.thumbnail)
                    }
                }
            } header: {
                Eyebrow("Songs")
            }
        }
        if !found.albums.isEmpty {
            Section {
                ForEach(found.albums) { album in
                    RadioPickerRow(title: album.name, subtitle: album.artistLine,
                                   action: { startSeed(.album(album.id)) }) {
                        ArtworkView(album.artwork, size: 40, cornerRadius: Theme.Radius.thumbnail)
                    }
                }
            } header: {
                Eyebrow("Albums")
            }
        }
        if !found.genres.isEmpty {
            Section {
                ForEach(found.genres) { genre in
                    RadioPickerRow(title: genre.name,
                                   action: { startSeed(.genre(key: genre.key, name: genre.name)) }) {
                        RadioPickerGlyph(systemImage: "guitars")
                    }
                }
            } header: {
                Eyebrow("Genres")
            }
        }
    }

    // MARK: Starting

    private func startSeed(_ seed: StationSeed) {
        radio.start(seed)
        dismiss()
    }

    private func startStation(_ station: Station) {
        radio.start(station)
        dismiss()
    }

    private static func isOnRadioPage(_ seed: StationSeed) -> Bool {
        switch seed {
        case .personal, .discovery, .favorites:
            return true
        default:
            return false
        }
    }
}

/// A row of the picker: the seed's picture, its name and a second line, and
/// the radio's symbol at the end, so it reads as "a station from this".
private struct RadioPickerRow<Leading: View>: View {
    let title: String
    let subtitle: String?
    let action: () -> Void
    let leading: Leading

    init(title: String, subtitle: String? = nil, action: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.leading = leading()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts a station from it")
    }
}

/// A symbol in a cover-sized grey square, for what has no cover (a genre).
private struct RadioPickerGlyph: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 40, height: 40)
            .background(.quaternary, in: .rect(cornerRadius: Theme.Radius.thumbnail))
            .accessibilityHidden(true)
    }
}
