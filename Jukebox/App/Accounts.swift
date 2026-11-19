// More than one account: a home server and a shared one, or two people on
// one server, kept side by side with one signed in, switched between
// without signing in again. Asked for with the other players' features
// Jukebox lacked: "maak ze allemaal maar" (the photographer, 17 November
// 2026). Both platforms' AppModels use this file as it is (Package.swift's
// `shared`), so the order below is the same on the iPhone, the Mac and
// Linux, and Linux's AccountCheck checks it after every build.
//
// What is the account's own, kept apart by its server's id and its user's
// (the name `OfflinePaths.account` makes of them):
// - its session, in the keychain's list (Keychain.swift, Linux's Platform);
// - its library cache (LibraryStore.cacheURL), as before;
// - its songs on the device, a folder each (OfflineDisk), as before;
// - its listening history, which is the radio's learning and what Home's
//   mixes are made from (HistoryStore);
// - its recent stations and the Last.fm answers about its library, which
//   name its songs by their ids (RadioController).
// Home's mixes are made again from those, so they are the account's too.
// What is the device's, the same for every account: AppSettings (the
// qualities, the pages, the appearance, the downloads' limit) and the
// Last.fm API key, which is a key to Last.fm's catalogue, not anyone's
// Last.fm account (the servers scrobble, ARCHITECTURE.md › Scrobbling).

import Foundation
import JukeboxKit
import Observation

/// The accounts kept on this device and which is signed in: the list's
/// one owner. The AppModel asks it, and keeps the stores in step.
@Observable
final class Accounts {
    /// Every account, in the order they were added.
    private(set) var saved: [ServerCredentials] = []
    @ObservationIgnored private var list = SavedAccounts(active: nil, saved: [])
    /// False when the keychain's list could not be read at launch: only a
    /// listener's own change (an account added, signed out of) writes it.
    @ObservationIgnored private var listKnown = true

    init() {}

    /// The one signed in as the list keeps it: a new account with its own
    /// folder name, when another had the one it would have had.
    var active: ServerCredentials? { list.active }

    /// At a launch: the keychain's session and list, put together. An
    /// install from before the list has one session: it is the list now,
    /// and the device's history and stations from then are its own
    /// (`AccountFiles.adoptLegacy`). Written back once, so the next launch
    /// reads what this one made and moves nothing again. Nil when signed
    /// out, or when the keychain could not be read (then nothing is written).
    /// A list that could not be read (a keyring that did not answer, the
    /// session read from its file) is not written over: this launch has
    /// the session alone.
    func restore() -> ServerCredentials? {
        guard let kept = Keychain.loadAccounts() else { return nil }
        list = SavedAccounts(active: kept.active, saved: kept.saved)
        listKnown = kept.listKnown
        // The rename moves only what is not there yet, so even with the
        // list unknown it takes nothing from another account.
        if SavedAccounts.isMigrating(active: kept.active, saved: kept.saved), let active = list.active {
            AccountFiles.adoptLegacy(for: active)
        }
        if list.needsSaving, kept.listKnown { Keychain.saveAccounts(list.all) }
        // A launch after one that ended between the two writes.
        if kept.active == nil, let first = list.active { Keychain.save(first) }
        saved = list.all
        return list.active
    }

    /// Signed in, or switched to; true when it is a new account here.
    /// The list is written before the session: were the app ended between
    /// the two, the next launch joins the session to the list again.
    @discardableResult
    func activate(_ account: ServerCredentials) -> Bool {
        let added = list.activate(account)
        Keychain.saveAccounts(list.all)
        Keychain.save(list.active ?? account)
        saved = list.all
        return added
    }

    /// The same account with what its server said of itself since.
    func update(_ account: ServerCredentials) {
        list.update(account)
        if listKnown { Keychain.saveAccounts(list.all) }
        if let active = list.active, active.isSameAccount(as: account) { Keychain.save(active) }
        saved = list.all
    }

    /// Signed out of; the account signed in after it (the first left, when
    /// it was the one signed in), or nil when none is left.
    func remove(_ account: ServerCredentials) -> ServerCredentials? {
        list.remove(account)
        Keychain.saveAccounts(list.all)
        if let active = list.active { Keychain.save(active) } else { Keychain.deleteCredentials() }
        saved = list.all
        return list.active
    }
}

/// Where an account's own files are, beside its library cache and its
/// songs' folder.
enum AccountFiles {
    /// Application Support/Jukebox/history-<account>.json.
    static func history(_ account: ServerCredentials) -> URL {
        support.appendingPathComponent("history-\(name(account)).json", isDirectory: false)
    }

    /// UserDefaults' recentStations.<account>.
    static func recentStationsKey(_ account: ServerCredentials) -> String {
        "recentStations.\(name(account))"
    }

    /// Caches/Jukebox/similarity-<account>/.
    static func similarity(_ account: ServerCredentials) -> URL {
        caches.appendingPathComponent("similarity-\(name(account))", isDirectory: true)
    }

    /// The migration: the one account of an install from before the list
    /// takes what the device kept for it then, by a rename. Only what is
    /// not there yet moves, so a second run moves nothing.
    static func adoptLegacy(for account: ServerCredentials) {
        move(support.appendingPathComponent("history.json", isDirectory: false), to: history(account))
        move(caches.appendingPathComponent("similarity", isDirectory: true), to: similarity(account))
        let defaults = UserDefaults.standard
        let key = recentStationsKey(account)
        if let stations = defaults.data(forKey: "recentStations"), defaults.data(forKey: key) == nil {
            defaults.set(stations, forKey: key)
        }
        defaults.removeObject(forKey: "recentStations")
    }

    /// Signed out of an account that is not the one signed in: what this
    /// device kept of it goes, as a sign-out of the one signed in forgets
    /// it (its songs go through OfflineStore.forget). Its history stays,
    /// as it does at every sign-out: signing in again finds the radio's
    /// learning.
    static func forget(_ account: ServerCredentials) {
        try? FileManager.default.removeItem(at: LibraryStore.cacheURL(for: account))
        try? FileManager.default.removeItem(at: similarity(account))
        UserDefaults.standard.removeObject(forKey: recentStationsKey(account))
    }

    private static func name(_ account: ServerCredentials) -> String {
        OfflinePaths.account(for: account)
    }

    private static var support: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("Jukebox", isDirectory: true)
    }

    private static var caches: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("Jukebox", isDirectory: true)
    }

    private static func move(_ from: URL, to: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: from.path), !files.fileExists(atPath: to.path) else { return }
        try? files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? files.moveItem(at: from, to: to)
    }
}

/// The stores an account fills, filled and put away in the one order that
/// loses nothing: the player stops while the old server, history and
/// library still hear its last song; each store writes what it holds to
/// the account's own files before the next account's are read.
struct AccountStores {
    let player: PlayQueue
    let library: LibraryStore
    let history: HistoryStore
    let radio: RadioController
    let mixes: MixStore
    let offline: OfflineStore
    let handoff: HandoffStore
    let settings: AppSettings
    /// This device as a speaker other clients control (RemoteControl.swift).
    let remote: RemoteControl

    /// Signed in, or switched to.
    func open(_ server: any MusicServer) async {
        let account = server.credentials
        history.open(AccountFiles.history(account))
        radio.open(account)
        player.server = server
        radio.server = server
        // The songs on the device first: they play before the library from
        // the server has come, or without it.
        await offline.open(server: server)
        await library.open(server: server)
        // What another device plays, or this one played last: once the
        // library is in, since what is offered is a song in it.
        handoff.server = server
        handoff.start()
        remote.server = server
        // The radio first: its graph is made in the background and needs
        // nothing from the mixes, so it does not wait for them to be made.
        radio.prepare()
        await mixes.rebuild(library: library, history: history, settings: settings)
    }

    /// The same account, with what its server said of itself since.
    func use(_ server: any MusicServer) {
        player.server = server
        radio.server = server
        library.use(server)
        offline.use(server)
        handoff.server = server
        // Asked since sign-in: remote control may have come (or gone).
        remote.server = server
    }

    /// The account signed in, put away. `forgetting` at a sign-out: its
    /// library cache, songs and recent stations go too (its history stays),
    /// and its plays heard offline and not yet told come back, the stop of
    /// its last song among them, to be sent on the way out.
    @discardableResult
    func close(forgetting: Bool) -> [PendingPlay] {
        // Nothing more is saved as this account's "left off": with no
        // server the handoff saves nothing, and the stop below is no news.
        handoff.server = nil
        handoff.reset()
        // No longer listed as this account's speaker.
        remote.server = nil
        // Its last song is told to its own server and history.
        player.stop()
        player.server = nil
        if forgetting { radio.reset() } else { radio.close() }
        radio.server = nil
        history.close()
        let unsent = forgetting ? offline.takeReports() : []
        if forgetting { offline.signOut() } else { offline.close() }
        if forgetting { library.reset() } else { library.close() }
        mixes.reset()
        return unsent
    }

    /// Whether an account's server answers it, asked before switching to
    /// it: with its own session (downloads' permission is the user's, so a
    /// token the server no longer takes shows), and for 10 seconds at most.
    nonisolated enum Reach: Sendable {
        case answers
        /// There, but not taking this session any more.
        case refuses
        case silent
    }

    static func reach(_ server: any MusicServer) async -> Reach {
        await withTaskGroup(of: Reach.self) { group in
            group.addTask {
                do {
                    _ = try await server.downloadsAllowed()
                    return .answers
                } catch MusicServerError.unauthorized {
                    return .refuses
                } catch MusicServerError.notAllowed {
                    return .answers
                } catch {
                    return .silent
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return .silent
            }
            let first = await group.next() ?? .silent
            group.cancelAll()
            return first
        }
    }
}
