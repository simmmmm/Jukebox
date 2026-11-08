// CONTRACT — signatures fixed, bodies the mixes agent's (docs/ARCHITECTURE.md).
// How they are made: Mixes/MixModel.swift and Mixes/MixBuilders.swift;
// measured by MixesEvaluationTests and MixesPerformanceTests.
//
// Home's playlists that Jukebox makes up itself ("op de homepage wil ik dat
// de app zelf leuke playlists verzint", the photographer, 8 November 2026):
// daily mixes around what the listener plays, new arrivals, what they have
// not heard in a while, deep cuts of artists they like, their favourites,
// decades and genres. The same for a whole day (seeded by the date), new the
// next morning, so a mix one liked at breakfast is still there at lunch.

import Foundation

public enum MixKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// "Daily Mix 1…6": one per cluster of artists the listener plays.
    case daily
    /// "New Arrivals": tracks from albums added in the last weeks.
    case newArrivals
    /// "Rediscover": tracks once played a lot, not in months.
    case rediscover
    /// "Deep Cuts": rarely or never played tracks by artists the listener likes.
    case deepCuts
    /// "Loved Tracks": favourites, shuffled.
    case favorites
    /// "On Repeat": what the listener plays most, lately.
    case onRepeat
    /// "1990s Mix" and so on.
    case decade
    /// "Rock Mix" and so on, for the listener's top genres.
    case genre
}

public struct Mix: Identifiable, Hashable, Sendable {
    /// Stable for the day: kind, key and date.
    public var id: String
    public var kind: MixKind
    /// "Daily Mix 1", "New Arrivals", "1990s Mix".
    public var title: String
    /// "Radiohead, Portishead and more".
    public var subtitle: String
    public var tracks: [Track]
    /// Four covers for the collage, from the mix's own tracks.
    public var artwork: [Artwork]
    /// The station that plays on from this mix ("Start Radio").
    public var stationSeed: StationSeed

    public init(id: String, kind: MixKind, title: String, subtitle: String, tracks: [Track],
                artwork: [Artwork], stationSeed: StationSeed) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.tracks = tracks
        self.artwork = artwork
        self.stationSeed = stationSeed
    }

    public var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
}

public struct MixGenerator: Sendable {
    /// The taste, the plays of the last month and the day, worked out once
    /// (Mixes/MixModel.swift); the mixes are made from it in
    /// Mixes/MixBuilders.swift.
    let model: MixModel

    public init(snapshot: LibrarySnapshot, taste: TasteProfile, history: ListeningHistory,
                graph: SimilarityGraph, now: Date, calendar: Calendar = .current) {
        model = MixModel(snapshot: snapshot, taste: taste, history: history, graph: graph, now: now, calendar: calendar)
    }

    /// Home's "Made for You", best first: the daily mixes, then the others
    /// that have enough tracks (25–50 each; a mix of fewer than 8 is left out).
    public func mixes() -> [Mix] {
        guard !model.snapshot.isEmpty else { return [] }
        let kinds = MixKind.allCases
        let others = model.otherMixes().sorted { x, y in
            if x.want != y.want { return x.want > y.want }
            let kx = kinds.firstIndex(of: x.mix.kind) ?? 0, ky = kinds.firstIndex(of: y.mix.kind) ?? 0
            return kx != ky ? kx < ky : x.mix.id < y.mix.id
        }
        return model.dailyMixes() + others.map(\.mix)
    }

    /// Stations to suggest on Home and Radio: Your Station, Discovery,
    /// Loved (when there are favourites), the top artists' stations, the top
    /// genres' and the decades the library has most of.
    public func suggestedStations() -> [Station] {
        guard !model.snapshot.isEmpty else { return [] }
        return model.stations()
    }
}
