// CoverKey: what the image caches keep a cover under holds none of the
// account's secrets, for every kind of server and secret.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Cover keys")
struct CoverKeyTests {
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.0",
                                         deviceName: "Test", deviceID: "device-1")

    static func account(_ kind: ServerKind, _ secret: ServerSecret, user: String = "anna") -> ServerCredentials {
        ServerCredentials(kind: kind, serverURL: URL(string: "https://music.example.com:4533/base")!,
                          serverID: "server-1", serverName: "Music", userID: "user-1", userName: user,
                          secret: secret, capabilities: [])
    }

    @Test("No secret in the key, the cover's id and size kept", arguments: [
        (ServerKind.subsonic(flavour: .navidrome), ServerSecret.subsonicToken(token: "0123456789abcdef0123456789abcdef", salt: "saltsaltsalt1234")),
        (.subsonic(flavour: .navidrome), .subsonicAPIKey("apikeyapikeyapikey")),
        (.subsonic(flavour: .navidrome), .subsonicPassword("hunter2hunter2")),
        (.jellyfin, .jellyfinToken("jellyfintokenjellyfin")),
        (.plex, .plexToken("plextokenplextoken")),
    ])
    func noSecret(kind: ServerKind, secret: ServerSecret) {
        let server = MusicServers.open(Self.account(kind, secret), identity: Self.identity)
        let url = server.artworkURL(Artwork(itemID: "al-77", tag: "tag-9"), maxPixelSize: 300)
        let key = CoverKey.of(url).absoluteString
        let secrets: [String] = switch secret {
        case let .subsonicToken(token, salt): [token, salt, "u=anna"]
        case let .subsonicAPIKey(key), let .jellyfinToken(key), let .plexToken(key): [key]
        case let .subsonicPassword(password): [password, "enc", password.utf8.map { String(format: "%02x", $0) }.joined()]
        }
        for secret in secrets { #expect(!key.contains(secret), "\(key)") }
        #expect(key.hasPrefix("https://music.example.com:4533/"))
        #expect(key.contains("300") && key.contains("tag-9"), "\(key)")
    }

    @Test("A Subsonic sign-in's new token and salt: the same key")
    func sameAcrossSignIns() {
        let covers = [("aaaa", "1111"), ("bbbb", "2222")].map { token, salt in
            MusicServers.open(Self.account(.subsonic(flavour: .navidrome), .subsonicToken(token: token, salt: salt)),
                              identity: Self.identity).artworkURL(Artwork(itemID: "al-77", tag: nil), maxPixelSize: 300)
        }
        #expect(covers[0] != covers[1])
        #expect(CoverKey.of(covers[0]) == CoverKey.of(covers[1]))
    }

    @Test("Only the kept names stay, sorted; user and fragment go")
    func strips() {
        let url = URL(string: "https://me:pw@h.example/rest/getCoverArt.view?u=a&t=b&s=c&v=1.16&c=Jukebox&size=300&id=x#f")!
        #expect(CoverKey.of(url).absoluteString == "https://h.example/rest/getCoverArt.view?id=x&size=300")
    }
}
