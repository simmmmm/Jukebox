// How a song sounds, from AcousticBrainz: recommendation 1 of
// docs/radio-alternatives.md ("ik zou het niet perse willen runnen maar de
// data ervan gebruiken om betere radio's te bouwen", the photographer, 20
// November 2026; "doe ze allemaal", 23 November 2026). Last.fm says who is
// near; this says what a song sounds like, so a piano station can tell
// Gorillaz apart where the tags call both "electronic".
//
// - ListenBrainz's lookup turns artist, title and album into a MusicBrainz
//   recording ID, fifty songs a call
//   (https://labs.api.listenbrainz.org/acrr-lookup, then acr-lookup without
//   the album);
// - AcousticBrainz gives that recording's high-level values, 25 a call
//   (https://acousticbrainz.org/api/v1/high-level). Frozen since 2022 and
//   CC0: an answer never goes stale.
// - No key, one call a second, a cache of a few numbers a song. Artist
//   names, song titles and album names go to MetaBrainz (PRIVACY.md).
// - Coverage, his library, 23 November 2026: 3 720 of 4 091 songs matched
//   (0.909), 3 007 with AcousticBrainz data (0.735), 2 026 of the 2 913
//   without a genre in the files.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A song's sound, 0 … 1 on each axis, as AcousticBrainz's classifiers
/// put it: the three of its twelve that set his piano artists apart from
/// Gorillaz, Angèle and Cocteau Twins (docs/RADIO.md, "How it sounds"):
/// acoustic 0.83 … 0.97 against 0.15 … 0.47, relaxed 0.89 … 1 against
/// 0.41 … 0.94, danceable 0 … 0.15 against 0.45 … 0.76. Its "electronic"
/// did not (0.27 … 0.67 against 0.42 … 0.73), nor "aggressive".
public struct SoundProfile: Codable, Sendable, Hashable {
    /// mood_acoustic: piano and strings near 1, Gorillaz near 0.
    public var acoustic: Double
    /// mood_relaxed: calm near 1, driving near 0.
    public var relaxed: Double
    /// danceability.
    public var danceable: Double

    public init(acoustic: Double, relaxed: Double, danceable: Double) {
        self.acoustic = acoustic
        self.relaxed = relaxed
        self.danceable = danceable
    }

    var axes: [Double] { [acoustic, relaxed, danceable] }
}

/// Looks songs up and keeps what came, in the account's Caches. Asks a
/// round at a time (`enrich`), quietly: a lookup that fails is tried again
/// next round, and the radio plays on without.
public actor SoundService {
    let directory: URL
    let transport: any HTTPTransport
    /// Between two requests: MetaBrainz asks for one a second.
    var minimumInterval: Duration = .seconds(1)
    /// A song that matched nothing, or a recording AcousticBrainz has no
    /// data for, is asked again after this: MusicBrainz grows.
    var missAge: TimeInterval = 90 * 86_400
    var currentDate: @Sendable () -> Date = { Date() }

    static let file = "acousticbrainz.json"
    static let version = 1

    struct Entry: Codable, Sendable, Hashable {
        var recording: String?
        var profile: SoundProfile?
        var fetched: Date
    }

    struct File: Codable, Sendable {
        var version: Int
        /// By song: the artist's key and the title's (`songKey`).
        var songs: [String: Entry]
    }

    private var songs: [String: Entry] = [:]
    private var loaded = false
    private var version = 0
    private var made: (index: LibrarySnapshot.Index, version: Int, profiles: [ItemID: SoundProfile])?

    public init(directory: URL, transport: any HTTPTransport = URLSessionTransport()) {
        self.directory = directory
        self.transport = transport
    }

    /// What is known of the library's songs, by track: every recording of
    /// a song gets the song's profile.
    public func profiles(for snapshot: LibrarySnapshot) -> [ItemID: SoundProfile] {
        load()
        if let made, made.index === snapshot.index, made.version == version { return made.profiles }
        var profiles: [ItemID: SoundProfile] = [:]
        for song in Self.songs(in: snapshot) {
            guard let profile = songs[song.key]?.profile else { continue }
            for i in song.members { profiles[snapshot.tracks[i].id] = profile }
        }
        made = (snapshot.index, version, profiles)
        return profiles
    }

    /// Looks up to `maxSongs` songs not asked yet (or missed long ago), the
    /// `priority` tracks' songs first. Returns `profiles(for:)`, and whether
    /// another round has songs to ask (none when this one stopped short:
    /// MetaBrainz did not answer, so not again until the next launch or
    /// library change).
    public func enrich(snapshot: LibrarySnapshot, priority: [ItemID] = [],
                       maxSongs: Int = 500) async -> (profiles: [ItemID: SoundProfile], more: Bool) {
        load()
        var due: [(key: String, artist: String, title: String, album: String)] = []
        var seen = Set<String>()
        let all = Self.songs(in: snapshot)
        let first = Set(priority.compactMap { snapshot.index.trackByID[$0].map { snapshot.index.trackSong[$0] } })
        let ordered = all.filter { first.contains($0.song) } + all.filter { !first.contains($0.song) }
        for (key, _, track, _) in ordered where due.count < maxSongs {
            guard seen.insert(key).inserted,
                  let artist = snapshot.primaryArtistKey(of: track).flatMap({ snapshot.artist(key: $0)?.name }) ?? track.primaryArtist?.name
            else { continue }
            if let known = songs[key], known.profile != nil || currentDate().timeIntervalSince(known.fetched) < missAge { continue }
            due.append((key, artist, track.name, track.albumName ?? ""))
        }
        guard !due.isEmpty else { return (profiles(for: snapshot), false) }

        // Recording IDs: with the album, then without it for the rest.
        var recordings: [String: String] = [:]
        for batch in Self.chunks(due, 50) {
            guard let found = await lookup("acrr-lookup", batch.map {
                ["artist_credit_name": $0.artist, "recording_name": $0.title, "release_name": $0.album]
            }) else { return (finish(snapshot), false) }
            for (i, id) in found where batch.indices.contains(i) { recordings[batch[i].key] = id }
        }
        let unmatched = due.filter { recordings[$0.key] == nil }
        for batch in Self.chunks(unmatched, 50) {
            guard let found = await lookup("acr-lookup", batch.map { ["artist_credit_name": $0.artist, "recording_name": $0.title] })
            else { return (finish(snapshot), false) }
            for (i, id) in found where batch.indices.contains(i) { recordings[batch[i].key] = id }
        }
        // Their sound.
        let ids = Array(Set(recordings.values)).sorted()
        var sound: [String: SoundProfile] = [:]
        var answered = Set<String>()
        var complete = true
        for batch in Self.chunks(ids, 25) {
            guard let found = await highLevel(batch) else {
                complete = false
                break
            }
            sound.merge(found) { a, _ in a }
            answered.formUnion(batch)
        }
        let now = currentDate()
        for song in due {
            let id = recordings[song.key]
            // A recording whose sound was not asked (the round stopped) is
            // asked again next round.
            if let id, !answered.contains(id) { continue }
            songs[song.key] = Entry(recording: id, profile: id.flatMap { sound[$0] }, fetched: now)
        }
        return (finish(snapshot), complete && due.count == maxSongs)
    }

    // MARK: - For the tests

    func setPacing(_ interval: Duration) { minimumInterval = interval }
    func setDate(_ date: @escaping @Sendable () -> Date) { currentDate = date }

    // MARK: - Inside

    private func finish(_ snapshot: LibrarySnapshot) -> [ItemID: SoundProfile] {
        version += 1
        save()
        return profiles(for: snapshot)
    }

    /// The library's songs (LibrarySnapshot's: "Eden", "Eden (Live)" and
    /// the best-of's copy are one), each asked once by its shortest title,
    /// and kept by the artist it is filed under and that title.
    static func songs(in snapshot: LibrarySnapshot) -> [(key: String, song: Int, track: Track, members: [Int])] {
        let index = snapshot.index
        var made: [(key: String, song: Int, track: Track, members: [Int])] = []
        for (song, members) in index.songTracks.enumerated() {
            guard let shortest = members.min(by: { snapshot.tracks[$0].name.count < snapshot.tracks[$1].name.count }) else { continue }
            let track = snapshot.tracks[shortest]
            guard let artist = snapshot.primaryArtistKey(of: track), !artist.isEmpty else { continue }
            let title = NameKey.title(track.name)
            guard !title.isEmpty else { continue }
            made.append((artist + "|" + title, song, track, members))
        }
        return made
    }

    /// Arrays, not slices: the lookup answers by the position in the batch
    /// it was sent (0, 1, …), and a slice from the second batch on starts
    /// at 50. `batch[i]` there trapped, the app gone a second after Better
    /// Radio's Turn On, on any library of more than 50 songs ("crashed als
    /// je better radio ja zegt", the photographer, 23 November 2026).
    static func chunks<T>(_ items: [T], _ size: Int) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    private var nextSlot: ContinuousClock.Instant?

    private func waitForSlot() async -> Bool {
        let clock = ContinuousClock()
        let slot = max(clock.now, nextSlot ?? clock.now)
        nextSlot = slot.advanced(by: minimumInterval)
        if slot > clock.now { try? await clock.sleep(until: slot, tolerance: nil) }
        return !Task.isCancelled
    }

    private func send(_ request: URLRequest) async -> Data? {
        guard await waitForSlot(), let response = try? await transport.send(request),
              (200..<300).contains(response.status) else { return nil }
        return response.body
    }

    static let userAgent = "Jukebox/1.3 (music player; radio)"

    /// The lookup's answer, by the position asked: nil when it did not
    /// answer, so the round stops.
    private func lookup(_ name: String, _ rows: [[String: String]]) async -> [Int: String]? {
        guard let url = URL(string: "https://labs.api.listenbrainz.org/\(name)/json"),
              let body = try? JSONSerialization.data(withJSONObject: rows) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let data = await send(request),
              let answer = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var found: [Int: String] = [:]
        for row in answer {
            guard let i = row["index"] as? Int, let id = row["recording_mbid"] as? String, !id.isEmpty else { continue }
            found[i] = id
        }
        return found
    }

    /// The profiles AcousticBrainz has of these recordings; nil when it
    /// did not answer.
    private func highLevel(_ ids: [String]) async -> [String: SoundProfile]? {
        guard let url = URL(string: "https://acousticbrainz.org/api/v1/high-level?recording_ids=" + ids.joined(separator: ";"))
        else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let data = await send(request),
              let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // A recording merged into another answers under that one.
        let mapping = answer["mbid_mapping"] as? [String: String] ?? [:]
        var found: [String: SoundProfile] = [:]
        for id in ids {
            guard let doc = (answer[id] ?? mapping[id].flatMap { answer[$0] }) as? [String: Any],
                  let first = doc["0"] as? [String: Any],
                  let profile = Self.profile(first["highlevel"] as? [String: Any]) else { continue }
            found[id] = profile
        }
        return found
    }

    /// {"mood_acoustic": {"all": {"acoustic": 0.93, "not_acoustic": 0.07}, …}, …}
    static func profile(_ highLevel: [String: Any]?) -> SoundProfile? {
        func value(_ name: String, _ positive: String) -> Double? {
            guard let all = (highLevel?[name] as? [String: Any])?["all"] as? [String: Any],
                  // A number as JSON has it: 1 reads as an integer.
                  let number = (all[positive] as? NSNumber)?.doubleValue, number.isFinite else { return nil }
            return min(1, max(0, number))
        }
        guard let acoustic = value("mood_acoustic", "acoustic"), let relaxed = value("mood_relaxed", "relaxed"),
              let danceable = value("danceability", "danceable") else { return nil }
        return SoundProfile(acoustic: acoustic, relaxed: relaxed, danceable: danceable)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(Self.file)),
              let file = try? decoder.decode(File.self, from: data), file.version == Self.version else { return }
        songs = file.songs
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(File(version: Self.version, songs: songs)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(Self.file), options: .atomic)
    }
}
