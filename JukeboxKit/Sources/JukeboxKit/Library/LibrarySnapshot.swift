// CONTRACT — signatures fixed, bodies the kit agent's (docs/ARCHITECTURE.md).
//
// The whole library at one moment, indexed for the radio and the mixes:
// by id, artist, album, genre and decade, and by name for matching what
// Last.fm says to what the library has. A value: made off the main actor
// from the tracks LibraryStore holds, handed to the radio, never changed.
//
// The index is built once, in `init`, and kept in one immutable class, so a
// snapshot is two references to copy and the radio reads plain arrays by
// track number rather than hashing ids. Names are split where a tag joins
// several: Jellyfin 12.4 gives "MC Polder; Lyric Engine" as one artist and
// "Hip-Hop; Nederhop" as one genre when a file's tag is written that way
// (the test server: 92 of 358 tracks have such an artist, 294 such a genre),
// and the radio needs the two artists and the two genres to know who sounds
// like whom.

import Foundation

public struct LibrarySnapshot: Sendable {
    public let tracks: [Track]
    /// The indices, by track number (the position in `tracks`).
    let index: Index

    public init(tracks: [Track]) {
        self.tracks = tracks
        self.index = Index(tracks: tracks)
    }

    public static let empty = LibrarySnapshot(tracks: [])

    public var isEmpty: Bool { tracks.isEmpty }

    public func track(id: ItemID) -> Track? {
        index.trackByID[id].map { tracks[$0] }
    }

    /// Tracks with this artist key among their performers or as album artist.
    public func tracks(artistKey: String) -> [Track] {
        guard let a = index.artistByKey[artistKey] else { return [] }
        return index.artistTracks[a].map { tracks[$0] }
    }

    /// An album's tracks in disc and track order.
    public func tracks(albumID: ItemID) -> [Track] {
        guard let a = index.albumByID[albumID] else { return [] }
        return index.albumTracks[a].map { tracks[$0] }
    }

    public func tracks(genreKey: String) -> [Track] {
        guard let g = index.genreByKey[genreKey] else { return [] }
        return index.genreTracks[g].map { tracks[$0] }
    }

    /// Tracks from the decade starting at `decade` (1990 for the 1990s).
    public func tracks(decade: Int) -> [Track] {
        (index.decadeTracks[decade] ?? []).map { tracks[$0] }
    }

    /// Every artist key that is an album artist or performer, with how many
    /// tracks carry it.
    public var artistTrackCounts: [String: Int] {
        index.artistTrackCounts
    }

    /// The artist as the library spells it, with its id when known.
    public func artist(key: String) -> ArtistRef? {
        index.artistByKey[key].map { index.artistRefs[$0] }
    }

    /// Every genre key with how many tracks carry it.
    public var genreTrackCounts: [String: Int] {
        index.genreTrackCounts
    }

    /// The genre as the library spells it.
    public func genreName(key: String) -> String? {
        index.genreByKey[key].map { index.genreNames[$0] }
    }

    /// Decades with tracks (1970, 1980, …) and how many.
    public var decadeTrackCounts: [Int: Int] {
        index.decadeTracks.mapValues(\.count)
    }

    /// The track by this artist with this title, by NameKey, preferring
    /// the original album over a compilation or a live one when both are
    /// there (the one with most plays, then the oldest).
    public func match(artist: String, title: String) -> Track? {
        guard let key = matchArtist(artist), let a = index.artistByKey[key] else { return nil }
        let wanted = NameKey.title(title)
        guard !wanted.isEmpty else { return nil }
        let candidates = index.titles.tracks(artist: a, titleKey: wanted, index: index, tracks: tracks)
        return candidates.min { index.prefer(tracks[$0], over: tracks[$1], $0, $1) }.map { tracks[$0] }
    }

    /// The library's key for an artist name from elsewhere (Last.fm), when
    /// the library has that artist.
    public func matchArtist(_ name: String) -> String? {
        let key = Index.artistKey(name)
        if index.artistByKey[key] != nil { return key }
        // "Artist feat. Guest" or "A; B" from elsewhere: the first named.
        let parts = Index.splitArtistNames(name)
        if parts.count > 1 {
            let first = Index.artistKey(parts[0])
            if index.artistByKey[first] != nil { return first }
        }
        return nil
    }
}

// MARK: - Additions for the radio and the mixes

extension LibrarySnapshot {
    /// The track's artists as the radio counts them: the one it is filed
    /// under first, then its other performers; joined tags split ("A; B",
    /// "A feat. B"), and "Various Artists" left out (on a compilation the
    /// performer is who it is by). Prefer this to `Track.artistKeys`, which
    /// computes NameKeys on every call and does not split.
    public func artistKeys(of track: Track) -> [String] {
        if let i = index.trackByID[track.id] {
            return index.trackArtists[i].map { index.artistKeys[$0] }
        }
        return Index.artistNames(of: track).map { Index.artistKey($0.name) }.filter { !$0.isEmpty }
    }

    /// The artist a track is filed under (album artist, else first
    /// performer), as the radio keeps artists apart.
    public func primaryArtistKey(of track: Track) -> String? {
        artistKeys(of: track).first
    }

    /// The track's genre keys, joined tags split.
    public func genreKeys(of track: Track) -> [String] {
        if let i = index.trackByID[track.id] {
            return index.trackGenres[i].map { index.genreKeys[$0] }
        }
        return Index.splitGenreNames(track.genres).map(NameKey.genre).filter { !$0.isEmpty }
    }

    /// The position of a track in `tracks`.
    public func position(of id: ItemID) -> Int? { index.trackByID[id] }

    /// Tracks filed under this artist (as album artist, or first performer
    /// on a compilation): an artist's own songs, without their guest spots.
    public func ownTracks(artistKey: String) -> [Track] {
        guard let a = index.artistByKey[artistKey] else { return [] }
        return index.artistOwnTracks[a].map { tracks[$0] }
    }

    /// How specific a genre is, from the share of artists that carry it:
    /// ln(1 + artists / artists with the genre). "Rock" in a rock-heavy
    /// library is about 1, a genre one artist in twenty has is about 3.
    public func genreSpecificity(key: String) -> Double {
        index.genreByKey[key].map { index.genreIDF[$0] } ?? 0
    }
}

// MARK: - A genre seed

extension LibrarySnapshot {
    /// What a genre station's seed stands for in this library.
    struct GenreSeed: Sendable {
        /// By genre number, the most specific first; the weights sum to 1.
        var parts: [(genre: Int, weight: Double)]
        /// The tracks that carry every part (a joined tag's own tracks),
        /// else the lead part's: where the station opens, and its covers.
        var tracks: [Int]
        /// The part the station is named after.
        var lead: Int { parts[0].genre }
    }

    /// The genre a genre seed names; or, for a name the library does not
    /// have as one genre, the parts of it that it does. Jellyfin's
    /// /MusicGenres lists a joined tag as one genre ("Rock; Shoegaze", 19 of
    /// the test server's 23), while the snapshot splits genres on ";" and
    /// "|" (Index.splitGenreNames): with the seed's own key only, every such
    /// station was Your Station (7 of 190 opened in their tag, by chance;
    /// now all 190, docs/RADIO.md). The parts are weighted by how specific
    /// each is: a joined tag is the general genre and then the one that
    /// says what it is, and "Rock; Shoegaze" should sound like shoegaze,
    /// with rock near. Nil when the library has none of it (the station is
    /// then Your Station under the seed's own name).
    func genreSeed(key: String, name: String) -> GenreSeed? {
        if let g = index.genreByKey[key] ?? index.genreByKey[NameKey.genre(name)] {
            return GenreSeed(parts: [(g, 1)], tracks: index.genreTracks[g])
        }
        var known: [(genre: Int, position: Int)] = []
        for (position, part) in Index.splitGenreNames([name]).enumerated() {
            if let g = index.genreByKey[NameKey.genre(part)], !known.contains(where: { $0.genre == g }) {
                known.append((g, position))
            }
        }
        guard !known.isEmpty else { return nil }
        // The most specific first; between two as specific, the one with
        // fewer tracks, then the one named later (a tag goes from the general
        // to the particular: "Hip-Hop; Nederhop").
        known.sort { x, y in
            let ix = index.genreIDF[x.genre], iy = index.genreIDF[y.genre]
            if ix != iy { return ix > iy }
            let nx = index.genreTracks[x.genre].count, ny = index.genreTracks[y.genre].count
            if nx != ny { return nx < ny }
            return x.position > y.position
        }
        let total = known.reduce(0) { $0 + index.genreIDF[$1.genre] }
        let parts = known.map { part in
            (genre: part.genre, weight: total > 0 ? index.genreIDF[part.genre] / total : 1 / Double(known.count))
        }
        let lead = parts[0].genre
        let all = index.genreTracks[lead].filter { t in parts.allSatisfy { index.trackGenres[t].contains($0.genre) } }
        return GenreSeed(parts: parts, tracks: all.isEmpty ? index.genreTracks[lead] : all)
    }
}

// MARK: - The index

extension LibrarySnapshot {
    final class Index: Sendable {
        // By track number.
        let trackByID: [ItemID: Int]
        /// Artist numbers, the one the track is filed under first.
        let trackArtists: [[Int]]
        let trackGenres: [[Int]]
        /// -1 when the track has no album.
        let trackAlbum: [Int]
        /// 0 when unknown.
        let trackYear: [Int]
        /// The song a track is a recording of: tracks filed under one artist
        /// with one title (brackets, " - …" and "feat." left out) are one
        /// song, so the radio plays "Karma Police" once, not once from OK
        /// Computer and again from the best-of. Measured: with 40 of 120
        /// tracks on a best-of too, 46 songs played twice in 6 × 60 picks.
        let trackSong: [Int]
        /// By song number: its tracks.
        let songTracks: [[Int]]

        // By artist number.
        let artistKeys: [String]
        let artistByKey: [String: Int]
        let artistRefs: [ArtistRef]
        /// Every track that carries the key (performer or album artist,
        /// "Various Artists" included), in library order.
        let artistTracks: [[Int]]
        /// The tracks filed under the artist.
        let artistOwnTracks: [[Int]]
        /// The median year of the artist's own tracks, 0 when unknown.
        let artistYear: [Int]

        // By genre number.
        let genreKeys: [String]
        let genreByKey: [String: Int]
        let genreNames: [String]
        let genreTracks: [[Int]]
        /// ln(1 + artists / artists carrying the genre).
        let genreIDF: [Double]
        /// Genres that appear together on artists, with a 0 … 1 strength
        /// (cosine of the two genres' artist sets), strongest first.
        let genreRelated: [[GenreLink]]

        // By album number.
        let albumByID: [ItemID: Int]
        let albumTracks: [[Int]]

        let decadeTracks: [Int: [Int]]
        let artistTrackCounts: [String: Int]
        let genreTrackCounts: [String: Int]

        /// Built on the first `match`: NameKey.title is about 25 µs a call
        /// with Linux's Foundation (measured), half a second for 20 000
        /// titles, and only Last.fm's similar tracks need it.
        let titles = TitleIndex()

        struct GenreLink: Sendable {
            var genre: Int
            var weight: Double
        }

        init(tracks: [Track]) {
            var trackByID: [ItemID: Int] = [:]
            trackByID.reserveCapacity(tracks.count)
            var trackArtists: [[Int]] = []
            trackArtists.reserveCapacity(tracks.count)
            var trackGenres: [[Int]] = []
            trackGenres.reserveCapacity(tracks.count)
            var trackAlbum: [Int] = []
            trackAlbum.reserveCapacity(tracks.count)
            var trackYear: [Int] = []
            trackYear.reserveCapacity(tracks.count)

            var artistKeys: [String] = []
            var artistByKey: [String: Int] = [:]
            var artistRefs: [ArtistRef] = []
            var artistTracks: [[Int]] = []
            var artistOwnTracks: [[Int]] = []
            var genreKeys: [String] = []
            var genreByKey: [String: Int] = [:]
            var genreNames: [String] = []
            var genreTracks: [[Int]] = []
            var albumByID: [ItemID: Int] = [:]
            var albumTracks: [[Int]] = []
            var decadeTracks: [Int: [Int]] = [:]
            var trackSong: [Int] = []
            trackSong.reserveCapacity(tracks.count)
            var songTracks: [[Int]] = []
            var songOf: [String: Int] = [:]
            var titleKeyOf: [String: String] = [:]

            // NameKey is slow on Linux (above); a library repeats each name
            // on every track, so each spelling is keyed once.
            var artistKeyOf: [String: String] = [:]
            var genreKeyOf: [String: String] = [:]
            var genrePartsOf: [String: [String]] = [:]
            var namesOf: [String: [String]] = [:]

            func parts(_ name: String) -> [String] {
                if let known = namesOf[name] { return known }
                let split = Self.splitArtistNames(name)
                namesOf[name] = split
                return split
            }

            // Ids of single artists, so a part of a joined tag ("MC Polder"
            // out of "MC Polder; Lyric Engine") gets the id the album
            // artist has.
            var idOfName: [String: ItemID] = [:]
            for track in tracks {
                if let ref = track.albumArtist, let id = ref.id, idOfName[ref.name] == nil, parts(ref.name).count == 1 {
                    idOfName[ref.name] = id
                }
                for ref in track.artists {
                    if let id = ref.id, idOfName[ref.name] == nil, parts(ref.name).count == 1 {
                        idOfName[ref.name] = id
                    }
                }
            }

            func artistNumber(_ ref: ArtistRef) -> Int? {
                let key: String
                if let known = artistKeyOf[ref.name] {
                    key = known
                } else {
                    key = Self.artistKey(ref.name)
                    artistKeyOf[ref.name] = key
                }
                guard !key.isEmpty else { return nil }
                if let a = artistByKey[key] {
                    // The spelling with an id wins over one without.
                    if artistRefs[a].id == nil, ref.id != nil { artistRefs[a] = ref }
                    return a
                }
                let a = artistKeys.count
                artistKeys.append(key)
                artistByKey[key] = a
                artistRefs.append(ref)
                artistTracks.append([])
                artistOwnTracks.append([])
                return a
            }

            for (i, track) in tracks.enumerated() {
                trackByID[track.id] = i

                // Artists: the radio's (filed-under first, Various Artists
                // out), and every key for the public lookup.
                let named = Self.artistNames(of: track, idOfName: idOfName, split: parts)
                var own: [Int] = []
                for ref in named {
                    if let a = artistNumber(ref), !own.contains(a) { own.append(a) }
                }
                trackArtists.append(own)
                var carried = own
                if let albumArtist = track.albumArtist, Self.isVarious(albumArtist.name),
                   let a = artistNumber(albumArtist), !carried.contains(a) {
                    carried.append(a)
                }
                for a in carried { artistTracks[a].append(i) }
                if let first = own.first { artistOwnTracks[first].append(i) }

                // The song: its artist and its title.
                let titleKey: String
                if let known = titleKeyOf[track.name] {
                    titleKey = known
                } else {
                    titleKey = Self.songKey(track.name)
                    titleKeyOf[track.name] = titleKey
                }
                if let first = own.first, !titleKey.isEmpty {
                    let songKey = "\(first)|\(titleKey)"
                    if let known = songOf[songKey] {
                        trackSong.append(known)
                        songTracks[known].append(i)
                    } else {
                        songOf[songKey] = songTracks.count
                        trackSong.append(songTracks.count)
                        songTracks.append([i])
                    }
                } else {
                    trackSong.append(songTracks.count)
                    songTracks.append([i])
                }

                // Genres.
                var genres: [Int] = []
                for raw in track.genres {
                    let names: [String]
                    if let known = genrePartsOf[raw] {
                        names = known
                    } else {
                        names = Self.splitGenreNames([raw])
                        genrePartsOf[raw] = names
                    }
                    for name in names {
                        let key: String
                        if let known = genreKeyOf[name] {
                            key = known
                        } else {
                            key = NameKey.genre(name)
                            genreKeyOf[name] = key
                        }
                        guard !key.isEmpty else { continue }
                        let g: Int
                        if let known = genreByKey[key] {
                            g = known
                        } else {
                            g = genreKeys.count
                            genreKeys.append(key)
                            genreByKey[key] = g
                            genreNames.append(name)
                            genreTracks.append([])
                        }
                        if !genres.contains(g) {
                            genres.append(g)
                            genreTracks[g].append(i)
                        }
                    }
                }
                trackGenres.append(genres)

                // Album.
                if let albumID = track.albumID {
                    let a: Int
                    if let known = albumByID[albumID] {
                        a = known
                    } else {
                        a = albumTracks.count
                        albumByID[albumID] = a
                        albumTracks.append([])
                    }
                    albumTracks[a].append(i)
                    trackAlbum.append(a)
                } else {
                    trackAlbum.append(-1)
                }

                // Year and decade; a year outside 1000 … 2999 is a broken tag.
                if let year = track.year, (1000...2999).contains(year) {
                    trackYear.append(year)
                    decadeTracks[year / 10 * 10, default: []].append(i)
                } else {
                    trackYear.append(0)
                }
            }

            for a in albumTracks.indices {
                albumTracks[a].sort { x, y in
                    let tx = tracks[x], ty = tracks[y]
                    let dx = tx.discNumber ?? 1, dy = ty.discNumber ?? 1
                    if dx != dy { return dx < dy }
                    let nx = tx.trackNumber ?? Int.max, ny = ty.trackNumber ?? Int.max
                    if nx != ny { return nx < ny }
                    if tx.name != ty.name { return tx.name < ty.name }
                    return x < y
                }
            }

            // An artist's era and genres are those of the records filed under
            // them; a guest spot is someone else's record (MC Polder guesting
            // on a jazz trio's album does not make him jazz). Artists who are
            // only ever guests have their guest spots; "Various Artists" has
            // none (it is nobody's).
            let artistRecords = artistKeys.indices.map { a in
                artistOwnTracks[a].isEmpty ? artistTracks[a].filter { trackArtists[$0].contains(a) } : artistOwnTracks[a]
            }

            // Each artist's median year.
            var artistYear = [Int](repeating: 0, count: artistKeys.count)
            for a in artistKeys.indices {
                let years = artistRecords[a].map { trackYear[$0] }.filter { $0 > 0 }.sorted()
                if !years.isEmpty { artistYear[a] = years[years.count / 2] }
            }

            // Each artist's genres.
            var genreArtists = [[Int]](repeating: [], count: genreKeys.count)
            var artistGenres = [[Int]](repeating: [], count: artistKeys.count)
            for a in artistKeys.indices {
                var mark = Set<Int>()
                for t in artistRecords[a] {
                    for g in trackGenres[t] where mark.insert(g).inserted {
                        genreArtists[g].append(a)
                        artistGenres[a].append(g)
                    }
                }
            }
            // Genre specificity, over artists rather than tracks, so one
            // prolific artist does not make their genre look common.
            let artistCount = Double(max(1, artistKeys.count))
            let genreIDF = genreArtists.map { log(1 + artistCount / Double(max(1, $0.count))) }

            // Genres that go together: the cosine of their artist sets.
            var together = [[Int: Int]](repeating: [:], count: genreKeys.count)
            for genres in artistGenres where genres.count > 1 {
                for x in genres { for y in genres where x != y { together[x][y, default: 0] += 1 } }
            }
            var genreRelated: [[GenreLink]] = []
            genreRelated.reserveCapacity(genreKeys.count)
            for g in genreKeys.indices {
                var list: [GenreLink] = together[g].map { h, n in
                    GenreLink(genre: h, weight: Double(n) / (Double(genreArtists[g].count) * Double(genreArtists[h].count)).squareRoot())
                }
                list.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.genre < $1.genre }
                genreRelated.append(Array(list.prefix(12)))
            }

            var artistTrackCounts: [String: Int] = [:]
            for a in artistKeys.indices { artistTrackCounts[artistKeys[a]] = artistTracks[a].count }
            var genreTrackCounts: [String: Int] = [:]
            for g in genreKeys.indices { genreTrackCounts[genreKeys[g]] = genreTracks[g].count }

            self.trackByID = trackByID
            self.trackArtists = trackArtists
            self.trackGenres = trackGenres
            self.trackAlbum = trackAlbum
            self.trackYear = trackYear
            self.trackSong = trackSong
            self.songTracks = songTracks
            self.artistKeys = artistKeys
            self.artistByKey = artistByKey
            self.artistRefs = artistRefs
            self.artistTracks = artistTracks
            self.artistOwnTracks = artistOwnTracks
            self.artistYear = artistYear
            self.genreKeys = genreKeys
            self.genreByKey = genreByKey
            self.genreNames = genreNames
            self.genreTracks = genreTracks
            self.genreIDF = genreIDF
            self.genreRelated = genreRelated
            self.albumByID = albumByID
            self.albumTracks = albumTracks
            self.decadeTracks = decadeTracks
            self.artistTrackCounts = artistTrackCounts
            self.genreTrackCounts = genreTrackCounts
        }

        var trackCount: Int { trackArtists.count }
        var songCount: Int { songTracks.count }
        var artistCount: Int { artistKeys.count }
        var genreCount: Int { genreKeys.count }

        // MARK: Names

        /// An artist's key: NameKey's, or for a name it folds to nothing
        /// ("!!!", "†‡†": punctuation only) the name itself in lower case
        /// without spaces. Such a band is still a band; with NameKey's empty
        /// key they had no artist at all, so nothing kept them apart and
        /// their station played someone else (measured).
        static func artistKey(_ name: String) -> String {
            let key = NameKey.artist(name)
            guard key.isEmpty else { return key }
            return String(String.UnicodeScalarView(name.lowercased().unicodeScalars.filter { !$0.properties.isWhitespace }))
        }

        /// A title as one song's: lower case, letters and digits, without a
        /// part that only says which recording it is — "(Remastered 2011)",
        /// "[Live]", " - Single Version", "(feat. X)" — but with any other
        /// ("Symphony No. 5 - II. Andante" is not "- I. Allegro"; a remix
        /// is a song of its own). Plain Swift: NameKey.title costs 25 µs a
        /// call with Linux's Foundation, half a second on 20 000 tracks.
        /// Empty for a title of punctuation only: then it is its own song.
        static func songKey(_ title: String) -> String {
            let scalars = Array(title.lowercased().unicodeScalars)
            func starts(_ k: Int, _ word: String) -> Bool {
                var j = k
                for c in word.unicodeScalars {
                    guard j < scalars.count, scalars[j] == c else { return false }
                    j += 1
                }
                return true
            }
            func isKept(_ c: Unicode.Scalar) -> Bool { c.properties.isAlphabetic || c.properties.numericType != nil }
            var out = String.UnicodeScalarView()
            var group = String.UnicodeScalarView()
            var depth = 0
            var k = 0
            while k < scalars.count {
                let c = scalars[k]
                if c == "(" || c == "[" {
                    if depth == 0 { group.removeAll() }
                    depth += 1
                } else if c == ")" || c == "]" {
                    if depth == 1, !isVersionNote(String(group)) { out.append(contentsOf: group.filter(isKept)) }
                    depth = max(0, depth - 1)
                } else if depth > 0 {
                    group.append(c)
                } else {
                    if c == " ", !out.isEmpty {
                        if starts(k, " feat. ") || starts(k, " feat ") || starts(k, " ft. ") || starts(k, " featuring ") { break }
                        if starts(k, " - "), isVersionNote(String(String.UnicodeScalarView(scalars[(k + 3)...]))) { break }
                    }
                    if isKept(c) { out.append(c) }
                }
                k += 1
            }
            return String(out)
        }

        /// Words that say which recording of a song it is, not which song.
        static let versionWords = ["remaster", "live", "version", "edit", "mono", "stereo", "demo", "acoustic",
                                   "single", "deluxe", "bonus", "feat", "ft.", "featuring", "with ", "explicit",
                                   "clean", "anniversary", "re-recorded", "unplugged"]

        static func isVersionNote(_ text: String) -> Bool {
            versionWords.contains { text.contains($0) }
        }

        /// "Various Artists" and its usual spellings: not an artist the radio
        /// keeps apart or links to anyone.
        static func isVarious(_ name: String) -> Bool {
            let lower = name.lowercased()
            guard lower.contains("various") || lower == "va" || lower == "v.a." else { return false }
            let key = NameKey.artist(name)
            return key == "variousartists" || key == "various" || key == "va" || key == "variousartist"
        }

        /// The track's artists, the one it is filed under first: the album
        /// artist unless that is "Various Artists", then the performers;
        /// joined tags split.
        static func artistNames(of track: Track, idOfName: [String: ItemID] = [:],
                                split: (String) -> [String] = splitArtistNames) -> [ArtistRef] {
            var refs: [ArtistRef] = []
            func add(_ ref: ArtistRef) {
                let parts = split(ref.name)
                if parts.count == 1 {
                    if !isVarious(ref.name) { refs.append(ref) }
                    return
                }
                for part in parts where !isVarious(part) {
                    refs.append(ArtistRef(id: idOfName[part], name: part))
                }
            }
            if let albumArtist = track.albumArtist { add(albumArtist) }
            for ref in track.artists { add(ref) }
            return refs
        }

        /// "A; B", "A | B", "A feat. B", "A (feat. B)", "A ft. B" as their
        /// parts. Not "&", "and" or "/": "Simon & Garfunkel" and "AC/DC"
        /// are one artist.
        static func splitArtistNames(_ name: String) -> [String] {
            let lower = name.lowercased()
            guard name.contains(";") || name.contains("|") || lower.contains("feat")
                    || lower.contains(" ft") else {
                return [name]
            }
            var s = name
            for marker in ["(featuring ", "(feat. ", "(feat ", "(ft. ", " featuring ", " feat. ", " feat ", " ft. ", " ft "] {
                while let r = s.range(of: marker, options: .caseInsensitive) {
                    s.replaceSubrange(r, with: ";")
                }
            }
            let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()[]"))
            let parts = s.split(whereSeparator: { $0 == ";" || $0 == "|" })
                .map { $0.trimmingCharacters(in: trim) }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? [name] : parts
        }

        /// "Rock; Alternative" and "Rock | Alternative" as two genres. Not
        /// "/": "Singer/Songwriter" is one.
        static func splitGenreNames(_ names: [String]) -> [String] {
            var out: [String] = []
            for name in names {
                for part in name.split(whereSeparator: { $0 == ";" || $0 == "|" }) {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty, !out.contains(trimmed) { out.append(trimmed) }
                }
            }
            return out
        }

        /// For `match`: the original before a compilation or a live
        /// recording, then the most played, then the oldest.
        func prefer(_ a: Track, over b: Track, _ ia: Int, _ ib: Int) -> Bool {
            let la = Self.isCompilationOrLive(a), lb = Self.isCompilationOrLive(b)
            if la != lb { return !la }
            if a.playCount != b.playCount { return a.playCount > b.playCount }
            let ya = a.year ?? Int.max, yb = b.year ?? Int.max
            if ya != yb { return ya < yb }
            return ia < ib
        }

        static func isCompilationOrLive(_ track: Track) -> Bool {
            if let albumArtist = track.albumArtist, isVarious(albumArtist.name) { return true }
            let album = (track.albumName ?? "").lowercased()
            let title = track.name.lowercased()
            let words = ["greatest hits", "best of", "the very best", "collection", "anthology",
                         "essential", "compilation", "hits", "live at", "live in", "live from",
                         "(live", "[live", "unplugged"]
            if words.contains(where: { album.contains($0) }) { return true }
            if album.hasSuffix(" live") || album == "live" { return true }
            return title.contains("(live") || title.contains("[live") || title.contains("- live")
        }
    }

    /// The title index, made once on first use, behind a lock so any task
    /// may ask.
    final class TitleIndex: @unchecked Sendable {
        private let lock = NSLock()
        private var byArtist: [Int: [String: [Int]]]?

        func tracks(artist: Int, titleKey: String, index: Index, tracks: [Track]) -> [Int] {
            lock.lock()
            defer { lock.unlock() }
            if byArtist == nil {
                var built: [Int: [String: [Int]]] = [:]
                var keyOf: [String: String] = [:]
                for (i, track) in tracks.enumerated() {
                    let key: String
                    if let known = keyOf[track.name] {
                        key = known
                    } else {
                        key = NameKey.title(track.name)
                        keyOf[track.name] = key
                    }
                    for a in index.trackArtists[i] { built[a, default: [:]][key, default: []].append(i) }
                }
                byArtist = built
            }
            return byArtist?[artist]?[titleKey] ?? []
        }
    }
}
