// SubsonicClient and its sign-in against a transport that answers for the
// server (SubsonicFake): the token, the envelope and its errors, the URLs it
// makes for AVPlayer, the image view and the downloads, the playback
// reports, and the calls only the server can answer. The answers are
// Navidrome 0.64.2's (SubsonicFixtures). docs/SERVERS.md is the design.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Subsonic: client")
struct SubsonicClientTests {
    typealias F = SubsonicFixtures

    // MARK: MD5

    /// RFC 1321's seven test vectors, the lengths around the padding's edge
    /// (55 bytes is the most one block holds), a password of more than
    /// ASCII, and the test server's token as `md5sum` makes it.
    @Test("MD5: RFC 1321's vectors, the padding's edges, UTF-8, and md5sum's token", arguments: [
        ("", "d41d8cd98f00b204e9800998ecf8427e"),
        ("a", "0cc175b9c0f1b6a831c399e269772661"),
        ("abc", "900150983cd24fb0d6963f7d28e17f72"),
        ("message digest", "f96b697d7cb7938d525a2f31aaf161d0"),
        ("abcdefghijklmnopqrstuvwxyz", "c3fcd3d76192e4007dfb496cca67e13b"),
        ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "d174ab98d277d9f5a5611c2c9f419d9f"),
        (String(repeating: "1234567890", count: 8), "57edf4a22be3c955ac49da2e2107b67a"),
        (String(repeating: "a", count: 55), "ef1772b6dff9a122358552954ad0df65"),
        (String(repeating: "a", count: 56), "3b0c8ac703f828b04c6c197006d17218"),
        (String(repeating: "a", count: 63), "b06521f39153d618550606be297466d5"),
        (String(repeating: "a", count: 64), "014842d480b571495a4a0363793f7367"),
        (String(repeating: "a", count: 65), "c743a45e0d2e6a95cb859adae0248435"),
        ("wachtwoord€ü0123456789abcdef", "82a1ca3f5b7d20a542ac5cc87373ce03"),
        ("testjukeboxtests", "e1c8d3b746dc149eaee6c600a4b2c47c"),
    ])
    func md5(text: String, digest: String) {
        #expect(MD5.hex(text) == digest)
    }

    @Test("A salt is 16 hex digits, a new one each time; hex is two digits a byte")
    func salts() {
        let salts = (0..<200).map { _ in SubsonicConnection.makeSalt() }
        #expect(salts.allSatisfy { $0.count == 16 && $0.allSatisfy(\.isHexDigit) && $0 == $0.lowercased() })
        #expect(Set(salts).count == salts.count)
        #expect(SubsonicConnection.hex([0x00, 0x0f, 0xa0, 0xff]) == "000fa0ff")
        #expect(SubsonicConnection.token(password: "test", salt: F.salt) == F.token)
    }

    // MARK: Signing in

    /// A Navidrome that knows user "test" with this password.
    static func navidrome(password: String, streamRole: Bool = true) -> SubsonicFake {
        let fake = SubsonicFake()
        fake.on("ping") { request in
            let salt = request.value("s") ?? ""
            let right = request.value("u") == "test" && request.value("t") == MD5.hex(password + salt)
            return .json(right ? F.ok() : F.failed(40, "Wrong username or password"))
        }
        fake.on("getUser", ok: streamRole ? F.user : F.user.replacingOccurrences(of: #""streamRole":true"#, with: #""streamRole":false"#))
        fake.on("getOpenSubsonicExtensions", ok: F.extensions)
        return fake
    }

    @Test("Signing in: t = md5(password + s) with a fresh salt; the password is sent and kept nowhere")
    func signInWithToken() async throws {
        let password = "geheim wachtwoord€"
        let fake = Self.navidrome(password: password)
        let signIn = MusicServers.signIn(to: F.detected(), identity: F.identity, transport: fake)
        #expect(!(signIn is any APIKeySignIn))
        #expect(!(signIn is any QuickConnectSignIn))
        let credentials = try await signIn.signIn(username: " test ", password: password)

        let ping = try #require(fake.requests("ping").first)
        let salt = try #require(ping.value("s"))
        #expect(salt.count == 16 && salt.allSatisfy(\.isHexDigit))
        #expect(ping.value("u") == "test")
        #expect(ping.value("t") == MD5.hex(password + salt))
        #expect(ping.value("p") == nil)
        #expect(ping.value("v") == "1.16.1")
        #expect(ping.value("c") == "Jukebox")
        #expect(ping.value("f") == "json")

        #expect(credentials.secret == .subsonicToken(token: MD5.hex(password + salt), salt: salt))
        #expect(credentials.kind == .subsonic(flavour: .navidrome))
        #expect(credentials.userID == "test" && credentials.userName == "test")
        #expect(credentials.apiVersion == "1.16.1")
        #expect(credentials.serverVersion == "0.64.2 (10114574)")
        #expect(credentials.serverURL == F.server)
        #expect(credentials.serverID == F.server.absoluteString)
        #expect(credentials.capabilities == F.navidromeCapabilities)
        #expect(!credentials.capabilities.contains(.apiKeySignIn) && !credentials.capabilities.contains(.quickConnect))
        #expect(fake.requests("getUser").first?.value("username") == "test")

        // Nothing sent or kept carries the password, as itself or in hex.
        let kept = String(decoding: try JSONEncoder().encode(credentials), as: UTF8.self)
        let hexed = SubsonicConnection.hex(Array(password.utf8))
        for text in [kept] + fake.requests.map({ $0.url.absoluteString + ($0.body ?? "") }) {
            #expect(!text.contains("geheim") && !text.contains("wachtwoord") && !text.contains(hexed))
        }
    }

    @Test("Two sign-ins, two salts; one session, one salt in every request and every URL")
    func oneSaltPerSession() async throws {
        let fake = Self.navidrome(password: "test")
        let signIn = SubsonicSignIn(server: F.detected(), identity: F.identity, transport: fake)
        let first = try await signIn.signIn(username: "test", password: "test")
        let second = try await signIn.signIn(username: "test", password: "test")
        #expect(first.secret != second.secret)

        guard case let .subsonicToken(token, salt) = first.secret else { Issue.record("not a token"); return }
        let session = SubsonicFake()
        session.on("getGenres", ok: #""genres":{}"#)
        session.on("getPlaylists", ok: #""playlists":{}"#)
        session.on("getAlbumList2", ok: #""albumList2":{}"#)
        let client = MusicServers.open(first, identity: F.identity, transport: session)
        _ = try await client.genres()
        _ = try await client.playlists()
        _ = try await client.allAlbums()
        let track = Track(id: "s1", name: "Song")
        let urls = [client.streamURL(for: track, quality: .original, playSessionID: "a"),
                    client.streamURL(for: track, quality: .low, playSessionID: "b"),
                    client.artworkURL(Artwork(itemID: "al1", tag: "al-al1_00"), maxPixelSize: 300),
                    client.downloadURL(for: track, quality: .original),
                    client.downloadURL(for: track, quality: .normal)]
        #expect(session.requests.count == 3)
        for request in session.requests {
            #expect(request.value("u") == "test" && request.value("t") == token && request.value("s") == salt)
        }
        for url in urls {
            let query = subsonicQuery(url)
            #expect(query["u"] == ["test"] && query["t"] == [token] && query["s"] == [salt], "\(url)")
            #expect(query["p"] == nil && query["playSessionId"] == nil)
        }
        // The same artwork and size: the same URL, so the image cache keeps it.
        #expect(client.artworkURL(Artwork(itemID: "al1", tag: "al-al1_00"), maxPixelSize: 300) == urls[2])
    }

    @Test("A wrong password is .unauthorized; a user who may not stream is .notAllowed")
    func signInRefused() async throws {
        let signIn = SubsonicSignIn(server: F.detected(), identity: F.identity,
                                    transport: Self.navidrome(password: "right"))
        await #expect(throws: MusicServerError.unauthorized) { _ = try await signIn.signIn(username: "test", password: "wrong") }
        let nobody = SubsonicFake()
        await #expect(throws: MusicServerError.unauthorized) {
            _ = try await SubsonicSignIn(server: F.detected(), identity: F.identity, transport: nobody)
                .signIn(username: "  ", password: "x")
        }
        #expect(nobody.requests.isEmpty)

        let listener = SubsonicSignIn(server: F.detected(), identity: F.identity,
                                      transport: Self.navidrome(password: "test", streamRole: false))
        await #expect(throws: MusicServerError.notAllowed) { _ = try await listener.signIn(username: "test", password: "test") }
    }

    /// A server that keeps only a hash of the password answers a token with
    /// 41 ("Token authentication not supported").
    static func hashKeeper(password: String) -> SubsonicFake {
        let fake = SubsonicFake()
        fake.on("ping") { request in
            if request.value("t") != nil {
                return .json(#"{"subsonic-response":{"status":"failed","version":"1.16.1","type":"lms","openSubsonic":true,"error":{"code":41,"message":"Token authentication not supported","helpUrl":"https://music.example.com/settings/keys"}}}"#)
            }
            let right = request.value("p") == "enc:" + SubsonicConnection.hex(Array(password.utf8))
                || (request.value("apiKey") == "the-key" && request.value("u") == nil)
            return .json(right ? F.ok() : F.failed(request.value("apiKey") != nil ? 44 : 40, "no"))
        }
        fake.on("getUser", ok: F.user)
        fake.on("tokenInfo", ok: #""tokenInfo":{"username":"keyholder"}"#)
        return fake
    }

    @Test("Error 41: an API key where offered; else the password itself, only over https or at home")
    func tokensRefused() async throws {
        let keyServer = F.detected(capabilities: [.apiKeySignIn, .lyrics])
        let offered = MusicServers.signIn(to: keyServer, identity: F.identity, transport: Self.hashKeeper(password: "pw"))
        #expect(offered is any APIKeySignIn)
        await #expect(throws: MusicServerError.needsAPIKey(helpURL: URL(string: "https://music.example.com/settings/keys"))) {
            _ = try await offered.signIn(username: "test", password: "pw")
        }

        let fake = Self.hashKeeper(password: "pw")
        let withKey = try #require(MusicServers.signIn(to: keyServer, identity: F.identity, transport: fake) as? any APIKeySignIn)
        let credentials = try await withKey.signIn(apiKey: " the-key ")
        #expect(credentials.secret == .subsonicAPIKey("the-key"))
        #expect(credentials.userName == "keyholder" && credentials.userID == "keyholder")
        #expect(fake.requests("ping").last?.value("u") == nil)
        #expect(fake.requests("getUser").first?.value("username") == "keyholder")
        await #expect(throws: MusicServerError.unauthorized) { _ = try await withKey.signIn(apiKey: "wrong") }

        // No key offered: the password, at home and over https; not over
        // plain http to the internet, where it would go in the clear.
        for (address, allowed) in [("http://nas.local:4533", true), ("http://192.168.1.20:4533", true),
                                   ("https://music.example.com", true), ("http://music.example.com:4533", false),
                                   ("http://203.0.113.9:4533", false)] {
            let url = try #require(URL(string: address))
            let fake = Self.hashKeeper(password: "pw")
            let signIn = SubsonicSignIn(server: F.detected(capabilities: [.lyrics], url: url), identity: F.identity,
                                        transport: fake)
            if allowed {
                let credentials = try await signIn.signIn(username: "test", password: "pw")
                #expect(credentials.secret == .subsonicPassword("pw"), "\(address)")
                #expect(fake.requests("ping").last?.value("p") == "enc:7077")
            } else {
                await #expect(throws: MusicServerError.passwordNeedsHTTPS, "\(address)") {
                    _ = try await signIn.signIn(username: "test", password: "pw")
                }
                #expect(fake.requests("ping").allSatisfy { $0.value("p") == nil })
            }
        }
    }

    @Test("A server older than API 1.13.0 has no tokens: the password at once, at home")
    func beforeTokens() async throws {
        let fake = Self.hashKeeper(password: "pw")
        let old = F.detected(capabilities: [.lyrics], apiVersion: "1.12.0")
        let credentials = try await SubsonicSignIn(server: old, identity: F.identity, transport: fake)
            .signIn(username: "test", password: "pw")
        #expect(credentials.secret == .subsonicPassword("pw"))
        #expect(fake.requests("ping").count == 1)
        #expect(fake.requests("ping").first?.value("v") == "1.12.0")
    }

    // MARK: The envelope

    @Test("Each error of the envelope, and of HTTP, as the app tells them apart")
    func errors() async throws {
        let xml = #"<subsonic-response xmlns="http://subsonic.org/restapi" status="failed" version="1.16.1"><error code="10" message="missing parameter: &#39;u&#39;"></error></subsonic-response>"#
        let cases: [(HTTPResponse, MusicServerError)] = [
            (.json(F.failed(40, "Wrong username or password")), .unauthorized),
            (.json(F.failed(44, "Invalid API key")), .unauthorized),
            (.json(F.failed(50, "User is not authorized for the given operation")), .notAllowed),
            (.json(F.failed(70, "Song not found")), .notFound),
            (.json(F.failed(10, "missing parameter: 'username'")), .server(status: 10, message: "missing parameter: 'username'")),
            (.json(F.failed(30, "Incompatible Subsonic REST protocol version")), .server(status: 30, message: SubsonicConnection.tooOld)),
            (.json(F.failed(20, "Client must upgrade")), .server(status: 20, message: "This server is newer than Jukebox can talk to.")),
            (.json(F.failed(0, "Database is locked")), .server(status: 0, message: "Database is locked")),
            (.json(#"{"subsonic-response":{"status":"failed","version":"1.16.1"}}"#), .server(status: 0, message: nil)),
            (HTTPResponse(status: 404, body: Data("404 page not found".utf8)), .unsupported(nil)),
            (HTTPResponse(status: 401, body: Data()), .unauthorized),
            (HTTPResponse(status: 403, body: Data()), .notAllowed),
            (HTTPResponse(status: 502, body: Data("<html><body>Bad gateway</body></html>".utf8)), .server(status: 502, message: nil)),
            (.json("<!DOCTYPE html><html lang=\"en\"><head></head></html>"), .decoding("not a Subsonic answer")),
            (.json(#"{"Items": []}"#), .decoding("not a Subsonic answer")),
            (HTTPResponse(status: 200, headers: ["Content-Type": "text/xml"], body: Data(xml.utf8)), .server(status: 30, message: SubsonicConnection.tooOld)),
        ]
        for (response, expected) in cases {
            let fake = SubsonicFake()
            fake.on("getGenres") { _ in response }
            await #expect(throws: expected, "\(String(decoding: response.body, as: UTF8.self))") {
                _ = try await F.client(fake).genres()
            }
        }
    }

    @Test("No such endpoint names what the server lacks")
    func unsupported() async throws {
        let client = F.client(SubsonicFake())
        await #expect(throws: MusicServerError.unsupported(.similarArtists)) { _ = try await client.similarArtists(artistID: "a", limit: 5) }
        await #expect(throws: MusicServerError.unsupported(.instantMix)) { _ = try await client.instantMix(from: .track("t"), limit: 5) }
        await #expect(throws: MusicServerError.unsupported(.topSongs)) { _ = try await client.topSongs(of: ArtistRef(id: "a", name: "A"), limit: 5) }
    }

    @Test("A transport failure is .transport; a cancelled request is cancellation; no session asks nothing")
    func transportErrors() async throws {
        let offline = SubsonicFake()
        offline.on("getGenres") { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await F.client(offline).genres()
            Issue.record("no error")
        } catch let MusicServerError.transport(message) {
            #expect(!message.isEmpty)
        }
        let cancelled = SubsonicFake()
        cancelled.on("getGenres") { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) { _ = try await F.client(cancelled).genres() }

        let fake = SubsonicFake()
        let notSignedIn = F.client(fake, secret: .jellyfinToken("not for this server"))
        await #expect(throws: MusicServerError.notSignedIn) { _ = try await notSignedIn.genres() }
        await notSignedIn.report(.played, PlaybackReport(trackID: "t", position: 40, isPaused: false, playSessionID: ""))
        #expect(fake.requests.isEmpty)
    }

    @Test("v is the lower of the server's version and 1.16.1")
    func apiVersion() async throws {
        #expect(SubsonicConnection.lower("1.15.0", "1.16.1") == "1.15.0")
        #expect(SubsonicConnection.lower("1.17.0", "1.16.1") == "1.16.1")
        #expect(SubsonicConnection.lower(nil, "1.16.1") == "1.16.1")
        #expect(SubsonicConnection.lower("nonsense", "1.16.1") == "1.16.1")
        #expect(SubsonicConnection.numbers("0.64.2 (10114574)") == [0, 64, 2])
        #expect(SubsonicConnection.compare("1.2", "1.2.0") == .orderedSame)
        #expect(SubsonicConnection.compare("1.10.0", "1.9.9") == .orderedDescending)
        #expect(SubsonicConnection.atLeast("1.13.0", "1.13.0") && !SubsonicConnection.atLeast(nil, "1.0.0"))

        let fake = SubsonicFake()
        fake.on("getGenres", ok: #""genres":{}"#)
        let old = SubsonicClient(credentials: F.credentials(apiVersion: "1.15.0"), identity: F.identity, transport: fake)
        _ = try await old.genres()
        #expect(fake.requests.first?.value("v") == "1.15.0")
    }

    // MARK: Capabilities

    @Test("Capabilities come from the API version and the extensions, never the name")
    func capabilities() {
        func caps(_ version: String?, _ open: Bool = false, _ ext: Set<String> = []) -> Set<ServerCapability> {
            SubsonicConnection.capabilities(apiVersion: version, openSubsonic: open, extensions: ext)
        }
        #expect(caps(nil) == [.lyrics])
        #expect(caps("1.8.0") == [.lyrics, .playlistReorder])
        #expect(caps("1.11.0") == [.lyrics, .playlistReorder, .instantMix, .similarArtists])
        #expect(caps("1.15.0") == [.lyrics, .playlistReorder, .instantMix, .similarArtists, .topSongs])
        #expect(caps("1.16.1", true, F.navidromeExtensions) == [
            .lyrics, .playlistReorder, .instantMix, .similarArtists, .topSongs, .syncedLyrics, .replayGain,
            .lastPlayed, .playbackTimeline, .transcodeOffset])
        #expect(caps("1.16.1", true, ["apiKeyAuthentication"]).contains(.apiKeySignIn))
    }

    @Test("currentCapabilities asks again: a ping and the extensions")
    func currentCapabilities() async throws {
        let fake = SubsonicFake()
        fake.on("ping", ok: "")
        fake.on("getOpenSubsonicExtensions", ok: F.extensions)
        #expect(try await F.client(fake, capabilities: []).currentCapabilities() == F.navidromeCapabilities)

        let gonic = SubsonicFake()
        gonic.on("ping", body: #"{"subsonic-response":{"status":"ok","version":"1.15.0","type":"gonic","serverVersion":"0.16.4","openSubsonic":false}}"#)
        #expect(try await F.client(gonic).currentCapabilities() == [.lyrics, .playlistReorder, .instantMix, .similarArtists, .topSongs])
        #expect(gonic.requests("getOpenSubsonicExtensions").isEmpty)
    }

    // MARK: URLs

    @Test("Stream URLs: the file at .original (format=raw), MP3 at the cap, MP3 at 320 for what AVPlayer cannot play")
    func streamURLs() throws {
        let client = F.client(SubsonicFake())
        let flac = Track(id: "s1", name: "Song", container: "flac")
        let opus = Track(id: "s2", name: "Song", container: "OPUS")
        func query(_ track: Track, _ quality: StreamQuality) -> [String: [String]] {
            let url = client.streamURL(for: track, quality: quality, playSessionID: "session")
            #expect(url.path == "/rest/stream.view")
            #expect(url.absoluteString.hasPrefix("http://nas.local:4533/rest/stream.view?id="))
            return subsonicQuery(url)
        }
        #expect(query(flac, .original)["format"] == ["raw"])
        #expect(query(flac, .original)["maxBitRate"] == nil)
        #expect(query(Track(id: "s3", name: "No suffix"), .original)["format"] == ["raw"])
        for (quality, kbps) in [(StreamQuality.high, "320"), (.normal, "256"), (.low, "128")] {
            #expect(query(flac, quality)["maxBitRate"] == [kbps])
            #expect(query(flac, quality)["format"] == ["mp3"])
        }
        #expect(query(opus, .original)["maxBitRate"] == ["320"])
        #expect(query(opus, .original)["format"] == ["mp3"])
        #expect(query(opus, .low)["maxBitRate"] == ["128"])
        #expect(query(flac, .original)["id"] == ["s1"])
        #expect(client.streamURL(for: flac, quality: .low, playSessionID: "a")
                == client.streamURL(for: flac, quality: .low, playSessionID: "b"))
    }

    @Test("Download URLs: download at .original, MP3 by stream at 256 and 128, MP3 at 320 for what AVPlayer cannot play")
    func downloadURLs() {
        let client = F.client(SubsonicFake())
        let mp3 = Track(id: "s1", name: "Song", container: "mp3")
        let ogg = Track(id: "s2", name: "Song", container: "ogg")
        let original = client.downloadURL(for: mp3, quality: .original)
        #expect(original.path == "/rest/download.view")
        #expect(subsonicQuery(original)["id"] == ["s1"])
        #expect(subsonicQuery(original)["format"] == nil && subsonicQuery(original)["maxBitRate"] == nil)
        for (quality, kbps) in [(DownloadQuality.high, "256"), (.normal, "128")] {
            let url = client.downloadURL(for: mp3, quality: quality)
            #expect(url.path == "/rest/stream.view")
            #expect(subsonicQuery(url)["maxBitRate"] == [kbps])
            #expect(subsonicQuery(url)["format"] == ["mp3"])
        }
        let converted = client.downloadURL(for: ogg, quality: .original)
        #expect(converted.path == "/rest/stream.view")
        #expect(subsonicQuery(converted)["maxBitRate"] == ["320"] && subsonicQuery(converted)["format"] == ["mp3"])
        #expect(client.downloadURL(for: mp3, quality: .high) == client.downloadURL(for: mp3, quality: .high))
    }

    @Test("Artwork: getCoverArt with the coverArt id, else the item's; the size; a reverse proxy's path; escaping")
    func artworkURLs() throws {
        let client = F.client(SubsonicFake())
        let url = client.artworkURL(Artwork(itemID: "0XtEsASSFBpRROqxktaHgP", tag: "al-0XtEsASSFBpRROqxktaHgP_2d7f387fbb87b3d2"),
                                    maxPixelSize: 300)
        #expect(url.path == "/rest/getCoverArt.view")
        #expect(subsonicQuery(url)["id"] == ["al-0XtEsASSFBpRROqxktaHgP_2d7f387fbb87b3d2"])
        #expect(subsonicQuery(url)["size"] == ["300"])
        #expect(subsonicQuery(client.artworkURL(Artwork(itemID: "al1", tag: nil), maxPixelSize: 0))["id"] == ["al1"])
        #expect(subsonicQuery(client.artworkURL(Artwork(itemID: "al1", tag: ""), maxPixelSize: 0))["size"] == ["1"])
        // A song's disc cover: the colon is escaped, and comes back as it was.
        let disc = client.artworkURL(Artwork(itemID: "s1", tag: "dc-0XtEsASSFBpRROqxktaHgP:1"), maxPixelSize: 240)
        #expect(disc.absoluteString.contains("id=dc-0XtEsASSFBpRROqxktaHgP%3A1&"))
        #expect(subsonicQuery(disc)["id"] == ["dc-0XtEsASSFBpRROqxktaHgP:1"])

        let proxied = SubsonicClient(credentials: F.credentials(url: URL(string: "https://example.com/navidrome/")!),
                                     identity: F.identity, transport: SubsonicFake())
        let odd = proxied.streamURL(for: Track(id: "a b&c=d/é", name: "x"), quality: .original, playSessionID: "")
        #expect(odd.absoluteString.hasPrefix("https://example.com/navidrome/rest/stream.view?id=a%20b%26c%3Dd%2F%C3%A9&"))
        #expect(subsonicQuery(odd)["id"] == ["a b&c=d/é"])
    }

    // MARK: Playback reports

    static func reports(capabilities: Set<ServerCapability>) async -> [SubsonicFake.Request] {
        let fake = SubsonicFake()
        fake.on("scrobble", ok: "")
        fake.on("reportPlayback", ok: "")
        let client = F.client(fake, capabilities: capabilities)
        await client.report(.nowPlaying, PlaybackReport(trackID: "s1", position: 0, isPaused: false, playSessionID: "j"))
        await client.report(.played, PlaybackReport(trackID: "s1", position: 31, isPaused: false, playSessionID: "j"))
        await client.report(.progress, PlaybackReport(trackID: "s1", position: 12.5, isPaused: true, playSessionID: "j"))
        await client.report(.progress, PlaybackReport(trackID: "s1", position: 20, isPaused: false, playSessionID: "j"))
        await client.report(.stopped, PlaybackReport(trackID: "s1", position: 45, isPaused: false, playSessionID: "j"))
        return fake.requests
    }

    @Test("Reports with playbackReport: the timeline with ignoreScrobble, and the one play by scrobble")
    func reportsWithTimeline() async throws {
        let sent = await Self.reports(capabilities: F.navidromeCapabilities)
        let now = Date().timeIntervalSince1970 * 1000
        #expect(sent.map(\.endpoint) == ["reportPlayback", "reportPlayback", "scrobble", "reportPlayback",
                                         "reportPlayback", "reportPlayback"])
        #expect(sent.map { $0.value("state") } == ["starting", "playing", nil, "paused", "playing", "stopped"])
        #expect(sent.map { $0.value("positionMs") } == ["0", "0", nil, "12500", "20000", "45000"])
        for report in sent where report.endpoint == "reportPlayback" {
            #expect(report.value("mediaId") == "s1" && report.value("mediaType") == "song")
            #expect(report.value("ignoreScrobble") == "true")
        }
        let scrobble = sent[2]
        #expect(scrobble.value("id") == "s1" && scrobble.value("submission") == "true")
        let time = try #require(scrobble.value("time").flatMap(Double.init))
        #expect(abs(time - (now - 31_000)) < 5_000)
        #expect(sent.allSatisfy { $0.value("playSessionId") == nil })
    }

    @Test("Reports without playbackReport: now playing and the play by scrobble, nothing else")
    func reportsWithoutTimeline() async throws {
        let sent = await Self.reports(capabilities: [.lyrics, .instantMix])
        #expect(sent.map(\.endpoint) == ["scrobble", "scrobble"])
        #expect(sent.map { $0.value("submission") } == ["false", "true"])
        #expect(sent.allSatisfy { $0.value("id") == "s1" })
    }

    @Test("A report the server refuses never throws")
    func reportErrors() async {
        let fake = SubsonicFake()
        fake.on("scrobble") { _ in HTTPResponse(status: 500, body: Data()) }
        fake.on("reportPlayback") { _ in throw URLError(.timedOut) }
        let client = F.client(fake)
        for event in PlaybackEvent.allCases {
            await client.report(event, PlaybackReport(trackID: "s1", position: 40, isPaused: false, playSessionID: ""))
        }
        #expect(fake.requests.count == 5)
    }

    // MARK: What only the server knows

    @Test("Mixes: getSimilarSongs for a song or an album, getSimilarSongs2 for an artist, a playlist's first song, getRandomSongs by genre")
    func mixes() async throws {
        let fake = SubsonicFake()
        let songs = (1...30).map { F.song("m\($0)") }.joined(separator: ",")
        fake.on("getSimilarSongs", ok: #""similarSongs":{"song":[\#(songs)]}"#)
        fake.on("getSimilarSongs2", ok: #""similarSongs2":{"song":[\#(songs)]}"#)
        fake.on("getRandomSongs", ok: #""randomSongs":{"song":[\#(songs)]}"#)
        fake.on("getPlaylist", ok: #""playlist":{"id":"p1","entry":[\#(F.song("first")),\#(F.song("second"))]}"#)
        let client = F.client(fake)

        let fromTrack = try await client.instantMix(from: .track("t1"), limit: 20)
        #expect(fromTrack.count == 20 && fromTrack.first?.id == "m1")
        _ = try await client.instantMix(from: .album("al1"), limit: 20)
        _ = try await client.instantMix(from: .artist("ar1"), limit: 20)
        _ = try await client.instantMix(from: .genre(name: "Nederhop", id: nil), limit: 1000)
        _ = try await client.instantMix(from: .playlist("p1"), limit: 20)
        let asked = fake.requests.map { "\($0.endpoint) \($0.value("id") ?? $0.value("genre") ?? "-")" }
        #expect(asked == ["getSimilarSongs t1", "getSimilarSongs al1", "getSimilarSongs2 ar1", "getRandomSongs Nederhop",
                          "getPlaylist p1", "getSimilarSongs first"])
        #expect(fake.requests("getSimilarSongs").first?.value("count") == "20")
        #expect(fake.requests("getRandomSongs").first?.value("size") == "500")

        let none = SubsonicFake()
        none.on("getSimilarSongs", ok: #""similarSongs":{}"#)
        none.on("getPlaylist", ok: #""playlist":{"id":"p1","songCount":0}"#)
        #expect(try await F.client(none).instantMix(from: .track("t1"), limit: 20).isEmpty)
        #expect(try await F.client(none).instantMix(from: .playlist("p1"), limit: 20).isEmpty)
        #expect(none.requests("getSimilarSongs").count == 1)
    }

    @Test("Top songs by name and id; similar artists without the artist; {} is none")
    func topSongsAndSimilar() async throws {
        let fake = SubsonicFake()
        fake.on("getTopSongs", ok: #""topSongs":{}"#)
        fake.on("getArtistInfo2", ok: #""artistInfo2":{}"#)
        let client = F.client(fake)
        #expect(try await client.topSongs(of: ArtistRef(id: "3hzlW4nytpm0ULiXdnIWFQ", name: "MC Polder"), limit: 10).isEmpty)
        _ = try await client.topSongs(of: ArtistRef(id: nil, name: "MC Polder"), limit: 10)
        let asked = fake.requests("getTopSongs")
        #expect(asked[0].value("artist") == "MC Polder" && asked[0].value("id") == "3hzlW4nytpm0ULiXdnIWFQ")
        #expect(asked[0].value("count") == "10")
        #expect(asked[1].value("id") == nil)
        #expect(try await client.similarArtists(artistID: "a1", limit: 5).isEmpty)
        let info = try #require(fake.requests("getArtistInfo2").first)
        #expect(info.value("id") == "a1" && info.value("count") == "5" && info.value("includeNotPresent") == "false")

        let lastfm = SubsonicFake()
        lastfm.on("getArtistInfo2", ok: #""artistInfo2":{"biography":"…","similarArtist":[{"id":"a1","name":"Self"},{"id":"a2","name":"Two","albumCount":1},{"id":"a3","name":"Three"}]}"#)
        lastfm.on("getTopSongs", ok: #""topSongs":{"song":[\#(F.song("t1")),\#(F.song("t2"))]}"#)
        #expect(try await F.client(lastfm).similarArtists(artistID: "a1", limit: 5).map(\.name) == ["Two", "Three"])
        #expect(try await F.client(lastfm).topSongs(of: ArtistRef(id: "a1", name: "Self"), limit: 5).map(\.id) == ["t1", "t2"])
    }

    @Test("Lyrics: getLyricsBySongId with songLyrics, getLyrics without; none is nil")
    func lyrics() async throws {
        let track = Track(id: "s1", name: "Blue Parade", artists: [ArtistRef(id: "a", name: "MC Polder")])
        let fake = SubsonicFake()
        fake.on("getLyricsBySongId", ok: #""lyricsList":{}"#)
        fake.on("getLyrics", ok: #""lyrics":{"value":""}"#)
        #expect(try await F.client(fake).lyrics(for: track) == nil)
        #expect(fake.requests("getLyricsBySongId").first?.value("id") == "s1")
        #expect(fake.requests("getLyrics").isEmpty)

        #expect(try await F.client(fake, capabilities: [.lyrics]).lyrics(for: track) == nil)
        let classic = try #require(fake.requests("getLyrics").first)
        #expect(classic.value("artist") == "MC Polder" && classic.value("title") == "Blue Parade")

        // Listed, but not there: the classic call.
        let plain = SubsonicFake()
        plain.on("getLyrics", ok: #""lyrics":{"artist":"MC Polder","title":"Blue Parade","value":"One\r\nTwo\n\nThree\n"}"#)
        let lyrics = try #require(try await F.client(plain).lyrics(for: track))
        #expect(lyrics.lines.map(\.text) == ["One", "Two", "", "Three"])
        #expect(!lyrics.isSynced)
    }

    // MARK: Changes and downloads

    @Test("Favourites: a song by id, an album by albumId, an artist by artistId")
    func favourites() async throws {
        let fake = SubsonicFake()
        fake.on("star", ok: "")
        fake.on("unstar", ok: "")
        let client = F.client(fake)
        try await client.setFavorite(true, item: .track("s1"))
        try await client.setFavorite(true, item: .album("al1"))
        try await client.setFavorite(false, item: .artist("ar1"))
        #expect(fake.requests.map { "\($0.endpoint) \($0.params.first!.name)=\($0.params.first!.value)" }
                == ["star id=s1", "star albumId=al1", "unstar artistId=ar1"])
    }

    @Test("Downloads allowed: getUser's downloadRole; true when it does not say or there is no getUser")
    func downloadsAllowed() async throws {
        func allowed(_ answer: HTTPResponse) async throws -> Bool {
            let fake = SubsonicFake()
            fake.on("getUser") { _ in answer }
            defer { #expect(fake.requests.first?.value("username") == "test") }
            return try await F.client(fake).downloadsAllowed()
        }
        #expect(try await allowed(.json(F.ok(F.user))))
        #expect(try await !allowed(.json(F.ok(F.user.replacingOccurrences(of: #""downloadRole":true"#, with: #""downloadRole":false"#)))))
        #expect(try await allowed(.json(F.ok(#""user":{"username":"test"}"#))))
        #expect(try await allowed(HTTPResponse(status: 404, body: Data())))
        await #expect(throws: MusicServerError.unauthorized) { _ = try await allowed(.json(F.failed(40, "Wrong username or password"))) }
    }
}
