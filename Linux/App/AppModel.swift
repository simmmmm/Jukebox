// Linux's root object: the session and the stores every screen reads. The
// iPhone's AppModel (Jukebox/App/AppModel.swift) without SwiftUI's
// navigation paths, and with the same stores, which are the same files
// (Package.swift's `shared`), the songs kept on the machine among them, and
// the same accounts (Accounts.swift): MainWindow goes Home when the account
// changes.

import Foundation
import JukeboxKit
import Observation

/// The one there is, for every screen.
let app = AppModel()

@Observable
final class AppModel {
    enum Phase: Equatable {
        /// Reading the keyring; a blank window for a moment.
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    /// Nil for a moment while another account is switched to.
    private(set) var credentials: ServerCredentials?
    private(set) var server: (any MusicServer)?
    /// Asking the server of the account being switched to.
    private(set) var isSwitching = false

    /// Every account kept on this computer, the one signed in among them.
    let accounts = Accounts()
    let identity: ClientIdentity
    let settings: AppSettings
    let library: LibraryStore
    let history: HistoryStore
    let player: AudioPlayer
    let radio: RadioController
    let mixes: MixStore
    let handoff: HandoffStore
    let offline: OfflineStore
    /// The window's right panel: open or not, Up next or the lyrics.
    let panel = PanelState()

    init() {
        identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.1",
                                  deviceName: ProcessInfo.processInfo.hostName, deviceID: Self.deviceID())
        settings = AppSettings()
        library = LibraryStore()
        history = HistoryStore()
        offline = OfflineStore(settings: settings, library: library, history: history)
        player = AudioPlayer(settings: settings, history: history)
        radio = RadioController(player: player, library: library, history: history, settings: settings)
        mixes = MixStore()
        handoff = HandoffStore(player: player, radio: radio, library: library, settings: settings, identity: identity)
        player.radio = radio
        // What moves play counts and "Played lately" when a song is heard
        // to the end.
        player.library = library
        // Songs on the machine play from their files; offline only they play,
        // and the radio chooses among them.
        player.offline = offline
        radio.offline = offline
        offline.onConnectivityChange = { [weak self] in self?.connectivityChanged() }
        offline.onSongsChange = { [weak self] in self?.radio.offlineSongsChanged() }
    }

    func can(_ capability: ServerCapability) -> Bool {
        credentials?.capabilities.contains(capability) ?? false
    }

    func detectServer(at typed: String) async throws -> DetectedServer {
        try await MusicServers.detect(typed, identity: identity)
    }

    func signIn(to server: DetectedServer) -> any ServerSignIn {
        MusicServers.signIn(to: server, identity: identity)
    }

    /// Signed in last time: open as it was, the library from disk at once.
    /// An install from before the list of accounts has its one session as
    /// the list's only entry (Accounts.restore).
    func restore() async {
        guard phase == .launching else { return }
        let saved = accounts.restore()
        Stats.track(.appOpen, ["server": Stats.server(saved?.kind)])
        if let saved {
            await begin(saved)
        } else {
            phase = .signedOut
        }
    }

    /// The first account, one more (Preferences' Add Account), or one
    /// already here signed in again; over an account signed in, that one is
    /// put away first, as a switch does.
    func signIn(_ credentials: ServerCredentials) async {
        if self.credentials != nil { putAway() }
        if accounts.activate(credentials) {
            Stats.track(.accountAdded, ["server": Stats.server(credentials.kind),
                                        "count": Stats.accountCount(accounts.saved.count)])
        }
        // As the list keeps it: perhaps with a folder name of its own.
        await begin(accounts.active ?? credentials)
    }

    /// Another saved account (the iPhone's AppModel.switchAccount has the
    /// reasons): nil when switched, else the words why not.
    func switchAccount(to account: ServerCredentials) async -> String? {
        guard let current = credentials, !current.isSameAccount(as: account), !isSwitching else { return nil }
        isSwitching = true
        defer { isSwitching = false }
        let name = ServerWords.name(of: account)
        switch await AccountStores.reach(MusicServers.open(account, identity: identity)) {
        case .answers:
            break
        case .refuses:
            return "\(name) no longer accepts this sign-in. Sign out of it, then add it again."
        case .silent:
            guard offline.hasSongs(of: account) else {
                return "\(name) isn’t answering, so Jukebox stays on \(ServerWords.name(of: current))."
            }
        }
        // Signed out, or switched, while the server was asked.
        guard credentials == current else { return nil }
        Stats.track(.accountSwitched)
        putAway()
        accounts.activate(account)
        await begin(account)
        return nil
    }

    /// Signs out of an account, the one signed in when none is named (the
    /// iPhone's AppModel.signOut has what goes and what stays).
    func signOut(_ account: ServerCredentials? = nil) async {
        guard let current = credentials else { return }
        let leaving = account ?? current
        Stats.track(.signedOut)
        guard leaving.isSameAccount(as: current) else {
            _ = accounts.remove(leaving)
            let unsent = offline.forget(leaving)
            AccountFiles.forget(leaving)
            let server = MusicServers.open(leaving, identity: identity)
            if !unsent.isEmpty { await OfflineReports.send(unsent, with: server) }
            await server.signOut()
            return
        }
        let server = self.server
        // What was heard offline goes to the server on the way out; then the
        // account's downloads go (OfflineStore.signOut), as on the iPhone.
        let unsent = AccountStores(app: self).close(forgetting: true)
        credentials = nil
        self.server = nil
        if let next = accounts.remove(current) {
            await begin(next)
        } else {
            phase = .signedOut
        }
        if let server, !unsent.isEmpty { await OfflineReports.send(unsent, with: server) }
        await server?.signOut()
    }

    private func begin(_ credentials: ServerCredentials) async {
        let server = MusicServers.open(credentials, identity: identity)
        self.credentials = credentials
        self.server = server
        phase = .signedIn
        await AccountStores(app: self).open(server)
        refreshServer(server)
    }

    /// The account signed in, put away for another: everything of it stays.
    private func putAway() {
        AccountStores(app: self).close(forgetting: false)
        credentials = nil
        server = nil
    }

    /// What the server can do now, asked once a launch (the iPhone's
    /// AppModel.refreshServer has the reasons).
    private func refreshServer(_ server: any MusicServer) {
        Task {
            guard let fresh = try? await server.currentCapabilities() else { return }
            var updated = server.credentials
            updated.capabilities = fresh
            guard updated != server.credentials, self.credentials == server.credentials else { return }
            accounts.update(updated)
            let opened = MusicServers.open(updated, identity: identity)
            credentials = opened.credentials
            self.server = opened
            AccountStores(app: self).use(opened)
        }
    }

    /// The network went, or came back (OfflineStore): the player and the
    /// radio play what can play now, and back online the library is read
    /// again (the iPhone's AppModel.connectivityChanged).
    private func connectivityChanged() {
        player.connectivityChanged()
        radio.connectivityChanged()
        if !offline.isOffline, case .failed = library.state {
            Task { await library.refresh() }
        }
    }

    /// One id per installation: Jellyfin lists the device by it.
    private static func deviceID() -> String {
        let key = "deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}

extension AccountStores {
    init(app: AppModel) {
        self.init(player: app.player, library: app.library, history: app.history, radio: app.radio,
                  mixes: app.mixes, offline: app.offline, handoff: app.handoff, settings: app.settings)
    }
}
