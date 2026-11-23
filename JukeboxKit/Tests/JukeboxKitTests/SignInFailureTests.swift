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
        #expect(ServerAddress.isInsecure(try #require(URL(string: address))) == insecure)
    }

    @Test("Sign In Anyway is kept per address, and only an insecure address asks")
    func consent() throws {
        let defaults = try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)"))
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
        let credentials = try await signIn.signIn(username: "test", password: "pw")
        #expect(credentials.secret == .subsonicPassword("pw"))
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
