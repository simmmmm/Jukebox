// Albums the server splits by album-artist tags, as one (Library/
// AlbumMerge.swift), from the three the photographer saw twice in Linux's
// Recently Added on 20 November 2026; and the albums that must stay apart.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Album merge")
struct AlbumMergeTests {
    func artist(_ name: String) -> ArtistRef { ArtistRef(id: nil, name: name) }
    func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    @Test("A second copy of the album: each song once, the numbered one kept")
    func secondCopy() {
        let tagged = Album(id: "a1", name: "Hold Your Breath", artists: [artist("Tash Sultana")], year: 2019)
        let copy = Album(id: "a2", name: "Hold Your Breath", artists: [artist("Tash Sultana"), artist("Tash Sultana")], year: 2019)
        let tracks = [Track(id: "c1", name: "bullet lovers", albumID: "a2", duration: 241),
                      Track(id: "t1", name: "Bullet Lovers", albumID: "a1", trackNumber: 2, duration: 240),
                      Track(id: "t2", name: "Hole", albumID: "a1", trackNumber: 6, duration: 200),
                      Track(id: "c2", name: "Hole", albumID: "a2", duration: 201),
                      Track(id: "c3", name: "Dirty Water", albumID: "a2", duration: 180)]
        let (albums, kept) = AlbumMerge.merge(albums: [tagged, copy], tracks: tracks)
        #expect(albums.count == 1)
        // The numbered copies stay, the bare ones go; a song only the copy has stays.
        #expect(kept.map(\.id) == ["t1", "t2", "c3"])
        #expect(albums[0].trackCount == 3)
    }

    @Test("Jack Johnson: the clean name, every track, the newest date")
    func jackJohnson() {
        let clean = Album(id: "a1", name: "From Here To Now To You", artists: [artist("Jack Johnson")],
                          year: 2013, imageTag: "t1", trackCount: 10, dateAdded: day(1))
        let split = Album(id: "a2", name: "From Here To Now To You",
                          artists: [artist("Jack Johnson"), artist("Jack Johnson")],
                          year: 2013, trackCount: 2, dateAdded: day(5))
        let tracks = [Track(id: "t1", name: "Shot Reverse Shot", albumID: "a1", trackNumber: 2),
                      Track(id: "t2", name: "I Got You", albumID: "a2", trackNumber: 1)]
        let (albums, moved) = AlbumMerge.merge(albums: [clean, split], tracks: tracks)
        #expect(albums.count == 1)
        #expect(albums[0].id == "a1")
        #expect(albums[0].artistLine == "Jack Johnson")
        // Counted from the tracks the library has, after any copy went.
        #expect(albums[0].trackCount == 2)
        #expect(albums[0].dateAdded == day(5))
        #expect(moved.map(\.albumID) == ["a1", "a1"])
        #expect(moved[1].albumImageTag == "t1")
        // A download or a station that kept "a2" still finds the album.
        #expect(albums[0].mergedIDs == ["a2"])

        // The cache's merged album meets a third part on the next load.
        let third = Album(id: "a3", name: "from here to now to you", artists: [artist("Jack Johnson")], year: 2013)
        let (again, _) = AlbumMerge.merge(albums: albums + [third], tracks: [])
        #expect(again.count == 1)
        #expect(Set(again[0].mergedIDs ?? []) == ["a2", "a3"])
    }

    @Test("The Jesus and Mary Chain: a capital And is the same band")
    func maryChain() {
        let a = Album(id: "b1", name: "Stoned and Dethroned", artists: [artist("The Jesus And Mary Chain")], year: 1994)
        let b = Album(id: "b2", name: "Stoned and Dethroned", artists: [artist("The Jesus and Mary Chain")], year: nil)
        let (albums, _) = AlbumMerge.merge(albums: [a, b], tracks: [])
        #expect(albums.count == 1)
        #expect(albums[0].year == 1994)
    }

    @Test("Maribou State: a joined tag, and a favourite part kept as the id")
    func maribou() {
        let a = Album(id: "c1", name: "Portraits", artists: [artist("Maribou State")], imageTag: "x", trackCount: 9)
        let b = Album(id: "c2", name: "Portraits ", artists: [artist("Maribou State, Maribou State")],
                      trackCount: 3, isFavorite: true)
        let other = Album(id: "z", name: "Kingdoms in Colour", artists: [artist("Maribou State")])
        let (albums, _) = AlbumMerge.merge(albums: [other, a, b], tracks: [])
        #expect(albums.map(\.id) == ["z", "c2"])
        #expect(albums[1].artistLine == "Maribou State")
        #expect(albums[1].isFavorite)
    }

    @Test("Editions, other artists and other years stay apart")
    func apart() {
        let base = Album(id: "d1", name: "Portraits", artists: [artist("Maribou State")], year: 2015)
        let deluxe = Album(id: "d2", name: "Portraits (Deluxe)", artists: [artist("Maribou State")], year: 2015)
        let someone = Album(id: "d3", name: "Portraits", artists: [artist("Someone Else, Maribou State")], year: 2015)
        let later = Album(id: "d4", name: "Portraits", artists: [artist("Maribou State")], year: 2020)
        let unknown = Album(id: "d5", name: "Portraits", artists: [artist("Maribou State")])
        let all = [base, deluxe, someone, later, unknown]
        let (albums, tracks) = AlbumMerge.merge(albums: all, tracks: [Track(id: "t", name: "x", albumID: "d5")])
        #expect(albums.map(\.id) == all.map(\.id))
        #expect(tracks[0].albumID == "d5")
    }

    @Test("First album artist: before a comma, an ampersand, feat or a semicolon")
    func first() {
        #expect(AlbumMerge.firstArtist("Jack Johnson feat. G. Love") == "jack johnson")
        #expect(AlbumMerge.firstArtist("Maribou State & Khruangbin") == "maribou state")
        #expect(AlbumMerge.firstArtist("A;B") == "a")
    }
}
