// Several accounts as one server (docs/MULTI-SERVER.md, "Step 1"): a
// MusicServer made of the accounts that are on, so the stores, which
// already hold `any MusicServer`, need not know there are several. The
// photographer, 21 November 2026: "ik zou niet weten waarom we die beperking
// moeten hebben als er meer mogelijk zijn".
//
// Every id it hands out is tagged with its account (AccountTag); a call by
// an id reads the tag, asks that member with the server's own id and tags
// what comes back. A call for everything asks every member at once and
// joins the answers in the members' order.
//
// With one account on the app does not make one of these: today's path,
// untagged. Nothing in the app makes one yet (steps 3 and 4).

import Foundation

public struct MergedServer: MusicServer {
    /// The accounts, in their order in Settings (the last word on which
    /// copy plays, docs/MULTI-SERVER.md section 4).
    public let members: [any MusicServer]
    private let tags: [AccountTag]

    /// At least one member, and no account twice: two members with one tag
    /// could not be told apart.
    public init(members: [any MusicServer]) {
        let tags = members.map { AccountTag($0.credentials) }
        precondition(!members.isEmpty, "a merged server needs a member")
        precondition(Set(tags).count == tags.count, "an account is in a merged server once")
        self.members = members
        self.tags = tags
    }

    // MARK: Which member

    /// The member an id belongs to; nil for an untagged id or another
    /// account's.
    public func member(for id: ItemID) -> (any MusicServer)? {
        route(id)?.server
    }

    /// What the account of `id` can do: how a per-item action is offered
    /// (`library.can(.rating, for: id)`, step 3). Empty for an id of no
    /// member.
    public func capabilities(for id: ItemID) -> Set<ServerCapability> {
        route(id)?.server.capabilities ?? []
    }

    private func route(_ id: ItemID) -> (index: Int, tag: AccountTag, server: any MusicServer, bare: ItemID)? {
        guard let (tag, bare) = AccountTag.split(id), let index = tags.firstIndex(of: tag) else { return nil }
        return (index, tag, members[index], bare)
    }

    /// For the calls that throw: an id of no member is one the merged
    /// server does not have.
    private func routed(_ id: ItemID) throws -> (index: Int, tag: AccountTag, server: any MusicServer, bare: ItemID) {
        guard let route = route(id) else { throw MusicServerError.notFound }
        return route
    }

    private static func strip(_ tag: AccountTag) -> (ItemID) -> ItemID {
        { tag.unwrap($0) ?? $0 }
    }

    /// For the calls that cannot throw (URLs, reports): an id of no member
    /// goes to the first as it is. It is a bug upstream when it happens; a
    /// URL that the server answers 404 says so where a crash would not.
    private func routeOrFirst(_ id: ItemID) -> (tag: AccountTag, server: any MusicServer) {
        if let route = route(id) { return (route.tag, route.server) }
        return (tags[0], members[0])
    }

    /// Every member at once, each answer tagged, joined in the members'
    /// order. A member that fails is left out, so a silent server does not
    /// hide the others' music; when all fail, the first one's error.
    private func everyMember<T: Sendable>(
        _ ask: @escaping @Sendable (any MusicServer, AccountTag) async throws -> [T]
    ) async throws -> [T] {
        let answers = await withTaskGroup(of: (Int, Result<[T], any Error>).self) { group in
            for (index, server) in members.enumerated() {
                let tag = tags[index]
                group.addTask {
                    do { return (index, .success(try await ask(server, tag))) } catch { return (index, .failure(error)) }
                }
            }
            var answers = [Result<[T], any Error>?](repeating: nil, count: members.count)
            for await (index, answer) in group { answers[index] = answer }
            return answers.compactMap { $0 }
        }
        var joined: [T] = []
        var firstError: (any Error)?
        var anyAnswered = false
        for answer in answers {
            switch answer {
            case let .success(items): joined += items; anyAnswered = true
            case let .failure(error): if firstError == nil { firstError = error }
            }
        }
        if !anyAnswered, let firstError { throw firstError }
        return joined
    }

    // MARK: Who: the calls that do not fit
    //
    // A merged server has no one kind, session, play state or download
    // policy. These answer with the first member's, so a store that has not
    // learnt of members yet goes on as with one account; steps 3 and 6 stop
    // using them on a merged server and ask `members`. So do the casts to
    // JellyfinServer, which a MergedServer never passes:
    // `YourYearLoader`, `PlayOn` (three), `RemoteControl` (two) and
    // `AppModel.refreshServer`.

    public var kind: ServerKind { members[0].kind }
    public var credentials: ServerCredentials { members[0].credentials }
    public func currentCapabilities() async throws -> Set<ServerCapability> {
        try await members[0].currentCapabilities()
    }
    public func signOut() async { await members[0].signOut() }
    public func downloadsAllowed() async throws -> Bool { try await members[0].downloadsAllowed() }

    /// The first member's ids go bare, so its older builds still read its
    /// own songs; another member's stay tagged (docs/MULTI-SERVER.md
    /// section 6 builds on this).
    public func savePlayState(_ state: PlayState) async throws {
        try await members[0].savePlayState(state.retagged(Self.strip(tags[0])))
    }

    /// A bare id is the first member's; a tagged one stays as it was saved.
    public func playState() async throws -> PlayState? {
        let tag = tags[0]
        return try await members[0].playState()?.retagged { AccountTag.split($0) == nil ? tag.wrap($0) : $0 }
    }

    /// Everything any account can do: what the app offers somewhere. Per
    /// item it is `capabilities(for:)`.
    public var capabilities: Set<ServerCapability> {
        members.reduce(into: []) { $0.formUnion($1.capabilities) }
    }

    // MARK: The library, all of it

    /// `progress` is told the sum over the members, so the bar fills once.
    public func allTracks(progress: (@Sendable (Int, Int) -> Void)?) async throws -> [Track] {
        let sum = ProgressSum(count: members.count, progress: progress)
        let tags = tags
        return try await everyMember { server, tag in
            try await server.allTracks(progress: sum.member(tags.firstIndex(of: tag) ?? 0)).map { $0.retagged(tag.wrap) }
        }
    }

    public func allAlbums() async throws -> [Album] {
        try await everyMember { server, tag in try await server.allAlbums().map { $0.retagged(tag.wrap) } }
    }

    public func allArtists() async throws -> [Artist] {
        try await everyMember { server, tag in try await server.allArtists().map { $0.retagged(tag.wrap) } }
    }

    public func playlists() async throws -> [Playlist] {
        try await everyMember { server, tag in try await server.playlists().map { $0.retagged(tag.wrap) } }
    }

    public func genres() async throws -> [Genre] {
        try await everyMember { server, tag in try await server.genres().map { $0.retagged(tag.wrap) } }
    }

    /// Each member's `limit` of each kind, joined.
    public func search(_ term: String, limit: Int) async throws -> SearchResults {
        let found = try await everyMember { (server, tag) async throws -> [SearchResults] in
            [try await server.search(term, limit: limit).retagged(tag.wrap)]
        }
        return SearchResults(artists: found.flatMap(\.artists), albums: found.flatMap(\.albums),
                             tracks: found.flatMap(\.tracks), playlists: found.flatMap(\.playlists))
    }

    // MARK: One item

    public func track(id: ItemID) async throws -> Track {
        let r = try routed(id)
        return try await r.server.track(id: r.bare).retagged(r.tag.wrap)
    }

    public func album(id: ItemID) async throws -> Album {
        let r = try routed(id)
        return try await r.server.album(id: r.bare).retagged(r.tag.wrap)
    }

    public func artist(id: ItemID) async throws -> Artist {
        let r = try routed(id)
        return try await r.server.artist(id: r.bare).retagged(r.tag.wrap)
    }

    public func albumTracks(albumID: ItemID) async throws -> [Track] {
        let r = try routed(albumID)
        return try await r.server.albumTracks(albumID: r.bare).map { $0.retagged(r.tag.wrap) }
    }

    // MARK: Changes

    public func setFavorite(_ isFavorite: Bool, item: ItemRef) async throws {
        let r = try routed(item.id)
        try await r.server.setFavorite(isFavorite, item: Self.bare(item, r.bare))
    }

    public func setRating(_ stars: Int, item: ItemRef) async throws {
        let r = try routed(item.id)
        try await r.server.setRating(stars, item: Self.bare(item, r.bare))
    }

    private static func bare(_ item: ItemRef, _ id: ItemID) -> ItemRef {
        switch item {
        case .track: .track(id)
        case .album: .album(id)
        case .artist: .artist(id)
        }
    }

    public func playlistTracks(playlistID: ItemID) async throws -> [Track] {
        let r = try routed(playlistID)
        return try await r.server.playlistTracks(playlistID: r.bare).map { $0.retagged(r.tag.wrap) }
    }

    /// On the server its songs are on. No server holds another's ids, so
    /// songs of two accounts throw: the store splits them first (step 4,
    /// and the open question of a playlist across servers). An empty one
    /// goes to the first account.
    public func createPlaylist(name: String, trackIDs: [ItemID]) async throws -> ItemID {
        let index = try trackIDs.first.map { try routed($0).index } ?? 0
        let bare = try Self.bare(trackIDs, of: tags[index])
        return tags[index].wrap(try await members[index].createPlaylist(name: name, trackIDs: bare))
    }

    /// Only the playlist's own account's songs: another's would be an id
    /// its server never heard of, so it throws, as `createPlaylist` does.
    public func addToPlaylist(playlistID: ItemID, trackIDs: [ItemID]) async throws {
        let r = try routed(playlistID)
        try await r.server.addToPlaylist(playlistID: r.bare, trackIDs: try Self.bare(trackIDs, of: r.tag))
    }

    private static func bare(_ ids: [ItemID], of tag: AccountTag) throws -> [ItemID] {
        try ids.map { id in
            guard let bare = tag.unwrap(id) else { throw MusicServerError.unsupported(nil) }
            return bare
        }
    }

    /// Entry ids are the server's own and never tagged
    /// (`Track.playlistEntryID`).
    public func removeFromPlaylist(playlistID: ItemID, entryIDs: [String]) async throws {
        let r = try routed(playlistID)
        try await r.server.removeFromPlaylist(playlistID: r.bare, entryIDs: entryIDs)
    }

    public func movePlaylistEntry(playlistID: ItemID, entryID: String, to index: Int) async throws {
        let r = try routed(playlistID)
        try await r.server.movePlaylistEntry(playlistID: r.bare, entryID: entryID, to: index)
    }

    public func deletePlaylist(id: ItemID) async throws {
        let r = try routed(id)
        try await r.server.deletePlaylist(id: r.bare)
    }

    // MARK: What only the server knows

    public func similarArtists(artistID: ItemID, limit: Int) async throws -> [Artist] {
        let r = try routed(artistID)
        return try await r.server.similarArtists(artistID: r.bare, limit: limit).map { $0.retagged(r.tag.wrap) }
    }

    /// The seed's account. A genre the library split out of a joined tag
    /// has no id, so no account: the first that mixes at all is asked.
    public func instantMix(from seed: MixSeed, limit: Int) async throws -> [Track] {
        let id: ItemID? = switch seed {
        case let .track(id), let .album(id), let .artist(id), let .playlist(id): id
        case let .genre(_, id): id
        }
        let index: Int
        let bareSeed: MixSeed
        if let id {
            let r = try routed(id)
            index = r.index
            bareSeed = switch seed {
            case .track: .track(r.bare)
            case .album: .album(r.bare)
            case .artist: .artist(r.bare)
            case .playlist: .playlist(r.bare)
            case let .genre(name, _): .genre(name: name, id: r.bare)
            }
        } else {
            guard let first = members.firstIndex(where: { $0.capabilities.contains(.instantMix) }) else {
                throw MusicServerError.unsupported(.instantMix)
            }
            index = first
            bareSeed = seed
        }
        return try await members[index].instantMix(from: bareSeed, limit: limit).map { $0.retagged(tags[index].wrap) }
    }

    /// The artist's account. By name alone (no id), the first account with
    /// `.topSongs` that knows any of the artist's songs.
    public func topSongs(of artist: ArtistRef, limit: Int) async throws -> [Track] {
        if let id = artist.id {
            let r = try routed(id)
            return try await r.server.topSongs(of: ArtistRef(id: r.bare, name: artist.name), limit: limit)
                .map { $0.retagged(r.tag.wrap) }
        }
        var lastError: (any Error)?
        for (index, server) in members.enumerated() where server.capabilities.contains(.topSongs) {
            do {
                let songs = try await server.topSongs(of: artist, limit: limit)
                if !songs.isEmpty { return songs.map { $0.retagged(tags[index].wrap) } }
            } catch { lastError = error }
        }
        if let lastError { throw lastError }
        return []
    }

    public func lyrics(for track: Track) async throws -> Lyrics? {
        let r = try routed(track.id)
        return try await r.server.lyrics(for: track.retagged(Self.strip(r.tag)))
    }

    public func shareURL(for id: ItemID, tracks: [ItemID]) async throws -> URL {
        let r = try routed(id)
        // Songs of another account cannot be in this server's share.
        return try await r.server.shareURL(for: r.bare, tracks: tracks.compactMap(r.tag.unwrap))
    }

    // MARK: Playing

    public func streamURL(for track: Track, quality: StreamQuality, playSessionID: String) -> URL {
        let (tag, server) = routeOrFirst(track.id)
        return server.streamURL(for: track.retagged(Self.strip(tag)), quality: quality, playSessionID: playSessionID)
    }

    public func castURL(for track: Track) -> CastStream {
        let (tag, server) = routeOrFirst(track.id)
        return server.castURL(for: track.retagged(Self.strip(tag)))
    }

    public func downloadURL(for track: Track, quality: DownloadQuality) -> URL {
        let (tag, server) = routeOrFirst(track.id)
        return server.downloadURL(for: track.retagged(Self.strip(tag)), quality: quality)
    }

    public func artworkURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        let (tag, server) = routeOrFirst(artwork.itemID)
        return server.artworkURL(artwork.retagged(Self.strip(tag)), maxPixelSize: maxPixelSize)
    }

    public func castArtworkURL(_ artwork: Artwork, maxPixelSize: Int) -> URL {
        let (tag, server) = routeOrFirst(artwork.itemID)
        return server.castArtworkURL(artwork.retagged(Self.strip(tag)), maxPixelSize: maxPixelSize)
    }

    /// Every member's: the queue may hold songs of each.
    public func prepareCast() async throws {
        for member in members { try await member.prepareCast() }
    }

    /// Told to the server the song was streamed from, only: no play is told
    /// twice.
    public func report(_ event: PlaybackEvent, _ report: PlaybackReport) async {
        let (tag, server) = routeOrFirst(report.trackID)
        await server.report(event, report.retagged(Self.strip(tag)))
    }
}

/// The members' progress added up: each member's last (done, total), told
/// as one sum.
private final class ProgressSum: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [(done: Int, total: Int)]
    private let progress: (@Sendable (Int, Int) -> Void)?

    init(count: Int, progress: (@Sendable (Int, Int) -> Void)?) {
        parts = Array(repeating: (0, 0), count: count)
        self.progress = progress
    }

    /// What member `index` is told to tell; nil when nobody listens.
    func member(_ index: Int) -> (@Sendable (Int, Int) -> Void)? {
        guard progress != nil else { return nil }
        return { done, total in self.set(index, done, total) }
    }

    func set(_ index: Int, _ done: Int, _ total: Int) {
        // Told under the lock, so two members' sums never arrive out of
        // order and the last one told is the whole.
        lock.lock()
        defer { lock.unlock() }
        parts[index] = (done, total)
        let sum = parts.reduce((0, 0)) { ($0.0 + $1.done, $0.1 + $1.total) }
        progress?(sum.0, sum.1)
    }
}
