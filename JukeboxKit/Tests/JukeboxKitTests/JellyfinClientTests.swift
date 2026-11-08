// JellyfinClient against a transport that answers for the server: the
// header, the errors, the fallbacks to 10.8's routes, the URLs it makes,
// paging, and what it asks for.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Jellyfin: client")
struct JellyfinClientTests {
    // MARK: The header

    @Test("Authorization: MediaBrowser …, the token only when signed in, values escaped")
    func header() async throws {
        let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.2 (3)",
                                      deviceName: "Simon’s \"iPhone\"", deviceID: "ABC-123")
        let transport = JellyfinMockTransport(body: JellyfinFixtures.publicInfo)
        let signedOut = JellyfinClient(serverURL: JellyfinFixtures.server, identity: identity, transport: transport)
        _ = try await signedOut.publicInfo()
        let first = try #require(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
        #expect(first == #"MediaBrowser Client="Jukebox", Device="Simon%E2%80%99s%20%22iPhone%22", DeviceId="ABC-123", Version="1.2%20%283%29""#)
        #expect(!first.contains("Token"))

        let signedIn = JellyfinClient(serverURL: JellyfinFixtures.server, identity: identity,
                                      accessToken: "tok", userID: "u", transport: transport)
        _ = try await signedIn.publicInfo()
        let second = try #require(transport.requests.last?.value(forHTTPHeaderField: "Authorization"))
        #expect(second.hasSuffix(#", Token="tok""#))
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    // MARK: Errors

    @Test("401 is .unauthorized, 404 .notFound, others .server with the body's message")
    func errors() async throws {
        let cases: [(Int, String, JellyfinError)] = [
            (401, "Error processing request.", .unauthorized),
            (404, JellyfinFixtures.notFound, .notFound),
            (400, JellyfinFixtures.validationProblem, .server(status: 400, message: "The value 'nonsense' is not valid.")),
            (500, "Error processing request.", .server(status: 500, message: "Error processing request.")),
            (503, "", .server(status: 503, message: nil)),
            (502, "<html><body>Bad gateway</body></html>", .server(status: 502, message: nil)),
            (500, #"{"title":"Internal","detail":"Database is locked"}"#, .server(status: 500, message: "Database is locked")),
            (403, #"{"Message":"User is disabled"}"#, .server(status: 403, message: "User is disabled")),
            (409, #"{"title":"Conflict","status":409}"#, .server(status: 409, message: "Conflict")),
        ]
        for (status, body, expected) in cases {
            let client = JellyfinFixtures.client(JellyfinMockTransport(status: status, body: body))
            await #expect(throws: expected, "\(status) \(body)") { _ = try await client.genres() }
        }
    }

    @Test("A transport failure is .transport; a cancelled request is cancellation")
    func transportErrors() async throws {
        let failing = JellyfinFixtures.client(JellyfinMockTransport { _ in throw URLError(.notConnectedToInternet) })
        do {
            _ = try await failing.genres()
            Issue.record("no error")
        } catch let JellyfinError.transport(message) {
            #expect(!message.isEmpty)
        }
        let cancelled = JellyfinFixtures.client(JellyfinMockTransport { _ in throw URLError(.cancelled) })
        await #expect(throws: CancellationError.self) { _ = try await cancelled.genres() }
    }

    @Test("A body that is not what was expected is .decoding")
    func decodingError() async throws {
        let client = JellyfinFixtures.client(JellyfinMockTransport(body: #"{"Items": 7}"#))
        do {
            _ = try await client.genres()
            Issue.record("no error")
        } catch let JellyfinError.decoding(what) {
            #expect(what.contains("Items"))
        }
    }

    @Test("Calls that need a user say .notSignedIn without asking the server")
    func notSignedIn() async throws {
        let transport = JellyfinMockTransport(body: "{}")
        let client = JellyfinFixtures.client(transport, signedIn: false)
        await #expect(throws: JellyfinError.notSignedIn) { _ = try await client.genres() }
        await #expect(throws: JellyfinError.notSignedIn) { _ = try await client.allTracks() }
        await #expect(throws: JellyfinError.notSignedIn) { try await client.setFavorite(true, itemID: "x") }
        await #expect(throws: JellyfinError.notSignedIn) { _ = try await client.search("x") }
        await client.reportStart(PlaybackReport(trackID: "t", position: 0, isPaused: false, playSessionID: "p"))
        await client.signOut()
        #expect(transport.requests.isEmpty)
    }

    // MARK: Signing in

    @Test("Sign in: the body, and credentials from the answer and the server's name")
    func signIn() async throws {
        let transport = JellyfinMockTransport { request in
            switch request.jellyfinPath {
            case "/jellyfin/System/Info/Public": return JellyfinMockTransport.respond(200, JellyfinFixtures.publicInfo)
            case "/jellyfin/Users/AuthenticateByName": return JellyfinMockTransport.respond(200, JellyfinFixtures.authResult)
            default: return JellyfinMockTransport.respond(404)
            }
        }
        let client = JellyfinFixtures.client(transport, signedIn: false)
        let credentials = try await client.signIn(username: "test", password: "p\"w")
        #expect(credentials == Credentials(serverURL: JellyfinFixtures.server, serverID: "ab1b921a10354a07a7dfbbc2c8061335",
                                           serverName: "0548ac3b6612", userID: JellyfinFixtures.userID,
                                           userName: "test", accessToken: JellyfinFixtures.token))
        let auth = try #require(transport.requests.first { $0.jellyfinPath.hasSuffix("AuthenticateByName") })
        #expect(auth.httpMethod == "POST")
        #expect(auth.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(auth.jellyfinBody["Username"] as? String == "test")
        #expect(auth.jellyfinBody["Pw"] as? String == "p\"w")
    }

    @Test("A wrong password is .unauthorized")
    func wrongPassword() async throws {
        let transport = JellyfinMockTransport { request in
            request.jellyfinPath.hasSuffix("Public")
                ? JellyfinMockTransport.respond(200, JellyfinFixtures.publicInfo)
                : JellyfinMockTransport.respond(401, "Error processing request.")
        }
        let client = JellyfinFixtures.client(transport, signedIn: false)
        await #expect(throws: JellyfinError.unauthorized) {
            _ = try await client.signIn(username: "test", password: "wrong")
        }
    }

    @Test("Not a Jellyfin server: a web page or a 404 is .invalidServerAddress")
    func notJellyfin() async throws {
        for (status, body) in [(200, "<html>hello</html>"), (404, ""), (200, #"{"Name":"x"}"#)] {
            let client = JellyfinFixtures.client(JellyfinMockTransport(status: status, body: body), signedIn: false)
            await #expect(throws: JellyfinError.invalidServerAddress) { _ = try await client.publicInfo() }
        }
    }

    @Test("Quick Connect: enabled, initiate (and 10.8's GET), state, sign in")
    func quickConnect() async throws {
        let transport = JellyfinMockTransport { request in
            switch (request.httpMethod ?? "", request.jellyfinPath) {
            case ("GET", "/jellyfin/QuickConnect/Enabled"): return JellyfinMockTransport.respond(200, "true")
            // 10.8: Initiate is a GET; a POST is 405.
            case ("POST", "/jellyfin/QuickConnect/Initiate"): return JellyfinMockTransport.respond(405)
            case ("GET", "/jellyfin/QuickConnect/Initiate"): return JellyfinMockTransport.respond(200, JellyfinFixtures.quickConnect)
            case ("GET", "/jellyfin/QuickConnect/Connect"):
                return request.jellyfinQuery["secret"] == "known"
                    ? JellyfinMockTransport.respond(200, #"{"Secret":"known","Code":"123456","Authenticated":true}"#)
                    : JellyfinMockTransport.respond(404, #""Unknown secret""#)
            case ("POST", "/jellyfin/Users/AuthenticateWithQuickConnect"): return JellyfinMockTransport.respond(200, JellyfinFixtures.authResult)
            case ("GET", "/jellyfin/System/Info/Public"): return JellyfinMockTransport.respond(200, JellyfinFixtures.publicInfo)
            default: return JellyfinMockTransport.respond(404)
            }
        }
        let client = JellyfinFixtures.client(transport, signedIn: false)
        #expect(await client.quickConnectEnabled())
        let started = try await client.quickConnectStart()
        #expect(started.code == "588758")
        #expect(!started.isAuthenticated)
        #expect(try await client.quickConnectState(secret: "known").isAuthenticated)
        await #expect(throws: JellyfinError.notFound) { _ = try await client.quickConnectState(secret: "gone") }
        let credentials = try await client.signIn(quickConnectSecret: "known")
        #expect(credentials.accessToken == JellyfinFixtures.token)
        let body = try #require(transport.requests.first { $0.jellyfinPath.hasSuffix("AuthenticateWithQuickConnect") })
        #expect(body.jellyfinBody["Secret"] as? String == "known")
    }

    @Test("Quick Connect is off when the server says false or fails")
    func quickConnectDisabled() async {
        #expect(!(await JellyfinFixtures.client(JellyfinMockTransport(body: "false")).quickConnectEnabled()))
        #expect(!(await JellyfinFixtures.client(JellyfinMockTransport(status: 500, body: "")).quickConnectEnabled()))
        #expect(!(await JellyfinFixtures.client(JellyfinMockTransport { _ in throw URLError(.timedOut) }).quickConnectEnabled()))
    }

    // MARK: Fallbacks

    @Test("Favourites: /UserFavoriteItems, and 10.8's route on a 404 only")
    func favoriteFallback() async throws {
        let transport = JellyfinMockTransport { request in
            request.jellyfinPath.hasPrefix("/jellyfin/UserFavoriteItems")
                ? JellyfinMockTransport.respond(404, JellyfinFixtures.notFound)
                : JellyfinMockTransport.respond(200, "{}")
        }
        try await JellyfinFixtures.client(transport).setFavorite(true, itemID: "item1")
        try await JellyfinFixtures.client(transport).setFavorite(false, itemID: "item1")
        #expect(transport.requests.map { "\($0.httpMethod ?? "") \($0.jellyfinPath)" } == [
            "POST /jellyfin/UserFavoriteItems/item1",
            "POST /jellyfin/Users/\(JellyfinFixtures.userID)/FavoriteItems/item1",
            "DELETE /jellyfin/UserFavoriteItems/item1",
            "DELETE /jellyfin/Users/\(JellyfinFixtures.userID)/FavoriteItems/item1",
        ])
        #expect(transport.requests[0].jellyfinQuery["userId"] == JellyfinFixtures.userID)

        // Any other error is the server's answer: no second try.
        let failing = JellyfinMockTransport(status: 500, body: "")
        await #expect(throws: JellyfinError.server(status: 500, message: nil)) {
            try await JellyfinFixtures.client(failing).setFavorite(true, itemID: "item1")
        }
        #expect(failing.requests.count == 1)
    }

    @Test("Lyrics: 404 is no lyrics, in one request")
    func noLyrics() async throws {
        let transport = JellyfinMockTransport(status: 404, body: JellyfinFixtures.notFound)
        #expect(try await JellyfinFixtures.client(transport).lyrics(trackID: "t") == nil)
        #expect(transport.requests.map(\.jellyfinPath) == ["/jellyfin/Audio/t/Lyrics"])
    }

    // MARK: URLs

    @Test("The stream URL: universal, the containers AVPlayer plays, HLS AAC, ApiKey")
    func streamURL() throws {
        let client = JellyfinFixtures.client(JellyfinMockTransport(body: ""))
        let original = client.streamURL(trackID: "track1", quality: .original, playSessionID: "play-1")
        let components = try #require(URLComponents(url: original, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "jf.example.com")
        #expect(components.path == "/jellyfin/Audio/track1/universal")
        let query = URLRequest(url: original).jellyfinQuery
        #expect(query["UserId"] == JellyfinFixtures.userID)
        #expect(query["DeviceId"] == "device-1")
        #expect(query["PlaySessionId"] == "play-1")
        #expect(query["Container"] == "mp3,aac,m4a|aac,m4a|alac,m4b|aac,mp4|aac,mp4|alac,flac,alac,wav,aiff")
        #expect(query["TranscodingContainer"] == "ts")
        #expect(query["TranscodingProtocol"] == "hls")
        #expect(query["AudioCodec"] == "aac")
        #expect(query["ApiKey"] == JellyfinFixtures.token)
        #expect(query["api_key"] == nil)
        #expect(query["MaxStreamingBitrate"] == nil)
        // Commas and pipes are escaped; nothing is left that a proxy might mangle.
        #expect(original.absoluteString.contains("Container=mp3%2Caac%2Cm4a%7Caac"))

        for (quality, bitrate) in [(StreamQuality.high, "320000"), (.normal, "256000"), (.low, "128000")] {
            let url = client.streamURL(trackID: "track1", quality: quality, playSessionID: "p")
            #expect(URLRequest(url: url).jellyfinQuery["MaxStreamingBitrate"] == bitrate)
        }
    }

    @Test("The image URL: square, quality 90, the tag; no token")
    func imageURL() throws {
        let client = JellyfinFixtures.client(JellyfinMockTransport(body: ""))
        let url = client.imageURL(Artwork(itemID: "album1", tag: "tag1"), maxPixelSize: 600)
        #expect(url.absoluteString == "https://jf.example.com/jellyfin/Items/album1/Images/Primary?fillWidth=600&fillHeight=600&quality=90&tag=tag1")
        let untagged = client.imageURL(Artwork(itemID: "album1", tag: nil), maxPixelSize: 0)
        #expect(untagged.absoluteString == "https://jf.example.com/jellyfin/Items/album1/Images/Primary?fillWidth=1&fillHeight=1&quality=90")
    }

    @Test("A query value with + & = and spaces arrives as it was typed")
    func escaping() async throws {
        let transport = JellyfinMockTransport(body: JellyfinFixtures.page([]))
        _ = try await JellyfinFixtures.client(transport).albums(AlbumQuery(genre: "R&B + Soul = 100%"))
        let request = try #require(transport.requests.first)
        #expect(request.jellyfinQuery["Genres"] == "R&B + Soul = 100%")
        #expect(request.url?.absoluteString.contains("Genres=R%26B%20%2B%20Soul%20%3D%20100%25") == true)
    }

    // MARK: What the library calls ask for

    @Test("Albums: the query; sort keys with tie-breakers ascending")
    func albumQuery() async throws {
        let transport = JellyfinMockTransport(body: JellyfinFixtures.page([JellyfinFixtures.album], total: 54, start: 20))
        let page = try await JellyfinFixtures.client(transport).albums(
            AlbumQuery(artistID: "ar1", genre: "Jazz", favoritesOnly: true, sort: .year, descending: true, start: 20, limit: 10))
        #expect(page.items.map(\.name) == ["Dust Parades"])
        #expect(page.totalCount == 54)
        #expect(page.startIndex == 20)
        let q = try #require(transport.requests.first).jellyfinQuery
        #expect(q["userId"] == JellyfinFixtures.userID)
        #expect(q["IncludeItemTypes"] == "MusicAlbum")
        #expect(q["Recursive"] == "true")
        #expect(q["AlbumArtistIds"] == "ar1")
        #expect(q["Genres"] == "Jazz")
        #expect(q["IsFavorite"] == "true")
        #expect(q["SortBy"] == "ProductionYear,SortName")
        #expect(q["SortOrder"] == "Descending,Ascending")
        #expect(q["StartIndex"] == "20")
        #expect(q["Limit"] == "10")
        #expect(q["Fields"] == "Genres,DateCreated,ChildCount")
        #expect(q["EnableImageTypes"] == "Primary")
        #expect(q["ImageTypeLimit"] == "1")
    }

    @Test("Tracks of an album come in disc and track order; a search asks no order")
    func trackQuery() async throws {
        let transport = JellyfinMockTransport(body: JellyfinFixtures.page([]))
        let client = JellyfinFixtures.client(transport)
        _ = try await client.tracks(TrackQuery(albumID: "al1"))
        _ = try await client.tracks(TrackQuery(albumID: "al1", sort: .playCount, descending: true))
        _ = try await client.tracks(TrackQuery(searchTerm: "  river  ", limit: 5))
        _ = try await client.tracks(TrackQuery(sort: .random, limit: 50))
        let qs = transport.requests.map(\.jellyfinQuery)
        #expect(qs[0]["ParentId"] == "al1")
        #expect(qs[0]["SortBy"] == "ParentIndexNumber,IndexNumber,SortName")
        #expect(qs[0]["IncludeItemTypes"] == "Audio")
        #expect(qs[0]["Fields"] == "Genres,DateCreated")
        #expect(qs[1]["SortBy"] == "PlayCount,SortName")
        #expect(qs[1]["SortOrder"] == "Descending,Ascending")
        #expect(qs[2]["SearchTerm"] == "river")
        #expect(qs[2]["SortBy"] == nil)
        #expect(qs[3]["SortBy"] == "Random")
        #expect(qs[3]["SortOrder"] == nil)
    }

    @Test("Tracks by id: in the order asked, 100 ids a request, missing ones left out")
    func tracksByID() async throws {
        let ids = (0..<250).map { "id\($0)" }
        let transport = JellyfinMockTransport { request in
            let asked = (request.jellyfinQuery["Ids"] ?? "").split(separator: ",").map(String.init)
            // The server answers in its own order, and has no id13.
            let items = asked.reversed().filter { $0 != "id13" }.map { JellyfinFixtures.track(id: $0, name: $0) }
            return JellyfinMockTransport.respond(200, JellyfinFixtures.page(items))
        }
        let page = try await JellyfinFixtures.client(transport).tracks(TrackQuery(ids: ids))
        #expect(transport.requests.count == 3)
        #expect(transport.requests.allSatisfy { ($0.url?.absoluteString.count ?? 0) < 8000 })
        #expect(page.items.map(\.id) == ids.filter { $0 != "id13" })
        #expect(page.totalCount == 250)

        let window = try await JellyfinFixtures.client(transport).tracks(TrackQuery(ids: ids, start: 10, limit: 5))
        #expect(window.items.map(\.id) == ["id10", "id11", "id12", "id14"])
        #expect(window.startIndex == 10)
        #expect(try await JellyfinFixtures.client(transport).tracks(TrackQuery(ids: [])).items.isEmpty)
    }

    @Test("All tracks: pages of pageSize, progress after each, every track once, in order")
    func allTracksPaging() async throws {
        let total = 250
        let transport = JellyfinMockTransport { request in
            let q = request.jellyfinQuery
            let start = Int(q["StartIndex"] ?? "0") ?? 0
            let limit = Int(q["Limit"] ?? "0") ?? 0
            // The last page repeats a track of the one before (a library
            // that changed while it was read).
            let from = start == 200 ? 199 : start
            let items = (from..<min(start + limit, total)).map { JellyfinFixtures.track(id: String(format: "t%03ld", $0), name: "x") }
            return JellyfinMockTransport.respond(200, JellyfinFixtures.page(items, total: total, start: start))
        }
        let calls = JellyfinProgressRecorder()
        let tracks = try await JellyfinFixtures.client(transport).allTracks(pageSize: 100) { done, all in
            calls.add(done, all)
        }
        #expect(tracks.count == 250)
        #expect(tracks.map(\.id) == (0..<250).map { String(format: "t%03ld", $0) })
        #expect(transport.requests.count == 3)
        #expect(Set(transport.requests.compactMap { $0.jellyfinQuery["StartIndex"] }) == ["0", "100", "200"])
        #expect(transport.requests.allSatisfy { $0.jellyfinQuery["SortBy"] == "SortName" && $0.jellyfinQuery["Limit"] == "100" })
        let recorded = calls.values
        #expect(recorded.count == 3)
        #expect(recorded.first?.0 == 100)
        #expect(recorded.allSatisfy { $0.1 == 250 })
        #expect(recorded.last?.0 == 250)
    }

    @Test("Search: four requests at once, one per kind")
    func search() async throws {
        let transport = JellyfinMockTransport { request in
            let q = request.jellyfinQuery
            if request.jellyfinPath.hasSuffix("/Artists/AlbumArtists") {
                return JellyfinMockTransport.respond(200, JellyfinFixtures.page([JellyfinFixtures.artist]))
            }
            switch q["IncludeItemTypes"] {
            case "MusicAlbum": return JellyfinMockTransport.respond(200, JellyfinFixtures.page([JellyfinFixtures.album]))
            case "Audio": return JellyfinMockTransport.respond(200, JellyfinFixtures.page([JellyfinFixtures.track]))
            case "Playlist": return JellyfinMockTransport.respond(200, JellyfinFixtures.page([JellyfinFixtures.playlist]))
            default: return JellyfinMockTransport.respond(404)
            }
        }
        let results = try await JellyfinFixtures.client(transport).search("blue", limit: 7)
        #expect(results.artists.count == 1 && results.albums.count == 1 && results.tracks.count == 1 && results.playlists.count == 1)
        #expect(transport.requests.count == 4)
        #expect(transport.requests.allSatisfy { $0.jellyfinQuery["SearchTerm"] == "blue" && $0.jellyfinQuery["Limit"] == "7" })
        #expect(try await JellyfinFixtures.client(transport).search("   ").isEmpty)
        #expect(transport.requests.count == 4)
    }

    @Test("Playlists: create's body, add and remove in chunks, move, delete")
    func playlistCalls() async throws {
        let transport = JellyfinMockTransport { request in
            request.jellyfinPath == "/jellyfin/Playlists" && request.httpMethod == "POST"
                ? JellyfinMockTransport.respond(200, #"{"Id":"pl1"}"#)
                : JellyfinMockTransport.respond(204)
        }
        let client = JellyfinFixtures.client(transport)
        let id = try await client.createPlaylist(name: "Night drive", trackIDs: ["a", "b"])
        #expect(id == "pl1")
        let create = transport.requests[0].jellyfinBody
        #expect(create["Name"] as? String == "Night drive")
        #expect(create["Ids"] as? [String] == ["a", "b"])
        #expect(create["UserId"] as? String == JellyfinFixtures.userID)
        #expect(create["MediaType"] as? String == "Audio")

        try await client.addToPlaylist(playlistID: "pl1", trackIDs: (0..<150).map { "t\($0)" })
        try await client.removeFromPlaylist(playlistID: "pl1", entryIDs: ["e1", "e2"])
        try await client.movePlaylistEntry(playlistID: "pl1", entryID: "e2", to: 0)
        try await client.deletePlaylist(id: "pl1")
        try await client.addToPlaylist(playlistID: "pl1", trackIDs: [])
        let calls = transport.requests.dropFirst().map { "\($0.httpMethod ?? "") \($0.jellyfinPath)" }
        #expect(calls == ["POST /jellyfin/Playlists/pl1/Items", "POST /jellyfin/Playlists/pl1/Items",
                          "DELETE /jellyfin/Playlists/pl1/Items", "POST /jellyfin/Playlists/pl1/Items/e2/Move/0",
                          "DELETE /jellyfin/Items/pl1"])
        #expect(transport.requests[1].jellyfinQuery["ids"]?.split(separator: ",").count == 100)
        #expect(transport.requests[2].jellyfinQuery["ids"]?.split(separator: ",").count == 50)
        #expect(transport.requests[3].jellyfinQuery["entryIds"] == "e1,e2")
    }

    @Test("Playback reports: the routes and the body; errors never reach the player")
    func reports() async throws {
        let transport = JellyfinMockTransport(status: 500, body: "")
        let client = JellyfinFixtures.client(transport)
        let report = PlaybackReport(trackID: "t1", position: 3.5, isPaused: false, playSessionID: "p1")
        await client.reportStart(report)
        await client.reportProgress(report)
        await client.reportStopped(report)
        #expect(transport.requests.map(\.jellyfinPath) == ["/jellyfin/Sessions/Playing", "/jellyfin/Sessions/Playing/Progress",
                                                           "/jellyfin/Sessions/Playing/Stopped"])
        let body = transport.requests[0].jellyfinBody
        #expect(body["ItemId"] as? String == "t1")
        #expect((body["PositionTicks"] as? NSNumber)?.int64Value == 35_000_000)
        #expect(body["PlaySessionId"] as? String == "p1")
        #expect(body["PlayMethod"] as? String == "DirectStream")
    }

    @Test("A single item is /Items?Ids=; none is .notFound")
    func singleItem() async throws {
        let found = JellyfinMockTransport(body: JellyfinFixtures.page([JellyfinFixtures.track]))
        let track = try await JellyfinFixtures.client(found).track(id: "2c4a765f5c8d9b4907be5d835a82513c")
        #expect(track.name == "Blue Parade")
        #expect(found.requests.first?.jellyfinPath == "/jellyfin/Items")
        #expect(found.requests.first?.jellyfinQuery["Ids"] == "2c4a765f5c8d9b4907be5d835a82513c")
        let none = JellyfinMockTransport(body: JellyfinFixtures.page([]))
        await #expect(throws: JellyfinError.notFound) { _ = try await JellyfinFixtures.client(none).album(id: "x") }
    }
}

/// Keeps what allTracks' progress was told.
final class JellyfinProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(Int, Int)] = []

    func add(_ done: Int, _ total: Int) {
        lock.lock()
        calls.append((done, total))
        lock.unlock()
    }

    var values: [(Int, Int)] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}
