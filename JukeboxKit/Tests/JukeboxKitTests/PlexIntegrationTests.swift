// PlexServer against the real Plex Media Server of dev/plex-test-server.sh
// (1.43.5, unclaimed, on a network with no way out; the made-up library of
// the Jellyfin test server: 23 album artists, 54 albums, 358 tracks in MP3,
// FLAC and M4A, read by the agent that has no genres). Skipped when
// PLEX_URL is not set; dev/kit-test.sh sets it, and runs these from inside
// the server's own network namespace (127.0.0.1), when the container runs.
//
// Detected at its address as the app detects it. Unclaimed, the server
// takes any request from itself, with or without a token: so the session
// here has none, and a made-up token goes through the token's way in (the
// library, the owner's name) without proving the token. This tests
// Jukebox's calls, not Plex's own accounts. What the tests change they
// change back, but play counts.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum PlexTestServer {
    static let url = ProcessInfo.processInfo.environment["PLEX_URL"]
    static let identity = ClientIdentity(clientName: "JukeboxKitTests", clientVersion: "1.0",
                                         deviceName: "Kit tests: Plex", deviceID: "jukebox-kit-plex")

    static let session = Task<PlexServer, any Error> {
        guard let url else { throw MusicServerError.invalidServerAddress }
        let found = try await detected()
        let credentials = ServerCredentials(kind: .plex, serverURL: found.url, serverID: found.id,
                                            serverName: found.name, serverVersion: found.version, userID: "kit",
                                            userName: "kit", secret: .plexToken(""),
                                            capabilities: PlexServer.capabilities)
        return try #require(MusicServers.open(credentials, identity: identity) as? PlexServer)
    }

    static func detected() async throws -> DetectedServer {
        guard let url else { throw MusicServerError.invalidServerAddress }
        return try await MusicServers.detect(url, identity: identity)
    }

    static func server() async throws -> PlexServer { try await session.value }

    /// A plain GET, as AVPlayer, the image view or a download task makes it.
    static func fetch(_ url: URL, range: String? = nil) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        return try await URLSessionTransport().send(request)
    }

    static func header(_ response: HTTPResponse, _ name: String) -> String? {
        response.headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

@Suite("Plex: the real server", .serialized, .enabled(if: PlexTestServer.url != nil), .timeLimit(.minutes(1)))
struct PlexIntegrationTests {
    @Test("Found at its address as Plex, and its library: 358 songs, 54 albums, 23 artists")
    func library() async throws {
        let found = try await PlexTestServer.detected()
        #expect(found.kind == .plex && found.version.hasPrefix("1.") && found.url.port == 32400)
        let way = try #require(MusicServers.signIn(to: found, identity: PlexTestServer.identity) as? any APIKeySignIn)
        let byToken = try await way.signIn(apiKey: "made-up")
        #expect(byToken.serverID == found.id && byToken.secret == .plexToken("made-up") && byToken.userName == "Plex")
        let server = try await PlexTestServer.server()
        let tracks = try await server.allTracks(progress: nil)
        let albums = try await server.allAlbums()
        let artists = try await server.allArtists()
        #expect(tracks.count == 358 && albums.count == 54 && artists.count == 23)
        #expect(tracks.allSatisfy { $0.fileKey != nil && $0.albumArtist != nil && $0.duration > 4 })
        #expect(Set(tracks.compactMap(\.container)) == ["mp3", "flac", "mp4"])
        let album = try #require(albums.first)
        let inOrder = try await server.albumTracks(albumID: album.id)
        #expect(inOrder.map(\.trackNumber) == inOrder.map(\.trackNumber).sorted { ($0 ?? 0) < ($1 ?? 0) })
        #expect(try await server.album(id: album.id).name == album.name)
        await #expect(throws: MusicServerError.notFound) { try await server.track(id: "999999") }
        let searched = try await server.search(String(album.name.prefix(5)), limit: 10)
        #expect(searched.albums.contains { $0.id == album.id })
    }

    @Test("The file as it is, with its length and ranges; capped, an MP3; covers")
    func files() async throws {
        let server = try await PlexTestServer.server()
        let tracks = try await server.allTracks(progress: nil)
        let mp3 = try #require(tracks.first { $0.container == "mp3" })
        let file = try await PlexTestServer.fetch(server.streamURL(for: mp3, quality: .original, playSessionID: "kit"))
        #expect(file.status == 200 && PlexTestServer.header(file, "Content-Type") == "audio/mpeg")
        #expect(PlexTestServer.header(file, "Content-Length") == String(file.body.count))
        let part = try await PlexTestServer.fetch(server.streamURL(for: mp3, quality: .original, playSessionID: "kit"),
                                                  range: "bytes=0-99")
        #expect(part.status == 206 && part.body.count == 100)
        // Over the file's rate: copied by the transcoder, no conversion (the
        // converters are plex.tv's to download, and this server cannot).
        let capped = try await PlexTestServer.fetch(server.streamURL(for: mp3, quality: .high, playSessionID: "kit-high"))
        #expect(capped.status == 200 && PlexTestServer.header(capped, "Content-Type") == "audio/mpeg" && capped.body.count > 10_000)
        let download = try await PlexTestServer.fetch(server.downloadURL(for: mp3, quality: .original))
        #expect(download.status == 200 && download.body == file.body)
        let cover = try await PlexTestServer.fetch(server.artworkURL(try #require(mp3.artwork), maxPixelSize: 300))
        #expect(cover.status == 200 && PlexTestServer.header(cover, "Content-Type") == "image/jpeg")
    }

    @Test("A favourite is five stars, and back to none")
    func favourite() async throws {
        let server = try await PlexTestServer.server()
        let album = try #require(try await server.allAlbums().first)
        try await server.setFavorite(true, item: .album(album.id))
        #expect(try await server.album(id: album.id).isFavorite)
        try await server.setFavorite(false, item: .album(album.id))
        #expect(try await server.album(id: album.id).isFavorite == false)
    }

    @Test("A playlist: made, added to (a song twice is once), moved, taken from, deleted")
    func playlist() async throws {
        let server = try await PlexTestServer.server()
        let ids = Array(try await server.allTracks(progress: nil).map(\.id).sorted().prefix(4))
        let id = try await server.createPlaylist(name: "Kit test", trackIDs: [ids[0], ids[1], ids[0]])
        defer { Task { try? await server.deletePlaylist(id: id) } }
        try await server.addToPlaylist(playlistID: id, trackIDs: [ids[2], ids[3]])
        var entries = try await server.playlistTracks(playlistID: id)
        #expect(entries.map(\.id) == [ids[0], ids[1], ids[2], ids[3]])
        // The first to the third place, as on Jellyfin: B C A D.
        try await server.movePlaylistEntry(playlistID: id, entryID: try #require(entries[0].playlistEntryID), to: 2)
        entries = try await server.playlistTracks(playlistID: id)
        #expect(entries.map(\.id) == [ids[1], ids[2], ids[0], ids[3]])
        try await server.movePlaylistEntry(playlistID: id, entryID: try #require(entries[3].playlistEntryID), to: 0)
        entries = try await server.playlistTracks(playlistID: id)
        #expect(entries.map(\.id) == [ids[3], ids[1], ids[2], ids[0]])
        try await server.removeFromPlaylist(playlistID: id, entryIDs: [try #require(entries[1].playlistEntryID), "nothing"])
        #expect(try await server.playlistTracks(playlistID: id).map(\.id) == [ids[3], ids[2], ids[0]])
        #expect(try await server.playlists().contains { $0.id == id && $0.trackCount == 3 && !$0.isReadOnly })
        try await server.deletePlaylist(id: id)
        #expect(try await server.playlists().contains { $0.id == id } == false)
    }

    @Test("A play counts once: not as it starts, once at .played, not again at the end or the stop")
    func plays() async throws {
        let server = try await PlexTestServer.server()
        let track = try #require(try await server.allTracks(progress: nil).sorted { $0.id < $1.id }.last)
        let before = try await server.track(id: track.id).playCount
        func report(_ event: PlaybackEvent, at position: TimeInterval) async {
            await server.report(event, PlaybackReport(trackID: track.id, position: position, isPaused: false,
                                                      playSessionID: "kit"))
        }
        await report(.nowPlaying, at: 0)
        #expect(try await server.track(id: track.id).playCount == before)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        await report(.played, at: 3)
        #expect(try await server.track(id: track.id).playCount == before + 1)
        // Played through to the end, in the time it takes.
        try await Task.sleep(nanoseconds: UInt64((track.duration + 1) * 1_000_000_000))
        await report(.progress, at: track.duration)
        await report(.stopped, at: track.duration)
        let after = try await server.track(id: track.id)
        #expect(after.playCount == before + 1 && after.lastPlayed != nil)
    }
}
