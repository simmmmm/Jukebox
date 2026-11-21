// Which recording of a song a title says it is: "(Unplugged)", "[Live]",
// "(Remastered 2014)", " - Live at Wembley".
//
// For the version filter on an album's and a playlist's page. The
// photographer, 21 November 2026, on Oasis's "(What's The Story) Morning
// Glory? (30th Anniversary)", whose songs come twice, remastered and
// unplugged, without track numbers: "ik wil bijv alle unplugged nummers er
// uit kunnen filteren of alle remastered als ze er zijn zeg maar?".
//
// Only the title's end counts, and only words that name a recording: an
// unknown part ("(Part 2)", "(Reprise)", " - II. Andante") is the song's own
// name, and "(feat. X)" names a guest, not a version. The radio's
// `songKey` reads versions for another job (one song, whatever its
// recording) and matches more loosely; it stays as it is.

import Foundation

public struct TrackVersion: Hashable, Sendable {
    /// What the filter says: "Remastered", "Live", "Mono Version".
    public let name: String

    public init(name: String) { self.name = name }

    /// A song whose title names no recording.
    public static let original = TrackVersion(name: "Original")

    /// The version a title names, and the title without that part
    /// ("Cast No Shadow (Unplugged)": Unplugged, "Cast No Shadow"). An
    /// original keeps its whole title.
    public static func read(_ title: String) -> (version: TrackVersion, title: String) {
        let whole = title.trimmingCharacters(in: .whitespaces)
        var rest = whole
        // Guests after the version ("Song (Live) (feat. X)") stay in the title.
        var guests = ""
        while let group = trailingGroup(rest) {
            guard !isGuest(group.inner) else {
                guests = " " + group.text + guests
                rest = group.head
                continue
            }
            guard !group.head.isEmpty, let version = kind(group.inner) else { return (.original, whole) }
            return settle(version, head: group.head, guests: guests)
        }
        if let dash = rest.range(of: " - ", options: .backwards) {
            let head = rest[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, let version = kind(String(rest[dash.upperBound...])) {
                return settle(version, head: head, guests: guests)
            }
        }
        return (.original, whole)
    }

    /// The kinds a list of songs holds, for the filter: Original first, the
    /// others by name. None when there are fewer than two, as then there is
    /// nothing to choose.
    public static func kinds(of tracks: [Track]) -> [TrackVersion] {
        let found = Set(tracks.map { read($0.name).version })
        guard found.count > 1 else { return [] }
        let others = found.subtracting([.original]).sorted { $0.name < $1.name }
        return (found.contains(.original) ? [.original] : []) + others
    }

    /// The songs of one version, in the order they came (an album's order:
    /// by name when it has no track numbers); all of them for nil.
    public static func tracks(_ tracks: [Track], in version: TrackVersion?) -> [Track] {
        guard let version else { return tracks }
        return tracks.filter { read($0.name).version == version }
    }

    // MARK: Reading

    /// Two markers ("(Live) (Remastered 2014)"): the one that says more
    /// than a remaster, so the song is Live.
    private static func settle(_ version: TrackVersion, head: String, guests: String) -> (version: TrackVersion, title: String) {
        if version == remastered {
            let before = read(head)
            if before.version != .original { return (before.version, before.title + guests) }
        }
        return (version, head + guests)
    }

    private static let remastered = TrackVersion(name: "Remastered")

    /// The kinds the filter knows by name, the more telling first: an
    /// unplugged live set is Unplugged, an acoustic live take Acoustic.
    private static let known: [(words: Set<String>, version: TrackVersion)] = [
        (["unplugged"], TrackVersion(name: "Unplugged")),
        (["acoustic"], TrackVersion(name: "Acoustic")),
        (["live"], TrackVersion(name: "Live")),
        (["demo", "demos"], TrackVersion(name: "Demo")),
        (["instrumental"], TrackVersion(name: "Instrumental")),
        (["remix", "rmx", "mix"], TrackVersion(name: "Remix")),
        (["edit"], TrackVersion(name: "Edit")),
    ]

    /// Other words that name a recording; such a part is a kind of its own,
    /// by its own words without numbers ("Single Version", "Mono", "Take").
    private static let otherWords: Set<String> = [
        "version", "mono", "stereo", "extended", "take", "outtake", "alternate",
        "rehearsal", "session", "sessions", "orchestral", "piano", "acapella", "cappella", "karaoke",
    ]

    /// The version a marker's words name, or nil when they name none.
    private static func kind(_ text: String) -> TrackVersion? {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        for (keys, version) in known where !keys.isDisjoint(with: words) { return version }
        if words.contains(where: { $0.hasPrefix("remaster") }) { return remastered }
        guard !words.isDisjoint(with: otherWords) else { return nil }
        let name = text.split(separator: " ")
            .filter { !$0.allSatisfy(\.isNumber) }
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return name.isEmpty ? nil : TrackVersion(name: name)
    }

    private static func isGuest(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return ["feat", "ft.", "ft ", "featuring", "with "].contains { lower.hasPrefix($0) }
    }

    /// The bracketed part a title ends with: its words, the part itself and
    /// what comes before it.
    private static func trailingGroup(_ s: String) -> (inner: String, text: String, head: String)? {
        guard let last = s.last, last == ")" || last == "]" else { return nil }
        var depth = 0
        var i = s.endIndex
        while i > s.startIndex {
            i = s.index(before: i)
            let c = s[i]
            if c == ")" || c == "]" { depth += 1 }
            if c == "(" || c == "[" {
                depth -= 1
                if depth == 0 {
                    let inner = s[s.index(after: i)..<s.index(before: s.endIndex)]
                    return (String(inner), String(s[i...]), s[..<i].trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return nil
    }
}
