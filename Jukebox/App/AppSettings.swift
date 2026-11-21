// The listener's choices, kept in UserDefaults: streaming quality on Wi-Fi
// and on the mobile network, loudness normalisation, crossfade, the Last.fm key, how
// adventurous the radio is, whether lyrics are looked up online, whether Now
// Playing's record spins, whether the music last played waits in the player
// at launch, whether the anonymous usage counts are sent, how songs are
// downloaded (Settings › Downloads), and which pages the sidebar and the tabs
// show (Settings › Pages). Observable, so a change shows at once.
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

    /// Enhance Radio with Last.fm: on, the radio asks Last.fm who sounds like
    /// whom; off, it makes no call there at all, with no key, Jukebox's or
    /// the listener's, and plays from the library alone, as a build without
    /// a key does. "is het nodig? misschien iets van 'enhance radio with
    /// last.fm' ?" (the photographer, 21 November 2026), once the app's own
    /// key meant Last.fm was always asked. On by default. What Last.fm said
    /// before stays on disk.
    var useLastFM: Bool {
        didSet {
            defaults.set(useLastFM, forKey: Keys.useLastFM)
            if useLastFM != oldValue { Stats.track(.settingChanged, ["name": "lastfm", "value": Stats.onOff(useLastFM)]) }
        }
    }

    /// The listener's own Last.fm key, optional: used in place of the app's
    /// (`appLastFMKey`) when set. Empty: none. Kept in UserDefaults, not the
    /// keychain: an API key for public data, not a password.
    var lastFMAPIKey: String {
        didSet { defaults.set(lastFMAPIKey, forKey: Keys.lastFMAPIKey) }
    }

    /// Jukebox's own Last.fm key, built in, so the radio knows who sounds
    /// like whom on every device without a key typed into each: "Ik denk dat
    /// een eigen last fm verstandiger is" (the photographer, 21 November
    /// 2026). Never in git: ci/app.sh puts it in the Info.plist from the
    /// runner's file, dev/linux-build.sh in Linux/App/AppKeys.swift from
    /// .env (docs/RADIO.md, Last.fm's key). Empty in a build without one.
    #if os(Linux)
    static let appLastFMKey = lastFMAppKey
    #else
    static let appLastFMKey = (Bundle.main.object(forInfoDictionaryKey: "LastFMAppKey") as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    #endif

    /// The key the radio asks Last.fm with: the listener's, else the app's.
    var lastFMKey: String {
        let own = lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? Self.appLastFMKey : own
    }

    var hasOwnLastFMKey: Bool { !lastFMAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The app's key in use: no key of the listener's, and the build has one.
    var usesAppLastFMKey: Bool { !hasOwnLastFMKey && !Self.appLastFMKey.isEmpty }

    /// The listener's Last.fm name, optional: with it the radio's clock
    /// reads their scrobbles from day one (docs/RADIO.md, "Scrobbles").
    /// Read only; empty: none. Never sent to Stats.
    var lastFMUser: String {
        didSet { defaults.set(lastFMUser, forKey: Keys.lastFMUser) }
    }

    /// When an album, a playlist or a mix ends, play on with a station from
    /// its last track, as Music's Autoplay does.
    var autoplay: Bool {
        didSet {
            defaults.set(autoplay, forKey: Keys.autoplay)
            if autoplay != oldValue { Stats.track(.settingChanged, ["name": "autoplay", "value": Stats.onOff(autoplay)]) }
        }
    }

    /// Crossfade, in seconds, one of `crossfades`; 0 off, as it starts.
    /// The photographer, of crossfade and the rest: "maak ze allemaal maar",
    /// and "ik wil alleen er voor waken dat we niet 10000 knopen krijgen":
    /// one choice in Settings › Playback, nothing in Now Playing. The queue
    /// fades (PlayQueue.crossfadeLevel), never within an album.
    var crossfade: Int {
        didSet {
            defaults.set(crossfade, forKey: Keys.crossfade)
            if crossfade != oldValue { Stats.track(.settingChanged, ["name": "crossfade", "value": crossfade == 0 ? "off" : "\(crossfade)"]) }
        }
    }

    /// Settings' lengths for Crossfade, in seconds; 0 is Off.
    static let crossfades = [0, 2, 4, 6, 8, 12]

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

    /// Now Playing moves: its record's label turns while music plays and
    /// the album's grooves under the page move on with each song (sketch
    /// D2, NowPlayingGround.swift). On unless the listener turns it off;
    /// off, the page is still (sketch D1, the wall), as it is anyway in Low
    /// Power Mode and under Reduce Motion — the photographer, of sketch E:
    /// "D1 is reduced motion/batterij besparing d2 normaal". The photographer, of
    /// the turntable, 8 November 2026: "dan zou ik ook de plaat willen zien
    /// draaien" — and "Als batterij een zorg wordt moeten we ook ff kijken
    /// wat we daar aan kunnen doen": this is the switch for that.
    var spinRecord: Bool {
        didSet {
            defaults.set(spinRecord, forKey: Keys.spinRecord)
            if spinRecord != oldValue { Stats.track(.settingChanged, ["name": "spin_record", "value": Stats.onOff(spinRecord)]) }
        }
    }

    /// At launch, the music last played (here, or left off on another
    /// device) waits in the player, paused, rather than in Home's notice
    /// (HandoffStore). The photographer, 14 November 2026, of "Where you
    /// left off · Continue": "ik denk dat het nummer gewoon onderin de player
    /// al klaar moet staan, optie voor in preferences die standaard aan staat".
    var resumeOnLaunch: Bool {
        didSet {
            defaults.set(resumeOnLaunch, forKey: Keys.resumeOnLaunch)
            if resumeOnLaunch != oldValue { Stats.track(.settingChanged, ["name": "resume_on_launch", "value": Stats.onOff(resumeOnLaunch)]) }
        }
    }

    /// Settings' Share Anonymous Usage (Stats, docs/STATS.md): on unless the
    /// listener turns it off. The photographer, 8 November 2026: "Kun je ook
    /// aptabase toevoegen van mijn account en alles tracken wat je mag zonder
    /// cookie melding" — the app sets no cookie and keeps no id for them, so
    /// nothing is asked first; the switch is the way out.
    var shareUsage: Bool {
        didSet {
            // Turned off: counted once, before it is written, while counting
            // is still on (Stats.on reads the defaults); nothing after it.
            // Turned on is not counted.
            if oldValue, !shareUsage { Stats.track(.settingChanged, ["name": "share_usage", "value": "off"]) }
            defaults.set(shareUsage, forKey: Keys.shareUsage)
        }
    }

    /// Settings › Downloads › Keep Songs I Play: what is played often or
    /// lately stays on the phone, up to `keepLimitGB` (OfflineStore, through
    /// JukeboxKit's KeepPolicy). On, at 5 GB, unless turned off: the
    /// photographer, asked whether the app should "automatisch bewaren wat je
    /// vaak of kort geleden hebt gespeeld, tot een grootte die je kiest",
    /// answered "Alle drie" (8 November 2026). Off, what it alone held goes.
    /// Read as `shareUsage` is, so a launch argument ("-keepSongs NO") turns
    /// it off too.
    var keepSongs: Bool {
        didSet {
            defaults.set(keepSongs, forKey: Keys.keepSongs)
            if keepSongs != oldValue { Stats.track(.settingChanged, ["name": "keep_songs", "value": Stats.onOff(keepSongs)]) }
        }
    }

    /// How much the keep may hold, in gigabytes: one of `keepLimits`.
    var keepLimitGB: Int {
        didSet { defaults.set(keepLimitGB, forKey: Keys.keepLimitGB) }
    }

    /// The quality songs are downloaded in, chosen ones and kept ones alike.
    /// High (AAC at 256 kbit/s) by default: a file the phone keeps is space
    /// it does not have, and an original can be ten times the size.
    var downloadQuality: DownloadQuality {
        didSet { defaults.set(downloadQuality.rawValue, forKey: Keys.downloadQuality) }
    }

    /// Downloads may use the mobile network (a hotspot, Low Data Mode too).
    /// Off by default: they wait for Wi-Fi.
    var downloadOverCellular: Bool {
        didSet { defaults.set(downloadOverCellular, forKey: Keys.downloadOverCellular) }
    }

    /// A page with a switch in Settings › Pages, in the sidebar's order, by
    /// the places' names in the usage counts. Home has none: it is always
    /// there. The photographer, 15 November 2026: "wellicht ook in de
    /// preferences dat je alle pagina's zelf aan of uit kan zetten naast home
    /// (dan zijn er uberhaupt geen pages) kan je zelf bepalen hoe
    /// minimalistisch je alles wilt hebben". A plain value, of no actor, as
    /// DesktopMeasures' are: SwiftUI's lists and Sets take it anywhere.
    nonisolated enum Page: String, CaseIterable, Sendable {
        case radio
        case albums, artists, songs, playlists, favorites, genres
        case recentlyAdded = "recently_added"
        case downloaded
        /// The playlists themselves, under the sidebar's kinds.
        case sidebarPlaylists = "sidebar_playlists"

        /// One of the library's kinds: the iPhone's Library tab has it.
        var isLibraryKind: Bool { self != .radio && self != .sidebarPlaylists }
    }

    /// The pages switched off. The ones off are kept rather than the ones
    /// on, so a page added later starts on. A page that is off leaves the
    /// sidebar and the tabs only: it stays reachable from Home and Search.
    var hiddenPages: Set<Page> {
        didSet {
            defaults.set(hiddenPages.map(\.rawValue).sorted(), forKey: Keys.hiddenPages)
            for page in hiddenPages.symmetricDifference(oldValue) {
                Stats.track(.settingChanged, ["name": "page_\(page.rawValue)", "value": Stats.onOff(!hiddenPages.contains(page))])
            }
        }
    }

    func shows(_ page: Page) -> Bool { !hiddenPages.contains(page) }

    func setShows(_ page: Page, _ shown: Bool) {
        if shown { hiddenPages.remove(page) } else { hiddenPages.insert(page) }
    }

    /// Any page but Home on: the wide window has its sidebar. Every one off,
    /// only Home is left and the sidebar goes ("dan zijn er uberhaupt geen
    /// pages").
    var showsAnyPage: Bool { Page.allCases.contains(where: shows) }

    /// Any of the library's kinds on: the iPhone has its Library tab.
    var showsLibrary: Bool { Page.allCases.contains { $0.isLibraryKind && shows($0) } }

    /// Settings' sizes for the keep, in gigabytes.
    static let keepLimits = [1, 2, 5, 10, 20]

    /// The keep's limit in bytes, as the system counts storage (a gigabyte
    /// is a thousand million bytes in Settings › General › iPhone Storage).
    var keepLimitBytes: Int64 { Int64(keepLimitGB) * 1_000_000_000 }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wifiQuality = StreamQuality(rawValue: defaults.string(forKey: Keys.wifiQuality) ?? "") ?? .original
        cellularQuality = StreamQuality(rawValue: defaults.string(forKey: Keys.cellularQuality) ?? "") ?? .normal
        normalizeVolume = defaults.object(forKey: Keys.normalizeVolume) as? Bool ?? true
        useLastFM = defaults.object(forKey: Keys.useLastFM) as? Bool ?? true
        lastFMAPIKey = defaults.string(forKey: Keys.lastFMAPIKey) ?? ""
        lastFMUser = defaults.string(forKey: Keys.lastFMUser) ?? ""
        autoplay = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        adventurousness = defaults.object(forKey: Keys.adventurousness) as? Double ?? 0.35
        let crossfade = defaults.integer(forKey: Keys.crossfade)
        self.crossfade = Self.crossfades.contains(crossfade) ? crossfade : 0
        findLyricsOnline = defaults.object(forKey: Keys.findLyricsOnline) as? Bool ?? true
        spinRecord = defaults.object(forKey: Keys.spinRecord) as? Bool ?? true
        resumeOnLaunch = defaults.object(forKey: Keys.resumeOnLaunch) as? Bool ?? true
        // As Stats.on reads it: a launch argument ("-shareUsage NO") is a
        // string, which `as? Bool` would not read.
        shareUsage = defaults.object(forKey: Keys.shareUsage) == nil || defaults.bool(forKey: Keys.shareUsage)
        keepSongs = defaults.object(forKey: Keys.keepSongs) == nil || defaults.bool(forKey: Keys.keepSongs)
        let limit = defaults.integer(forKey: Keys.keepLimitGB)
        keepLimitGB = Self.keepLimits.contains(limit) ? limit : 5
        downloadQuality = DownloadQuality(rawValue: defaults.string(forKey: Keys.downloadQuality) ?? "") ?? .high
        downloadOverCellular = defaults.object(forKey: Keys.downloadOverCellular) as? Bool ?? false
        hiddenPages = Set((defaults.stringArray(forKey: Keys.hiddenPages) ?? []).compactMap(Page.init(rawValue:)))
    }

    /// Last.fm is asked: switched on, and a key to ask with. Every call the
    /// radio makes there goes through this (RadioController.makeService).
    var hasLastFM: Bool { useLastFM && !lastFMKey.isEmpty }

    private enum Keys {
        static let wifiQuality = "wifiQuality"
        static let cellularQuality = "cellularQuality"
        static let normalizeVolume = "normalizeVolume"
        static let useLastFM = "useLastFM"
        static let lastFMAPIKey = "lastFMAPIKey"
        static let lastFMUser = "lastFMUser"
        static let adventurousness = "adventurousness"
        static let autoplay = "autoplay"
        static let crossfade = "crossfade"
        static let findLyricsOnline = "findLyricsOnline"
        static let spinRecord = "spinRecord"
        static let resumeOnLaunch = "resumeOnLaunch"
        static let shareUsage = Stats.key
        static let keepSongs = "keepSongs"
        static let keepLimitGB = "keepLimitGB"
        static let downloadQuality = "downloadQuality"
        static let downloadOverCellular = "downloadOverCellular"
        static let hiddenPages = "hiddenPages"
    }
}
