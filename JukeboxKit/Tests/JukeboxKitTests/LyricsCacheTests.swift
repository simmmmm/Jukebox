// LyricsCache in a directory of its own under the temporary directory: an
// answer kept and read back as it was, found answers for 90 days and "not
// found" for 3, a file of another query or a broken file never answering.

import Foundation
import Testing
@testable import JukeboxKit

/// A clock the test moves.
final class LyricsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var now: Date { lock.withLock { current } }

    func advance(days: Double) {
        advance(seconds: days * 86_400)
    }

    func advance(seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

@Suite("Lyrics: the cache")
struct LyricsCacheTests {
    let query = LyricsQuery(artist: "De Kanaalzangers", title: "Langs het water", album: "Oktoberlicht", duration: 192)

    func withCache(_ body: (LyricsCache, LyricsTestClock, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jukebox-lyrics-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = LyricsTestClock()
        let cache = LyricsCache(directory: directory, now: { clock.now })
        try await body(cache, clock, directory)
    }

    @Test("Synced, plain and instrumental come back as they were stored")
    func hit() async throws {
        try await withCache { cache, _, _ in
            #expect(await cache.lookup(query) == nil)

            let synced = try #require(LRCParser.parse(LyricsFixtures.dutch))
            await cache.store(.found(synced, synced: true), for: query)
            #expect(await cache.lookup(query) == .found(synced, synced: true))

            let plainQuery = LyricsQuery(artist: "De Kanaalzangers", title: "Langs het water", album: nil, duration: 192)
            let plain = try #require(LRCParser.plain(LyricsFixtures.dutchPlain))
            await cache.store(.found(plain, synced: false), for: plainQuery)
            #expect(await cache.lookup(plainQuery) == .found(plain, synced: false))

            let instrumental = LyricsQuery(artist: "De Kanaalzangers", title: "Nachtmuziek", album: "Oktoberlicht", duration: 245)
            await cache.store(.instrumental, for: instrumental)
            #expect(await cache.lookup(instrumental) == .instrumental)

            // Each its own; a song of another length is another song.
            #expect(await cache.lookup(query) == .found(synced, synced: true))
            let longer = LyricsQuery(artist: "De Kanaalzangers", title: "Langs het water", album: "Oktoberlicht", duration: 231)
            #expect(await cache.lookup(longer) == nil)
        }
    }

    @Test("Found answers kept 90 days, then gone from disk too")
    func foundExpires() async throws {
        try await withCache { cache, clock, directory in
            let lyrics = Lyrics(lines: [Lyrics.Line(start: 1, text: "Een")])
            await cache.store(.found(lyrics, synced: true), for: query)
            clock.advance(days: 89)
            #expect(await cache.lookup(query) == .found(lyrics, synced: true))
            clock.advance(days: 2)
            #expect(await cache.lookup(query) == nil)
            let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(left.isEmpty)
        }
    }

    @Test("Not found kept 3 days, so a song is asked for again after")
    func notFoundExpires() async throws {
        try await withCache { cache, clock, _ in
            await cache.store(.notFound, for: query)
            #expect(await cache.lookup(query) == .notFound)
            clock.advance(days: 2.9)
            #expect(await cache.lookup(query) == .notFound)
            clock.advance(days: 0.2)
            #expect(await cache.lookup(query) == nil)
            // Asked again and found: kept for the long time.
            await cache.store(.instrumental, for: query)
            clock.advance(days: 30)
            #expect(await cache.lookup(query) == .instrumental)
        }
    }

    @Test("A newer answer replaces the old; removeAll forgets everything")
    func replaceAndRemove() async throws {
        try await withCache { cache, _, directory in
            await cache.store(.notFound, for: query)
            await cache.store(.instrumental, for: query)
            #expect(await cache.lookup(query) == .instrumental)
            await cache.removeAll()
            #expect(await cache.lookup(query) == nil)
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            // And it keeps working after.
            await cache.store(.notFound, for: query)
            #expect(await cache.lookup(query) == .notFound)
        }
    }

    @Test("A file holding another query's answer, or a broken one, answers nothing")
    func foreignAndBroken() async throws {
        try await withCache { cache, _, directory in
            let other = LyricsQuery(artist: "Het Andere Koor", title: "Elders", album: nil, duration: 100)
            await cache.store(.instrumental, for: other)
            // As if the two shared a hash: other's file under query's name.
            let otherFile = directory.appendingPathComponent(LyricsCache.fileName(other.cacheKey))
            let queryFile = directory.appendingPathComponent(LyricsCache.fileName(query.cacheKey))
            try FileManager.default.copyItem(at: otherFile, to: queryFile)
            #expect(await cache.lookup(query) == nil)
            // Left alone: it is the other one's.
            #expect(await cache.lookup(other) == .instrumental)

            try Data("{not json".utf8).write(to: queryFile)
            #expect(await cache.lookup(query) == nil)
            #expect(!FileManager.default.fileExists(atPath: queryFile.path))
        }
    }

    @Test("File names: a stable hash of the key, the same on every run")
    func fileNames() {
        // FNV-1a's own value for "", and for "a".
        #expect(LyricsCache.fileName("") == "cbf29ce484222325.json")
        #expect(LyricsCache.fileName("a") == "af63dc4c8601ec8c.json")
        #expect(LyricsCache.fileName(query.cacheKey) != LyricsCache.fileName(query.cacheKey + "x"))
    }

    @Test("Titles of slashes, dots, line ends, emoji and 10 000 letters: one short file each, read back")
    func awkwardNames() async throws {
        try await withCache { cache, _, directory in
            let queries = [
                LyricsQuery(artist: "AC/DC", title: "../../etc/passwd", album: "/", duration: 200),
                LyricsQuery(artist: "Sigur Rós", title: "( )", album: "Ágætis byrjun: \"Live\"\n\t*?<>|", duration: 300),
                LyricsQuery(artist: "宇多田ヒカル", title: "First Love 🎹", album: nil, duration: 260),
                LyricsQuery(artist: "A", title: String(repeating: "Long ", count: 2_000), album: String(repeating: "é", count: 5_000),
                            duration: 100),
            ]
            for (index, query) in queries.enumerated() {
                await cache.store(.found(Lyrics(lines: [Lyrics.Line(start: Double(index), text: "\(index)")]), synced: true),
                                  for: query)
            }
            for (index, query) in queries.enumerated() {
                #expect(await cache.lookup(query) == .found(Lyrics(lines: [Lyrics.Line(start: Double(index), text: "\(index)")]),
                                                            synced: true))
            }
            // All in the directory itself, named by the hash alone.
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(names.count == queries.count)
            for name in names {
                #expect(name.count == 21)
                #expect(name.hasSuffix(".json"))
                #expect(name.dropLast(5).allSatisfy { $0.isHexDigit })
            }
        }
    }

    @Test("To the second: 90 days less one is kept, 90 days is not; a clock set back forgets")
    func boundaries() async throws {
        try await withCache { cache, clock, _ in
            // Whole seconds, so the sums are exact.
            await cache.store(.instrumental, for: query)
            clock.advance(seconds: 90 * 86_400 - 1)
            #expect(await cache.lookup(query) == .instrumental)
            clock.advance(seconds: 1)
            #expect(await cache.lookup(query) == nil)

            await cache.store(.notFound, for: query)
            clock.advance(seconds: 3 * 86_400 - 1)
            #expect(await cache.lookup(query) == .notFound)
            clock.advance(seconds: 1)
            #expect(await cache.lookup(query) == nil)

            // Saved "in the future" (the phone's clock was wrong, then put
            // right): not trusted, asked again.
            await cache.store(.instrumental, for: query)
            clock.advance(days: -1)
            #expect(await cache.lookup(query) == nil)
        }
    }

    @Test("A song's file is small")
    func size() async throws {
        try await withCache { cache, _, directory in
            let synced = try #require(LRCParser.parse(LyricsFixtures.dutch))
            await cache.store(.found(synced, synced: true), for: query)
            let file = directory.appendingPathComponent(LyricsCache.fileName(query.cacheKey))
            let bytes = try Data(contentsOf: file).count
            print("LYRICS-MEASURE cache file for a 21-line song: \(bytes) bytes")
            #expect(bytes < 4_000)
        }
    }
}
