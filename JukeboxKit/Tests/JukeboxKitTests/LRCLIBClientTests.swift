// LRCLIBClient against LRCLIB's answers as LyricsFixtures writes them
// (lrclib.net is not reachable from where these run; LRCLIBLiveTests asks
// the real one where it is): the exact requests and the User-Agent LRCLIB
// asks for, /api/get found, its 404 followed by /api/search and the best
// record by length, nothing close enough, instrumental, failures, and the
// query cleaned of what a library's tags carry.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Lyrics: LRCLIB client")
struct LRCLIBClientTests {
    let userAgent = LRCLIBClient.userAgent(appVersion: "1.0")

    func client(_ transport: LRCLIBMockTransport) -> LRCLIBClient {
        LRCLIBClient(userAgent: userAgent, transport: transport)
    }

    func search(_ records: [[String: Any]]) -> Data {
        LyricsFixtures.json(records)
    }

    @Test("The requests: /api/get with all four fields, then /api/search, escaped, with the User-Agent")
    func requests() async throws {
        let mock = LRCLIBMockTransport(get: nil)
        let found = try await client(mock).lyrics(artist: "Simon + Garfunkel", title: "Rain & Shine",
                                                  album: "Wet / Dry", duration: 201.6)
        #expect(found == .notFound)
        let sent = mock.requests
        #expect(sent.count == 2)

        let get = try #require(sent.first)
        #expect(get.url?.absoluteString ==
            "https://lrclib.net/api/get?track_name=Rain%20%26%20Shine&artist_name=Simon%20%2B%20Garfunkel&album_name=Wet%20%2F%20Dry&duration=202")
        #expect(get.httpMethod == "GET")
        #expect(get.value(forHTTPHeaderField: "User-Agent") == "Jukebox/1.0 (https://github.com/simmmmm/Jukebox)")
        #expect(get.timeoutInterval == 8)
        #expect(get.lrclibQuery == ["track_name": "Rain & Shine", "artist_name": "Simon + Garfunkel",
                                    "album_name": "Wet / Dry", "duration": "202"])

        let search = sent[1]
        #expect(search.url?.absoluteString ==
            "https://lrclib.net/api/search?track_name=Rain%20%26%20Shine&artist_name=Simon%20%2B%20Garfunkel")
        #expect(search.value(forHTTPHeaderField: "User-Agent") == "Jukebox/1.0 (https://github.com/simmmmm/Jukebox)")
    }

    @Test("/api/get finds the song: its synced lyrics, nothing searched")
    func getFound() async throws {
        let mock = LRCLIBMockTransport(get: LyricsFixtures.json(LyricsFixtures.dutchRecord))
        let found = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                  album: "Oktoberlicht", duration: 192.4)
        guard case let .found(lyrics, synced) = found else {
            Issue.record("Expected lyrics, got \(found)")
            return
        }
        #expect(synced)
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.count == 21)
        #expect(lyrics.lines.first?.text == "De lantaarns gaan aan langs het water")
        #expect(mock.requests.count == 1)
    }

    @Test("A record with plain lyrics only: unsynced lines")
    func plainOnly() async throws {
        let record = LyricsFixtures.record(track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                           duration: 192, plain: LyricsFixtures.dutchPlain)
        let mock = LRCLIBMockTransport(get: LyricsFixtures.json(record))
        let found = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                  album: "Oktoberlicht", duration: 192)
        guard case let .found(lyrics, synced) = found else {
            Issue.record("Expected lyrics, got \(found)")
            return
        }
        #expect(!synced)
        #expect(!lyrics.isSynced)
        #expect(lyrics.lines.count == 5)
    }

    @Test("/api/get's 404, then the search: the synced record closest in length, of this title and artist")
    func searchBestMatch() async throws {
        let synced = LyricsFixtures.dutch
        let records: [[String: Any]] = [
            // Another song by the same artist.
            LyricsFixtures.record(id: 1, track: "Oktoberlicht", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                  duration: 193, synced: "[00:01.00]Wrong song"),
            // The same title by someone else.
            LyricsFixtures.record(id: 2, track: "Langs het water", artist: "Het Andere Koor", album: "Elders",
                                  duration: 192, synced: "[00:01.00]Wrong artist"),
            // The live take, far longer.
            LyricsFixtures.record(id: 3, track: "Langs het water (Live)", artist: "De Kanaalzangers", album: "Live in Paradiso",
                                  duration: 231, synced: "[00:01.00]Too long"),
            // Plain only, nearest in length: synced is better.
            LyricsFixtures.record(id: 4, track: "Langs het water", artist: "De Kanaalzangers", album: "Singles",
                                  duration: 192, plain: "Plain only"),
            // Synced, 2.5 s off: the one.
            LyricsFixtures.record(id: 5, track: "Langs Het Water", artist: "De Kanaalzangers feat. Iemand", album: "Singles",
                                  duration: 189.5, synced: synced),
            // Synced, 2.9 s off: further.
            LyricsFixtures.record(id: 6, track: "Langs het water", artist: "De Kanaalzangers", album: "Elders",
                                  duration: 194.9, synced: "[00:01.00]Further off"),
            // Synced, 3.5 s off: never.
            LyricsFixtures.record(id: 7, track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                  duration: 195.5, synced: "[00:01.00]Too far"),
        ]
        let mock = LRCLIBMockTransport(get: nil, search: search(records))
        let found = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                  album: "Oktoberlicht", duration: 192)
        guard case let .found(lyrics, isSynced) = found else {
            Issue.record("Expected lyrics, got \(found)")
            return
        }
        #expect(isSynced)
        #expect(lyrics.lines.first?.text == "De lantaarns gaan aan langs het water")
        #expect(mock.requests.map { $0.url?.path } == ["/api/get", "/api/search"])
    }

    @Test("Of two synced records equally close, the one of the same album")
    func sameAlbumWins() async throws {
        let records: [[String: Any]] = [
            LyricsFixtures.record(id: 1, track: "Langs het water", artist: "De Kanaalzangers", album: "Singles",
                                  duration: 193, synced: "[00:01.00]Singles"),
            LyricsFixtures.record(id: 2, track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                  duration: 191, synced: "[00:01.00]Album"),
        ]
        let mock = LRCLIBMockTransport(get: nil, search: search(records))
        let found = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                  album: "Oktoberlicht", duration: 192)
        #expect(found == .found(Lyrics(lines: [Lyrics.Line(start: 1, text: "Album")]), synced: true))
    }

    @Test("A search with nothing within 3 s, or nothing at all: not found")
    func searchNothingClose() async throws {
        let records: [[String: Any]] = [
            LyricsFixtures.record(track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                  duration: 200, synced: LyricsFixtures.dutch),
            LyricsFixtures.record(track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                  duration: 185, plain: LyricsFixtures.dutchPlain),
        ]
        let far = try await client(LRCLIBMockTransport(get: nil, search: search(records)))
            .lyrics(artist: "De Kanaalzangers", title: "Langs het water", album: "Oktoberlicht", duration: 192)
        #expect(far == .notFound)

        let empty = try await client(LRCLIBMockTransport(get: nil))
            .lyrics(artist: "De Kanaalzangers", title: "Langs het water", album: "Oktoberlicht", duration: 192)
        #expect(empty == .notFound)
    }

    @Test("A record /api/get finds more than 3 s off is not used: the search decides")
    func getTooFar() async throws {
        let far = LyricsFixtures.record(track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                        duration: 199, synced: LyricsFixtures.dutch)
        let mock = LRCLIBMockTransport(get: LyricsFixtures.json(far))
        let found = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                  album: "Oktoberlicht", duration: 192)
        #expect(found == .notFound)
        #expect(mock.requests.count == 2)
    }

    @Test("Instrumental, from /api/get or the search; words win over the mark")
    func instrumental() async throws {
        let mark = LyricsFixtures.record(track: "Nachtmuziek", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                         duration: 245, instrumental: true)
        let fromGet = try await client(LRCLIBMockTransport(get: LyricsFixtures.json(mark)))
            .lyrics(artist: "De Kanaalzangers", title: "Nachtmuziek", album: "Oktoberlicht", duration: 245)
        #expect(fromGet == .instrumental)

        let fromSearch = try await client(LRCLIBMockTransport(get: nil, search: search([mark])))
            .lyrics(artist: "De Kanaalzangers", title: "Nachtmuziek", album: "Oktoberlicht", duration: 245)
        #expect(fromSearch == .instrumental)

        let words = LyricsFixtures.record(track: "Nachtmuziek", artist: "De Kanaalzangers", album: "Singles",
                                          duration: 246, synced: "[00:10.00]Toch woorden")
        let both = try await client(LRCLIBMockTransport(get: nil, search: search([mark, words])))
            .lyrics(artist: "De Kanaalzangers", title: "Nachtmuziek", album: "Oktoberlicht", duration: 245)
        #expect(both == .found(Lyrics(lines: [Lyrics.Line(start: 10, text: "Toch woorden")]), synced: true))
    }

    @Test("Without an album or a length, only the search is asked")
    func searchOnly() async throws {
        let mock = LRCLIBMockTransport(get: LyricsFixtures.json(LyricsFixtures.dutchRecord),
                                       search: search([LyricsFixtures.dutchRecord]))
        let noAlbum = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                    album: nil, duration: 192)
        #expect(noAlbum != .notFound)
        // No length: the name alone decides.
        let noLength = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                     album: "Oktoberlicht", duration: 0)
        #expect(noLength != .notFound)
        #expect(mock.requests.map { $0.url?.path } == ["/api/search", "/api/search"])
    }

    @Test("No network throws, as the transport threw it; LRCLIB's 500 and 429 throw; 404 does not")
    func failures() async throws {
        let offline = LRCLIBMockTransport { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) {
            _ = try await client(offline).lyrics(artist: "A", title: "B", album: "C", duration: 100)
        }
        for status in [500, 429, 503] {
            let down = LRCLIBMockTransport(get: Data("{}".utf8), getStatus: status)
            await #expect(throws: LRCLIBClient.Failure.status(status)) {
                _ = try await client(down).lyrics(artist: "A", title: "B", album: "C", duration: 100)
            }
        }
        let garbled = LRCLIBMockTransport(get: Data("<html>".utf8))
        await #expect(throws: LRCLIBClient.Failure.unreadable) {
            _ = try await client(garbled).lyrics(artist: "A", title: "B", album: "C", duration: 100)
        }
        let searchDown = LRCLIBMockTransport { request in
            HTTPResponse(status: request.url?.path == "/api/get" ? 404 : 502, body: Data())
        }
        await #expect(throws: LRCLIBClient.Failure.status(502)) {
            _ = try await client(searchDown).lyrics(artist: "A", title: "B", album: "C", duration: 100)
        }
    }

    @Test("Artists: whole names or credits, never a name that only begins the other's letters")
    func artistsWhole() {
        let same: [(String, String)] = [
            ("Daft Punk, Pharrell Williams", "Daft Punk"),
            ("Daft Punk feat. Pharrell Williams & Nile Rodgers", "Daft Punk"),
            ("Daft Punk", "Daft Punk, Pharrell Williams"),
            ("The Weeknd", "Weeknd"),
            ("Simon & Garfunkel", "Simon and Garfunkel"),
            ("Nirvana (US)", "Nirvana"),
            ("Beyoncé x JAY-Z", "Beyonce"),
            ("AC/DC", "AC/DC"),
        ]
        for (record, ours) in same {
            #expect(LRCLIBClient.sameArtist(record, ours), "\(record) is \(ours)")
        }
        let others: [(String, String)] = [
            ("Queensrÿche", "Queen"),
            ("Kissin' Dynamite", "Kiss"),
            ("ABBA", "A"),
            ("Heartless Bastards", "Heart"),
            ("Yes", "Yesterday's Kids"),
            ("", "Queen"),
            ("Queen", ""),
        ]
        for (record, ours) in others {
            #expect(!LRCLIBClient.sameArtist(record, ours), "\(record) is not \(ours)")
        }
    }

    @Test("Titles of brackets or punctuation alone are compared whole")
    func titlesWithoutKey() {
        #expect(LRCLIBClient.sameTitle("Langs Het Water (Remastered)", "Langs het water"))
        #expect(LRCLIBClient.sameTitle("(untitled)", "(Untitled)"))
        #expect(!LRCLIBClient.sameTitle("(Intro)", "(Untitled)"))
        #expect(!LRCLIBClient.sameTitle("…", "!!!"))
        #expect(!LRCLIBClient.sameTitle("Anything", ""))
    }

    @Test("The search never takes a record of a name-alike artist, a key-less title or no length")
    func searchRefusesLookalikes() async throws {
        let records: [[String: Any]] = [
            LyricsFixtures.record(id: 1, track: "Langs het water", artist: "De Kanaalzangers Revisited", album: "Oktoberlicht",
                                  duration: 192, synced: "[00:01.00]Another band"),
            LyricsFixtures.record(id: 2, track: "Langs het water", artist: "De Kanaal", album: "Oktoberlicht",
                                  duration: 192, synced: "[00:01.00]Another band too"),
        ]
        var noLength = LyricsFixtures.record(id: 3, track: "Langs het water", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                             duration: 0, synced: "[00:01.00]No length")
        noLength["duration"] = NSNull()
        let found = try await client(LRCLIBMockTransport(get: nil, search: search(records + [noLength])))
            .lyrics(artist: "De Kanaalzangers", title: "Langs het water", album: "Oktoberlicht", duration: 192)
        #expect(found == .notFound)

        let untitled = [LyricsFixtures.record(id: 4, track: "(Intro)", artist: "De Kanaalzangers", album: "Oktoberlicht",
                                              duration: 60, synced: "[00:01.00]Intro")]
        let none = try await client(LRCLIBMockTransport(get: nil, search: search(untitled)))
            .lyrics(artist: "De Kanaalzangers", title: "(Untitled)", album: "Oktoberlicht", duration: 60)
        #expect(none == .notFound)
    }

    /// Records every quarter second from 3:02 to 3:22, of this song and of
    /// two others, and the song's own length every tenth of a second from
    /// 2:57 to 3:27: the pick is this song's, the closest, within 3 s, or
    /// nothing.
    @Test("Whatever the lengths, never a record more than 3 s off or of another song")
    func searchSweep() {
        var records: [LRCLIBRecord] = []
        var id = 0
        for step in 0...80 {
            let duration = 182 + Double(step) * 0.25
            for (track, artist) in [("Langs het water", "De Kanaalzangers"), ("Langs het water", "Het Andere Koor"),
                                    ("Oktoberlicht", "De Kanaalzangers")] {
                id += 1
                records.append(LRCLIBRecord(id: id, trackName: track, artistName: artist, albumName: "Oktoberlicht",
                                            duration: duration, instrumental: false, plainLyrics: nil,
                                            syncedLyrics: "[00:01.00]\(track) \(artist) \(duration)"))
            }
        }
        for tenth in 0...300 {
            let length = 177 + Double(tenth) / 10
            let query = LyricsQuery(artist: "De Kanaalzangers", title: "Langs het water", album: "Oktoberlicht", duration: length)
            let picked = LRCLIBClient.best(of: records, for: query)
            let nearest = records.filter { $0.artistName == "De Kanaalzangers" && $0.trackName == "Langs het water" }
                .map { abs(($0.duration ?? 0) - length) }.min() ?? .infinity
            if nearest > LRCLIBClient.durationTolerance {
                #expect(picked?.id == nil, "\(length) s: nothing within 3 s")
            } else {
                #expect(picked?.trackName == "Langs het water" && picked?.artistName == "De Kanaalzangers",
                        "\(length) s: this song")
                let off = abs((picked?.duration ?? .infinity) - length)
                #expect(off <= LRCLIBClient.durationTolerance, "\(length) s: within 3 s")
                // The closest of all.
                #expect(off == nearest, "\(length) s: the closest")
            }
        }
    }

    @Test("/api/get that does not answer in time: the search is asked, and its answer used")
    func getTimesOut() async throws {
        let mock = LRCLIBMockTransport { request in
            if request.url?.path == "/api/get" { throw URLError(.timedOut) }
            return HTTPResponse(status: 200, body: LyricsFixtures.json([LyricsFixtures.dutchRecord]))
        }
        let found = try await client(mock).lyrics(artist: "De Kanaalzangers", title: "Langs het water",
                                                  album: "Oktoberlicht", duration: 192)
        guard case let .found(lyrics, synced) = found else {
            Issue.record("Expected lyrics, got \(found)")
            return
        }
        #expect(synced)
        #expect(lyrics.lines.count == 21)
        #expect(mock.requests.map { $0.url?.path } == ["/api/get", "/api/search"])

        // A search that does not answer either: thrown, so nothing is kept.
        let silent = LRCLIBMockTransport { _ in throw URLError(.timedOut) }
        await #expect(throws: URLError.self) {
            _ = try await client(silent).lyrics(artist: "A", title: "B", album: "C", duration: 100)
        }
        #expect(silent.requests.count == 2)
    }

    @Test("The query: the main artist, the title without its guests, brackets left for the search to drop")
    func query() {
        let joined = LyricsQuery(artist: "De Kanaalzangers; Iemand Anders", title: "Langs het water (feat. Iemand Anders)",
                                 album: "  ", duration: 192.4)
        #expect(joined.artist == "De Kanaalzangers")
        #expect(joined.title == "Langs het water")
        #expect(joined.album == nil)
        #expect(joined.seconds == 192)

        #expect(LyricsQuery(artist: "A feat. B", title: "Song ft. B", duration: 1).artist == "A")
        #expect(LyricsQuery(artist: "A Ft. B", title: "Song ft. B", duration: 1).title == "Song")
        #expect(LyricsQuery(artist: "A", title: "Song [with B]", duration: 1).title == "Song")
        #expect(LyricsQuery(artist: "A", title: "Song (Featuring B) (Live)", duration: 1).title == "Song (Live)")
        // One artist each, kept whole.
        for name in ["Simon & Garfunkel", "Earth, Wind & Fire", "AC/DC", "Florence + the Machine"] {
            #expect(LyricsQuery(artist: name, title: "Song", duration: 1).artist == name)
        }
        // The search drops the version, the length then tells them apart.
        let remaster = LyricsQuery(artist: "A", title: "Song (Remastered 2011) - Mono", duration: 1)
        #expect(remaster.title == "Song (Remastered 2011) - Mono")
        #expect(remaster.searchTitle == "Song")
        #expect(LyricsQuery(artist: "A", title: "(Untitled)", duration: 1).searchTitle == "(Untitled)")
        #expect(joined.cacheKey == "de kanaalzangers|langs het water||192")
    }

    @Test("The query from a Track: its own performer, not a compilation's Various Artists")
    func queryFromTrack() throws {
        let various = Track(id: "1", name: "Langs het water (feat. Iemand)", albumName: "Hits van het Jaar",
                            artists: [ArtistRef(id: nil, name: "De Kanaalzangers"), ArtistRef(id: nil, name: "Iemand")],
                            albumArtist: ArtistRef(id: nil, name: "Various Artists"), duration: 192)
        let query = try #require(LyricsQuery(track: various))
        #expect(query.artist == "De Kanaalzangers")
        #expect(query.title == "Langs het water")
        #expect(query.album == "Hits van het Jaar")

        let unsplit = Track(id: "2", name: "Song", artists: [ArtistRef(id: nil, name: "A; B")], duration: 100)
        #expect(LyricsQuery(track: unsplit)?.artist == "A")

        let albumOnly = Track(id: "3", name: "Song", albumArtist: ArtistRef(id: nil, name: "Album Artist"), duration: 100)
        #expect(LyricsQuery(track: albumOnly)?.artist == "Album Artist")

        #expect(LyricsQuery(track: Track(id: "4", name: "Song", duration: 100)) == nil)
        #expect(LyricsQuery(track: Track(id: "5", name: " ", artists: [ArtistRef(id: nil, name: "A")], duration: 100)) == nil)
        let onlyVarious = Track(id: "6", name: "Song", artists: [ArtistRef(id: nil, name: "Various Artists")],
                                albumArtist: ArtistRef(id: nil, name: "VA"), duration: 100)
        #expect(LyricsQuery(track: onlyVarious) == nil)
    }

    @Test("Asked for a Track, the client sends the cleaned query")
    func cleanedRequest() async throws {
        let mock = LRCLIBMockTransport(get: nil)
        _ = try await client(mock).lyrics(artist: "De Kanaalzangers; Iemand", title: "Langs het water (feat. Iemand)",
                                          album: "Oktoberlicht", duration: 192)
        let get = try #require(mock.requests.first)
        #expect(get.lrclibQuery["artist_name"] == "De Kanaalzangers")
        #expect(get.lrclibQuery["track_name"] == "Langs het water")
    }
}
