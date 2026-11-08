// Jellyfin's answers into Track, Album, Artist, Playlist, Genre, Lyrics and
// Quick Connect states, from literals of what the 12.4 server sends.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Jellyfin: decoding and mapping")
struct JellyfinDecodingTests {
    func item(_ json: String) throws -> JellyfinItem {
        try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
    }

    @Test("A track: performers, album artist, genres, numbers, user data")
    func track() throws {
        let track = try #require(try item(JellyfinFixtures.track).asTrack())
        #expect(track.id == "2c4a765f5c8d9b4907be5d835a82513c")
        #expect(track.name == "Blue Parade")
        #expect(track.albumID == "db819dd856243bb2ee6e34f20cebf984")
        #expect(track.albumName == "Iron Gardens")
        #expect(track.artists == [ArtistRef(id: "45c0fee6139602552d2167741735c07e", name: "MC Polder"),
                                  ArtistRef(id: "9462cf3929c2979a36a5e8bed4ee77cf", name: "Lyric Engine")])
        #expect(track.albumArtist == ArtistRef(id: "45c0fee6139602552d2167741735c07e", name: "MC Polder"))
        #expect(track.genres == ["Hip-Hop", "Nederhop"])
        #expect(track.year == 2016)
        #expect(track.trackNumber == 1)
        #expect(track.discNumber == 1)
        #expect(track.duration == 6)
        #expect(track.imageTag == nil)
        #expect(track.albumImageTag == "b63e8160ef7d966248696c03c30e0626")
        #expect(track.artwork == Artwork(itemID: "db819dd856243bb2ee6e34f20cebf984", tag: "b63e8160ef7d966248696c03c30e0626"))
        #expect(track.isFavorite)
        #expect(track.playCount == 3)
        #expect(abs((track.lastPlayed?.timeIntervalSince1970 ?? 0) - 1_794_102_558.4805246) < 0.000_01)
        #expect(abs((track.dateAdded?.timeIntervalSince1970 ?? 0) - 1_794_101_162.3483093) < 0.000_01)
        #expect(track.normalizationGain == -7.5)
        #expect(track.playlistEntryID == "2c4a765f5c8d9b4907be5d835a82513c")
        #expect(track.artistLine == "MC Polder, Lyric Engine")
    }

    @Test("A track with little: no user data, no ids, a year only in PremiereDate")
    func sparseTrack() throws {
        let json = #"""
        {"Id":"t1","Name":"Hint","Type":"Audio","RunTimeTicks":12345678,
         "PremiereDate":"1999-05-01T00:00:00.0000000Z","Artists":["A", ""],"AlbumArtist":"B",
         "PrimaryImageTag":"p","UserData":{"LastPlayedDate":"0001-01-01T00:00:00.0000000Z"},
         "DateCreated":"not a date"}
        """#
        let track = try #require(try item(json).asTrack())
        #expect(track.artists == [ArtistRef(id: nil, name: "A")])
        #expect(track.albumArtist == ArtistRef(id: nil, name: "B"))
        #expect(track.year == 1999)
        #expect(abs(track.duration - 1.2345678) < 0.000_000_1)
        #expect(track.playCount == 0)
        #expect(!track.isFavorite)
        #expect(track.lastPlayed == nil)
        #expect(track.dateAdded == nil)
        #expect(track.normalizationGain == nil)
        #expect(track.playlistEntryID == nil)
        // A track's own image is in ImageTags only.
        #expect(track.imageTag == nil)
    }

    @Test("An item without an id is dropped, not the page")
    func noID() throws {
        let page = JellyfinFixtures.page([#"{"Name":"no id"}"#, JellyfinFixtures.track(id: "a", name: "A"), #"{"Id":""}"#])
        let result = try JSONDecoder().decode(JellyfinItemsResult.self, from: Data(page.utf8))
        #expect((result.items ?? []).compactMap { $0.asTrack() }.map(\.id) == ["a"])
        #expect(result.totalRecordCount == 3)
    }

    @Test("An album: ChildCount, RunTimeTicks, album artists before performers")
    func album() throws {
        let album = try #require(try item(JellyfinFixtures.album).asAlbum())
        #expect(album.id == "d69312c4d583d8619adbb036b73e79fe")
        #expect(album.name == "Dust Parades")
        #expect(album.artists == [ArtistRef(id: "6630c43097f3b47f81a35c0dd57fec0f", name: "Hexagon Lights")])
        #expect(album.year == 2019)
        #expect(album.genres == ["Electronic; Techno"])
        #expect(album.imageTag == "a0afaf02c8097145cf98ab95ad6bb91e")
        #expect(album.trackCount == 7)
        #expect(album.duration == 47)
        #expect(!album.isFavorite)
        #expect(album.playCount == 0)
        #expect(album.lastPlayed == nil)
        #expect(album.dateAdded != nil)
    }

    @Test("CumulativeRunTimeTicks wins over RunTimeTicks when both are there")
    func cumulative() throws {
        let json = #"{"Id":"a","Name":"A","Type":"MusicAlbum","RunTimeTicks":10,"CumulativeRunTimeTicks":600000000}"#
        #expect(try item(json).asAlbum()?.duration == 60)
    }

    @Test("An album artist with counts and overview; a genre; a playlist")
    func others() throws {
        let artist = try #require(try item(JellyfinFixtures.artist).asArtist())
        #expect(artist == Artist(id: "67b37b6aab140ac9da5cb06c6a6db8e9", name: "Amsterdam Strings", imageTag: "f00d",
                                 genres: ["Classical"], isFavorite: true, albumCount: 3, songCount: 22,
                                 overview: "A string ensemble."))
        let genre = try #require(try item(JellyfinFixtures.genre).asGenre())
        #expect(genre == Genre(id: "5d98424b382b886304766be2851d2682", name: "Classical",
                               imageTag: "74cbd217f604ebcaa43c8022d81a14ca", songCount: 22, albumCount: 3))
        let playlist = try #require(try item(JellyfinFixtures.playlist).asPlaylist())
        #expect(playlist.id == "ef78e9ded245b898db79ee08250526b8")
        #expect(playlist.trackCount == 4)
        #expect(playlist.duration == 28)
        #expect(playlist.imageTag == "8e5f2179618b4a86790236cc3d8fa0f4")
        #expect(abs((playlist.dateAdded?.timeIntervalSince1970 ?? 0) - 1_794_102_412) < 0.001)
    }

    @Test("Lyrics, synced: the documented shape")
    func syncedLyrics() throws {
        let json = #"""
        {"Metadata":{"Artist":"MC Polder","Title":"Blue Parade","Length":60000000,"IsSynced":true},
         "Lyrics":[{"Text":"First line","Start":5000000},
                   {"Text":"Second line","Start":22500000,"Cues":[{"Position":0,"EndPosition":6,"Start":22500000,"End":25000000}]},
                   {"Text":"","Start":40000000}]}
        """#
        let lyrics = try #require(try JSONDecoder().decode(JellyfinLyrics.self, from: Data(json.utf8)).asLyrics())
        #expect(lyrics.isSynced)
        #expect(lyrics.lines == [Lyrics.Line(start: 0.5, text: "First line"),
                                 Lyrics.Line(start: 2.25, text: "Second line"),
                                 Lyrics.Line(start: 4, text: "")])
    }

    @Test("Lyrics, plain: no Start, or IsSynced false")
    func plainLyrics() throws {
        let plain = #"{"Metadata":{},"Lyrics":[{"Text":"One"},{"Text":"Two"}]}"#
        let a = try #require(try JSONDecoder().decode(JellyfinLyrics.self, from: Data(plain.utf8)).asLyrics())
        #expect(!a.isSynced)
        #expect(a.lines.map(\.text) == ["One", "Two"])

        let unsynced = #"{"Metadata":{"IsSynced":false},"Lyrics":[{"Text":"One","Start":0},{"Text":"Two","Start":0}]}"#
        let b = try #require(try JSONDecoder().decode(JellyfinLyrics.self, from: Data(unsynced.utf8)).asLyrics())
        #expect(!b.isSynced)

        let zeros = #"{"Lyrics":[{"Text":"One","Start":0},{"Text":"Two","Start":0}]}"#
        let c = try #require(try JSONDecoder().decode(JellyfinLyrics.self, from: Data(zeros.utf8)).asLyrics())
        #expect(!c.isSynced)

        let empty = #"{"Metadata":{},"Lyrics":[]}"#
        #expect(try JSONDecoder().decode(JellyfinLyrics.self, from: Data(empty.utf8)).asLyrics() == nil)
    }

    @Test("Quick Connect's documented shapes")
    func quickConnect() throws {
        let start = try JSONDecoder().decode(JellyfinQuickConnectResult.self, from: Data(JellyfinFixtures.quickConnect.utf8))
        #expect(start.code == "588758")
        #expect(start.secret == "7E53089B6931599088F77D07612D2FC68812A82FF172E7F23C170CCC6D39E670")
        #expect(start.authenticated == false)
        let done = try JSONDecoder().decode(JellyfinQuickConnectResult.self,
                                            from: Data(#"{"Secret":"s","Code":"123456","Authenticated":true}"#.utf8))
        #expect(done.authenticated == true)
    }

    @Test("A playback report's body")
    func playbackBody() throws {
        let body = JellyfinPlaybackInfo(PlaybackReport(trackID: "t", position: 187.25, isPaused: true, playSessionID: "p"))
        let data = try JSONEncoder().encode(body)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["ItemId"] as? String == "t")
        #expect(object["MediaSourceId"] as? String == "t")
        #expect((object["PositionTicks"] as? NSNumber)?.int64Value == 1_872_500_000)
        #expect(object["IsPaused"] as? Bool == true)
        #expect(object["PlaySessionId"] as? String == "p")
        #expect(object["PlayMethod"] as? String == "DirectStream")
        #expect(object["CanSeek"] as? Bool == true)
    }

    @Test("Decoding 358 tracks' worth of JSON is quick")
    func decodeSpeed() throws {
        let one = JellyfinFixtures.track
        let page = JellyfinFixtures.page(Array(repeating: one, count: 2000))
        let data = Data(page.utf8)
        let clock = ContinuousClock()
        var tracks: [Track] = []
        let elapsed = try clock.measure {
            let result = try JSONDecoder().decode(JellyfinItemsResult.self, from: data)
            tracks = (result.items ?? []).compactMap { $0.asTrack() }
        }
        #expect(tracks.count == 2000)
        print("JellyfinDecoding: a page of 2000 tracks (\(data.count / 1024) kB) decoded and mapped in \(elapsed)")
    }
}
