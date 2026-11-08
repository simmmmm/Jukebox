// The download URL's shape, the file's name and the admin's word on
// downloading. The URL against the real server: OfflineIntegrationTests.swift.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import JukeboxKit

@Suite("Offline: the download URL")
struct OfflineDownloadTests {
    @Test("Universal, plain HTTP (never HLS), AAC in m4a, the cap 10% over the quality, ApiKey")
    func downloadURL() throws {
        let client = JellyfinFixtures.client(JellyfinMockTransport(body: ""))
        for quality in DownloadQuality.allCases {
            let url = client.downloadURL(trackID: "track1", quality: quality)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.scheme == "https")
            #expect(components.host == "jf.example.com")
            #expect(components.path == "/jellyfin/Audio/track1/universal")
            let query = URLRequest(url: url).jellyfinQuery
            #expect(query["UserId"] == JellyfinFixtures.userID)
            #expect(query["DeviceId"] == "device-1")
            #expect(query["Container"] == "mp3,aac,m4a|aac,m4a|alac,m4b|aac,mp4|aac,mp4|alac,flac,alac,wav,aiff")
            #expect(query["TranscodingContainer"] == "m4a")
            #expect(query["TranscodingProtocol"] == "http")
            #expect(query["AudioCodec"] == "aac")
            #expect(query["ApiKey"] == JellyfinFixtures.token)
            #expect(query["api_key"] == nil)
            // A download is not a play: no play session to report.
            #expect(query["PlaySessionId"] == nil)
            switch quality {
            case .original:
                #expect(query["MaxStreamingBitrate"] == nil)
                #expect(query["AudioBitRate"] == "256000")
            case .high:
                #expect(query["MaxStreamingBitrate"] == "281600")
                #expect(query["AudioBitRate"] == "256000")
            case .normal:
                #expect(query["MaxStreamingBitrate"] == "140800")
                #expect(query["AudioBitRate"] == "128000")
            }
            #expect(!url.absoluteString.contains("hls"))
        }
        let signedOut = JellyfinFixtures.client(JellyfinMockTransport(body: ""), signedIn: false)
        #expect(URLRequest(url: signedOut.downloadURL(trackID: "t", quality: .high)).jellyfinQuery["ApiKey"] == nil)
        // An id is one escaped path segment.
        #expect(client.downloadURL(trackID: "a/b c", quality: .normal).absoluteString.contains("/Audio/a%2Fb%20c/universal?"))
    }

    @Test("The file's name: the id and the extension of what came")
    func fileName() {
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: "audio/mp4") == "2c4a765f.m4a")
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: "audio/flac") == "2c4a765f.flac")
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: "audio/mpeg") == "2c4a765f.mp3")
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: "audio/aac") == "2c4a765f.aac")
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: "Audio/MPEG; charset=binary") == "2c4a765f.mp3")
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: "audio/x-wav") == "2c4a765f.wav")
        #expect(OfflineFile.fileName(trackID: "2c4a765f", contentType: nil) == "2c4a765f.m4a")
        #expect(OfflineFile.fileName(trackID: "../x y", contentType: "audio/aiff") == "___x_y.aiff")
        #expect(OfflineFile.fileName(trackID: "", contentType: "audio/mp4") == "track.m4a")
    }

    @Test("Downloads allowed: the user's policy, true when it does not say")
    func downloadsAllowed() async throws {
        let off = JellyfinMockTransport(body: #"{"Name":"nodl","Id":"u","Policy":{"IsAdministrator":false,"EnableContentDownloading":false}}"#)
        #expect(try await JellyfinFixtures.client(off).downloadsAllowed() == false)
        #expect(off.requests.map(\.jellyfinPath) == ["/jellyfin/Users/Me"])
        let on = JellyfinMockTransport(body: #"{"Name":"test","Id":"u","Policy":{"EnableContentDownloading":true}}"#)
        #expect(try await JellyfinFixtures.client(on).downloadsAllowed() == true)
        let silent = JellyfinMockTransport(body: #"{"Name":"test","Id":"u"}"#)
        #expect(try await JellyfinFixtures.client(silent).downloadsAllowed() == true)
        await #expect(throws: JellyfinError.notSignedIn) {
            try await JellyfinFixtures.client(silent, signedIn: false).downloadsAllowed()
        }
    }
}
