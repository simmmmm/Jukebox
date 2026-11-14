// Classical music in the kit (the classical research, 14 November 2026):
// what a track now carries and how each server's real answer fills it, and
// the research's heuristics (its works.py), ported to Classical/Works.swift,
// on its examples and on both servers' answers for its classical test
// library (ClassicalFixtures). The photographer, 14 November 2026: "iets wat ik
// ook graag zou willen supporten is klassieke muziek hoe veel fanaten het
// wél zouden willen zien".

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Classical: what a track carries, from both servers")
struct ClassicalTrackTests {
    /// A library as the kit kept it before the classical fields, encoded by
    /// that kit (14 November 2026) with sorted keys.
    static let oldCache = #"""
    {"albums":[{"artists":[{"id":"r1","name":"Ludwig van Beethoven"}],"genres":["Classical"],"id":"a1","isFavorite":false,"name":"Symphony No. 5","playCount":0,"trackCount":4,"year":2016}],"artists":[{"genres":[],"id":"r1","isFavorite":false,"name":"Ludwig van Beethoven"}],"genres":[{"id":"Classical","name":"Classical"}],"playlists":[{"id":"p1","isReadOnly":false,"name":"Sunday"}],"savedAt":816100000,"tracks":[{"albumArtist":{"id":"r1","name":"Ludwig van Beethoven"},"albumID":"a1","albumName":"Symphony No. 5","artists":[{"id":"r1","name":"Ludwig van Beethoven"}],"container":"flac","dateAdded":815000000,"discNumber":1,"duration":451,"genres":["Classical"],"id":"t1","imageTag":"dc-a1:1","isFavorite":true,"lastPlayed":816000000,"name":"Symphony No. 5 in C minor, Op. 67: I. Allegro con brio","normalizationGain":-6.5,"playCount":3,"trackNumber":1,"year":2016}],"version":1}
    """#

    @Test("A library kept on disk before the classical fields still opens; the new ones go to disk and back")
    func oldCacheOpens() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("classical-cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(Self.oldCache.utf8).write(to: url)

        let library = try #require(LibraryCache.load(from: url))
        let track = try #require(library.tracks.first)
        #expect(track.name == "Symphony No. 5 in C minor, Op. 67: I. Allegro con brio")
        #expect(track.playCount == 3 && track.isFavorite && track.container == "flac" && track.normalizationGain == -6.5)
        #expect(track.credits == nil && track.work == nil && track.movement == nil && track.grouping == nil
                && track.discTitle == nil)
        #expect(library.albums.count == 1 && library.artists.count == 1 && library.playlists.count == 1)

        var classical = track
        classical.credits = [Credit(role: .composer, artist: ArtistRef(id: "r1", name: "Ludwig van Beethoven")),
                             Credit(role: .conductor, artist: ArtistRef(id: nil, name: "Anna Verhoef")),
                             Credit(role: .performer, artist: ArtistRef(id: "r2", name: "Lena Brandt"), instrument: "Piano")]
        classical.work = "Symphony No. 5 in C minor, Op. 67"
        classical.movement = Movement(name: "Allegro con brio", number: 1, count: 4)
        classical.grouping = "Beethoven: The Symphonies"
        classical.discTitle = "Act I"
        try LibraryCache.save(CachedLibrary(savedAt: Date(), tracks: [classical, track], albums: [], artists: [],
                                            playlists: [], genres: []), to: url)
        #expect(LibraryCache.load(from: url)?.tracks == [classical, track])
    }

    @Test("Navidrome: composer, conductor, soloists with their instrument, lyricist, work, movement, grouping, as search3 sends them")
    func navidrome() throws {
        let tracks = ClassicalFixtures.navidromeTracks
        #expect(tracks.count == 47)
        func track(_ title: String, year: Int? = nil) throws -> Track {
            try #require(tracks.first { $0.name == title && (year == nil || $0.year == year) })
        }

        // Picard as it comes: the roles apart, and the movement's own work.
        let weber = try track("Symphony No. 5 in C minor, Op. 67: I. Allegro con brio", year: 2016)
        #expect(weber.credits == [
            Credit(role: .composer, artist: ArtistRef(id: "4Z0TlrU5k1fZJdMbCXD8ki", name: "Ludwig van Beethoven")),
            Credit(role: .conductor, artist: ArtistRef(id: "71qFn5LKaBsgWnPSO4M3qH", name: "Jonas Weber")),
            Credit(role: .performer, artist: ArtistRef(id: "4FQyoV3dEEWHxbp9bhib2l", name: "Berlin Chamber Philharmonic"),
                   instrument: "Orchestra"),
        ])
        #expect(weber.work == "Symphony No. 5 in C minor, Op. 67: I. Allegro con brio" && weber.movement == nil)

        // A FLAC with MOVEMENT and MOVEMENTTOTAL; an MP3's MVIN "1/4" loses
        // its number in Navidrome (measured).
        let verhoef = try track("Symphony No. 5 in C minor, Op. 67: II. Andante con moto", year: 2019)
        #expect(verhoef.work == "Symphony No. 5 in C minor, Op. 67")
        #expect(verhoef.movement == Movement(name: "Andante con moto", number: 2, count: 4))
        #expect(try track("Allegro con brio").movement == Movement(name: "Allegro con brio"))

        // The opera: the librettist, the singers' voices, in Navidrome's order.
        let duet = try track("Die Zauberflöte, K. 620: Act II. No. 21 Duet “Pa-pa-pa”")
        #expect(duet.credited(.lyricist).map(\.name) == ["Emanuel Schikaneder"])
        #expect(duet.credited(.conductor).map(\.name) == ["Ruben Sterk"])
        #expect((duet.credits ?? []).filter { $0.role == .performer }.map { "\($0.artist.name) (\($0.instrument ?? ""))" }
                == ["Sofie Lindqvist (Soprano)", "Marten Hol (Baritone)", "Leiden Opera Chorus (Choir Vocals)",
                    "Hague Baroque Orchestra (Orchestra)"])

        // Vivaldi: GROUPING, and the violin.
        let spring = try track("Violin Concerto in E major, RV 269 “La primavera”: I. Allegro")
        #expect(spring.grouping == "Le quattro stagioni, Op. 8 Nos. 1–4")
        #expect(spring.work == "Violin Concerto in E major, RV 269 “La primavera”")
        #expect((spring.credits ?? []).first { $0.instrument == "Violin" }?.artist.name == "Sara Kok")

        // The CDDB rip has the composer only; the compilation and the files
        // without tags nothing.
        #expect(try track("Symphony No. 5 In C Minor, Op. 67 - I. Allegro Con Brio").credits?.map(\.role) == [.composer])
        #expect(try track("Schubert: Ständchen, D 957 No. 4").credits == nil)
        let untagged = try track("01 - I. Allegro non troppo")
        #expect(untagged.credits == nil && untagged.work == nil && untagged.movement == nil && untagged.grouping == nil)

        // Navidrome lists the contributors in another order on each song of
        // one album: mapped, every song of one recording has the same.
        for album in ["Beethoven: Symphony No. 5", "Die Zauberflöte (Highlights)", "Piano Concertos Nos. 20 & 21",
                      "Vivaldi: The Four Seasons", "Symphony No. 5 · Egmont Overture"] {
            #expect(Set(tracks.filter { $0.albumName == album }.map(\.credits)).count == 1, "\(album)")
        }
    }

    @Test("Navidrome: an opera's acts come with its album, and reach its songs in allTracks and albumTracks")
    func navidromeDiscTitles() async throws {
        let fake = SubsonicFake()
        fake.on("getAlbumList2", body: ClassicalFixtures.navidromeAlbums)
        fake.on("search3", body: ClassicalFixtures.navidromeSongs)
        let tracks = try await SubsonicFixtures.client(fake).allTracks(progress: nil)
        #expect(tracks.count == 47)
        let acts = tracks.filter { $0.discTitle != nil }.map { "\($0.discNumber ?? 0) \($0.discTitle ?? "")" }
        #expect(acts.sorted() == ["1 Act I", "1 Act I", "2 Act II", "2 Act II"])
        #expect(tracks.filter { $0.discTitle != nil }.allSatisfy { $0.albumName == "Die Zauberflöte (Highlights)" })

        // getAlbum: the album with its songs, as Navidrome answers it.
        let opera = "549oySNJUTBHMVbTk9sXVD"
        let one = SubsonicFake()
        one.on("getAlbum", body: try Self.album(opera))
        let album = try await SubsonicFixtures.client(one).albumTracks(albumID: opera)
        #expect(album.map { $0.discTitle ?? "" } == ["Act I", "Act I", "Act II", "Act II"])
    }

    /// getAlbum's answer for one album of the fixture: the album as
    /// getAlbumList2 has it, with its songs.
    static func album(_ id: String) throws -> String {
        func inner(_ json: String, _ key: String, _ list: String) throws -> [[String: Any]] {
            let body = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            let response = body?["subsonic-response"] as? [String: Any]
            return (response?[key] as? [String: Any])?[list] as? [[String: Any]] ?? []
        }
        var album = try #require(try inner(ClassicalFixtures.navidromeAlbums, "albumList2", "album").first { $0["id"] as? String == id })
        album["song"] = try inner(ClassicalFixtures.navidromeSongs, "searchResult3", "song").filter { $0["albumId"] as? String == id }
        let data = try JSONSerialization.data(withJSONObject: ["subsonic-response": ["status": "ok", "version": "1.16.1",
                                                                                      "album": album]])
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Jellyfin: the composer from People, and not the artists People repeats; nothing else is there")
    func jellyfin() {
        let tracks = ClassicalFixtures.jellyfinTracks
        #expect(tracks.count == 47)
        // 39 of the 47 have a Composer person (measured): not the
        // compilation's 6 (composer only in the title) or the 2 untagged.
        #expect(tracks.filter { $0.credits != nil }.count == 39)
        #expect(tracks.allSatisfy { ($0.credits ?? []).allSatisfy { $0.role == .composer && $0.artist.id != nil } })
        #expect(Set(tracks.flatMap { $0.credited(.composer).map(\.name) })
                == ["Ludwig van Beethoven", "Wolfgang Amadeus Mozart", "Johann Sebastian Bach", "Antonio Vivaldi"])
        #expect(tracks.allSatisfy { $0.work == nil && $0.movement == nil && $0.grouping == nil && $0.discTitle == nil })
    }

    static func server(_ transport: JellyfinMockTransport) -> JellyfinServer {
        JellyfinServer(client: JellyfinFixtures.client(transport),
                       credentials: ServerCredentials(jellyfin: Credentials(
                        serverURL: JellyfinFixtures.server, serverID: "s", serverName: "Jellyfin",
                        userID: JellyfinFixtures.userID, userName: "test", accessToken: JellyfinFixtures.token)))
    }

    /// The fixture's items as Jellyfin answers the kit's page (no People),
    /// or the People request for some ids.
    static func items(people: Bool, ids: Set<String>? = nil) throws -> String {
        let all = try JSONSerialization.jsonObject(with: Data(ClassicalFixtures.jellyfinItems.utf8)) as? [String: Any]
        var items = (all?["Items"] as? [[String: Any]] ?? []).filter { ids?.contains($0["Id"] as? String ?? "") ?? true }
        if !people { items = items.map { var item = $0; item["People"] = nil; return item } }
        let data = try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": items.count,
                                                               "StartIndex": 0])
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Jellyfin: People only for the classical albums' tracks, by id; a pop library asks nothing more; a failure costs only the composers")
    func jellyfinPeopleOnlyForClassical() async throws {
        let page = try Self.items(people: false)
        let transport = JellyfinMockTransport { request in
            let query = request.jellyfinQuery
            guard query["Fields"] == "People" else { return JellyfinMockTransport.respond(200, page) }
            let ids = Set((query["Ids"] ?? "").split(separator: ",").map(String.init))
            return JellyfinMockTransport.respond(200, try Self.items(people: true, ids: ids))
        }
        let tracks = try await Self.server(transport).allTracks(progress: nil)
        #expect(tracks.count == 47)
        let asked = transport.requests.filter { $0.jellyfinQuery["Fields"] == "People" }
        #expect(asked.count == 1)
        // The 9 classical albums' 45 tracks, not the folder of 2 untagged files.
        let ids = Set((asked.first?.jellyfinQuery["Ids"] ?? "").split(separator: ",").map(String.init))
        #expect(ids.count == 45)
        #expect(tracks.filter { !ids.contains($0.id) }.allSatisfy { $0.name.hasPrefix("0") })
        #expect(tracks.filter { $0.credits != nil }.count == 39)
        #expect(tracks.first { $0.name == "Cello Suite No. 1 in G major, BWV 1007: I. Prélude" }?
            .credited(.composer).map(\.name) == ["Johann Sebastian Bach"])

        // A pop library, its tracks on albums: one request, no more.
        let pop = JellyfinMockTransport(body: JellyfinFixtures.page((1...3).map { i in
            #"{"Id":"p\#(i)","Name":"Night River \#(i)","Type":"Audio","AlbumId":"al","Album":"Dust Parades","Genres":["Rock; Alternative"],"RunTimeTicks":50000000}"#
        }))
        let popTracks = try await Self.server(pop).allTracks(progress: nil)
        #expect(popTracks.count == 3 && popTracks.allSatisfy { $0.albumID == "al" })
        #expect(pop.requests.count == 1)

        // The People request fails: the library still loads, without composers.
        let failing = JellyfinMockTransport { request in
            if request.jellyfinQuery["Fields"] == "People" { return JellyfinMockTransport.respond(500) }
            return JellyfinMockTransport.respond(200, page)
        }
        let without = try await Self.server(failing).allTracks(progress: nil)
        #expect(without.count == 47 && without.allSatisfy { $0.credits == nil })
    }
}

@Suite("Classical: on the test servers", .serialized, .enabled(if: !TestServers.available.isEmpty))
struct ClassicalServerTests {
    /// The made-up library has two classical artists and no composer,
    /// work or movement tag: their albums are found, nothing else changes,
    /// and Jellyfin takes the People request (asked here directly, as
    /// allTracks would hide its failure).
    @Test("The made-up library: its classical albums found, no credits made up; Jellyfin answers the People request",
          arguments: TestServers.available)
    func library(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let tracks = try await server.allTracks(progress: nil)
        let classical = Classical.classicalAlbumIDs(in: tracks)
        let expected = Set(tracks.filter { ["Amsterdam Strings", "Clara Venn"].contains($0.albumArtist?.name) }
            .compactMap(\.albumID))
        #expect(!expected.isEmpty && classical == expected)
        #expect(tracks.allSatisfy { $0.credits == nil && $0.work == nil && $0.movement == nil && $0.discTitle == nil })

        if let jellyfin = server as? JellyfinServer {
            let ids = tracks.filter { $0.albumID.map(classical.contains) == true }.map(\.id)
            let start = Date()
            let credits = try await jellyfin.client.credits(of: ids)
            TestServers.measure(test, "People for the \(ids.count) tracks of classical albums in "
                                + "\(Int(Date().timeIntervalSince(start) * 1000)) ms")
            #expect(credits.isEmpty)
        }
    }
}

@Suite("Classical: works where the tags are missing (works.py)")
struct ClassicalWorkTests {
    let known = Classical.commonComposers

    @Test("The work from the work tag; Picard's per-movement work cut before the movement")
    func workTag() {
        func work(_ tag: String, title: String) -> Classical.WorkPart {
            Classical.workPart(of: Track(id: "t", name: title, work: tag), knownComposers: known)
        }
        let picard = work("Symphony No. 5 in C minor, Op. 67: I. Allegro con brio",
                          title: "Symphony No. 5 in C minor, Op. 67: I. Allegro con brio")
        #expect(picard.work == "Symphony No. 5 in C minor, Op. 67" && picard.part == "I. Allegro con brio")
        let aria = work("Die Zauberflöte, K. 620: Act II. No. 14 Aria “Der Hölle Rache kocht in meinem Herzen”",
                        title: "Die Zauberflöte, K. 620: Act II. No. 14 Aria “Der Hölle Rache kocht in meinem Herzen”")
        #expect(aria.work == "Die Zauberflöte, K. 620"
                && aria.part == "Act II. No. 14 Aria “Der Hölle Rache kocht in meinem Herzen”")
        // Mp3tag: the work tag whole, the title the movement.
        let mp3tag = work("Symphony No. 5 in C minor, Op. 67", title: "Scherzo. Allegro")
        #expect(mp3tag.work == "Symphony No. 5 in C minor, Op. 67" && mp3tag.part == "Scherzo. Allegro")

        // Every Navidrome song with a work tag: a work without a movement in it.
        for track in ClassicalFixtures.navidromeTracks where track.work != nil {
            let found = Classical.workPart(of: track, knownComposers: known)
            #expect(found.work.map { !$0.contains(": I") && !$0.contains(": Act") && !$0.hasSuffix("Overture") } == true,
                    "\(track.name)")
        }
    }

    @Test("Splitting a title at a movement marker: a Roman numeral, Act, Scene, No., Overture", arguments: [
        ("Symphony No. 5 in C minor, Op. 67: I. Allegro con brio", "Symphony No. 5 in C minor, Op. 67", "I. Allegro con brio"),
        ("Symphony No. 5 In C Minor, Op. 67 - III. Scherzo: Allegro", "Symphony No. 5 In C Minor, Op. 67", "III. Scherzo: Allegro"),
        ("Cello Suite No. 1 in G major, BWV 1007: V. Menuets I & II", "Cello Suite No. 1 in G major, BWV 1007", "V. Menuets I & II"),
        ("Die Zauberflöte, K. 620: Act I. No. 2 Aria “Der Vogelfänger bin ich ja”", "Die Zauberflöte, K. 620",
         "Act I. No. 2 Aria “Der Vogelfänger bin ich ja”"),
        ("Egmont, Op. 84: Overture", "Egmont, Op. 84", "Overture"),
        ("Tosca – Act II. Vissi d’arte", "Tosca", "Act II. Vissi d’arte"),
        ("Tosca, Act II: Scene 5", "Tosca, Act II", "Scene 5"),
        ("Carmen: No. 5 Habanera", "Carmen", "No. 5 Habanera"),
        ("Violin Concerto in G minor, RV 315 “L’estate”: III. Presto", "Violin Concerto in G minor, RV 315 “L’estate”", "III. Presto"),
        ("01 - I. Allegro non troppo", nil, "I. Allegro non troppo"),
        ("Allegro con brio", nil, "Allegro con brio"),
        ("Night River", nil, "Night River"),
        ("Intro - Interlude", nil, "Intro - Interlude"),
    ] as [(String, String?, String)])
    func movementMarker(title: String, work: String?, part: String) {
        let found = Classical.split(title: title, knownComposers: known)
        #expect(found.work == work && found.part == part && found.composer == nil)
    }

    @Test("A composer before a colon, only when it is a known composer")
    func composerBeforeColon() {
        let cddb = Classical.split(title: "Beethoven: Symphony No. 5 - I. Allegro con brio", knownComposers: known)
        #expect(cddb.composer == "Beethoven" && cddb.work == "Symphony No. 5" && cddb.part == "I. Allegro con brio")
        let dvorak = Classical.split(title: "Dvořák: Symphony No. 9 'From the New World' - II. Largo", knownComposers: known)
        #expect(dvorak.composer == "Dvořák" && dvorak.work == "Symphony No. 9 'From the New World'" && dvorak.part == "II. Largo")
        // No movement: the rest is the work, one track long.
        let air = Classical.split(title: "Bach: Air (Orchestral Suite No. 3 in D, BWV 1068)", knownComposers: known)
        #expect(air.composer == "Bach" && air.work == "Air (Orchestral Suite No. 3 in D, BWV 1068)")
        #expect(Classical.split(title: "J.S. Bach: Air", knownComposers: known).composer == "J.S. Bach")

        // Not a composer: nothing is taken off.
        let interlude = Classical.split(title: "Interlude: Night River", knownComposers: known)
        #expect(interlude.composer == nil && interlude.work == nil && interlude.part == "Interlude: Night River")
        #expect(Classical.split(title: "Shattered Glass: Remix", knownComposers: known).composer == nil)
        // Unknown to the list, known to the library's own tags.
        let tagged = [Track(id: "z", name: "Suite", credits: [Credit(role: .composer, artist: ArtistRef(id: nil, name: "Pieter Zandvoort"))])]
        let library = Classical.knownComposers(in: tagged)
        #expect(Classical.split(title: "Zandvoort: Suite No. 1 - I. Prelude", knownComposers: known).composer == nil)
        #expect(Classical.split(title: "Zandvoort: Suite No. 1 - I. Prelude", knownComposers: library).composer == "Zandvoort")
        #expect(Classical.surname("Bach, Johann Sebastian") == "bach" && Classical.surname("Ludwig van Beethoven") == "beethoven")
    }

    @Test("A title that is only a tempo takes the album's name as the work, when the album is named like one")
    func tempoOnly() {
        // Jellyfin drops the work tag of the Mp3tag album (measured).
        let mp3tag = ClassicalFixtures.jellyfinTracks.filter { $0.albumName == "Symphony No. 5" && $0.year == 2012 }
        #expect(mp3tag.map(\.name).sorted() == ["Allegro", "Allegro con brio", "Andante con moto", "Scherzo. Allegro"])
        #expect(mp3tag.allSatisfy { Classical.workPart(of: $0, knownComposers: known).work == "Symphony No. 5" })

        func work(_ title: String, album: String) -> String? {
            Classical.workPart(of: Track(id: "t", name: title, albumName: album), knownComposers: known).work
        }
        #expect(work("Sarabande", album: "Cello Suite No. 1 in G major, BWV 1007") == "Cello Suite No. 1 in G major, BWV 1007")
        #expect(work("Larghetto", album: "Piano Concerto, Op. 11") == "Piano Concerto, Op. 11")
        // Pop titles that are tempos, on albums that are no work.
        #expect(work("Prelude", album: "Night Songs") == nil)
        #expect(work("Finale", album: "Greatest Hits") == nil)
        #expect(work("Night River", album: "Symphony No. 5") == nil)
    }

    @Test("Catalogue numbers folded: KV 466, K. 466 and K466 are one; BWV, Op., Hob., D. and RV likewise")
    func catalogueNumbers() {
        let typed: [String: [String]] = [
            "K 466": ["KV 466", "K. 466", "K466", "K 466", "kv466", "k. 466", "Mozart K 466"],
            "BWV 1007": ["BWV 1007", "BWV1007", "bwv 1007", "BWV. 1007"],
            "Op 67": ["Op. 67", "op. 67", "Op 67", "op67", "Opus 67"],
            "Hob I:94": ["Hob. I:94", "Hob.I:94", "hob i:94", "Hob. I: 94"],
            "D 957/4": ["D 957 No. 4", "D. 957 No. 4", "d957 no. 4", "D 957, No. 4"],
            "RV 269": ["RV 269", "RV. 269", "rv269"],
            "Op 27/2": ["Op. 27 No. 2", "op. 27, no. 2"],
        ]
        for (key, forms) in typed {
            for form in forms { #expect(CatalogueNumber.normalize(form) == key, "\(form)") }
        }
        #expect(CatalogueNumber.normalize("Symphony No. 5") == nil && CatalogueNumber.normalize("466") == nil)

        // In titles and works, as the servers send them.
        let titles: [String: String] = [
            "Piano Concerto No. 20 in D minor, K. 466: I. Allegro": "K 466",
            "Bach: Air (Orchestral Suite No. 3 in D, BWV 1068)": "BWV 1068",
            "Haydn: Symphony No. 94 in G, Hob. I:94 'Surprise' - II. Andante": "Hob I:94",
            "Schubert: Ständchen, D 957 No. 4": "D 957/4",
            "Symphony no. 5 in C minor, op. 67: I. Allegro con brio": "Op 67",
            "Le quattro stagioni, Op. 8 Nos. 1–4": "Op 8",
            "Violin Concerto in E major, RV 269 “La primavera”: I. Allegro": "RV 269",
            "Die Zauberflöte, K. 620: Overture": "K 620",
            "Piano Sonata No. 11 in A, K331: III. Alla turca": "K 331",
            "Piano Concerto No. 20 in D minor, KV 466": "K 466",
        ]
        for (title, key) in titles { #expect(CatalogueNumber.find(in: title)?.description == key, "\(title)") }
        // One capital letter alone is no prefix: band names, keys, words.
        for title in ["M83 Remix", "L7 Live", "Area D2", "Ständchen, D957", "Symphony No. 5 in C minor", "Mambo No. 5",
                      "Top 40", "Hip-Hop 2", "Night River"] {
            #expect(CatalogueNumber.find(in: title) == nil, "\(title)")
        }
        #expect(RadioRealLibraryFixture.tracks.allSatisfy { CatalogueNumber.find(in: $0.name) == nil })
        // The same key from what was typed and from the title, and one work
        // whichever way a title writes it.
        for typed in ["kv 466", "K466", "K. 466"] {
            #expect(CatalogueNumber.normalize(typed) == CatalogueNumber.find(in: "Piano Concerto No. 20 in D minor, K. 466")?.description)
        }
        #expect(Set(["Rondo, K. 485", "Rondo, KV 485", "Rondo, K485"].map { Classical.workKey(composer: "Mozart", work: $0) }).count == 1)
    }

    @Test("A performance: consecutive tracks of one album sharing a work, performers and year; 19 on each server, as works.py found")
    func performances() {
        for (server, tracks) in [("Navidrome", ClassicalFixtures.navidromeTracks), ("Jellyfin", ClassicalFixtures.jellyfinTracks)] {
            let found = Classical.performances(tracks)
            #expect(found.count == 19, "\(server)")
            #expect(found.map(\.tracks.count).sorted() == [1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3, 3, 4, 4, 4, 4, 4, 6], "\(server)")
            #expect(found.reduce(0) { $0 + $1.tracks.count } == 47)

            // The two Mozart concertos on one album apart.
            let concertos = found.filter { $0.work.hasPrefix("Piano Concerto") }
            #expect(concertos.map(\.work) == ["Piano Concerto No. 20 in D minor, K. 466", "Piano Concerto No. 21 in C major, K. 467"], "\(server)")
            #expect(concertos.allSatisfy { $0.composer == "Wolfgang Amadeus Mozart" && $0.tracks.count == 3 })
            // The suite whole, with its catalogue number.
            let suite = found.first { $0.catalogue == CatalogueNumber(prefix: "BWV", number: "1007") }
            #expect(suite?.parts == ["I. Prélude", "II. Allemande", "III. Courante", "IV. Sarabande", "V. Menuets I & II", "VI. Gigue"])
            // The opera's four numbers over two discs; the overture to Egmont alone.
            #expect(found.first { $0.work == "Die Zauberflöte, K. 620" }?.tracks.map(\.discNumber) == [1, 1, 2, 2])
            #expect(found.first { $0.work == "Egmont, Op. 84" }?.parts == ["Overture"])
            // The compilation: each track a work of its own, by the composer its title names.
            let compilation = found.filter { $0.tracks.first?.albumName == "The Best of Classical" }
            #expect(compilation.map { $0.composer ?? "?" } == ["Beethoven", "Dvořák", "Mozart", "Bach", "Haydn", "Schubert"], "\(server)")
        }

        // Navidrome merges the 1998 and 2012 "Symphony No. 5" into one album
        // of 8 (measured): the year and the performers tell them apart.
        let merged = Classical.performances(ClassicalFixtures.navidromeTracks).filter { $0.tracks.first?.albumName == "Symphony No. 5" }
        #expect(merged.map { $0.tracks.first?.year } == [1998, 2012])
        #expect(merged.map(\.parts) == [["I. Allegro Con Brio", "II. Andante Con Moto", "III. Scherzo: Allegro", "IV. Allegro"],
                                        ["Allegro con brio", "Andante con moto", "Scherzo. Allegro", "Allegro"]])
    }

    @Test("The same work across recordings: the composer, then the form and number, else the catalogue number")
    func sameWork() {
        let fifth = Classical.WorkKey(composer: "beethoven", work: "symphony 5")
        var keys: [Set<Classical.WorkKey>] = []
        for tracks in [ClassicalFixtures.navidromeTracks, ClassicalFixtures.jellyfinTracks] {
            let found = Classical.performances(tracks)
            // Four recordings of the Fifth, and the compilation's movement.
            #expect(found.filter { $0.key == fifth }.map(\.tracks.count).sorted() == [1, 4, 4, 4, 4])
            keys.append(Set(found.map(\.key)))
        }
        // Both servers name the same works.
        #expect(keys[0] == keys[1])
        #expect(keys[0].isSuperset(of: [
            Classical.WorkKey(composer: "mozart", work: "piano concerto 20"),
            Classical.WorkKey(composer: "mozart", work: "piano concerto 21"),
            Classical.WorkKey(composer: "mozart", work: "K 620"),
            Classical.WorkKey(composer: "vivaldi", work: "RV 269"),
            Classical.WorkKey(composer: "bach", work: "cello suite 1"),
            Classical.WorkKey(composer: "schubert", work: "D 957/4"),
            Classical.WorkKey(composer: "dvorak", work: "symphony 9"),
        ]))
        // Spellings of one work agree; another composer's Fifth does not.
        #expect(Classical.workKey(composer: "Ludwig van Beethoven", work: "Symphony no. 5 in C minor, op. 67") == fifth)
        #expect(Classical.workKey(composer: "Beethoven", work: "Symphony No. 5 In C Minor") == fifth)
        #expect(Classical.workKey(composer: "Gustav Mahler", work: "Symphony No. 5") != fifth)
        #expect(Classical.workKey(composer: "Mozart", work: "Piano Concerto No. 20 in D minor, KV 466")
                == Classical.workKey(composer: "Wolfgang Amadeus Mozart", work: "Piano Concerto No. 20, K. 466"))
    }

    @Test("Recognising the classical albums of 20 000 pop songs, as Jellyfin's allTracks does on every load")
    func recognitionCost() {
        // The made-up library 56 times over, each copy its own albums.
        let real = RadioRealLibraryFixture.tracks
        let tracks = (0..<56).flatMap { copy in
            real.map { t in
                Track(id: "\(copy)-\(t.id)", name: t.name, albumID: t.albumID.map { "\(copy)-\($0)" },
                      albumName: t.albumName, artists: t.artists, albumArtist: t.albumArtist, genres: t.genres)
            }
        }
        let start = Date()
        let classical = Classical.classicalAlbumIDs(in: tracks)
        let seconds = Date().timeIntervalSince(start)
        print("CLASSICAL-MEASURE \(tracks.count) tracks: classical albums found in \(Int(seconds * 1000)) ms")
        #expect(classical.count == 56 * Classical.classicalAlbumIDs(in: real).count)
        #expect(seconds < 1)
    }

    @Test("Recognising an album as classical: its genre, or most tracks with a movement or a catalogue number")
    func classicalAlbums() {
        // Every album of the classical library but the folder of files without tags.
        let navidrome = ClassicalFixtures.navidromeTracks
        #expect(Classical.classicalAlbumIDs(in: navidrome).count == 8)
        #expect(!Classical.classicalAlbumIDs(in: navidrome).contains("69IwB2p7tQDejD3lowUIFo"))
        let jellyfin = ClassicalFixtures.jellyfinTracks
        #expect(Classical.classicalAlbumIDs(in: jellyfin).count == 9)
        #expect(!Classical.classicalAlbumIDs(in: jellyfin).contains("a8d6f24dee7a2c59cb7e5594bebd5577"))

        // The made-up pop library: only the two classical artists' albums.
        let real = RadioRealLibraryFixture.tracks
        let expected = Set(real.filter { ["Amsterdam Strings", "Clara Venn"].contains($0.albumArtist?.name) }.compactMap(\.albumID))
        #expect(!expected.isEmpty && Classical.classicalAlbumIDs(in: real) == expected)
        #expect(real.allSatisfy { Classical.split(title: $0.name, knownComposers: known).work == nil })

        // Without a genre, by the titles; a composer or work tag alone is no sign.
        func album(_ titles: [String], genre: String = "", composer: Bool = false, work: Bool = false) -> Set<ItemID> {
            Classical.classicalAlbumIDs(in: titles.enumerated().map { i, title in
                Track(id: "\(i)", name: title, albumID: "a", genres: genre.isEmpty ? [] : [genre],
                      credits: composer ? [Credit(role: .composer, artist: ArtistRef(id: nil, name: "Max Martin"))] : nil,
                      work: work ? title : nil)
            })
        }
        #expect(album(["Sonata in A, K. 331: I. Andante grazioso", "Sonata in A, K. 331: II. Menuetto", "Sonata in A, K. 331: III. Alla turca"]) == ["a"])
        #expect(album(["Night River", "Glass Song", "Red Letters"], genre: "Classical; Piano") == ["a"])
        #expect(album(["Night River", "Glass Song", "Red Letters"], composer: true, work: true).isEmpty)
        #expect(album(["Night River", "Glass Song", "Interlude: III. Strings"]).isEmpty)
    }
}
