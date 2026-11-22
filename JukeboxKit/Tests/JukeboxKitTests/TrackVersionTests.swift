// The version a title names (Library/TrackVersion.swift), from the Oasis
// album the photographer filtered on 21 November 2026 and the usual
// titles that must stay their own song's.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Track version")
struct TrackVersionTests {
    func version(_ title: String) -> String { TrackVersion.read(title).version.name }
    func base(_ title: String) -> String { TrackVersion.read(title).title }

    /// "(What's The Story) Morning Glory? (30th Anniversary)": no track
    /// numbers, so in the order of their names.
    let oasis = ["Cast No Shadow (Remastered)", "Cast No Shadow (Unplugged)",
                 "Champagne Supernova (Remastered)", "Champagne Supernova (Unplugged)",
                 "Don't Look Back in Anger (Remastered)", "Don't Look Back in Anger (Unplugged)",
                 "Hello (Remastered)", "Morning Glory (Remastered)", "Wonderwall (Unplugged)"]
        .enumerated().map { Track(id: "o\($0.offset)", name: $0.element) }

    @Test("The Oasis album: Remastered and Unplugged, each in the album's order")
    func oasisAlbum() {
        let kinds = TrackVersion.kinds(of: oasis)
        #expect(kinds.map(\.name) == ["Remastered", "Unplugged"])
        let unplugged = TrackVersion.tracks(oasis, without: [kinds[0]])
        #expect(unplugged.map(\.name) == ["Cast No Shadow (Unplugged)", "Champagne Supernova (Unplugged)",
                                          "Don't Look Back in Anger (Unplugged)", "Wonderwall (Unplugged)"])
        #expect(TrackVersion.tracks(oasis, without: []).count == oasis.count)
        #expect(TrackVersion.only(kinds, without: [kinds[0]]) == kinds[1])
        #expect(TrackVersion.only(kinds, without: []) == nil)
        #expect(base("Cast No Shadow (Unplugged)") == "Cast No Shadow")
    }

    @Test("The kinds by their words")
    func kinds() {
        #expect(version("Song [Live]") == "Live")
        #expect(version("Song (Live at Wembley)") == "Live")
        #expect(version("Song (Remastered 2014)") == "Remastered")
        #expect(version("Song (2011 Remaster)") == "Remastered")
        #expect(version("Song (Demo)") == "Demo")
        #expect(version("Song (Acoustic)") == "Acoustic")
        #expect(version("Song (Acoustic Version)") == "Acoustic")
        #expect(version("Song (Remix)") == "Remix")
        #expect(version("Song (Extended Mix)") == "Remix")
        #expect(version("Song (Instrumental)") == "Instrumental")
        #expect(version("Song (Radio Edit)") == "Edit")
        #expect(version("Song (MTV Unplugged)") == "Unplugged")
        #expect(version("Song (Mono)") == "Mono")
        #expect(version("Song (Single Version)") == "Single Version")
        #expect(version("Song (Take 2)") == "Take")
    }

    @Test("A dash's part, only when it names a recording")
    func dash() {
        #expect(version("Creep - Remastered 2009") == "Remastered")
        #expect(base("Creep - Remastered 2009") == "Creep")
        #expect(version("Song - Live") == "Live")
        #expect(version("Symphony No. 5 - II. Andante") == "Original")
        #expect(base("Symphony No. 5 - II. Andante") == "Symphony No. 5 - II. Andante")
    }

    @Test("Guests, parts and the song's own words are no version")
    func notVersions() {
        #expect(version("Song (feat. X)") == "Original")
        #expect(version("Song (Part 2)") == "Original")
        #expect(version("Song (Reprise)") == "Original")
        #expect(version("(Live)") == "Original")
        #expect(version("Live Forever") == "Original")
        #expect(version("Alive (Credit Roll)") == "Original")
        #expect(version("(I Can't Get No) Satisfaction") == "Original")
        #expect(base("Song (Part 2)") == "Song (Part 2)")
    }

    @Test("A guest after the version stays in the title")
    func guestAfterVersion() {
        #expect(version("Song (Live) (feat. X)") == "Live")
        #expect(base("Song (Live) (feat. X)") == "Song (feat. X)")
    }

    @Test("Two markers: the one that says more than a remaster")
    func twoMarkers() {
        #expect(version("Song (Live) (Remastered 2014)") == "Live")
        #expect(base("Song (Live) (Remastered 2014)") == "Song")
    }

    @Test("Original counts, first; one kind alone is no choice")
    func original() {
        let mixed = [Track(id: "1", name: "Song"), Track(id: "2", name: "Song (Live)"), Track(id: "3", name: "Other")]
        #expect(TrackVersion.kinds(of: mixed).map(\.name) == ["Original", "Live"])
        #expect(TrackVersion.tracks(mixed, without: [TrackVersion(name: "Live")]).map(\.id) == ["1", "3"])
        #expect(TrackVersion.kinds(of: [Track(id: "1", name: "A (Live)"), Track(id: "2", name: "B [Live]")]).isEmpty)
        #expect(TrackVersion.kinds(of: [Track(id: "1", name: "A"), Track(id: "2", name: "B (feat. X)")]).isEmpty)
    }

    @Test("Each kind on or off on its own, the last one on stays on")
    func toggling() {
        let live = TrackVersion(name: "Live"), demo = TrackVersion(name: "Demo")
        let kinds: [TrackVersion] = [.original, demo, live]
        var off = TrackVersion.toggle(live, in: [], of: kinds)
        #expect(off == [live])
        off = TrackVersion.toggle(demo, in: off, of: kinds)
        #expect(off == [live, demo])
        // Original is the last one on: it stays on.
        #expect(TrackVersion.toggle(.original, in: off, of: kinds) == off)
        #expect(TrackVersion.toggle(live, in: off, of: kinds) == [demo])
    }
}
