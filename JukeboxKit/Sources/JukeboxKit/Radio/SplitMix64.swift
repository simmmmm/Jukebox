// The radio's own random numbers: SplitMix64 (Steele, Lea and Flood, 2014),
// so a station is the same for the same seed on every device and in every
// test, and nothing depends on the system's generator. Public, so the mixes
// can be "the same for a whole day" from a seed made of the date.

import Foundation

public struct SplitMix64: RandomNumberGenerator, Sendable, Hashable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0 ..< 1, from the top 53 bits.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// A seed from a string that is the same in every process (FNV-1a),
    /// unlike `hashValue`: "daily-2026-11-08" gives the same mix all day.
    public static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
