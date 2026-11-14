// Classical music where the tags fall short: which tracks make one
// performance of a work, its composer and catalogue number, which
// performances are of the same work, and which albums are classical.
// Ported from works.py, the sketch of the classical research (14 November
// 2026, part 4), whose rules found 19 performances in both servers' answers
// for its classical test library; ClassicalTests runs the same answers
// through these.
//
// The photographer, 14 November 2026: "iets wat ik ook graag zou willen
// supporten is klassieke muziek hoe veel fanaten het wél zouden willen
// zien". Pure functions over Tracks. Only JellyfinServer.allTracks uses one
// (which albums to ask composers for); the radio, the mixes and the
// library's grouping wait for his answers to the research's three questions.

import Foundation

public enum Classical {
    /// What a track's tags and title say of its work.
    public struct WorkPart: Hashable, Sendable {
        /// As credited, else as the title names it ("Beethoven: …").
        public var composer: String?
        /// Nil when no work can be told: then the track stands alone.
        public var work: String?
        /// The track's own part ("I. Allegro con brio"); the whole title
        /// when the title holds no work.
        public var part: String
    }

    /// Which performances are of one work, across recordings: the
    /// composer's surname, and "symphony 5", else the catalogue number
    /// ("K 466"), else the work's folded name.
    public struct WorkKey: Hashable, Sendable {
        public var composer: String
        public var work: String
    }

    /// Consecutive tracks of one album with one work, the same performers
    /// and the same year: one recording of the work, played whole.
    public struct Performance: Hashable, Sendable {
        /// The work's name; for a track that is no part of a told work, its
        /// own title.
        public var work: String
        public var composer: String?
        public var catalogue: CatalogueNumber?
        public var key: WorkKey
        public var tracks: [Track]
        /// `parts[i]` is `tracks[i]`'s own part of the work.
        public var parts: [String]
    }

    // MARK: A track's work

    /// The work from the title alone: "Work: I. Movement", "Work - II.
    /// Movement", "Work: Act II. No. 14 …", "Opera: Overture", after a
    /// composer before a colon when `knownComposers` has that surname
    /// ("Beethoven: Symphony No. 5 - I. Allegro") and after a file's
    /// number ("01 - I. Allegro non troppo").
    public static func split(title: String, knownComposers: Set<String>) -> WorkPart {
        var title = title
        if let m = WorkPattern.trackPrefix.groups(title), let prefix = m[0] { title.removeFirst(prefix.count) }
        var composer: String?
        if let m = WorkPattern.composerPrefix.groups(title), let who = m[1], let rest = m[2],
           knownComposers.contains(surname(who)) {
            composer = who
            title = rest
        }
        if let m = WorkPattern.movement.groups(title), let work = m[1], let part = m[2] {
            return WorkPart(composer: composer, work: work.trimmingCharacters(in: .whitespaces),
                            part: part.trimmingCharacters(in: .whitespaces))
        }
        return WorkPart(composer: composer, work: composer == nil ? nil : title, part: title)
    }

    /// The work tag first, cut where Picard writes the movement's own work
    /// ("…, Op. 67: I. Allegro con brio"); else the title (`split`); else,
    /// for a title that is only a tempo ("Allegro con brio") on an album
    /// named like a work ("Symphony No. 5"), the album: Jellyfin drops the
    /// work tag Mp3tag wrote (measured).
    public static func workPart(of track: Track, knownComposers: Set<String>) -> WorkPart {
        var found = split(title: track.name, knownComposers: knownComposers)
        if var tagged = track.work?.trimmingCharacters(in: .whitespaces), !tagged.isEmpty {
            if let m = WorkPattern.movement.groups(tagged), let work = m[1] { tagged = work }
            found.work = tagged
        }
        if found.work == nil, WorkPattern.tempo.groups(found.part) != nil,
           let album = track.albumName, WorkPattern.formNumber.groups(album) != nil || CatalogueNumber.find(in: album) != nil {
            found.work = album
        }
        if let credited = track.credited(.composer).first { found.composer = credited.name }
        return found
    }

    // MARK: Performances

    /// The performances among `tracks`, in album order (album, disc, track,
    /// year, as works.py). The performers and the year are in the rule
    /// because Navidrome merges two albums of one name and album artist
    /// into one (measured): there the 1998 recording without disc numbers
    /// comes first, then the 2012 one as disc 1. ponytail: two merged
    /// recordings that both say disc 1 interleave and fall apart into
    /// single tracks; sort by year first within an album if a library
    /// shows that.
    public static func performances(_ tracks: [Track], knownComposers: Set<String>? = nil) -> [Performance] {
        let known = knownComposers ?? Self.knownComposers(in: tracks)
        let ordered = tracks.enumerated().sorted { a, b in
            let x = (a.element.albumID ?? "", a.element.discNumber ?? 0, a.element.trackNumber ?? 0,
                     a.element.year ?? 0, a.offset)
            let y = (b.element.albumID ?? "", b.element.discNumber ?? 0, b.element.trackNumber ?? 0,
                     b.element.year ?? 0, b.offset)
            return x < y
        }.map(\.element)

        struct Same: Equatable {
            var album: ItemID?, work: String, performers: Set<String>, year: Int?
        }
        var out: [Performance] = []
        var last: Same?
        for track in ordered {
            let found = workPart(of: track, knownComposers: known)
            let name = found.work ?? found.part
            let performers = Set((track.credited(.performer) + track.credited(.conductor) + track.artists).map(\.name))
            let same = Same(album: track.albumID, work: NameKey.fold(name), performers: performers, year: track.year)
            if found.work != nil, same == last, !out.isEmpty {
                out[out.count - 1].tracks.append(track)
                out[out.count - 1].parts.append(found.part)
            } else {
                out.append(Performance(work: name, composer: found.composer, catalogue: CatalogueNumber.find(in: name),
                                       key: workKey(composer: found.composer, work: name),
                                       tracks: [track], parts: [found.part]))
            }
            last = same
        }
        return out
    }

    /// ponytail: by surname, which mixes the Bachs and the Strausses; the
    /// composer's id (Navidrome has one for each) fixes that when a page
    /// needs it.
    public static func workKey(composer: String?, work: String) -> WorkKey {
        let who = composer.map(surname) ?? "?"
        if let m = WorkPattern.formNumber.groups(work), let form = m[1], let number = m[2] {
            let words = NameKey.fold(form).split(separator: " ").joined(separator: " ")
            return WorkKey(composer: who, work: "\(words) \(number)")
        }
        if let catalogue = CatalogueNumber.find(in: work) { return WorkKey(composer: who, work: catalogue.description) }
        return WorkKey(composer: who, work: NameKey.fold(work))
    }

    // MARK: Composers

    /// A name's surname as composers are compared: "Ludwig van Beethoven"
    /// and "Beethoven" are "beethoven"; "Bach, Johann Sebastian" is "bach".
    public static func surname(_ name: String) -> String {
        if let comma = name.firstIndex(of: ",") { return NameKey.fold(String(name[..<comma])) }
        return NameKey.fold(name.split(separator: " ").last.map(String.init) ?? name)
    }

    /// The surnames of every composer the library credits, and the common
    /// ones (`commonComposers`): who may stand before a colon in a title.
    public static func knownComposers(in tracks: [Track]) -> Set<String> {
        var known = commonComposers
        for track in tracks {
            for composer in track.credited(.composer) { known.insert(surname(composer.name)) }
        }
        return known
    }

    /// Composers a compilation names in its titles ("Dvořák: Symphony No.
    /// 9 …") without a composer tag anywhere. ponytail: the most played,
    /// not every one; surnames that are also common words (Pärt, Glass,
    /// Field, Wolf, Berg, Adams, Williams) are left out, as "Shattered
    /// Glass: Remix" would read as a composer. The library's own composer
    /// tags add the rest.
    public static let commonComposers: Set<String> = [
        "albeniz", "albinoni", "allegri", "alkan", "arensky", "auber", "bach", "barber", "bartok", "beethoven",
        "bellini", "berlioz", "bernstein", "biber", "bizet", "boccherini", "borodin", "boulez", "brahms",
        "britten", "bruch", "bruckner", "busoni", "buxtehude", "byrd", "chabrier", "charpentier", "chausson",
        "cherubini", "chopin", "cimarosa", "clementi", "copland", "corelli", "couperin", "czerny", "debussy",
        "delibes", "delius", "dohnanyi", "donizetti", "dowland", "dukas", "dutilleux", "dvorak", "elgar",
        "enescu", "falla", "faure", "franck", "gershwin", "gesualdo", "glazunov", "glinka", "gluck",
        "gorecki", "gounod", "granados", "grieg", "handel", "haendel", "haydn", "hindemith", "holst",
        "honegger", "hummel", "humperdinck", "ives", "janacek", "khachaturian", "kodaly", "korngold",
        "lalo", "lehar", "leoncavallo", "ligeti", "liszt", "lully", "lutoslawski", "mahler", "martinu",
        "mascagni", "massenet", "mendelssohn", "messiaen", "meyerbeer", "milhaud", "monteverdi", "mozart",
        "mussorgsky", "moussorgsky", "nielsen", "offenbach", "orff", "pachelbel", "paganini", "palestrina",
        "penderecki", "pergolesi", "poulenc", "prokofiev", "prokofieff", "puccini", "purcell",
        "rachmaninoff", "rachmaninov", "rameau", "ravel", "reger", "respighi", "rimsky-korsakov", "rodrigo",
        "rossini", "saint-saens", "salieri", "sarasate", "satie", "scarlatti", "schnittke", "schoenberg",
        "schubert", "schumann", "schutz", "scriabin", "shostakovich", "sibelius", "smetana", "spohr",
        "stockhausen", "strauss", "stravinsky", "suk", "suppe", "szymanowski", "tallis", "tchaikovsky",
        "tschaikowsky", "telemann", "tippett", "vaughan", "verdi", "vieuxtemps", "villa-lobos", "vivaldi",
        "wagner", "walton", "weber", "webern", "widor", "zelenka",
    ]

    // MARK: Which albums

    /// The albums among `tracks` that are classical: more than half their
    /// tracks are in a classical genre, or have a movement (the tag, or one
    /// in the title) or a catalogue number. Per album, not per library, so
    /// a pop library with three classical albums has three. A composer tag
    /// is no sign (pop has songwriters in COMPOSER), nor a work tag alone
    /// (Picard writes WORK for pop songs too).
    ///
    /// It runs on every Jellyfin load, pop libraries included, so each
    /// genre tag is folded once, not once a track, and the patterns run
    /// only where they can match.
    public static func classicalAlbumIDs(in tracks: [Track]) -> Set<ItemID> {
        var counts: [ItemID: (classical: Int, all: Int)] = [:]
        var genreIsClassical: [String: Bool] = [:]
        for track in tracks {
            guard let album = track.albumID else { continue }
            counts[album, default: (0, 0)].all += 1
            let byGenre = track.genres.contains { tag in
                if let known = genreIsClassical[tag] { return known }
                let classical = LibrarySnapshot.Index.splitGenreNames([tag])
                    .contains { classicalGenres.contains(NameKey.genre($0)) }
                genreIsClassical[tag] = classical
                return classical
            }
            if byGenre || hasMovementOrNumber(track) { counts[album, default: (0, 0)].classical += 1 }
        }
        return Set(counts.filter { $0.value.classical * 2 > $0.value.all }.keys)
    }

    /// A movement (the tag, or a marker in the title) or a catalogue number.
    static func hasMovementOrNumber(_ track: Track) -> Bool {
        if track.movement != nil { return true }
        // A movement needs a colon or a dash, a number a digit.
        let title = track.name
        if title.contains(":") || title.contains(" - ") || title.contains(" – ") || title.contains(" — "),
           split(title: title, knownComposers: []).work != nil { return true }
        if title.contains(where: \.isNumber), CatalogueNumber.find(in: title) != nil { return true }
        return track.work.flatMap(CatalogueNumber.find) != nil
    }

    /// NameKey.genre keys.
    static let classicalGenres: Set<String> = [
        "classical", "baroque", "opera", "chamber", "chambermusic", "orchestral", "earlymusic", "romantic",
        "contemporaryclassical", "modernclassical", "choral", "renaissance", "medieval",
    ]
}

/// A catalogue number as people search by it: "KV 466", "K. 466" and "K466"
/// are K 466; "Op. 67" and "op.67" Op 67; "D 957 No. 4" D 957/4; "Hob. I:94"
/// keeps its Roman part. Neither server folds these (measured: "KV 466"
/// finds nothing where the titles say "K. 466").
public struct CatalogueNumber: Hashable, Sendable, CustomStringConvertible {
    /// "K", "BWV", "Op", "Hob", …
    public var prefix: String
    /// "466", "I:94", "957/4".
    public var number: String

    public var description: String { "\(prefix) \(number)" }

    public init(prefix: String, number: String) {
        self.prefix = prefix
        self.number = number
    }

    /// The first catalogue number in a title or a work. The one-letter
    /// prefixes only as capitals, and D, S, L and M only with a full stop
    /// or a space ("D 957", "S. 178"), so "in D, BWV 1068" is BWV 1068 and
    /// a title naming M83 or L7 has none; K also without ("K466", as
    /// Mozart's numbers are often written: one with "K. 466" and "KV 466").
    public static func find(in text: String) -> CatalogueNumber? {
        guard let m = WorkPattern.catalogue.groups(text), let number = m[3] else { return nil }
        guard let prefix = m[1] ?? m[2] else { return nil }
        return make(prefix, number, m[4])
    }

    /// What someone typed, as the number it names: "kv466", "K. 466" and
    /// "Mozart K 466" are all "K 466"; nil when it names none. For search:
    /// the key `find(in:)` gives a title's number. Looser than `find`: any
    /// case, and "d957" too, which no title is read as.
    public static func normalize(_ query: String) -> String? {
        guard let m = WorkPattern.catalogueTyped.groups(query), let prefix = m[1], let number = m[2] else { return nil }
        return make(prefix, number, m[3])?.description
    }

    static func make(_ prefix: String, _ number: String, _ sub: String?) -> CatalogueNumber? {
        guard let canonical = prefixes[prefix.lowercased()] else { return nil }
        var number = number.replacingOccurrences(of: " ", with: "")
        if let colon = number.firstIndex(of: ":") {
            number = number[..<colon].uppercased() + number[colon...].lowercased()
        } else {
            number = number.lowercased()
        }
        if let sub { number += "/\(sub)" }
        return CatalogueNumber(prefix: canonical, number: number)
    }

    static let prefixes: [String: String] = [
        "bwv": "BWV", "buxwv": "BuxWV", "hwv": "HWV", "twv": "TWV", "rv": "RV", "kv": "K", "k": "K",
        "opus": "Op", "op": "Op", "hob": "Hob", "woo": "WoO", "d": "D", "sz": "Sz", "s": "S", "l": "L",
        "m": "M", "fp": "FP",
    ]
}

/// The patterns of works.py. NSRegularExpression is immutable and safe from
/// any thread (Apple's documentation); the wrapper says so to Swift 6 on
/// every platform. NSRegularExpression rather than Swift's Regex: 4× as
/// fast on Linux (1.1 against 4.7 µs a title, measured) and Sendable.
struct WorkPattern: @unchecked Sendable {
    let regex: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// The first match's groups (0: the whole match), nil for a group that
    /// took no part; nil when nothing matches.
    func groups(_ text: String) -> [String?]? {
        guard let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
    }

    /// A movement after the work, after ":" or a dash between spaces: a
    /// Roman numeral up to XII and a full stop, "Act II.", "Scene 3",
    /// "No. 14", Overture.
    static let movement = WorkPattern(
        #"^(.+?)(?::|\s[-–—]\s)\s*((?:(?:XII|XI|X|IX|VIII|VII|VI|V|IV|III|II|I)\.|(?i:Act) [IVX]+\.|(?i:Scene) \d+|(?i:No)\. ?\d+|(?i:Overture|Ouverture))\s*.*)$"#)
    /// "Beethoven: …": who may be a composer, before the first colon.
    static let composerPrefix = WorkPattern(#"^([^:]{2,40}):\s+(.+)$"#)
    /// A file's name as its title: "01 - ", "3. ".
    static let trackPrefix = WorkPattern(#"^\d{1,3}\s*[-.]\s+"#)
    /// "Symphony No. 5", "Piano Concerto No. 20", "Cello Suite no. 1".
    static let formNumber = WorkPattern(#"([A-Za-z][A-Za-z ]{2,30}?)\s+(?i:No)\.\s?(\d+)"#)
    /// A title that is only a tempo or a dance.
    static let tempo = WorkPattern(
        #"^(?:Allegro|Andante|Adagio|Largo|Presto|Lento|Vivace|Moderato|Scherzo|Menuett?o?|Rondo|Finale|Prélude|Prelude|Allemande|Courante|Sarabande|Gigue|Grave|Larghetto|Allegretto)\b"#,
        .caseInsensitive)

    private static let multiLetter = "BWV|BuxWV|HWV|TWV|RV|KV|Opus|Op|Hob|WoO|Sz|FP"
    private static let number = #"[IVX]+:\s?\d+[a-z]?|\d+[a-z]?"#
    /// In titles: 1 a prefix of more letters, any case; 2 a one-letter one,
    /// then a full stop or a space (K: or nothing); 3 the number; 4 "No. n".
    static let catalogue = WorkPattern(
        #"\b(?:((?i:\#(multiLetter)))\.?\s?|(K|D|S|L|M)(?:\.\s?|\s|(?<=K)))(\#(number))(?:,?\s+(?i:No)\.?\s?(\d+))?\b"#)
    /// As typed: any case, spaces and full stops optional. 1 the prefix,
    /// 2 the number, 3 "No. n".
    static let catalogueTyped = WorkPattern(
        #"\b(\#(multiLetter)|K|D|S|L|M)\.?\s?(\#(number))(?:,?\s+No\.?\s?(\d+))?\b"#, .caseInsensitive)
}
