// Emby, Jellyfin's ancestor, spoken to by JellyfinClient with `isEmby`
// (docs/SERVERS.md, "Emby"): where the two differ, against answers as Emby
// 4.10 gave them; and the real Emby of dev/emby-test-server.sh (user
// test/test, the made-up library), skipped when EMBY_URL is not set.
// dev/kit-test.sh sets it when the container runs. Everything else the app
// asks of Emby is ServerContractTests', where Emby is one of the servers.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

enum EmbyTestServer {
    static let environment = ProcessInfo.processInfo.environment
    static let url: URL? = environment["EMBY_URL"].flatMap { MusicServers.candidateAddresses(for: $0).first }
    static let user = environment["EMBY_USER"] ?? "test"
    static let password = environment["EMBY_PASSWORD"] ?? "test"

    static func identity(_ device: String) -> ClientIdentity {
        ClientIdentity(clientName: "JukeboxKitTests", clientVersion: "1.0",
                       deviceName: "Kit tests: Emby \(device)", deviceID: "jukebox-kit-emby-\(device)")
    }

    /// What Emby 4.10 answered without credentials (measured): public info
    /// without a ProductName, and its ping as plain text.
    static func answer(_ url: URL) -> HTTPResponse {
        switch url.path {
        case "/System/Info/Public":
            .json(#"{"LocalAddresses":[],"RemoteAddresses":[],"ServerName":"7357f6d294fb","Version":"4.10.2.0","Id":"6188f42b95714cba829673da04d4248a"}"#)
        case "/System/Ping": HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("Emby Server".utf8))
        default: HTTPResponse(status: 404, body: Data("The file '\(url.path)' could not be found.".utf8))
        }
    }

    static let credentials = ServerCredentials(
        kind: .emby, serverURL: URL(string: "http://emby.local:8096")!, serverID: "6188f42b95714cba829673da04d4248a",
        serverName: "nas", serverVersion: "4.10.2.0", userID: "f6a52d5afb1b4b37854a9c9a38f502ee", userName: "test",
        secret: .jellyfinToken("0123456789abcdef0123456789abcdef"), capabilities: ServerCapability.emby)
}

@Suite("Emby: where it differs from Jellyfin")
struct EmbyTests {
    @Test("Found as Emby by its ping, with Emby's capabilities and no Quick Connect; Jellyfin still Jellyfin")
    func detection() async throws {
        let identity = ServerAddressTests.identity
        let emby = AddressFake { EmbyTestServer.answer($0) }
        let server = try await MusicServers.detect("http://emby.local:8096", identity: identity, transport: emby)
        #expect(server.kind == .emby && server.kind.displayName == "Emby")
        #expect(server.id == "6188f42b95714cba829673da04d4248a" && server.version == "4.10.2.0")
        #expect(server.capabilities == ServerCapability.emby)
        #expect(!(MusicServers.signIn(to: server, identity: identity, transport: emby) is any QuickConnectSignIn))

        // Jellyfin names itself, so it is never asked the ping.
        let jellyfin = AddressFake { AddressFake.jellyfin($0) }
        #expect(try await MusicServers.detect("http://jf.local:8096", identity: identity, transport: jellyfin).kind == .jellyfin)
        #expect(!jellyfin.requests.contains { $0.path == "/System/Ping" })
    }

    @Test("An Emby session is kept and opened again as Emby")
    func keptAsEmby() throws {
        let data = try JSONEncoder().encode(EmbyTestServer.credentials)
        let again = try JSONDecoder().decode(ServerCredentials.self, from: data)
        #expect(again == EmbyTestServer.credentials && again.jellyfin?.accessToken == "0123456789abcdef0123456789abcdef")
        let server = MusicServers.open(again, identity: ServerAddressTests.identity)
        #expect(server.kind == .emby && server.capabilities == ServerCapability.emby)
        #expect((server as? JellyfinServer)?.client.isEmby == true)
    }

    @Test("The token goes in a URL as api_key, covers are sized by maxWidth; Jellyfin's URLs as they were")
    func urls() throws {
        let identity = ServerAddressTests.identity
        let emby = MusicServers.open(EmbyTestServer.credentials, identity: identity)
        var jellyfinCredentials = EmbyTestServer.credentials
        jellyfinCredentials.kind = .jellyfin
        let jellyfin = MusicServers.open(jellyfinCredentials, identity: identity)
        let track = Track(id: "378", name: "Blue Dance", albumID: "528", duration: 5)
        func query(_ url: URL) -> [String: String] {
            Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
                       uniquingKeysWith: { first, _ in first })
        }
        for (server, key, other) in [(emby, "api_key", "ApiKey"), (jellyfin, "ApiKey", "api_key")] {
            let stream = query(server.streamURL(for: track, quality: .low, playSessionID: "p"))
            let download = query(server.downloadURL(for: track, quality: .normal))
            #expect(stream[key] == "0123456789abcdef0123456789abcdef" && download[key] == stream[key])
            #expect(stream[other] == nil && download[other] == nil)
        }
        let cover = Artwork(itemID: "528", tag: "80f2190aa02cec8adedfdf3a9e3dc56f")
        #expect(query(emby.artworkURL(cover, maxPixelSize: 300)) == ["maxWidth": "300", "maxHeight": "300", "quality": "90", "tag": cover.tag!])
        #expect(query(jellyfin.artworkURL(cover, maxPixelSize: 300)) == ["fillWidth": "300", "fillHeight": "300", "quality": "90", "tag": cover.tag!])
    }
}

@Suite("Emby: the real server", .serialized, .timeLimit(.minutes(1)), .enabled(if: EmbyTestServer.url != nil))
struct EmbyIntegrationTests {
    @Test("Found as Emby, signed in, kept, opened again; a song plays from the URL it makes")
    func signIn() async throws {
        let url = try #require(EmbyTestServer.url)
        let identity = EmbyTestServer.identity("sign-in")
        let server = try await MusicServers.detect(url.absoluteString, identity: identity)
        #expect(server.kind == .emby && server.capabilities == ServerCapability.emby)
        let signIn = MusicServers.signIn(to: server, identity: identity)
        #expect(!(signIn is any QuickConnectSignIn))
        await #expect(throws: MusicServerError.unauthorized) {
            _ = try await signIn.signIn(username: EmbyTestServer.user, password: "not the password")
        }
        let credentials = try await signIn.signIn(username: EmbyTestServer.user, password: EmbyTestServer.password)
        #expect(credentials.kind == .emby && credentials.capabilities == ServerCapability.emby)
        let kept = try JSONDecoder().decode(ServerCredentials.self, from: JSONEncoder().encode(credentials))
        let opened = MusicServers.open(kept, identity: identity)
        let track = try #require(try await opened.allTracks(progress: nil).first)
        let file = try await JellyfinTestServer.fetch(opened.streamURL(for: track, quality: .original, playSessionID: UUID().uuidString))
        #expect(file.status == 200 && file.jellyfinHeader("Content-Type")?.hasPrefix("audio/") == true)
        await opened.signOut()
        #expect(try await JellyfinTestServer.fetch(opened.streamURL(for: track, quality: .original, playSessionID: "x")).status == 401)
    }
}
