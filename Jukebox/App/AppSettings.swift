// The listener's choices, kept in UserDefaults: streaming quality on Wi-Fi
// and on the mobile network, loudness normalisation, the Last.fm key, how
// adventurous the radio is. Observable, so a change shows at once.

import Foundation
import JukeboxKit
import Observation

@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var wifiQuality: StreamQuality {
        didSet { defaults.set(wifiQuality.rawValue, forKey: Keys.wifiQuality) }
    }

    var cellularQuality: StreamQuality {
        didSet { defaults.set(cellularQuality.rawValue, forKey: Keys.cellularQuality) }
    }

    /// Play every track at the loudness Jellyfin measured (10.9+), so a
    /// quiet old record and a loud new one sit side by side on the radio.
    var normalizeVolume: Bool {
        didSet { defaults.set(normalizeVolume, forKey: Keys.normalizeVolume) }
    }

    /// Empty: no Last.fm. Kept in UserDefaults, not the keychain: an API
    /// key for public data, not a password.
    var lastFMAPIKey: String {
        didSet { defaults.set(lastFMAPIKey, forKey: Keys.lastFMAPIKey) }
    }

    /// When an album, a playlist or a mix ends, play on with a station from
    /// its last track, as Music's Autoplay does.
    var autoplay: Bool {
        didSet { defaults.set(autoplay, forKey: Keys.autoplay) }
    }

    /// The radio's dial, 0 familiar … 1 adventurous.
    var adventurousness: Double {
        didSet { defaults.set(adventurousness, forKey: Keys.adventurousness) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wifiQuality = StreamQuality(rawValue: defaults.string(forKey: Keys.wifiQuality) ?? "") ?? .original
        cellularQuality = StreamQuality(rawValue: defaults.string(forKey: Keys.cellularQuality) ?? "") ?? .normal
        normalizeVolume = defaults.object(forKey: Keys.normalizeVolume) as? Bool ?? true
        lastFMAPIKey = defaults.string(forKey: Keys.lastFMAPIKey) ?? ""
        autoplay = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        adventurousness = defaults.object(forKey: Keys.adventurousness) as? Double ?? 0.35
    }

    var hasLastFM: Bool { !lastFMAPIKey.trimmingCharacters(in: .whitespaces).isEmpty }

    private enum Keys {
        static let wifiQuality = "wifiQuality"
        static let cellularQuality = "cellularQuality"
        static let normalizeVolume = "normalizeVolume"
        static let lastFMAPIKey = "lastFMAPIKey"
        static let adventurousness = "adventurousness"
        static let autoplay = "autoplay"
    }
}
