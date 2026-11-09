// JellyfinServer, the wrapper that makes JellyfinClient a MusicServer:
// what it passes through as it is, and the one thing it adds — a place of
// its own for each entry of a song that is in a playlist twice, which
// Jellyfin 12.4 cannot tell apart. The fake keeps a playlist as 12.4 was
// measured to (curl, 9 November 2026): an entry's PlaylistItemId is the
// song's id; DELETE …/Items?entryIds= removes every place of that id;
// POST …/Items?ids=&position= inserts there; Move moves the first place.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

/// One playlist, "pl", as Jellyfin 12.4 keeps it.
final class JellyfinPlaylistFake: @unchecked Sendable {
    private let lock = NSLock()
    private var songs: [String]
    private(set) var calls: [String] = []
    /// The n-th change (from 1) fails on the way.
    var failing: Int?
    private var changes = 0

    init(_ songs: [String]) { self.songs = songs }

    var list: [String] { lock.withLock { songs } }

    lazy var transport = JellyfinMockTransport { [self] request in try self.answer(request) }

    func answer(_ request: URLRequest) throws -> HTTPResponse {
        let url = request.url!
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        let path = url.path.replacingOccurrences(of: "/jellyfin", with: "")
        let method = request.httpMethod ?? "GET"
        return try lock.withLock {
            if method != "GET" {
                calls.append("\(method) \(path)" + (query["position"].map { " at \($0)" } ?? ""))
                changes += 1
                if changes == failing { throw URLError(.networkConnectionLost) }
            }
            switch (method, path) {
            case ("GET", "/Playlists/pl/Items"):
                let items = songs.map { #"{"Id":"\#($0)","Name":"Song \#($0)","Type":"Audio","PlaylistItemId":"\#($0)"}"# }
                return HTTPResponse(status: 200, body: Data(#"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(songs.count)}"#.utf8))
            case ("DELETE", "/Playlists/pl/Items"):
                let gone = Set((query["entryIds"] ?? "").split(separator: ",").map(String.init))
                songs.removeAll { gone.contains($0) }
            case ("POST", "/Playlists/pl/Items"):
                let ids = (query["ids"] ?? "").split(separator: ",").map(String.init)
                if let position = query["position"].flatMap(Int.init) {
                    songs.insert(contentsOf: ids, at: min(position, songs.count))
                } else {
                    songs += ids
                }
            case let ("POST", move) where move.hasPrefix("/Playlists/pl/Items/"):
                let parts = move.split(separator: "/")
                let entry = String(parts[3]), index = Int(parts[5]) ?? 0
                if let from = songs.firstIndex(of: entry) {
                    let song = songs.remove(at: from)
                    songs.insert(song, at: min(index, songs.count))
                }
            default:
                return HTTPResponse(status: 404, body: Data())
            }
            return HTTPResponse(status: 204, body: Data())
        }
    }

    var server: JellyfinServer {
        JellyfinServer(client: JellyfinFixtures.client(transport),
                       credentials: ServerCredentials(jellyfin: Credentials(
                        serverURL: JellyfinFixtures.server, serverID: "s", serverName: "Jellyfin",
                        userID: JellyfinFixtures.userID, userName: "test", accessToken: JellyfinFixtures.token)))
    }
}

@Suite("Jellyfin: as a MusicServer")
struct JellyfinServerTests {
    @Test("A playlist without repeats keeps Jellyfin's entry ids and Jellyfin's own calls")
    func ownCalls() async throws {
        let fake = JellyfinPlaylistFake(["A", "B", "C", "D"])
        let server = fake.server
        let entries = try await server.playlistTracks(playlistID: "pl")
        #expect(entries.map(\.playlistEntryID) == ["A", "B", "C", "D"])
        try await server.movePlaylistEntry(playlistID: "pl", entryID: "A", to: 2)
        #expect(fake.list == ["B", "C", "A", "D"])
        try await server.removeFromPlaylist(playlistID: "pl", entryIDs: ["C"])
        #expect(fake.list == ["B", "A", "D"])
        #expect(fake.calls == ["POST /Playlists/pl/Items/A/Move/2", "DELETE /Playlists/pl/Items"])
    }

    @Test("A song twice: a place of its own for each entry; removing one keeps the other where it was")
    func repeatsRemoved() async throws {
        let fake = JellyfinPlaylistFake(["A", "B", "A", "C", "A"])
        let server = fake.server
        let entries = try await server.playlistTracks(playlistID: "pl")
        #expect(entries.map(\.id) == ["A", "B", "A", "C", "A"])
        #expect(entries.map(\.playlistEntryID) == ["A#0", "B#0", "A#1", "C#0", "A#2"])

        try await server.removeFromPlaylist(playlistID: "pl", entryIDs: ["A#1"])
        #expect(fake.list == ["A", "B", "C", "A"])
        #expect(fake.calls == ["DELETE /Playlists/pl/Items", "POST /Playlists/pl/Items at 0", "POST /Playlists/pl/Items at 3"])

        try await server.removeFromPlaylist(playlistID: "pl", entryIDs: ["B#0", "A#0"])
        #expect(fake.list == ["C", "A"])
    }

    @Test("A song twice: moving one place, by Jellyfin's rule for where it ends up", arguments: 0..<6, 0..<6)
    func repeatsMoved(from: Int, to: Int) async throws {
        let songs = ["A", "B", "A", "C", "A", "D"]
        let fake = JellyfinPlaylistFake(songs)
        let server = fake.server
        let entry = try #require(try await server.playlistTracks(playlistID: "pl")[from].playlistEntryID)
        try await server.movePlaylistEntry(playlistID: "pl", entryID: entry, to: to)
        var expected = songs
        expected.insert(expected.remove(at: from), at: to)
        #expect(fake.list == expected)
    }

    @Test("A lost request leaves out only the moved song's places; an entry gone is .notFound")
    func repeatsLost() async throws {
        let fake = JellyfinPlaylistFake(["A", "B", "A", "C", "A"])
        fake.failing = 2
        let server = fake.server
        await #expect(throws: (any Error).self) {
            try await server.movePlaylistEntry(playlistID: "pl", entryID: "A#2", to: 1)
        }
        #expect(fake.list.filter { $0 != "A" } == ["B", "C"])
        await #expect(throws: MusicServerError.notFound) {
            try await JellyfinPlaylistFake(["A", "A"]).server.movePlaylistEntry(playlistID: "pl", entryID: "Z#0", to: 0)
        }
    }

    @Test("Entry ids made here are told from Jellyfin's own")
    func places() {
        #expect(JellyfinServer.isPlace("2c4a765f5c8d9b4907be5d835a82513c#1"))
        #expect(!JellyfinServer.isPlace("2c4a765f5c8d9b4907be5d835a82513c"))
        #expect(!JellyfinServer.isPlace("a#"))
        #expect(!JellyfinServer.isPlace("a#x"))
        #expect(!JellyfinServer.isPlace("a#²"))
    }
}
