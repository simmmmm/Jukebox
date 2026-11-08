// The offline manifest: every song on the phone once, with every reason it
// is there.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Offline: the manifest")
struct OfflineManifestTests {
    static let saved = Date(timeIntervalSinceReferenceDate: 815_800_000)

    static func file(_ id: ItemID, _ reasons: Set<OfflineReason>, bytes: Int64 = 1_000,
                     quality: DownloadQuality = .high, name: String? = nil) -> OfflineFile {
        OfflineFile(trackID: id, fileName: name ?? "\(id).m4a", bytes: bytes, savedAt: saved,
                    quality: quality, reasons: reasons)
    }

    @Test("Empty: this version, no files, no bytes")
    func empty() {
        let manifest = OfflineManifest()
        #expect(manifest.version == OfflineManifest.version)
        #expect(manifest.files.isEmpty)
        #expect(!manifest.has("a"))
        #expect(manifest.file("a") == nil)
        #expect(manifest.chosenBytes == 0)
        #expect(manifest.keptBytes == 0)
    }

    @Test("Add, has, file, and a reason added to a song there; none to a song not")
    func addAndReasons() {
        var manifest = OfflineManifest()
        manifest.add(Self.file("a", [.album("al1")]))
        #expect(manifest.has("a"))
        #expect(manifest.file("a")?.reasons == [.album("al1")])
        let added = manifest.addReason(.playlist("p1"), to: "a")
        #expect(added)
        #expect(manifest.file("a")?.reasons == [.album("al1"), .playlist("p1")])
        let addedToMissing = manifest.addReason(.kept, to: "missing")
        #expect(!addedToMissing)
        #expect(!manifest.has("missing"))
    }

    @Test("A song saved again: the newest file, the reasons of both")
    func addAgain() {
        var manifest = OfflineManifest()
        manifest.add(Self.file("a", [.album("al1")], bytes: 9_000, quality: .original, name: "a.flac"))
        manifest.add(Self.file("a", [.kept], bytes: 4_000, quality: .normal, name: "a.m4a"))
        let file = manifest.file("a")
        #expect(file?.reasons == [.album("al1"), .kept])
        #expect(file?.fileName == "a.m4a")
        #expect(file?.bytes == 4_000)
        #expect(file?.quality == .normal)
        #expect(manifest.files.count == 1)
    }

    @Test("Songs by reason, by id; chosen and kept bytes, a song both counted as chosen")
    func tracksAndBytes() {
        var manifest = OfflineManifest()
        manifest.add(Self.file("c", [.album("al1")], bytes: 100))
        manifest.add(Self.file("a", [.album("al1"), .kept], bytes: 200))
        manifest.add(Self.file("b", [.kept], bytes: 400))
        manifest.add(Self.file("d", [.mix("daily-2026-11-08")], bytes: 800))
        #expect(manifest.tracks(with: .album("al1")) == ["a", "c"])
        #expect(manifest.tracks(with: .kept) == ["a", "b"])
        #expect(manifest.tracks(with: .mix("daily-2026-11-08")) == ["d"])
        #expect(manifest.tracks(with: .playlist("none")).isEmpty)
        #expect(manifest.chosenBytes == 1_100)
        #expect(manifest.keptBytes == 400)
        #expect(manifest.file("a")?.isChosen == true)
        #expect(manifest.file("b")?.isChosen == false)
    }

    @Test("Removing an album's download: its songs lose the reason; only those left with none come back")
    func removeReason() {
        var manifest = OfflineManifest()
        manifest.add(Self.file("a", [.album("al1")]))
        manifest.add(Self.file("b", [.album("al1"), .playlist("p1")]))
        manifest.add(Self.file("c", [.album("al1"), .kept]))
        manifest.add(Self.file("d", [.album("al2")]))
        let orphans = manifest.removeReason(.album("al1"))
        #expect(orphans.map(\.trackID) == ["a"])
        #expect(!manifest.has("a"))
        #expect(manifest.file("b")?.reasons == [.playlist("p1")])
        #expect(manifest.file("c")?.reasons == [.kept])
        #expect(manifest.file("d")?.reasons == [.album("al2")])
        let again = manifest.removeReason(.album("al1"))
        #expect(again.isEmpty)
    }

    @Test("The keep letting go of a few: only those, a chosen song stays, an unknown id passed over")
    func removeReasonFrom() {
        var manifest = OfflineManifest()
        manifest.add(Self.file("a", [.kept]))
        manifest.add(Self.file("b", [.kept, .playlist("p1")]))
        manifest.add(Self.file("c", [.kept]))
        let orphans = manifest.removeReason(.kept, from: ["a", "b", "nope"])
        #expect(orphans.map(\.trackID) == ["a"])
        #expect(manifest.file("b")?.reasons == [.playlist("p1")])
        #expect(manifest.file("c")?.reasons == [.kept])
        #expect(!manifest.has("nope"))
    }

    @Test("Forget: the songs whose files are gone")
    func forget() {
        var manifest = OfflineManifest()
        manifest.add(Self.file("a", [.kept]))
        manifest.add(Self.file("b", [.album("x")]))
        manifest.forget(["a", "nope"])
        #expect(!manifest.has("a"))
        #expect(manifest.has("b"))
    }

    @Test("Saved and loaded: every kind of reason, dates, qualities; the folder made")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-manifest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("deeper/manifest.json")
        var manifest = OfflineManifest()
        manifest.add(Self.file("a", [.album("al1"), .playlist("p1"), .mix("daily"), .kept], bytes: 7_765_392))
        manifest.add(Self.file("b", [.kept], bytes: 3_924_627, quality: .normal))
        manifest.add(Self.file("c", [.album("al1")], bytes: 15_369_415, quality: .original, name: "c.flac"))
        try manifest.save(to: url)
        let loaded = OfflineManifest.load(from: url)
        #expect(loaded.version == OfflineManifest.version)
        #expect(loaded.files == manifest.files)
        // Saved over: the old one replaced whole.
        var smaller = loaded
        smaller.forget(["a", "b"])
        try smaller.save(to: url)
        #expect(OfflineManifest.load(from: url).files.keys.sorted() == ["c"])
    }

    @Test("Load: missing, unreadable, or of another version is empty")
    func loadFallbacks() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-manifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(OfflineManifest.load(from: folder.appendingPathComponent("none.json")).files.isEmpty)

        let garbage = folder.appendingPathComponent("garbage.json")
        try Data("{\"version\": 1, \"files\": [".utf8).write(to: garbage)
        #expect(OfflineManifest.load(from: garbage).files.isEmpty)

        let other = folder.appendingPathComponent("v2.json")
        try Data(Self.onDisk.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8).write(to: other)
        let fromOther = OfflineManifest.load(from: other)
        #expect(fromOther.files.isEmpty)
        #expect(fromOther.version == OfflineManifest.version)
    }

    /// Version 1 as it is written: if this stops reading, the shape changed
    /// and the version must be bumped.
    static let onDisk = #"""
    {"files":{"t1":{"bytes":3924627,"fileName":"t1.m4a","quality":"normal","reasons":[{"album":{"_0":"al1"}},{"kept":{}}],"savedAt":815800000,"trackID":"t1"}},"version":1}
    """#

    @Test("The format on disk, version 1")
    func format() throws {
        let manifest = try JSONDecoder().decode(OfflineManifest.self, from: Data(Self.onDisk.utf8))
        let file = try #require(manifest.file("t1"))
        #expect(file.reasons == [.album("al1"), .kept])
        #expect(file.quality == .normal)
        #expect(file.savedAt == Self.saved)
        #expect(manifest.keptBytes == 0)
        #expect(manifest.chosenBytes == 3_924_627)
    }
}
