// What Subsonic sends, made into the kit's own models (SubsonicDTO.swift),
// and the library calls built on it: every song in pages or album by album,
// albums and artists, an album's order, search, and a playlist's entries
// through every change. The answers are Navidrome 0.64.2's (SubsonicFixtures)
// and the shapes other Subsonic servers send (numbers for ids, a single
// object for a list of one, no OpenSubsonic fields).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Subsonic: answers into the library")
struct SubsonicMappingTests {
    typealias F = SubsonicFixtures

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: Models

    @Test("A Navidrome song: performers split, the album artist, genres, play count, dates, the disc's cover, the suffix")
    func navidromeSong() throws {
        let track = try #require(try Self.decode(SubsonicChild.self, F.blueParadeIronGardens).asTrack())
        #expect(track.id == "7ljPKGNMSwb9xQJ9R6sgwi")
        #expect(track.name == "Blue Parade")
        #expect(track.albumID == "0XtEsASSFBpRROqxktaHgP" && track.albumName == "Iron Gardens")
        #expect(track.artists == [ArtistRef(id: "3hzlW4nytpm0ULiXdnIWFQ", name: "MC Polder"),
                                  ArtistRef(id: "0uE2mIyabW57P8LI7VBB3J", name: "Lyric Engine")])
        #expect(track.albumArtist == ArtistRef(id: "3hzlW4nytpm0ULiXdnIWFQ", name: "MC Polder"))
        #expect(track.primaryArtist?.name == "MC Polder")
        #expect(track.artistLine == "MC Polder, Lyric Engine")
        #expect(track.genres == ["Hip-Hop", "Nederhop"])
        #expect(track.year == 2016 && track.trackNumber == 1 && track.discNumber == 1)
        #expect(track.duration == 6)
        #expect(track.imageTag == "dc-0XtEsASSFBpRROqxktaHgP:1" && track.albumImageTag == nil)
        #expect(track.artwork == Artwork(itemID: track.id, tag: "dc-0XtEsASSFBpRROqxktaHgP:1"))
        #expect(track.isFavorite)
        #expect(track.playCount == 1)
        #expect(track.lastPlayed == Self.date("2026-11-09T17:54:32Z"))
        let added = try #require(track.dateAdded)
        #expect(abs(added.timeIntervalSince(try #require(Self.date("2026-11-09T17:49:48.147Z")))) < 0.001)
        #expect(track.normalizationGain == nil)
        #expect(track.playlistEntryID == nil)
        #expect(track.container == "m4a")

        let other = try #require(try Self.decode(SubsonicChild.self, F.blueParadeSignalLines).asTrack())
        #expect(other.artists.map(\.name) == ["Amsterdam Strings", "Clara Venn"])
        #expect(!other.isFavorite && other.playCount == 0 && other.lastPlayed == nil)
        #expect(other.container == "flac")
    }

    @Test("A song from a server without OpenSubsonic, and the shapes others send")
    func otherSongs() throws {
        let classic = try #require(try Self.decode(SubsonicChild.self, #"""
            {"id":"5","title":"Old","artist":"Someone","artistId":"9","album":"Then","albumId":"12","genre":"Jazz",
             "duration":"5","track":"3","discNumber":0,"year":0,"coverArt":"","starred":"","suffix":"MP3"}
            """#).asTrack())
        #expect(classic.artists == [ArtistRef(id: "9", name: "Someone")])
        #expect(classic.albumArtist == nil)
        #expect(classic.genres == ["Jazz"])
        #expect(classic.duration == 5 && classic.trackNumber == 3)
        #expect(classic.year == nil && classic.discNumber == nil)
        #expect(classic.imageTag == nil && !classic.isFavorite)
        #expect(classic.container == "mp3")

        // Ampache and older Airsonic: numbers for ids, a fraction for a length.
        let numbers = try #require(try Self.decode(SubsonicChild.self,
            #"{"id":123,"title":"x","albumId":45,"duration":5.6,"isDir":"false","replayGain":{"trackGain":-7.5,"albumGain":-6.1}}"#).asTrack())
        #expect(numbers.id == "123" && numbers.albumID == "45" && numbers.duration == 5.6)
        #expect(numbers.normalizationGain == -7.5)
        let albumGain = try Self.decode(SubsonicChild.self, #"{"id":"1","title":"x","replayGain":{"albumGain":-6.1}}"#).asTrack()
        #expect(albumGain?.normalizationGain == -6.1)
        let odd = try #require(try Self.decode(SubsonicChild.self, #"{"id":"1","title":["not text"],"year":"nineteen","starred":true}"#).asTrack())
        #expect(odd.name == "" && odd.year == nil)

        // Not songs: a folder, a video, no id.
        for json in [#"{"id":"d","isDir":true,"title":"Folder"}"#, #"{"id":"v","type":"video","title":"Clip"}"#,
                     #"{"title":"No id"}"#, #"{"id":"","title":"Empty id"}"#] {
            #expect(try Self.decode(SubsonicChild.self, json).asTrack() == nil, "\(json)")
        }
    }

    @Test("Lists: missing, {}, one object where an array belongs, an element that is not an object")
    func lenientLists() throws {
        func songs(_ inner: String) throws -> [String] {
            let body = try SubsonicConnection.decode(Data(F.ok(inner).utf8))
            return (body.searchResult3?.song ?? []).compactMap { $0.asTrack()?.id }
        }
        #expect(try songs("").isEmpty)
        #expect(try songs(#""searchResult3":{}"#).isEmpty)
        #expect(try songs(#""searchResult3":{"song":\#(F.song("one"))}"#) == ["one"])
        #expect(try songs(#""searchResult3":{"song":[1,\#(F.song("a")),"x",null,\#(F.song("b"))]}"#) == ["a", "b"])
        #expect(try songs(#""searchResult3":{"song":7}"#).isEmpty)
        // A part of the wrong shape costs that part, not the answer.
        let body = try SubsonicConnection.decode(Data(F.ok(#""searchResult3":"nonsense","genres":{"genre":[{"value":"Jazz"}]}"#).utf8))
        #expect(body.isOK && body.searchResult3 == nil)
        #expect(body.genres?.genre.count == 1)
    }

    @Test("An album, an artist, a playlist and a genre as Navidrome sends them")
    func otherModels() throws {
        let album = try #require(try Self.decode(SubsonicAlbum.self, F.ironGardens).asAlbum())
        #expect(album.id == "0XtEsASSFBpRROqxktaHgP" && album.name == "Iron Gardens")
        #expect(album.artists == [ArtistRef(id: "3hzlW4nytpm0ULiXdnIWFQ", name: "MC Polder")])
        #expect(album.year == 2016 && album.genres == ["Hip-Hop", "Nederhop"])
        #expect(album.imageTag == "al-0XtEsASSFBpRROqxktaHgP_2d7f387fbb87b3d2")
        #expect(album.artwork == Artwork(itemID: album.id, tag: album.imageTag))
        #expect(album.trackCount == 8 && album.duration == 53)
        #expect(!album.isFavorite && album.playCount == 1)
        #expect(album.lastPlayed == Self.date("2026-11-09T17:54:32Z"))
        #expect(album.dateAdded != nil)
        // getAlbumList (not ID3) calls the name `title`.
        #expect(try Self.decode(SubsonicAlbum.self, #"{"id":"1","title":"Old Style","artist":"A"}"#).asAlbum()?.name == "Old Style")

        let playlist = try #require(try Self.decode(SubsonicPlaylist.self, "{" + F.playlistHead + "}").asPlaylist(user: "test"))
        #expect(playlist.id == "49jbXaAzpdP4nsvwSAwyor" && playlist.name == "Fixture")
        #expect(playlist.imageTag == "pl-49jbXaAzpdP4nsvwSAwyor" && playlist.trackCount == 3 && playlist.duration == 18)
        #expect(!playlist.isReadOnly && playlist.dateAdded != nil)
        // Without `readonly`: someone else's is read-only, one's own (any case) is not.
        #expect(try Self.decode(SubsonicPlaylist.self, #"{"id":"p","name":"T","owner":"someone"}"#).asPlaylist(user: "test")?.isReadOnly == true)
        #expect(try Self.decode(SubsonicPlaylist.self, #"{"id":"p","name":"T","owner":"Test"}"#).asPlaylist(user: "test")?.isReadOnly == false)
        #expect(try Self.decode(SubsonicPlaylist.self, #"{"id":"p","name":"T","owner":"test","readonly":true}"#).asPlaylist(user: "test")?.isReadOnly == true)

        let genre = try #require(try Self.decode(SubsonicGenre.self, #"{"value":"Electronic","songCount":74,"albumCount":11}"#).asGenre())
        #expect(genre == Genre(id: "Electronic", name: "Electronic", songCount: 74, albumCount: 11))
        #expect(try Self.decode(SubsonicGenre.self, #"{"value":"  "}"#).asGenre() == nil)
    }

    @Test("Lyrics: the synced ones first, their offset; unsynced lines; plain text; none")
    func lyricsMapping() throws {
        let both = try Self.decode(SubsonicLyricsList.self, #"""
            {"structuredLyrics":[
              {"lang":"und","synced":false,"line":[{"value":"plain one"},{"value":"plain two"}]},
              {"displayArtist":"MC Polder","displayTitle":"Blue Parade","lang":"eng","synced":true,"offset":250,
               "line":[{"start":100,"value":"Zero"},{"start":1000,"value":"First"},{"start":3500,"value":"Second"}]}]}
            """#).asLyrics()
        #expect(both == Lyrics(lines: [Lyrics.Line(start: 0, text: "Zero"), Lyrics.Line(start: 0.75, text: "First"),
                                       Lyrics.Line(start: 3.25, text: "Second")]))
        let unsynced = try Self.decode(SubsonicLyricsList.self,
            #"{"structuredLyrics":{"synced":false,"line":[{"value":"one"},{"start":5,"value":"two"}]}}"#).asLyrics()
        #expect(unsynced == Lyrics(lines: [Lyrics.Line(start: nil, text: "one"), Lyrics.Line(start: nil, text: "two")]))
        #expect(try Self.decode(SubsonicLyricsList.self, "{}").asLyrics() == nil)
        #expect(try Self.decode(SubsonicLyricsList.self, #"{"structuredLyrics":[{"synced":true,"line":[{"start":0,"value":""}]}]}"#).asLyrics() == nil)
        #expect(try Self.decode(SubsonicPlainLyrics.self, #"{"value":"\n  First line \r\n\r\nSecond\n\n"}"#).asLyrics()?.lines.map(\.text)
                == ["First line", "", "Second"])
        #expect(try Self.decode(SubsonicPlainLyrics.self, #"{"value":""}"#).asLyrics() == nil)
    }

    // MARK: The library

    /// A server with `songs` in albums of the given sizes, whose search3
    /// pages by offset (or, `paging: false`, answers the first page again).
    static func library(albums: [(String, Int)], paging: Bool = true, searchRefused: Bool = false) -> SubsonicFake {
        let fake = SubsonicFake()
        let songs = albums.flatMap { album, count in
            (1...count).map { F.song("\(album)-\($0)", album: album, track: $0, albumArtist: false) }
        }
        fake.on("getAlbumList2") { request in
            let offset = Int(request.value("offset") ?? "0") ?? 0
            let page = albums.dropFirst(offset).map { F.album($0.0, songs: $0.1, artist: "Artist \($0.0)") }
            return .json(F.ok(#""albumList2":{"album":[\#(page.joined(separator: ","))]}"#))
        }
        fake.on("search3") { request in
            if searchRefused { return .json(F.failed(10, "missing parameter: 'query'")) }
            let size = Int(request.value("songCount") ?? "20") ?? 20
            let offset = paging ? Int(request.value("songOffset") ?? "0") ?? 0 : 0
            let page = songs.dropFirst(offset).prefix(size)
            return .json(F.ok(#""searchResult3":{"song":[\#(page.joined(separator: ","))]}"#))
        }
        fake.on("getAlbum") { request in
            let id = request.value("id") ?? ""
            let own = albums.first { $0.0 == id }.map { album in
                (1...album.1).map { F.song("\(id)-\($0)", album: id, track: $0, albumArtist: false) }
            } ?? []
            return .json(F.ok(#""album":{"id":"\#(id)","name":"Album \#(id)","artist":"Artist \#(id)","song":[\#(own.joined(separator: ","))]}"#))
        }
        return fake
    }

    @Test("Every song by search3 in pages, progress as they come, the album artist from the albums")
    func allTracksInPages() async throws {
        let fake = Self.library(albums: [("a", 3), ("b", 2)])
        let progress = SubsonicProgressRecorder()
        let tracks = try await F.client(fake).allTracks(pageSize: 2) { progress.add($0, $1) }
        #expect(tracks.map(\.id) == ["a-1", "a-2", "a-3", "b-1", "b-2"])
        #expect(fake.requests("search3").map { $0.value("songOffset") } == ["0", "2", "4"])
        #expect(fake.requests("search3").allSatisfy { $0.value("query") == "" && $0.value("artistCount") == "0" && $0.value("albumCount") == "0" })
        #expect(progress.values.map { [$0.0, $0.1] } == [[0, 5], [2, 5], [4, 5], [5, 5]])
        #expect(tracks.allSatisfy { $0.albumArtist?.name == "Artist \($0.albumID!)" })
        #expect(fake.requests("getAlbum").isEmpty)

        // The app's call: 1000 a page, one request for a small library.
        let one = Self.library(albums: [("a", 3), ("b", 2)])
        #expect(try await F.client(one).allTracks(progress: nil).count == 5)
        #expect(one.requests("search3").count == 1)
    }

    @Test("A server that does not page, or will not search for nothing: the missing albums are walked")
    func allTracksByAlbums() async throws {
        let stuck = Self.library(albums: [("a", 3), ("b", 2), ("c", 1)], paging: false)
        let tracks = try await F.client(stuck).allTracks(pageSize: 2, progress: nil)
        #expect(Set(tracks.map(\.id)) == ["a-1", "a-2", "a-3", "b-1", "b-2", "c-1"] && tracks.count == 6)
        #expect(Set(stuck.requests("getAlbum").compactMap { $0.value("id") }) == ["a", "b", "c"])

        let refusing = Self.library(albums: [("a", 3), ("b", 2)], searchRefused: true)
        #expect(try await F.client(refusing).allTracks(progress: nil).count == 5)

        let offline = SubsonicFake()
        offline.on("getAlbumList2") { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: (any Error).self) { _ = try await F.client(offline).allTracks(progress: nil) }
    }

    @Test("Albums by getAlbumList2 until nothing new; album artists without guests; genres and playlists by name")
    func lists() async throws {
        let fake = Self.library(albums: [("a", 1), ("b", 1), ("c", 1)])
        fake.on("getArtists", ok: F.artistIndexes)
        fake.on("getGenres", ok: #""genres":{"genre":[{"value":"rock","songCount":2},{"value":"Électro","songCount":1},{"value":"Ambient"}]}"#)
        fake.on("getPlaylists", ok: #""playlists":{"playlist":[{"id":"2","name":"zz"},{"id":"1","name":"Aa"},{"id":"3","name":"m","owner":"other"}]}"#)
        let client = F.client(fake)
        #expect(try await client.allAlbums().map(\.id) == ["a", "b", "c"])
        #expect(fake.requests("getAlbumList2").map { $0.value("offset") } == ["0", "3"])
        #expect(fake.requests("getAlbumList2").allSatisfy { $0.value("type") == "alphabeticalByName" && $0.value("size") == "500" })

        let artists = try await client.allArtists()
        #expect(artists.map(\.name) == ["Amsterdam Strings", "MC Polder"])
        #expect(artists[1].isFavorite && artists[1].albumCount == 3 && artists[1].imageTag == nil)
        #expect(try await client.genres().map(\.name) == ["Ambient", "Électro", "rock"])
        let playlists = try await client.playlists()
        #expect(playlists.map(\.name) == ["Aa", "m", "zz"])
        #expect(playlists.map(\.isReadOnly) == [false, true, false])

        // A server that answers the same page again: no endless loop.
        let same = SubsonicFake()
        same.on("getAlbumList2", ok: #""albumList2":{"album":[\#(F.album("a", songs: 1))]}"#)
        #expect(try await F.client(same).allAlbums().count == 1)
        #expect(same.requests.count == 2)
    }

    @Test("An album's songs by disc and track; one item; an unknown one is .notFound")
    func items() async throws {
        let fake = SubsonicFake()
        let discs = [F.song("2-1", track: 1, disc: 2, albumArtist: false), F.song("1-2", track: 2, disc: 1, albumArtist: false),
                     F.song("x", albumArtist: false), F.song("1-1", track: 1, disc: 1, albumArtist: false),
                     F.song("nodisc-3", track: 3, albumArtist: false)].joined(separator: ",")
        fake.on("getAlbum", ok: #""album":{"id":"al","name":"Two Discs","artist":"Band","artistId":"b1","song":[\#(discs)]}"#)
        fake.on("getSong", body: F.failed(70, "Song not found"))
        fake.on("getArtist", ok: #""artist":{"id":"b1","name":"Band","albumCount":1,"album":[\#(F.album("al", songs: 5))]}"#)
        let client = F.client(fake)
        let tracks = try await client.albumTracks(albumID: "al")
        #expect(tracks.map(\.id) == ["1-1", "1-2", "nodisc-3", "x", "2-1"])
        #expect(tracks.allSatisfy { $0.albumArtist == ArtistRef(id: "b1", name: "Band") })
        #expect(try await client.album(id: "al").name == "Two Discs")
        #expect(try await client.artist(id: "b1").albumCount == 1)
        await #expect(throws: MusicServerError.notFound) { _ = try await client.track(id: "nope") }
    }

    @Test("Search: search3's artists, albums and songs, `limit` of each; playlists matched by name here")
    func search() async throws {
        let fake = SubsonicFake()
        fake.on("search3", ok: #""searchResult3":{"artist":[{"id":"n","name":"Nightdrive","albumCount":2}],"album":[\#(F.album("al", songs: 3))],"song":[\#(F.song("s1")),\#(F.song("s2"))]}"#)
        fake.on("getPlaylists", ok: #""playlists":{"playlist":[{"id":"1","name":"Late NIGHT"},{"id":"2","name":"Morning"},{"id":"3","name":"Nightcäp"}]}"#)
        let client = F.client(fake)
        let results = try await client.search("  night ", limit: 1)
        #expect(results.artists.map(\.name) == ["Nightdrive"])
        #expect(results.albums.map(\.id) == ["al"])
        #expect(results.tracks.map(\.id) == ["s1", "s2"])
        #expect(results.playlists.map(\.id) == ["1"])
        let asked = try #require(fake.requests("search3").first)
        #expect(asked.value("query") == "night")
        #expect([asked.value("artistCount"), asked.value("albumCount"), asked.value("songCount")] == ["1", "1", "1"])
        #expect(try await client.search("nightcap", limit: 5).playlists.map(\.id) == ["3"])
        #expect(try await client.search("   ", limit: 5).isEmpty)
        #expect(fake.requests("search3").count == 2)
    }

    // MARK: Playlist entries

    @Test("Entry ids: the song and which of its places, from 0")
    func entryIDs() {
        #expect(SubsonicClient.entryIDs(["A", "B", "A", "C", "A"]) == ["A#0", "B#0", "A#1", "C#0", "A#2"])
        #expect(SubsonicClient.parse(entryID: "A#1") == ("A", 1))
        #expect(SubsonicClient.parse(entryID: "odd#id#2") == ("odd#id", 2))
        #expect(SubsonicClient.parse(entryID: "plain") == ("plain", 0))
        #expect(SubsonicClient.parse(entryID: "x#-1") == ("x#-1", 0))
        let list = ["A", "B", "A"]
        #expect(SubsonicClient.positions(of: ["A#1"], in: list) == [2])
        #expect(SubsonicClient.positions(of: ["A#0", "B#0"], in: list) == [0, 1])
        // Changed elsewhere: fewer places now, the last one not taken; gone, skipped.
        #expect(SubsonicClient.positions(of: ["A#5"], in: list) == [2])
        #expect(SubsonicClient.positions(of: ["A#0", "A#1", "A#2"], in: ["A", "B"]) == [0])
        #expect(SubsonicClient.positions(of: ["Z#0", "B#0", "B#0"], in: list) == [1])
    }

    /// Playlists kept in memory, changed as Navidrome 0.64.2 changes them
    /// (measured): updatePlaylist removes by the positions before the change
    /// and then adds at the end; createPlaylist with playlistId replaces
    /// the songs. `failing`: the n-th updatePlaylist (from 1) fails on the
    /// way, as a phone's network does.
    final class Playlists: @unchecked Sendable {
        private let lock = NSLock()
        private var lists: [String: [String]] = [:]
        private var updates = 0
        var failing: Int?

        subscript(id: String) -> [String] { lock.withLock { lists[id] ?? [] } }

        func serve(_ fake: SubsonicFake, formPost: Bool) {
            fake.on("getOpenSubsonicExtensions", ok: formPost ? F.extensions : #""openSubsonicExtensions":[]"#)
            fake.on("createPlaylist") { [self] request in
                let id = request.value("playlistId") ?? "p\(request.value("name") ?? "")"
                lock.withLock { lists[id] = request.values("songId") }
                return .json(F.ok(#""playlist":{"id":"\#(id)","name":"x"}"#))
            }
            fake.on("updatePlaylist") { [self] request in
                let id = request.value("playlistId") ?? ""
                return try lock.withLock {
                    updates += 1
                    if updates == failing { throw URLError(.networkConnectionLost) }
                    let gone = Set(request.values("songIndexToRemove").compactMap(Int.init))
                    var list = (lists[id] ?? []).enumerated().filter { !gone.contains($0.offset) }.map(\.element)
                    list += request.values("songIdToAdd")
                    lists[id] = list
                    return .json(F.ok())
                }
            }
            fake.on("getPlaylist") { [self] request in
                let songs = self[request.value("id") ?? ""].map { F.song($0) }
                return .json(F.ok(#""playlist":{"id":"x","entry":[\#(songs.joined(separator: ","))]}"#))
            }
        }
    }

    static func playlistServer(formPost: Bool = true) -> (SubsonicClient, SubsonicFake, Playlists) {
        let fake = SubsonicFake()
        let lists = Playlists()
        lists.serve(fake, formPost: formPost)
        return (F.client(fake), fake, lists)
    }

    @Test("A playlist's tracks carry their entry ids; add, remove and move change the right places")
    func playlistChanges() async throws {
        let (client, fake, lists) = Self.playlistServer()
        let id = try await client.createPlaylist(name: "t", trackIDs: ["A", "B", "C", "A"])
        let entries = try await client.playlistTracks(playlistID: id)
        #expect(entries.map(\.id) == ["A", "B", "C", "A"])
        #expect(entries.map(\.playlistEntryID) == ["A#0", "B#0", "C#0", "A#1"])

        try await client.addToPlaylist(playlistID: id, trackIDs: ["D", "A"])
        #expect(lists[id] == ["A", "B", "C", "A", "D", "A"])
        try await client.removeFromPlaylist(playlistID: id, entryIDs: ["A#0", "C#0", "Z#0"])
        #expect(lists[id] == ["B", "A", "D", "A"])
        try await client.removeFromPlaylist(playlistID: id, entryIDs: ["A#1"])
        #expect(lists[id] == ["B", "A", "D"])

        // `index` is where the entry ends up, as on Jellyfin: A to 2 in
        // A B C D gives B C A D.
        let moved = try await client.createPlaylist(name: "m", trackIDs: ["A", "B", "C", "D"])
        try await client.movePlaylistEntry(playlistID: moved, entryID: "A#0", to: 2)
        #expect(lists[moved] == ["B", "C", "A", "D"])
        try await client.movePlaylistEntry(playlistID: moved, entryID: "D#0", to: 0)
        #expect(lists[moved] == ["D", "B", "C", "A"])
        try await client.movePlaylistEntry(playlistID: moved, entryID: "B#0", to: 99)
        #expect(lists[moved] == ["D", "C", "A", "B"])
        let before = fake.requests("updatePlaylist").count
        try await client.movePlaylistEntry(playlistID: moved, entryID: "C#0", to: 1)
        #expect(fake.requests("updatePlaylist").count == before)
        await #expect(throws: MusicServerError.notFound) {
            try await client.movePlaylistEntry(playlistID: moved, entryID: "Z#0", to: 0)
        }
        #expect(fake.requests("getOpenSubsonicExtensions").isEmpty)
    }

    @Test("Every move against Jellyfin's rule: remove the entry, insert it at index")
    func everyMove() async throws {
        let songs = ["A", "B", "C", "D", "E", "F"]
        for from in songs.indices {
            for to in songs.indices {
                let (client, _, lists) = Self.playlistServer()
                let id = try await client.createPlaylist(name: "x", trackIDs: songs)
                try await client.movePlaylistEntry(playlistID: id, entryID: "\(songs[from])#0", to: to)
                var expected = songs
                expected.insert(expected.remove(at: from), at: to)
                #expect(lists[id] == expected, "\(from) → \(to)")
            }
        }
    }

    @Test("A long playlist: one form POST where the server takes them; a move near the end sends little")
    func longPlaylistWithFormPost() async throws {
        let songs = (0..<250).map { "s\($0)" }
        let (client, fake, lists) = Self.playlistServer(formPost: true)
        let id = try await client.createPlaylist(name: "long", trackIDs: songs)
        #expect(lists[id] == songs)
        let created = try #require(fake.requests("createPlaylist").first)
        #expect(created.method == "POST" && created.values("songId").count == 250)
        #expect(created.url.query == nil)  // the credentials too are in the body
        #expect(created.value("t") == F.token && created.value("f") == "json")

        try await client.movePlaylistEntry(playlistID: id, entryID: "s0#0", to: 249)
        #expect(lists[id] == Array(songs.dropFirst()) + ["s0"])
        #expect(fake.requests("updatePlaylist").map(\.method) == ["POST"])

        // s0 is last now: one place up touches the last two places only.
        try await client.movePlaylistEntry(playlistID: id, entryID: "s0#0", to: 248)
        let near = try #require(fake.requests("updatePlaylist").last)
        #expect(near.method == "GET")
        #expect(near.values("songIndexToRemove") == ["248", "249"] && near.values("songIdToAdd") == ["s0", "s249"])

        try await client.removeFromPlaylist(playlistID: id, entryIDs: songs.prefix(150).map { "\($0)#0" })
        #expect(lists[id] == Array(songs[150..<249]) + ["s249"])
        #expect(fake.requests("updatePlaylist").last?.method == "POST")
    }

    @Test("A long playlist without formPost: 100 a request, additions first; a request lost loses no song")
    func longPlaylistWithoutFormPost() async throws {
        let songs = (0..<250).map { "s\($0)" }
        let (client, fake, lists) = Self.playlistServer(formPost: false)
        let id = try await client.createPlaylist(name: "long", trackIDs: songs)
        #expect(lists[id] == songs)
        #expect(fake.requests("createPlaylist").first?.values("songId").count == 100)
        #expect(fake.requests("updatePlaylist").map { $0.values("songIdToAdd").count } == [100, 50])
        #expect(fake.requests.allSatisfy { $0.method == "GET" })

        let start = fake.requests("updatePlaylist").count
        try await client.movePlaylistEntry(playlistID: id, entryID: "s0#0", to: 249)
        #expect(lists[id] == Array(songs.dropFirst()) + ["s0"])
        let move = fake.requests("updatePlaylist").dropFirst(start)
        #expect(move.map { $0.values("songIdToAdd").count } == [100, 100, 50, 0, 0, 0])
        #expect(move.map { $0.values("songIndexToRemove").count } == [0, 0, 0, 100, 100, 50])
        #expect(move.allSatisfy { $0.values("songIdToAdd").count + $0.values("songIndexToRemove").count <= 100 })
        // Highest first: each request's positions are still where they were.
        #expect(move.dropFirst(3).first?.values("songIndexToRemove").first == "249")

        for failing in 1...6 {
            let (client, _, lists) = Self.playlistServer(formPost: false)
            let id = try await client.createPlaylist(name: "f", trackIDs: songs)
            lists.failing = 2 + failing  // after the two requests that made it
            await #expect(throws: (any Error).self) {
                try await client.movePlaylistEntry(playlistID: id, entryID: "s10#0", to: 200)
            }
            #expect(Set(lists[id]) == Set(songs), "request \(failing) lost")
        }
    }

    @Test("An old server's createPlaylist answers nothing: the newest playlist of that name")
    func createWithoutAnswer() async throws {
        let fake = SubsonicFake()
        fake.on("createPlaylist", ok: "")
        fake.on("getPlaylists", ok: #""playlists":{"playlist":[{"id":"old","name":"Mix","created":"2026-01-01T00:00:00Z"},{"id":"new","name":"Mix","created":"2026-11-09T10:00:00Z"},{"id":"other","name":"Else","created":"2026-11-09T11:00:00Z"}]}"#)
        #expect(try await F.client(fake).createPlaylist(name: "Mix", trackIDs: ["a"]) == "new")
        fake.on("getPlaylists", ok: #""playlists":{}"#)
        await #expect(throws: MusicServerError.decoding("the new playlist has no id")) {
            _ = try await F.client(fake).createPlaylist(name: "Mix", trackIDs: [])
        }
        fake.on("deletePlaylist", body: F.failed(70, "data not found"))
        await #expect(throws: MusicServerError.notFound) { try await F.client(fake).deletePlaylist(id: "gone") }
    }
}
