// Sharing's words and links (Apple's search answers written here; the real
// one is not asked), and a playlist's own cover on the test Jellyfin: set by
// test, an administrator; refused to second, who is not.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

private final class SearchTransport: HTTPTransport, @unchecked Sendable {
    let body: String
    let status: Int
    var asked: [URLRequest] = []
    init(_ body: String, status: Int = 200) {
        self.body = body
        self.status = status
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        asked.append(request)
        return HTTPResponse(status: status, body: Data(body.utf8))
    }
}

@Suite("Sharing")
struct SharingTests {
    let track = Track(id: "t", name: "Night Bus (Remastered)", artists: [ArtistRef(id: "a", name: "Blue Room Trio")],
                      duration: 200)

    @Test("A song's words and its song.link, only for the same title by the same artist")
    func song() async throws {
        let answer = """
        {"resultCount":2,"results":[
          {"trackId":1,"collectionId":10,"artistName":"Someone Else","trackName":"Night Bus"},
          {"trackId":2,"collectionId":20,"artistName":"Blue Room Trio","trackName":"Night Bus"}]}
        """
        let transport = SearchTransport(answer)
        let shared = await Sharing(transport: transport).text(for: .track(track))
        #expect(shared.words == "Night Bus (Remastered) by Blue Room Trio")
        #expect(shared.url?.absoluteString == "https://song.link/i/2")
        #expect(shared.text == "Night Bus (Remastered) by Blue Room Trio\nhttps://song.link/i/2")
        let asked = try #require(transport.asked.first?.url?.absoluteString)
        #expect(asked.hasPrefix("https://itunes.apple.com/search?term=Blue%20Room%20Trio%20Night%20Bus"))
        #expect(asked.contains("entity=song"))
    }

    @Test("Nothing alike, or no answer: the words alone")
    func wordsAlone() async {
        let other = SearchTransport(#"{"results":[{"trackId":1,"artistName":"Blue Room Trio","trackName":"Day Tram"}]}"#)
        #expect(await Sharing(transport: other).text(for: .track(track)).url == nil)
        let down = SearchTransport("", status: 503)
        let shared = await Sharing(transport: down).text(for: .track(track))
        #expect(shared.text == "Night Bus (Remastered) by Blue Room Trio")
    }

    @Test("An album's album.link, an artist's Apple Music page")
    func albumAndArtist() async {
        let album = Album(id: "al", name: "Harbour Lights", artists: [ArtistRef(id: "a", name: "Blue Room Trio")])
        let albums = SearchTransport(#"{"results":[{"collectionId":7,"artistName":"Blue Room Trio","collectionName":"Harbour Lights"}]}"#)
        #expect(await Sharing(transport: albums).text(for: .album(album)).text
            == "Harbour Lights by Blue Room Trio\nhttps://album.link/i/7")
        let artist = Artist(id: "a", name: "Blue Room Trio")
        let artists = SearchTransport(#"{"results":[{"artistName":"Blue Room Trio","artistLinkUrl":"https://music.apple.com/us/artist/x/9"}]}"#)
        #expect(await Sharing(transport: artists).text(for: .artist(artist)).text
            == "Blue Room Trio\nhttps://music.apple.com/us/artist/x/9")
    }
}

@Suite("Playlist covers: the real server", .serialized, .timeLimit(.minutes(1)), .enabled(if: JellyfinTestServer.url != nil))
struct PlaylistCoverIntegrationTests {
    func server(_ user: String) async throws -> JellyfinServer {
        let url = try #require(JellyfinTestServer.url)
        let identity = JellyfinTestServer.identity("covers-\(user)")
        let credentials = try await JellyfinClient(serverURL: url, identity: identity)
            .signIn(username: user, password: user)
        return JellyfinServer(client: JellyfinClient(credentials: credentials, identity: identity),
                              credentials: ServerCredentials(jellyfin: credentials))
    }

    /// One orange pixel, as a JPEG.
    static let jpeg = Data(base64Encoded:
        "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=")!

    @Test("An administrator sets a playlist's cover; another user may not")
    func cover() async throws {
        let admin = try await server("test")
        #expect(try await admin.playlistCoversAllowed())
        let id = try await admin.createPlaylist(name: "Kit tests: cover", trackIDs: [])
        // The playlist goes again whatever the upload did.
        var failure: (any Error)?
        do { try await admin.setPlaylistCover(playlistID: id, jpeg: Self.jpeg) } catch { failure = error }
        let playlist = try? await admin.playlists().first { $0.id == id }
        try await admin.deletePlaylist(id: id)
        if let failure { throw failure }
        #expect(playlist?.imageTag != nil)

        let other = try await server("second")
        #expect(try await other.playlistCoversAllowed() == false)
    }
}
