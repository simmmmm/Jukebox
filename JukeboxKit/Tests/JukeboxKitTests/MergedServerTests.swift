// Several accounts as one server (Server/MergedServer.swift, AccountTag,
// Retag; docs/MULTI-SERVER.md, "Step 1"), against the Jellyfin and the
// Navidrome of dev/jellyfin-test-server.sh and dev/navidrome-test-server.sh,
// which hold the same made-up library: 358 songs and 54 albums each. The
// tags and the round trip of every model need no server.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Servers: account tags and retagging")
struct AccountTagTests {
    static let tag = AccountTag(SavedAccountsTests.account("home", "tijmen"))
    static let other = AccountTag(SavedAccountsTests.account("shared", "tijmen"))

    @Test("A tag is 8 hex digits of the server's id and the user's; split and unwrap give the id back")
    func tags() throws {
        let tag = Self.tag
        #expect(tag.value.count == 8 && tag.value.allSatisfy(\.isHexDigit))
        #expect(tag != Self.other)
        #expect(AccountTag(SavedAccountsTests.account("home", "second")) != tag)
        // The address is not in it: the same server and user at another
        // address is the same account.
        var away = SavedAccountsTests.account("home", "tijmen")
        away.serverURL = URL(string: "https://music.example.com")!
        #expect(AccountTag(away) == tag)

        // A Subsonic id may hold colons, or look tagged itself.
        for id in ["378", "a:b:c", "deadbeef:1", "al-1#2"] {
            let wrapped = tag.wrap(id)
            let split = try #require(AccountTag.split(wrapped))
            #expect(split.tag == tag && split.bare == id)
            #expect(tag.unwrap(wrapped) == id && Self.other.unwrap(wrapped) == nil)
        }
        #expect(AccountTag.split("378") == nil)
        #expect(AccountTag.split("DEADBEEF:378") == nil)
        #expect(AccountTag.split("deadbeef:") == nil)
        #expect(tag.unwrap("378") == nil)
    }

    /// Every field set, so a field the walk forgets shows.
    static func track(_ id: String) -> Track {
        var track = Track(
            id: id, name: "Song \(id)", albumID: "al\(id)", albumName: "Album", artists: [ArtistRef(id: "ar1", name: "One"), ArtistRef(id: nil, name: "Guest")],
            albumArtist: ArtistRef(id: "ar1", name: "One"), genres: ["Folk"], year: 1999, trackNumber: 2, discNumber: 1,
            duration: 200, imageTag: "img", albumImageTag: "alimg", isFavorite: true, playCount: 3,
            lastPlayed: Date(timeIntervalSince1970: 1_000), dateAdded: Date(timeIntervalSince1970: 500),
            normalizationGain: -6, playlistEntryID: "\(id)#0", container: "flac",
            credits: [Credit(role: .composer, artist: ArtistRef(id: "ar9", name: "Bach"), instrument: "Organ")],
            work: "Work", movement: Movement(name: "I", number: 1, count: 3), grouping: "G", discTitle: "Disc",
            rating: 4, albumNormalizationGain: -5, moods: ["calm"], bpm: 90)
        track.fileKey = "/library/parts/1/file.flac"
        return track
    }

    static func stations() -> [Station] {
        let seeds: [StationSeed] = [
            .track("t1"), .artist(key: "one", name: "One", id: "ar1"), .artist(key: "two", name: "Two", id: nil),
            .album("al1"), .genre(key: "folk", name: "Folk"), .decade(1990),
            .collection(id: "pl1", name: "List", trackIDs: ["t1", "t2"]), .personal, .discovery, .favorites,
        ]
        return seeds.map { Station(id: Station.id(for: $0), seed: $0, title: "S", subtitle: "s", artwork: [Artwork(itemID: "al1", tag: "x")]) }
    }

    @Test("Tagged and stripped again, every model is itself; every id inside is tagged, and nothing else")
    func roundTrip() throws {
        let tag = Self.tag
        let strip = { (id: ItemID) in tag.unwrap(id) ?? id }
        let track = Self.track("t1")
        var album = Album(id: "al1", name: "Album", artists: [ArtistRef(id: "ar1", name: "One")], year: 1999,
                          genres: ["Folk"], imageTag: "img", trackCount: 2, duration: 400, isFavorite: true,
                          dateAdded: Date(timeIntervalSince1970: 500), playCount: 2,
                          lastPlayed: Date(timeIntervalSince1970: 1_000), rating: 3, normalizationGain: -4)
        album.mergedIDs = ["al2", "al3"]
        let artist = Artist(id: "ar1", name: "One", imageTag: "img", genres: ["Folk"], isFavorite: true,
                            albumCount: 1, songCount: 2, overview: "About")
        let playlist = Playlist(id: "pl1", name: "List", imageTag: "img", trackCount: 2, duration: 400,
                                dateAdded: Date(timeIntervalSince1970: 1), isReadOnly: true)
        let genre = Genre(id: "Folk", name: "Folk", imageTag: "img", songCount: 2, albumCount: 1)
        let report = PlaybackReport(trackID: "t1", position: 12, isPaused: true, playSessionID: "s", volume: 0.5)
        let state = PlayState(deviceID: "d", deviceName: "PC", updatedAt: Date(timeIntervalSince1970: 9), isPlaying: true,
                              queue: ["t1", "t2", "t3"], index: 1, position: 30, title: "T",
                              station: Self.stations()[0], takenFrom: "other", takenAt: Date(timeIntervalSince1970: 8))
        let found = SearchResults(artists: [artist], albums: [album], tracks: [track], playlists: [playlist])

        #expect(track.retagged(tag.wrap).retagged(strip) == track)
        #expect(album.retagged(tag.wrap).retagged(strip) == album)
        #expect(artist.retagged(tag.wrap).retagged(strip) == artist)
        #expect(playlist.retagged(tag.wrap).retagged(strip) == playlist)
        #expect(genre.retagged(tag.wrap).retagged(strip) == genre)
        #expect(report.retagged(tag.wrap).retagged(strip) == report)
        #expect(state.retagged(tag.wrap).retagged(strip) == state)
        for station in Self.stations() { #expect(station.retagged(tag.wrap).retagged(strip) == station) }
        let back = found.retagged(tag.wrap).retagged(strip)
        #expect(back.artists == found.artists && back.albums == found.albums
                && back.tracks == found.tracks && back.playlists == found.playlists)

        let tagged = track.retagged(tag.wrap)
        let ids = [tagged.id, tagged.albumID] + tagged.artists.map(\.id) + [tagged.albumArtist?.id]
            + (tagged.credits ?? []).map(\.artist.id)
        #expect(ids.compactMap { $0 }.allSatisfy { tag.unwrap($0) != nil })
        #expect(tagged.artists[1].id == nil)
        #expect(tagged.playlistEntryID == "t1#0" && tagged.imageTag == "img" && tagged.fileKey == track.fileKey)
        #expect(tagged.artwork?.itemID == tag.wrap("t1") && tagged.artwork?.tag == "img")
        #expect(album.retagged(tag.wrap).mergedIDs == ["al2", "al3"].map(tag.wrap))

        let station = Self.stations()[0].retagged(tag.wrap)
        #expect(station.seed == .track(tag.wrap("t1")) && station.id == Station.id(for: station.seed))
        #expect(station.artwork.map(\.itemID) == [tag.wrap("al1")])
        let collection = Self.stations()[6].retagged(tag.wrap)
        #expect(collection.seed == .collection(id: "pl1", name: "List", trackIDs: ["t1", "t2"].map(tag.wrap)))
        #expect(state.retagged(tag.wrap).takenFrom == "other")
    }
}

/// A server that does not answer: Navidrome, stopped, as far as a client
/// can tell. The shared test servers are never stopped.
private struct SilentTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        throw MusicServerError.transport("Could not connect to the server.")
    }
}

enum MergedTestServer {
    static let merged = Task<MergedServer, any Error> {
        MergedServer(members: [try await TestServers.jellyfin.value, try await TestServers.navidrome.value])
    }

    /// The whole library through the merged server, asked once.
    static let library = Task<(tracks: [Track], albums: [Album], progress: [(Int, Int)]), any Error> {
        let server = try await merged.value
        let progress = SubsonicProgressRecorder()
        let tracks = try await server.allTracks { progress.add($0, $1) }
        return (tracks, try await server.allAlbums(), progress.values)
    }

    static func key(_ t: Track) -> String {
        "\(t.albumArtist?.name ?? "")|\(t.albumName ?? "")|\(t.discNumber ?? 1)|\(t.trackNumber ?? 0)|\(t.name)"
    }
}

@Suite("Servers: Jellyfin and Navidrome as one", .serialized, .timeLimit(.minutes(3)), .enabled(if: TestServers.both))
struct MergedServerTests {
    @Test("716 songs and 108 albums, every id tagged with its account, no two alike")
    func library() async throws {
        let server = try await MergedTestServer.merged.value
        let (tracks, albums, progress) = try await MergedTestServer.library.value
        #expect(tracks.count == 716 && Set(tracks.map(\.id)).count == 716)
        #expect(albums.count == 108 && Set(albums.map(\.id)).count == 108)
        #expect(progress.last.map { $0 == (716, 716) } == true)
        #expect(progress.allSatisfy { $0.0 <= $0.1 })

        let tags = server.members.map { AccountTag($0.credentials) }
        for tag in tags {
            #expect(tracks.filter { tag.unwrap($0.id) != nil }.count == 358)
            #expect(albums.filter { tag.unwrap($0.id) != nil }.count == 54)
        }
        // A song's album and artists are of its own account.
        for track in tracks {
            let tag = try #require(AccountTag.split(track.id)?.tag)
            let inside = [track.albumID, track.albumArtist?.id] + track.artists.map(\.id)
            #expect(inside.compactMap { $0 }.allSatisfy { tag.unwrap($0) != nil }, "\(track.id)")
        }
        #expect(Set(tracks.compactMap(\.albumID)) == Set(albums.map(\.id)))
        let artists = try await server.allArtists()
        #expect(artists.count == 46 && Set(artists.map(\.id)).count == 46)
        #expect(server.capabilities == server.members[0].capabilities.union(server.members[1].capabilities))
    }

    @Test("Every song asked back by its id is the same song, from its own server")
    func everySong() async throws {
        let server = try await MergedTestServer.merged.value
        let tracks = try await MergedTestServer.library.value.tracks
        // Sixteen at a time.
        let wrong = try await withThrowingTaskGroup(of: String?.self) { group in
            var wrong: [String] = []
            for (n, track) in tracks.enumerated() {
                if n >= 16, let w = try await group.next() ?? nil { wrong.append(w) }
                group.addTask {
                    let again = try await server.track(id: track.id)
                    let tag = AccountTag.split(track.id)?.tag
                    let own = server.member(for: track.id).map { AccountTag($0.credentials) }
                    let same = again.id == track.id && again.name == track.name && again.albumID == track.albumID
                        && abs(again.duration - track.duration) < 0.01 && own == tag
                    return same ? nil : track.id
                }
            }
            for try await w in group { if let w { wrong.append(w) } }
            return wrong
        }
        #expect(wrong.isEmpty, "\(wrong.prefix(5))")
        await #expect(throws: MusicServerError.notFound) { _ = try await server.track(id: "378") }
        await #expect(throws: MusicServerError.notFound) { _ = try await server.track(id: "00000000:378") }
    }

    @Test("A stream, a cover and a download point at the song's own server with its own id")
    func urls() async throws {
        let server = try await MergedTestServer.merged.value
        let tracks = try await MergedTestServer.library.value.tracks
        for member in server.members {
            let tag = AccountTag(member.credentials)
            let track = try #require(tracks.first { tag.unwrap($0.id) != nil })
            let bare = track.retagged { tag.unwrap($0) ?? $0 }
            let stream = server.streamURL(for: track, quality: .high, playSessionID: "kit")
            #expect(stream == member.streamURL(for: bare, quality: .high, playSessionID: "kit"))
            #expect(stream.host == member.credentials.serverURL.host && stream.port == member.credentials.serverURL.port)
            #expect(!stream.absoluteString.contains(tag.value) && stream.absoluteString.contains(bare.id))
            #expect(server.downloadURL(for: track, quality: .original) == member.downloadURL(for: bare, quality: .original))
            #expect(server.castURL(for: track) == member.castURL(for: bare))
            let artwork = try #require(track.artwork)
            #expect(server.artworkURL(artwork, maxPixelSize: 300)
                    == member.artworkURL(try #require(bare.artwork), maxPixelSize: 300))
            let file = try await NavidromeTestServer.fetch(server.downloadURL(for: track, quality: .original))
            #expect(file.status == 200 && file.body.count > 1000, "\(member.kind)")
        }
    }

    @Test("A favourite set through the merged server shows on that server only")
    func favourite() async throws {
        let server = try await MergedTestServer.merged.value
        let tracks = try await MergedTestServer.library.value.tracks
        let (jellyfin, navidrome) = (server.members[0], server.members[1])
        let jTag = AccountTag(jellyfin.credentials)
        let byKey = Dictionary(tracks.filter { jTag.unwrap($0.id) == nil }.map { (MergedTestServer.key($0), $0) },
                               uniquingKeysWith: { a, _ in a })
        let track = try #require(tracks.filter { jTag.unwrap($0.id) != nil && !$0.isFavorite }.randomElement())
        let twin = try #require(byKey[MergedTestServer.key(track)])
        let twinBefore = try await navidrome.track(id: try #require(AccountTag.split(twin.id)?.bare)).isFavorite

        try await server.setFavorite(true, item: .track(track.id))
        do {
            #expect(try await server.track(id: track.id).isFavorite)
            #expect(try await jellyfin.track(id: try #require(jTag.unwrap(track.id))).isFavorite)
            #expect(try await server.track(id: twin.id).isFavorite == twinBefore)
        } catch {
            try? await server.setFavorite(false, item: .track(track.id))
            throw error
        }
        try await server.setFavorite(false, item: .track(track.id))
        #expect(try await !server.track(id: track.id).isFavorite)
    }

    @Test("A playlist of one server's songs lands there; of two servers' it throws")
    func playlists() async throws {
        let server = try await MergedTestServer.merged.value
        let tracks = try await MergedTestServer.library.value.tracks
        for (index, member) in server.members.enumerated() {
            let tag = AccountTag(member.credentials)
            let own = Array(tracks.filter { tag.unwrap($0.id) != nil }.shuffled().prefix(2))
            let name = "Jukebox merged \(UUID().uuidString.prefix(8))"
            let id = try await server.createPlaylist(name: name, trackIDs: own.map(\.id))
            do {
                #expect(tag.unwrap(id) != nil && server.member(for: id).map { AccountTag($0.credentials) } == tag)
                #expect(try await member.playlists().contains { $0.id == tag.unwrap(id) && $0.name == name })
                let other = server.members[1 - index]
                #expect(try await !other.playlists().contains { $0.name == name })
                #expect(try await server.playlistTracks(playlistID: id).map(\.id) == own.map(\.id))
                #expect(try await server.playlists().contains { $0.id == id })
            } catch {
                try? await server.deletePlaylist(id: id)
                throw error
            }
            try await server.deletePlaylist(id: id)
        }
        let mixed = server.members.map { member in
            tracks.first { AccountTag(member.credentials).unwrap($0.id) != nil }!.id
        }
        await #expect(throws: MusicServerError.unsupported(nil)) {
            _ = try await server.createPlaylist(name: "Jukebox merged: never made", trackIDs: mixed)
        }
    }

    @Test("With Navidrome not answering, the Jellyfin half still loads; with neither, it throws")
    func silentMember() async throws {
        let jellyfin = try await TestServers.jellyfin.value
        let navidrome = try await TestServers.navidrome.value
        let silent = MusicServers.open(navidrome.credentials, identity: NavidromeTestServer.identity,
                                       transport: SilentTransport())
        let server = MergedServer(members: [jellyfin, silent])
        let tracks = try await server.allTracks(progress: nil)
        #expect(tracks.count == 358)
        #expect(tracks.allSatisfy { AccountTag(jellyfin.credentials).unwrap($0.id) != nil })
        #expect(try await server.allAlbums().count == 54)
        let silentJellyfin = MusicServers.open(jellyfin.credentials, identity: TestServers.jellyfinIdentity,
                                               transport: SilentTransport())
        await #expect(throws: MusicServerError.self) {
            _ = try await MergedServer(members: [silentJellyfin, silent]).allTracks(progress: nil)
        }
    }

    @Test("One member: every answer is the plain server's with the tag added")
    func oneMember() async throws {
        for plain in [try await TestServers.jellyfin.value, try await TestServers.navidrome.value] {
            let server = MergedServer(members: [plain])
            let tag = AccountTag(plain.credentials)
            #expect(server.kind == plain.kind && server.credentials == plain.credentials
                    && server.capabilities == plain.capabilities)
            let byID = { (list: [Track]) in list.sorted { $0.id < $1.id } }
            let plainTracks = try await plain.allTracks(progress: nil)
            #expect(byID(try await server.allTracks(progress: nil)) == byID(plainTracks.map { $0.retagged(tag.wrap) }))
            #expect(Set(try await server.allAlbums()) == Set(try await plain.allAlbums().map { $0.retagged(tag.wrap) }))
            #expect(Set(try await server.allArtists()) == Set(try await plain.allArtists().map { $0.retagged(tag.wrap) }))
            #expect(Set(try await server.genres()) == Set(try await plain.genres().map { $0.retagged(tag.wrap) }))
            #expect(Set(try await server.playlists()) == Set(try await plain.playlists().map { $0.retagged(tag.wrap) }))
            let track = try #require(plainTracks.first)
            #expect(try await server.track(id: tag.wrap(track.id)) == (try await plain.track(id: track.id)).retagged(tag.wrap))
            let albumID = try #require(track.albumID)
            #expect(try await server.albumTracks(albumID: tag.wrap(albumID))
                    == (try await plain.albumTracks(albumID: albumID)).map { $0.retagged(tag.wrap) })
            let found = try await server.search(track.name, limit: 5)
            let plainFound = try await plain.search(track.name, limit: 5)
            #expect(found.tracks == plainFound.tracks.map { $0.retagged(tag.wrap) })
            #expect(found.albums == plainFound.albums.map { $0.retagged(tag.wrap) })
            #expect(found.artists == plainFound.artists.map { $0.retagged(tag.wrap) })
        }
    }
}
