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

    public enum Failure: Error, Sendable, Equatable, LocalizedError {
        case invalidKey
        case rateLimited
        case notFound
        case other(String)

        public var errorDescription: String? {
            switch self {
            case .invalidKey: "Last.fm did not accept the API key."
            case .rateLimited: "Last.fm asks to wait a moment."
            case .notFound: "Last.fm does not know that."
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

    /// Whether the key works (one cheap call), for Settings.
    public func validateKey() async -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isWhitespace) else { return false }
        do {
            _ = try await similarArtists(to: "Cher", limit: 1)
            return true
        } catch let failure as Failure {
            switch failure {
            // Asked to wait, or "not found": Last.fm read the key and took it.
            case .rateLimited, .notFound: return true
            case .invalidKey, .other: return false
            }
        } catch {
            // No answer at all says nothing good about the key: Settings
            // shows it as not working, and the listener can try again.
            return false
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
        request.setValue("Jukebox/1.0 (Jellyfin music player for iOS)", forHTTPHeaderField: "User-Agent")
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

    /// - Parameter directory: where the graph and Last.fm's answers are kept
    ///   (the app's Caches).
    public init(directory: URL, lastFM: LastFMClient?) {
        self.directory = directory
        self.lastFM = lastFM
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

    func isFresh(_ fetched: Date) -> Bool {
        let age = currentDate().timeIntervalSince(fetched)
        // A date well ahead of now (the clock was changed) is stale too.
        return age >= -3600 && age < maxAge
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
                case .notFound:
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
