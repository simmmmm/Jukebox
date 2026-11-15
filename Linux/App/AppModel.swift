// Linux's root object: the session and the stores every screen reads. The
// iPhone's AppModel (Jukebox/App/AppModel.swift) without SwiftUI's
// navigation paths, and with the same stores, which are the same files
// (Package.swift's `shared`), the songs kept on the machine among them.

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
    private(set) var credentials: ServerCredentials?
    private(set) var server: (any MusicServer)?

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
        identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.0",
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
    func restore() async {
        guard phase == .launching else { return }
        let saved = Keychain.loadCredentials()
        Stats.track(.appOpen, ["server": Stats.server(saved?.kind)])
        if let saved {
            await begin(saved)
        } else {
            phase = .signedOut
        }
    }

    func signIn(_ credentials: ServerCredentials) async {
        Keychain.save(credentials)
        await begin(credentials)
    }

    func signOut() async {
        Stats.track(.signedOut)
        player.stop()
        radio.reset()
        let server = self.server
        // What was heard offline goes to the server on the way out; then the
        // account's downloads go (OfflineStore.signOut), as on the iPhone.
        let unsent = offline.takeReports()
        offline.signOut()
        Keychain.deleteCredentials()
        credentials = nil
        self.server = nil
        player.server = nil
        radio.server = nil
        handoff.server = nil
        handoff.reset()
        library.reset()
        mixes.reset()
        phase = .signedOut
        if let server, !unsent.isEmpty { await OfflineReports.send(unsent, with: server) }
        await server?.signOut()
    }

    private func begin(_ credentials: ServerCredentials) async {
        let server = MusicServers.open(credentials, identity: identity)
        self.credentials = credentials
        self.server = server
        player.server = server
        radio.server = server
        phase = .signedIn
        // The songs on the machine first: they play before the library from
        // the server has come, or without it.
        await offline.open(server: server)
        await library.open(server: server)
        // What another device plays, or this one played last: once the
        // library is in, since an offer is of a song in it.
        handoff.server = server
        handoff.start()
        // The radio first: its graph needs nothing from the mixes.
        radio.prepare()
        refreshServer(server)
        await mixes.rebuild(library: library, history: history, settings: settings)
    }

    /// What the server can do now, asked once a launch (the iPhone's
    /// AppModel.refreshServer has the reasons).
    private func refreshServer(_ server: any MusicServer) {
        Task {
            guard let fresh = try? await server.currentCapabilities() else { return }
            var updated = server.credentials
            updated.capabilities = fresh
            guard updated != server.credentials, self.credentials == server.credentials else { return }
            Keychain.save(updated)
            let opened = MusicServers.open(updated, identity: identity)
            credentials = opened.credentials
            self.server = opened
            player.server = opened
            radio.server = opened
            library.use(opened)
            offline.use(opened)
            handoff.server = opened
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
