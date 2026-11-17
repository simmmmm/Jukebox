// Plex Media Server as a MusicServer, through the server's own HTTP API with
// `Accept: application/json`. The owner, 17 November 2026: "emby en plex
// kunnen beide toch". docs/SERVERS.md ("Plex") has the map and what was
// measured on Plex Media Server 1.43.5 (dev/plex-test-server.sh, unclaimed,
// the made-up library):
//
// - The library is every music section's (type "artist"): tracks are type
//   10, albums 9, artists 8, paged with X-Plex-Container-Start and -Size.
//   Tracks carry no genres: they take their album's.
// - A song streams and downloads as its file (`Part.key`, plain HTTP with
//   Content-Length and ranges, so gapless and normalisation work as with a
//   file anywhere); converted, through the universal music transcoder as a
//   progressive MP3 (`start.mp3`, protocol http), never HLS.
// - A favourite is a rating of 10, five stars ("/:/rate").
// - A play counts at `.played`, by "/:/scrobble"; the timeline tells the
//   server what plays, without the song's `duration`: with it, a timeline
//   at the end counts a play of its own (measured: twice with our
//   scrobble), without it none did, stopped at the end or past it. A stop
//   is sent at 0 s besides.
// - A playlist holds a song once: Plex drops a second copy (measured), so
//   `playlistItemID` names each place.
// - What Plex has no call for is off: mixes, similar artists, top songs,
//   loudness, and the play state kept from one device to another.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PlexServer: MusicServer {
    public let credentials: ServerCredentials
    let connection: PlexConnection

    /// What every Plex server has once signed in (docs/SERVERS.md).
    public static let capabilities: Set<ServerCapability> = [
        .lyrics, .syncedLyrics, .playlistReorder, .playbackTimeline, .lastPlayed,
    ]

    public init(credentials: ServerCredentials, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.credentials = credentials
        let token: String? = if case let .plexToken(token) = credentials.secret { token } else { nil }
        connection = PlexConnection(baseURL: credentials.serverURL, token: token, identity: identity,
                                    transport: transport)
    }

    public var kind: ServerKind { .plex }
    public var capabilities: Set<ServerCapability> { credentials.capabilities }

    // MARK: Who

    /// The server answers this session (the library, which takes the
    /// token: /identity answers anyone); what it can do does not change
    /// with its version.
    public func currentCapabilities() async throws -> Set<ServerCapability> {
        _ = try await connection.container("/library/sections")
        return Self.capabilities
    }

    /// Plex has no sign-out for a token: the app forgets it.
    public func signOut() async {}

    // MARK: The library

    /// The music sections' keys: a server may keep more than one.
    func sections() async throws -> [String] {
        try await connection.container("/library/sections").directories
            .filter { $0.type == "artist" }.compactMap(\.key)
    }

    /// Every item of a type in every music section, 1000 a page.
    func all(_ type: Int) async throws -> [PlexItem] {
        var items: [PlexItem] = []
        for section in try await sections() {
            var start = 0
            while true {
                let page = try await connection.container("/library/sections/\(PlexConnection.segment(section))/all", [
                    URLQueryItem(name: "type", value: String(type)),
                    URLQueryItem(name: "X-Plex-Container-Start", value: String(start)),
                    URLQueryItem(name: "X-Plex-Container-Size", value: "1000"),
                ])
                items += page.metadata
                start += page.metadata.count
                if page.metadata.isEmpty || start >= (page.totalSize ?? start) { break }
            }
        }
        return items
    }

    /// Every track, with its album's genres (Plex keeps them on the album).
    public func allTracks(progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track] {
        async let albums = all(9)
        let items = try await all(10)
        let genres = Dictionary(try await albums.compactMap { album in album.ratingKey.map { ($0, album.genres) } },
                                uniquingKeysWith: { first, _ in first })
        progress?(items.count, items.count)
        return items.compactMap { item in
            var track = item.track
            if let album = track?.albumID, let found = genres[album] { track?.genres = found }
            return track
        }
    }

    public func allAlbums() async throws -> [Album] {
        try await all(9).compactMap(\.album)
    }

    public func allArtists() async throws -> [Artist] {
        try await all(8).compactMap(\.artist)
    }

    public func playlists() async throws -> [Playlist] {
        try await connection.container("/playlists", [URLQueryItem(name: "playlistType", value: "audio")])
            .metadata.compactMap(\.playlist)
    }

    /// The albums' genres, counted: Plex's own genre lists are per section
    /// and give no counts.
    public func genres() async throws -> [Genre] {
        var counts: [String: Int] = [:]
        for album in try await all(9) {
            for genre in album.genres { counts[genre, default: 0] += 1 }
        }
        return counts.map { Genre(id: $0.key, name: $0.key, albumCount: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: One item

    func item(_ id: ItemID) async throws -> PlexItem {
        guard let item = try await connection.container("/library/metadata/\(PlexConnection.segment(id))").metadata.first
        else { throw MusicServerError.notFound }
        return item
    }

    public func track(id: ItemID) async throws -> Track {
        guard let track = try await item(id).track else { throw MusicServerError.notFound }
        return track
    }

    public func album(id: ItemID) async throws -> Album {
        guard let album = try await item(id).album else { throw MusicServerError.notFound }
        return album
    }

    public func artist(id: ItemID) async throws -> Artist {
        guard let artist = try await item(id).artist else { throw MusicServerError.notFound }
        return artist
    }

    /// The album's children, in disc and track order.
    public func albumTracks(albumID: ItemID) async throws -> [Track] {
        try await connection.container("/library/metadata/\(PlexConnection.segment(albumID))/children")
            .metadata.compactMap(\.track)
            .sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
    }

    /// /hubs/search: one hub a kind, `limit` in each.
    public func search(_ term: String, limit: Int) async throws -> SearchResults {
        let hubs = try await connection.container("/hubs/search", [
            URLQueryItem(name: "query", value: term), URLQueryItem(name: "limit", value: String(limit)),
        ]).hubs
        let items = hubs.flatMap(\.metadata)
        return SearchResults(artists: items.compactMap(\.artist), albums: items.compactMap(\.album),
                             tracks: items.compactMap(\.track), playlists: items.compactMap(\.playlist))
    }

    // MARK: Changes

    /// Five stars, or none: the rating is the favourite (docs/SERVERS.md).
    public func setFavorite(_ isFavorite: Bool, item: ItemRef) async throws {
        try await connection.send("PUT", "/:/rate", [
            URLQueryItem(name: "key", value: item.id),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "rating", value: isFavorite ? "10" : "-1"),
        ])
    }

    /// No stars of their own: Plex's one rating is the favourite here (five
    /// stars), so a rating of three would take the favourite away.
    public func setRating(_ stars: Int, item: ItemRef) async throws {
        throw MusicServerError.unsupported(.rating)
    }

    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        try await connection.container("/playlists/\(PlexConnection.segment(playlistID))/items").metadata.compactMap(\.track)
    }

    /// `uri` names the songs on this server; 100 to a request, as Jellyfin's
    /// ids go. A song already there is dropped by Plex.
    func songs(_ ids: some Collection<ItemID>) -> URLQueryItem {
        URLQueryItem(name: "uri", value: "server://\(credentials.serverID)/com.plexapp.plugins.library/library/metadata/"
            + ids.joined(separator: ","))
    }

    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        let created = try await connection.container("/playlists", [
            URLQueryItem(name: "type", value: "audio"), URLQueryItem(name: "title", value: name),
            URLQueryItem(name: "smart", value: "0"), songs(trackIDs.prefix(JellyfinClient.idsPerRequest)),
        ], method: "POST")
        guard let id = created.metadata.first?.ratingKey else { throw MusicServerError.decoding("no playlist") }
        try await addToPlaylist(playlistID: id, trackIDs: Array(trackIDs.dropFirst(JellyfinClient.idsPerRequest)))
        return id
    }

    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        var rest = trackIDs[...]
        while !rest.isEmpty {
            try await connection.send("PUT", "/playlists/\(PlexConnection.segment(playlistID))/items",
                                      [songs(rest.prefix(JellyfinClient.idsPerRequest))])
            rest = rest.dropFirst(JellyfinClient.idsPerRequest)
        }
    }

    /// One DELETE a place; a place already gone is skipped.
    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        for entry in entryIDs {
            do {
                try await connection.send("DELETE", "/playlists/\(PlexConnection.segment(playlistID))/items/\(PlexConnection.segment(entry))")
            } catch MusicServerError.notFound {}
        }
    }

    /// Plex moves a place to after another (none: to the top). `index` is
    /// where it ends up, as on Jellyfin: the place before it there is the
    /// one it goes after.
    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        var entries = try await playlistTracks(playlistID: playlistID).compactMap(\.playlistEntryID)
        guard let from = entries.firstIndex(of: entryID) else { throw MusicServerError.notFound }
        entries.remove(at: from)
        let to = min(max(0, index), entries.count)
        try await connection.send("PUT", "/playlists/\(PlexConnection.segment(playlistID))/items/\(PlexConnection.segment(entryID))/move",
                                  to == 0 ? [] : [URLQueryItem(name: "after", value: entries[to - 1])])
    }

    public func deletePlaylist(id: ItemID) async throws {
        try await connection.send("DELETE", "/playlists/\(PlexConnection.segment(id))")
    }

    // MARK: What only the server knows

    /// Plex's similar artists are names from its online agent, not items.
    public func similarArtists(artistID: ItemID, limit: Int) async throws -> [Artist] {
        throw MusicServerError.unsupported(.similarArtists)
    }

    /// Plex's sonic mixes need Plex Pass and an analysed library: off.
    public func instantMix(from seed: MixSeed, limit: Int) async throws -> [Track] {
        throw MusicServerError.unsupported(.instantMix)
    }

    public func topSongs(of artist: ArtistRef, limit: Int) async throws -> [Track] {
        throw MusicServerError.unsupported(.topSongs)
    }

    /// A lyrics stream of the song's file (streamType 4: a sidecar .lrc or
    /// .txt, or Plex Pass's LyricFind), as text; nil when it has none.
    public func lyrics(for track: Track) async throws -> Lyrics? {
        let streams = try await item(track.id).media.flatMap(\.parts).flatMap(\.streams)
        guard let key = streams.first(where: { $0.streamType == 4 && $0.key != nil })?.key else { return nil }
        let text = String(decoding: try await connection.send("GET", key), as: UTF8.self)
        return LRCParser.parse(text) ?? LRCParser.plain(text)
    }

    // MARK: Playing

    /// The file as it is; converted only when capped or not playable here
    /// (docs/SERVERS.md, "Plex: streaming").
    public func streamURL(for track: Track, quality: StreamQuality, playSessionID: String) -> URL {
        if let kbps = quality.maxBitrate.map({ $0 / 1000 }) {
            return transcoded(track, kbps: kbps, session: playSessionID)
        }
        return file(track) ?? transcoded(track, kbps: 320, session: playSessionID)
    }

    public func downloadURL(for track: Track, quality: DownloadQuality) -> URL {
        switch quality {
        case .original: file(track, download: true) ?? transcoded(track, kbps: 320, session: download(track, quality))
        case .high: transcoded(track, kbps: 256, session: download(track, quality))
        case .normal: transcoded(track, kbps: 128, session: download(track, quality))
        }
    }

    /// The file, when it plays here as it is.
    func file(_ track: Track, download: Bool = false) -> URL? {
        guard let key = track.fileKey, !SubsonicClient.cannotPlay(track) else { return nil }
        return connection.url(key, download ? [URLQueryItem(name: "download", value: "1")] : [], withToken: true)
    }

    /// The universal music transcoder, as one progressive MP3 at `kbps` at
    /// most: a file under the cap is copied, not converted again. Plex's
    /// Generic profile has no target for music (it answered 400), so the
    /// request adds one: MP3 over plain HTTP.
    func transcoded(_ track: Track, kbps: Int, session: String) -> URL {
        connection.url("/music/:/transcode/universal/start.mp3", [
            URLQueryItem(name: "path", value: "/library/metadata/\(track.id)"),
            URLQueryItem(name: "mediaIndex", value: "0"), URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "directPlay", value: "0"), URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "maxAudioBitrate", value: String(kbps)),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: connection.identity.deviceID),
            URLQueryItem(name: "X-Plex-Product", value: connection.identity.clientName),
            URLQueryItem(name: "X-Plex-Platform", value: "Generic"),
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value:
                "add-transcode-target(type=musicProfile&context=streaming&protocol=http&container=mp3&audioCodec=mp3)"),
        ], withToken: true)
    }

    /// One transcoder session a song and quality: the same URL each time,
    /// and no new session left on the server by asking again.
    func download(_ track: Track, _ quality: DownloadQuality) -> String {
        "jukebox-download-\(track.id)-\(quality.rawValue)"
    }

    /// Whoever may play a song may have its file: Plex's `allowSync` is
    /// its own downloads (Plex Pass's), false on a server without it. Asked
    /// of the library all the same, as a switch of accounts asks it whether
    /// the server answers and takes the token.
    public func downloadsAllowed() async throws -> Bool {
        _ = try await connection.container("/library/sections")
        return true
    }

    /// /photo/:/transcode, within `maxPixelSize` square. `tag` is the
    /// image's path ("/library/metadata/149/thumb/1794902352": the number
    /// changes with the image).
    public func artworkURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        connection.url("/photo/:/transcode", [
            URLQueryItem(name: "width", value: String(maxPixelSize)),
            URLQueryItem(name: "height", value: String(maxPixelSize)),
            URLQueryItem(name: "url", value: artwork.tag ?? "/library/metadata/\(artwork.itemID)/thumb"),
        ], withToken: true)
    }

    /// The timeline is what the server shows as playing; the scrobble is
    /// the play. No `duration` and a stop at 0 s: a timeline that says the
    /// song reached its end counts a play of its own (measured on 1.43.5),
    /// which `.played` has counted already.
    public func report(_ event: PlaybackEvent, _ report: PlaybackReport) async {
        let state: String
        var time = report.position
        switch event {
        case .played:
            try? await connection.send("GET", "/:/scrobble", [
                URLQueryItem(name: "key", value: report.trackID),
                URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            ], timeout: 15)
            return
        case .nowPlaying, .progress: state = report.isPaused ? "paused" : "playing"
        case .stopped:
            state = "stopped"
            time = 0
        }
        try? await connection.send("GET", "/:/timeline", [
            URLQueryItem(name: "ratingKey", value: report.trackID),
            URLQueryItem(name: "key", value: "/library/metadata/\(report.trackID)"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "time", value: String(Int(time * 1000))),
        ], timeout: 15)
    }

    // MARK: From one device to another

    /// Plex keeps no state of a client's for others to read: the handoff
    /// is off on Plex.
    public func savePlayState(_ state: PlayState) async throws {
        throw MusicServerError.unsupported(nil)
    }

    public func playState() async throws -> PlayState? { nil }
}

// MARK: - Talking to Plex

/// One server's address and token, and every request to it: Plex's
/// headers (the client's id is the installation's, ClientIdentity.deviceID),
/// JSON, and its errors as MusicServerError.
struct PlexConnection: Sendable {
    let baseURL: URL
    let token: String?
    let identity: ClientIdentity
    let transport: any HTTPTransport

    static func segment(_ text: String) -> String { JellyfinClient.escape(text) }

    /// The base and a path (a Plex key is a path); the token in the query
    /// for a URL a player or a download fetches without headers.
    func url(_ path: String, _ query: [URLQueryItem] = [], withToken: Bool = false) -> URL {
        var string = baseURL.absoluteString
        while string.hasSuffix("/") { string.removeLast() }
        string += path.hasPrefix("/") ? path : "/" + path
        var query = query
        if withToken, let token, !token.isEmpty { query.append(URLQueryItem(name: "X-Plex-Token", value: token)) }
        if !query.isEmpty {
            string += (path.contains("?") ? "&" : "?") + query.map {
                "\(JellyfinClient.escape($0.name))=\(JellyfinClient.escape($0.value ?? ""))"
            }.joined(separator: "&")
        }
        return URL(string: string) ?? baseURL
    }

    /// Plex's own headers, for its server and for plex.tv alike.
    static func headers(_ identity: ClientIdentity, token: String?) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Plex-Product": identity.clientName,
            "X-Plex-Version": identity.clientVersion,
            "X-Plex-Client-Identifier": identity.deviceID,
            "X-Plex-Device-Name": identity.deviceName,
        ]
        if let token, !token.isEmpty { headers["X-Plex-Token"] = token }
        return headers
    }

    @discardableResult
    func send(_ method: String, _ path: String, _ query: [URLQueryItem] = [],
              timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url(path, query))
        request.httpMethod = method
        request.timeoutInterval = timeout
        for (name, value) in Self.headers(identity, token: token) { request.setValue(value, forHTTPHeaderField: name) }
        return try await Self.send(request, transport)
    }

    func container(_ path: String, _ query: [URLQueryItem] = [], method: String = "GET") async throws -> PlexContainer {
        try Self.decode(PlexAnswer.self, try await send(method, path, query)).container ?? PlexContainer()
    }

    /// 401 is a token not taken, 403 a user not allowed, 404 nothing there.
    static func send(_ request: URLRequest, _ transport: any HTTPTransport) async throws -> Data {
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MusicServerError.transport(error.localizedDescription)
        }
        switch response.status {
        case 200..<300: return response.body
        case 401: throw MusicServerError.unauthorized
        case 403: throw MusicServerError.notAllowed
        case 404: throw MusicServerError.notFound
        default: throw MusicServerError.server(status: response.status, message: nil)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MusicServerError.decoding("\(T.self)")
        }
    }
}

// MARK: - What Plex answers

/// `{"MediaContainer": {…}}`.
struct PlexAnswer: Decodable {
    var container: PlexContainer?

    enum CodingKeys: String, CodingKey { case container = "MediaContainer" }
}

/// Read leniently, as Subsonic's answers are: an id may be a number or a
/// string (Plex sends both, measured), and one odd field costs that field.
struct PlexContainer: Decodable {
    var metadata: [PlexItem] = []
    var directories: [PlexItem] = []
    var hubs: [PlexHub] = []
    var totalSize: Int?
    var machineIdentifier: String?
    var version: String?
    var friendlyName: String?

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        metadata = c.lenientList(PlexItem.self, SubsonicKey("Metadata"))
        directories = c.lenientList(PlexItem.self, SubsonicKey("Directory"))
        hubs = c.lenientList(PlexHub.self, SubsonicKey("Hub"))
        totalSize = c.lenientInt(SubsonicKey("totalSize"))
        machineIdentifier = c.lenientString(SubsonicKey("machineIdentifier"))
        version = c.lenientString(SubsonicKey("version"))
        friendlyName = c.lenientString(SubsonicKey("friendlyName"))
    }
}

struct PlexHub: Decodable {
    var metadata: [PlexItem]

    init(from decoder: any Decoder) throws {
        metadata = try decoder.container(keyedBy: SubsonicKey.self).lenientList(PlexItem.self, SubsonicKey("Metadata"))
    }
}

/// A track, album, artist, playlist or section, as Plex lists them all.
struct PlexItem: Decodable {
    var ratingKey, key, type, title: String?
    var parentRatingKey, parentTitle, grandparentRatingKey, grandparentTitle, originalTitle: String?
    var thumb, parentThumb, composite: String?
    var index, parentIndex, year, parentYear, leafCount, childCount, viewCount: Int?
    var playlistItemID: String?
    /// Milliseconds.
    var duration: Double?
    var userRating: Double?
    /// Seconds since 1970.
    var addedAt, lastViewedAt: Double?
    var smart: Bool?
    var genres: [String]
    var media: [PlexMedia]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        func string(_ name: String) -> String? { c.lenientString(SubsonicKey(name)).flatMap { $0.isEmpty ? nil : $0 } }
        func int(_ name: String) -> Int? { c.lenientInt(SubsonicKey(name)) }
        func double(_ name: String) -> Double? { c.lenientDouble(SubsonicKey(name)) }
        ratingKey = string("ratingKey"); key = string("key"); type = string("type"); title = string("title")
        parentRatingKey = string("parentRatingKey"); parentTitle = string("parentTitle")
        grandparentRatingKey = string("grandparentRatingKey"); grandparentTitle = string("grandparentTitle")
        originalTitle = string("originalTitle")
        thumb = string("thumb"); parentThumb = string("parentThumb"); composite = string("composite")
        index = int("index"); parentIndex = int("parentIndex"); year = int("year"); parentYear = int("parentYear")
        leafCount = int("leafCount"); childCount = int("childCount"); viewCount = int("viewCount")
        playlistItemID = string("playlistItemID")
        duration = double("duration"); userRating = double("userRating")
        addedAt = double("addedAt"); lastViewedAt = double("lastViewedAt")
        smart = c.lenientBool(SubsonicKey("smart"))
        genres = c.lenientList(PlexTag.self, SubsonicKey("Genre")).compactMap(\.tag)
        media = c.lenientList(PlexMedia.self, SubsonicKey("Media"))
    }

    static func date(_ seconds: Double?) -> Date? {
        seconds.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    }

    /// Five stars: what Plex's apps show as the most a song can be liked.
    var isFavorite: Bool { (userRating ?? 0) >= 10 }

    var track: Track? {
        guard type == "track", let ratingKey else { return nil }
        let albumArtist = grandparentTitle.map { ArtistRef(id: grandparentRatingKey, name: $0) }
        // The track's own artist tag, when it is not the album's (a guest,
        // "Amsterdam Strings; Willow & Pine"): Plex keeps it as a name only.
        let artists = originalTitle.map { [ArtistRef(id: nil, name: $0)] } ?? albumArtist.map { [$0] } ?? []
        let part = media.first?.parts.first
        var track = Track(id: ratingKey, name: title ?? "", albumID: parentRatingKey, albumName: parentTitle,
                          artists: artists, albumArtist: albumArtist, genres: genres,
                          year: parentYear ?? year, trackNumber: index, discNumber: parentIndex,
                          duration: (duration ?? 0) / 1000, imageTag: thumb, albumImageTag: parentThumb,
                          isFavorite: isFavorite, playCount: viewCount ?? 0,
                          lastPlayed: Self.date(lastViewedAt), dateAdded: Self.date(addedAt),
                          playlistEntryID: playlistItemID,
                          container: part?.container ?? media.first?.container)
        track.fileKey = part?.key
        return track
    }

    var album: Album? {
        guard type == "album", let ratingKey else { return nil }
        return Album(id: ratingKey, name: title ?? "",
                     artists: parentTitle.map { [ArtistRef(id: parentRatingKey, name: $0)] } ?? [],
                     year: year, genres: genres, imageTag: thumb, trackCount: leafCount,
                     isFavorite: isFavorite, dateAdded: Self.date(addedAt), playCount: viewCount ?? 0,
                     lastPlayed: Self.date(lastViewedAt))
    }

    var artist: Artist? {
        guard type == "artist", let ratingKey else { return nil }
        return Artist(id: ratingKey, name: title ?? "", imageTag: thumb, genres: genres, isFavorite: isFavorite,
                      albumCount: childCount)
    }

    /// A smart playlist is the server's rule, not a list to edit.
    var playlist: Playlist? {
        guard type == "playlist", let ratingKey else { return nil }
        return Playlist(id: ratingKey, name: title ?? "", imageTag: composite ?? thumb, trackCount: leafCount,
                        duration: duration.map { $0 / 1000 }, dateAdded: Self.date(addedAt),
                        isReadOnly: smart ?? false)
    }
}

struct PlexTag: Decodable {
    var tag: String?
}

struct PlexMedia: Decodable {
    var container: String?
    var parts: [PlexPart]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        container = c.lenientString(SubsonicKey("container"))
        parts = c.lenientList(PlexPart.self, SubsonicKey("Part"))
    }
}

struct PlexPart: Decodable {
    var key: String?
    var container: String?
    var streams: [PlexStream]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        key = c.lenientString(SubsonicKey("key"))
        container = c.lenientString(SubsonicKey("container"))
        streams = c.lenientList(PlexStream.self, SubsonicKey("Stream"))
    }
}

/// A stream of a file: 2 its sound, 4 its lyrics (with a `key` to fetch).
struct PlexStream: Decodable {
    var streamType: Int?
    var key: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        streamType = c.lenientInt(SubsonicKey("streamType"))
        key = c.lenientString(SubsonicKey("key"))
    }
}
