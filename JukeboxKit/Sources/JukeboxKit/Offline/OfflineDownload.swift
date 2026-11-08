// What the app needs around a download besides its URL (Offline.swift):
// the AAC rate of a quality, the name to save the file under, and whether
// the server's admin lets this user download at all. docs/OFFLINE.md.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension DownloadQuality {
    /// The AAC rate asked of the server, bits a second; nil for the
    /// original, which is sent as it is.
    public var aacBitrate: Int? {
        switch self {
        case .original: nil
        case .high: 256_000
        case .normal: 128_000
        }
    }
}

extension OfflineFile {
    /// The name to save a song's file under: its id and the extension of
    /// what the server sent. AVPlayer reads a local file by its extension,
    /// and downloadURL can answer with any container the phone plays (the
    /// file itself) or an m4a (a transcode), so the name comes from the
    /// answer's Content-Type, not from the quality asked for. One song and
    /// one kind of file give one name, so saving it again overwrites it.
    public static func fileName(trackID: ItemID, contentType: String?) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var stem = String(trackID.map { allowed.contains($0) ? $0 : "_" })
        if stem.isEmpty { stem = "track" }
        return "\(stem).\(fileExtension(contentType: contentType))"
    }

    /// The extension for a Content-Type as Jellyfin 12.4 sends them for
    /// downloadURL (measured: audio/mpeg, audio/flac, audio/mp4, audio/aac)
    /// and the other containers in its direct list. Anything else is m4a:
    /// what the server makes when it transcodes, the likeliest answer.
    public static func fileExtension(contentType: String?) -> String {
        let type = (contentType ?? "").split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        } ?? ""
        switch type {
        case "audio/mpeg", "audio/mp3", "audio/mpeg3", "audio/x-mpeg": return "mp3"
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/aac", "audio/aacp", "audio/x-aac": return "aac"
        case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        default: return "m4a"
        }
    }
}

/// /Users/Me, only the part that says whether downloading is allowed.
struct JellyfinUserPolicyAnswer: Decodable, Sendable {
    struct Policy: Decodable, Sendable {
        var enableContentDownloading: Bool?
        enum CodingKeys: String, CodingKey { case enableContentDownloading = "EnableContentDownloading" }
    }

    var policy: Policy?
    enum CodingKeys: String, CodingKey { case policy = "Policy" }
}

extension JellyfinClient {
    /// Whether the server's admin lets this user download (Dashboard ›
    /// Users › "Allow media downloading", the user's
    /// Policy.EnableContentDownloading). downloadURL itself is not refused
    /// when it is off — measured on 12.4: /Items/{id}/Download 403, the
    /// universal URL 200 for the same user — so it is the app that keeps to
    /// what the admin said. True when the answer does not say, as a new
    /// user's policy is on 12.4.
    public func downloadsAllowed() async throws -> Bool {
        _ = try requireUser()
        let answer = try await get(JellyfinUserPolicyAnswer.self, "/Users/Me")
        return answer.policy?.enableContentDownloading ?? true
    }
}
