// Now Playing's "Lossless" (Server/Lossless.swift): what the engine is
// given, by the track's container and the quality it was asked at.

import Testing
@testable import JukeboxKit

@Suite("Lossless: the container, and the sound as the engine gets it")
struct LosslessTests {
    @Test("Lossless by the container alone; m4a and Jellyfin's lists are not")
    func containers() {
        for kind in ["flac", "FLAC", "wav", "aiff", "aif", "alac", "ape", "wv", "tta", "dsf", "dff"] {
            #expect(Lossless.isLossless(kind), "\(kind)")
        }
        for kind in ["mp3", "m4a", "mp4", "m4b", "aac", "ogg", "opus", "mov,mp4,m4a,3gp,3g2,mj2", ""] {
            #expect(!Lossless.isLossless(kind), "\(kind)")
        }
        #expect(!Lossless.isLossless(nil))
    }

    @Test("Heard lossless only as the file is: streamed at Original, or kept at Original")
    func heard() {
        #expect(Lossless.heard("flac", streamedAt: .original, keptAt: nil))
        #expect(Lossless.heard("Wav", streamedAt: .original, keptAt: nil))
        for lower in [StreamQuality.high, .normal, .efficient, .low] {
            #expect(!Lossless.heard("flac", streamedAt: lower, keptAt: nil), "\(lower)")
        }
        #expect(!Lossless.heard("m4a", streamedAt: .original, keptAt: nil), "ALAC or AAC: not known")
        #expect(!Lossless.heard(nil, streamedAt: .original, keptAt: nil))
        #expect(!Lossless.heard("flac", streamedAt: nil, keptAt: nil), "nothing given")
        // A kept file is what it was saved as, whatever the stream would be.
        #expect(Lossless.heard("flac", streamedAt: .low, keptAt: .original))
        #expect(!Lossless.heard("flac", streamedAt: .original, keptAt: .high))
        // Converted by every server even at Original.
        for kind in ["ape", "wv", "tta", "dsf", "dff"] {
            #expect(!Lossless.heard(kind, streamedAt: .original, keptAt: nil), "\(kind)")
            #expect(!Lossless.heard(kind, streamedAt: nil, keptAt: .original), "\(kind) kept")
        }
    }
}
