// The pieces Home and Radio share: which station is on the air, what a tab
// shows while the library loads or when it has nothing, a station's tile
// that opens its page and its long-press menu, a station's kind in words,
// the grey placeholders a shelf shows while the mixes are being made, and a
// mix's tile and menu.
// Named Home… or Station… so they cannot clash with another part's helpers.

import JukeboxKit
import SwiftUI

extension RadioController {
    /// The station on the air: one is starting, or the player is playing
    /// its queue. `station` alone can outlive the music (the player was
    /// stopped from the lock screen), so the player's context decides.
    func stationOnAir(player: AudioPlayer) -> Station? {
        guard let station else { return nil }
        if isStarting || player.context?.station?.id == station.id { return station }
        return nil
    }
}

extension AudioPlayer {
    /// A mix from `index`, named after the mix in Now Playing ("Playing
    /// from Daily Mix 1").
    func playMix(_ mix: Mix, from index: Int = 0, shuffled: Bool = false) {
        // Which kind of mix is played (Stats): its kind, never its title.
        Stats.track(.mixPlayed, ["kind": mix.kind.rawValue])
        play(mix.tracks, startingAt: index, context: QueueContext(.mix(mix.id), title: mix.title), shuffled: shuffled)
    }
}

enum HomeText {
    /// "1 song", "25 songs".
    static func songs(_ count: Int) -> String {
        count == 1 ? String(localized: "1 song") : String(localized: "\(count) songs")
    }

    /// "25 songs, 1 hour, 42 minutes"; the songs alone under a minute.
    static func summary(count: Int, duration: TimeInterval) -> String {
        let spoken = duration.spoken
        return duration >= 60 && !spoken.isEmpty ? "\(songs(count)), \(spoken)" : songs(count)
    }
}

// MARK: - The library's state, where a tab has nothing to show yet

/// Home's and Radio's page before there is music: the first load with its
/// progress, the error with a way to try again, or a server with no music.
struct HomeLibraryStatus: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch library.state {
        case .empty:
            // Signed in a moment ago: the load is about to start.
            HomeLoadingView(progress: nil)
        case let .loading(progress):
            HomeLoadingView(progress: progress)
        case let .failed(message):
            ContentUnavailableView {
                Label("Could Not Load Your Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await library.refresh() }
                }
                .buttonStyle(.prominent)
                .fixedSize()
            }
        case .loaded:
            ContentUnavailableView {
                Label("No Music Yet", systemImage: "music.note")
            } description: {
                Text("Your \(library.serverKind) server has no music in its libraries yet. Add some there, then check again.")
            } actions: {
                Button("Check Again") {
                    Task { await library.refresh() }
                }
                .buttonStyle(.secondary)
                .fixedSize()
            }
        }
    }
}

/// The first load: the mark, flat, the words, and the bar when the server
/// has said how much there is.
struct HomeLoadingView: View {
    let progress: Double?

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ArchMark(size: 48)
            VStack(spacing: Theme.Space.xs) {
                Text("Loading your library…")
                    .font(.headline)
                Text("The first time takes a moment. After that, Jukebox opens at once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let progress {
                VStack(spacing: Theme.Space.s) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 240)
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .padding(Theme.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stations

/// What kind of station it is, as a fact under a station's name on its
/// page: "Artist station", "Your Station" says what it is by its name.
enum StationText {
    static func kind(_ station: Station) -> String {
        switch station.seed {
        case .track: String(localized: "Song station")
        case .artist: String(localized: "Artist station")
        case .album: String(localized: "Album station")
        case .genre: String(localized: "Genre station")
        case .decade: String(localized: "Decade station")
        case .collection: String(localized: "Playlist station")
        case .personal: String(localized: "From your listening")
        case .discovery: String(localized: "New to you")
        case .favorites: String(localized: "From your favorites")
        }
    }
}

/// A station's tile: it opens the station's page, where what the radio
/// made of it can be seen before it plays. The photographer, 8 November
/// 2026: "Als je nu klikt op een tegel van radio begint er meteen van alles
/// te spelen ipv dat je kan zien wat je van de playlist gemaakt hebt." A
/// long press plays it at once. The one on the air opens its page too,
/// which then shows what plays and what comes next; its art is the one lit.
struct StationTileLink: View {
    let station: Station

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player

    init(station: Station) {
        self.station = station
    }

    var body: some View {
        let onAir = radio.stationOnAir(player: player)?.seed == station.seed
        NavigationLink(value: Route.station(station)) {
            StationCard(station: station)
        }
        .buttonStyle(.plain)
        .contextMenu {
            StationMenu(station: station)
        }
        .accessibilityAddTraits(onAir ? .isSelected : [])
        .accessibilityHint(Text("Shows the station and what it would play"))
    }
}

/// A station's long press, on its tile and its card: play it now, without
/// looking first, or see its page. The station on the air offers Now
/// Playing instead of Play: playing it again would start it over.
struct StationMenu: View {
    let station: Station

    @Environment(RadioController.self) private var radio
    @Environment(AudioPlayer.self) private var player
    @Environment(Navigator.self) private var navigator

    init(station: Station) {
        self.station = station
    }

    var body: some View {
        Section {
            if radio.stationOnAir(player: player)?.seed == station.seed {
                Button("Show Now Playing", systemImage: "play.circle") {
                    navigator.isNowPlayingPresented = true
                }
            } else {
                Button("Play Station", systemImage: "play.fill") {
                    Stats.track(.stationStarted, ["seed": Stats.seed(station.seed), "from": "tile_menu"])
                    radio.start(station)
                }
            }
            Button("Show Station", systemImage: "dot.radiowaves.left.and.right") {
                navigator.open(.station(station))
            }
        }
    }
}

// MARK: - Placeholders

struct HomePlaceholder: Identifiable {
    let id: Int
}

/// A shelf of grey tiles while the mixes and stations are being made, so
/// Home does not jump when they arrive.
struct HomePlaceholderShelf: View {
    enum Kind {
        case mix
        case station
    }

    let kind: Kind
    var width: CGFloat = 160

    var body: some View {
        Shelf(items: Self.items, width: width) { _ in
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                RoundedRectangle(cornerRadius: Theme.Radius.artwork)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                Text("Daily Mix 1")
                    .font(.subheadline.weight(.medium))
                Text("Artists you love and more")
                    .font(.subheadline)
            }
            .redacted(reason: .placeholder)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .mix ? Text("Making your mixes") : Text("Finding your stations"))
    }

    private static let items = (0..<5).map { HomePlaceholder(id: $0) }
}

// MARK: - Mixes and albums on a shelf

/// A mix's card that opens it, with what can be done with it on a long press.
struct HomeMixLink: View {
    let mix: Mix

    var body: some View {
        NavigationLink(value: Route.mix(mix)) {
            MixCard(mix: mix)
        }
        .buttonStyle(.plain)
        .contextMenu {
            HomeMixMenu(mix: mix)
        }
    }
}

/// What can be done with a mix, as Music orders it for a playlist.
struct HomeMixMenu: View {
    let mix: Mix

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(Navigator.self) private var navigator

    init(mix: Mix) {
        self.mix = mix
    }

    var body: some View {
        Section {
            Button("Play", systemImage: "play.fill") {
                player.playMix(mix)
            }
            Button("Shuffle", systemImage: "shuffle") {
                player.playMix(mix, shuffled: true)
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": Stats.seed(mix.stationSeed), "from": "menu"])
                radio.start(mix.stationSeed)
            }
        }
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(mix.tracks)
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.addToQueue(mix.tracks)
            }
        }
        Section {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: mix.tracks)
            }
        }
    }
}

/// An album's tile that opens it; a long press plays it or starts its station.
struct HomeAlbumLink: View {
    let album: Album

    init(album: Album) {
        self.album = album
    }

    var body: some View {
        NavigationLink(value: Route.album(album)) {
            AlbumTile(album: album)
        }
        .buttonStyle(.plain)
        .contextMenu {
            HomeAlbumMenu(album: album)
        }
    }
}

/// An album's long press, on a shelf's tile and on Played lately's row:
/// play it, shuffle it, or start its station.
struct HomeAlbumMenu: View {
    let album: Album

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library

    init(album: Album) {
        self.album = album
    }

    var body: some View {
        Section {
            Button("Play", systemImage: "play.fill") {
                play(shuffled: false)
            }
            Button("Shuffle", systemImage: "shuffle") {
                play(shuffled: true)
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "album", "from": "menu"])
                radio.start(.album(album.id))
            }
        }
    }

    private func play(shuffled: Bool) {
        let tracks = library.tracks(inAlbum: album.id)
        player.play(tracks, context: QueueContext(.album(album.id), title: album.name), shuffled: shuffled)
    }
}
