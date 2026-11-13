// Anonymous usage counts on the photographer's own OpenPanel server
// (stats.numa.photo, open source), as Numa counts (Numa-mac's Stats.swift),
// with one difference: on until the listener turns them off. The
// photographer, 8 November 2026: "Kun je ook aptabase toevoegen van mijn
// account en alles tracken wat je mag zonder cookie melding." OpenPanel and
// not Aptabase since 13 November 2026: the photographer wants to see the
// order of what someone does in one visit and where a visit ends, and
// Aptabase only counts. The app sets no cookie and keeps no id for it: the
// server ties one visit's events together itself. Settings › Privacy › Share
// Anonymous Usage turns it off; from then on nothing is set up or sent
// (`track` returns first).
//
// The events are a closed list (`Name`) with coarse properties from fixed
// lists: a screen's kind, a station's kind of seed, a bucket. Never a title,
// an artist, an album, a search, a server's address or name, a user, an id.
// Every event also carries the app version and build, the system and its
// version, the language and the device model. docs/STATS.md has every event
// and the question it answers.

import AVFoundation
import Foundation
import JukeboxKit
import SwiftUI

/// What a property may be: a word from the app's own lists, a number, yes or no.
nonisolated protocol Value {}
extension String: Value {}
extension Bool: Value {}
extension Int: Value {}
extension Double: Value {}

enum Stats {
    /// AppSettings.shareUsage's key. Read here as well: the counts come
    /// from everywhere, the settings object only from the environment.
    static let key = "shareUsage"

    /// Every event there is. A new one goes here and in docs/STATS.md, in
    /// the same change.
    enum Name: String {
        case appOpen = "app_open"
        case signedIn = "signed_in"
        case signInFailed = "sign_in_failed"
        case signedOut = "signed_out"
        case libraryLoaded = "library_loaded"
        case screen
        case playStarted = "play_started"
        case stationStarted = "station_started"
        case stationPage = "station_page"
        case radioFeedback = "radio_feedback"
        case dialChanged = "dial_changed"
        case trackEnded = "track_ended"
        case lyricsShown = "lyrics_shown"
        case mixOpened = "mix_opened"
        case mixPlayed = "mix_played"
        case playlistCreated = "playlist_created"
        case playlistSongsAdded = "playlist_songs_added"
        case favoriteSet = "favorite_set"
        case searchUsed = "search_used"
        case settingChanged = "setting_changed"
        case lastFMKey = "lastfm_key"
        case playbackError = "playback_error"
        case downloadChosen = "download_chosen"
        case offlinePlayStarted = "offline_play_started"
    }

    /// On unless turned off. Read with `bool(forKey:)` once the key is
    /// there, so a launch argument ("-shareUsage NO") turns it off too.
    static var on: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    /// Where the events go, and the project they belong to. The id and the
    /// secret come from the OpenPanel project (Settings › Clients); while the
    /// id is empty nothing is sent.
    static let api = URL(string: "https://stats.numa.photo/api/track")!
    static let clientID = ""
    static let clientSecret = ""

    static func track(_ name: Name, _ props: [String: Value] = [:]) {
        guard on, !clientID.isEmpty else { return }
        var properties: [String: Any] = props
        properties["__version"] = version
        properties["__buildNumber"] = build
        properties["__timestamp"] = ISO8601DateFormatter().string(from: Date())
        properties["locale"] = Locale.preferredLanguages.first ?? ""
        properties["model"] = model
        // Xcode's and CI's builds, kept apart on the server.
        #if DEBUG
        properties["debug"] = true
        #endif
        let event: [String: Any] = ["type": "track", "payload": ["name": name.rawValue, "properties": properties]]
        guard let body = try? JSONSerialization.data(withJSONObject: event) else { return }
        var request = URLRequest(url: api)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue(clientID, forHTTPHeaderField: "openpanel-client-id")
        if !clientSecret.isEmpty {
            request.setValue(clientSecret, forHTTPHeaderField: "openpanel-client-secret")
        }
        Wire.shared.send(request)
    }

    // MARK: Buckets: coarse, so no number tells one library from another

    /// A library's songs.
    static func trackCount(_ count: Int) -> String {
        switch count {
        case ..<100: return "<100"
        case ..<1_000: return "100-999"
        case ..<10_000: return "1k-9k"
        default: return "10k+"
        }
    }

    /// How long something took, in seconds.
    static func duration(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<1: return "<1"
        case ..<5: return "1-5"
        case ..<30: return "5-30"
        default: return "30+"
        }
    }

    /// What a search found.
    static func resultCount(_ count: Int) -> String {
        switch count {
        case ..<1: return "0"
        case ..<10: return "1-9"
        default: return "10+"
        }
    }

    /// The radio's dial, in fifths.
    static func dial(_ value: Double) -> String {
        switch value {
        case ..<0.2: return "0-0.2"
        case ..<0.4: return "0.2-0.4"
        case ..<0.6: return "0.4-0.6"
        case ..<0.8: return "0.6-0.8"
        default: return "0.8-1"
        }
    }

    /// A switch's value.
    static func onOff(_ isOn: Bool) -> String {
        isOn ? "on" : "off"
    }

    // MARK: Kinds, never the thing itself

    /// A station by its kind of seed: never the artist, album or genre.
    static func seed(_ seed: StationSeed) -> String {
        switch seed {
        case .track: return "track"
        case .artist: return "artist"
        case .album: return "album"
        case .genre: return "genre"
        case .decade: return "decade"
        case .collection: return "collection"
        case .personal: return "personal"
        case .discovery: return "discovery"
        case .favorites: return "favorites"
        }
    }

    /// What a queue was started from.
    static func source(_ kind: QueueContext.Kind) -> String {
        switch kind {
        case .album: return "album"
        case .artist: return "artist"
        case .playlist: return "playlist"
        case .mix: return "mix"
        case .genre: return "genre"
        case .songs: return "songs"
        case .favorites: return "favorites"
        case .search: return "search"
        case .radio: return "station"
        case .other: return "other"
        }
    }

    /// The kind of server, coarsely: `jellyfin`, `navidrome`, or `subsonic`
    /// for every other Subsonic server (Gonic, Airsonic, …, and one that
    /// names itself: never its own word); `none` signed out. Never which
    /// server, nor its version.
    static func server(_ kind: ServerKind?) -> String {
        switch kind {
        case .jellyfin?: return "jellyfin"
        case .subsonic(.navidrome)?: return "navidrome"
        case .subsonic?: return "subsonic"
        case nil: return "none"
        }
    }

    /// Why signing in did not work, from the servers' errors; never the
    /// message, which can hold the address.
    static func signInFailure(_ error: Error, quickConnect: Bool = false) -> String {
        switch error as? MusicServerError {
        case .transport?:
            return "unreachable"
        case .invalidServerAddress?:
            // `not_jellyfin` before 9 November 2026, when only Jellyfin was.
            return "not_a_server"
        case .unauthorized?:
            // For Quick Connect the server says so when Quick Connect is
            // turned off there, not of a password.
            return quickConnect ? "other" : "wrong_password"
        case .needsAPIKey?:
            return "needs_api_key"
        case .passwordNeedsHTTPS?:
            return "needs_https"
        default:
            return "other"
        }
    }

    /// Why a song could not be played, from the error AVFoundation gave:
    /// the network (a URL error, or one under it), the server (its setup,
    /// or not letting this client have the song), a file it cannot read.
    static func playbackFailure(_ error: Error?) -> String {
        guard let error else { return "other" }
        let failure = error as NSError
        let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        if failure.domain == NSURLErrorDomain || underlying?.domain == NSURLErrorDomain { return "network" }
        guard failure.domain == AVFoundationErrorDomain else { return "other" }
        switch AVError.Code(rawValue: failure.code) {
        case .fileFormatNotRecognized?, .fileFailedToParse?, .decoderNotFound?, .decodeFailed?:
            return "unsupported"
        case .serverIncorrectlyConfigured?, .contentIsNotAuthorized?:
            return "server"
        default:
            return "other"
        }
    }

    /// Where the lyrics shown for a song came from, and whether they are
    /// timed; never the song or its words.
    static func lyrics(_ answer: LyricsAnswer) -> [String: Value] {
        switch answer {
        case let .lyrics(lyrics, fromLRCLIB):
            return ["source": fromLRCLIB ? "lrclib" : "server", "synced": lyrics.isSynced]
        case .instrumental, .notFound:
            return ["source": "none", "synced": false]
        case .failed:
            return ["source": "failed", "synced": false]
        }
    }

    // MARK: What every event carries

    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    /// The device model as the system names it ("iPhone17,1", "Mac15,6").
    private static let model: String = {
        var size = 0
        #if os(macOS)
        let name = "hw.model"
        #else
        let name = "hw.machine"
        #endif
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &value, &size, nil, 0)
        return String(cString: value)
    }()

    /// A browser's kind of user agent: OpenPanel reads the system and its
    /// version from it, as it does for a website.
    private static let agent: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let system = "\(v.majorVersion)_\(v.minorVersion)"
        #if os(macOS)
        let device = "Macintosh; Intel Mac OS X \(system)"
        #else
        let device = model.hasPrefix("iPad") ? "iPad; CPU OS \(system) like Mac OS X" : "iPhone; CPU iPhone OS \(system) like Mac OS X"
        #endif
        return "Mozilla/5.0 (\(device)) AppleWebKit/605.1.15 (KHTML, like Gecko) Jukebox/\(version)"
    }()
}

extension View {
    /// `action` once for as long as this view lives: a page pushed, a sheet
    /// or a cover opened, a panel shown. Not again when it shows again after
    /// what covered it has gone, as `onAppear` alone would: then Back would
    /// count as another visit.
    func countsOnce(_ action: @escaping () -> Void) -> some View {
        modifier(StatsOnce(action: action))
    }

    /// The `screen` event for this view, once for as long as it lives.
    /// `name` is a kind of screen from docs/STATS.md, never what it shows.
    func countsScreen(_ name: String) -> some View {
        countsOnce { Stats.track(.screen, ["name": name]) }
    }
}

private struct StatsOnce: ViewModifier {
    let action: () -> Void
    @State private var isCounted = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !isCounted else { return }
            isCounted = true
            action()
        }
    }
}

/// Sends the events one at a time, in order. One that got no answer (no
/// network) waits for the next event and goes first then; one the server
/// answered, also with a refusal, is done.
// ponytail: waits in memory only, 200 at most, gone when the app quits; a
// file on disk if visits without a network turn out to matter.
// `nonisolated`: the app's types are the main actor's unless they say so
// (project.yml), and this one works on its own queue.
private nonisolated final class Wire: @unchecked Sendable {
    static let shared = Wire()
    private let queue = DispatchQueue(label: "jukebox.stats")
    private var waiting: [URLRequest] = []
    private var sending = false

    func send(_ request: URLRequest) {
        queue.async {
            if self.waiting.count < 200 { self.waiting.append(request) }
            self.next()
        }
    }

    /// On `queue`.
    private func next() {
        guard !sending, let request = waiting.first else { return }
        sending = true
        URLSession.shared.dataTask(with: request) { _, response, _ in
            self.queue.async {
                self.sending = false
                guard response is HTTPURLResponse else { return }
                self.waiting.removeFirst()
                self.next()
            }
        }.resume()
    }
}
