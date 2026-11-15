// A fake Jellyfin for the screenshots: serves the demo library (dev/demo/,
// recorded once from the test server of dev/jellyfin-test-server.sh) to the
// app in the iOS Simulator on CI, where there is no Docker and so no real
// Jellyfin, and to Linux's walk (dev/linux-screens.sh).
//
//   swiftc -O -parse-as-library dev/fake-jellyfin.swift \
//     JukeboxKit/Sources/JukeboxKit/Subsonic/MD5.swift -o build/fake-jellyfin
//   build/fake-jellyfin --port 8096 --data dev/demo
//   build/fake-jellyfin --song-lengths    2:30–5:30 songs, for the pictures
//   build/fake-jellyfin --slow-downloads  0.4–2 s a song downloaded, so its ring shows
//
// Foundation only, one file and the kit's MD5: Xcode's swiftc builds it on
// the macOS runner, the image of dev/linux-build.sh on Linux. It was Python
// until 15 November 2026 ("al die python troep hoeft niet in de repo te
// staan"); it answers as that did, request for request.
//
// It answers every route JukeboxKit's JellyfinClient uses, the way Jellyfin
// 12.4 does where the client depends on it (each measured on the test server;
// the client's own comments say how): filters, sorts and pages as /Items does;
// only the fields asked for; the play count going up at the start report; the
// user's favourites and playlists changing, in memory, until it stops; images
// by id at any size; the audio with byte ranges, as AVPlayer asks for it.
// Signing in takes the recorded user's name with the password ("test"); Quick
// Connect is off. A route it does not know is logged as UNKNOWN ROUTE and
// answered 404, so what is missing shows in the log.
//
// The sign-in screen asks every address both ways at once (JukeboxKit's
// MusicServers.detect): Jellyfin's /System/Info/Public and Subsonic's
// /rest/ping.view. The fake answers the second as Jellyfin 12.4 does, measured
// on the test server: 404 with no body, which the kit reads as "not a Subsonic
// server", so the Jellyfin answer wins. It is a known route, not an UNKNOWN one.
//
// Deliberately unlike Jellyfin:
// - Any token is taken until it is signed out, not only the ones it gave: the
//   UI tests may sign in with a token of their own, and a restarted fake keeps
//   the app signed in.
// - Every track plays one of four 8-second AAC clips, looped to the length the
//   track says (Clip, below), and nothing is transcoded: a bitrate limit gets
//   the same file, never HLS.
// - Images are 600×600 whatever size is asked.
// - Dates move with the clock: the library is as fresh as the day it was
//   recorded (things played "yesterday" stay yesterday).

import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

typealias Obj = [String: Any]
let ticksPerSecond = 10_000_000

let logLock = NSLock()

func log(_ line: String) {
    var now = time(nil)
    var parts = tm()
    localtime_r(&now, &parts)
    let stamp = String(format: "%02d:%02d:%02d ", parts.tm_hour, parts.tm_min, parts.tm_sec)
    logLock.lock()
    print(stamp + line)
    fflush(stdout)
    logLock.unlock()
}

struct HTTPError: Error {
    let status: Int
    var detail: String? = nil
}

/// What Python called a KeyError or a ValueError: the fake failing, a 500.
struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - JSON values, as Python reads them

func text(_ value: Any?) -> String? { value as? String }

func int(_ value: Any?) -> Int? {
    if value is NSNull { return nil }
    if let number = value as? Int { return number }
    if let number = value as? NSNumber { return number.intValue }
    return nil
}

/// Python's bool(): None, False, 0, "" and empty lists and dicts are false.
func truthy(_ value: Any?) -> Bool {
    guard let value, !(value is NSNull) else { return false }
    if let flag = value as? Bool { return flag }
    if let number = value as? NSNumber { return number.doubleValue != 0 }
    if let string = value as? String { return !string.isEmpty }
    if let list = value as? [Any] { return !list.isEmpty }
    if let object = value as? Obj { return !object.isEmpty }
    return true
}

func list(_ value: Any?) -> [Any] { value as? [Any] ?? [] }
func objects(_ value: Any?) -> [Obj] { list(value).compactMap { $0 as? Obj } }
func strings(_ value: Any?) -> [String] { list(value).compactMap { $0 as? String } }

func json(_ value: Any) -> [UInt8] {
    // UTF-8 as it is and no spaces, as the Python wrote it.
    (try? Array(JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .fragmentsAllowed])))
        ?? Array("null".utf8)
}

func parseJSON(_ bytes: [UInt8]) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])
}

/// A JSON string as Python's json.dumps writes it (ASCII only).
func quoted(_ string: String) -> String {
    var out = "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case _ where scalar.value < 0x20 || scalar.value > 0x7e:
            for unit in String(scalar).utf16 { out += String(format: "\\u%04x", unit) }
        default: out.unicodeScalars.append(scalar)
        }
    }
    return out + "\""
}

// MARK: - Dates, as Jellyfin writes them: seven fractional digits and a Z

/// Microseconds since 1970, UTC.
func parseDate(_ raw: String) -> Int64? {
    var string = Substring(raw)
    while string.hasSuffix("Z") { string.removeLast() }
    var micro: Int64 = 0
    if let dot = string.firstIndex(of: ".") {
        guard let fraction = Int64(String((string[string.index(after: dot)...] + "000000").prefix(6))) else { return nil }
        micro = fraction
        string = string[..<dot]
    }
    let fields = string.split(whereSeparator: { $0 == "-" || $0 == "T" || $0 == ":" }).compactMap { Int($0) }
    guard fields.count == 6 else { return nil }
    var parts = tm()
    parts.tm_year = Int32(fields[0] - 1900)
    parts.tm_mon = Int32(fields[1] - 1)
    parts.tm_mday = Int32(fields[2])
    parts.tm_hour = Int32(fields[3])
    parts.tm_min = Int32(fields[4])
    parts.tm_sec = Int32(fields[5])
    return Int64(timegm(&parts)) * 1_000_000 + micro
}

func formatDate(_ micro: Int64) -> String {
    var seconds = time_t(micro >= 0 ? micro / 1_000_000 : (micro - 999_999) / 1_000_000)
    let rest = micro - Int64(seconds) * 1_000_000
    var parts = tm()
    gmtime_r(&seconds, &parts)
    return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%06d0Z", parts.tm_year + 1900, parts.tm_mon + 1,
                  parts.tm_mday, parts.tm_hour, parts.tm_min, parts.tm_sec, Int32(rest))
}

func nowMicro() -> Int64 {
    var now = timeval()
    gettimeofday(&now, nil)
    return Int64(now.tv_sec) * 1_000_000 + Int64(now.tv_usec)
}

func nowDate() -> String { formatDate(nowMicro()) }

func shifted(_ value: Any?, by delta: Int64) -> Any? {
    // Year 1 is Jellyfin's "never" (DateLastMediaAdded): left alone.
    guard let string = value as? String, string.hasPrefix("19") || string.hasPrefix("20"),
          let moment = parseDate(string) else { return value }
    return formatDate(moment + delta)
}

/// Jellyfin takes ids with and without dashes, in any case.
func norm(_ id: Any?) -> String {
    ((id as? String) ?? "").replacingOccurrences(of: "-", with: "").lowercased()
}

/// For comparing names: no case, no accents.
func fold(_ value: String?) -> String {
    var out = String.UnicodeScalarView()
    for scalar in (value ?? "").decomposedStringWithCompatibilityMapping.unicodeScalars
    where scalar.properties.canonicalCombiningClass == .notReordered {
        out.append(scalar)
    }
    return String(out).lowercased()
}

func newID() -> String { UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") }

/// Python's str(uuid.UUID(hex)): the dashed form.
func dashed(_ hex: String) -> String {
    var out = ""
    for (index, character) in hex.enumerated() {
        if [8, 12, 16, 20].contains(index) { out += "-" }
        out.append(character)
    }
    return out
}

/// Percent-decoding as Python's unquote: invalid UTF-8 becomes U+FFFD.
func unquote(_ string: String, plus: Bool = false) -> String {
    let bytes = Array(string.utf8)
    var out: [UInt8] = []
    var index = 0
    func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
    while index < bytes.count {
        let byte = bytes[index]
        if byte == 37, index + 2 < bytes.count, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) {
            out.append(high << 4 | low)
            index += 3
        } else {
            out.append(plus && byte == 43 ? 32 : byte)
            index += 1
        }
    }
    return String(decoding: out, as: UTF8.self)
}

/// Python's slice a[start:end] for a start of 0 or more.
func slice<T>(_ array: [T], _ start: Int, _ end: Int?) -> [T] {
    let count = array.count
    var stop = end ?? count
    if stop < 0 { stop += count }
    let from = min(start, count), to = max(from, min(stop, count))
    return Array(array[from..<to])
}

/// The query string; names in any case, as ASP.NET binds them.
struct Query {
    var values: [String: [String]] = [:]

    init(_ raw: String) {
        for part in raw.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = unquote(String(pair[0]), plus: true).lowercased()
            values[key, default: []].append(pair.count > 1 ? unquote(String(pair[1]), plus: true) : "")
        }
    }

    func get(_ name: String) -> String? { values[name.lowercased()]?.last }

    func list(_ name: String, separator: Character = ",") -> [String] {
        (values[name.lowercased()] ?? []).flatMap { value in
            value.split(separator: separator, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    func flag(_ name: String) -> Bool? { get(name).map { $0.lowercased() == "true" } }

    func number(_ name: String) -> Int? {
        get(name).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

// MARK: - Python's random, for the same shuffles from the same seed

/// MT19937 seeded as Python's random.Random(int) seeds it, and its
/// shuffle: SortBy=Random and the instant mixes come out in the order the
/// Python fake gave them.
struct PythonRandom {
    private var state = [UInt32](repeating: 0, count: 624)
    private var index = 624

    init(seed: Int) {
        var key: [UInt32] = []
        var rest = seed.magnitude
        repeat {
            key.append(UInt32(truncatingIfNeeded: rest))
            rest >>= 32
        } while rest > 0
        state[0] = 19_650_218
        for i in 1..<624 {
            state[i] = 1_812_433_253 &* (state[i - 1] ^ (state[i - 1] >> 30)) &+ UInt32(i)
        }
        var i = 1, j = 0
        for _ in 0..<max(624, key.count) {
            state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_664_525)) &+ key[j] &+ UInt32(j)
            i += 1
            j += 1
            if i >= 624 { state[0] = state[623]; i = 1 }
            if j >= key.count { j = 0 }
        }
        for _ in 0..<623 {
            state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_566_083_941)) &- UInt32(i)
            i += 1
            if i >= 624 { state[0] = state[623]; i = 1 }
        }
        state[0] = 0x8000_0000
    }

    private mutating func next() -> UInt32 {
        if index >= 624 {
            for k in 0..<624 {
                let y = (state[k] & 0x8000_0000) | (state[(k + 1) % 624] & 0x7fff_ffff)
                state[k] = state[(k + 397) % 624] ^ (y >> 1) ^ (y & 1 == 0 ? 0 : 0x9908_b0df)
            }
            index = 0
        }
        var y = state[index]
        index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9d2c_5680
        y ^= (y << 15) & 0xefc6_0000
        y ^= y >> 18
        return y
    }

    /// _randbelow: as many bits as n has, again until under n.
    private mutating func below(_ n: Int) -> Int {
        let bits = Int.bitWidth - n.leadingZeroBitCount
        while true {
            let r = bits == 0 ? 0 : Int(next() >> (32 - UInt32(bits)))
            if r < n { return r }
        }
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        var i = array.count - 1
        while i >= 1 {
            array.swapAt(i, below(i + 1))
            i -= 1
        }
    }
}

// MARK: - Sorting as Python sorts: stable, ties kept in order either way

enum Key {
    case text(String), number(Int)

    static func compare(_ a: Key, _ b: Key) -> Int {
        switch (a, b) {
        case let (.text(x), .text(y)):
            // Code point by code point, as Python compares str.
            if x.unicodeScalars.elementsEqual(y.unicodeScalars) { return 0 }
            return x.unicodeScalars.lexicographicallyPrecedes(y.unicodeScalars) ? -1 : 1
        case let (.number(x), .number(y)): return x == y ? 0 : x < y ? -1 : 1
        case (.number, .text): return -1
        case (.text, .number): return 1
        }
    }

    static func compare(_ a: [Key], _ b: [Key]) -> Int {
        for (x, y) in zip(a, b) {
            let order = compare(x, y)
            if order != 0 { return order }
        }
        return a.count == b.count ? 0 : a.count < b.count ? -1 : 1
    }
}

func stableSorted(_ pool: [Obj], descending: Bool = false, by key: (Obj) -> [Key]) -> [Obj] {
    pool.enumerated().map { (offset: $0.offset, key: key($0.element), item: $0.element) }
        .sorted { a, b in
            let order = Key.compare(a.key, b.key)
            if order != 0 { return descending ? order > 0 : order < 0 }
            return a.offset < b.offset
        }
        .map(\.item)
}

// MARK: - The audio: an 8-second clip, as long as the track says

func fourCC(_ name: String) -> [UInt8] { Array(name.utf8) }

/// MP4 boxes that hold other boxes, on the way to the sample tables.
let containers: Set<[UInt8]> = Set(["moov", "trak", "mdia", "minf", "stbl", "edts"].map(fourCC))

struct Box {
    var kind: [UInt8]
    var data: [UInt8] = []
    var children: [Box]? = nil
}

func be32(_ bytes: [UInt8], _ at: Int) throws -> UInt32 {
    guard at >= 0, at + 4 <= bytes.count else { throw Failure("unpack requires a buffer of 4 bytes") }
    return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
}

func be32(_ values: [Int]) throws -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(values.count * 4)
    for value in values {
        guard value >= 0, value <= Int(UInt32.max) else { throw Failure("'I' format requires 0 <= number <= 4294967295") }
        out += [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]
    }
    return out
}

func put32(_ bytes: inout [UInt8], _ at: Int, _ value: Int) throws {
    guard at >= 0, at + 4 <= bytes.count else { throw Failure("pack_into requires a buffer of at least \(at + 4) bytes") }
    bytes.replaceSubrange(at..<at + 4, with: try be32([value]))
}

func describe(_ kind: [UInt8]) -> String { "b'" + String(decoding: kind, as: UTF8.self) + "'" }

/// A container's payload parsed in turn.
func parseBoxes(_ data: [UInt8], _ start: Int, _ end: Int) throws -> [Box] {
    var out: [Box] = []
    var at = start
    while at < end {
        guard at + 8 <= data.count else { throw Failure("unpack requires a buffer of 8 bytes") }
        let size = Int(try be32(data, at))
        let kind = Array(data[at + 4..<at + 8])
        if size < 8 || at + size > end { throw Failure("a box the fake does not read: \(describe(kind))") }
        if containers.contains(kind) {
            out.append(Box(kind: kind, children: try parseBoxes(data, at + 8, at + size)))
        } else {
            out.append(Box(kind: kind, data: Array(data[at + 8..<at + size])))
        }
        at += size
    }
    return out
}

func buildBoxes(_ tree: [Box]) throws -> [UInt8] {
    var out: [UInt8] = []
    for box in tree {
        let payload = try box.children.map(buildBoxes) ?? box.data
        out += try be32([8 + payload.count]) + box.kind + payload
    }
    return out
}

/// The first box at the path of types.
func findBox(_ tree: [Box], _ path: [String]) throws -> Box {
    guard let first = path.first, let box = tree.first(where: { $0.kind == fourCC(first) }) else {
        throw Failure("(\(path.map { describe(fourCC($0)) }.joined(separator: ", ")),)")
    }
    return path.count == 1 ? box : try findBox(box.children ?? [], Array(path.dropFirst()))
}

func updateBox(_ tree: inout [Box], _ path: [String], _ change: (inout Box) throws -> Void) throws {
    guard let first = path.first, let index = tree.firstIndex(where: { $0.kind == fourCC(first) }) else {
        throw Failure("(\(path.map { describe(fourCC($0)) }.joined(separator: ", ")),)")
    }
    if path.count == 1 {
        try change(&tree[index])
    } else {
        var children = tree[index].children ?? []
        try updateBox(&children, Array(path.dropFirst()), change)
        tree[index].children = children
    }
}

/// One of the demo's clips, served as long as the track it stands for.
///
/// Why: a song that says 3:42 (--song-lengths) but ends after 8 s is, to
/// the app, a skip (PlayOutcome: under 30 s heard of a long song), so the
/// radio would learn from skips the listener never made, Now Playing's
/// scrubber would read 0:08 (it takes the length AVPlayer finds in the
/// file), and the queue would move on every 8 s while the screenshot walk
/// is taking its pictures.
///
/// How: the clip's AAC frames, repeated, in a new MP4 of the same shape as
/// the one ffmpeg wrote (one track, one chunk, the encoder's 1024 priming
/// samples skipped by the edit list, a roll group over every sample). The
/// first frame primes the decoder once; frames 1 to the last full one then
/// loop, so the first 8 s are the clip's own bytes and each seam is a fade
/// out meeting a fade in. The sample tables and the durations are written
/// for the new length; nothing is re-encoded. A clip in another shape is
/// served as it is, 8 s, and the log says why.
final class Clip {
    let name: String
    let data: [UInt8]
    var ok = false
    var rate = 0, priming = 0, frame = 0, loop = 0
    var frames: [[UInt8]] = []
    var tree: [Box] = []

    /// The last eight files made, of every clip (Python's lru_cache of 8).
    static var made: [(name: String, seconds: Int, file: [UInt8])] = []

    init(name: String, data: [UInt8]) {
        self.name = name
        self.data = data
        do {
            try read()
            ok = true
        } catch {
            log("audio/\(name).m4a is served as it is, 8 s whatever the track says: \(error)")
        }
    }

    func read() throws {
        let tree = try parseBoxes(data, 0, data.count)
        let moov = try findBox(tree, ["moov"]).children ?? []
        if moov.filter({ $0.kind == fourCC("trak") }).count != 1 { throw Failure("not one track") }
        // Version 0 of each: their durations are 32 bits at the offsets file() writes.
        for path in [["mvhd"], ["trak", "tkhd"], ["trak", "mdia", "mdhd"]] {
            if try findBox(moov, path).data.first != 0 { throw Failure("\(path.last!) is not version 0") }
        }
        let stbl = try findBox(moov, ["trak", "mdia", "minf", "stbl"]).children ?? []
        rate = Int(try be32(findBox(moov, ["trak", "mdia", "mdhd"]).data, 12))
        let elst = try findBox(moov, ["trak", "edts", "elst"]).data
        if try elst.first != 0 || be32(elst, 4) != 1 { throw Failure("not one version-0 edit") }
        priming = Int(Int32(bitPattern: try be32(elst, 12)))
        let stts = try findBox(stbl, ["stts"]).data
        var deltas: [Int] = []
        for k in 0..<Int(try be32(stts, 4)) {
            let count = Int(try be32(stts, 8 + 8 * k)), delta = Int(try be32(stts, 12 + 8 * k))
            deltas += repeatElement(delta, count: count)
        }
        let stsz = try findBox(stbl, ["stsz"]).data
        let fixed = Int(try be32(stsz, 4)), count = Int(try be32(stsz, 8))
        let sizes = fixed != 0 ? Array(repeating: fixed, count: count)
            : try (0..<count).map { Int(try be32(stsz, 12 + 4 * $0)) }
        let stsc = try findBox(stbl, ["stsc"]).data
        let stco = try findBox(stbl, ["stco"]).data
        if try be32(stsc, 4) != 1 || be32(stco, 4) != 1 || Int(be32(stsc, 12)) != count || deltas.count != count {
            throw Failure("not one chunk of every sample")
        }
        var offset = Int(try be32(stco, 8))
        guard let first = deltas.first else { throw Failure("list index out of range") }
        frame = first
        frames = sizes.map { size in
            // Short at the end, as a Python slice is.
            let from = min(offset, data.count), to = min(offset + size, data.count)
            offset += size
            return Array(data[from..<to])
        }
        // Frame 0 is the priming; the loop is 1 … the last of full length.
        loop = 1
        while loop < count && deltas[loop] == frame { loop += 1 }
        if priming != frame || loop < 2 {
            throw Failure("priming of \(priming) samples, \(loop - 1) full frames")
        }
        // One group over every sample, as ffmpeg writes it for AAC, or none.
        if let sbgp = stbl.first(where: { $0.kind == fourCC("sbgp") })?.data,
           try sbgp.first != 0 || be32(sbgp, 8) != 1 {
            throw Failure("a sample group of another shape")
        }
        self.tree = tree
    }

    /// The MP4 for a track of `seconds` (whole seconds are enough: the app
    /// shows minutes and seconds); the clip as it is if that fails.
    func file(_ seconds: Int) -> [UInt8] {
        if let index = Clip.made.firstIndex(where: { $0.name == name && $0.seconds == seconds }) {
            let hit = Clip.made.remove(at: index)
            Clip.made.append(hit)
            return hit.file
        }
        var file = data
        if ok && seconds > 0 {
            do {
                file = try looped(seconds)
            } catch {
                log("audio/\(name).m4a served as it is for \(seconds) s: \(error)")
            }
        }
        Clip.made.append((name, seconds, file))
        if Clip.made.count > 8 { Clip.made.removeFirst() }
        return file
    }

    func looped(_ seconds: Int) throws -> [UInt8] {
        let samples = seconds * rate
        let needed = (samples + frame - 1) / frame
        let order = [0] + (0..<needed).map { 1 + $0 % (loop - 1) }
        let chosen = order.map { frames[$0] }
        let movieScale = Int(try be32(findBox(tree, ["moov", "mvhd"]).data, 12))
        let length = seconds * movieScale

        // ftyp and moov ('free' and the old mdat left out), copied, so the
        // clip's own tree stays as it is for the next length.
        var tree = self.tree.filter { $0.kind == fourCC("ftyp") || $0.kind == fourCC("moov") }
        func patch(_ path: [String], _ at: Int, _ value: Int) throws {
            try updateBox(&tree, ["moov"] + path) { try put32(&$0.data, at, value) }
        }
        try patch(["mvhd"], 16, length)
        try patch(["trak", "tkhd"], 20, length)
        try patch(["trak", "edts", "elst"], 8, length)
        try patch(["trak", "mdia", "mdhd"], 16, chosen.count * frame)
        let stbl = ["moov", "trak", "mdia", "minf", "stbl"]
        let stts = try be32([0, 1, chosen.count, frame])
        try updateBox(&tree, stbl + ["stts"]) { $0.data = stts }
        let stsc = try be32([0, 1, 1, chosen.count, 1])
        try updateBox(&tree, stbl + ["stsc"]) { $0.data = stsc }
        let stsz = try be32([0, 0, chosen.count] + chosen.map(\.count))
        try updateBox(&tree, stbl + ["stsz"]) { $0.data = stsz }
        try updateBox(&tree, stbl) { table in
            // Its one entry now counts every sample (read() checked the shape).
            if let index = table.children?.firstIndex(where: { $0.kind == fourCC("sbgp") }) {
                try put32(&table.children![index].data, 12, chosen.count)
            }
        }
        let empty = try be32([0, 1, 0])
        try updateBox(&tree, stbl + ["stco"]) { $0.data = empty }
        var head = try buildBoxes(tree)
        let start = try be32([0, 1, head.count + 8])
        try updateBox(&tree, stbl + ["stco"]) { $0.data = start }
        head = try buildBoxes(tree)
        var out = head
        let payloadSize = chosen.reduce(0) { $0 + $1.count }
        out.reserveCapacity(head.count + 8 + payloadSize)
        out += try be32([8 + payloadSize]) + fourCC("mdat")
        for frame in chosen { out += frame }
        return out
    }
}

// MARK: - The library and what the user changes in it

final class Library {
    let folder: String
    let password: String
    var rng: PythonRandom
    var lyrics: [String: Obj] = [:]
    let publicInfo: Obj
    let serverID: String
    var user: Obj
    let signIn: Obj
    let views: [Obj]
    let template: Obj
    /// {type: {field: [keys]}}: what each field adds, so what to leave out.
    let fields: [String: [String: [String]]]

    var items: [String: Obj] = [:]
    var userdata: [String: Obj] = [:]
    var order: [String] = []
    let albumArtists: Set<String>
    let similar: [String: [String]]
    var entries: [String: [String]]
    let audio: [String: String]
    var tracks: [String] = []
    var albumTracks: [String: [String]] = [:]

    var revoked = Set<String>()
    var deviceTokens: [String: String] = [:]
    var files: [String: [UInt8]] = [:]
    var clips: [String: Clip] = [:]
    /// --clips-as-recorded: every track the 8-second clip itself.
    var clipsAsRecorded = false
    /// --slow-downloads: a song downloaded takes 0.4 to 2 s.
    var slowDownloads = false

    init(folder: String, songLengths: Bool, seed: Int, password: String) throws {
        self.folder = folder
        self.password = password
        rng = PythonRandom(seed: seed)
        func load(_ name: String) throws -> Any {
            try parseJSON(Array(try Data(contentsOf: URL(fileURLWithPath: folder + "/" + name))))
        }
        let server = try load("server.json") as? Obj ?? [:]
        let recorded = objects((try load("items.json") as? Obj)?["Items"])
        let relations = try load("relations.json") as? Obj ?? [:]
        var lyrics: [String: Obj] = [:]
        for (key, value) in try load("lyrics.json") as? Obj ?? [:] {
            lyrics[norm(key)] = value as? Obj
        }
        self.lyrics = lyrics

        guard let recordedAt = text(server["recordedAt"]).flatMap(parseDate) else { throw Failure("recordedAt") }
        let delta = nowMicro() - recordedAt
        publicInfo = server["publicInfo"] as? Obj ?? [:]
        serverID = text(publicInfo["Id"]) ?? ""
        var user = server["user"] as? Obj ?? [:]
        for key in ["LastLoginDate", "LastActivityDate"] where user[key] != nil {
            user[key] = shifted(user[key], by: delta)
        }
        self.user = user
        signIn = server["signIn"] as? Obj ?? [:]
        views = objects(server["views"])
        template = server["playlistTemplate"] as? Obj ?? [:]
        var fields: [String: [String: [String]]] = [:]
        for (kind, gated) in server["fields"] as? Obj ?? [:] {
            var lowered: [String: [String]] = [:]
            for (field, keys) in gated as? Obj ?? [:] { lowered[field.lowercased()] = strings(keys) }
            fields[kind] = lowered
        }
        self.fields = fields

        var items: [String: Obj] = [:], userdata: [String: Obj] = [:], order: [String] = []
        for var item in recorded {
            for key in ["DateCreated", "DateLastMediaAdded"] where item[key] != nil {
                item[key] = shifted(item[key], by: delta)
            }
            let id = text(item["Id"]) ?? ""
            if let data = item.removeValue(forKey: "UserData"), var data = data as? Obj {
                if data["LastPlayedDate"] != nil { data["LastPlayedDate"] = shifted(data["LastPlayedDate"], by: delta) }
                userdata[id] = data
            }
            items[id] = item
            order.append(id)
        }
        self.items = items
        self.userdata = userdata
        self.order = order
        albumArtists = Set(strings(relations["albumArtists"]))
        similar = (relations["similar"] as? Obj ?? [:]).mapValues(strings)
        entries = (relations["playlists"] as? Obj ?? [:]).mapValues(strings)
        audio = (relations["audio"] as? Obj ?? [:]).compactMapValues { $0 as? String }
        tracks = order.filter { text(items[$0]!["Type"]) == "Audio" }
        for id in tracks {
            albumTracks[text(items[id]!["AlbumId"]) ?? "", default: []].append(id)
        }
        if songLengths { stretch() }
    }

    func type(_ item: Obj) -> String { text(item["Type"]) ?? "" }

    /// Song lengths a listener expects (2:30 to 5:30, by id) instead of the
    /// test library's 5 to 8 seconds, with the albums and artists summed
    /// again. The audio follows: each clip is looped to its track's length (Clip).
    func stretch() {
        for id in tracks {
            let seconds = 150 + Int(String(MD5.hex(id).prefix(6)), radix: 16)! % 181
            items[id]!["RunTimeTicks"] = seconds * ticksPerSecond
        }
        for (id, item) in items {
            let ticks: Int
            switch type(item) {
            case "MusicAlbum":
                ticks = (albumTracks[text(item["Id"]) ?? ""] ?? []).reduce(0) { $0 + int(items[$1]!["RunTimeTicks"])! }
            case "MusicArtist":
                let artist = text(item["Id"]) ?? ""
                ticks = tracks.filter { Self.byArtist(items[$0]!, artist) }.reduce(0) { $0 + int(items[$1]!["RunTimeTicks"])! }
            default:
                continue
            }
            for key in ["RunTimeTicks", "CumulativeRunTimeTicks"] where item[key] != nil {
                items[id]![key] = ticks
            }
        }
        for (id, var entry) in lyrics where items[id] != nil {
            var metadata = entry["Metadata"] as? Obj ?? [:]
            metadata["Length"] = items[id]!["RunTimeTicks"]
            entry["Metadata"] = metadata
            lyrics[id] = entry
        }
    }

    static func byArtist(_ item: Obj, _ artist: String) -> Bool {
        (objects(item["ArtistItems"]) + objects(item["AlbumArtists"])).contains { norm($0["Id"]) == artist }
    }

    // --- tokens

    func issueToken(_ device: String) -> String {
        let token = newID()
        // Signing in again from the same device signs its old token out, as on 12.4.
        if let old = deviceTokens[device], !old.isEmpty { revoked.insert(old) }
        deviceTokens[device] = token
        return token
    }

    func valid(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return !revoked.contains(token)
    }

    // --- items as Jellyfin sends them

    func shape(_ item: Obj, _ wanted: Set<String>, userData: Bool = true, entry: Bool = false) -> Obj {
        let gated = fields[type(item)] ?? [:]
        var keep = Set<String>()
        for field in wanted { keep.formUnion(gated[field] ?? []) }
        let drop = Set(gated.values.joined()).subtracting(keep)
        var out: Obj = ["Name": item["Name"] ?? NSNull(), "ServerId": serverID]
        for (key, value) in item where key != "Name" && !drop.contains(key) {
            out[key] = value
            if key == "Id" && entry {
                // On 12.4 a playlist entry's id is the track's own.
                out["PlaylistItemId"] = item["Id"]
            }
        }
        let id = text(item["Id"]) ?? ""
        if type(item) == "Playlist" {
            let list = entries[id] ?? []
            let ticks = list.compactMap { items[$0] }.reduce(0) { $0 + (int($1["RunTimeTicks"]) ?? 0) }
            for (key, value) in [("ChildCount", list.count), ("RunTimeTicks", ticks), ("CumulativeRunTimeTicks", ticks)]
            where out[key] != nil {
                out[key] = value
            }
        }
        if userData && userdata[id] != nil { out["UserData"] = userdataDTO(id) }
        return out
    }

    func userdataDTO(_ id: String) -> Obj {
        let data = userdata[id] ?? [:]
        var out: Obj = ["PlaybackPositionTicks": data["PlaybackPositionTicks"] ?? 0, "PlayCount": data["PlayCount"] ?? 0,
                        "IsFavorite": truthy(data["IsFavorite"])]
        if truthy(data["LastPlayedDate"]) { out["LastPlayedDate"] = data["LastPlayedDate"] }
        out["Played"] = truthy(data["Played"])
        out["Key"] = data["Key"] ?? id
        out["ItemId"] = id
        return out
    }

    func page(_ pool: [Obj], _ q: Query, entry: Bool = false) -> Obj {
        let start = max(0, q.number("StartIndex") ?? 0)
        let limit = q.number("Limit")
        let chosen = slice(pool, start, limit.map { start + max(0, $0) })
        let wanted = Set(q.list("Fields").map { $0.lowercased() })
        let userData = q.flag("EnableUserData") != false
        return ["Items": chosen.map { shape($0, wanted, userData: userData, entry: entry) },
                "TotalRecordCount": pool.count, "StartIndex": start]
    }

    // --- /Items and friends: the pool, then filters, then order

    func pool(_ scope: String, _ q: Query) -> ([Obj], String) {
        let ids = q.list("Ids").map(norm)
        if !ids.isEmpty { return (ids.compactMap { items[$0] }, "ids") }
        let all = order.map { items[$0]! }
        switch scope {
        case "albumartists": return (order.filter(albumArtists.contains).map { items[$0]! }, "list")
        case "artists": return (all.filter { type($0) == "MusicArtist" }, "list")
        case "genres": return (all.filter { type($0) == "MusicGenre" }, "list")
        default: break
        }
        let parent = norm(q.get("ParentId"))
        let include = Set(q.list("IncludeItemTypes").map { $0.lowercased() })
        let musical = { (item: Obj) in ["MusicAlbum", "Audio"].contains(self.type(item)) }
        if !parent.isEmpty {
            if let list = entries[parent] { return (list.compactMap { items[$0] }, "playlist") }
            if let item = items[parent] {
                switch type(item) {
                case "MusicAlbum": return ((albumTracks[parent] ?? []).map { items[$0]! }, "list")
                case "MusicArtist": return (all.filter { musical($0) && Self.byArtist($0, parent) }, "list")
                case "MusicGenre":
                    let name = text(item["Name"]) ?? ""
                    return (all.filter { strings($0["Genres"]).contains(name) && musical($0) }, "list")
                default: break
                }
            }
            if let view = views.first(where: { norm($0["Id"]) == parent }), !view.isEmpty {
                if text(view["CollectionType"]) == "playlists" { return (all.filter { type($0) == "Playlist" }, "list") }
                return (all.filter { musical($0) || include.contains(type($0).lowercased()) }, "list")
            }
            return ([], "list")
        }
        if q.flag("Recursive") == true {
            // Artists and genres are not in the folders: only when asked for by type.
            return (all.filter { !["MusicArtist", "MusicGenre"].contains(type($0)) || include.contains(type($0).lowercased()) },
                    "list")
        }
        return (views, "views")
    }

    func query(_ scope: String, _ q: Query) -> Obj {
        var (pool, context) = self.pool(scope, q)
        if context == "views" {
            return ["Items": pool.map { view -> Obj in var view = view; view["ServerId"] = serverID; return view },
                    "TotalRecordCount": pool.count, "StartIndex": 0]
        }
        let include = Set(q.list("IncludeItemTypes").map { $0.lowercased() })
        let exclude = Set(q.list("ExcludeItemTypes").map { $0.lowercased() })
        let media = Set(q.list("MediaTypes").map { $0.lowercased() })
        if !include.isEmpty { pool = pool.filter { include.contains(type($0).lowercased()) } }
        if !exclude.isEmpty { pool = pool.filter { !exclude.contains(type($0).lowercased()) } }
        if !media.isEmpty { pool = pool.filter { media.contains((text($0["MediaType"]) ?? "").lowercased()) } }
        for name in ["ArtistIds", "AlbumArtistIds", "ContributingArtistIds"] {
            let wanted = Set(q.list(name).map(norm))
            if wanted.isEmpty { continue }
            func refs(_ item: Obj) -> Set<String> {
                let found: [Obj]
                switch name {
                case "AlbumArtistIds": found = objects(item["AlbumArtists"])
                case "ContributingArtistIds":
                    let album = Set(objects(item["AlbumArtists"]).map { norm($0["Id"]) })
                    found = objects(item["ArtistItems"]).filter { !album.contains(norm($0["Id"])) }
                default: found = objects(item["ArtistItems"]) + objects(item["AlbumArtists"])
                }
                return Set(found.map { norm($0["Id"]) })
            }
            pool = pool.filter { !refs($0).isDisjoint(with: wanted) }
        }
        let albums = Set(q.list("AlbumIds").map(norm))
        if !albums.isEmpty { pool = pool.filter { albums.contains(norm($0["AlbumId"])) } }
        var genres = Set(q.list("Genres", separator: "|").map(fold))
        genres.formUnion(q.list("GenreIds").compactMap { items[norm($0)] }.map { fold(text($0["Name"])) })
        if !genres.isEmpty { pool = pool.filter { !genres.isDisjoint(with: strings($0["Genres"]).map(fold)) } }
        let years = Set(q.list("Years").filter { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
            .compactMap { Int($0) })
        if !years.isEmpty { pool = pool.filter { int($0["ProductionYear"]).map(years.contains) ?? false } }
        let filters = Set(q.list("Filters").map { $0.lowercased() })
        let favourite = !filters.isDisjoint(with: ["isfavorite", "isfavoriteorlikes"]) ? true : q.flag("IsFavorite")
        if let favourite {
            pool = pool.filter { truthy(userdata[text($0["Id"]) ?? ""]?["IsFavorite"]) == favourite }
        }
        let played = filters.contains("isplayed") ? true : filters.contains("isunplayed") ? false : q.flag("IsPlayed")
        if let played {
            pool = pool.filter { truthy(userdata[text($0["Id"]) ?? ""]?["Played"]) == played }
        }
        if let starts = q.get("NameStartsWith"), !starts.isEmpty {
            let prefix = fold(starts)
            pool = pool.filter { sortName($0).hasPrefix(prefix) }
        }
        let term = (q.get("SearchTerm") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            // Matched in the name only, ordered by relevance whatever SortBy
            // says (both measured on 12.4: tracks are not found by artist).
            let folded = fold(term)
            pool = pool.filter { fold(text($0["Name"])).contains(folded) }
            pool = stableSorted(pool) { [.number(Self.relevance($0, folded)), .text(self.sortName($0))] }
        } else {
            pool = sorted(pool, q, context)
        }
        return page(pool, q, entry: context == "playlist")
    }

    func sortName(_ item: Obj) -> String {
        let name = text(item["SortName"]) ?? ""
        return fold(name.isEmpty ? text(item["Name"]) : name)
    }

    static func relevance(_ item: Obj, _ term: String) -> Int {
        let name = fold(text(item["Name"]))
        if name == term { return 0 }
        if name.hasPrefix(term) { return 1 }
        if name.split(whereSeparator: \.isWhitespace).contains(where: { $0.hasPrefix(term) }) { return 2 }
        return 3
    }

    func sortKey(_ key: String) -> ((Obj) -> Key)? {
        let data = { (item: Obj) in self.userdata[text(item["Id"]) ?? ""] ?? [:] }
        switch key.lowercased() {
        case "sortname": return { .text(self.sortName($0)) }
        case "name": return { .text(fold(text($0["Name"]))) }
        case "albumartist": return { .text(fold(text($0["AlbumArtist"]))) }
        case "artist": return { .text(fold(strings($0["Artists"]).first)) }
        case "album": return { .text(fold(text($0["Album"]))) }
        case "productionyear": return { .number(int($0["ProductionYear"]) ?? 0) }
        case "premieredate": return { .text(text($0["PremiereDate"]) ?? "") }
        case "datecreated", "datelastcontentadded": return { .text(text($0["DateCreated"]) ?? "") }
        case "dateplayed": return { .text(text(data($0)["LastPlayedDate"]) ?? "") }
        case "playcount": return { .number(int(data($0)["PlayCount"]) ?? 0) }
        case "isfavoriteorliked": return { .number(truthy(data($0)["IsFavorite"]) ? 1 : 0) }
        case "indexnumber": return { .number(int($0["IndexNumber"]) ?? 0) }
        case "parentindexnumber": return { .number(int($0["ParentIndexNumber"]) ?? 0) }
        case "runtime": return { .number(int($0["RunTimeTicks"]) ?? 0) }
        case "childcount": return { .number(int($0["ChildCount"]) ?? 0) }
        default: return nil
        }
    }

    func sorted(_ pool: [Obj], _ q: Query, _ context: String) -> [Obj] {
        var keys = q.list("SortBy")
        let orders = q.list("SortOrder").map { $0.lowercased() }
        if keys.isEmpty {
            // Ids in the order asked; a playlist in its own; the rest by name.
            if context == "ids" || context == "playlist" { return pool }
            keys = ["SortName"]
        }
        var pool = pool
        if keys.contains(where: { $0.lowercased() == "random" }) {
            rng.shuffle(&pool)
            return pool
        }
        // One SortOrder applies to every key; several go one for one (12.4).
        for n in stride(from: keys.count - 1, through: 0, by: -1) {
            guard let key = sortKey(keys[n]) else {
                log("  (SortBy \(keys[n]) is not known to the fake: ignored)")
                continue
            }
            let order = orders.count == 1 ? orders[0] : n < orders.count ? orders[n] : "ascending"
            pool = stableSorted(pool, descending: order == "descending") { [key($0)] }
        }
        return pool
    }

    /// The seed's genres, shuffled; a track's mix starts with the track
    /// (12.4 does both: an artist's mix was all 23 tracks of its genre).
    func instantMix(_ seedID: String, _ q: Query) throws -> Obj {
        guard let seed = items[seedID] else { throw HTTPError(status: 404) }
        var first: [Obj] = []
        let genres: Set<String>
        switch type(seed) {
        case "Audio":
            genres = Set(strings(seed["Genres"]))
            first = [seed]
        case "MusicGenre":
            genres = [text(seed["Name"]) ?? ""]
        case "Playlist":
            genres = Set(try (entries[seedID] ?? []).flatMap { id -> [String] in
                guard let item = items[id] else { throw Failure("KeyError: '\(id)'") }
                return strings(item["Genres"])
            })
        default:
            genres = Set(strings(seed["Genres"]))
        }
        var rest = tracks.filter { $0 != seedID && !genres.isDisjoint(with: strings(items[$0]!["Genres"])) }
            .map { items[$0]! }
        rng.shuffle(&rest)
        let limit = q.number("Limit") ?? 200
        let mix = Array((first + rest).prefix(max(1, limit == 0 ? 200 : limit)))
        let wanted = Set(q.list("Fields").map { $0.lowercased() })
        return ["Items": mix.map { shape($0, wanted) }, "TotalRecordCount": mix.count, "StartIndex": 0]
    }

    /// The server's own answer for an album artist (recorded); for
    /// anything else, items of its kind sharing a genre, as 12.4 does.
    func similarTo(_ id: String, _ q: Query) throws -> Obj {
        guard let item = items[id] else { throw HTTPError(status: 404) }
        var found: [Obj]
        if let recorded = similar[id] {
            found = recorded.compactMap { items[$0] }
        } else {
            let genres = Set(strings(item["Genres"]))
            found = order.filter { $0 != id }.map { items[$0]! }
                .filter { type($0) == type(item) && !genres.isDisjoint(with: strings($0["Genres"])) }
        }
        let limit = q.number("Limit") ?? 50
        found = Array(found.prefix(max(1, limit == 0 ? 50 : limit)))
        let wanted = Set(q.list("Fields").map { $0.lowercased() })
        return ["Items": found.map { shape($0, wanted) }, "TotalRecordCount": found.count, "StartIndex": 0]
    }

    func searchHints(_ q: Query) -> Obj {
        let term = fold((q.get("SearchTerm") ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        if term.isEmpty { return ["SearchHints": [Any](), "TotalRecordCount": 0] }
        let kinds = Set(q.list("IncludeItemTypes").map { $0.lowercased() })
        var found = order.map { items[$0]! }
            .filter { fold(text($0["Name"])).contains(term) && (kinds.isEmpty || kinds.contains(type($0).lowercased())) }
        found = stableSorted(found) { [.number(Self.relevance($0, term)), .text(self.sortName($0))] }
        let total = found.count
        let start = max(0, q.number("StartIndex") ?? 0)
        found = slice(found, start, q.number("Limit").map { start + $0 })
        let hints: [Obj] = found.map { item in
            var hint: Obj = ["ItemId": item["Id"]!, "Id": item["Id"]!, "Name": item["Name"] ?? NSNull()]
            for key in ["IndexNumber", "ProductionYear", "ParentIndexNumber"] where item[key] != nil {
                hint[key] = item[key]
            }
            if let primary = (item["ImageTags"] as? Obj)?["Primary"], truthy(primary) { hint["PrimaryImageTag"] = primary }
            hint["Type"] = item["Type"]
            hint["RunTimeTicks"] = item["RunTimeTicks"] ?? NSNull()
            hint["MediaType"] = item["MediaType"] ?? "Unknown"
            for key in ["Album", "AlbumId", "AlbumArtist", "Artists"] where item[key] != nil {
                hint[key] = item[key]
            }
            hint["ChannelId"] = NSNull()
            return hint
        }
        return ["SearchHints": hints, "TotalRecordCount": total]
    }

    // --- changes

    func createPlaylist(_ name: String, _ ids: [String]) throws -> String {
        let id = newID()
        var item = template
        let old = text(item["Name"]) ?? ""
        item["Name"] = name
        item["Id"] = id
        if item["SortName"] != nil { item["SortName"] = name.lowercased() }
        if let path = text(item["Path"]) { item["Path"] = path.replacingOccurrences(of: old, with: name) }
        if item["DateCreated"] != nil { item["DateCreated"] = nowDate() }
        item["ImageTags"] = Obj()
        items[id] = item
        order.append(id)
        userdata[id] = ["PlaybackPositionTicks": 0, "PlayCount": 0, "IsFavorite": false, "Played": false,
                        "Key": dashed(id), "ItemId": id]
        entries[id] = ids.map(norm).filter { items[$0] != nil }
        return id
    }

    func favourite(_ id: String, _ value: Bool) throws -> Obj {
        guard items[id] != nil else { throw HTTPError(status: 404) }
        var data = userdata[id] ?? ["PlaybackPositionTicks": 0, "PlayCount": 0, "Played": false, "Key": id, "ItemId": id]
        data["IsFavorite"] = value
        userdata[id] = data
        return userdataDTO(id)
    }

    func played(_ id: String, _ value: Bool) throws -> Obj {
        guard items[id] != nil else { throw HTTPError(status: 404) }
        var data = userdata[id] ?? ["PlaybackPositionTicks": 0, "PlayCount": 0, "IsFavorite": false, "Key": id, "ItemId": id]
        data["Played"] = value
        if value {
            data["PlayCount"] = max(1, int(data["PlayCount"]) ?? 0)
            data["LastPlayedDate"] = nowDate()
        }
        userdata[id] = data
        return userdataDTO(id)
    }

    /// 12.4, measured: the start report counts the play and sets the date;
    /// progress or a stop alone set the date and Played; a stop without
    /// PositionTicks counts one more.
    func report(_ kind: String, _ body: Obj) {
        let id = norm(body["ItemId"])
        guard var data = userdata[id] else { return }
        data["LastPlayedDate"] = nowDate()
        data["Played"] = true
        if kind == "start" || (kind == "stopped" && body["PositionTicks"] == nil) {
            data["PlayCount"] = (int(data["PlayCount"]) ?? 0) + 1
        }
        userdata[id] = data
    }

    func file(_ path: String) throws -> [UInt8] {
        if let data = files[path] { return data }
        let data = Array(try Data(contentsOf: URL(fileURLWithPath: path)))
        files[path] = data
        return data
    }

    func clip(_ name: String) throws -> Clip {
        if let clip = clips[name] { return clip }
        let clip = Clip(name: name, data: try file(folder + "/audio/" + name + ".m4a"))
        clips[name] = clip
        return clip
    }
}

// MARK: - HTTP

struct Request {
    let method: String
    let path: String
    let query: String
    let headers: [(String, String)]
    var body: [UInt8] = []

    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }
}

struct Response {
    var status: Int
    var body: [UInt8] = []
    var contentType: String? = nil
    var headers: [(String, String)] = []
    /// Seconds to wait before answering, outside the library's lock.
    var delay: Double = 0
}

func jsonResponse(_ value: Any, status: Int = 200) -> Response {
    Response(status: status, body: json(value), contentType: "application/json; charset=utf-8")
}

func problem(_ status: Int, _ detail: String?) -> Response {
    // 12.4 answers a missing or dead token with an empty 401.
    if status == 401 && detail == nil { return Response(status: 401) }
    let titles = [400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                  405: "Method Not Allowed", 416: "Range Not Satisfiable", 500: "Internal Server Error"]
    var body = "{\"type\": \"https://tools.ietf.org/html/rfc9110\", \"title\": \(quoted(titles[status] ?? "Error")), \"status\": \(status)"
    if let detail, !detail.isEmpty { body += ", \"detail\": \(quoted(detail))" }
    return Response(status: status, body: Array((body + "}").utf8), contentType: "application/problem+json; charset=utf-8")
}

/// `MediaBrowser Client="…", Device="…", DeviceId="…", Version="…", Token="…"`,
/// each value percent-encoded.
let authorizationPattern = try! NSRegularExpression(pattern: #"(\w+)="([^"]*)""#)

func parseAuthorization(_ value: String?) -> [String: String] {
    guard let value else { return [:] }
    var out: [String: String] = [:]
    let string = value as NSString
    for match in authorizationPattern.matches(in: value, range: NSRange(location: 0, length: string.length)) {
        out[string.substring(with: match.range(at: 1)).lowercased()] = unquote(string.substring(with: match.range(at: 2)))
    }
    return out
}

var lib: Library!
let libraryLock = NSRecursiveLock()

func token(_ request: Request, _ q: Query) -> String? {
    for name in ["Authorization", "X-Emby-Authorization"] {
        if let token = parseAuthorization(request.header(name))["token"], !token.isEmpty { return token }
    }
    for name in ["X-Emby-Token", "X-MediaBrowser-Token"] {
        if let token = request.header(name), !token.isEmpty { return token }
    }
    // ApiKey in the URL, as AVPlayer's requests carry it; 12.4 refuses api_key.
    return q.get("ApiKey")
}

func require(_ request: Request, _ q: Query) throws {
    if !lib.valid(token(request, q)) { throw HTTPError(status: 401) }
}

func bodyObject(_ request: Request) throws -> Obj {
    guard !request.body.isEmpty else { return [:] }
    guard let value = try? parseJSON(request.body) else { throw HTTPError(status: 400, detail: "the body is not JSON") }
    return value as? Obj ?? [:]
}

typealias Handler = (Request, Query, [String?]) throws -> Response

func fieldsOf(_ q: Query) -> Set<String> { Set(q.list("Fields").map { $0.lowercased() }) }

func publicInfo(_ request: Request, _ q: Query, _ groups: [String?]) -> Response {
    var info = lib.publicInfo
    if let host = request.header("Host"), !host.isEmpty, info["LocalAddress"] == nil {
        info["LocalAddress"] = "http://\(host)"
    }
    return jsonResponse(info)
}

func authenticate(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    let body: Obj
    if request.body.isEmpty {
        body = [:]
    } else {
        guard let value = try? parseJSON(request.body) else { throw HTTPError(status: 400, detail: "the body is not JSON") }
        body = value as? Obj ?? [:]
    }
    let name = (text(body["Username"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if name.lowercased() != (text(lib.user["Name"]) ?? "").lowercased() || (text(body["Pw"]) ?? "") != lib.password {
        // As 12.4: 401 with a line of text.
        return Response(status: 401, body: Array("Error processing request.".utf8), contentType: "text/plain; charset=utf-8")
    }
    let authorization = request.header("Authorization").flatMap { $0.isEmpty ? nil : $0 } ?? request.header("X-Emby-Authorization")
    let header = parseAuthorization(authorization)
    let token = lib.issueToken(header["deviceid"] ?? "")
    var answer = lib.signIn
    let stamp = nowDate()
    lib.user["LastLoginDate"] = stamp
    lib.user["LastActivityDate"] = stamp
    answer["User"] = lib.user
    answer["AccessToken"] = token
    answer["ServerId"] = lib.serverID
    if var session = answer["SessionInfo"] as? Obj, !session.isEmpty {
        let values: [(String, String?)] = [
            ("Client", header["client"]), ("DeviceName", header["device"]), ("DeviceId", header["deviceid"]),
            ("ApplicationVersion", header["version"]), ("UserId", text(lib.user["Id"])), ("UserName", text(lib.user["Name"])),
            ("LastActivityDate", stamp), ("Id", newID()),
        ]
        for (key, value) in values where session[key] != nil {
            if let value { session[key] = value }
        }
        answer["SessionInfo"] = session
    }
    return jsonResponse(answer)
}

func logout(_ request: Request, _ q: Query, _ groups: [String?]) -> Response {
    if let token = token(request, q), !token.isEmpty { lib.revoked.insert(token) }
    return Response(status: 204)
}

func me(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    if let id = groups.first ?? nil, !id.isEmpty, norm(id) != text(lib.user["Id"]) { throw HTTPError(status: 404) }
    return jsonResponse(lib.user)
}

func userViews(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let views = lib.views.map { view -> Obj in var view = view; view["ServerId"] = lib.serverID; return view }
    return jsonResponse(["Items": views, "TotalRecordCount": views.count, "StartIndex": 0])
}

func listing(_ scope: String) -> Handler {
    { request, q, _ in
        try require(request, q)
        return jsonResponse(lib.query(scope, q))
    }
}

func item(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    guard let item = lib.items[norm(groups[0])] else { throw HTTPError(status: 404) }
    return jsonResponse(lib.shape(item, fieldsOf(q)))
}

func deleteItem(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = norm(groups[0])
    guard let item = lib.items[id] else { throw HTTPError(status: 404) }
    if lib.type(item) != "Playlist" { throw HTTPError(status: 403, detail: "the fake deletes playlists only") }
    lib.items[id] = nil
    lib.order.removeAll { $0 == id }
    lib.entries[id] = nil
    lib.userdata[id] = nil
    return Response(status: 204)
}

func similar(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    return jsonResponse(try lib.similarTo(norm(groups[0]), q))
}

func instantMix(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = (groups.first ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? q.get("Id")
    return jsonResponse(try lib.instantMix(norm(id), q))
}

func searchHints(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    return jsonResponse(lib.searchHints(q))
}

func playlistItems(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = norm(groups[0])
    guard let list = lib.entries[id] else { throw HTTPError(status: 404) }
    let pool = lib.sorted(list.compactMap { lib.items[$0] }, q, "playlist")
    return jsonResponse(lib.page(pool, q, entry: true))
}

func createPlaylist(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let body = try bodyObject(request)
    let name = [text(body["Name"]), q.get("Name")].compactMap { $0 }.first { !$0.isEmpty } ?? "New Playlist"
    let given = strings(body["Ids"])
    let id = try lib.createPlaylist(name, given.isEmpty ? q.list("Ids") : given)
    return jsonResponse(["Id": id])
}

func addToPlaylist(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = norm(groups[0])
    guard lib.entries[id] != nil else { throw HTTPError(status: 404) }
    // At the end, in order; a track already there is there twice (12.4).
    lib.entries[id]! += q.list("Ids").map(norm).filter { lib.items[$0] != nil }
    return Response(status: 204)
}

func removeFromPlaylist(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = norm(groups[0])
    guard let list = lib.entries[id] else { throw HTTPError(status: 404) }
    // An entry id is the track's id, so every entry of that track goes;
    // an id the playlist does not have is ignored (12.4).
    let gone = Set(q.list("EntryIds").map(norm))
    lib.entries[id] = list.filter { !gone.contains($0) }
    return Response(status: 204)
}

func moveInPlaylist(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = norm(groups[0]), entry = norm(groups[1])
    guard var list = lib.entries[id], let at = list.firstIndex(of: entry) else { throw HTTPError(status: 404) }
    // The first entry of that id, taken out and put in at the index.
    list.remove(at: at)
    list.insert(entry, at: min(max(0, Int(groups[2] ?? "") ?? 0), list.count))
    lib.entries[id] = list
    return Response(status: 204)
}

func favourite(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    return jsonResponse(try lib.favourite(norm(groups[0]), request.method == "POST"))
}

func played(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    return jsonResponse(try lib.played(norm(groups[0]), request.method == "POST"))
}

func playing(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let body = request.body.isEmpty ? [:] : ((try? parseJSON(request.body)) as? Obj ?? [:])
    if let kind = groups.first ?? nil {
        if ["progress", "stopped"].contains(kind.lowercased()) { lib.report(kind.lowercased(), body) }
    } else {
        lib.report("start", body)
    }
    return Response(status: 204)
}

func capabilities(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    return Response(status: 204)
}

func lyrics(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    guard let lyrics = lib.lyrics[norm(groups[0])] else { throw HTTPError(status: 404) }
    return jsonResponse(lyrics)
}

func image(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    let id = norm(groups[0])
    let tag = (lib.items[id]?["ImageTags"] as? Obj)?["Primary"]
    let path = lib.folder + "/images/" + id + ".jpg"
    guard (groups[1] ?? "").lowercased() == "primary", truthy(tag), let tag = text(tag),
          FileManager.default.fileExists(atPath: path) else { throw HTTPError(status: 404) }
    // With the tag the URL never changes its picture: cache for good (12.4).
    let cache = truthy(q.get("tag")) ? "public, max-age=31536000, immutable" : "public"
    return Response(status: 200, body: try lib.file(path), contentType: "image/jpeg",
                    headers: [("Cache-Control", cache), ("ETag", "\"\(tag)\"")])
}

let rangePattern = try! NSRegularExpression(pattern: #"\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)"#)

func audio(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    try require(request, q)
    let id = norm(groups[0])
    guard let name = lib.audio[id] else { throw HTTPError(status: 404) }
    guard let track = lib.items[id] else { throw Failure("KeyError: '\(id)'") }
    // As long as the track says, so the app hears it to its end (Clip).
    let seconds = lib.clipsAsRecorded ? 0
        : Int((Double(int(track["RunTimeTicks"]) ?? 0) / Double(ticksPerSecond)).rounded(.toNearestOrEven))
    let data = try lib.clip(name).file(seconds)
    let size = data.count
    // A download (TranscodingProtocol=http; the player's stream is HLS) as
    // slow as a real server's, so its progress can be seen: 0.4 to 2 s a
    // song, the same song the same each time.
    let delay = lib.slowDownloads && q.get("TranscodingProtocol") == "http"
        ? 0.4 + Double(Int(String(MD5.hex(id).prefix(4)), radix: 16)! % 17) / 10 : 0
    let headers = [("Accept-Ranges", "bytes"), ("ETag", "\"\(name)-\(seconds)\"")]
    guard let wanted = request.header("Range") else {
        return Response(status: 200, body: data, contentType: "audio/mp4", headers: headers, delay: delay)
    }
    // One range, as AVPlayer asks: "bytes=0-1", "bytes=1000-", "bytes=-500".
    let string = wanted as NSString
    let unsatisfiable = Response(status: 416, headers: [("Content-Range", "bytes */\(size)")], delay: delay)
    guard let found = rangePattern.firstMatch(in: wanted, options: .anchored, range: NSRange(location: 0, length: string.length))
    else { return unsatisfiable }
    let first = string.substring(with: found.range(at: 1)), last = string.substring(with: found.range(at: 2))
    if first.isEmpty && last.isEmpty { return unsatisfiable }
    let start: Int, end: Int
    if first.isEmpty {
        start = max(0, size - (Int(last) ?? 0))
        end = size - 1
    } else {
        start = Int(first) ?? 0
        end = last.isEmpty ? size - 1 : min(Int(last) ?? 0, size - 1)
    }
    if start >= size || start > end { return unsatisfiable }
    return Response(status: 206, body: Array(data[start...end]), contentType: "audio/mp4",
                    headers: headers + [("Content-Range", "bytes \(start)-\(end)/\(size)")], delay: delay)
}

let idPattern = "([0-9A-Fa-f-]{32,36})"
let routeTable: [(String, String, Handler)] = [
    ("GET", "/System/Info/Public", publicInfo),
    ("GET POST", "/System/Ping", { _, _, _ in jsonResponse("Jellyfin Server") }),
    // As 12.4 answers a Subsonic client's /rest/…: 404, no body.
    ("GET POST", "/rest/.*", { _, _, _ in Response(status: 404) }),
    ("POST", "/Users/AuthenticateByName", authenticate),
    ("POST", "/Users/AuthenticateWithQuickConnect", quickDisabled),
    ("POST", "/Sessions/Logout", logout),
    ("GET", "/QuickConnect/Enabled", { _, _, _ in jsonResponse(false) }),
    ("POST", "/QuickConnect/Initiate", quickDisabled),
    ("GET", "/QuickConnect/Connect", quickDisabled),
    ("POST", "/QuickConnect/Authorize", quickDisabled),
    ("GET", "/Users/Me", me),
    ("GET", "/Users/" + idPattern, me),
    ("GET", "/UserViews", userViews),
    ("GET", "/Users/" + idPattern + "/Views", userViews),
    ("GET", "/Items", listing("items")),
    ("GET", "/Users/" + idPattern + "/Items", listing("items")),
    ("GET", "/Items/" + idPattern, item),
    ("DELETE", "/Items/" + idPattern, deleteItem),
    ("GET", "/Users/[^/]+/Items/" + idPattern, item),
    ("GET", "/Artists/AlbumArtists", listing("albumartists")),
    ("GET", "/Artists", listing("artists")),
    ("GET", "/MusicGenres", listing("genres")),
    ("GET", "/Genres", listing("genres")),
    ("GET", "/(?:Items|Artists|Albums)/" + idPattern + "/Similar", similar),
    ("GET", "/(?:Items|Songs|Albums|Artists|Playlists|MusicGenres)/" + idPattern + "/InstantMix", instantMix),
    ("GET", "/(?:Artists|MusicGenres)/InstantMix", instantMix),
    ("GET", "/Search/Hints", searchHints),
    ("POST", "/Playlists", createPlaylist),
    ("GET", "/Playlists/" + idPattern + "/Items", playlistItems),
    ("POST", "/Playlists/" + idPattern + "/Items", addToPlaylist),
    ("DELETE", "/Playlists/" + idPattern + "/Items", removeFromPlaylist),
    ("POST", "/Playlists/" + idPattern + "/Items/" + idPattern + "/Move/(-?\\d+)", moveInPlaylist),
    ("POST DELETE", "/UserFavoriteItems/" + idPattern, favourite),
    ("POST DELETE", "/Users/[^/]+/FavoriteItems/" + idPattern, favourite),
    ("POST DELETE", "/UserPlayedItems/" + idPattern, played),
    ("POST DELETE", "/Users/[^/]+/PlayedItems/" + idPattern, played),
    ("POST", "/Sessions/Playing", playing),
    ("POST", "/Sessions/Playing/(Progress|Stopped|Ping)", playing),
    ("POST", "/Sessions/Capabilities(?:/Full)?", capabilities),
    ("GET", "/Audio/" + idPattern + "/Lyrics", lyrics),
    ("GET", "/Audio/" + idPattern + "/(universal|stream)(?:\\.\\w+)?", audio),
    ("GET", "/Items/" + idPattern + "/Images/(\\w+)(?:/(\\d+))?", image),
]
let routes: [(methods: Set<String>, pattern: NSRegularExpression, handler: Handler)] = routeTable.map { methods, pattern, handler in
    (Set(methods.split(separator: " ").map(String.init)),
     try! NSRegularExpression(pattern: "^" + pattern + "$", options: .caseInsensitive), handler)
}

func quickDisabled(_ request: Request, _ q: Query, _ groups: [String?]) throws -> Response {
    throw HTTPError(status: 401, detail: "Quick connect is disabled")
}

/// The handler for a path, its groups (nil where an optional one did not
/// match), and whether the path is known for another method.
func match(_ method: String, _ path: String) -> (Handler?, [String?], Bool) {
    var allowed = false
    let string = path as NSString
    for route in routes {
        guard let found = route.pattern.firstMatch(in: path, range: NSRange(location: 0, length: string.length)) else {
            continue
        }
        if route.methods.contains(method) || (method == "HEAD" && route.methods.contains("GET")) {
            let groups: [String?] = (1..<found.numberOfRanges).map { index in
                let range = found.range(at: index)
                guard range.location != NSNotFound else { return nil }
                let group = string.substring(with: range)
                return group.isEmpty ? group : unquote(group)
            }
            return (route.handler, groups, true)
        }
        allowed = true
    }
    return (nil, [], allowed)
}

/// The answer to one request, worked out under the library's lock.
func respond(_ request: Request) -> (Response, known: Bool) {
    libraryLock.lock()
    defer { libraryLock.unlock() }
    let q = Query(request.query)
    let (handler, groups, allowed) = match(request.method, request.path)
    guard let handler else {
        return allowed ? (problem(405, nil), true) : (problem(404, nil), false)
    }
    do {
        return (try handler(request, q, groups), true)
    } catch let error as HTTPError {
        return (problem(error.status, error.detail), true)
    } catch {
        log("Traceback: \(error)")
        return (problem(500, "the fake failed: see its log"), true)
    }
}

// MARK: - The server: a thread for each connection, HTTP/1.1 kept alive

final class Connection {
    let fd: Int32
    private var buffer: [UInt8] = []
    private var start = 0

    init(_ fd: Int32) { self.fd = fd }

    private func fill() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = recv(fd, &chunk, chunk.count, 0)
        guard count > 0 else { return false }
        if start > 0 {
            buffer.removeFirst(start)
            start = 0
        }
        buffer += chunk[0..<count]
        return true
    }

    /// A line without its end, nil when the peer has gone.
    func line() -> [UInt8]? {
        while true {
            if let end = buffer[start...].firstIndex(of: 10) {
                var line = Array(buffer[start..<end])
                start = end + 1
                if line.last == 13 { line.removeLast() }
                return line
            }
            guard fill() else { return nil }
        }
    }

    func read(_ count: Int) -> [UInt8] {
        while buffer.count - start < count {
            guard fill() else { break }
        }
        let end = min(buffer.count, start + count)
        defer { start = end }
        return Array(buffer[start..<end])
    }

    func write(_ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            guard count > 0 else { return false }
            sent += count
        }
        return true
    }
}

let reasons = [100: "Continue", 200: "OK", 204: "No Content", 206: "Partial Content", 400: "Bad Request",
               401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
               416: "Requested Range Not Satisfiable", 500: "Internal Server Error", 501: "Not Implemented"]

func httpDate() -> String {
    var now = time(nil)
    var parts = tm()
    gmtime_r(&now, &parts)
    var out = [CChar](repeating: 0, count: 64)
    strftime(&out, out.count, "%a, %d %b %Y %H:%M:%S GMT", &parts)
    return String(cString: out)
}

func head(_ status: Int, _ lines: [(String, String)]) -> [UInt8] {
    var head = "HTTP/1.1 \(status) \(reasons[status] ?? "")\r\nServer: FakeJellyfin/12.4\r\nDate: \(httpDate())\r\n"
    for (name, value) in lines { head += "\(name): \(value)\r\n" }
    return Array((head + "\r\n").utf8)
}

func serve(_ connection: Connection) {
    defer { close(connection.fd) }
    while let requestLine = connection.line() {
        let started = DispatchTime.now().uptimeNanoseconds
        let words = String(decoding: requestLine, as: UTF8.self).split(separator: " ").map(String.init)
        guard words.count == 3, words[2].hasPrefix("HTTP/") else {
            if !words.isEmpty {
                _ = connection.write(head(400, [("Connection", "close"), ("Content-Length", "0")]))
            }
            return
        }
        let (method, target, version) = (words[0], words[1], words[2])
        var headers: [(String, String)] = []
        while let line = connection.line(), !line.isEmpty {
            let text = String(decoding: line, as: UTF8.self)
            guard let colon = text.firstIndex(of: ":") else { continue }
            headers.append((String(text[..<colon]), text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
        }
        // As Python's http.server: 1.1 stays open unless told to close; 1.0
        // closes unless told to keep alive.
        var keepAlive = version >= "HTTP/1.1"
        let connectionHeader = headers.first { $0.0.lowercased() == "connection" }?.1.lowercased()
        if connectionHeader == "close" { keepAlive = false } else if connectionHeader == "keep-alive" { keepAlive = true }
        var request = Request(method: method, path: "", query: "", headers: headers)
        guard ["GET", "HEAD", "POST", "DELETE", "PUT"].contains(method) else {
            let body = Array("Unsupported method ('\(method)')".utf8)
            _ = connection.write(head(501, [("Content-Type", "text/plain"), ("Connection", "close"),
                                            ("Content-Length", "\(body.count)")]) + body)
            return
        }
        if version >= "HTTP/1.1", request.header("Expect")?.lowercased() == "100-continue" {
            _ = connection.write(Array("HTTP/1.1 100 Continue\r\n\r\n".utf8))
        }

        // The target: path and query, "//" made "/" and no slash at the end.
        var raw = Substring(target)
        if let scheme = raw.range(of: "://") {
            raw = raw[scheme.upperBound...]
            raw = raw.firstIndex(of: "/").map { raw[$0...] } ?? ""
        }
        if let hash = raw.firstIndex(of: "#") { raw = raw[..<hash] }
        let query = raw.firstIndex(of: "?").map { String(raw[raw.index(after: $0)...]) } ?? ""
        var path = String(raw.firstIndex(of: "?").map { raw[..<$0] } ?? raw)
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/" }
        request = Request(method: method, path: path, query: query, headers: headers)

        var status = "0", sent = 0, known = true
        var gone = false
        if request.header("Transfer-Encoding")?.lowercased() == "chunked" {
            var body: [UInt8] = []
            while true {
                guard let line = connection.line() else { gone = true; break }
                let size = Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespaces), radix: 16) ?? 0
                if size == 0 { _ = connection.line(); break }
                body += connection.read(size)
                _ = connection.line()
            }
            request.body = body
        } else if let length = Int(request.header("Content-Length") ?? ""), length > 0 {
            request.body = connection.read(length)
        }
        if gone {
            // AVPlayer drops connections it no longer needs.
            status = "dropped"
        } else {
            let (response, isKnown) = respond(request)
            if response.delay > 0 { Thread.sleep(forTimeInterval: response.delay) }
            known = isKnown
            status = String(response.status)
            var lines: [(String, String)] = []
            if let type = response.contentType { lines.append(("Content-Type", type)) }
            // A 204 has no length, as 12.4 (Kestrel) sends it and HTTP says.
            if response.status != 204 { lines.append(("Content-Length", String(response.body.count))) }
            lines += response.headers
            let bytes = head(response.status, lines) + (method == "HEAD" ? [] : response.body)
            if connection.write(bytes) { sent = response.body.count } else { keepAlive = false }
        }
        var shown = path + (query.isEmpty ? "" : "?" + query)
        if shown.unicodeScalars.count > 300 { shown = String(String.UnicodeScalarView(shown.unicodeScalars.prefix(300))) + "…" }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        log((known ? "" : "UNKNOWN ROUTE ") + "\(method) \(shown) → \(status) (\(sent) B, \(String(format: "%.1f", ms)) ms)")
        if gone || !keepAlive { return }
    }
}

#if canImport(Glibc)
let streamSocket = Int32(SOCK_STREAM.rawValue)
#else
let streamSocket = SOCK_STREAM
#endif

/// A listening socket: [::] taking IPv4 as well (on a Mac "localhost" is
/// ::1 and 127.0.0.1, and the simulator's app may try ::1 first), or one
/// IPv4 address. Its errno when it cannot be had.
func listening(_ host: String, _ port: Int) -> (Int32, String?, Int32) {
    let six = host.isEmpty || host.contains(":")
    let fd = socket(six ? AF_INET6 : AF_INET, streamSocket, 0)
    guard fd >= 0 else { return (-1, nil, errno) }
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    var bound: Int32
    let shown: String
    if six {
        var no: Int32 = 0
        setsockopt(fd, Int32(IPPROTO_IPV6), IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in6()
        #if canImport(Darwin)
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        #endif
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = in_port_t(UInt16(port).bigEndian)
        address.sin6_addr = in6addr_any
        if !host.isEmpty { inet_pton(AF_INET6, host, &address.sin6_addr) }
        shown = host.isEmpty ? "::" : host
        bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
    } else {
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, host, &address.sin_addr)
        shown = host
        bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
    }
    if bound != 0 || listen(fd, 64) != 0 {
        let failure = errno
        close(fd)
        return (-1, nil, failure)
    }
    return (fd, shown, 0)
}

@main
enum FakeJellyfin {
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0)
        // A peer that hangs up mid-answer must not end the server.
        signal(SIGPIPE, SIG_IGN)
        var host = "", port = 8096, data = "dev/demo", password = "test", seed = 1
        var songLengths = false, clipsAsRecorded = false, slowDownloads = false
        var arguments = Array(CommandLine.arguments.dropFirst())
        func value(_ name: String) -> String {
            guard !arguments.isEmpty else {
                FileHandle.standardError.write(Data("fake-jellyfin: \(name) needs a value\n".utf8))
                exit(2)
            }
            return arguments.removeFirst()
        }
        while !arguments.isEmpty {
            var argument = arguments.removeFirst()
            if let equals = argument.firstIndex(of: "="), argument.hasPrefix("--") {
                arguments.insert(String(argument[argument.index(after: equals)...]), at: 0)
                argument = String(argument[..<equals])
            }
            switch argument {
            case "--host": host = value(argument)
            case "--port": port = Int(value(argument)) ?? -1
            case "--data": data = value(argument)
            case "--password": password = value(argument)
            case "--seed": seed = Int(value(argument)) ?? 1
            // Tracks of 2:30 to 5:30 instead of the test library's 5 to 8 seconds.
            case "--song-lengths": songLengths = true
            // The looped files are checked with ffmpeg only (no AVPlayer here):
            // if the simulator's player refuses them, this serves the clips
            // ffmpeg wrote, every track 8 s.
            case "--clips-as-recorded": clipsAsRecorded = true
            // Each song downloaded (not streamed) takes 0.4 to 2 s, as from a real server.
            case "--slow-downloads": slowDownloads = true
            case "-h", "--help":
                print("fake-jellyfin [--host H] [--port 8096] [--data dev/demo] [--password test] [--seed 1]"
                      + " [--song-lengths] [--clips-as-recorded] [--slow-downloads]")
                exit(0)
            default:
                FileHandle.standardError.write(Data("fake-jellyfin: unrecognized argument \(argument)\n".utf8))
                exit(2)
            }
        }
        guard (0...65535).contains(port) else {
            FileHandle.standardError.write(Data("fake-jellyfin: --port takes a number\n".utf8))
            exit(2)
        }

        do {
            let folder = URL(fileURLWithPath: data).standardizedFileURL.path
            lib = try Library(folder: folder, songLengths: songLengths, seed: seed, password: password)
        } catch {
            FileHandle.standardError.write(Data("fake-jellyfin: the library in \(data): \(error)\n".utf8))
            exit(1)
        }
        lib.clipsAsRecorded = clipsAsRecorded
        lib.slowDownloads = slowDownloads

        var (fd, shown, failure) = listening(host, port)
        if fd < 0 && host.isEmpty && failure != EADDRINUSE {
            // No IPv6 here (some containers): IPv4 alone.
            (fd, shown, failure) = listening("0.0.0.0", port)
        }
        guard fd >= 0, let shown else {
            FileHandle.standardError.write(Data("fake-jellyfin: port \(port): \(String(cString: strerror(failure)))\n".utf8))
            exit(1)
        }

        var kinds: [String: Int] = [:]
        for item in lib.items.values { kinds[lib.type(item), default: 0] += 1 }
        let place = shown.contains(":") ? "[\(shown)]" : shown
        log("fake Jellyfin \(text(lib.publicInfo["Version"]) ?? "") \"\(text(lib.publicInfo["ServerName"]) ?? "")\" on "
            + "http://\(place):\(port): " + kinds.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
            + "; user \(text(lib.user["Name"]) ?? "")")
        // Each clip read once now, so a clip it cannot loop shows in the log
        // at the start rather than at the first song.
        do {
            for name in Set(lib.audio.values).sorted() { _ = try lib.clip(name) }
        } catch {
            FileHandle.standardError.write(Data("fake-jellyfin: \(error)\n".utf8))
            exit(1)
        }

        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            let thread = Thread { serve(Connection(client)) }
            thread.stackSize = 1 << 20
            thread.start()
        }
    }
}
