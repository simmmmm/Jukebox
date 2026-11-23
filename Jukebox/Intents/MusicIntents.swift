// Siri's App Shortcuts and the Shortcuts app's actions, on the iPhone, the
// iPad and the Mac: play something of the library, Your Station, a station
// from something, shuffle, like this song. Pause, resume, next and previous
// are the system's already (RemoteCommands), so they are not here.
//
// The types are `nonisolated`: the system makes and reads them off the main
// actor, which is the app's default (project.yml). Their work hops to it
// through Voice, whose calls are the screens' own.
//
// What the system learns of the library: Your Station and the playlists'
// names, for Siri's phrases (Voice.suggestions). Any other name is found
// when it is said, and nothing is donated or put in Spotlight. Like This
// Song writes to the server, so it asks for an unlocked device; playing
// does not, as the car needs it with the phone in a pocket.

import AppIntents
import JukeboxKit

// MARK: The library, as Siri and Shortcuts see it

/// An album, an artist, a playlist, a song, a genre, or Your Station: one
/// type, so "Play X" needs no word for what X is.
nonisolated struct MusicEntity: AppEntity, Hashable {
    enum Kind: String, Sendable {
        case album, artist, playlist, song, genre, station
    }

    /// "album:" and the server's id; a genre by its key.
    let id: String
    let kind: Kind
    let itemID: String
    let name: String
    /// The artist, or what kind of thing it is.
    let detail: String?

    init(kind: Kind, itemID: String, name: String, detail: String?) {
        id = "\(kind.rawValue):\(itemID)"
        self.kind = kind
        self.itemID = itemID
        self.name = name
        self.detail = detail
    }

    init(_ album: Album) { self.init(kind: .album, itemID: album.id, name: album.name, detail: album.artistLine) }
    init(_ artist: Artist) {
        self.init(kind: .artist, itemID: artist.id, name: artist.name, detail: String(localized: "Artist"))
    }
    init(_ playlist: Playlist) {
        self.init(kind: .playlist, itemID: playlist.id, name: playlist.name, detail: String(localized: "Playlist"))
    }
    init(_ track: Track) { self.init(kind: .song, itemID: track.id, name: track.name, detail: track.artistLine) }
    init(_ genre: Genre) { self.init(kind: .genre, itemID: genre.key, name: genre.name, detail: String(localized: "Genre")) }

    static var yourStation: MusicEntity {
        MusicEntity(kind: .station, itemID: "personal", name: String(localized: "Your Station"),
                    detail: String(localized: "Made from what you play"))
    }

    static func parse(_ id: String) -> (kind: Kind, itemID: String)? {
        guard let colon = id.firstIndex(of: ":"), let kind = Kind(rawValue: String(id[..<colon])) else { return nil }
        return (kind, String(id[id.index(after: colon)...]))
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Music") }

    var displayRepresentation: DisplayRepresentation {
        if let detail {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery: MusicQuery { MusicQuery() }
}

/// Names to the library's things, from the library in memory: what Siri
/// heard when it asked "Which one?", and the Shortcuts app's search.
nonisolated struct MusicQuery: EntityStringQuery {
    func entities(for identifiers: [MusicEntity.ID]) async throws -> [MusicEntity] {
        await Self.lookUp(identifiers)
    }

    func entities(matching string: String) async throws -> [MusicEntity] {
        await Self.search(string)
    }

    func suggestedEntities() async throws -> [MusicEntity] {
        await Self.suggestions()
    }

    @MainActor private static func lookUp(_ identifiers: [String]) async -> [MusicEntity] {
        guard let app = await Voice.ready() else { return [] }
        return identifiers.compactMap { Voice.entity(id: $0, in: app.library) }
    }

    @MainActor private static func search(_ string: String) async -> [MusicEntity] {
        guard let app = await Voice.ready() else { return [] }
        return Voice.find(string, in: app.library, limit: 10)
    }

    @MainActor private static func suggestions() async -> [MusicEntity] {
        guard let app = await Voice.ready() else { return [] }
        return Voice.suggestions(in: app.library)
    }
}

// MARK: Actions

nonisolated struct PlayMusicIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play"
    static let description = IntentDescription("Plays an album, artist, playlist, song or genre from your library.")

    @Parameter(title: "Music", requestValueDialog: "What would you like to hear?")
    var music: MusicEntity

    @Parameter(title: "Shuffle", default: false)
    var shuffled: Bool

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$music)") { \.$shuffled }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await Self.run(music, shuffled: shuffled)
        return .result(dialog: "\(said)")
    }

    @MainActor private static func run(_ music: MusicEntity, shuffled: Bool) async -> String {
        guard let app = await Voice.ready() else { return Voice.signInFirst }
        return await Voice.play(music, shuffled: shuffled, app: app).text
    }
}

nonisolated struct StartStationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Start a Station"
    static let description = IntentDescription("Starts a station from an artist, album, song, playlist or genre.")

    @Parameter(title: "From", requestValueDialog: "A station from what?")
    var music: MusicEntity

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Start a station from \(\.$music)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await Self.run(music)
        return .result(dialog: "\(said)")
    }

    @MainActor private static func run(_ music: MusicEntity) async -> String {
        guard let app = await Voice.ready() else { return Voice.signInFirst }
        return await Voice.play(music, asStation: true, app: app).text
    }
}

nonisolated struct PlayYourStationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Your Station"
    static let description = IntentDescription("Plays the station made from what you play.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await Self.run()
        return .result(dialog: "\(said)")
    }

    @MainActor private static func run() async -> String {
        guard let app = await Voice.ready() else { return Voice.signInFirst }
        return await Voice.play(.yourStation, app: app).text
    }
}

nonisolated enum ShuffleScope: String, AppEnum {
    case library
    case favorites

    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Songs") }
    static let caseDisplayRepresentations: [ShuffleScope: DisplayRepresentation] = [
        .library: DisplayRepresentation(title: "My Library", synonyms: ["Everything", "All My Music", "My Music"]),
        .favorites: DisplayRepresentation(title: "My Favorites", synonyms: ["Favorites", "My Favorite Songs"]),
    ]
}

nonisolated struct ShuffleIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Shuffle"
    static let description = IntentDescription("Shuffles every song in your library, or your favorite songs.")

    @Parameter(title: "Songs", default: .library)
    var scope: ShuffleScope

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Shuffle \(\.$scope)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await Self.run(favorites: scope == .favorites)
        return .result(dialog: "\(said)")
    }

    @MainActor private static func run(favorites: Bool) async -> String {
        guard let app = await Voice.ready() else { return Voice.signInFirst }
        return Voice.shuffle(favorites: favorites, app: app).text
    }
}

nonisolated struct LikeSongIntent: AppIntent {
    static let title: LocalizedStringResource = "Like This Song"
    static let description = IntentDescription("Thumbs up for the song on a station; otherwise adds it to your favorites.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await Self.run()
        return .result(dialog: "\(said)")
    }

    @MainActor private static func run() async -> String {
        guard let app = await Voice.ready() else { return Voice.signInFirst }
        return await Voice.likeCurrent(app: app)
    }
}

// MARK: Siri's phrases, without setting anything up

nonisolated struct JukeboxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayYourStationIntent(), phrases: [
            "Play Your Station in \(.applicationName)",
            "Play my station in \(.applicationName)",
            "Start the radio in \(.applicationName)",
        ], shortTitle: "Your Station", systemImageName: "dot.radiowaves.left.and.right")
        // Only the suggested names match a phrase with one in it (Voice's
        // suggestions); "Play something in Jukebox" asks which, and any name
        // in the library answers. On the iPhone, SiriKit's media intent hears
        // every other "Play … in Jukebox" (SiriMedia.swift).
        AppShortcut(intent: PlayMusicIntent(), phrases: [
            "Play \(\.$music) in \(.applicationName)",
            "Play \(\.$music) on \(.applicationName)",
            "Play something in \(.applicationName)",
        ], shortTitle: "Play", systemImageName: "play.fill")
        AppShortcut(intent: StartStationIntent(), phrases: [
            "Start a station from \(\.$music) in \(.applicationName)",
            "Play \(\.$music) radio in \(.applicationName)",
            "Start a station in \(.applicationName)",
        ], shortTitle: "Start a Station", systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: ShuffleIntent(), phrases: [
            "Shuffle \(\.$scope) in \(.applicationName)",
            "Shuffle \(.applicationName)",
        ], shortTitle: "Shuffle", systemImageName: "shuffle")
        AppShortcut(intent: LikeSongIntent(), phrases: [
            "Like this song in \(.applicationName)",
            "I like this song in \(.applicationName)",
        ], shortTitle: "Like This Song", systemImageName: "hand.thumbsup")
    }
}
