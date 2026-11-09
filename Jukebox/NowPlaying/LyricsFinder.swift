// Where Now Playing's lyrics come from: the listener's own server first
// (Jellyfin reads them from the files and from .lrc files beside them;
// Navidrome too, and an older Subsonic server by artist and title), and
// when it has none and Settings' "Find Lyrics Online" is on, LRCLIB — a free,
// open lyrics database, mostly synced, that Feishin asks too. Most libraries
// have no lyrics of their own, so without it Now Playing said "No Lyrics"
// nearly always; the photographer, 8 November 2026: "Kun je ook lyrics
// toevoegen".
//
// The server is asked once a launch for each song; LRCLIB's answers are also
// kept on disk (the kit's LyricsCache: found for 90 days, not found for 3),
// so a song is not looked up again each time it comes round on a station.
// Nothing is asked while the lyrics are closed: LyricsView asks for the song
// playing and, while it is open, the one after it. A server without lyrics
// of any kind (ServerCapability.lyrics: a Jellyfin before 10.9) is not asked:
// LRCLIB answers at once.

import Foundation
import JukeboxKit

/// What Now Playing shows for a song.
enum LyricsAnswer: Equatable {
    /// `fromLRCLIB`: the server had none and LRCLIB had them, so the view
    /// says where they are from.
    case lyrics(Lyrics, fromLRCLIB: Bool)
    /// LRCLIB lists the song as having no words.
    case instrumental
    /// Neither the server nor, when it may be asked, LRCLIB has lyrics.
    case notFound
    /// Nothing answered (`server`: the listener's server did not; else
    /// LRCLIB did not). Not remembered: asked again next time.
    case failed(server: Bool)
}

final class LyricsFinder {
    static let shared = LyricsFinder()

    private let lrclib: LRCLIBClient
    private let cache: LyricsCache

    /// The server's lyrics, by track, this launch.
    private var fromServer: [ItemID: Lyrics] = [:]
    /// Tracks the server has no lyrics for.
    private var notOnServer: Set<ItemID> = []
    /// LRCLIB's answers, by track, this launch (and on disk for longer).
    private var fromLRCLIB: [ItemID: LyricsLookup] = [:]
    /// The next song's lookups under way, so when that song starts
    /// mid-lookup the view waits for it rather than asking twice.
    private var asking: [Asked: Task<LyricsAnswer, Never>] = [:]

    private struct Asked: Hashable {
        var trackID: ItemID
        var online: Bool
    }

    init() {
        // LRCLIB asks for the app's name, version and a link.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        lrclib = LRCLIBClient(userAgent: LRCLIBClient.userAgent(appVersion: version))
        // Caches, not Application Support: the system may clear it when the
        // phone runs short of space, and a song is then only asked again.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cache = LyricsCache(directory: caches.appendingPathComponent("Lyrics", isDirectory: true))
    }

    /// The answer already known this launch, without asking anyone: what
    /// the view shows at once, with no spinner in between.
    func known(_ track: Track, online: Bool) -> LyricsAnswer? {
        if let lyrics = fromServer[track.id] {
            return .lyrics(lyrics, fromLRCLIB: false)
        }
        guard notOnServer.contains(track.id) else { return nil }
        guard online else { return .notFound }
        guard let lookup = fromLRCLIB[track.id] else { return nil }
        return Self.answer(lookup)
    }

    /// The song's lyrics: the server's, else LRCLIB's when `online`.
    /// Asked in the caller's task, so when the view goes or the song
    /// changes, its requests are cancelled with it: skipping through ten
    /// songs with the lyrics open leaves no ten lookups running, and none
    /// is begun with LRCLIB for a song already gone.
    func lyrics(for track: Track, server: any MusicServer, online: Bool) async -> LyricsAnswer {
        if let known = known(track, online: online) { return known }
        // The next song's lookup, begun while the one before it played:
        // waited for, not asked again.
        if let running = asking[Asked(trackID: track.id, online: online)] { return await running.value }
        return await find(track, server: server, online: online)
    }

    /// Looks up `track` in the background if nothing is known of it yet:
    /// the next song's, while the lyrics are open, so they are there when
    /// it starts. A task of its own, so it ends and is remembered even when
    /// the song playing ends first; one song's, as LyricsView asks only
    /// once it has the song playing's answer.
    func prefetch(_ track: Track?, server: any MusicServer, online: Bool) {
        guard let track, known(track, online: online) == nil else { return }
        let asked = Asked(trackID: track.id, online: online)
        guard asking[asked] == nil else { return }
        asking[asked] = Task {
            let answer = await self.find(track, server: server, online: online)
            self.asking[asked] = nil
            return answer
        }
    }

    private func find(_ track: Track, server: any MusicServer, online: Bool) async -> LyricsAnswer {
        if !server.capabilities.contains(.lyrics), fromServer[track.id] == nil {
            if notOnServer.count >= 2_000 { notOnServer.removeAll() }
            notOnServer.insert(track.id)
        }
        if fromServer[track.id] == nil, !notOnServer.contains(track.id) {
            do {
                // The track, not its id: a Subsonic server's classic
                // getLyrics asks by artist and title.
                if let lyrics = try await server.lyrics(for: track), !lyrics.lines.isEmpty {
                    remember(lyrics, for: track.id)
                    return .lyrics(lyrics, fromLRCLIB: false)
                }
                if notOnServer.count >= 2_000 { notOnServer.removeAll() }
                notOnServer.insert(track.id)
            } catch MusicServerError.unsupported {
                // It has no such call after all (a Subsonic server's 404):
                // as having none.
                notOnServer.insert(track.id)
            } catch MusicServerError.notFound {
                // The server does not know the song (Subsonic's 70): none.
                notOnServer.insert(track.id)
            } catch {
                // The server did not answer: perhaps it has lyrics, so
                // LRCLIB's are not shown in their place.
                return .failed(server: true)
            }
        }
        if let known = known(track, online: online) { return known }
        // A song with no artist or title cannot be looked up.
        guard let query = LyricsQuery(track: track) else { return .notFound }
        do {
            let lookup: LyricsLookup
            if let kept = await cache.lookup(query) {
                lookup = kept
            } else {
                // Not asked for a song whose view has gone while the cache
                // was read (as failed: not remembered).
                guard !Task.isCancelled else { return .failed(server: false) }
                lookup = try await lrclib.lyrics(query)
                await cache.store(lookup, for: query)
            }
            remember(lookup, for: track.id)
            return Self.answer(lookup)
        } catch {
            return .failed(server: false)
        }
    }

    private func remember(_ lyrics: Lyrics, for trackID: ItemID) {
        // A few hundred songs' lyrics are a few hundred kilobytes; past
        // that, start again rather than keep a whole evening's.
        if fromServer.count >= 200 { fromServer.removeAll() }
        fromServer[trackID] = lyrics
    }

    private func remember(_ lookup: LyricsLookup, for trackID: ItemID) {
        if fromLRCLIB.count >= 200 { fromLRCLIB.removeAll() }
        fromLRCLIB[trackID] = lookup
    }

    private static func answer(_ lookup: LyricsLookup) -> LyricsAnswer {
        switch lookup {
        case let .found(lyrics, _): .lyrics(lyrics, fromLRCLIB: true)
        case .instrumental: .instrumental
        case .notFound: .notFound
        }
    }
}
