// What a failed sign-in says and counts, plain http away from home, and
// detection's redirects and walls.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import Testing

@Suite("Signing in: failures, plain http, redirects")
struct SignInFailureTests {
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1", deviceName: "Tests", deviceID: "t")

    @Test("A URLError's code is the reason, through the kit's .transport text")
    func connectionProblems() {
        let cases: [(URLError.Code, String)] = [
            (.timedOut, "timed_out"), (.cannotFindHost, "host_not_found"), (.dnsLookupFailed, "host_not_found"),
            (.cannotConnectToHost, "cannot_connect"), (.notConnectedToInternet, "offline"),
            (.serverCertificateUntrusted, "untrusted_certificate"), (.serverCertificateHasUnknownRoot, "untrusted_certificate"),
            (.secureConnectionFailed, "tls_failed"), (.appTransportSecurityRequiresSecureConnection, "ats_blocked"),
        ]
        for (code, reason) in cases {
            let error = MusicServerError.transport(ConnectionProblem.describe(URLError(code)))
            let failure = SignInFailure(error, step: .password)
            #expect(failure.reason == reason, "\(code)")
            #expect(failure.message == ConnectionProblem(URLError(code))?.message)
        }
        #expect(SignInFailure(MusicServerError.transport("something else"), step: .password).reason == "unreachable")
    }

    @Test("Every failure has a short message of its own")
    func messages() {
        let all: [(Error, SignInFailure.Step, String)] = [
            (MusicServerError.invalidServerAddress, .address, "not_a_server"),
            (MusicServerError.server(status: 401, message: nil), .address, "behind_login"),
            (MusicServerError.server(status: 403, message: nil), .address, "behind_login"),
            (MusicServerError.unauthorized, .password, "wrong_password"),
            (MusicServerError.unauthorized, .apiKey, "wrong_password"),
            (MusicServerError.unauthorized, .quickConnect, "quick_connect_off"),
            (MusicServerError.needsAPIKey(helpURL: nil), .password, "needs_api_key"),
            (MusicServerError.passwordNeedsHTTPS, .password, "needs_https"),
            (MusicServerError.notAllowed, .password, "not_allowed"),
            (MusicServerError.notFound, .quickConnect, "code_expired"),
            (MusicServerError.server(status: 500, message: nil), .password, "server_error"),
        ]
        var seen = Set<String>()
        for (error, step, reason) in all {
            let failure = SignInFailure(error, step: step)
            #expect(failure.reason == reason, "\(error)")
            // One sentence, two at most.
            #expect(failure.message.filter { $0 == "." }.count <= 3, "\(failure.message)")
            seen.insert(failure.message)
        }
        #expect(seen.count == all.count - 1)  // the two wrong_password words differ, behind_login's are one
    }

    @Test("Jukebox's https guess that reached nothing says to type http://")
    func httpHint() throws {
        let error = MusicServerError.transport(ConnectionProblem.describe(URLError(.cannotConnectToHost)))
        let guessed = SignInFailure(error, step: .address, address: URL(string: "https://music.example.com"))
        #expect(guessed.message.contains("http://"))
        let typed = SignInFailure(error, step: .address, address: URL(string: "http://music.example.com"))
        #expect(!typed.message.contains("type http://"))
    }

    @Test("Plain http away from home is insecure; at home, or over https, it is not", arguments: [
        ("http://music.example.com", true), ("http://203.0.113.9:4533", true), ("http://[2001:db8::1]", true),
        ("http://nas.local:4533", false), ("http://192.168.1.20", false), ("http://100.64.0.1", false),
        ("https://music.example.com", false), ("http://[fd12::1]", false),
    ])
    func insecure(address: String, insecure: Bool) throws {
        #expect(ServerAddress.isInsecure(try #require(URL(string: address)), network: Self.home) == insecure)
    }

    /// A device at home: 192.168.1.5/24, Tailscale up, fd12::5/64; "nas.local"
    /// is 192.168.1.20 there.
    static let home = LocalNetwork(interfaces: [
        .init(name: "wlan0", address: [192, 168, 1, 5], mask: [255, 255, 255, 0]),
        .init(name: "tailscale0", address: [100, 101, 1, 2], mask: [255, 255, 255, 255]),
        .init(name: "wlan0", address: [0xfd, 0x12] + [UInt8](repeating: 0, count: 13) + [5],
              mask: [UInt8](repeating: 255, count: 8) + [UInt8](repeating: 0, count: 8)),
    ], resolve: { $0 == "nas.local" ? [[192, 168, 1, 20]] : [] })

    /// The same device in a café: 10.20.0.7/16, no Tailscale; the café's
    /// DNS answers "nas" with an address of its own network, and its mobile
    /// link is carrier-grade NAT, which is not Tailscale.
    static let cafe = LocalNetwork(interfaces: [
        .init(name: "wlan0", address: [10, 20, 0, 7], mask: [255, 255, 0, 0]),
        .init(name: "wwan0", address: [100, 70, 0, 1], mask: [255, 192, 0, 0]),
    ], resolve: { $0 == "nas" ? [[10, 20, 0, 9]] : [] })

    @Test("Home is the network the device is on, not the address's shape", arguments: [
        ("http://192.168.1.20", false, true), ("http://nas.local:4533", false, true),
        ("http://100.64.0.1", false, true), ("http://[fd12::1]", false, true),
        ("http://nas", true, false), ("http://127.0.0.1:8096", false, false), ("http://localhost", false, false),
        ("http://10.20.5.5", true, false), ("http://192.168.1.10:8096", false, true),
        // The rule's limit: a name the café's own DNS answers on its own
        // network passes there.
    ])
    func homeIsWhereTheDeviceIs(address: String, home: Bool, cafe: Bool) throws {
        let url = try #require(URL(string: address))
        #expect(ServerAddress.isInsecure(url, network: Self.home) == home, "at home")
        #expect(ServerAddress.isInsecure(url, network: Self.cafe) == cafe, "in the café")
    }

    @Test("A credential over plain http waits for the home network; detection's first questions go")
    func plainHTTPGuard() throws {
        var signIn = URLRequest(url: try #require(URL(string: "http://192.168.1.10:8096/Users/AuthenticateByName")))
        signIn.httpMethod = "POST"
        signIn.httpBody = Data(#"{"Pw":"x"}"#.utf8)
        #expect(PlainHTTPGuard.carriesCredentials(signIn))
        var info = URLRequest(url: try #require(URL(string: "http://192.168.1.10:8096/System/Info/Public")))
        info.setValue("MediaBrowser Client=\"Jukebox\", Device=\"Linux\"", forHTTPHeaderField: "X-Emby-Authorization")
        #expect(!PlainHTTPGuard.carriesCredentials(info))
        info.setValue("MediaBrowser Client=\"Jukebox\", Token=\"abc\"", forHTTPHeaderField: "X-Emby-Authorization")
        #expect(PlainHTTPGuard.carriesCredentials(info))
        let subsonic = URLRequest(url: try #require(URL(string: "http://nas:4533/rest/ping?u=a&t=b&s=c")))
        #expect(PlainHTTPGuard.carriesCredentials(subsonic))
        #expect(!PlainHTTPGuard.carriesCredentials(URLRequest(url: try #require(URL(string: "http://nas:4533/rest/ping")))))
        let defaults = try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)"))
        let consent = PlainHTTPConsent(defaults: defaults)
        consent.accept(try #require(URL(string: "http://192.168.1.10:8096/jellyfin")))
        #expect(consent.isAcceptedOrigin(try #require(URL(string: "http://192.168.1.10:8096/Items"))))
        #expect(!consent.isAcceptedOrigin(try #require(URL(string: "http://192.168.1.10:8097/Items"))))
    }

    @Test("Sign In Anyway is kept per address, and only an insecure address asks")
    func consent() throws {
        let defaults = try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)"))
        try LocalNetwork.$standIn.withValue(Self.home) {
        let consent = PlainHTTPConsent(defaults: defaults)
        let away = try #require(URL(string: "http://music.example.com:4533"))
        let other = try #require(URL(string: "http://music.example.com:4534"))
        #expect(consent.mustAsk(away))
        #expect(!consent.mustAsk(try #require(URL(string: "http://nas.local:4533"))))
        #expect(!consent.mustAsk(try #require(URL(string: "https://music.example.com"))))
        consent.accept(away)
        consent.accept(away)
        #expect(!consent.mustAsk(away))
        #expect(consent.mustAsk(other))
        #expect(defaults.stringArray(forKey: PlainHTTPConsent.key) == [away.absoluteString])
        }
    }

    @Test("The password itself goes over plain http away from home only after Sign In Anyway")
    func passwordAfterConsent() async throws {
        let defaults = try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)"))
        let consent = PlainHTTPConsent(defaults: defaults)
        let url = try #require(URL(string: "http://music.example.com:4533"))
        let fake = SubsonicClientTests.hashKeeper(password: "pw")
        let signIn = SubsonicSignIn(server: SubsonicFixtures.detected(capabilities: [.lyrics], url: url),
                                    identity: SubsonicFixtures.identity, transport: fake, consent: consent)
        await #expect(throws: MusicServerError.passwordNeedsHTTPS) {
            _ = try await signIn.signIn(username: "test", password: "pw")
        }
        #expect(fake.requests("ping").allSatisfy { $0.value("p") == nil })
        consent.accept(url)
        // Then its own question: the password itself.
        await #expect(throws: MusicServerError.passwordItself) {
            _ = try await signIn.signIn(username: "test", password: "pw")
        }
        #expect(fake.requests("ping").allSatisfy { $0.value("p") == nil })
        consent.acceptPasswordItself(url)
        let credentials = try await signIn.signIn(username: "test", password: "pw")
        #expect(credentials.secret == .subsonicPassword("pw"))
    }

    @Test("Over https too, the password itself goes only after its own question")
    func passwordItselfOverHTTPS() async throws {
        let defaults = try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)"))
        let consent = PlainHTTPConsent(defaults: defaults)
        let url = try #require(URL(string: "https://music.example.com"))
        let fake = SubsonicClientTests.hashKeeper(password: "pw")
        let signIn = SubsonicSignIn(server: SubsonicFixtures.detected(capabilities: [.lyrics], url: url),
                                    identity: SubsonicFixtures.identity, transport: fake, consent: consent)
        await #expect(throws: MusicServerError.passwordItself) {
            _ = try await signIn.signIn(username: "test", password: "pw")
        }
        #expect(fake.requests("ping").allSatisfy { $0.value("p") == nil })
        #expect(SignInFailure(MusicServerError.passwordItself, step: .password).reason == "password_itself")
        #expect(!PasswordItselfWords.message(for: url).contains(PasswordItselfWords.unencrypted))
    }

    @Test("A redirect at sign-in to another host is not taken as the server: the café run")
    func redirectToAnotherHost() async throws {
        // The café drops 443 for music.example.test; its 8096 answers 301
        // to https://evil.example.test, which plays Jellyfin with a real
        // certificate. Nothing may sign in there.
        let fake = AddressFake { url in
            guard url.scheme == "http", url.port == 8096 else { throw URLError(.cannotConnectToHost) }
            var answer = AddressFake.jellyfin(url)
            answer.url = URL(string: "https://evil.example.test\(url.path)")
            return answer
        }
        await #expect(throws: MusicServerError.movedElsewhere(host: "evil.example.test")) {
            _ = try await MusicServers.detect("music.example.test", identity: Self.identity, transport: fake)
        }
        #expect(!fake.requests.contains { $0.path.contains("AuthenticateByName") })
        // The same host on another port is another server too.
        let port = AddressFake { url in
            guard url.scheme == "http", url.port == 8096 else { throw URLError(.cannotConnectToHost) }
            var answer = AddressFake.jellyfin(url)
            answer.url = URL(string: "https://music.example.test:9443\(url.path)")
            return answer
        }
        await #expect(throws: MusicServerError.movedElsewhere(host: "music.example.test:9443")) {
            _ = try await MusicServers.detect("music.example.test", identity: Self.identity, transport: port)
        }
    }

    @Test("A server reached through a redirect keeps the address it answered at")
    func redirected() async throws {
        let fake = AddressFake { url in
            var answer = AddressFake.navidrome(url)
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            parts.scheme = "https"
            parts.port = nil
            answer.url = parts.url
            return answer
        }
        let server = try await MusicServers.detect("http://music.example.com", identity: Self.identity, transport: fake)
        #expect(server.url.absoluteString == "https://music.example.com")
        #expect(server.id == "https://music.example.com")
    }

    @Test("Every answer a 401 or 403: a wall in front, not \"no server\"")
    func wall() async throws {
        let fake = AddressFake { _ in HTTPResponse(status: 401, body: Data("<html>Sign in</html>".utf8)) }
        await #expect(throws: MusicServerError.server(status: 401, message: nil)) {
            _ = try await MusicServers.detect("https://music.example.com:443", identity: Self.identity, transport: fake)
        }
    }

    @Test("Redirects: same host as they are, never down to http, another host without credentials or a body")
    func redirectPolicy() throws {
        func request(_ url: String, method: String = "GET", body: Bool = false) -> URLRequest {
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = method
            if body { request.httpBody = Data(#"{"Pw":"secret"}"#.utf8) }
            request.setValue("MediaBrowser Token=\"t\"", forHTTPHeaderField: "Authorization")
            request.setValue("t", forHTTPHeaderField: "X-Emby-Token")
            request.setValue("p", forHTTPHeaderField: "X-Plex-Token")
            return request
        }
        let post = request("http://music.example.com/Users/AuthenticateByName", method: "POST", body: true)
        // http to https on the same host: followed, body and all.
        let upgraded = try #require(RedirectPolicy.next(
            request("https://music.example.com/Users/AuthenticateByName", method: "POST", body: true), after: post))
        #expect(upgraded.httpBody != nil)
        #expect(upgraded.value(forHTTPHeaderField: "Authorization") != nil)
        // Never from https down to plain http, not even on the same host.
        #expect(RedirectPolicy.next(request("http://music.example.com/x"), after: request("https://music.example.com/x")) == nil)
        // The same host on another port is another origin: no body, no
        // credential headers.
        #expect(RedirectPolicy.next(request("https://music.example.com:8443/Users/AuthenticateByName", method: "POST",
                                            body: true), after: post) == nil)
        let otherPort = try #require(RedirectPolicy.next(request("https://music.example.com:8443/x"),
                                                         after: request("https://music.example.com/x")))
        #expect(otherPort.value(forHTTPHeaderField: "X-Emby-Token") == nil)
        // Another host: never the POST's body (a 307 or 308)…
        #expect(RedirectPolicy.next(request("https://evil.example.net/x", method: "POST", body: true), after: post) == nil)
        // …and a GET goes without the credential headers.
        let elsewhere = try #require(RedirectPolicy.next(request("https://cdn.example.net/x"),
                                                         after: request("https://music.example.com/x")))
        for header in RedirectPolicy.credentialHeaders { #expect(elsewhere.value(forHTTPHeaderField: header) == nil) }
        // Nowhere but http and https.
        #expect(RedirectPolicy.next(request("ftp://music.example.com/x"), after: request("http://music.example.com/x")) == nil)
    }

    @Test("A dotted name whose https does not answer, found on plain http: that sign-in asks first, never silently")
    func httpFallbackAsks() async throws {
        let fake = AddressFake { url in
            guard url.scheme == "http", url.port == 8096 else { throw URLError(.cannotConnectToHost) }
            return AddressFake.jellyfin(url)
        }
        let server = try await MusicServers.detect("music.example.com", identity: Self.identity, transport: fake)
        #expect(server.url.absoluteString == "http://music.example.com:8096")
        let defaults = try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)"))
        #expect(PlainHTTPConsent(defaults: defaults).mustAsk(server.url))
        #expect(ServerAddress.isInsecure(server.url))
    }

    @Test("A name on the internet is asked alone first: its fallback ports only after it fails")
    func publicNameAlone() async throws {
        let fake = AddressFake { url in
            if url.port == nil { return AddressFake.navidrome(url) }
            throw URLError(.timedOut)
        }
        let server = try await MusicServers.detect("music.example.com", identity: Self.identity, transport: fake)
        #expect(server.url.absoluteString == "https://music.example.com")
        #expect(fake.requests.allSatisfy { $0.port == nil })
    }
}
