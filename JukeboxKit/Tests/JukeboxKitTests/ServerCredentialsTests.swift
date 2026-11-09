// The server-neutral layer's value types (Server/MusicServer.swift): the
// keychain's session read as it was kept before there were Subsonic servers,
// and the names servers give themselves.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Servers: credentials and kinds")
struct ServerCredentialsTests {
    /// What the Jellyfin-only app put in the keychain: a Credentials, as
    /// JSONEncoder writes it. Read as ServerCredentials, nobody is signed
    /// out by the update.
    @Test("The Jellyfin-only keychain entry still opens the session")
    func readsTheOldCredentials() throws {
        let old = Credentials(serverURL: URL(string: "http://192.168.1.10:8096")!,
                              serverID: "ab1b921a10354a07a7dfbbc2c8061335", serverName: "Tijmen's Music",
                              userID: "f0e1d2c3b4a5968778695a4b3c2d1e0f", userName: "test",
                              accessToken: "0123456789abcdef0123456789abcdef")
        let data = try JSONEncoder().encode(old)
        let read = try JSONDecoder().decode(ServerCredentials.self, from: data)
        #expect(read.kind == .jellyfin)
        #expect(read.secret == .jellyfinToken(old.accessToken))
        #expect(read.serverURL == old.serverURL)
        #expect(read.serverID == old.serverID)
        #expect(read.userID == old.userID)
        #expect(read.capabilities == ServerCapability.jellyfin)
        #expect(read.jellyfin == old)
    }

    @Test("A Subsonic session goes to the keychain and back without its password")
    func subsonicRoundTrip() throws {
        let credentials = ServerCredentials(
            kind: .subsonic(flavour: .navidrome), serverURL: URL(string: "http://nas.local:4533")!,
            serverID: "http://nas.local:4533", serverName: "nas.local", serverVersion: "0.64.2 (10114574)",
            apiVersion: "1.16.1", userID: "test", userName: "test",
            secret: .subsonicToken(token: "e1c8d3b746dc149eaee6c60f0a3c1b2d", salt: "9f2c4a7e1b3d5f60"),
            capabilities: [.instantMix, .lyrics, .syncedLyrics, .playlistReorder, .playbackTimeline])
        let data = try JSONEncoder().encode(credentials)
        #expect(try JSONDecoder().decode(ServerCredentials.self, from: data) == credentials)
        #expect(credentials.jellyfin == nil)
        // No password and no Jellyfin-style token field in what is kept.
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("accessToken"))
        #expect(!text.contains("password"))
    }

    @Test("OpenSubsonic's type names the server", arguments: [
        ("navidrome", SubsonicFlavour.navidrome),
        ("Navidrome", .navidrome),
        ("gonic", .gonic),
        ("airsonic-advanced", .airsonic),
        ("Airsonic", .airsonic),
        ("ampache", .ampache),
        ("lms", .lms),
        ("", .subsonic),
        ("Supysonic", .other("Supysonic")),
    ])
    func flavour(type: String, expected: SubsonicFlavour) {
        #expect(SubsonicFlavour(type: type) == expected)
    }

    @Test("No type at all is the original Subsonic")
    func noType() {
        #expect(SubsonicFlavour(type: nil) == .subsonic)
        #expect(ServerKind.subsonic(flavour: .navidrome).displayName == "Navidrome")
        #expect(ServerKind.jellyfin.displayName == "Jellyfin")
    }

    @Test("JellyfinClient's errors become the layer's one for one")
    func jellyfinErrors() {
        #expect(MusicServerError(.unauthorized) == .unauthorized)
        #expect(MusicServerError(.notFound) == .notFound)
        #expect(MusicServerError(.invalidServerAddress) == .invalidServerAddress)
        #expect(MusicServerError(.server(status: 403, message: nil)) == .notAllowed)
        #expect(MusicServerError(.server(status: 500, message: "x")) == .server(status: 500, message: "x"))
        #expect(MusicServerError(.transport("offline")) == .transport("offline"))
    }

    @Test("Which item a favourite is for")
    func itemRef() {
        #expect(ItemRef.album("al-1").id == "al-1")
        #expect(ItemRef.track("t") != ItemRef.album("t"))
    }
}
