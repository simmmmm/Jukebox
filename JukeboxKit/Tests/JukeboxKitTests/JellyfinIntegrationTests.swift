// JellyfinClient against the real Jellyfin of dev/jellyfin-test-server.sh
// (12.4, user test/test, 23 album artists, 54 albums, 358 tracks in MP3,
// FLAC and M4A). Skipped when JELLYFIN_URL is not set; dev/kit-test.sh sets
// it when the server runs. Lines starting "JELLYFIN-MEASURE" are the
// measurements in the report.
//
// What the tests change on the server they change back (favourites, the
// test playlist), except play counts: a playback report counts a play for
// good, so it is made on a track picked at random.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum JellyfinTestServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url: URL? = environment["JELLYFIN_URL"].flatMap { JellyfinClient.normalize(serverAddress: $0) }
    static let user = environment["JELLYFIN_USER"] ?? "test"
    static let password = environment["JELLYFIN_PASSWORD"] ?? "test"

    /// Jellyfin signs out a device's other tokens when it signs in again
    /// (measured on 12.4: the first token answers 401 after a second sign-in
    /// with the same DeviceId), so every test shares one session, and the
    /// sign-in tests use devices of their own.
    static func identity(_ device: String) -> ClientIdentity {
        ClientIdentity(clientName: "JukeboxKitTests", clientVersion: "1.0",
                       deviceName: "Kit tests: Jellyfin \(device)", deviceID: "jukebox-kit-jellyfin-\(device)")
    }

    static let session = Task<JellyfinClient, any Error> {
        guard let url else { throw JellyfinError.invalidServerAddress }
        let main = JellyfinTestServer.identity("main")
        let credentials = try await JellyfinClient(serverURL: url, identity: main)
            .signIn(username: user, password: password)
        return JellyfinClient(credentials: credentials, identity: main)
    }

    static func client() async throws -> JellyfinClient { try await session.value }

    /// A plain GET, as AVPlayer or the image view would make it: no header.
    static func fetch(_ url: URL) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        return try await URLSessionTransport().send(request)
    }

    static func measure(_ line: String) {
        print("JELLYFIN-MEASURE \(line)")
    }

    static func ms(_ duration: Duration) -> String {
        let c = duration.components
        let value = Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
        return String(format: "%.1f ms", value)
    }

    /// Guest credits are "A; B" on this library (its tags are not split),
    /// or two names when the library splits them: the same either way.
    static func names(_ list: [String]) -> [String] {
        list.flatMap { $0.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) } }
    }
}

extension HTTPResponse {
    func jellyfinHeader(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

@Suite("Jellyfin: the real server", .serialized, .enabled(if: JellyfinTestServer.url != nil))
struct JellyfinIntegrationTests {
    let clock = ContinuousClock()

    // MARK: Signing in

    @Test("Public info, and the address normalised from JELLYFIN_URL")
    func publicInfo() async throws {
        let url = try #require(JellyfinTestServer.url)
        let info = try await JellyfinClient(serverURL: url, identity: JellyfinTestServer.identity("public")).publicInfo()
        #expect(!info.id.isEmpty)
        #expect(!info.name.isEmpty)
        #expect(info.version.first?.isNumber == true)
        JellyfinTestServer.measure("server \(info.name) version \(info.version) at \(url)")
    }

    @Test("Sign in with the right password, sign out, and the token is gone")
    func signInAndOut() async throws {
        let url = try #require(JellyfinTestServer.url)
        let identity = JellyfinTestServer.identity("signin")
        let anonymous = JellyfinClient(serverURL: url, identity: identity)
        let info = try await anonymous.publicInfo()
        let credentials = try await anonymous.signIn(username: JellyfinTestServer.user, password: JellyfinTestServer.password)
        #expect(credentials.userName == JellyfinTestServer.user)
        #expect(credentials.userID.count == 32)
        #expect(!credentials.accessToken.isEmpty)
        #expect(credentials.serverID == info.id)
        #expect(credentials.serverName == info.name)
        #expect(credentials.serverURL == url)

        let client = JellyfinClient(credentials: credentials, identity: identity)
        #expect(try await !client.genres().isEmpty)
        await client.signOut()
        await #expect(throws: JellyfinError.unauthorized) { _ = try await client.genres() }
    }

    @Test("A wrong password is .unauthorized")
    func wrongPassword() async throws {
        let url = try #require(JellyfinTestServer.url)
        let client = JellyfinClient(serverURL: url, identity: JellyfinTestServer.identity("wrong"))
        await #expect(throws: JellyfinError.unauthorized) {
            _ = try await client.signIn(username: JellyfinTestServer.user, password: "not the password")
        }
    }

    @Test("Quick Connect: a code, authorised by a signed-in user, signs in")
    func quickConnect() async throws {
        let url = try #require(JellyfinTestServer.url)
        let identity = JellyfinTestServer.identity("quickconnect")
        let phone = JellyfinClient(serverURL: url, identity: identity)
        guard await phone.quickConnectEnabled() else {
            JellyfinTestServer.measure("quick connect: disabled on this server")
            await #expect(throws: (any Error).self) { _ = try await phone.quickConnectStart() }
            return
        }
        let started = try await phone.quickConnectStart()
        #expect(started.code.count == 6)
        #expect(!started.isAuthenticated)
        #expect(try await !phone.quickConnectState(secret: started.secret).isAuthenticated)

        // What the user does in another client that is signed in already.
        let other = try await JellyfinTestServer.client()
        try await other.send("POST", "/QuickConnect/Authorize",
                             query: [URLQueryItem(name: "code", value: started.code),
                                     URLQueryItem(name: "userId", value: other.userID)])

        #expect(try await phone.quickConnectState(secret: started.secret).isAuthenticated)
        let credentials = try await phone.signIn(quickConnectSecret: started.secret)
        #expect(credentials.userID == other.userID)
        #expect(credentials.userName == JellyfinTestServer.user)
        let signedIn = JellyfinClient(credentials: credentials, identity: identity)
        #expect(try await !signedIn.genres().isEmpty)
        await signedIn.signOut()

        await #expect(throws: JellyfinError.notFound) { _ = try await phone.quickConnectState(secret: "not-a-secret") }
        JellyfinTestServer.measure("quick connect: enabled; initiate, authorise, state, sign in all worked")
    }

    // MARK: Lists

    @Test("Album artists: 23, paged, searched, one by id")
    func artists() async throws {
        let client = try await JellyfinTestServer.client()
        let all = try await client.artists()
        #expect(all.totalCount == 23)
        #expect(all.items.count == 23)
        // By SortName, which drops a leading "The": "The Lanterns" sorts under L.
        let sortNames = all.items.map { $0.name.hasPrefix("The ") ? String($0.name.dropFirst(4)) : $0.name }
        #expect(sortNames == sortNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(all.items.allSatisfy { ($0.songCount ?? 0) > 0 && ($0.albumCount ?? 0) > 0 })
        // Not every artist's genres: with internet (GitHub's runners), Jellyfin's
        // MusicBrainz and AudioDB providers set an artist's genres from what they
        // find online, and for these made-up names that can be none.

        let window = try await client.artists(start: 2, limit: 5)
        #expect(window.items.map(\.id) == Array(all.items[2..<7]).map(\.id))
        #expect(window.startIndex == 2)
        #expect(window.totalCount == 23)

        let found = try await client.artists(searchTerm: "night")
        #expect(found.items.map(\.name).contains("Nightdrive"))

        let one = try #require(all.items.first { $0.name == "MC Polder" })
        let again = try await client.artist(id: one.id)
        #expect(again.name == "MC Polder")
        #expect(again.albumCount == 3)
        #expect(again.songCount == one.songCount)
        await #expect(throws: JellyfinError.notFound) { _ = try await client.artist(id: "ffffffffffffffffffffffffffffffff") }
    }

    @Test("Albums: 54; by artist, by genre, by year; one by id with its tracks in order")
    func albums() async throws {
        let client = try await JellyfinTestServer.client()
        let all = try await client.albums(AlbumQuery())
        #expect(all.totalCount == 54)
        #expect(all.items.count == 54)
        #expect(all.items.allSatisfy { $0.imageTag != nil && ($0.trackCount ?? 0) > 0 && ($0.duration ?? 0) > 0 && $0.year != nil })

        let artist = try #require(try await client.artists().items.first { $0.name == "MC Polder" })
        let byArtist = try await client.albums(AlbumQuery(artistID: artist.id))
        #expect(byArtist.items.count == 3)
        #expect(byArtist.items.allSatisfy { $0.artists.contains { $0.id == artist.id } })

        let byYear = try await client.albums(AlbumQuery(sort: .year, descending: true))
        let years = byYear.items.compactMap(\.year)
        #expect(years == years.sorted(by: >))

        let genre = try #require(all.items.first?.genres.first)
        let byGenre = try await client.albums(AlbumQuery(genre: genre))
        #expect(!byGenre.items.isEmpty)
        #expect(byGenre.items.allSatisfy { $0.genres.contains(genre) })

        let album = try #require(all.items.first)
        let again = try await client.album(id: album.id)
        #expect(again == album)
        let tracks = try await client.tracks(TrackQuery(albumID: album.id))
        #expect(tracks.items.count == album.trackCount)
        let order = tracks.items.map { [$0.discNumber ?? 0, $0.trackNumber ?? 0] }
        #expect(order == order.sorted { $0.lexicographicallyPrecedes($1) })
        let sum = tracks.items.reduce(0) { $0 + $1.duration }
        #expect(abs(sum - (album.duration ?? 0)) < 0.01)
        #expect(tracks.items.allSatisfy { $0.albumID == album.id && $0.albumName == album.name })
    }

    @Test("A known track, mapped: artists, album artist, album, year, genres, duration")
    func knownTrack() async throws {
        let client = try await JellyfinTestServer.client()
        let found = try await client.tracks(TrackQuery(searchTerm: "Blue Parade"))
        let track = try #require(found.items.first { $0.albumName == "Iron Gardens" })
        #expect(track.name == "Blue Parade")
        #expect(JellyfinTestServer.names(track.artists.map(\.name)) == ["MC Polder", "Lyric Engine"])
        #expect(track.artists.allSatisfy { $0.id != nil })
        #expect(track.albumArtist?.name == "MC Polder")
        #expect(track.albumArtist?.id != nil)
        #expect(track.primaryArtist?.name == "MC Polder")
        #expect(track.year == 2016)
        #expect(JellyfinTestServer.names(track.genres) == ["Hip-Hop", "Nederhop"])
        #expect(track.duration == 6)
        #expect(track.trackNumber == 1)
        #expect(track.discNumber == 1)
        #expect(track.imageTag == nil)
        #expect(track.albumImageTag != nil)
        #expect(track.dateAdded != nil)
        #expect(track.playlistEntryID == nil)

        let album = try await client.album(id: try #require(track.albumID))
        #expect(album.name == "Iron Gardens")
        #expect(album.artists.map(\.name) == ["MC Polder"])
        #expect(album.year == 2016)
        #expect(album.imageTag == track.albumImageTag)

        let again = try await client.track(id: track.id)
        #expect(again.name == track.name && again.albumID == track.albumID && again.duration == track.duration)
    }

    @Test("Tracks by id keep the order asked; by artist; by genre with the genre's count")
    func trackQueries() async throws {
        let client = try await JellyfinTestServer.client()
        let some = try await client.tracks(TrackQuery(limit: 30)).items
        let ids = Array(some.map(\.id).shuffled().prefix(12))
        let byID = try await client.tracks(TrackQuery(ids: ids))
        #expect(byID.items.map(\.id) == ids)

        let artist = try #require(try await client.artists().items.first { $0.name == "Blue Room Trio" })
        let byArtist = try await client.tracks(TrackQuery(artistID: artist.id))
        #expect(!byArtist.items.isEmpty)
        #expect(byArtist.items.allSatisfy { $0.artistKeys.contains(artist.key) || $0.artists.contains { $0.id == artist.id } })

        let genres = try await client.genres()
        // With internet (GitHub's runners), the online providers add the genres
        // they find for an artist ("alternative rock", "punk", "house"), which
        // no song carries: seen on CI, 27 genres where the files have 23. A real
        // server has those too, so the files' own are the ones with songs.
        let withSongs = genres.filter { ($0.songCount ?? 0) > 0 }
        #expect(withSongs.count >= 23)
        let genre = try #require(withSongs.first)
        let inGenre = try await client.tracks(TrackQuery(genre: genre.name, limit: 0))
        #expect(inGenre.totalCount == genre.songCount)
        JellyfinTestServer.measure("genres: \(genres.count): \(genres.map(\.name).joined(separator: " | "))")
    }

    @Test("All 358 tracks, each once; time by page size and pages at once")
    func allTracks() async throws {
        let client = try await JellyfinTestServer.client()
        let calls = JellyfinProgressRecorder()
        let tracks = try await client.allTracks { calls.add($0, $1) }
        #expect(tracks.count == 358)
        #expect(Set(tracks.map(\.id)).count == 358)
        #expect(calls.values.last.map { $0 == (358, 358) } == true)
        #expect(tracks.allSatisfy { !$0.name.isEmpty && $0.duration > 0 && $0.albumID != nil && !$0.genres.isEmpty })

        // A small page size: many pages, still each track once. (Tracks with
        // the same SortName — 32 here, "0001 - 0005 - Red Story" twice and
        // so on — can come in another order than in one page; on 12.4 never
        // so that one is missed or doubled: 3 runs of pages of 7 by curl.)
        let small = try await client.allTracks(pageSize: 7, concurrentPages: 3, progress: nil)
        #expect(small.count == 358)
        #expect(Set(small.map(\.id)) == Set(tracks.map(\.id)))

        for (size, concurrent) in [(2000, 1), (500, 1), (200, 1), (200, 3), (100, 1), (100, 3), (50, 1), (50, 3), (25, 1), (25, 3)] {
            var times: [Duration] = []
            for _ in 0..<3 {
                let elapsed = try await clock.measure {
                    let all = try await client.allTracks(pageSize: size, concurrentPages: concurrent, progress: nil)
                    #expect(all.count == 358)
                }
                times.append(elapsed)
            }
            let pages = (358 + size - 1) / size
            JellyfinTestServer.measure("allTracks pageSize \(size) (\(pages) pages, \(concurrent) at once): "
                                       + times.map(JellyfinTestServer.ms).joined(separator: ", "))
        }
    }

    @Test("Playlists: create, list, add, move, remove, mix, search, delete")
    func playlists() async throws {
        let client = try await JellyfinTestServer.client()
        let pool = try await client.tracks(TrackQuery(sort: .random, limit: 4)).items
        try #require(Set(pool.map(\.id)).count == 4)
        let (a, b, c, d) = (pool[0].id, pool[1].id, pool[2].id, pool[3].id)
        let name = "Jukebox kit test \(UUID().uuidString.prefix(8))"

        let id = try await client.createPlaylist(name: name, trackIDs: [a, b])
        do {
            let listed = try #require(try await client.playlists().first { $0.id == id })
            #expect(listed.name == name)
            #expect(listed.trackCount == 2)
            #expect(listed.dateAdded != nil)

            try await client.addToPlaylist(playlistID: id, trackIDs: [c, d])
            var entries = try await client.playlistTracks(playlistID: id)
            #expect(entries.map(\.id) == [a, b, c, d])
            #expect(entries.allSatisfy { $0.playlistEntryID != nil })
            JellyfinTestServer.measure("playlist entry ids equal the track ids: \(entries.allSatisfy { $0.playlistEntryID == $0.id })")

            try await client.movePlaylistEntry(playlistID: id, entryID: try #require(entries[3].playlistEntryID), to: 0)
            entries = try await client.playlistTracks(playlistID: id)
            #expect(entries.map(\.id) == [d, a, b, c])

            try await client.removeFromPlaylist(playlistID: id, entryIDs: [try #require(entries[2].playlistEntryID)])
            entries = try await client.playlistTracks(playlistID: id)
            #expect(entries.map(\.id) == [d, a, c])
            #expect(try await client.playlists().first { $0.id == id }?.trackCount == 3)

            let mix = try await client.instantMix(seedID: id, limit: 10)
            JellyfinTestServer.measure("instantMix of a playlist: \(mix.count) tracks")

            let search = try await client.search(String(name.suffix(8)))
            #expect(search.playlists.map(\.id) == [id])
        } catch {
            try? await client.deletePlaylist(id: id)
            throw error
        }
        try await client.deletePlaylist(id: id)
        #expect(try await !client.playlists().contains(where: { $0.id == id }))
        await #expect(throws: JellyfinError.notFound) { _ = try await client.playlistTracks(playlistID: id) }
    }

    @Test("Similar artists and instant mixes from a track, an album, an artist, a genre")
    func similarAndMixes() async throws {
        let client = try await JellyfinTestServer.client()
        let artist = try #require(try await client.artists().items.first { $0.name == "MC Polder" })
        let similar = try await client.similarArtists(artistID: artist.id, limit: 10)
        #expect(!similar.contains { $0.id == artist.id })
        JellyfinTestServer.measure("similarArtists(MC Polder): \(similar.map(\.name))")

        let album = try #require(try await client.albums(AlbumQuery(artistID: artist.id)).items.first)
        let track = try #require(try await client.tracks(TrackQuery(albumID: album.id)).items.first)
        let genre = try #require(try await client.genres().first { track.genres.contains($0.name) })
        for (kind, seed) in [("track", track.id), ("album", album.id), ("artist", artist.id), ("genre", genre.id)] {
            let mix = try await client.instantMix(seedID: seed, limit: 15)
            #expect(!mix.isEmpty, "\(kind)")
            #expect(mix.count <= 15)
            #expect(mix.allSatisfy { $0.duration > 0 && !$0.name.isEmpty })
            let artists = Set(mix.compactMap { $0.albumArtist?.name })
            JellyfinTestServer.measure("instantMix(\(kind)): \(mix.count) tracks, first is the seed: \(mix.first?.id == seed), album artists \(artists.sorted())")
        }
    }

    @Test("Search: four kinds at once, against /Search/Hints")
    func search() async throws {
        let client = try await JellyfinTestServer.client()
        let results = try await client.search("night", limit: 10)
        #expect(results.artists.map(\.name).contains("Nightdrive"))
        #expect(!results.tracks.isEmpty && results.tracks.count <= 10)
        #expect(results.tracks.allSatisfy { $0.name.localizedCaseInsensitiveContains("night") || $0.artistLine.localizedCaseInsensitiveContains("night") || ($0.albumName ?? "").localizedCaseInsensitiveContains("night") })

        var ours: [Duration] = []
        var hints: [Duration] = []
        for term in ["night", "blue", "a"] {
            for _ in 0..<3 {
                ours.append(try await clock.measure { _ = try await client.search(term, limit: 20) })
                hints.append(try await clock.measure {
                    try await client.send("GET", "/Search/Hints", query: client.userQuery(client.requireUser()) + [
                        URLQueryItem(name: "searchTerm", value: term), URLQueryItem(name: "limit", value: "80"),
                        URLQueryItem(name: "includeItemTypes", value: "MusicArtist,MusicAlbum,Audio,Playlist")])
                })
            }
        }
        JellyfinTestServer.measure("search (4 at once): " + ours.map(JellyfinTestServer.ms).joined(separator: ", "))
        JellyfinTestServer.measure("/Search/Hints:      " + hints.map(JellyfinTestServer.ms).joined(separator: ", "))
    }

    @Test("No lyrics on this library: nil")
    func lyrics() async throws {
        let client = try await JellyfinTestServer.client()
        let track = try #require(try await client.tracks(TrackQuery(limit: 1)).items.first)
        #expect(try await client.lyrics(trackID: track.id) == nil)
    }

    // MARK: Changes

    @Test("Favourites round trip for a track, an album and an artist")
    func favorites() async throws {
        let client = try await JellyfinTestServer.client()
        let track = try #require(try await client.tracks(TrackQuery(sort: .random, limit: 1)).items.first)
        let album = try await client.album(id: try #require(track.albumID))
        let artist = try await client.artist(id: try #require(album.artists.first?.id))

        try await client.setFavorite(true, itemID: track.id)
        try await client.setFavorite(true, itemID: album.id)
        try await client.setFavorite(true, itemID: artist.id)
        do {
            #expect(try await client.track(id: track.id).isFavorite)
            #expect(try await client.album(id: album.id).isFavorite)
            #expect(try await client.artist(id: artist.id).isFavorite)
            #expect(try await client.tracks(TrackQuery(favoritesOnly: true)).items.contains { $0.id == track.id })
            #expect(try await client.albums(AlbumQuery(favoritesOnly: true)).items.contains { $0.id == album.id })
            #expect(try await client.artists(favoritesOnly: true).items.contains { $0.id == artist.id })
        } catch {
            for id in [track.id, album.id, artist.id] { try? await client.setFavorite(false, itemID: id) }
            throw error
        }
        for id in [track.id, album.id, artist.id] { try await client.setFavorite(false, itemID: id) }
        #expect(try await !client.track(id: track.id).isFavorite)
        #expect(try await !client.album(id: album.id).isFavorite)
        #expect(try await !client.artist(id: artist.id).isFavorite)
    }

    @Test("Playback reports: the start counts the play and sets the date; the stop adds nothing")
    func playbackReports() async throws {
        let client = try await JellyfinTestServer.client()
        let track = try #require(try await client.tracks(TrackQuery(sort: .random, limit: 1)).items.first)
        let before = try await client.track(id: track.id)
        let session = UUID().uuidString
        let started = Date()

        await client.reportStart(PlaybackReport(trackID: track.id, position: 0, isPaused: false, playSessionID: session))
        let afterStart = try await client.track(id: track.id)
        await client.reportProgress(PlaybackReport(trackID: track.id, position: track.duration / 2, isPaused: true, playSessionID: session))
        await client.reportStopped(PlaybackReport(trackID: track.id, position: track.duration, isPaused: false, playSessionID: session))
        let afterStop = try await client.track(id: track.id)

        #expect(afterStart.playCount == before.playCount + 1)
        #expect(afterStop.playCount == before.playCount + 1)
        let played = try #require(afterStop.lastPlayed)
        #expect(abs(played.timeIntervalSince(started)) < 120)
        JellyfinTestServer.measure("play count \(before.playCount) → \(afterStart.playCount) after start → \(afterStop.playCount) after stop at the end; last played \(played)")
    }

    // MARK: Playing

    @Test("Stream URLs: the file itself at .original, HLS at .low that loads; ApiKey, not api_key")
    func streams() async throws {
        let client = try await JellyfinTestServer.client()
        let user = try client.requireUser()
        // One track per format, by the file's extension.
        let response = try await client.send("GET", "/Items", query: client.userQuery(user) + [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"), URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Path")])
        let object = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let items = try #require(object["Items"] as? [[String: Any]])
        var byFormat: [String: String] = [:]
        for item in items {
            guard let path = item["Path"] as? String, let id = item["Id"] as? String else { continue }
            let ext = String(path.split(separator: ".").last ?? "").lowercased()
            if byFormat[ext] == nil { byFormat[ext] = id }
        }
        #expect(Set(byFormat.keys) == ["mp3", "flac", "m4a"])

        let expectedType = ["mp3": "audio/mpeg", "flac": "audio/flac", "m4a": "audio/mp4"]
        var hlsLoaded = 0
        for format in ["mp3", "flac", "m4a"] {
            let id = try #require(byFormat[format])
            let original = try await JellyfinTestServer.fetch(client.streamURL(trackID: id, quality: .original, playSessionID: UUID().uuidString))
            #expect(original.status == 200, "\(format)")
            #expect(original.jellyfinHeader("Content-Type") == expectedType[format], "\(format)")
            #expect(original.body.count > 10_000, "\(format)")
            JellyfinTestServer.measure("stream \(format) .original: \(original.status) \(original.jellyfinHeader("Content-Type") ?? "-") \(original.body.count) bytes")

            let lowURL = client.streamURL(trackID: id, quality: .low, playSessionID: UUID().uuidString)
            let low = try await JellyfinTestServer.fetch(lowURL)
            #expect(low.status == 200, "\(format)")
            let type = low.jellyfinHeader("Content-Type") ?? "-"
            var line = "stream \(format) .low: \(low.status) \(type) \(low.body.count) bytes"
            if type.contains("mpegurl") {
                // The master playlist names the media playlist, relative to /Audio/{id}/.
                let master = String(decoding: low.body, as: UTF8.self)
                let mediaRef = try #require(master.split(separator: "\n").first { !$0.hasPrefix("#") && !$0.isEmpty })
                let mediaURL = try #require(URL(string: String(mediaRef), relativeTo: lowURL)?.absoluteURL)
                let media = try await JellyfinTestServer.fetch(mediaURL)
                #expect(media.status == 200)
                let mediaText = String(decoding: media.body, as: UTF8.self)
                let segmentRef = try #require(mediaText.split(separator: "\n").first { !$0.hasPrefix("#") && !$0.isEmpty })
                let segment = try await JellyfinTestServer.fetch(try #require(URL(string: String(segmentRef), relativeTo: mediaURL)?.absoluteURL))
                #expect(segment.status == 200)
                #expect(segment.body.count > 1000)
                line += "; media playlist \(media.status), first segment \(segment.status) \(segment.jellyfinHeader("Content-Type") ?? "-") \(segment.body.count) bytes"
                hlsLoaded += 1
            }
            JellyfinTestServer.measure(line)
        }
        #expect(hlsLoaded >= 1)

        // The FLAC is a sine tone of 105 kbit/s, under .low's 128: sent as it
        // is. Under a cap below its bitrate it is HLS too, and loads.
        let flac = try #require(byFormat["flac"])
        let capped = try #require(URL(string: client.streamURL(trackID: flac, quality: .low, playSessionID: UUID().uuidString)
            .absoluteString.replacingOccurrences(of: "MaxStreamingBitrate=128000", with: "MaxStreamingBitrate=64000")))
        let master = try await JellyfinTestServer.fetch(capped)
        #expect(master.jellyfinHeader("Content-Type") == "application/vnd.apple.mpegurl")
        let mediaRef = try #require(String(decoding: master.body, as: UTF8.self).split(separator: "\n").first { !$0.hasPrefix("#") })
        let media = try await JellyfinTestServer.fetch(try #require(URL(string: String(mediaRef), relativeTo: capped)?.absoluteURL))
        #expect(media.status == 200)
        #expect(String(decoding: media.body, as: UTF8.self).contains("#EXT-X-ENDLIST"))
        JellyfinTestServer.measure("stream flac at 64 kbit/s: \(master.status) \(master.jellyfinHeader("Content-Type") ?? "-"), media playlist \(media.status)")

        // Which name for the token this server takes in a URL.
        let id = try #require(byFormat["mp3"])
        let withApiKey = client.streamURL(trackID: id, quality: .original, playSessionID: "probe")
        let withOldName = try #require(URL(string: withApiKey.absoluteString.replacingOccurrences(of: "ApiKey=", with: "api_key=")))
        let new = try await JellyfinTestServer.fetch(withApiKey).status
        let old = try await JellyfinTestServer.fetch(withOldName).status
        #expect(new == 200)
        JellyfinTestServer.measure("token in the URL: ApiKey \(new), api_key \(old)")
    }

    @Test("Image URL: 200 image/jpeg for an album")
    func image() async throws {
        let client = try await JellyfinTestServer.client()
        let album = try #require(try await client.albums(AlbumQuery(limit: 1)).items.first)
        let artwork = try #require(album.artwork)
        let image = try await JellyfinTestServer.fetch(client.imageURL(artwork, maxPixelSize: 300))
        #expect(image.status == 200)
        #expect(image.jellyfinHeader("Content-Type") == "image/jpeg")
        #expect(image.body.starts(with: [0xFF, 0xD8]))
        JellyfinTestServer.measure("image: \(image.status) \(image.jellyfinHeader("Content-Type") ?? "-") \(image.body.count) bytes, cache \(image.jellyfinHeader("Cache-Control") ?? "-")")
    }
}
