// CONTRACT — signatures fixed, bodies the radio agent's (docs/ARCHITECTURE.md,
// docs/RADIO.md).
//
// The radio is what the photographer cares about most ("ik vind vooral de
// radiofunctie echt belangrijk", 8 November 2026). A station starts from a
// seed — a song, an artist, an album, a genre, a decade, a playlist, or the
// listener's own taste — and plays for as long as it is left on: near the
// seed, never the same artist twice in a row, nothing heard an hour ago,
// and it listens back: a skip, a thumbs down or a song heard to the end
// changes what comes next, at once.
//
// Everything here is a value and runs anywhere; RadioController in the app
// holds one RadioSession and feeds the player from it.

import Foundation

// MARK: - What was heard

public enum PlayOutcome: String, Codable, Sendable, Hashable {
    /// Heard to (near) the end: at least 80%, or all but the last 20 s.
    case completed
    /// Heard for a while, then left: more than a skip, less than a listen.
    case partial
    /// Left within the first 30 s (or half of a short track).
    case skipped
    /// Thumbs up.
    case liked
    /// Thumbs down.
    case disliked

    /// The outcome of a play that ended (not liked or disliked) after
    /// `listened` of `duration` seconds. "All but the last 20 s" only for a
    /// track longer than 40 s: for a shorter one (an interlude) it would make
    /// every play, however short, a completed one.
    public static func of(listened: TimeInterval, duration: TimeInterval) -> PlayOutcome {
        guard duration > 0 else { return listened >= 30 ? .completed : .skipped }
        if listened >= duration * 0.8 || (duration > 40 && listened >= duration - 20) { return .completed }
        if listened < min(30, duration * 0.5) { return .skipped }
        return .partial
    }
}

public struct PlayEvent: Codable, Sendable, Hashable {
    public var trackID: ItemID
    public var date: Date
    /// Seconds heard.
    public var listened: TimeInterval
    /// The track's length, seconds.
    public var duration: TimeInterval
    public var outcome: PlayOutcome
    /// The station it played on, if a radio played it.
    public var stationID: String?
    /// Kept with the event, so history still means something for a track
    /// that has since left the library.
    public var artistKeys: [String]
    public var genreKeys: [String]

    public init(trackID: ItemID, date: Date, listened: TimeInterval, duration: TimeInterval,
                outcome: PlayOutcome, stationID: String? = nil, artistKeys: [String] = [],
                genreKeys: [String] = []) {
        self.trackID = trackID
        self.date = date
        self.listened = listened
        self.duration = duration
        self.outcome = outcome
        self.stationID = stationID
        self.artistKeys = artistKeys
        self.genreKeys = genreKeys
    }

    /// The artist and genre keys as the radio counts them: joined tags
    /// ("A; B", "Rock; Pop") split, as LibrarySnapshot does, so the history
    /// of a song that has left the library still finds its artists.
    public init(track: Track, date: Date, listened: TimeInterval, outcome: PlayOutcome, stationID: String? = nil) {
        let artists = Set(LibrarySnapshot.Index.artistNames(of: track).map { LibrarySnapshot.Index.artistKey($0.name) }.filter { !$0.isEmpty })
        let genres = LibrarySnapshot.Index.splitGenreNames(track.genres).map(NameKey.genre).filter { !$0.isEmpty }
        self.init(trackID: track.id, date: date, listened: listened, duration: track.duration,
                  outcome: outcome, stationID: stationID, artistKeys: artists.sorted(),
                  genreKeys: genres)
    }
}

/// Every play on this device, oldest first, the newest 20 000 kept: what
/// Jellyfin does not keep (skips, thumbs, when), for the radio and the mixes.
public struct ListeningHistory: Codable, Sendable {
    public static let limit = 20_000

    public private(set) var events: [PlayEvent]

    public init(events: [PlayEvent] = []) {
        self.events = Array(events.suffix(Self.limit))
    }

    public mutating func append(_ event: PlayEvent) {
        events.append(event)
        if events.count > Self.limit { events.removeFirst(events.count - Self.limit) }
    }

    /// Tracks played (any outcome) since `date`.
    public func trackIDs(since date: Date) -> Set<ItemID> {
        var ids = Set<ItemID>()
        for event in events.reversed() {
            if event.date < date { break }
            ids.insert(event.trackID)
        }
        return ids
    }

    /// The history kept at `url`; empty when there is none or it cannot be read.
    public static func load(from url: URL) -> ListeningHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(ListeningHistory.self, from: data) else {
            return ListeningHistory()
        }
        return history
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

// MARK: - Taste

/// What the listener likes, from Jellyfin's favourites and play counts and
/// from this device's history (completions, skips, thumbs), for tracks,
/// artists and genres. Recent behaviour weighs more than old.
public struct TasteProfile: Sendable {
    /// Worked out once (Radio/Taste.swift), aligned with the snapshot.
    let data: TasteData

    public init(snapshot: LibrarySnapshot, history: ListeningHistory, now: Date) {
        data = TasteData(snapshot: snapshot, history: history, now: now)
    }

    /// -1 (avoid) … 0 (unknown or neutral) … 1 (loved).
    public func trackAffinity(_ id: ItemID) -> Double {
        data.index.trackByID[id].map { data.trackAffinity[$0] } ?? 0
    }

    public func artistAffinity(_ key: String) -> Double {
        data.index.artistByKey[key].map { data.artistAffinity[$0] } ?? 0
    }

    public func genreAffinity(_ key: String) -> Double {
        data.index.genreByKey[key].map { data.genreAffinity[$0] } ?? 0
    }

    /// 0 never heard … 1 heard a lot (play count and history together).
    public func familiarity(_ id: ItemID) -> Double {
        data.index.trackByID[id].map { data.familiarity[$0] } ?? 0
    }

    /// Artist keys, most liked first.
    public func topArtists(_ count: Int) -> [String] { Array(data.rankedArtists.prefix(max(0, count))) }
    /// Genre keys, most liked first.
    public func topGenres(_ count: Int) -> [String] { Array(data.rankedGenres.prefix(max(0, count))) }
}

// MARK: - Who sounds like whom

public struct Neighbor: Codable, Sendable, Hashable {
    public var key: String
    /// 0 … 1.
    public var weight: Double

    public init(key: String, weight: Double) {
        self.key = key
        self.weight = weight
    }
}

/// Artists (by NameKey) and tracks (by id) and who is near them. Made from
/// the library itself — shared genres, guests on each other's tracks, era —
/// and, when a Last.fm key is set, from Last.fm's similar artists and
/// tracks (SimilarityService), which are far better.
public struct SimilarityGraph: Codable, Sendable {
    /// Artist key → neighbour key → 0 … 1, kept both ways.
    var artistEdges: [String: [String: Double]] = [:]
    /// Track id → similar track id → 0 … 1, one way.
    var trackEdges: [ItemID: [ItemID: Double]] = [:]
    /// Artists that were the first key of `addArtistEdge`: those asked about
    /// elsewhere (Last.fm).
    var enriched: Set<String> = []

    public init() {}

    /// From the library alone (Radio/Similarity.swift: shared genres by how
    /// specific they are, guests, era).
    public static func fromLibrary(_ snapshot: LibrarySnapshot) -> SimilarityGraph {
        build(from: snapshot)
    }

    /// An edge both ways; a second edge between the same two keeps the
    /// heavier, so library and Last.fm edges can be merged in any order.
    /// `a` is the artist that was asked about (Last.fm's artist.getSimilar
    /// for `a` answered `b`): it counts in `enrichedArtistCount`.
    public mutating func addArtistEdge(_ a: String, _ b: String, weight: Double) {
        guard a != b, !a.isEmpty, !b.isEmpty, weight.isFinite, weight > 0 else { return }
        setArtistEdge(a, b, weight: weight)
        enriched.insert(a)
    }

    /// One way: Last.fm's similar tracks are not symmetric.
    public mutating func addTrackEdge(from: ItemID, to: ItemID, weight: Double) {
        guard from != to, weight.isFinite, weight > 0 else { return }
        let w = min(1, weight)
        if (trackEdges[from]?[to] ?? 0) < w { trackEdges[from, default: [:]][to] = w }
    }

    public mutating func merge(_ other: SimilarityGraph) {
        for (a, edges) in other.artistEdges {
            for (b, w) in edges where (artistEdges[a]?[b] ?? 0) < w { artistEdges[a, default: [:]][b] = w }
        }
        for (from, edges) in other.trackEdges {
            for (to, w) in edges where (trackEdges[from]?[to] ?? 0) < w { trackEdges[from, default: [:]][to] = w }
        }
        enriched.formUnion(other.enriched)
    }

    /// Heaviest first.
    public func similarArtists(to key: String, limit: Int = 50) -> [Neighbor] {
        Self.sorted(artistEdges[key], limit: limit)
    }

    /// Heaviest first; the keys are track ids.
    public func similarTracks(to id: ItemID, limit: Int = 50) -> [Neighbor] {
        Self.sorted(trackEdges[id], limit: limit)
    }

    /// How many artists have Last.fm edges: what Settings shows.
    public var enrichedArtistCount: Int { enriched.count }
}

// MARK: - Stations

public enum StationSeed: Hashable, Codable, Sendable {
    case track(ItemID)
    case artist(key: String, name: String, id: ItemID?)
    case album(ItemID)
    case genre(key: String, name: String)
    /// The decade's first year: 1990 for the 1990s.
    case decade(Int)
    /// A playlist or a mix: its tracks are the seed.
    case collection(id: String, name: String, trackIDs: [ItemID])
    /// "Your Station": everything the listener likes, near and far.
    case personal
    /// "Discovery": tracks the listener has rarely or never heard, near
    /// what they like.
    case discovery
    /// "Loved": favourites and what sounds like them.
    case favorites
}

public struct Station: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var seed: StationSeed
    /// "Radiohead Radio", "Your Station", "1990s Radio", "Rock Radio".
    public var title: String
    public var subtitle: String?
    /// Up to four covers, for the station's artwork.
    public var artwork: [Artwork]

    public init(id: String, seed: StationSeed, title: String, subtitle: String? = nil, artwork: [Artwork] = []) {
        self.id = id
        self.seed = seed
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
    }

    /// The station for `seed`, its id, title and artwork from the library.
    public init(seed: StationSeed, snapshot: LibrarySnapshot) {
        let about = Self.describe(seed, in: snapshot)
        self.init(id: Self.id(for: seed), seed: seed, title: about.title, subtitle: about.subtitle,
                  artwork: about.artwork)
    }
}

public struct RadioSettings: Codable, Sendable, Hashable {
    /// 0 = familiar (close to the seed, songs the listener knows) … 1 =
    /// adventurous (further out, more that is new to them).
    public var adventurousness: Double
    /// At least this many tracks between two by one artist.
    public var artistSeparation: Int
    /// A track heard (anywhere) in the last this many hours waits.
    public var noRepeatHours: Double

    public init(adventurousness: Double = 0.35, artistSeparation: Int = 3, noRepeatHours: Double = 12) {
        self.adventurousness = adventurousness
        self.artistSeparation = artistSeparation
        self.noRepeatHours = noRepeatHours
    }
}

/// Why the radio chose a track, in words under it in Up Next.
public enum PickReason: Hashable, Codable, Sendable {
    case seed
    case byArtist(String)
    case similarArtist(String)
    case similarTrack(String)
    case genre(String)
    case era(Int)
    case favorite
    case rediscover
    case discovery
    case becauseYouLiked(String)
    case instantMix

    /// "More by Radiohead", "Because you like Portishead", "From the 1990s".
    public var text: String {
        switch self {
        case .seed: "Where the station started"
        case let .byArtist(name): "More by \(name)"
        case let .similarArtist(name): "Sounds like \(name)"
        case let .similarTrack(title): "Like “\(title)”"
        case let .genre(name): "More \(name)"
        case let .era(decade): "From the \(decade)s"
        case .favorite: "One of your favourites"
        case .rediscover: "Not heard in a while"
        case .discovery: "New to you"
        case let .becauseYouLiked(title): "Because you liked “\(title)”"
        case .instantMix: "From Jellyfin’s mix"
        }
    }
}

public struct RadioPick: Identifiable, Hashable, Sendable {
    public var track: Track
    public var reason: PickReason
    public var score: Double

    public var id: ItemID { track.id }

    public init(track: Track, reason: PickReason, score: Double) {
        self.track = track
        self.reason = reason
        self.score = score
    }
}

public enum RadioFeedback: Hashable, Sendable {
    /// Heard to the end.
    case finished(ItemID)
    /// Left after this many seconds.
    case skipped(ItemID, after: TimeInterval)
    case liked(ItemID)
    /// Thumbs down: skip it now, and less like it from here.
    case disliked(ItemID)
}

/// One station, playing. Hand-outs are remembered: `next` plays a song
/// (any of its recordings) again only after `noRepeatHours` of music, or
/// sooner in a library that has run out, and keeps artists apart;
/// `returnUnplayed` puts back what was handed out but not yet heard, when
/// feedback means the queue ahead should be chosen again.
public struct RadioSession: Sendable {
    public private(set) var station: Station
    public var settings: RadioSettings {
        didSet { engine.settings = settings }
    }
    /// Everything the session knows and has handed out (Radio/RadioEngine.swift).
    var engine: RadioEngine

    /// - Parameters:
    ///   - recentlyPlayed: tracks heard in the last `settings.noRepeatHours`
    ///     anywhere (ListeningHistory.trackIDs(since:)), which wait.
    ///   - randomSeed: the same seed, library and feedback give the same
    ///     station, for the tests.
    public init(station: Station, snapshot: LibrarySnapshot, taste: TasteProfile, graph: SimilarityGraph,
                settings: RadioSettings = RadioSettings(), recentlyPlayed: Set<ItemID> = [],
                randomSeed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.station = station
        self.settings = settings
        engine = RadioEngine(seed: station.seed, snapshot: snapshot, taste: taste, graph: graph,
                             settings: settings, recentlyPlayed: recentlyPlayed, randomSeed: randomSeed)
    }

    /// Tracks from outside the library's own knowledge — Jellyfin's Instant
    /// Mix for the seed, Last.fm's similar tracks — as candidates, raised by
    /// `weight` (0 … 1).
    public mutating func addCandidates(_ ids: [ItemID], weight: Double, reason: PickReason) {
        engine.addCandidates(ids, weight: weight, reason: reason)
    }

    /// The next `count` tracks. Fewer only when the library is out of
    /// tracks that fit (a library of a few songs); then the rules loosen
    /// before the station stops.
    public mutating func next(_ count: Int) -> [RadioPick] {
        engine.next(count)
    }

    /// What the listener did with a track the session handed out.
    public mutating func record(_ feedback: RadioFeedback) {
        engine.record(feedback)
    }

    /// Put back tracks handed out but not heard, so the next `next` chooses
    /// again with what is known now.
    public mutating func returnUnplayed(_ ids: [ItemID]) {
        engine.returnUnplayed(ids)
    }

    /// Every track handed out and not returned, in order.
    public var handedOut: [ItemID] { engine.handed.map { engine.snapshot.tracks[$0].id } }
}
