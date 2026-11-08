// LRCLIB's answers, kept on disk so a song is not asked for again each time
// it plays: lyrics found (and "instrumental") for 90 days, "not found" for 3,
// because LRCLIB's listeners add lyrics every day and a song missing today
// may be there next week. One small JSON file per song (a song's synced
// lyrics are 2 to 5 kB), named by a hash of the query, which is kept inside
// the file too, so two queries that share a hash never answer for each other.

import Foundation

public actor LyricsCache {
    /// How long a found answer is kept.
    public static let foundLifetime: TimeInterval = 90 * 86_400
    /// How long "not found" is kept.
    public static let notFoundLifetime: TimeInterval = 3 * 86_400

    public let directory: URL
    let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    /// The kept answer, nil when there is none or it is too old (the file
    /// is removed then).
    public func lookup(_ query: LyricsQuery) -> LyricsLookup? {
        let file = url(for: query)
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.version == Entry.currentVersion else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        // Another query with the same hash: not this one's, and left alone.
        guard entry.key == query.cacheKey else { return nil }
        let lifetime = entry.kind == .notFound ? Self.notFoundLifetime : Self.foundLifetime
        let age = now().timeIntervalSince(entry.saved)
        guard age >= 0, age < lifetime, let lookup = entry.lookup else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return lookup
    }

    /// Keeps the answer. A failure to write is not the listener's problem:
    /// the song is asked for again next time.
    public func store(_ lookup: LyricsLookup, for query: LyricsQuery) {
        let entry = Entry(query: query, lookup: lookup, saved: now())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: query), options: .atomic)
    }

    /// Every answer gone.
    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(for query: LyricsQuery) -> URL {
        directory.appendingPathComponent(Self.fileName(query.cacheKey))
    }

    /// FNV-1a, 64 bits, as hex: the same on every run and platform, unlike
    /// Swift's own hashValue, and Foundation has no digest of its own.
    static func fileName(_ key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex + ".json"
    }

    // MARK: - The file

    struct Entry: Codable, Sendable {
        enum Kind: String, Codable, Sendable {
            case synced, plain, instrumental, notFound
        }

        struct Line: Codable, Sendable {
            var start: TimeInterval?
            var text: String
        }

        static let currentVersion = 1

        var version: Int
        var key: String
        var saved: Date
        var kind: Kind
        var lines: [Line]

        init(query: LyricsQuery, lookup: LyricsLookup, saved: Date) {
            version = Self.currentVersion
            key = query.cacheKey
            self.saved = saved
            switch lookup {
            case let .found(lyrics, synced):
                kind = synced ? .synced : .plain
                lines = lyrics.lines.map { Line(start: $0.start, text: $0.text) }
            case .instrumental:
                kind = .instrumental
                lines = []
            case .notFound:
                kind = .notFound
                lines = []
            }
        }

        /// Nil for a file of lyrics without lines, which says nothing.
        var lookup: LyricsLookup? {
            switch kind {
            case .synced, .plain:
                guard !lines.isEmpty else { return nil }
                let lyrics = Lyrics(lines: lines.map { Lyrics.Line(start: $0.start, text: $0.text) })
                return .found(lyrics, synced: kind == .synced)
            case .instrumental:
                return .instrumental
            case .notFound:
                return .notFound
            }
        }
    }
}
