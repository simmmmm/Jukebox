// CONTRACT — signatures fixed, bodies the kit agent's (docs/ARCHITECTURE.md).
//
// Last.fm, only when the listener has put their own (free) API key in
// Settings — the photographer chose this, 8 November 2026: the radio works
// from the library alone, and knows who sounds like whom far better with
// Last.fm. Only artist names and track titles leave the phone.
//
// https://ws.audioscrobbler.com/2.0/?method=artist.getsimilar&artist=…&api_key=…&format=json
// Note: artist.getsimilar gives `match` as a string ("0.87"), track.getsimilar
// as a number; an error is {"error": 10, "message": "Invalid API key"} with
// status 200 or 403. LastFM/LastFMAnswers.swift reads all of it leniently;
// LastFM/LastFMStore.swift is what the service keeps on disk.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LastFMClient: Sendable {
    public struct SimilarArtist: Codable, Sendable, Hashable {
        public var name: String
        /// 0 … 1.
        public var match: Double

        public init(name: String, match: Double) {
            self.name = name
            self.match = match
        }
    }

    public struct SimilarTrack: Codable, Sendable, Hashable {
        public var artist: String
        public var title: String
        /// 0 … 1.
        public var match: Double

        public init(artist: String, title: String, match: Double) {
            self.artist = artist
            self.title = title
            self.match = match
        }
    }

    public struct TopTrack: Codable, Sendable, Hashable {
        public var title: String
        public var playcount: Int
        /// 1 is the most played.
        public var rank: Int

        public init(title: String, playcount: Int, rank: Int) {
            self.title = title
            self.playcount = playcount
            self.rank = rank
        }
    }

    /// An artist's tag, as many listeners gave it: 100 for the artist's
    /// strongest, the rest relative to it.
    public struct Tag: Codable, Sendable, Hashable {
        public var name: String
        /// 0 … 100.
        public var count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    /// A song the listener played elsewhere, as Last.fm has it.
    public struct Scrobble: Codable, Sendable, Hashable {
        public var artist: String
        public var title: String
        public var date: Date

        public init(artist: String, title: String, date: Date) {
            self.artist = artist
            self.title = title
            self.date = date
        }
    }

    public enum Failure: Error, Sendable, Equatable, LocalizedError {
        case invalidKey
        case rateLimited
        case notFound
        /// The listener keeps their plays to themselves (error 17).
        case hidden
        case other(String)

        public var errorDescription: String? {
            switch self {
            case .invalidKey: "Last.fm did not accept the API key."
            case .rateLimited: "Last.fm asks to wait a moment."
            case .notFound: "Last.fm does not know that."
            case .hidden: "Last.fm keeps these plays private."
            case let .other(message): message
            }
        }
    }

    public let apiKey: String
    public let transport: any HTTPTransport

    public init(apiKey: String, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.transport = transport
    }

    /// artist.getSimilar, with autocorrect.
    public func similarArtists(to artist: String, limit: Int = 50) async throws -> [SimilarArtist] {
        let body = try await call("artist.getsimilar", [("artist", artist), ("limit", Self.limit(limit))])
        let answer = try Self.decode(LastFMSimilarArtistsAnswer.self, body)
        let items = answer.similarartists?.artist?.items ?? []
        let similar = items.compactMap { item -> SimilarArtist? in
            guard let name = Self.clean(item.name?.value), let match = Self.unit(item.match?.value) else { return nil }
            return SimilarArtist(name: name, match: match)
        }
        return Array(similar.prefix(max(0, limit)))
    }

    /// track.getSimilar, with autocorrect.
    public func similarTracks(artist: String, title: String, limit: Int = 50) async throws -> [SimilarTrack] {
        let body = try await call("track.getsimilar", [("artist", artist), ("track", title), ("limit", Self.limit(limit))])
        let answer = try Self.decode(LastFMSimilarTracksAnswer.self, body)
        let items = answer.similartracks?.track?.items ?? []
        let similar = items.compactMap { item -> SimilarTrack? in
            guard let title = Self.clean(item.name?.value), let artist = Self.clean(item.artist?.value),
                  let match = Self.unit(item.match?.value) else { return nil }
            return SimilarTrack(artist: artist, title: title, match: match)
        }
        return Array(similar.prefix(max(0, limit)))
    }

    /// artist.getTopTracks: an artist page's "Top Songs", by Last.fm's
    /// play counts rather than only this listener's.
    public func topTracks(artist: String, limit: Int = 20) async throws -> [TopTrack] {
        let body = try await call("artist.gettoptracks", [("artist", artist), ("limit", Self.limit(limit))])
        let answer = try Self.decode(LastFMTopTracksAnswer.self, body)
        let items = answer.toptracks?.track?.items ?? []
        var tracks: [TopTrack] = []
        for (position, item) in items.enumerated() {
            guard let title = Self.clean(item.name?.value) else { continue }
            // A rank Last.fm left out is the place in its list.
            let rank = item.attributes?.rank?.value.flatMap(Self.int) ?? position + 1
            let plays = item.playcount?.value.flatMap(Self.int) ?? 0
            tracks.append(TopTrack(title: title, playcount: max(0, plays), rank: max(1, rank)))
        }
        tracks.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.playcount > $1.playcount }
        return Array(tracks.prefix(max(0, limit)))
    }

    /// artist.getTopTags: what listeners call the artist ("shoegaze",
    /// "dream pop"), strongest first. The radio reads them as genres where a
    /// library's own tags say little (docs/RADIO.md, "Last.fm's tags").
    public func topTags(artist: String) async throws -> [Tag] {
        let body = try await call("artist.gettoptags", [("artist", artist)])
        let answer = try Self.decode(LastFMTopTagsAnswer.self, body)
        let items = answer.toptags?.tag?.items ?? []
        return items.compactMap { item -> Tag? in
            guard let name = Self.clean(item.name?.value) else { return nil }
            let count = item.count?.value.flatMap(Self.int) ?? 0
            return Tag(name: name, count: min(100, max(0, count)))
        }
    }

    /// user.getRecentTracks, one page, newest first: what the listener
    /// played since `from`, for the clock (docs/RADIO.md, "Scrobbles").
    /// The song playing now has no date yet and is left out. Read only:
    /// nothing is ever written to Last.fm.
    public func recentTracks(user: String, from: Date? = nil, page: Int = 1,
                             limit: Int = 200) async throws -> (scrobbles: [Scrobble], pages: Int) {
        var parameters = [("user", user), ("limit", String(min(200, max(1, limit)))), ("page", String(max(1, page)))]
        if let from, from.timeIntervalSince1970.isFinite {
            parameters.append(("from", String(Int(max(0, from.timeIntervalSince1970)))))
        }
        let body = try await call("user.getrecenttracks", parameters)
        let answer = try Self.decode(LastFMRecentTracksAnswer.self, body)
        let scrobbles = (answer.recenttracks?.track?.items ?? []).compactMap { item -> Scrobble? in
            guard let title = Self.clean(item.name?.value), let artist = Self.clean(item.artist?.value),
                  let uts = item.date?.uts?.value, uts.isFinite, uts > 0 else { return nil }
            return Scrobble(artist: artist, title: title, date: Date(timeIntervalSince1970: uts))
        }
        let pages = answer.recenttracks?.attributes?.totalPages?.value.flatMap(Self.int) ?? 1
        return (scrobbles, max(1, pages))
    }

    /// What Last.fm said of a username, in the same words on every client.
    public enum UserCheck: Sendable, Equatable {
        case accepted
        case unknown
        case hidden
        /// The key itself was turned down.
        case refusedKey
        case unreachable

        public var problem: String? {
            switch self {
            case .accepted: nil
            case .unknown: "Last.fm has no listener by this name"
            case .hidden: "This listener keeps their plays private on Last.fm"
            case .refusedKey: "Last.fm did not accept the API key"
            case .unreachable: "Could not reach Last.fm; try again"
            }
        }
    }

    /// Whether Last.fm shows this listener's plays (one cheap call, the one
    /// the clock makes), for Settings.
    public func validateUser(_ user: String) async -> UserCheck {
        let name = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return .unknown }
        do {
            _ = try await recentTracks(user: name, limit: 1)
            return .accepted
        } catch let failure as Failure {
            switch failure {
            case .rateLimited: return .accepted
            case .notFound: return .unknown
            case .hidden: return .hidden
            case .invalidKey: return .refusedKey
            case .other: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }

    /// What Last.fm said of a key: Settings keeps it only when accepted, and
    /// says why not otherwise, in the same words on every client.
    public enum KeyCheck: Sendable, Equatable {
        case accepted
        case refused
        /// No answer, or Last.fm's own trouble: nothing said about the key.
        case unreachable

        public var problem: String? {
            switch self {
            case .accepted: nil
            case .refused: "Last.fm did not accept this key"
            case .unreachable: "Could not reach Last.fm; try again"
            }
        }
    }

    /// Whether Last.fm takes the key (one cheap call), for Settings.
    public func validateKey() async -> KeyCheck {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isWhitespace) else { return .refused }
        do {
            _ = try await similarArtists(to: "Cher", limit: 1)
            return .accepted
        } catch let failure as Failure {
            switch failure {
            // Asked to wait, or "not found": Last.fm read the key and took it.
            case .rateLimited, .notFound, .hidden: return .accepted
            case .invalidKey: return .refused
            // A status of 500, an answer that cannot be read, "service
            // offline": Last.fm's trouble, the key may well be good.
            case .other: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }

    // MARK: - The request

    static let endpoint = "https://ws.audioscrobbler.com/2.0/"

    /// RFC 3986's unreserved characters, and everything else escaped. Not
    /// URLComponents' query encoding, which leaves "+" as it is: Last.fm
    /// reads "+" as a space, and "Simon + Garfunkel" must reach it as spelt.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Last.fm takes 1 … 1000.
    static func limit(_ limit: Int) -> String {
        String(min(1000, max(1, limit)))
    }

    func request(_ method: String, _ parameters: [(String, String)]) throws -> URLRequest {
        // autocorrect=1: "Beatles" is answered as The Beatles. format=json:
        // the default is XML.
        let pairs = [("method", method)] + parameters + [("autocorrect", "1"), ("api_key", apiKey), ("format", "json")]
        let query = pairs.map { Self.encode($0.0) + "=" + Self.encode($0.1) }.joined(separator: "&")
        guard let url = URL(string: Self.endpoint + "?" + query) else {
            throw Failure.other("Could not make a Last.fm address.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        // Last.fm asks clients to say who they are.
        request.setValue("Jukebox/1.1 (Jellyfin music player for iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The answer's body, or Last.fm's error as a Failure. A transport error
    /// (no network) is thrown as the transport threw it, so a caller can
    /// tell "Last.fm said no" from "nothing answered".
    func call(_ method: String, _ parameters: [(String, String)]) async throws -> Data {
        let response = try await transport.send(try request(method, parameters))
        // The error object first: Last.fm sends it with 200 as well as 403.
        if let failure = Self.failure(in: response.body) { throw failure }
        if response.status == 429 { throw Failure.rateLimited }
        guard (200..<300).contains(response.status) else {
            throw Failure.other("Last.fm answered with status \(response.status).")
        }
        return response.body
    }

    /// Last.fm's error codes (last.fm/api/errorcodes) as the four cases the
    /// app tells apart.
    static func failure(in body: Data) -> Failure? {
        guard let answer = try? JSONDecoder().decode(LastFMErrorAnswer.self, from: body),
              let code = answer.error?.value.flatMap(int) else { return nil }
        let message = answer.message?.value ?? ""
        switch code {
        // 10 invalid key, 26 suspended key, 4 authentication failed.
        case 10, 26, 4: return .invalidKey
        case 29: return .rateLimited
        // 6: "The artist you supplied could not be found", "Track not found".
        case 6: return .notFound
        // 17: "Login: User required to be logged in", a listener who hides
        // their recent plays.
        case 17: return .hidden
        default: return .other(message.isEmpty ? "Last.fm error \(code)." : message)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ body: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw Failure.other("Last.fm's answer could not be read.")
        }
    }

    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// A match in 0 … 1; nothing when it is missing.
    static func unit(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    static func int(_ value: Double) -> Int? {
        guard value.isFinite, abs(value) < 1e15 else { return nil }
        return Int(value.rounded())
    }
}

/// Builds and keeps the SimilarityGraph: the library's own edges, and
/// Last.fm's for the artists the listener plays most, fetched a few a second
/// (Last.fm asks for at most five), kept on disk for 30 days so a launch
/// asks again only for what is new or stale.
public actor SimilarityService {
    let directory: URL
    let lastFM: LastFMClient?

    // How it paces itself; internal, so the tests can make it quick.
    /// Between two requests: four a second, under Last.fm's five.
    var minimumInterval: Duration = .milliseconds(250)
    /// After "rate limit exceeded": this, then twice this, then the round
    /// stops (`maxAttempts` requests in all).
    var backoff: Duration = .seconds(2)
    var maxAttempts = 3
    /// An answer older than this is asked again (when its artist is among
    /// those enrich is given, or its song starts a station).
    var maxAge: TimeInterval = 30 * 86_400
    var currentDate: @Sendable () -> Date = { Date() }
    /// How many similar artists to ask for: the more, the more of them a
    /// personal library has. 100 is Last.fm's own default, about 40 kB.
    var similarArtistLimit = 100

    private var store = LastFMStore()
    private var loaded = false
    /// Last.fm said the key is not valid: nothing more is asked with it.
    private(set) var keyRejected = false
    private var nextSlot: ContinuousClock.Instant?
    /// Bumped whenever an answer is added, so the graph is made again.
    private var answersVersion = 0
    private var libraryGraph: (index: LibrarySnapshot.Index, graph: SimilarityGraph)?
    private var merged: (index: LibrarySnapshot.Index, version: Int, lastFM: SimilarityGraph, graph: SimilarityGraph)?

    /// The listener's Last.fm name, for their scrobbles; nil or empty: none.
    let user: String?
    /// An artist's tags change slowly: asked again after half a year.
    var tagMaxAge: TimeInterval = 183 * 86_400
    /// What a tag of strength 100 counts against a genre of the files' own
    /// (1); weaker tags by their share of it. Measured in docs/RADIO.md
    /// ("Last.fm's tags").
    var tagWeight = 0.5
    /// The scrobbles kept: the clock's 21-day fade leaves 5% of a play this
    /// old.
    var scrobbleDays = 90.0
    /// At most this many pages of 200 a round.
    var scrobblePages = 10
    /// Asked again after this.
    var scrobbleRefresh: TimeInterval = 6 * 3600
    private var tagsVersion = 0
    private var tagged: (index: LibrarySnapshot.Index, version: Int, snapshot: LibrarySnapshot)?

    /// - Parameter directory: where the graph and Last.fm's answers are kept
    ///   (the app's Caches).
    /// - Parameter user: the listener's Last.fm name, whose scrobbles the
    ///   clock reads (`scrobbles(for:)`); nothing is ever written to Last.fm.
    public init(directory: URL, lastFM: LastFMClient?, user: String? = nil) {
        self.directory = directory
        self.lastFM = lastFM
        self.user = LastFMClient.clean(user)
    }

    // MARK: - Last.fm's tags

    /// The library as the radio reads it: with a key, each artist's Last.fm
    /// tags on disk as extra genres (LibrarySnapshot.init(tracks:artistTags:));
    /// without one, or with no tags yet, `snapshot` itself. Made once per
    /// snapshot and set of tags.
    public func radioSnapshot(for snapshot: LibrarySnapshot) -> LibrarySnapshot {
        loadIfNeeded()
        guard lastFM != nil, !store.tags.isEmpty else { return snapshot }
        if let tagged, tagged.index === snapshot.index, tagged.version == tagsVersion { return tagged.snapshot }
        var artistTags: [String: [LibrarySnapshot.GenreTag]] = [:]
        for (key, answer) in store.tags where snapshot.index.artistByKey[key] != nil {
            let tags = Self.genreTags(answer.tags, artist: answer.name, weight: tagWeight)
            if !tags.isEmpty { artistTags[key] = tags }
        }
        let made = artistTags.isEmpty ? snapshot : LibrarySnapshot(tracks: snapshot.tracks, artistTags: artistTags)
        tagged = (snapshot.index, tagsVersion, made)
        return made
    }

    /// Asks Last.fm for the tags of up to `maxArtists` artists not asked
    /// lately: the `priority` ones first (the most liked), then the rest of
    /// the library, most songs first. Returns `radioSnapshot(for:)` with
    /// them. Stops quietly on a network error.
    public func enrichTags(snapshot: LibrarySnapshot, priority artistKeys: [String],
                           maxArtists: Int = 150) async -> LibrarySnapshot {
        loadIfNeeded()
        guard lastFM != nil, !keyRejected, maxArtists > 0 else { return radioSnapshot(for: snapshot) }
        let index = snapshot.index
        let rest = index.artistKeys.indices
            .sorted { x, y in
                let cx = index.artistOwnTracks[x].count, cy = index.artistOwnTracks[y].count
                return cx != cy ? cx > cy : index.artistKeys[x] < index.artistKeys[y]
            }
            .map { index.artistKeys[$0] }
        var due: [(key: String, name: String)] = []
        var seen = Set<String>()
        for key in artistKeys + rest where seen.insert(key).inserted {
            guard let ref = snapshot.artist(key: key), !LibrarySnapshot.Index.isVarious(ref.name),
                  let name = LastFMClient.clean(ref.name) else { continue }
            if let known = store.tags[key], isFresh(known.fetched, maxAge: tagMaxAge) { continue }
            due.append((key, name))
            if due.count == maxArtists { break }
        }
        var unsaved = 0
        var failuresInARow = 0
        asking: for (key, name) in due {
            if Task.isCancelled { break }
            if let known = store.tags[key], isFresh(known.fetched, maxAge: tagMaxAge) { continue }
            switch await ask({ try await $0.topTags(artist: name) }) {
            case let .answer(tags):
                store.tags[key] = LastFMStore.TagAnswer(name: name, fetched: currentDate(), tags: tags)
                failuresInARow = 0
            case .notFound:
                store.tags[key] = LastFMStore.TagAnswer(name: name, fetched: currentDate(), tags: [])
                failuresInARow = 0
            case .failed:
                failuresInARow += 1
                if failuresInARow >= 3 { break asking }
                continue
            case .unavailable, .rateLimited, .offline:
                break asking
            }
            tagsVersion += 1
            unsaved += 1
            if unsaved >= 20 {
                store.saveTags(to: directory)
                unsaved = 0
            }
        }
        if unsaved > 0 { store.saveTags(to: directory) }
        return radioSnapshot(for: snapshot)
    }

    /// Tags that name no genre: "seen live", "favorites", where the artist
    /// is from, who sings.
    static let notGenres: Set<String> = [
        "seen live", "favorites", "favourites", "favorite", "favourite", "my favorite", "favorite artists",
        "love", "awesome", "beautiful", "amazing", "cool", "good", "albums i own", "spotify", "all",
        "male vocalists", "female vocalists", "male vocalist", "female vocalist", "vocalists",
        "american", "british", "english", "uk", "usa", "canadian", "australian", "german", "dutch",
        "french", "swedish", "norwegian", "japanese", "icelandic", "irish", "scottish", "belgian",
    ]

    /// An artist's tags as genres: the five strongest that name one, at
    /// `weight` × their strength. A decade ("80s") is left to the radio's
    /// own eras; the artist's own name is no genre.
    static func genreTags(_ tags: [LastFMClient.Tag], artist: String, weight: Double) -> [LibrarySnapshot.GenreTag] {
        let own = NameKey.artist(artist)
        var kept: [LibrarySnapshot.GenreTag] = []
        var keys = Set<String>()
        for tag in tags.sorted(by: { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }) where tag.count >= 10 {
            let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            guard !lower.isEmpty, !notGenres.contains(lower), !lower.contains(where: \.isNumber),
                  NameKey.artist(name) != own, keys.insert(NameKey.genre(name)).inserted else { continue }
            // Last.fm writes tags in lower case; a genre the files have
            // keeps the files' spelling (LibrarySnapshot).
            kept.append(LibrarySnapshot.GenreTag(name: lower.capitalized, weight: weight * Double(tag.count) / 100))
            if kept.count == 5 { break }
        }
        return kept
    }

    // MARK: - Scrobbles

    /// The listener's Last.fm plays of the last `scrobbleDays` that are
    /// library songs, as completed plays, oldest first: for the clock
    /// (TasteProfile's `scrobbles`), never written anywhere. Asked again
    /// after `scrobbleRefresh`, only what is newer. Empty without a key or a
    /// name.
    public func scrobbles(for snapshot: LibrarySnapshot) async -> ListeningHistory {
        loadIfNeeded()
        guard let user, lastFM != nil else { return ListeningHistory() }
        // Another name is another listener.
        if let kept = store.scrobbles, kept.user != user { store.scrobbles = nil }
        let now = currentDate()
        let window = now.addingTimeInterval(-scrobbleDays * 86_400)
        if store.scrobbles.map({ !isFresh($0.fetched, maxAge: scrobbleRefresh) }) ?? true {
            await fetchScrobbles(user: user, since: window)
        }
        guard let kept = store.scrobbles else { return ListeningHistory() }
        var events: [PlayEvent] = []
        for play in kept.plays.reversed() where play.date >= window {
            guard let track = snapshot.matchKeyed(artist: play.artist, artistKey: play.artistKey, titleKey: play.titleKey) else { continue }
            events.append(PlayEvent(trackID: track.id, date: play.date, listened: track.duration,
                                    duration: track.duration, outcome: .completed))
        }
        return ListeningHistory(events: events)
    }

    /// The plays since the newest kept (or since `window`), all pages or
    /// none: a page missing would leave a hole the next round never fills.
    private func fetchScrobbles(user: String, since window: Date) async {
        let old = store.scrobbles?.plays.filter { $0.date >= window } ?? []
        let from = max(window, old.first.map { $0.date.addingTimeInterval(1) } ?? window)
        var fresh: [LastFMClient.Scrobble] = []
        var pages = 1
        var page = 1
        while page <= min(pages, scrobblePages) {
            if Task.isCancelled { return }
            let asking = page
            switch await ask({ try await $0.recentTracks(user: user, from: from, page: asking) }) {
            case let .answer(answer):
                fresh += answer.scrobbles
                pages = answer.pages
            case .notFound:
                // No such listener, or plays kept private: nothing, asked
                // again later.
                fresh = []
                pages = 0
            case .failed, .unavailable, .rateLimited, .offline:
                return
            }
            page += 1
        }
        var seen = Set<String>()
        var plays: [LastFMStore.ScrobbleAnswer.Play] = []
        let made = fresh.map { s in
            LastFMStore.ScrobbleAnswer.Play(artist: s.artist, title: s.title, date: s.date,
                                            artistKey: NameKey.artist(s.artist), titleKey: NameKey.title(s.title))
        }
        for play in (made + old).sorted(by: { $0.date > $1.date })
        where play.date >= window && seen.insert("\(play.date.timeIntervalSince1970)|\(play.artistKey)|\(play.titleKey)").inserted {
            plays.append(play)
        }
        store.scrobbles = LastFMStore.ScrobbleAnswer(user: user, fetched: currentDate(), plays: plays)
        store.saveScrobbles(to: directory)
    }

    /// The graph as it is now: the library's edges, plus what is on disk.
    public func graph(for snapshot: LibrarySnapshot) -> SimilarityGraph {
        parts(for: snapshot).graph
    }

    /// Asks Last.fm about up to `maxArtists` artists, most liked first, that
    /// are not on disk or are stale, and returns the graph with them.
    /// Nothing when there is no key. Stops quietly on a network error.
    public func enrich(snapshot: LibrarySnapshot, priority artistKeys: [String],
                       maxArtists: Int = 150) async -> SimilarityGraph {
        loadIfNeeded()
        guard lastFM != nil, !keyRejected, maxArtists > 0 else { return graph(for: snapshot) }

        let due = dueArtists(in: snapshot, priority: artistKeys, max: maxArtists)
        var answered = 0
        var unsaved = 0
        var failuresInARow = 0
        asking: for (key, name) in due {
            if Task.isCancelled { break }
            // Another round may have asked meanwhile: the actor serves other
            // calls while this one waits for Last.fm.
            if let known = store.artists[key], isFresh(known.fetched) { continue }
            let limit = similarArtistLimit
            switch await ask({ try await $0.similarArtists(to: name, limit: limit) }) {
            case let .answer(similar):
                store.artists[key] = LastFMStore.ArtistAnswer(
                    name: name, fetched: currentDate(),
                    similar: similar.map { .init(name: $0.name, match: $0.match, key: NameKey.artist($0.name)) })
                failuresInARow = 0
            case .notFound:
                store.artists[key] = LastFMStore.ArtistAnswer(name: name, fetched: currentDate(), similar: [])
                failuresInARow = 0
            case .failed:
                // Last.fm's own error about one artist: the next may work;
                // three in a row say it is Last.fm that is unwell.
                failuresInARow += 1
                if failuresInARow >= 3 { break asking }
                continue
            case .unavailable, .rateLimited, .offline:
                break asking
            }
            answersVersion += 1
            answered += 1
            unsaved += 1
            // Now and then, so an app closed halfway keeps most of it.
            if unsaved >= 20 {
                store.saveArtists(to: directory)
                unsaved = 0
            }
        }
        if unsaved > 0 { store.saveArtists(to: directory) }
        let parts = parts(for: snapshot)
        if answered > 0 { LastFMStore.saveGraph(parts.lastFM, to: directory) }
        return parts.graph
    }

    /// Last.fm's similar tracks for one track, as library tracks, for a song
    /// station. Empty when there is no key or nothing matches.
    public func similarTracks(to track: Track, in snapshot: LibrarySnapshot) async -> [Neighbor] {
        loadIfNeeded()
        guard lastFM != nil else { return [] }
        // The artist it is filed under, as one name: "MC Polder", not "MC
        // Polder; Lyric Engine", which Last.fm does not know.
        let artistName = snapshot.primaryArtistKey(of: track).flatMap { snapshot.artist(key: $0)?.name }
            ?? track.primaryArtist?.name
        guard let artist = LastFMClient.clean(artistName), let title = LastFMClient.clean(track.name) else { return [] }
        let cacheKey = NameKey.artist(artist) + "|" + NameKey.title(title)

        var answer = store.tracks[cacheKey]
        if answer.map({ !isFresh($0.fetched) }) ?? true {
            var fresh: [LastFMClient.SimilarTrack]?
            switch await ask({ try await $0.similarTracks(artist: artist, title: title, limit: 100) }) {
            case let .answer(similar): fresh = similar
            case .notFound: fresh = []
            // A stale answer is better than none.
            case .failed, .unavailable, .rateLimited, .offline: fresh = nil
            }
            if let fresh {
                let made = LastFMStore.TrackAnswer(
                    trackID: track.id, artist: artist, title: title, fetched: currentDate(),
                    similar: fresh.map { .init(artist: $0.artist, title: $0.title, match: $0.match,
                                               artistKey: NameKey.artist($0.artist), titleKey: NameKey.title($0.title)) })
                answer = made
                store.tracks[cacheKey] = made
                answersVersion += 1
                store.saveTracks(to: directory)
            }
        }
        guard let answer else { return [] }

        var seen: Set<ItemID> = [track.id]
        var neighbors: [Neighbor] = []
        for similar in answer.similar.sorted(by: { $0.match > $1.match }) where similar.match > 0 {
            guard let match = snapshot.matchKeyed(artist: similar.artist, artistKey: similar.artistKey, titleKey: similar.titleKey),
                  seen.insert(match.id).inserted else { continue }
            neighbors.append(Neighbor(key: match.id, weight: similar.match))
        }
        return neighbors
    }

    /// Last.fm's top tracks of an artist, as library tracks, most played
    /// first. Empty when there is no key.
    public func topTracks(artist: ArtistRef, in snapshot: LibrarySnapshot, limit: Int = 10) async -> [Track] {
        loadIfNeeded()
        guard lastFM != nil, limit > 0, let name = LastFMClient.clean(artist.name) else { return [] }
        let artistKey = NameKey.artist(name)

        var answer = store.top[artistKey]
        if answer.map({ !isFresh($0.fetched) }) ?? true {
            // More than asked for: not every song Last.fm knows is in the
            // library.
            let wanted = max(50, limit * 3)
            var fresh: [LastFMClient.TopTrack]?
            switch await ask({ try await $0.topTracks(artist: name, limit: wanted) }) {
            case let .answer(tracks): fresh = tracks
            case .notFound: fresh = []
            case .failed, .unavailable, .rateLimited, .offline: fresh = nil
            }
            if let fresh {
                let made = LastFMStore.TopAnswer(
                    artist: name, fetched: currentDate(),
                    tracks: fresh.map { .init(title: $0.title, playcount: $0.playcount, rank: $0.rank, titleKey: NameKey.title($0.title)) })
                answer = made
                store.top[artistKey] = made
                store.saveTop(to: directory)
            }
        }
        guard let answer else { return [] }

        var seen = Set<ItemID>()
        var tracks: [Track] = []
        for top in answer.tracks.sorted(by: { $0.rank < $1.rank }) {
            guard let match = snapshot.matchKeyed(artist: name, artistKey: artistKey, titleKey: top.titleKey),
                  seen.insert(match.id).inserted else { continue }
            tracks.append(match)
            if tracks.count == limit { break }
        }
        return tracks
    }

    // MARK: - For the tests

    func setPacing(minimumInterval: Duration, backoff: Duration) {
        self.minimumInterval = minimumInterval
        self.backoff = backoff
        nextSlot = nil
    }

    func setDate(_ date: @escaping @Sendable () -> Date) {
        currentDate = date
    }

    func setTagWeight(_ weight: Double) {
        tagWeight = weight
        tagsVersion += 1
    }

    // MARK: - Inside

    /// What one request came to.
    enum Asked<Value: Sendable>: Sendable {
        case answer(Value)
        /// Last.fm does not know it: an answer of nothing, and kept as one.
        case notFound
        /// No key, or Last.fm turned the key down.
        case unavailable
        /// Still "rate limit exceeded" after backing off.
        case rateLimited
        /// Last.fm's own error, for this request.
        case failed
        /// No answer: no network, or the task was cancelled.
        case offline
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        store = LastFMStore.load(from: directory)
    }

    func isFresh(_ fetched: Date, maxAge: TimeInterval? = nil) -> Bool {
        let age = currentDate().timeIntervalSince(fetched)
        // A date well ahead of now (the clock was changed) is stale too.
        return age >= -3600 && age < (maxAge ?? self.maxAge)
    }

    /// One request at Last.fm's pace, backing off when it asks to.
    private func ask<Value: Sendable>(_ work: @Sendable (LastFMClient) async throws -> Value) async -> Asked<Value> {
        guard let lastFM, !keyRejected else { return .unavailable }
        var attempt = 0
        while true {
            do {
                try await waitForSlot()
                return .answer(try await work(lastFM))
            } catch let failure as LastFMClient.Failure {
                switch failure {
                case .invalidKey:
                    keyRejected = true
                    return .unavailable
                case .notFound, .hidden:
                    return .notFound
                case .other:
                    return .failed
                case .rateLimited:
                    attempt += 1
                    guard attempt < maxAttempts else { return .rateLimited }
                    // Every request waits, not only this one: they share the slot.
                    holdRequests(for: backoff * (1 << (attempt - 1)))
                }
            } catch {
                return .offline
            }
        }
    }

    /// Requests start at least `minimumInterval` apart, whoever asks: the
    /// slot is taken before the wait, so two rounds interleaving on the actor
    /// still keep the pace; and counted again from when the wait ended, so
    /// one that woke late does not leave the next less room (measured: 36 ms
    /// between two requests 40 ms apart, before).
    private func waitForSlot() async throws {
        let clock = ContinuousClock()
        let now = clock.now
        let slot = max(now, nextSlot ?? now)
        nextSlot = slot.advanced(by: minimumInterval)
        if slot > now { try await clock.sleep(until: slot, tolerance: nil) }
        try Task.checkCancellation()
        let woke = clock.now.advanced(by: minimumInterval)
        if let next = nextSlot, next < woke { nextSlot = woke }
    }

    private func holdRequests(for duration: Duration) {
        let now = ContinuousClock().now
        nextSlot = max(nextSlot ?? now, now.advanced(by: duration))
    }

    /// The priority artists that are in the library and not freshly asked
    /// about, in the order given, at most `max`.
    private func dueArtists(in snapshot: LibrarySnapshot, priority: [String], max: Int) -> [(key: String, name: String)] {
        var due: [(key: String, name: String)] = []
        var seen = Set<String>()
        for key in priority where seen.insert(key).inserted {
            guard let ref = snapshot.artist(key: key), !LibrarySnapshot.Index.isVarious(ref.name),
                  let name = LastFMClient.clean(ref.name) else { continue }
            if let known = store.artists[key], isFresh(known.fetched) { continue }
            due.append((key, name))
            if due.count == max { break }
        }
        return due
    }

    private func libraryEdges(for snapshot: LibrarySnapshot) -> SimilarityGraph {
        if let libraryGraph, libraryGraph.index === snapshot.index { return libraryGraph.graph }
        let graph = SimilarityGraph.fromLibrary(snapshot)
        libraryGraph = (snapshot.index, graph)
        return graph
    }

    /// Last.fm's edges mapped onto this library, and merged with the
    /// library's own; made once per snapshot and set of answers.
    private func parts(for snapshot: LibrarySnapshot) -> (lastFM: SimilarityGraph, graph: SimilarityGraph) {
        loadIfNeeded()
        if let merged, merged.index === snapshot.index, merged.version == answersVersion {
            return (merged.lastFM, merged.graph)
        }
        let lastFM = lastFMEdges(for: snapshot)
        var graph = libraryEdges(for: snapshot)
        graph.merge(lastFM)
        merged = (snapshot.index, answersVersion, lastFM, graph)
        return (lastFM, graph)
    }

    /// Last.fm's answers as edges between this library's artists and
    /// tracks: from the artist asked about to each similar artist the
    /// library has, weighted by Last.fm's match.
    private func lastFMEdges(for snapshot: LibrarySnapshot) -> SimilarityGraph {
        var graph = SimilarityGraph()
        let index = snapshot.index
        if !store.hasArtistFile, store.artists.isEmpty, let saved = store.savedGraph {
            // Only the graph is left (the answers' file is gone or from
            // another version): its edges between artists still here.
            for (a, edges) in saved.artistEdges where index.artistByKey[a] != nil {
                for (b, weight) in edges where index.artistByKey[b] != nil {
                    if saved.isEnriched(a) {
                        graph.addArtistEdge(a, b, weight: weight)
                    } else {
                        graph.setArtistEdge(a, b, weight: weight)
                    }
                }
            }
        }
        for (asked, answer) in store.artists where index.artistByKey[asked] != nil {
            for similar in answer.similar {
                guard let key = snapshot.matchArtistKeyed(similar.name, key: similar.key), key != asked else { continue }
                graph.addArtistEdge(asked, key, weight: similar.match)
            }
        }
        // Song stations' answers, for tracks still in the library: a song
        // station started again has Last.fm's songs from its first pick.
        for answer in store.tracks.values where index.trackByID[answer.trackID] != nil {
            for similar in answer.similar where similar.match > 0 {
                if let match = snapshot.matchKeyed(artist: similar.artist, artistKey: similar.artistKey, titleKey: similar.titleKey),
                   match.id != answer.trackID {
                    graph.addTrackEdge(from: answer.trackID, to: match.id, weight: similar.match)
                }
            }
        }
        return graph
    }
}

// MARK: - Matching with the keys already made

extension LibrarySnapshot {
    /// `matchArtist(_:)` for a name whose NameKey is known: NameKey is about
    /// 25 µs a name on Linux, and the graph matches every answer again for
    /// every snapshot.
    func matchArtistKeyed(_ name: String, key: String) -> String? {
        if index.artistByKey[key] != nil { return key }
        // "A feat. B" or "A; B": matchArtist splits it (and keys it again,
        // so only for names that are joined).
        guard Index.splitArtistNames(name).count > 1 else { return nil }
        return matchArtist(name)
    }

    /// `match(artist:title:)` with the keys already made.
    func matchKeyed(artist name: String, artistKey: String, titleKey: String) -> Track? {
        guard !titleKey.isEmpty, let key = matchArtistKeyed(name, key: artistKey), let a = index.artistByKey[key] else { return nil }
        let candidates = index.titles.tracks(artist: a, titleKey: titleKey, index: index, tracks: tracks)
        return candidates.min { index.prefer(tracks[$0], over: tracks[$1], $0, $1) }.map { tracks[$0] }
    }
}
