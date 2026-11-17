// The accounts kept on a device (Server/SavedAccounts.swift): the one
// session of an install from before the list becomes its only entry, read
// again it stays so, and two accounts on one Jellyfin (the test server's
// test and second) are two entries that each keep their own session.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Servers: the saved accounts")
struct SavedAccountsTests {
    static func account(_ server: String, _ user: String, token: String = "t", version: String = "") -> ServerCredentials {
        ServerCredentials(kind: .jellyfin, serverURL: URL(string: "http://\(server).local:8096")!, serverID: server,
                          serverName: server, serverVersion: version, userID: user, userName: user,
                          secret: .jellyfinToken(token))
    }

    let home = Self.account("home", "tijmen")
    let shared = Self.account("shared", "tijmen")

    @Test("An install from before the list: its one session is the list, and is active")
    func migrates() {
        #expect(SavedAccounts.isMigrating(active: home, saved: nil))
        let made = SavedAccounts(active: home, saved: nil)
        #expect(made.all == [home])
        #expect(made.active == home)
        #expect(made.needsSaving)
    }

    @Test("Read again, the migrated list is what was saved: nothing moves twice")
    func migrationIsIdempotent() {
        let first = SavedAccounts(active: home, saved: nil)
        let second = SavedAccounts(active: first.active, saved: first.all)
        #expect(second.all == first.all)
        #expect(second.active == home)
        #expect(!second.needsSaving)
        #expect(!SavedAccounts.isMigrating(active: second.active, saved: second.all))
    }

    @Test("The Jellyfin-only app's session, as it is in the keychain, migrates too")
    func migratesTheOldestSession() throws {
        let old = Credentials(serverURL: URL(string: "http://192.168.1.10:8096")!, serverID: "ab1b921a",
                              serverName: "Tijmen's Music", userID: "f0e1d2c3", userName: "test", accessToken: "0123")
        let read = try JSONDecoder().decode(ServerCredentials.self, from: JSONEncoder().encode(old))
        let made = SavedAccounts(active: read, saved: nil)
        #expect(made.all.count == 1)
        #expect(made.active?.jellyfin == old)
        // And the list as written reads back the same.
        let written = try JSONEncoder().encode(made.all)
        #expect(try JSONDecoder().decode([ServerCredentials].self, from: written) == made.all)
    }

    @Test("The active session is newer than its copy in the list (an older build signed in again)")
    func activeWins() {
        let renewed = Self.account("home", "tijmen", token: "new")
        let made = SavedAccounts(active: renewed, saved: [home, shared])
        #expect(made.all == [renewed, shared])
        #expect(made.active == renewed)
        #expect(made.needsSaving)
    }

    @Test("No active session but a list: the first is active, nobody is signed out")
    func firstWhenNoneActive() {
        let made = SavedAccounts(active: nil, saved: [shared, home])
        #expect(made.active == shared)
        #expect(!made.needsSaving)
        #expect(SavedAccounts(active: nil, saved: nil).active == nil)
    }

    @Test("Signing in again to an account already here keeps its place and is no new one")
    func activateKeepsPlace() {
        var accounts = SavedAccounts(active: home, saved: [home, shared])
        let again = accounts.activate(Self.account("shared", "tijmen", token: "again"))
        #expect(!again)
        #expect(accounts.all.map(\.serverID) == ["home", "shared"])
        #expect(accounts.active?.secret == .jellyfinToken("again"))
        let third = Self.account("home", "anna")
        let added = accounts.activate(third)
        #expect(added)
        #expect(accounts.all.count == 3)
        #expect(accounts.active == third)
    }

    @Test("Signed out of the active one, the next is active; of another, the active stays")
    func remove() {
        var accounts = SavedAccounts(active: home, saved: [home, shared])
        accounts.remove(shared)
        #expect(accounts.all == [home])
        #expect(accounts.active == home)
        accounts.activate(shared)
        accounts.remove(shared)
        #expect(accounts.active == home)
        accounts.remove(home)
        #expect(accounts.all.isEmpty)
        #expect(accounts.active == nil)
    }

    @Test("Two accounts whose folder names would be one: the newer gets its own, the older keeps its")
    func folderNames() throws {
        // Two Subsonic addresses that differ only in punctuation fold to
        // one name ("httpnaslocal4533-anna").
        func subsonic(_ url: String) -> ServerCredentials {
            ServerCredentials(kind: .subsonic(flavour: .navidrome), serverURL: URL(string: url)!, serverID: url,
                              serverName: "", userID: "anna", userName: "anna", secret: .subsonicAPIKey("k"))
        }
        let first = subsonic("http://nas.local:4533"), second = subsonic("http://nas-local:4533")
        #expect(first.folder == second.folder)
        var accounts = SavedAccounts(active: first, saved: nil)
        accounts.activate(second)
        let named = try #require(accounts.all.last)
        #expect(accounts.all[0].folderName == nil)
        #expect(named.folderName != nil && named.folder != accounts.all[0].folder)
        #expect(accounts.active?.folder == named.folder)
        // Stable: signed in again, read back, or after the other is gone.
        accounts.activate(second)
        #expect(accounts.all.last?.folder == named.folder)
        let read = try JSONDecoder().decode([ServerCredentials].self, from: JSONEncoder().encode(accounts.all))
        #expect(SavedAccounts(active: second, saved: read).active?.folder == named.folder)
        accounts.remove(first)
        #expect(accounts.all.first?.folder == named.folder)
        // Every account without a clash keeps the name it always had.
        #expect(home.folderName == nil && home.folder == "home-tijmen")
        #expect(SavedAccounts.stableHash("a") == SavedAccounts.stableHash("a"))
    }

    @Test("What the server said of itself since replaces the account's entry")
    func update() {
        var accounts = SavedAccounts(active: home, saved: [home, shared])
        let newer = Self.account("shared", "tijmen", version: "12.4.0")
        accounts.update(newer)
        #expect(accounts.all[1].serverVersion == "12.4.0")
        #expect(accounts.active == home)
    }

    /// Two users of the test Jellyfin, signed in from one device as the app
    /// does (one DeviceId): two accounts, and neither sign-in ends the
    /// other's session (Jellyfin 12.4 ends only the same user's older token
    /// on that device), so a switch back finds the first still signed in.
    @Test("Two users of one Jellyfin are two accounts, each still signed in")
    func twoUsersOnOneServer() async throws {
        guard let url = JellyfinTestServer.url else { return }
        let identity = JellyfinTestServer.identity("accounts")
        let found = try await MusicServers.detect(url.absoluteString, identity: identity)
        let first = try await MusicServers.signIn(to: found, identity: identity)
            .signIn(username: JellyfinTestServer.user, password: JellyfinTestServer.password)
        let second: ServerCredentials
        do {
            second = try await MusicServers.signIn(to: found, identity: identity).signIn(username: "second", password: "second")
        } catch {
            // A test server from before dev/jellyfin-test-server.sh made the second user.
            print("SKIP: no user \"second\" on the test Jellyfin")
            return
        }
        var accounts = SavedAccounts(active: first, saved: nil)
        let added = accounts.activate(second)
        #expect(added)
        #expect(accounts.all.count == 2)
        #expect(!first.isSameAccount(as: second))
        for account in accounts.all {
            let server = MusicServers.open(account, identity: identity)
            #expect(try await server.downloadsAllowed())
            #expect(try await server.allAlbums().count > 0)
        }
        // Signing out of one ends its session alone: the other plays on.
        await MusicServers.open(second, identity: identity).signOut()
        #expect(try await MusicServers.open(first, identity: identity).downloadsAllowed())
        await MusicServers.open(first, identity: identity).signOut()
    }
}
