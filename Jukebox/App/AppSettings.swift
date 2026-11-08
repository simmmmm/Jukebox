// The listener's choices, kept in UserDefaults: streaming quality on Wi-Fi
// and on the mobile network, loudness normalisation, the Last.fm key, how
// adventurous the radio is, whether lyrics are looked up online, whether the
// anonymous usage counts are sent. Observable, so a change shows at once.
// A change of a choice is itself counted (Stats, `setting_changed`): its
// name and its new value, which are Jukebox's own words, never the key.

import Foundation
import JukeboxKit
import Observation

@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var wifiQuality: StreamQuality {
        didSet {
            defaults.set(wifiQuality.rawValue, forKey: Keys.wifiQuality)
            if wifiQuality != oldValue { Stats.track(.settingChanged, ["name": "wifi_quality", "value": wifiQuality.rawValue]) }
        }
    }

    var cellularQuality: StreamQuality {
        didSet {
            defaults.set(cellularQuality.rawValue, forKey: Keys.cellularQuality)
            if cellularQuality != oldValue { Stats.track(.settingChanged, ["name": "cellular_quality", "value": cellularQuality.rawValue]) }
        }
    }

    /// Play every track at the loudness Jellyfin measured (10.9+), so a
    /// quiet old record and a loud new one sit side by side on the radio.
    var normalizeVolume: Bool {
        didSet {
            defaults.set(normalizeVolume, forKey: Keys.normalizeVolume)
            if normalizeVolume != oldValue { Stats.track(.settingChanged, ["name": "normalize", "value": Stats.onOff(normalizeVolume)]) }
        }
    }

    /// Empty: no Last.fm. Kept in UserDefaults, not the keychain: an API
    /// key for public data, not a password.
    var lastFMAPIKey: String {
        didSet { defaults.set(lastFMAPIKey, forKey: Keys.lastFMAPIKey) }
    }

    /// When an album, a playlist or a mix ends, play on with a station from
    /// its last track, as Music's Autoplay does.
    var autoplay: Bool {
        didSet {
            defaults.set(autoplay, forKey: Keys.autoplay)
            if autoplay != oldValue { Stats.track(.settingChanged, ["name": "autoplay", "value": Stats.onOff(autoplay)]) }
        }
    }

    /// The radio's dial, 0 familiar … 1 adventurous.
    var adventurousness: Double {
        didSet { defaults.set(adventurousness, forKey: Keys.adventurousness) }
    }

    /// When the server has no lyrics for a song, look on LRCLIB. On unless
    /// the listener turns it off: most libraries have no lyrics of their
    /// own, and the photographer asked for lyrics ("Kun je ook lyrics
    /// toevoegen", 8 November 2026).
    var findLyricsOnline: Bool {
        didSet {
            defaults.set(findLyricsOnline, forKey: Keys.findLyricsOnline)
            if findLyricsOnline != oldValue { Stats.track(.settingChanged, ["name": "find_lyrics_online", "value": Stats.onOff(findLyricsOnline)]) }
        }
    }

    /// Settings' Share Anonymous Usage (Stats, docs/STATS.md): on unless the
    /// listener turns it off. The photographer, 8 November 2026: "Kun je ook
    /// aptabase toevoegen van mijn account en alles tracken wat je mag zonder
    /// cookie melding" — Aptabase sets no cookie and keeps no device id or
    /// address, so nothing is asked first; the switch is the way out.
    var shareUsage: Bool {
        didSet {
            // Turned off: counted once, before it is written, while counting
            // is still on (Stats.on reads the defaults); nothing after it.
            // Turned on is not counted.
            if oldValue, !shareUsage { Stats.track(.settingChanged, ["name": "share_usage", "value": "off"]) }
            defaults.set(shareUsage, forKey: Keys.shareUsage)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wifiQuality = StreamQuality(rawValue: defaults.string(forKey: Keys.wifiQuality) ?? "") ?? .original
        cellularQuality = StreamQuality(rawValue: defaults.string(forKey: Keys.cellularQuality) ?? "") ?? .normal
        normalizeVolume = defaults.object(forKey: Keys.normalizeVolume) as? Bool ?? true
        lastFMAPIKey = defaults.string(forKey: Keys.lastFMAPIKey) ?? ""
        autoplay = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        adventurousness = defaults.object(forKey: Keys.adventurousness) as? Double ?? 0.35
        findLyricsOnline = defaults.object(forKey: Keys.findLyricsOnline) as? Bool ?? true
        // As Stats.on reads it: a launch argument ("-shareUsage NO") is a
        // string, which `as? Bool` would not read.
        shareUsage = defaults.object(forKey: Keys.shareUsage) == nil || defaults.bool(forKey: Keys.shareUsage)
    }

    var hasLastFM: Bool { !lastFMAPIKey.trimmingCharacters(in: .whitespaces).isEmpty }

    private enum Keys {
        static let wifiQuality = "wifiQuality"
        static let cellularQuality = "cellularQuality"
        static let normalizeVolume = "normalizeVolume"
        static let lastFMAPIKey = "lastFMAPIKey"
        static let adventurousness = "adventurousness"
        static let autoplay = "autoplay"
        static let findLyricsOnline = "findLyricsOnline"
        static let shareUsage = Stats.key
    }
}
