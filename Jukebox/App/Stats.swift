// Anonymous usage counts on the photographer's own Aptabase server
// (stats.numa.photo, open source), as Numa counts (Numa-mac's Stats.swift),
// with one difference: on until the listener turns them off. The
// photographer, 8 November 2026: "Kun je ook aptabase toevoegen van mijn
// account en alles tracken wat je mag zonder cookie melding." Aptabase sets
// no cookie, keeps no device id and no address, and the app stores nothing
// for it, so there is nothing to ask first. Settings › Privacy › Share
// Anonymous Usage turns it off; from then on nothing is set up or sent
// (`track` returns first).
//
// The events are a closed list (`Name`) with coarse properties from fixed
// lists: a screen's kind, a station's kind of seed, a bucket. Never a title,
// an artist, an album, a search, a server's address or name, a user, an id.
// Aptabase adds the app version and build, the system and its version, the
// language and the device model. docs/STATS.md has every event and the
// question it answers.

import AVFoundation
import Aptabase
import Foundation
import JukeboxKit
import SwiftUI

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
    }

    /// On unless turned off. Read with `bool(forKey:)` once the key is
    /// there, so a launch argument ("-shareUsage NO") turns it off too.
    static var on: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    // Made once, on the first event while counting is on: never while it
    // is off, so then not even the client exists.
    private static let start: Void = Aptabase.shared.initialize(
        appKey: "A-SH-1430104593",
        with: InitOptions(host: "https://stats.numa.photo")
    )

    static func track(_ name: Name, _ props: [String: Value] = [:]) {
        guard on else { return }
        _ = start
        Aptabase.shared.trackEvent(name.rawValue, with: props)
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

    /// Why signing in did not work, from Jellyfin's errors; never the
    /// message, which can hold the address.
    static func signInFailure(_ error: Error, quickConnect: Bool = false) -> String {
        switch error as? JellyfinError {
        case .transport?:
            return "unreachable"
        case .invalidServerAddress?:
            return "not_jellyfin"
        case .unauthorized?:
            // For Quick Connect the server says so when Quick Connect is
            // turned off there, not of a password.
            return quickConnect ? "other" : "wrong_password"
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
