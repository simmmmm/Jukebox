// SubsonicClient against the real Navidrome of dev/navidrome-test-server.sh
// (0.64.2, user test/test, the made-up library of the Jellyfin test server:
// 23 album artists, 54 albums, 358 tracks in MP3, FLAC and M4A; Last.fm,
// Spotify, Deezer and ListenBrainz off). Skipped when NAVIDROME_URL is not
// set; dev/kit-test.sh sets it when the container runs. Lines starting
// "NAVIDROME-MEASURE" are the measurements in docs/SERVERS.md.
//
// What both servers must do alike is ServerContractTests'; this is what is
// Navidrome's own: the token, its numbers, the files it sends, long
// playlists by form POST, and what it answers without its agents. What the
// tests change they change back, but play counts and "now playing".

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum NavidromeTestServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url: URL? = environment["NAVIDROME_URL"].flatMap { MusicServers.candidateAddresses(for: $0).first }
    static let user = environment["NAVIDROME_USER"] ?? "test"
    static let password = environment["NAVIDROME_PASSWORD"] ?? "test"
    static let identity = ClientIdentity(clientName: "JukeboxKitTests", clientVersion: "1.0",
                                         deviceName: "Kit tests: Navidrome", deviceID: "jukebox-kit-navidrome")

    /// One sign-in for every test, as the app signs in: detect, then the
    /// password made into a token.
    static let session = Task<SubsonicClient, any Error> {
        guard let url else { throw MusicServerError.invalidServerAddress }
        let server = try await MusicServers.detect(url.absoluteString, identity: identity)
        let credentials = try await MusicServers.signIn(to: server, identity: identity)
            .signIn(username: user, password: password)
        return SubsonicClient(credentials: credentials, identity: identity)
    }

    static func client() async throws -> SubsonicClient { try await session.value }

    /// A plain GET, as AVPlayer, the image view or a download task makes it.
    static func fetch(_ url: URL) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        return try await URLSessionTransport().send(request)
    }

    /// An answer the kit does not read itself (getNowPlaying), as JSON.
    static func raw(_ client: SubsonicClient, _ endpoint: String, _ query: [URLQueryItem] = []) async throws -> [String: Any] {
        let response = try await fetch(client.connection.url(endpoint, query))
        let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        return object?["subsonic-response"] as? [String: Any] ?? [:]
    }

    /// One track of each file kind, by its suffix.
    static func oneOfEach(_ tracks: [Track]) -> [String: Track] {
        var byKind: [String: Track] = [:]
        for track in tracks.sorted(by: { $0.id < $1.id }) {
            if let kind = track.container, byKind[kind] == nil { byKind[kind] = track }
        }
        return byKind
    }

    static func measure(_ line: String) {
        print("NAVIDROME-MEASURE \(line)")
    }

    /// A JSON number as JSONSerialization gives it, here or on Apple's.
    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return (value as? Double).map { Int($0) }
    }

    static func ms(_ duration: Duration) -> String {
        let c = duration.components
        return String(format: "%.1f ms", Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15)
    }
}

@Suite("Navidrome: the real server", .serialized, .enabled(if: NavidromeTestServer.url != nil))
struct NavidromeIntegrationTests {
    let clock = ContinuousClock()

    // MARK: Signing in

    @Test("Sign in: a token and its salt, never the password; capabilities; the session from the keychain")
    func signIn() async throws {
        let url = try #require(NavidromeTestServer.url)
        let identity = NavidromeTestServer.identity
        let server = try await MusicServers.detect(url.absoluteString, identity: identity)
        let credentials = try await MusicServers.signIn(to: server, identity: identity)
            .signIn(username: NavidromeTestServer.user, password: NavidromeTestServer.password)
        guard case let .subsonicToken(token, salt) = credentials.secret else {
            Issue.record("not a token: \(credentials.secret)")
            return
        }
        #expect(salt.count == 16 && token == MD5.hex(NavidromeTestServer.password + salt))
        #expect(credentials.kind == .subsonic(flavour: .navidrome))
        #expect(credentials.userName == NavidromeTestServer.user && credentials.userID == NavidromeTestServer.user)
        #expect(credentials.serverURL == url && credentials.serverID == url.absoluteString)
        #expect(credentials.apiVersion == "1.16.1")
        #expect(credentials.serverVersion.first?.isNumber == true)
        #expect(credentials.capabilities.isSuperset(of: [.lyrics, .syncedLyrics, .instantMix, .similarArtists, .topSongs,
                                                          .playlistReorder, .replayGain, .playbackTimeline, .lastPlayed,
                                                          .transcodeOffset]))
        #expect(credentials.capabilities.isDisjoint(with: [.quickConnect, .apiKeySignIn]))

        // As the keychain keeps it and the next launch opens it.
        let kept = try JSONDecoder().decode(ServerCredentials.self, from: try JSONEncoder().encode(credentials))
        let reopened = MusicServers.open(kept, identity: identity)
        #expect(try await !reopened.genres().isEmpty)
        #expect(try await reopened.currentCapabilities() == credentials.capabilities)
        #expect(try await reopened.downloadsAllowed())

        await #expect(throws: MusicServerError.unauthorized) {
            _ = try await MusicServers.signIn(to: server, identity: identity)
                .signIn(username: NavidromeTestServer.user, password: "not the password")
        }
        let stranger = SubsonicClient(credentials: ServerCredentials(
            kind: credentials.kind, serverURL: url, serverID: url.absoluteString, serverName: "x",
            apiVersion: "1.16.1", userID: "test", userName: "test",
            secret: .subsonicToken(token: String(repeating: "0", count: 32), salt: salt)), identity: identity)
        await #expect(throws: MusicServerError.unauthorized) { _ = try await stranger.genres() }
        NavidromeTestServer.measure("signed in to \(credentials.kind.displayName) \(credentials.serverVersion), API \(credentials.apiVersion ?? "-"), capabilities \(credentials.capabilities.map(\.rawValue).sorted())")
    }

    // MARK: The library

    @Test("The whole library: 358 tracks, 54 albums, 23 artists, 23 genres; the time it takes")
    func library() async throws {
        let client = try await NavidromeTestServer.client()
        let calls = SubsonicProgressRecorder()
        let tracks = try await client.allTracks { calls.add($0, $1) }
        #expect(tracks.count == 358)
        #expect(Set(tracks.map(\.id)).count == 358)
        #expect(calls.values.first.map { $0 == (0, 358) } == true)
        #expect(calls.values.last.map { $0 == (358, 358) } == true)
        #expect(tracks.allSatisfy { !$0.name.isEmpty && $0.duration >= 5 && $0.albumID != nil && !$0.genres.isEmpty })
        #expect(tracks.allSatisfy { $0.albumArtist != nil && !$0.artists.isEmpty && $0.artists.allSatisfy { $0.id != nil } })
        #expect(tracks.allSatisfy { ($0.imageTag ?? "").hasPrefix("dc-\($0.albumID!):") && $0.albumImageTag == nil })
        #expect(Set(tracks.compactMap(\.container)) == ["mp3", "flac", "m4a"])
        let guests = tracks.filter { $0.artists.count > 1 }.count
        let blends = tracks.filter { $0.genres.count > 1 }.count
        #expect(guests == 92 && blends == 294)

        let albums = try await client.allAlbums()
        #expect(albums.count == 54)
        #expect(albums.reduce(0) { $0 + ($1.trackCount ?? 0) } == 358)
        #expect(albums.allSatisfy { ($0.imageTag ?? "").hasPrefix("al-\($0.id)_") && $0.year != nil && !$0.artists.isEmpty })
        #expect(Set(tracks.compactMap(\.albumID)) == Set(albums.map(\.id)))

        let artists = try await client.allArtists()
        #expect(artists.count == 23)
        #expect(artists.allSatisfy { $0.imageTag == nil && ($0.albumCount ?? 0) > 0 })
        #expect(Set(albums.compactMap { $0.artists.first?.name }) == Set(artists.map(\.name)))

        let genres = try await client.genres()
        #expect(genres.count == 23)
        #expect(genres.allSatisfy { $0.id == $0.name && ($0.songCount ?? 0) > 0 })

        var times: [Duration] = []
        for _ in 0..<3 { times.append(try await clock.measure { _ = try await client.allTracks(progress: nil) }) }
        var pagedCount = 0
        let paged = try await clock.measure { pagedCount = try await client.allTracks(pageSize: 100, progress: nil).count }
        #expect(pagedCount == 358)
        NavidromeTestServer.measure("allTracks (getAlbumList2 + search3): " + times.map(NavidromeTestServer.ms).joined(separator: ", ")
                                    + "; in pages of 100: \(NavidromeTestServer.ms(paged)); \(guests) with guests, \(blends) with two genres or more")
    }

    @Test("Every album's tracks in disc and track order, as many as it says")
    func albumOrder() async throws {
        let client = try await NavidromeTestServer.client()
        let albums = try await client.allAlbums()
        for album in albums {
            let tracks = try await client.albumTracks(albumID: album.id)
            #expect(tracks.count == album.trackCount, "\(album.name)")
            let order = tracks.map { [$0.discNumber ?? 1, $0.trackNumber ?? 0] }
            #expect(order == order.sorted { $0.lexicographicallyPrecedes($1) }, "\(album.name)")
            #expect(tracks.allSatisfy { $0.albumID == album.id && $0.albumName == album.name })
            #expect(abs(tracks.reduce(0) { $0 + $1.duration } - (album.duration ?? 0)) <= Double(tracks.count))
        }
        let dust = try #require(albums.first { $0.name == "Dust Parades" })
        let tracks = try await client.albumTracks(albumID: dust.id)
        NavidromeTestServer.measure("Dust Parades: " + tracks.map { "\($0.discNumber ?? 0)-\($0.trackNumber ?? 0)" }.joined(separator: " "))
    }

    @Test("A known track, mapped: performers split, the album artist, genres, year, the suffix")
    func knownTrack() async throws {
        let client = try await NavidromeTestServer.client()
        let found = try await client.search("Blue Parade", limit: 20)
        let track = try #require(found.tracks.first { $0.albumName == "Iron Gardens" })
        #expect(track.name == "Blue Parade")
        #expect(track.artists.map(\.name) == ["MC Polder", "Lyric Engine"])
        #expect(track.albumArtist?.name == "MC Polder")
        #expect(track.genres == ["Hip-Hop", "Nederhop"])
        #expect(track.year == 2016 && track.trackNumber == 1 && track.discNumber == 1 && track.duration == 6)
        #expect(track.container == "m4a" && track.dateAdded != nil && track.normalizationGain == nil)

        let again = try await client.track(id: track.id)
        #expect(again.name == track.name && again.albumID == track.albumID && again.artists == track.artists)
        let album = try await client.album(id: try #require(track.albumID))
        #expect(album.name == "Iron Gardens" && album.artists.map(\.name) == ["MC Polder"] && album.year == 2016)
        let artist = try await client.artist(id: try #require(track.albumArtist?.id))
        #expect(artist.name == "MC Polder" && artist.albumCount == 3)

        for unknown in ["ffffffffffffffffffffff", "nope"] {
            await #expect(throws: MusicServerError.notFound) { _ = try await client.track(id: unknown) }
            await #expect(throws: MusicServerError.notFound) { _ = try await client.album(id: unknown) }
            await #expect(throws: MusicServerError.notFound) { _ = try await client.artist(id: unknown) }
            await #expect(throws: MusicServerError.notFound) { _ = try await client.playlistTracks(playlistID: unknown) }
            await #expect(throws: MusicServerError.notFound) { try await client.deletePlaylist(id: unknown) }
        }
    }

    @Test("Search: artists, albums and songs of a term")
    func search() async throws {
        let client = try await NavidromeTestServer.client()
        let results = try await client.search("night", limit: 20)
        #expect(results.artists.map(\.name).contains("Nightdrive"))
        #expect(!results.albums.isEmpty && results.albums.count <= 20)
        #expect(!results.tracks.isEmpty && results.tracks.count <= 20)
        NavidromeTestServer.measure("search night: \(results.artists.map(\.name)), \(results.albums.count) albums, \(results.tracks.count) songs")
    }

    // MARK: Playlists

    @Test("A playlist of the whole library: one form POST each way; a move to the end and back")
    func longPlaylist() async throws {
        let client = try await NavidromeTestServer.client()
        let ids = try await client.allTracks(progress: nil).map(\.id).sorted()
        let name = "Jukebox kit long \(UUID().uuidString.prefix(8))"
        let id = try await client.createPlaylist(name: name, trackIDs: ids)
        do {
            #expect(try await client.playlistTracks(playlistID: id).map(\.id) == ids)
            let first = try #require(try await client.playlistTracks(playlistID: id).first?.playlistEntryID)
            let moved = try await clock.measure { try await client.movePlaylistEntry(playlistID: id, entryID: first, to: 357) }
            #expect(try await client.playlistTracks(playlistID: id).map(\.id) == Array(ids.dropFirst()) + [ids[0]])
            try await client.movePlaylistEntry(playlistID: id, entryID: "\(ids[0])#0", to: 0)
            #expect(try await client.playlistTracks(playlistID: id).map(\.id) == ids)
            try await client.removeFromPlaylist(playlistID: id, entryIDs: ids.prefix(200).map { "\($0)#0" })
            #expect(try await client.playlistTracks(playlistID: id).map(\.id) == Array(ids.dropFirst(200)))
            let listed = try #require(try await client.playlists().first { $0.id == id })
            #expect(listed.trackCount == 158 && !listed.isReadOnly)
            // "pl-<id>" by curl every time; once, in a run of these tests,
            // something more after it.
            #expect(listed.imageTag?.hasPrefix("pl-\(id)") == true, "\(listed.imageTag ?? "nil")")
            NavidromeTestServer.measure("a move in a playlist of 358 (read, one POST): \(NavidromeTestServer.ms(moved)); cover \(listed.imageTag ?? "-") for pl-\(id)")
        } catch {
            try? await client.deletePlaylist(id: id)
            throw error
        }
        try await client.deletePlaylist(id: id)
    }

    // MARK: Playing

    @Test("Streams: the file at .original with its length; MP3 at every cap")
    func streams() async throws {
        let client = try await NavidromeTestServer.client()
        let byKind = NavidromeTestServer.oneOfEach(try await client.allTracks(progress: nil))
        #expect(Set(byKind.keys) == ["mp3", "flac", "m4a"])
        for (kind, track) in byKind.sorted(by: { $0.key < $1.key }) {
            for quality in StreamQuality.allCases {
                let got = try await NavidromeTestServer.fetch(client.streamURL(for: track, quality: quality, playSessionID: "x"))
                let type = got.jellyfinHeader("Content-Type") ?? "-"
                let expected = quality == .original ? kind : "mp3"
                #expect(got.status == 200, "\(kind) \(quality)")
                #expect(type.hasPrefix("audio/"), "\(kind) \(quality): \(type)")
                #expect(OfflineDownloadIntegrationTests.kind(of: got.body) == expected, "\(kind) \(quality)")
                if quality == .original {
                    #expect(got.jellyfinHeader("Content-Length") == String(got.body.count))
                    #expect(got.jellyfinHeader("Accept-Ranges") == "bytes")
                }
                NavidromeTestServer.measure("stream \(kind) .\(quality): \(got.status) \(type) \(got.body.count) bytes, length \(got.jellyfinHeader("Content-Length") ?? "-")")
            }
        }
        // An unknown song: 200 and a JSON error, not audio.
        let unknown = try await NavidromeTestServer.fetch(client.streamURL(for: Track(id: "nope", name: ""), quality: .original, playSessionID: ""))
        #expect(unknown.status == 200 && unknown.jellyfinHeader("Content-Type")?.hasPrefix("application/json") == true)
    }

    @Test("Downloads at each quality: the file itself at .original, MP3 at .high and .normal, named by their type")
    func downloads() async throws {
        let client = try await NavidromeTestServer.client()
        let byKind = NavidromeTestServer.oneOfEach(try await client.allTracks(progress: nil))
        for (kind, track) in byKind.sorted(by: { $0.key < $1.key }) {
            let file = try await NavidromeTestServer.fetch(client.streamURL(for: track, quality: .original, playSessionID: ""))
            for quality in DownloadQuality.allCases {
                let url = client.downloadURL(for: track, quality: quality)
                let got = try await NavidromeTestServer.fetch(url)
                let type = got.jellyfinHeader("Content-Type")
                let expected = quality == .original ? kind : "mp3"
                #expect(got.status == 200, "\(kind) \(quality)")
                #expect(OfflineDownloadIntegrationTests.kind(of: got.body) == expected, "\(kind) \(quality)")
                #expect(OfflineFile.fileExtension(contentType: type) == expected, "\(kind) \(quality)")
                if quality == .original {
                    #expect(got.body == file.body, "\(kind): the file byte for byte")
                    #expect(got.jellyfinHeader("Accept-Ranges") == "bytes")
                }
                NavidromeTestServer.measure("download \(kind) .\(quality) (\(url.path)): \(got.status) \(type ?? "-") \(got.body.count) bytes, length \(got.jellyfinHeader("Content-Length") ?? "chunked")")
            }
        }
        #expect(try await client.downloadsAllowed())
    }

    @Test("Artwork: the album's cover immutable, the disc's revalidated, a playlist's mosaic")
    func artwork() async throws {
        let client = try await NavidromeTestServer.client()
        let album = try #require(try await client.allAlbums().first)
        let cover = try await NavidromeTestServer.fetch(client.artworkURL(try #require(album.artwork), maxPixelSize: 300))
        #expect(cover.status == 200 && cover.jellyfinHeader("Content-Type") == "image/jpeg")
        #expect(cover.body.starts(with: [0xFF, 0xD8]))
        #expect(cover.jellyfinHeader("Cache-Control")?.contains("immutable") == true)
        let track = try #require(try await client.albumTracks(albumID: album.id).first)
        let disc = try await NavidromeTestServer.fetch(client.artworkURL(try #require(track.artwork), maxPixelSize: 300))
        #expect(disc.status == 200 && disc.jellyfinHeader("Content-Type") == "image/jpeg")
        NavidromeTestServer.measure("cover: \(cover.body.count) bytes, \(cover.jellyfinHeader("Cache-Control") ?? "-"); disc: \(disc.jellyfinHeader("Cache-Control") ?? "-")")
    }

    @Test("Now playing: the timeline shows in getNowPlaying, paused too, and counts no play")
    func nowPlaying() async throws {
        let client = try await NavidromeTestServer.client()
        let tracks = try await client.allTracks(progress: nil)
        let track = try #require(tracks.randomElement())
        let before = try await client.track(id: track.id).playCount
        await client.report(.nowPlaying, PlaybackReport(trackID: track.id, position: 0, isPaused: false, playSessionID: ""))
        await client.report(.progress, PlaybackReport(trackID: track.id, position: 2, isPaused: true, playSessionID: ""))
        let now = try await NavidromeTestServer.raw(client, "getNowPlaying")
        let entries = (now["nowPlaying"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
        let ours = try #require(entries.first { $0["id"] as? String == track.id && $0["playerName"] as? String == "JukeboxKitTests" })
        #expect(ours["state"] as? String == "paused")
        #expect(NavidromeTestServer.int(ours["positionMs"]) == 2000)
        await client.report(.stopped, PlaybackReport(trackID: track.id, position: track.duration, isPaused: false, playSessionID: ""))
        // Stopped at the end: Navidrome would count it, but not with ignoreScrobble.
        #expect(try await client.track(id: track.id).playCount == before)
    }

    // MARK: Without its agents

    @Test("Without Last.fm: no similar artists, no top songs; mixes by genre, from Navidrome's own library")
    func withoutAgents() async throws {
        let client = try await NavidromeTestServer.client()
        let artists = try await client.allArtists()
        let artist = try #require(artists.first { $0.name == "MC Polder" })
        #expect(try await client.similarArtists(artistID: artist.id, limit: 10).isEmpty)
        #expect(try await client.topSongs(of: artist.ref, limit: 10).isEmpty)
        #expect(try await client.topSongs(of: ArtistRef(id: nil, name: artist.name), limit: 10).isEmpty)

        let tracks = try await client.allTracks(progress: nil)
        let seed = try #require(tracks.first { $0.albumArtist?.id == artist.id })
        var lines: [String] = []
        for (name, mix) in [("track", MixSeed.track(seed.id)), ("album", .album(try #require(seed.albumID))),
                            ("artist", .artist(artist.id)), ("genre", .genre(name: "Nederhop", id: nil))] {
            var songs: [Track] = []
            let time = try await clock.measure { songs = try await client.instantMix(from: mix, limit: 20) }
            #expect(!songs.isEmpty && songs.count <= 20, "\(name)")
            let sharing = songs.filter { !Set($0.genres).isDisjoint(with: seed.genres) }.count
            lines.append("\(name) \(songs.count) songs, \(sharing) sharing a genre with the seed, \(NavidromeTestServer.ms(time))")
        }
        let nederhop = try await client.instantMix(from: .genre(name: "Nederhop", id: nil), limit: 50)
        #expect(nederhop.allSatisfy { $0.genres.contains("Nederhop") })
        NavidromeTestServer.measure("instantMix from MC Polder's \(seed.name) (\(seed.genres.joined(separator: ", "))): " + lines.joined(separator: "; "))
    }
}
