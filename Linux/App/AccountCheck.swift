// A check of what keeps two accounts apart on one device (Jukebox/App/
// Accounts.swift), run without a server: dev/linux-errors.sh runs it after
// every build (JUKEBOX_CHECK=accounts), as the queue's. The migration of an
// install from before the list (its history and recent stations become its
// one account's, and a second run moves nothing), each account's history
// and stations read back after a switch, every saved account's songs kept
// when another opens, and a sign-out of one taking only its own files.
//
// It runs in a folder of its own: XDG_DATA_HOME and XDG_CACHE_HOME are set
// to a fresh one before anything asks where to write, and the check stops
// if Foundation would still write elsewhere. The keyring is never asked
// (Accounts.restore is the kit's SavedAccounts, tested in JukeboxKit).

import Foundation
import JukeboxKit

enum AccountCheck {
    static func run() -> Int32 {
        UserDefaults.standard.set(false, forKey: Stats.key)
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("jukebox-account-check-\(UUID().uuidString)", isDirectory: true)
        setenv("XDG_DATA_HOME", root.appendingPathComponent("data").path, 1)
        setenv("XDG_CACHE_HOME", root.appendingPathComponent("cache").path, 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileManager.default
        guard files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path.hasPrefix(root.path) == true,
              files.urls(for: .cachesDirectory, in: .userDomainMask).first?.path.hasPrefix(root.path) == true else {
            print("account check: Foundation does not follow XDG_DATA_HOME here; nothing was run")
            return 1
        }

        var failed: [String] = []
        var checks = 0
        func expect(_ ok: Bool, _ what: String) {
            checks += 1
            if !ok { failed.append(what) }
        }
        func account(_ server: String, _ user: String) -> ServerCredentials {
            ServerCredentials(kind: .jellyfin, serverURL: URL(string: "http://\(server).local:8096")!, serverID: server,
                              serverName: server, userID: user, userName: user, secret: .jellyfinToken("t"))
        }
        let home = account("home0123", "anna"), shared = account("shared45", "anna")
        let support = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jukebox", isDirectory: true)
        let caches = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jukebox", isDirectory: true)

        // The device as a build from before the list left it.
        let heard = PlayEvent(trackID: "song-1", date: Date(), listened: 200, duration: 200, outcome: .completed)
        var old = ListeningHistory()
        old.append(heard)
        try? old.save(to: support.appendingPathComponent("history.json"))
        try? files.createDirectory(at: caches.appendingPathComponent("similarity"), withIntermediateDirectories: true)
        let station = Station(seed: .personal, snapshot: .empty)
        UserDefaults.standard.set(try? JSONEncoder().encode([station]), forKey: "recentStations")

        AccountFiles.adoptLegacy(for: home)
        expect(ListeningHistory.load(from: AccountFiles.history(home)).events == [heard], "the history becomes the account's")
        expect(!files.fileExists(atPath: support.appendingPathComponent("history.json").path), "the old history is moved, not copied")
        expect(files.fileExists(atPath: AccountFiles.similarity(home).path), "Last.fm's answers become the account's")
        expect(UserDefaults.standard.data(forKey: "recentStations") == nil
               && UserDefaults.standard.data(forKey: AccountFiles.recentStationsKey(home)) != nil,
               "the recent stations become the account's")
        // Again, with a history the old build wrote since: it is not taken.
        try? ListeningHistory().save(to: support.appendingPathComponent("history.json"))
        AccountFiles.adoptLegacy(for: home)
        expect(ListeningHistory.load(from: AccountFiles.history(home)).events == [heard], "a second migration moves nothing")

        // Each account's history and stations, read back after a switch.
        let history = HistoryStore()
        history.open(AccountFiles.history(home))
        expect(history.history.events == [heard], "the history opens with its account")
        history.open(AccountFiles.history(shared))
        expect(history.history.events.isEmpty, "another account starts with its own, empty")
        history.record(PlayEvent(trackID: "song-2", date: Date(), listened: 10, duration: 200, outcome: .skipped))
        history.close()
        history.flush()
        history.open(AccountFiles.history(home))
        expect(history.history.events == [heard], "switched back, the first account's is as it was")
        history.open(AccountFiles.history(shared))
        expect(history.history.events.map(\.trackID) == ["song-2"], "a play written as its account was put away is kept")

        let settings = AppSettings()
        // An engine that plays nothing, and nothing is played.
        setenv("JUKEBOX_AUDIO_SINK", "fakesink", 1)
        let player = AudioPlayer(settings: settings, history: history)
        let radio = RadioController(player: player, library: LibraryStore(), history: history, settings: settings)
        radio.open(home)
        expect(radio.recentStations.map { $0.id } == [station.id], "the account's recent stations")
        radio.open(shared)
        expect(radio.recentStations.isEmpty, "another account has none of them")
        radio.reset()
        radio.open(home)
        expect(radio.recentStations.count == 1, "a sign-out of another leaves them")

        // Songs on the device: one folder an account, each kept while
        // another opens; a sign-out of one takes its folder alone.
        for (who, file) in [(home, "song-1.mp3"), (shared, "song-9.mp3")] {
            let name = OfflinePaths.account(for: who)
            try? files.createDirectory(at: OfflinePaths.files(name), withIntermediateDirectories: true)
            _ = files.createFile(atPath: OfflinePaths.files(name).appendingPathComponent(file).path, contents: Data([1]))
        }
        let play = PendingPlay(trackID: "song-9", playSessionID: "p", startPosition: 0, stopPosition: 10)
        try? JSONEncoder().encode([play]).write(to: OfflinePaths.reports(OfflinePaths.account(for: shared)))
        _ = OfflineDisk.load(OfflinePaths.account(for: home))
        expect(OfflineDisk.hasSongs(OfflinePaths.account(for: shared)), "opening one account keeps another's songs")
        let offline = OfflineStore(settings: settings, library: LibraryStore(), history: history)
        expect(offline.hasSongs(of: shared), "an account not open has its songs, for a switch offline")
        expect(offline.forget(shared) == [play], "signed out of, an account's plays heard offline are handed over")
        expect(!files.fileExists(atPath: OfflinePaths.folder(OfflinePaths.account(for: shared)).path), "and its songs go")
        // (Its stray file, wanted by nothing, went at its own load, as before.)
        expect(files.fileExists(atPath: OfflinePaths.folder(OfflinePaths.account(for: home)).path), "the other's folder stays")

        // The library cache stays at a switch, goes at a sign-out.
        try? files.createDirectory(at: caches, withIntermediateDirectories: true)
        _ = files.createFile(atPath: LibraryStore.cacheURL(for: shared).path, contents: Data([1]))
        AccountFiles.forget(shared)
        expect(!files.fileExists(atPath: LibraryStore.cacheURL(for: shared).path), "a sign-out of an account takes its library cache")
        expect(files.fileExists(atPath: AccountFiles.history(shared).path), "and leaves its history, for a sign-in again")

        // Copy Diagnostic Info (Support.swift) says the kind of server and
        // never whose: no address, name, user or token.
        let secretive = ServerCredentials(kind: .jellyfin, serverURL: URL(string: "https://music.hidden.example:8920")!,
                                          serverID: "id-hidden", serverName: "Hidden Music", serverVersion: "10.11.0",
                                          userID: "uid-hidden", userName: "hidden-user", secret: .jellyfinToken("hidden-token"))
        let info = Support.diagnostics(version: "1.3", client: "Linux", account: secretive, lastFM: true)
        expect(info.contains("Jellyfin 10.11.0") && info.contains("Last.fm: on"), "diagnostic info names the server's kind and Last.fm")
        expect(!info.lowercased().contains("hidden"), "diagnostic info holds no address, name, user or token")
        expect(!info.contains(ProcessInfo.processInfo.hostName), "nor the machine's name")
        expect(Support.contactURL("") == nil && Support.contactURL("a@b.example")?.scheme == "mailto", "no contact while empty; an address is a mailto")

        // Enhance Radio is on by default, yet asks nothing of Last.fm,
        // ListenBrainz or AcousticBrainz before it is answered.
        let fresh = UserDefaults(suiteName: "jukebox-account-check")!
        fresh.removePersistentDomain(forName: "jukebox-account-check")
        defer { fresh.removePersistentDomain(forName: "jukebox-account-check") }
        let unasked = AppSettings(defaults: fresh)
        expect(unasked.enhanceRadio && !unasked.radioChoiceMade && !unasked.enhancesRadio && !unasked.hasLastFM,
               "Enhance Radio waits for its answer")
        unasked.enhanceRadio = true
        expect(unasked.radioChoiceMade && unasked.enhancesRadio == !AppSettings.appLastFMKey.isEmpty,
               "and once answered, it is on")

        print("account check: \(checks - failed.count) of \(checks) passed")
        for what in failed { print("  failed: \(what)") }
        return failed.isEmpty ? 0 : 1
    }
}
