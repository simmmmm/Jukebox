// What Siri and Shortcuts ask of Jukebox, answered with the calls the
// screens make: `player.play`, `radio.start`, `radio.like`. Nothing here
// chooses or queues by itself, so the queue, offline and the counts behave
// as after a tap. Above all for the car: CarPlay was just built, and without
// a voice every song there is a tap while driving.
//
// Two ways in, both to here: App Intents (Intents/MusicIntents.swift: the
// Shortcuts app, Siri's App Shortcuts, the Mac) and, on the iPhone, SiriKit's
// INPlayMediaIntent (Intents/SiriMedia.swift), which is what turns "Play
// <any album> in Jukebox" into a search of the library.
//
// An intent can launch the app in the background, without its window, as the
// car can: `ready` restores the session as the car's scene does, and waits a
// moment for the library.

// updateAppShortcutParameters.
import AppIntents
import Foundation
import JukeboxKit

enum Voice {
    /// The session, restored if nobody has yet, once the library is in (or
    /// a few seconds have passed). Nil signed out.
    static func ready() async -> AppModel? {
        let app = AppModel.shared
        if app.phase == .launching {
            // As CarPlay's scene does from a cold start: the session, then is
            // the server there (often not, in a car).
            Task {
                await app.restore()
                if app.phase == .signedIn { app.offline.appBecameActive() }
            }
        }
        // restore returns before the mixes are made, but a first launch on a
        // server waits for the whole library: Siri waits about ten seconds.
        for _ in 0..<80 {
            switch app.phase {
            case .signedOut: return nil
            // Another account being switched to (Accounts.swift): what Siri
            // asked for is found in that one's library, once it is in.
            case .signedIn where app.isSwitching || app.credentials == nil:
                try? await Task.sleep(for: .milliseconds(100))
            case .signedIn where !app.library.tracks.isEmpty: return app
            case .signedIn where app.library.state != .empty && !isLoading(app.library): return app
            default: try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return app.phase == .signedIn ? app : nil
    }

    private static func isLoading(_ library: LibraryStore) -> Bool {
        if case .loading = library.state { return true }
        return false
    }

    /// The window has a library (JukeboxApp): Siri's phrases learn its
    /// names (Voice.suggestions), and on the iPhone Siri's permission is
    /// asked, once, in front of the listener rather than in the car.
    static func libraryShown(_ app: AppModel) async {
        guard app.phase == .signedIn, app.library.lastLoaded != nil else { return }
        JukeboxShortcuts.updateAppShortcutParameters()
        #if os(iOS)
        SiriMedia.askOnce()
        #endif
    }

    static let signInFirst = String(localized: "Open Jukebox and sign in to your music server first.")

    /// What came of a request: whether music now plays, and what Siri says.
    struct Answer: Sendable {
        let played: Bool
        let text: String

        static func no(_ text: String) -> Answer { Answer(played: false, text: text) }
    }

    // MARK: Finding

    /// What a name means in the library, best first: a name said whole
    /// before one that only contains it, then playlists, albums, artists,
    /// genres and songs. Your Station when the words name a station.
    static func find(_ term: String, in library: LibraryStore, limit: Int = 5) -> [MusicEntity] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let found = library.search(term, limit: limit)
        var all: [MusicEntity] = []
        if term.localizedCaseInsensitiveContains("station") || term.localizedCaseInsensitiveContains("radio") {
            all.append(.yourStation)
        }
        all += found.playlists.map(MusicEntity.init)
        all += found.albums.map(MusicEntity.init)
        all += found.artists.map(MusicEntity.init)
        all += library.genres.filter { $0.name.localizedCaseInsensitiveContains(term) }.prefix(limit).map(MusicEntity.init)
        all += found.tracks.map(MusicEntity.init)
        // Stable: within the whole names and within the rest, the order above.
        let whole = all.filter { $0.name.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return whole + all.filter { whole.firstIndex(of: $0) == nil }
    }

    /// The same, of one kind, as SiriKit's search names it ("the album
    /// Blue", "the playlist Road"); an album by the artist said first.
    static func find(_ term: String, kind: MusicEntity.Kind, artist: String?, in library: LibraryStore) -> [MusicEntity] {
        var matches = find(term, in: library, limit: 25).filter { $0.kind == kind }
        if let artist, !artist.isEmpty {
            let by = matches.filter { $0.detail?.localizedCaseInsensitiveContains(artist) == true }
            matches = by + matches.filter { by.firstIndex(of: $0) == nil }
        }
        return matches
    }

    /// For the Shortcuts app's list and Siri's App Shortcut phrases: the
    /// playlists, the albums played lately and the favourites. Only these
    /// match a phrase that names them ("Play Road Trip in Jukebox"); any
    /// other name goes through `find`.
    static func suggestions(in library: LibraryStore) -> [MusicEntity] {
        var all = [MusicEntity.yourStation]
        all += library.playlists.prefix(40).map(MusicEntity.init)
        all += library.recentlyPlayedAlbums.prefix(30).map(MusicEntity.init)
        all += library.favoriteAlbums.prefix(20).map(MusicEntity.init)
        all += library.favoriteArtists.prefix(20).map(MusicEntity.init)
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    /// An entity again from its id, as the library has it now.
    static func entity(id: String, in library: LibraryStore) -> MusicEntity? {
        guard let parsed = MusicEntity.parse(id) else { return nil }
        let itemID = parsed.itemID
        switch parsed.kind {
        case .station: return .yourStation
        case .album: return library.album(id: itemID).map(MusicEntity.init)
        case .artist: return library.artist(id: itemID).map(MusicEntity.init)
        case .song: return library.track(id: itemID).map(MusicEntity.init)
        case .playlist: return library.playlists.first { $0.id == itemID }.map(MusicEntity.init)
        case .genre: return library.genres.first { $0.key == itemID }.map(MusicEntity.init)
        }
    }

    // MARK: Playing

    /// Plays it as its page's Play does: an album, a playlist or a song from
    /// the top; an artist's songs shuffled, as there is no one order to
    /// them; a genre as its station, which is how Jukebox plays a genre
    /// asked for by voice. `asStation`: its station instead, as Start Radio.
    /// What Siri says back.
    static func play(_ entity: MusicEntity, asStation: Bool = false, shuffled: Bool = false, app: AppModel) async -> Answer {
        let library = app.library
        if asStation || entity.kind == .genre || entity.kind == .station {
            guard let seed = await seed(of: entity, in: library) else { return .no(notFound(entity)) }
            return await start(app.radio.station(for: seed), app: app)
        }
        let tracks: [Track]
        let context: QueueContext
        var shuffled = shuffled
        switch entity.kind {
        case .album:
            tracks = library.tracks(inAlbum: entity.itemID)
            context = QueueContext(.album(entity.itemID), title: entity.name)
        case .artist:
            guard let artist = library.artist(id: entity.itemID) else { return .no(notFound(entity)) }
            tracks = library.tracks(by: artist)
            context = QueueContext(.artist(entity.itemID), title: entity.name)
            shuffled = true
        case .playlist:
            guard let playlist = library.playlists.first(where: { $0.id == entity.itemID }),
                  let songs = try? await library.tracks(in: playlist) else { return .no(notFound(entity)) }
            tracks = songs
            context = QueueContext(.playlist(entity.itemID), title: entity.name)
        case .song:
            guard let track = library.track(id: entity.itemID) else { return .no(notFound(entity)) }
            tracks = [track]
            context = QueueContext(.songs, title: entity.name)
        case .genre, .station:
            return .no(notFound(entity))
        }
        return play(tracks, context: context, shuffled: shuffled, app: app)
    }

    /// Everything, or the favourite songs, shuffled, as Shuffle on Songs and
    /// on Favorites.
    static func shuffle(favorites: Bool, app: AppModel) -> Answer {
        let library = app.library
        if favorites {
            return play(library.favoriteTracks, context: QueueContext(.favorites, title: String(localized: "Favorite Songs")),
                        shuffled: true, app: app)
        }
        return play(library.tracks, context: QueueContext(.songs, title: String(localized: "Songs")), shuffled: true, app: app)
    }

    private static func play(_ tracks: [Track], context: QueueContext, shuffled: Bool, app: AppModel) -> Answer {
        guard !tracks.isEmpty else { return .no(String(localized: "There is nothing to play there.")) }
        // Counted as asked of Siri (Stats, play_started `from`), not as the
        // page's kind; read once, by this play.
        Stats.nextFrom = "siri"
        app.player.play(tracks, context: context, shuffled: shuffled)
        // Offline, a song not on the phone does not play, and the player
        // says why.
        guard app.player.context == context else {
            return .no(app.player.errorMessage ?? String(localized: "That could not play."))
        }
        return Answer(played: true, text: String(localized: "Playing \(context.title)."))
    }

    /// `from`: `siri`, or `widget` for the widget's button (WidgetIntents.swift).
    static func start(_ station: Station, app: AppModel, from: String = "siri") async -> Answer {
        Stats.track(.stationStarted, ["seed": Stats.seed(station.seed), "from": from])
        app.radio.start(station)
        // The station chooses its first songs off the main actor.
        for _ in 0..<80 where app.radio.isStarting {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard app.player.context?.station?.id == station.id else {
            return .no(app.player.errorMessage ?? String(localized: "Could not start \(station.title)."))
        }
        return Answer(played: true, text: String(localized: "Playing \(station.title)."))
    }

    private static func seed(of entity: MusicEntity, in library: LibraryStore) async -> StationSeed? {
        switch entity.kind {
        case .station: return .personal
        case .song: return .track(entity.itemID)
        case .album: return .album(entity.itemID)
        case .artist:
            guard let artist = library.artist(id: entity.itemID) else { return nil }
            return .artist(key: artist.key, name: artist.name, id: artist.id)
        case .genre:
            guard let genre = library.genres.first(where: { $0.key == entity.itemID }) else { return nil }
            return .genre(key: genre.key, name: genre.name)
        case .playlist:
            guard let playlist = library.playlists.first(where: { $0.id == entity.itemID }),
                  let tracks = try? await library.tracks(in: playlist), !tracks.isEmpty else { return nil }
            return .collection(id: playlist.id, name: playlist.name, trackIDs: tracks.map(\.id))
        }
    }

    private static func notFound(_ entity: MusicEntity) -> String {
        String(localized: "\(entity.name) is not in your library any more.")
    }

    /// Thumbs up on a station, as Now Playing's; elsewhere the song's heart.
    /// Never a second thumb, which would take the first back.
    static func likeCurrent(app: AppModel) async -> String {
        guard let track = app.player.currentTrack else { return String(localized: "Nothing is playing.") }
        if app.player.context?.isRadio == true {
            if !app.radio.liked.contains(track.id) { app.radio.like(track) }
        } else if !app.library.isFavorite(track.id) {
            await app.library.setFavorite(true, item: .track(track.id))
        }
        return String(localized: "Liked \(track.name).")
    }
}
