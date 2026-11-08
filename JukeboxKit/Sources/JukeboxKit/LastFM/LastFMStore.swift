// What SimilarityService keeps on disk: Last.fm's answers as they came (by
// the artist or song asked about, with when), and the graph made from them.
// The answers, not only the graph, because what an answer means depends on
// the library: "Portishead" is an edge only once the library has
// Portishead, so the graph is made again from the answers for every
// snapshot, and an artist added later gets the edges Last.fm already gave.
//
// Four files in the service's directory, JSON, each written whole and
// atomically, so a crash leaves the last good one:
// - lastfm-artists.json: artist.getsimilar, by the library's artist key;
// - lastfm-tracks.json: track.getsimilar, by artist key and title key;
// - lastfm-top-tracks.json: artist.gettoptracks, by artist key;
// - lastfm-graph.json: the Last.fm edges as mapped onto the library the
//   last time Last.fm was asked (a SimilarityGraph), read only when the
//   answers themselves are missing.

import Foundation

struct LastFMStore: Sendable {
    struct ArtistAnswer: Codable, Sendable, Hashable {
        struct Similar: Codable, Sendable, Hashable {
            var name: String
            var match: Double
            /// NameKey.artist(name), worked out once when the answer came:
            /// it is about 25 µs a name on Linux, and the graph is made again
            /// from every answer for every snapshot.
            var key: String
        }

        /// The name Last.fm was asked about.
        var name: String
        var fetched: Date
        /// Empty when Last.fm does not know the artist: kept, so it is not
        /// asked again for a month.
        var similar: [Similar]
    }

    struct TrackAnswer: Codable, Sendable, Hashable {
        struct Similar: Codable, Sendable, Hashable {
            var artist: String
            var title: String
            var match: Double
            /// NameKey.artist(artist) and NameKey.title(title), once: a
            /// thousand answers of a hundred songs are matched again for
            /// every snapshot.
            var artistKey: String
            var titleKey: String
        }

        /// The library track it was asked for, for the graph's track edges.
        var trackID: ItemID
        var artist: String
        var title: String
        var fetched: Date
        var similar: [Similar]
    }

    struct TopAnswer: Codable, Sendable, Hashable {
        struct Top: Codable, Sendable, Hashable {
            var title: String
            var playcount: Int
            var rank: Int
            var titleKey: String
        }

        var artist: String
        var fetched: Date
        var tracks: [Top]
    }

    /// The files' own wrapper, so a later version can tell an older file.
    struct File<Value: Codable & Sendable>: Codable, Sendable {
        var version: Int
        var answers: [String: Value]
    }

    static let version = 1
    static let artistsFile = "lastfm-artists.json"
    static let tracksFile = "lastfm-tracks.json"
    static let topTracksFile = "lastfm-top-tracks.json"
    static let graphFile = "lastfm-graph.json"
    /// Song stations are started often and each asks about one song: the
    /// newest this many answers are kept. An answer of 100 similar songs is
    /// about 10 kB and the file is written whole after each new one, so 300
    /// (3 MB) rather than every song ever started.
    static let maxTrackAnswers = 300
    static let maxTopAnswers = 300

    var artists: [String: ArtistAnswer] = [:]
    var tracks: [String: TrackAnswer] = [:]
    var top: [String: TopAnswer] = [:]
    /// The graph as last saved; used only when `artists` could not be read.
    var savedGraph: SimilarityGraph?
    /// Whether lastfm-artists.json was there and read.
    var hasArtistFile = false

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// What is in `directory`; empty parts where a file is missing or does
    /// not read (an older or broken one is as good as none: the answers are
    /// asked for again).
    static func load(from directory: URL) -> LastFMStore {
        var store = LastFMStore()
        let decoder = decoder()
        func read<Value: Codable & Sendable>(_ name: String, as _: Value.Type) -> [String: Value]? {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                  let file = try? decoder.decode(File<Value>.self, from: data),
                  file.version == version else { return nil }
            return file.answers
        }
        if let artists = read(artistsFile, as: ArtistAnswer.self) {
            store.artists = artists
            store.hasArtistFile = true
        }
        store.tracks = read(tracksFile, as: TrackAnswer.self) ?? [:]
        store.top = read(topTracksFile, as: TopAnswer.self) ?? [:]
        if !store.hasArtistFile,
           let data = try? Data(contentsOf: directory.appendingPathComponent(graphFile)) {
            store.savedGraph = try? decoder.decode(SimilarityGraph.self, from: data)
        }
        return store
    }

    func saveArtists(to directory: URL) {
        Self.write(File(version: Self.version, answers: artists), to: directory, name: Self.artistsFile)
    }

    mutating func saveTracks(to directory: URL) {
        tracks = Self.newest(tracks, keep: Self.maxTrackAnswers, date: \.fetched)
        Self.write(File(version: Self.version, answers: tracks), to: directory, name: Self.tracksFile)
    }

    mutating func saveTop(to directory: URL) {
        top = Self.newest(top, keep: Self.maxTopAnswers, date: \.fetched)
        Self.write(File(version: Self.version, answers: top), to: directory, name: Self.topTracksFile)
    }

    static func saveGraph(_ graph: SimilarityGraph, to directory: URL) {
        write(graph, to: directory, name: graphFile)
    }

    /// A cache that cannot be written is a cache that is asked again next
    /// time: nothing to tell the listener.
    static func write<Value: Encodable>(_ value: Value, to directory: URL, name: String) {
        guard let data = try? encoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    static func newest<Value>(_ answers: [String: Value], keep: Int, date: KeyPath<Value, Date>) -> [String: Value] {
        guard answers.count > keep else { return answers }
        let kept = answers.sorted { a, b in
            a.value[keyPath: date] != b.value[keyPath: date] ? a.value[keyPath: date] > b.value[keyPath: date] : a.key < b.key
        }.prefix(keep)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }
}
