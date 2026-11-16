// What a device is playing, kept on the listener's own server so their
// other devices can show it and go on from it. The photographer, 13
// November 2026, of the iPhone's app and Linux's: "ik wil ook dat de ios app
// en de linux app van elkaar kunnen zien wat ze afspelen net als bij spotify
// zodat ik verder kan waar ik gebleven was als ik wegga van mijn pc".
//
// No service of Jukebox's own carries it: the music server every device is
// signed in to already does.
// - A Subsonic server has it as its API's play queue (savePlayQueue,
//   getPlayQueue): the songs, the current one, the position, and who saved
//   it, by the name the client gave (`c`). Measured on Navidrome 0.64.2: one
//   queue a user, `changedBy` the `c` of the save, `changed` the server's
//   own clock, an empty save clears it.
// - Jellyfin has no play queue to keep, and its sessions end with the app.
//   It does keep a user's own preferences for a client by name
//   (/DisplayPreferences/{id}?client=), as jellyfin-web keeps its settings:
//   the state goes there as JSON, under CustomPrefs "playState". Measured on
//   12.4: a POST of {"CustomPrefs": {…}} alone is kept (204), 20 kB of value
//   comes back whole, and it is the user's on every device.

import Foundation

public struct PlayState: Codable, Sendable, Hashable {
    /// The installation that saved it (ClientIdentity.deviceID), so a
    /// device knows its own. A Subsonic server keeps no such id: the
    /// device's name there.
    public var deviceID: String
    /// "Tijmen's iPhone", "tijmen-pc": "Playing on …".
    public var deviceName: String
    public var updatedAt: Date
    /// Nil where the server does not keep it (Subsonic): then only
    /// "left off on", never "playing on".
    public var isPlaying: Bool?
    /// The queue around the current song (`window`), in play order.
    public var trackIDs: [ItemID]
    /// The current song, in `trackIDs`.
    public var index: Int
    /// Seconds into it.
    public var position: TimeInterval
    /// What the queue was started from ("Kid A", "Your Station"); Subsonic
    /// keeps none.
    public var title: String?
    /// The station that played, so it can play on, not only its next songs.
    public var station: Station?
    /// The device this one took the music over from ("Continue Here"), by
    /// its `deviceID`: that device, still playing, then stops — one room's
    /// music moving to another, as Spotify moves it. Nil for music simply
    /// started; and a Subsonic server keeps none, so there the first device
    /// plays on until it is paused by hand.
    public var takenFrom: String?
    /// When it was taken over. A device repeats both in its later saves (so
    /// a save lost under another's is made good), and the device it took
    /// from obeys each taking once, by this: pressing Play there again
    /// later is that device's own music, not something to stop.
    public var takenAt: Date?

    /// How much of a queue is kept: enough to go back a few songs and on
    /// for an album or so, and short enough for a Subsonic server's URL.
    public static let before = 10
    public static let after = 50

    /// `queue` whole, with `index` the current song's place in it: what is
    /// kept is the window around it.
    public init(deviceID: String, deviceName: String, updatedAt: Date = Date(), isPlaying: Bool?,
                queue: [ItemID], index: Int, position: TimeInterval, title: String? = nil,
                station: Station? = nil, takenFrom: String? = nil, takenAt: Date? = nil) {
        let current = min(max(index, 0), max(queue.count - 1, 0))
        let start = max(0, current - Self.before)
        let end = min(queue.count, current + 1 + Self.after)
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.isPlaying = isPlaying
        self.trackIDs = Array(queue[start..<end])
        self.index = current - start
        self.position = max(0, position)
        self.title = title
        self.station = station
        self.takenFrom = takenFrom
        self.takenAt = takenAt
    }

    public var currentTrackID: ItemID? {
        trackIDs.indices.contains(index) ? trackIDs[index] : nil
    }

    /// Saved by this device: nothing to show, nothing to take over.
    public func isOwn(_ identity: ClientIdentity) -> Bool {
        deviceID == identity.deviceID || deviceID == identity.deviceName
    }

    /// Playing there now, as far as can be told: said to be playing, and
    /// saved within the last two minutes (a device saves every half minute
    /// while it plays, and one that lost its network stops saving).
    public func isLive(now: Date = Date()) -> Bool {
        isPlaying == true && now.timeIntervalSince(updatedAt) < 120
    }
}

public extension MusicServer {
    /// For a server that keeps none. Both of Jukebox's do.
    func savePlayState(_ state: PlayState) async throws {
        throw MusicServerError.unsupported(nil)
    }

    func playState() async throws -> PlayState? { nil }
}

// MARK: - Jellyfin

/// /DisplayPreferences' body, as far as Jukebox reads and writes it.
struct JellyfinDisplayPreferences: Codable, Sendable {
    var customPrefs: [String: String?]?

    enum CodingKeys: String, CodingKey {
        case customPrefs = "CustomPrefs"
    }
}

public extension JellyfinClient {
    /// The preferences' id and client: Jukebox's own, beside jellyfin-web's
    /// ("usersettings", "emby").
    private static var playStatePath: String { "/DisplayPreferences/jukebox" }
    private static var playStateKey: String { "playState" }

    private func playStateQuery(_ user: String) -> [URLQueryItem] {
        userQuery(user) + [URLQueryItem(name: "client", value: "Jukebox")]
    }

    /// POST /DisplayPreferences/jukebox?userId=&client=Jukebox.
    func savePlayState(_ state: PlayState) async throws {
        let user = try requireUser()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let json = String(data: try encoder.encode(state), encoding: .utf8) else { return }
        try await send("POST", Self.playStatePath, query: playStateQuery(user),
                       json: JellyfinDisplayPreferences(customPrefs: [Self.playStateKey: json]))
    }

    /// GET the same; nil when nothing was saved, or what was is not a state
    /// (another version's): then there is nothing to go on from.
    func playState() async throws -> PlayState? {
        let user = try requireUser()
        let preferences = try await get(JellyfinDisplayPreferences.self, Self.playStatePath,
                                        query: playStateQuery(user))
        guard let json = preferences.customPrefs?[Self.playStateKey] ?? nil, !json.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(PlayState.self, from: Data(json.utf8))
    }
}

public extension JellyfinServer {
    func savePlayState(_ state: PlayState) async throws {
        try await mapped { try await client.savePlayState(state) }
    }

    func playState() async throws -> PlayState? {
        try await mapped { try await client.playState() }
    }
}

// MARK: - Subsonic

/// getPlayQueue's answer.
struct SubsonicPlayQueue: Decodable {
    var entry: [SubsonicChild]
    /// The current song's id (a number on servers older than ids as text).
    var current: String?
    /// Milliseconds.
    var position: Double?
    var changed: String?
    var changedBy: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        entry = c.lenientList(SubsonicChild.self, SubsonicKey("entry"))
        current = c.lenientString(SubsonicKey("current"))
        position = c.lenientDouble(SubsonicKey("position"))
        changed = c.lenientString(SubsonicKey("changed"))
        changedBy = c.lenientString(SubsonicKey("changedBy"))
    }
}

public extension SubsonicClient {
    /// The name the queue is saved under: `c`, which the server gives back
    /// as `changedBy`. "Jukebox (tijmen-pc)", so the other device can say
    /// where; every other call stays plain "Jukebox".
    private static func savedBy(_ deviceName: String) -> String { "Jukebox (\(deviceName))" }

    private static func deviceName(from changedBy: String) -> String {
        guard changedBy.hasPrefix("Jukebox ("), changedBy.hasSuffix(")") else { return changedBy }
        return String(changedBy.dropFirst("Jukebox (".count).dropLast())
    }

    /// savePlayQueue: the songs, the current one and where it is.
    func savePlayState(_ state: PlayState) async throws {
        var query = state.trackIDs.map { URLQueryItem(name: "id", value: $0) }
        if let current = state.currentTrackID {
            query.append(URLQueryItem(name: "current", value: current))
            query.append(URLQueryItem(name: "position", value: String(Int(state.position * 1000))))
        }
        _ = try await connection.with(clientName: Self.savedBy(state.deviceName)).call("savePlayQueue", query)
    }

    /// getPlayQueue; nil when none is saved. Another app's queue (Feishin's,
    /// Symfonium's) reads as that app's, by its name: the server keeps one a user.
    func playState() async throws -> PlayState? {
        guard let queue = try await connection.call("getPlayQueue").playQueue, !queue.entry.isEmpty else { return nil }
        let ids = queue.entry.compactMap(\.id)
        guard !ids.isEmpty else { return nil }
        let name = Self.deviceName(from: queue.changedBy ?? "")
        var state = PlayState(deviceID: name, deviceName: name,
                              updatedAt: queue.changed.flatMap(JellyfinDate.parse) ?? .distantPast,
                              isPlaying: nil, queue: [], index: 0,
                              position: (queue.position ?? 0) / 1000)
        // As the server has them, not windowed again: it is the window saved.
        state.trackIDs = ids
        state.index = queue.current.flatMap { ids.firstIndex(of: $0) } ?? 0
        return state
    }
}
