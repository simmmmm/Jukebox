// The addresses that leave the transport (a song's stream, a cast's, a
// download, the remote control's websocket) wait for the home network as
// every call does: each server's own, run through PlainHTTPGuard at home
// and in the café (SignInFailureTests.home, .cafe).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit
import Testing

@Suite("Plain http addresses outside the transport")
struct PlainHTTPAddressesTests {
    static let identity = SubsonicFixtures.identity

    /// Every address a server hands a player, a TV, a download or a socket,
    /// each with the account's token in it.
    static func addresses() throws -> [URL] {
        let track = Track(id: "s1", name: "Song")
        let jellyfin = JellyfinClient(serverURL: try #require(URL(string: "http://192.168.1.10:8096")), identity: identity,
                                      accessToken: "tok", userID: "u")
        let subsonic = SubsonicClient(credentials: SubsonicFixtures.credentials(url: try #require(URL(string: "http://192.168.1.20:4533"))),
                                      identity: identity)
        let plex = PlexServer(credentials: PlexSignInTests.signedInAtHome(), identity: identity)
        return [
            jellyfin.streamURL(trackID: "s1", quality: .original, playSessionID: "p"),
            jellyfin.castURL(for: track).url,
            jellyfin.downloadURL(trackID: "s1", quality: .original),
            try #require(jellyfin.sessionSocketURL),
            subsonic.streamURL(for: track, quality: .original, playSessionID: "p"),
            subsonic.castURL(for: track).url,
            subsonic.downloadURL(for: track, quality: .original),
            plex.streamURL(for: track, quality: .low, playSessionID: "p"),
            plex.downloadURL(for: track, quality: .normal),
        ]
    }

    @Test("Each carries its token, and goes at home only")
    func homeOnly() throws {
        for url in try Self.addresses() {
            #expect(PlainHTTPGuard.carriesCredentials(URLRequest(url: url)), "\(url)")
            LocalNetwork.$standIn.withValue(SignInFailureTests.cafe) {
                #expect(!PlainHTTPGuard.mayFetch(url), "café: \(url)")
                #expect(!PlainHTTPGuard.mayFetchNow(url), "café: \(url)")
                #expect(PlainHTTPGuard.refusal(for: url)?.contains("isn't on the network") == true, "\(url)")
            }
            LocalNetwork.$standIn.withValue(SignInFailureTests.home) {
                #expect(PlainHTTPGuard.mayFetch(url), "home: \(url)")
                // A literal address needs no lookup: known at once.
                #expect(PlainHTTPGuard.mayFetchNow(url), "home: \(url)")
            }
        }
    }

    @Test("A websocket is plain http as ws://, and secure as wss://")
    func websocket() throws {
        let plain = try #require(URL(string: "ws://192.168.1.10:8096/socket?ApiKey=tok&deviceId=d"))
        let secure = try #require(URL(string: "wss://192.168.1.10:8096/socket?ApiKey=tok&deviceId=d"))
        LocalNetwork.$standIn.withValue(SignInFailureTests.cafe) {
            #expect(!PlainHTTPGuard.mayFetch(plain))
            #expect(PlainHTTPGuard.mayFetch(secure) && PlainHTTPGuard.mayFetchNow(secure))
        }
        let https = JellyfinClient(serverURL: try #require(URL(string: "https://192.168.1.10:8920")), identity: Self.identity,
                                   accessToken: "tok")
        #expect(https.sessionSocketURL?.scheme == "wss")
    }

    @Test("A name not looked up lately is not cleared at once; looked up, it is")
    func nameWaitsForLookup() throws {
        let url = try #require(URL(string: "http://nas.local:4533/rest/stream?u=a&t=b&s=c&id=s1"))
        LocalNetwork.$standIn.withValue(SignInFailureTests.home) {
            #expect(!PlainHTTPGuard.mayFetchNow(url))
            #expect(PlainHTTPGuard.mayFetch(url))
        }
        // Without its token it goes as it is, looked up or not.
        let bare = try #require(URL(string: "http://nas.local:4533/rest/ping"))
        LocalNetwork.$standIn.withValue(SignInFailureTests.cafe) {
            #expect(PlainHTTPGuard.mayFetchNow(bare))
        }
    }

    @Test("Sign In Anyway clears an address away from home, the websocket's too")
    func acceptedOrigin() throws {
        let accepted = PlainHTTPConsent(defaults: try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)")))
        let asked = PlainHTTPConsent(defaults: try #require(UserDefaults(suiteName: "consent-\(UUID().uuidString)")))
        accepted.accept(try #require(URL(string: "http://192.168.1.10:8096")))
        let socket = URLRequest(url: try #require(URL(string: "ws://192.168.1.10:8096/socket?ApiKey=tok")))
        LocalNetwork.$standIn.withValue(SignInFailureTests.cafe) {
            #expect(PlainHTTPGuard.refusal(socket, consent: accepted) == nil)
            #expect(PlainHTTPGuard.refusal(socket, consent: asked) != nil)
        }
    }
}
