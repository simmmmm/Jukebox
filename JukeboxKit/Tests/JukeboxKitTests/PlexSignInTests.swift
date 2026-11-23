// Plex without a server or plex.tv: detection, plex.tv's sign-in in the
// browser read from the shapes Plex documents (no plex.tv account was used:
// the flow is untested end to end), a token as an API key, and the mapping
// and the URLs, against answers recorded from Plex Media Server 1.43.5
// (dev/plex-test-server.sh, 17 November 2026).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum PlexFixtures {
    static let identity = #"{"MediaContainer":{"size":0,"claimed":false,"machineIdentifier":"0df8f334a6be6c02e03c8251708a9ed133182644","version":"1.43.5.11079-b3b13e506"}}"#

    /// /library/metadata/150, as 1.43.5 answered it.
    static let track = #"""
    {"MediaContainer":{"size":1,"Metadata":[{"ratingKey":"151","key":"/library/metadata/151","parentRatingKey":"149",
    "grandparentRatingKey":"131","type":"track","title":"Ghost Machine","grandparentTitle":"Amsterdam Strings",
    "parentTitle":"Ghost Rooms","originalTitle":"Amsterdam Strings; Willow & Pine","index":2,"parentIndex":1,
    "parentYear":1985,"thumb":"/library/metadata/149/thumb/1794902352","parentThumb":"/library/metadata/149/thumb/1794902352",
    "duration":6034,"addedAt":1794611181,"userRating":10.0,"viewCount":2,"lastViewedAt":1794902537,"playlistItemID":4,
    "Media":[{"id":124,"duration":6034,"container":"mp3","Part":[{"id":124,"key":"/library/parts/124/1794611181/file.mp3",
    "container":"mp3","Stream":[{"id":122,"streamType":2,"codec":"mp3"},{"id":900,"streamType":4,"key":"/library/streams/900","format":"lrc"}]}]}]}]}}
    """#

    /// POST https://plex.tv/api/v2/pins?strong=true, as Plex's documentation
    /// ("Authenticating with Plex") shows it.
    static let pin = #"{"id":564964751,"code":"8iscs4sq8q7aex0d8ff6q1t2g","product":"Jukebox","trusted":false,"clientIdentifier":"test-device","location":{"code":"NL"},"expiresIn":1800,"createdAt":"2026-11-17T08:00:00Z","expiresAt":"2026-11-17T08:30:00Z","authToken":null,"newRegistration":null}"#
    static let pinSigned = pin.replacingOccurrences(of: #""authToken":null"#, with: #""authToken":"account-token""#)

    /// GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1:
    /// a player (not a server), a friend's server, and one's own with a
    /// relay, a remote and a local address, in that order.
    static let resources = #"""
    [{"name":"Living Room TV","product":"Plex for Android (TV)","clientIdentifier":"tv","provides":"client,player","owned":true,"connections":[]},
     {"name":"Friend's Plex","product":"Plex Media Server","productVersion":"1.42.1","clientIdentifier":"friend","provides":"server",
      "owned":false,"accessToken":"friend-token","connections":[{"protocol":"https","address":"203.0.113.7","port":32400,
      "uri":"https://203-0-113-7.friend.plex.direct:32400","local":false,"relay":false}]},
     {"name":"Home","product":"Plex Media Server","productVersion":"1.43.5.11079-b3b13e506","clientIdentifier":"home",
      "provides":"server","owned":true,"accessToken":"home-token","connections":[
      {"protocol":"https","address":"198.51.100.1","port":8443,"uri":"https://198-51-100-1.home.plex.direct:8443","local":false,"relay":true},
      {"protocol":"https","address":"198.51.100.2","port":32400,"uri":"https://198-51-100-2.home.plex.direct:32400","local":false,"relay":false},
      {"protocol":"http","address":"192.168.1.10","port":32400,"uri":"http://192.168.1.10:32400","local":true,"relay":false}]}]
    """#

    static let user = #"{"id":12345678,"uuid":"abc","username":"listener","title":"Listener","email":"listener@example.com"}"#
}

@Suite("Plex: sign-in and mapping, without a server", .timeLimit(.minutes(1)))
struct PlexSignInTests {
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.0", deviceName: "Test",
                                         deviceID: "test-device")

    static let detected = DetectedServer(kind: .plex, url: URL(string: "http://nas.local:32400")!,
                                         id: "0df8f334a6be6c02e03c8251708a9ed133182644", name: "nas",
                                         version: "1.43.5")

    @Test("A Plex server is found at its port, by the host alone, and named by its root")
    func detection() async throws {
        let fake = AddressFake { url in
            guard AddressFake.address(url) == "nas.local:32400" else { return try AddressFake.refused() }
            switch url.path {
            case "/identity": return .json(PlexFixtures.identity)
            case "/": return .json(#"{"MediaContainer":{"friendlyName":"Attic"}}"#)
            default: return HTTPResponse(status: 404, body: Data())
            }
        }
        let server = try await MusicServers.detect("nas.local", identity: Self.identity, transport: fake)
        #expect(server.kind == .plex && server.url.absoluteString == "http://nas.local:32400")
        #expect(server.id == "0df8f334a6be6c02e03c8251708a9ed133182644" && server.name == "Attic")
        #expect(server.version == "1.43.5.11079-b3b13e506")
        #expect(MusicServers.candidateAddresses(for: "nas:32400").first?.absoluteString == "http://nas:32400")
    }

    @Test("A password is not Plex's: an API key is asked for, with Plex's page on tokens")
    func password() async throws {
        let way = MusicServers.signIn(to: Self.detected, identity: Self.identity, transport: AddressFake { _ in try AddressFake.refused() })
        #expect(way is any APIKeySignIn)
        await #expect(throws: MusicServerError.needsAPIKey(helpURL: PlexSignIn.tokenHelp)) {
            try await way.signIn(username: "me", password: "secret")
        }
    }

    @Test("A token pasted as an API key: tried on the library, the same token the same account")
    func token() async throws {
        let fake = AddressFake { url in
            switch url.path {
            case "/library/sections": .json(#"{"MediaContainer":{"size":0}}"#)
            case "/myplex/account": .json(#"{"MyPlex":{"username":"owner","signInState":"ok"}}"#)
            default: HTTPResponse(status: 404, body: Data())
            }
        }
        let way = try #require(MusicServers.signIn(to: Self.detected, identity: Self.identity, transport: fake) as? any APIKeySignIn)
        let one = try await way.signIn(apiKey: " abc ")
        let two = try await way.signIn(apiKey: "abc")
        #expect(one.kind == .plex && one.secret == .plexToken("abc") && one.userName == "owner")
        #expect(one.userID == two.userID && one.userID.hasPrefix("token-"))
        #expect(one.capabilities == PlexServer.capabilities)

        let refused = AddressFake { _ in HTTPResponse(status: 401, body: Data()) }
        let no = try #require(MusicServers.signIn(to: Self.detected, identity: Self.identity, transport: refused) as? any APIKeySignIn)
        await #expect(throws: MusicServerError.unauthorized) { try await no.signIn(apiKey: "wrong") }
    }

    @Test("plex.tv: the PIN, the page it opens, the token once signed in")
    func pin() async throws {
        let asked = Counter()
        let fake = AddressFake { url in
            switch url.path {
            case "/api/v2/pins": return .json(PlexFixtures.pin, status: 201)
            case "/api/v2/pins/564964751": return .json(asked.next() < 2 ? PlexFixtures.pin : PlexFixtures.pinSigned)
            default: return HTTPResponse(status: 404, body: Data())
            }
        }
        let account = PlexAccount(identity: Self.identity, transport: fake)
        let pin = try await account.start(forwardURL: URL(string: "jukebox://plex"))
        #expect(pin.id == 564964751 && pin.code == "8iscs4sq8q7aex0d8ff6q1t2g")
        #expect(pin.authURL.absoluteString == "https://app.plex.tv/auth#?clientID=test-device&code=8iscs4sq8q7aex0d8ff6q1t2g"
            + "&context%5Bdevice%5D%5Bproduct%5D=Jukebox&forwardUrl=jukebox%3A%2F%2Fplex")
        #expect(fake.requests.first?.query?.contains("strong=true") == true)
        #expect(try await account.token(for: pin) == "account-token")
    }

    @Test("plex.tv: servers only, one's own first; the home address beats the remote and the relay")
    func servers() async throws {
        let fake = AddressFake { url in
            switch (url.host ?? "", url.path) {
            case ("plex.tv", "/api/v2/resources"): .json(PlexFixtures.resources)
            case ("plex.tv", "/api/v2/user"): .json(PlexFixtures.user)
            case (_, "/identity"): .json(PlexFixtures.identity)
            default: HTTPResponse(status: 404, body: Data())
            }
        }
        let account = PlexAccount(identity: Self.identity, transport: fake)
        let servers = try await account.servers(token: "account-token")
        #expect(servers.map(\.id) == ["home", "friend"])
        #expect(servers[0].addresses.map(\.absoluteString) == [
            "http://192.168.1.10:32400", "https://198-51-100-2.home.plex.direct:32400",
            "https://198-51-100-1.home.plex.direct:8443",
        ])
        let credentials = try await account.signIn(to: servers[0], accountToken: "account-token")
        #expect(credentials.serverURL.absoluteString == "http://192.168.1.10:32400")
        #expect(credentials.serverID == "home" && credentials.serverName == "Home")
        #expect(credentials.userID == "12345678" && credentials.userName == "listener")
        // The server's own token for this account, not the account's.
        #expect(credentials.secret == .plexToken("home-token"))
        // Every address kept, in the order to try.
        #expect(credentials.addresses == servers[0].addresses)
    }

    /// Home's address and the remote one, as plex.tv gave them.
    static let home = URL(string: "http://192.168.1.10:32400")!
    static let remote = URL(string: "https://198-51-100-2.home.plex.direct:32400")!
    static func signedInAtHome() -> ServerCredentials {
        var credentials = ServerCredentials(kind: .plex, serverURL: home, serverID: "home", serverName: "Home",
                                            userID: "1", userName: "me", secret: .plexToken("tok"),
                                            capabilities: PlexServer.capabilities)
        credentials.addresses = [home, remote]
        return credentials
    }

    @Test("Signed in at home, opened away: the first request finds the remote address, and the songs come from there")
    func awayFromHome() async throws {
        let fake = AddressFake { url in
            if url.host == "192.168.1.10" { return try AddressFake.refused() }
            return url.path == "/identity" ? .json(PlexFixtures.identity) : .json(#"{"MediaContainer":{"size":0}}"#)
        }
        let server = PlexServer(credentials: Self.signedInAtHome(), identity: Self.identity, transport: fake)
        #expect(try await server.downloadsAllowed())
        let track = Track(id: "151", name: "Ghost Machine")
        #expect(server.streamURL(for: track, quality: .low, playSessionID: "s").host == Self.remote.host)
        #expect(fake.requests.last?.host == Self.remote.host && fake.requests.last?.path == "/library/sections")
        // Asked once: the next request goes straight there.
        let asked = fake.requests.count
        _ = try await server.playlists()
        #expect(fake.requests.count == asked + 1 && fake.requests.last?.host == Self.remote.host)
        // The account itself is unchanged: nothing to save.
        #expect(server.credentials == Self.signedInAtHome())
    }

    @Test("Home answers again first; gone from home mid-session, asked again; none answering, the error is the network's")
    func movingAround() async throws {
        let atHome = Flag(true)
        let fake = AddressFake { url in
            if url.host == "192.168.1.10", !atHome.value { return try AddressFake.refused() }
            return url.path == "/identity" ? .json(PlexFixtures.identity) : .json(#"{"MediaContainer":{"size":0}}"#)
        }
        let server = PlexServer(credentials: Self.signedInAtHome(), identity: Self.identity, transport: fake)
        _ = try await server.playlists()
        #expect(fake.requests.last?.host == Self.home.host)
        atHome.value = false
        _ = try await server.playlists()
        #expect(fake.requests.last?.host == Self.remote.host)

        let offline = AddressFake { _ in try AddressFake.refused() }
        let nowhere = PlexServer(credentials: Self.signedInAtHome(), identity: Self.identity, transport: offline)
        await #expect(throws: MusicServerError.self) { try await nowhere.playlists() }
        #expect(nowhere.streamURL(for: Track(id: "1", name: "x"), quality: .low, playSessionID: "s").host == Self.home.host)
    }

    @Test("plex.tv: away from home, the remote address; the address typed first of all")
    func addresses() async throws {
        let fake = AddressFake { url in
            switch (url.host ?? "", url.path) {
            case ("plex.tv", "/api/v2/resources"): return .json(PlexFixtures.resources)
            case ("plex.tv", "/api/v2/user"): return .json(PlexFixtures.user)
            case ("192.168.1.10", _): return try AddressFake.refused()
            case (_, "/identity"): return .json(PlexFixtures.identity)
            default: return HTTPResponse(status: 404, body: Data())
            }
        }
        let account = PlexAccount(identity: Self.identity, transport: fake)
        let home = try #require(try await account.servers(token: "t").first)
        let away = try await account.signIn(to: home, accountToken: "t")
        #expect(away.serverURL.absoluteString == "https://198-51-100-2.home.plex.direct:32400")
        let typed = try await account.signIn(to: home, accountToken: "t", preferring: URL(string: "http://nas.local:32400")!)
        #expect(typed.serverURL.absoluteString == "http://nas.local:32400")
    }

    @Test("A track: its album's artist, its own artists' tag, five stars a favourite, its file")
    func track() throws {
        let answer = try JSONDecoder().decode(PlexAnswer.self, from: Data(PlexFixtures.track.utf8))
        let track = try #require(answer.container?.metadata.first?.track)
        #expect(track.id == "151" && track.name == "Ghost Machine" && track.albumID == "149")
        #expect(track.albumArtist == ArtistRef(id: "131", name: "Amsterdam Strings"))
        #expect(track.artists == [ArtistRef(id: nil, name: "Amsterdam Strings; Willow & Pine")])
        #expect(track.trackNumber == 2 && track.discNumber == 1 && track.year == 1985)
        #expect(abs(track.duration - 6.034) < 0.001 && track.isFavorite && track.playCount == 2)
        #expect(track.lastPlayed == Date(timeIntervalSince1970: 1794902537))
        #expect(track.playlistEntryID == "4" && track.container == "mp3")
        #expect(track.fileKey == "/library/parts/124/1794611181/file.mp3")
    }

    @Test("The file as it is; capped or unplayable, the transcoder's MP3; covers by their path")
    func urls() throws {
        let credentials = ServerCredentials(kind: .plex, serverURL: URL(string: "http://nas:32400")!, serverID: "m",
                                            serverName: "nas", userID: "1", userName: "me", secret: .plexToken("tok"))
        let server = PlexServer(credentials: credentials, identity: Self.identity)
        let answer = try JSONDecoder().decode(PlexAnswer.self, from: Data(PlexFixtures.track.utf8))
        var track = try #require(answer.container?.metadata.first?.track)
        #expect(server.streamURL(for: track, quality: .original, playSessionID: "s").absoluteString
            == "http://nas:32400/library/parts/124/1794611181/file.mp3?X-Plex-Token=tok")
        let capped = server.streamURL(for: track, quality: .low, playSessionID: "s").absoluteString
        #expect(capped.hasPrefix("http://nas:32400/music/:/transcode/universal/start.mp3?path=%2Flibrary%2Fmetadata%2F151&"))
        #expect(capped.contains("maxAudioBitrate=128") && capped.contains("protocol=http") && capped.contains("X-Plex-Token=tok"))
        #expect(server.downloadURL(for: track, quality: .original).absoluteString.contains("file.mp3?download=1&X-Plex-Token=tok"))
        // A Chromecast: the MP3's file; an M4A, the transcoder's MP3. Never
        // the account's token: before prepareCast, none at all.
        let cast = server.castURL(for: track)
        #expect(cast.contentType == "audio/mpeg"
            && cast.url.absoluteString == "http://nas:32400/library/parts/124/1794611181/file.mp3")
        track.container = "mp4"
        let converted = server.castURL(for: track)
        #expect(converted.contentType == "audio/mpeg" && converted.url.absoluteString.contains("start.mp3?")
            && converted.url.absoluteString.contains("maxAudioBitrate=320") && !converted.url.absoluteString.contains("tok"))
        track.container = "opus"
        #expect(server.streamURL(for: track, quality: .original, playSessionID: "s").absoluteString.contains("maxAudioBitrate=320"))
        #expect(server.artworkURL(Artwork(itemID: "149", tag: "/library/metadata/149/thumb/1794902352"), maxPixelSize: 300).absoluteString
            == "http://nas:32400/photo/:/transcode?width=300&height=300&url=%2Flibrary%2Fmetadata%2F149%2Fthumb%2F1794902352&X-Plex-Token=tok")
    }

    @Test("Plain http away from home is never asked with the token, unless accepted for that address")
    func plainHTTPAway() async throws {
        let away = URL(string: "http://203.0.113.7:32400")!
        let fake = AddressFake { _ in .json(PlexFixtures.identity) }
        let found = await PlexAccount.firstAnswering([away, Self.remote], token: "t", identity: Self.identity, transport: fake)
        #expect(found == Self.remote && !fake.requests.contains { $0.host == "203.0.113.7" })
        let defaults = try #require(UserDefaults(suiteName: "plex-plain-http-test"))
        defaults.removeObject(forKey: "signIn.plainHTTPAccepted")
        #expect(!PlexAccount.mayAsk(away, defaults: defaults) && PlexAccount.mayAsk(Self.home, defaults: defaults))
        defaults.set([away.absoluteString], forKey: "signIn.plainHTTPAccepted")
        #expect(PlexAccount.mayAsk(away, defaults: defaults))
        defaults.removeObject(forKey: "signIn.plainHTTPAccepted")
    }

    @Test("A cast gets the server's transient token, not the account's")
    func castToken() async throws {
        let fake = AddressFake { url in
            url.path == "/security/token"
                ? .json(#"{"MediaContainer":{"size":0,"token":"transient-1234"}}"#)
                : .json(#"{"MediaContainer":{"size":0}}"#)
        }
        let credentials = ServerCredentials(kind: .plex, serverURL: URL(string: "http://nas:32400")!, serverID: "m",
                                            serverName: "nas", userID: "1", userName: "me", secret: .plexToken("tok"))
        let server = PlexServer(credentials: credentials, identity: Self.identity, transport: fake)
        try await server.prepareCast()
        let asked = try #require(fake.requests.first)
        #expect(asked.query?.contains("type=delegation") == true)
        let answer = try JSONDecoder().decode(PlexAnswer.self, from: Data(PlexFixtures.track.utf8))
        let track = try #require(answer.container?.metadata.first?.track)
        let urls = [server.castURL(for: track).url,
                    server.castArtworkURL(Artwork(itemID: "149", tag: nil), maxPixelSize: 600)]
        for url in urls {
            #expect(url.absoluteString.contains("X-Plex-Token=transient-1234") && !url.absoluteString.contains("=tok"), "\(url)")
        }
        // Here, the account's as before.
        #expect(server.artworkURL(Artwork(itemID: "149", tag: nil), maxPixelSize: 600).absoluteString.contains("X-Plex-Token=tok"))
    }

    @Test("Reports: the timeline while it plays, the scrobble for the play, a stop at 0 s")
    func reports() async throws {
        let fake = AddressFake { _ in .json(#"{"MediaContainer":{"size":0}}"#) }
        let credentials = ServerCredentials(kind: .plex, serverURL: URL(string: "http://nas:32400")!, serverID: "m",
                                            serverName: "nas", userID: "1", userName: "me", secret: .plexToken("tok"))
        let server = PlexServer(credentials: credentials, identity: Self.identity, transport: fake)
        let report = PlaybackReport(trackID: "151", position: 3.5, isPaused: false, playSessionID: "s")
        for event in PlaybackEvent.allCases { await server.report(event, report) }
        let sent = fake.requests.map { "\($0.path) \(($0.query ?? "").split(separator: "&").filter { $0.hasPrefix("state") || $0.hasPrefix("time") || $0.hasPrefix("key=1") }.joined(separator: " "))" }
        #expect(sent == ["/:/timeline state=playing time=3500", "/:/scrobble key=151",
                         "/:/timeline state=playing time=3500", "/:/timeline state=stopped time=0"])
    }

    @Test("Lyrics: the file's lyrics stream, timed")
    func lyrics() async throws {
        let fake = AddressFake { url in
            switch url.path {
            case "/library/metadata/151": .json(PlexFixtures.track)
            case "/library/streams/900": HTTPResponse(status: 200, body: Data("[00:01.00]One\n[00:02.50]Two\n".utf8))
            default: HTTPResponse(status: 404, body: Data())
            }
        }
        let credentials = ServerCredentials(kind: .plex, serverURL: URL(string: "http://nas:32400")!, serverID: "m",
                                            serverName: "nas", userID: "1", userName: "me", secret: .plexToken("tok"))
        let server = PlexServer(credentials: credentials, identity: Self.identity, transport: fake)
        let lyrics = try #require(try await server.lyrics(for: Track(id: "151", name: "Ghost Machine")))
        #expect(lyrics.lines.map(\.text) == ["One", "Two"] && lyrics.lines.last?.start == 2.5)
    }

    @Test("A Plex session in the keychain reads back as it was")
    func keychain() throws {
        let credentials = Self.signedInAtHome()
        let read = try JSONDecoder().decode(ServerCredentials.self, from: JSONEncoder().encode(credentials))
        #expect(read == credentials && read.addresses == [Self.home, Self.remote])
        #expect(MusicServers.open(read, identity: Self.identity) is PlexServer)
    }
}

/// A switch, across tasks.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool
    init(_ on: Bool) { self.on = on }
    var value: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }
}

/// Counts calls, across tasks.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { defer { count += 1 }; return count } }
}
