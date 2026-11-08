// downloadURL against the real Jellyfin of dev/jellyfin-test-server.sh
// (12.4): one song of each format at each quality, fetched as a background
// download task fetches it (no header), and checked to be the audio file it
// says it is. Skipped when JELLYFIN_URL is not set. Lines starting
// "JELLYFIN-MEASURE" are the measurements in docs/OFFLINE.md.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Offline: downloads from the real server", .serialized, .enabled(if: JellyfinTestServer.url != nil))
struct OfflineDownloadIntegrationTests {
    /// What the bytes are, by their first bytes: FLAC's "fLaC", an MP4's
    /// "ftyp" box, MP3 (ID3 tags or a frame sync with a layer) and ADTS AAC
    /// (a frame sync with layer 0).
    static func kind(of data: Data) -> String? {
        let b = [UInt8](data.prefix(12))
        guard b.count >= 12 else { return nil }
        if b[0...3] == [0x66, 0x4C, 0x61, 0x43] { return "flac" }
        if b[4...7] == [0x66, 0x74, 0x79, 0x70] { return "m4a" }
        if b[0...2] == [0x49, 0x44, 0x33] { return "mp3" }
        if b[0] == 0xFF, b[1] & 0xF0 == 0xF0 { return b[1] & 0x06 == 0 ? "aac" : "mp3" }
        return nil
    }

    /// An MP4's top-level boxes, in order.
    static func boxes(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        var names: [String] = []
        var at = 0
        while at + 8 <= bytes.count {
            var size = bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
            let name = String(decoding: bytes[at + 4..<at + 8], as: UTF8.self)
            if size == 1, at + 16 <= bytes.count { size = bytes[at + 8..<at + 16].reduce(0) { $0 << 8 | Int($1) } }
            if size == 0 { size = bytes.count - at }
            guard size >= 8 else { break }
            names.append(name)
            at += size
        }
        return names
    }

    @Test("Each format at each quality: 200, audio, the file itself here; a lower cap gives a fragmented m4a; no token 401")
    func downloads() async throws {
        let client = try await JellyfinTestServer.client()
        let user = try client.requireUser()
        let token = try #require(client.accessToken)
        // One track per format, by the file's extension.
        let response = try await client.send("GET", "/Items", query: client.userQuery(user) + [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"), URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Path")])
        let object = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        let items = try #require(object["Items"] as? [[String: Any]])
        var byFormat: [String: String] = [:]
        for item in items {
            guard let path = item["Path"] as? String, let id = item["Id"] as? String else { continue }
            let ext = String(path.split(separator: ".").last ?? "").lowercased()
            if byFormat[ext] == nil { byFormat[ext] = id }
        }
        #expect(Set(byFormat.keys) == ["mp3", "flac", "m4a"])

        let expectedType = ["mp3": "audio/mpeg", "flac": "audio/flac", "m4a": "audio/mp4"]
        for format in ["mp3", "flac", "m4a"] {
            let id = try #require(byFormat[format])
            let track = try await client.track(id: id)
            // The file as it is, to compare with.
            let original = try await JellyfinTestServer.fetch(client.url("/Items/\(id)/Download",
                                                                         [URLQueryItem(name: "ApiKey", value: token)]))
            #expect(original.status == 200)

            for quality in DownloadQuality.allCases {
                let got = try await JellyfinTestServer.fetch(client.downloadURL(trackID: id, quality: quality))
                let type = got.jellyfinHeader("Content-Type")
                #expect(got.status == 200, "\(format) \(quality)")
                #expect(type == expectedType[format], "\(format) \(quality)")
                #expect(Self.kind(of: got.body) == format, "\(format) \(quality)")
                #expect(OfflineFile.fileExtension(contentType: type) == format)
                // These are 6–8 s tones at 105–129 kbit/s: under every
                // quality's cap, so each comes as itself, byte for byte.
                #expect(got.body == original.body, "\(format) \(quality)")
                let rate = Double(got.body.count * 8) / max(1, track.duration) / 1000
                JellyfinTestServer.measure(String(format: "download %@ .%@: %ld %@ %ld bytes (%.1f kbit/s over %.0f s), length %@, ranges %@, %@",
                                                  format, quality.rawValue, got.status, type ?? "-", got.body.count, rate, track.duration,
                                                  got.jellyfinHeader("Content-Length") ?? "-", got.jellyfinHeader("Accept-Ranges") ?? "-",
                                                  got.body == original.body ? "the file itself" : "not the file"))
            }

            // Under a cap below the file's rate it is transcoded: AAC in a
            // fragmented m4a, one response, no length known in advance.
            let normal = client.downloadURL(trackID: id, quality: .normal).absoluteString
            let capped = try #require(URL(string: normal
                .replacingOccurrences(of: "MaxStreamingBitrate=140800", with: "MaxStreamingBitrate=70400")
                .replacingOccurrences(of: "AudioBitRate=128000", with: "AudioBitRate=64000")))
            let transcoded = try await JellyfinTestServer.fetch(capped)
            #expect(transcoded.status == 200)
            #expect(transcoded.jellyfinHeader("Content-Type") == "audio/mp4")
            #expect(Self.kind(of: transcoded.body) == "m4a")
            let boxes = Self.boxes(transcoded.body)
            #expect(boxes.first == "ftyp")
            #expect(boxes.contains("moov") && boxes.contains("moof") && boxes.contains("mdat"))
            let rate = Double(transcoded.body.count * 8) / max(1, track.duration) / 1000
            // 64 kbit/s and the m4a's index: measured 67.7–68.7.
            #expect(rate > 60 && rate < 80, "\(format): \(rate) kbit/s")
            #expect(transcoded.body != original.body)
            JellyfinTestServer.measure(String(format: "download %@ capped at 70 kbit/s: %ld %@ %ld bytes (%.1f kbit/s), boxes %@, length %@",
                                              format, transcoded.status, transcoded.jellyfinHeader("Content-Type") ?? "-",
                                              transcoded.body.count, rate, boxes.joined(separator: " "),
                                              transcoded.jellyfinHeader("Content-Length") ?? "none"))
        }

        // The token is what lets a headerless download in.
        let id = try #require(byFormat["mp3"])
        let url = client.downloadURL(trackID: id, quality: .high).absoluteString
        let withoutToken = try #require(URL(string: url.replacingOccurrences(of: "&ApiKey=\(token)", with: "")))
        let oldName = try #require(URL(string: url.replacingOccurrences(of: "ApiKey=", with: "api_key=")))
        let refused = try await JellyfinTestServer.fetch(withoutToken).status
        let old = try await JellyfinTestServer.fetch(oldName).status
        #expect(refused == 401)
        JellyfinTestServer.measure("download without a token: \(refused); with api_key: \(old)")

        // The test user is the server's admin: downloads are allowed.
        #expect(try await client.downloadsAllowed())
    }
}
