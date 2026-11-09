// The contract (Server/MusicServer.swift) as the app relies on it, the same
// checks on every test server that runs: Jellyfin through JellyfinServer,
// Navidrome through SubsonicClient, both opened as the app opens them
// (MusicServers.detect, signIn, open) and used only as `any MusicServer`.
// Where the two must differ the contract says how (topSongs, the mixes'
// answers without agents); everywhere else one rule for both. And the two
// servers hold one made-up library, so they must give the same one.
//
// Skipped where neither server runs; each server's case where it does not.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum TestServers {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let open: @Sendable () async throws -> any MusicServer
        var testDescription: String { name }
    }

    /// A device of its own: Jellyfin signs out a device's other tokens when
    /// it signs in again (JellyfinTestServer).
    static let jellyfinIdentity = JellyfinTestServer.identity("contract")

    static let jellyfin = Task<any MusicServer, any Error> {
        guard let url = JellyfinTestServer.url else { throw MusicServerError.invalidServerAddress }
        let server = try await MusicServers.detect(url.absoluteString, identity: jellyfinIdentity)
        let credentials = try await MusicServers.signIn(to: server, identity: jellyfinIdentity)
            .signIn(username: JellyfinTestServer.user, password: JellyfinTestServer.password)
        return MusicServers.open(credentials, identity: jellyfinIdentity)
    }

    static let navidrome = Task<any MusicServer, any Error> {
        let client = try await NavidromeTestServer.client()
        return MusicServers.open(client.credentials, identity: NavidromeTestServer.identity)
    }

    static var available: [Case] {
        var list: [Case] = []
        if JellyfinTestServer.url != nil { list.append(Case(name: "Jellyfin") { try await jellyfin.value }) }
        if NavidromeTestServer.url != nil { list.append(Case(name: "Navidrome") { try await navidrome.value }) }
        return list
    }

    static var both: Bool { JellyfinTestServer.url != nil && NavidromeTestServer.url != nil }

    /// Joined credits ("A; B") as names, as the libraries split them or not.
    static func names(_ list: [String]) -> Set<String> { Set(JellyfinTestServer.names(list)) }

    static func measure(_ server: Case, _ line: String) {
        print("SERVERS-MEASURE \(server.name): \(line)")
    }
}

@Suite("Servers: the contract, on every test server", .serialized, .enabled(if: !TestServers.available.isEmpty))
struct ServerContractTests {
    // MARK: The library

    @Test("The whole library: 358 tracks, 54 albums, 23 album artists, each consistent with the others",
          arguments: TestServers.available)
    func library(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let progress = SubsonicProgressRecorder()
        let tracks = try await server.allTracks { progress.add($0, $1) }
        #expect(tracks.count == 358 && Set(tracks.map(\.id)).count == 358)
        #expect(progress.values.last.map { $0 == (358, 358) } == true)
        #expect(tracks.allSatisfy { !$0.name.isEmpty && $0.duration > 0 && $0.albumArtist != nil && !$0.genres.isEmpty })
        #expect(tracks.allSatisfy { $0.artwork != nil && $0.playlistEntryID == nil })

        let albums = try await server.allAlbums()
        #expect(albums.count == 54 && Set(albums.map(\.id)).count == 54)
        #expect(albums.reduce(0) { $0 + ($1.trackCount ?? 0) } == 358)
        #expect(Set(tracks.compactMap(\.albumID)) == Set(albums.map(\.id)))

        let artists = try await server.allArtists()
        #expect(artists.count == 23 && Set(artists.map(\.id)).count == 23)
        #expect(Set(albums.compactMap { $0.artists.first?.name }) == Set(artists.map(\.name)))
        #expect(Set(tracks.compactMap { $0.albumArtist?.name }) == Set(artists.map(\.name)))

        let genres = try await server.genres()
        #expect(!genres.isEmpty && Set(genres.map(\.id)).count == genres.count)
        let playlists = try await server.playlists()
        #expect(Set(playlists.map(\.id)).count == playlists.count)
        TestServers.measure(test, "\(tracks.count) tracks, \(albums.count) albums, \(artists.count) artists, \(genres.count) genres")
    }

    @Test("Jellyfin and Navidrome give the same library: tracks, credits, genres, years, lengths",
          .enabled(if: TestServers.both))
    func sameLibrary() async throws {
        let jellyfin = try await TestServers.jellyfin.value
        let navidrome = try await TestServers.navidrome.value
        func key(_ t: Track) -> String {
            "\(t.albumArtist?.name ?? "")|\(t.albumName ?? "")|\(t.discNumber ?? 1)|\(t.trackNumber ?? 0)|\(t.name)"
        }
        let ours = try await jellyfin.allTracks(progress: nil)
        let theirs = try await navidrome.allTracks(progress: nil)
        #expect(ours.map(key).sorted() == theirs.map(key).sorted())
        let other = Dictionary(theirs.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var differ: [String] = []
        for track in ours {
            guard let twin = other[key(track)] else { continue }
            if TestServers.names(track.artists.map(\.name)) != TestServers.names(twin.artists.map(\.name)) { differ.append("artists \(key(track))") }
            if TestServers.names(track.genres) != TestServers.names(twin.genres) { differ.append("genres \(key(track))") }
            if track.year != twin.year { differ.append("year \(key(track))") }
            if abs(track.duration - twin.duration) > 1 { differ.append("length \(key(track)): \(track.duration) \(twin.duration)") }
        }
        #expect(differ.isEmpty, "\(differ.prefix(10))")

        let albums = { (list: [Album]) in Set(list.map { "\($0.artists.first?.name ?? "")|\($0.name)|\($0.year ?? 0)|\($0.trackCount ?? 0)" }) }
        #expect(albums(try await jellyfin.allAlbums()) == albums(try await navidrome.allAlbums()))
        #expect(Set(try await jellyfin.allArtists().map(\.name)) == Set(try await navidrome.allArtists().map(\.name)))
        let split = { (list: [Genre]) in TestServers.names(list.filter { ($0.songCount ?? 1) > 0 }.map(\.name)) }
        let genres = (split(try await jellyfin.genres()), split(try await navidrome.genres()))
        // Jellyfin with internet adds genres its providers find for an artist,
        // which no file has (JellyfinIntegrationTests): the files' are in both.
        #expect(genres.1.isSubset(of: genres.0))
        print("SERVERS-MEASURE the same library: \(ours.count) tracks match by artist, album, disc, track and title; genres \(genres.0.count) / \(genres.1.count)")
    }

    // MARK: One item

    @Test("One track, album and artist by id; an unknown id is .notFound", arguments: TestServers.available)
    func items(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let tracks = try await server.allTracks(progress: nil)
        let track = try #require(tracks.first { $0.name == "Blue Parade" && $0.albumName == "Iron Gardens" })
        #expect(TestServers.names(track.artists.map(\.name)) == ["MC Polder", "Lyric Engine"])
        #expect(track.albumArtist?.name == "MC Polder" && track.year == 2016 && track.trackNumber == 1)
        let again = try await server.track(id: track.id)
        #expect(again.name == track.name && again.albumID == track.albumID && again.duration == track.duration)
        let album = try await server.album(id: try #require(track.albumID))
        #expect(album.name == "Iron Gardens" && album.artists.first?.name == "MC Polder" && album.year == 2016)
        #expect(album.trackCount == 8)
        let artist = try await server.artist(id: try #require(album.artists.first?.id))
        #expect(artist.name == "MC Polder" && artist.albumCount == 3)

        let unknown = "ffffffffffffffffffffffffffffffff"
        await #expect(throws: MusicServerError.notFound) { _ = try await server.track(id: unknown) }
        await #expect(throws: MusicServerError.notFound) { _ = try await server.album(id: unknown) }
        await #expect(throws: MusicServerError.notFound) { _ = try await server.artist(id: unknown) }
    }

    @Test("An album's tracks in disc and track order, as many as it says", arguments: TestServers.available)
    func albumTracks(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        for album in try await server.allAlbums() {
            let tracks = try await server.albumTracks(albumID: album.id)
            #expect(tracks.count == album.trackCount, "\(album.name)")
            let order = tracks.map { [$0.discNumber ?? 1, $0.trackNumber ?? 0] }
            #expect(order == order.sorted { $0.lexicographicallyPrecedes($1) }, "\(album.name)")
            #expect(tracks.allSatisfy { $0.albumID == album.id })
        }
    }

    @Test("Search finds an artist by part of its name", arguments: TestServers.available)
    func search(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let results = try await server.search("night", limit: 10)
        #expect(results.artists.map(\.name).contains("Nightdrive"))
        #expect(!results.tracks.isEmpty && results.tracks.count <= 10 && results.albums.count <= 10)
        #expect(try await server.search("zzzqqq", limit: 10).isEmpty)
    }

    // MARK: Changes

    @Test("Favourites on and off for a track, its album and the album's artist", arguments: TestServers.available)
    func favourites(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let track = try #require(try await server.allTracks(progress: nil).randomElement())
        let album = try await server.album(id: try #require(track.albumID))
        let artistID = try #require(album.artists.first?.id)
        let items: [ItemRef] = [.track(track.id), .album(album.id), .artist(artistID)]
        func favourites() async throws -> [Bool] {
            [try await server.track(id: track.id).isFavorite, try await server.album(id: album.id).isFavorite,
             try await server.artist(id: artistID).isFavorite]
        }
        for item in items { try await server.setFavorite(true, item: item) }
        do {
            #expect(try await favourites() == [true, true, true])
            #expect(try await server.allArtists().first { $0.id == artistID }?.isFavorite == true)
        } catch {
            for item in items { try? await server.setFavorite(false, item: item) }
            throw error
        }
        for item in items { try await server.setFavorite(false, item: item) }
        #expect(try await favourites() == [false, false, false])
    }

    @Test("A playlist: create, add (a song twice), move by entry, remove by entry, find, delete",
          arguments: TestServers.available)
    func playlists(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let pool = Array(try await server.allTracks(progress: nil).shuffled().prefix(4))
        let (a, b, c, d) = (pool[0].id, pool[1].id, pool[2].id, pool[3].id)
        let name = "Jukebox contract \(UUID().uuidString.prefix(8))"
        let id = try await server.createPlaylist(name: name, trackIDs: [a, b])
        func entries() async throws -> [Track] { try await server.playlistTracks(playlistID: id) }
        do {
            let listed = try #require(try await server.playlists().first { $0.id == id })
            #expect(listed.name == name && listed.trackCount == 2 && !listed.isReadOnly)

            try await server.addToPlaylist(playlistID: id, trackIDs: [c, d, a])
            var now = try await entries()
            #expect(now.map(\.id) == [a, b, c, d, a])
            let entryIDs = now.compactMap(\.playlistEntryID)
            #expect(entryIDs.count == 5 && Set(entryIDs).count == 5)

            // `to` is where the entry ends up (Jellyfin: A to 2 in A B C D gives B C A D).
            try await server.movePlaylistEntry(playlistID: id, entryID: try #require(now[0].playlistEntryID), to: 2)
            now = try await entries()
            #expect(now.map(\.id) == [b, c, a, d, a])
            try await server.movePlaylistEntry(playlistID: id, entryID: try #require(now[4].playlistEntryID), to: 0)
            now = try await entries()
            #expect(now.map(\.id) == [a, b, c, a, d])

            try await server.removeFromPlaylist(playlistID: id, entryIDs: [try #require(now[3].playlistEntryID)])
            now = try await entries()
            #expect(now.map(\.id) == [a, b, c, d])
            try await server.removeFromPlaylist(playlistID: id, entryIDs: [try #require(now[0].playlistEntryID),
                                                                           try #require(now[2].playlistEntryID)])
            #expect(try await entries().map(\.id) == [b, d])
            #expect(try await server.playlists().first { $0.id == id }?.trackCount == 2)

            #expect(try await server.search(String(name.suffix(8)), limit: 10).playlists.map(\.id) == [id])
            #expect(try await !server.instantMix(from: .playlist(id), limit: 10).isEmpty)
        } catch {
            try? await server.deletePlaylist(id: id)
            throw error
        }
        try await server.deletePlaylist(id: id)
        #expect(try await !server.playlists().contains { $0.id == id })
        await #expect(throws: MusicServerError.notFound) { _ = try await server.playlistTracks(playlistID: id) }
    }

    @Test("Playback reports: one play counted, once, at .played; the date it was played", arguments: TestServers.available)
    func reports(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let track = try #require(try await server.allTracks(progress: nil).randomElement())
        let before = try await server.track(id: track.id).playCount
        let session = UUID().uuidString
        let started = Date()
        func report(_ event: PlaybackEvent, at position: TimeInterval, paused: Bool = false) async {
            await server.report(event, PlaybackReport(trackID: track.id, position: position, isPaused: paused, playSessionID: session))
        }
        await report(.nowPlaying, at: 0)
        let afterStart = try await server.track(id: track.id).playCount
        await report(.played, at: 1)
        let afterPlayed = try await server.track(id: track.id)
        await report(.progress, at: track.duration / 2, paused: true)
        await report(.progress, at: track.duration / 2)
        await report(.stopped, at: track.duration)
        let afterStop = try await server.track(id: track.id)
        let counts: [Int] = [afterStart, afterPlayed.playCount, afterStop.playCount]
        #expect(counts == [before, before + 1, before + 1])
        let played = try #require(afterStop.lastPlayed)
        #expect(abs(played.timeIntervalSince(started)) < 120)
        TestServers.measure(test, "play count \(before) → \(afterStart) at nowPlaying → \(afterPlayed.playCount) at played → \(afterStop.playCount) after progress and stopped at the end")
    }

    // MARK: Playing

    @Test("Stream, artwork and download URLs answer with what they say, fetched with no header",
          arguments: TestServers.available)
    func urls(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let tracks = try await server.allTracks(progress: nil)
        let track = try #require(tracks.first { $0.name == "Blue Parade" && $0.albumName == "Iron Gardens" })
        for quality in StreamQuality.allCases {
            let got = try await JellyfinTestServer.fetch(server.streamURL(for: track, quality: quality, playSessionID: UUID().uuidString))
            let type = got.jellyfinHeader("Content-Type") ?? "-"
            #expect(got.status == 200, "\(quality)")
            #expect(type.hasPrefix("audio/") || type.contains("mpegurl"), "\(quality): \(type)")
        }
        let album = try await server.album(id: try #require(track.albumID))
        for artwork in [album.artwork, track.artwork].compactMap({ $0 }) {
            let image = try await JellyfinTestServer.fetch(server.artworkURL(artwork, maxPixelSize: 300))
            #expect(image.status == 200 && image.jellyfinHeader("Content-Type")?.hasPrefix("image/") == true)
        }
        for quality in DownloadQuality.allCases {
            let got = try await JellyfinTestServer.fetch(server.downloadURL(for: track, quality: quality))
            let type = got.jellyfinHeader("Content-Type")
            #expect(got.status == 200, "\(quality)")
            #expect(type?.hasPrefix("audio/") == true, "\(quality): \(type ?? "-")")
            #expect(OfflineDownloadIntegrationTests.kind(of: got.body) == OfflineFile.fileExtension(contentType: type), "\(quality)")
            TestServers.measure(test, "download m4a .\(quality): \(type ?? "-") \(got.body.count) bytes")
        }
        #expect(try await server.downloadsAllowed())
        #expect(try await server.lyrics(for: track) == nil)
    }

    // MARK: What only the server knows

    @Test("Mixes, similar artists, top songs: answers as the capabilities say", arguments: TestServers.available)
    func serverOnly(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        #expect(try await server.currentCapabilities() == server.capabilities)
        let tracks = try await server.allTracks(progress: nil)
        let seed = try #require(tracks.first { $0.albumArtist?.name == "MC Polder" })
        let artistID = try #require(seed.albumArtist?.id)
        let genre = try #require(try await server.genres().first { seed.genres.contains($0.name) })
        for (name, mix) in [("track", MixSeed.track(seed.id)), ("album", .album(try #require(seed.albumID))),
                            ("artist", .artist(artistID)), ("genre", .genre(name: genre.name, id: genre.id))] {
            let songs = try await server.instantMix(from: mix, limit: 15)
            #expect(!songs.isEmpty && songs.count <= 15, "\(name)")
        }
        // A genre the server has no id for (split out of a joined tag).
        #expect(try await server.instantMix(from: .genre(name: "Nederhop", id: nil), limit: 15).count <= 15)

        let similar = try await server.similarArtists(artistID: artistID, limit: 10)
        #expect(!similar.contains { $0.id == artistID } && similar.count <= 10)
        if server.capabilities.contains(.topSongs) {
            #expect(try await server.topSongs(of: ArtistRef(id: artistID, name: "MC Polder"), limit: 10).count <= 10)
        } else {
            await #expect(throws: MusicServerError.unsupported(.topSongs)) {
                _ = try await server.topSongs(of: ArtistRef(id: artistID, name: "MC Polder"), limit: 10)
            }
        }
        TestServers.measure(test, "similar artists of MC Polder: \(similar.map(\.name)); capabilities \(server.capabilities.map(\.rawValue).sorted())")
    }
}
