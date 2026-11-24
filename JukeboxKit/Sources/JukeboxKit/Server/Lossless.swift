// Whether the song playing is heard lossless, for the word "Lossless" on
// Now Playing: "op ios wil ik ergens net als Spotify duiden als originals
// lossless zijn dat we dat tonen als je gaat streamen" (the photographer,
// 24 November 2026). So it says what reaches the engine, not what the file
// on the server is: a FLAC streamed at High is AAC by then.
//
// All a track says about its file is its container (`Track.container`), so
// that decides. Pure.

import Foundation

public enum Lossless {
    /// Containers whose sound is lossless by the container alone.
    // ponytail: ALAC in an .m4a (and .mp4, .m4b) reads as not lossless, as
    // the container cannot tell it from AAC. Once Track carries the codec
    // (Jellyfin's MediaStreams `Codec`, OpenSubsonic's `codec` and
    // `bitDepth`, Plex's `audioCodec`), "alac" there makes it lossless too.
    static let containers: Set<String> = ["flac", "wav", "aiff", "aif", "alac", "ape", "wv", "tta", "dsf", "dff"]

    /// Lossless, but no server sends them as they are even at Original:
    /// Jellyfin's `directContainers` leave them out (AAC), Subsonic's and
    /// Plex's `unplayable` make them MP3 at 320, and so do their downloads.
    static let convertedAnyway: Set<String> = ["ape", "wv", "tta", "dsf", "dff"]

    /// Whether a container is lossless ("flac", "WAV"); Jellyfin's lists
    /// ("mov,mp4,m4a,…") and nil are not.
    public static func isLossless(_ container: String?) -> Bool {
        container.map { containers.contains($0.lowercased()) } ?? false
    }

    /// Whether the engine is given the song lossless: a kept file saved at
    /// Original (`keptAt`), else a stream asked at Original (`streamedAt`),
    /// of a lossless container the server sends as it is. Every other
    /// quality converts (AAC, MP3 or Opus).
    public static func heard(_ container: String?, streamedAt: StreamQuality?, keptAt: DownloadQuality?) -> Bool {
        guard isLossless(container), let kind = container?.lowercased(), !convertedAnyway.contains(kind) else { return false }
        if let keptAt { return keptAt == .original }
        return streamedAt == .original
    }
}
