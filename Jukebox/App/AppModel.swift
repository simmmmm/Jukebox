// The app's one root object: the session (signed out, or signed in to a
// server as a user), and the stores every screen reads — the library, the
// player, the radio, the mixes, the history, the songs on the phone and the
// settings. Made once in JukeboxApp and handed down through the environment,
// each store on its own (`@Environment(LibraryStore.self)` and so on), so a
// view reads only what it draws.
//
// The session is a MusicServer (JukeboxKit's Server/MusicServer.swift):
// Jellyfin, or Navidrome and the other Subsonic servers, one protocol for
// all, so nothing below this file asks which. The photographer, 8 November
// 2026: "Moet eigenlijk ook voor navidrome en die ander"; and 9 November,
// before the release: "Kun je die navidunges en subsonic toevoegen". What a
// server lacks is hidden, not offered and failed (`can`, ServerCapability).

import Foundation
import JukeboxKit
import Observation
// NavigationPath, for clearing the Navigator's stacks at sign-out.
import SwiftUI

@Observable
final class AppModel {
    /// The one model, for the phone's window and the car's screen
    /// (CarPlay/CarPlayScene.swift) alike: CarPlay can launch the app
    /// without its window, and both play the same queue.
    static let shared = AppModel()

    enum Phase: Equatable {
        /// Reading the keychain; a blank screen for a moment.
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    /// The session as the keychain keeps it: the server's kind, name and
    /// version, the user, what the server can do. Nil for a moment while
    /// another account is switched to.
    private(set) var credentials: ServerCredentials?
    private(set) var server: (any MusicServer)?
    /// Asking the server of the account being switched to (`switchAccount`).
    private(set) var isSwitching = false
    /// Why the last switch did not happen, for the alert RootView shows
    /// (a switch from a menu has no place of its own to say it).
    var switchProblem: String?

    /// Another account from a menu or a row: switched, or why not.
    func choose(_ account: ServerCredentials) {
        Task { switchProblem = await switchAccount(to: account) }
    }

    /// Every account kept on this device (Accounts.swift), the one signed
    /// in among them.
    let accounts = Accounts()
    let identity: ClientIdentity
    let settings: AppSettings
    let navigator: Navigator
    let library: LibraryStore
    let history: HistoryStore
    let player: AudioPlayer
    let radio: RadioController
    let mixes: MixStore
    let offline: OfflineStore
    /// What plays here, kept for the listener's other devices, and what
    /// plays there, offered here (HandoffStore).
    let handoff: HandoffStore

    init() {
        identity = ClientIdentity(
            clientName: "Jukebox",
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            deviceName: Device.name,
            deviceID: Self.deviceID()
        )
        settings = AppSettings()
        navigator = Navigator()
        library = LibraryStore()
        history = HistoryStore()
        player = AudioPlayer(settings: settings, history: history)
        radio = RadioController(player: player, library: library, history: history, settings: settings)
        mixes = MixStore()
        offline = OfflineStore(settings: settings, library: library, history: history)
        handoff = HandoffStore(player: player, radio: radio, library: library, settings: settings, identity: identity)
        player.radio = radio
        // What moves play counts and "Recently Played" when a song is heard
        // to the end (AudioPlayer calls library.notePlayed).
        player.library = library
        // Songs on the phone play from their files; offline only they play,
        // and the radio chooses from them alone.
        player.offline = offline
        radio.offline = offline
        offline.onConnectivityChange = { [weak self] in self?.connectivityChanged() }
        offline.onSongsChange = { [weak self] in self?.radio.offlineSongsChanged() }
        // Chromecasts (PlayOn.swift): Google's Cast SDK on the iPhone and
        // the iPad, castv2 over Network's TLS on the Mac, which has no SDK.
        #if os(macOS)
        player.playOn.castFinder = BonjourCastFinder()
        player.playOn.castPlayer = { device in
            CastPlayer(device: device, socket: NetworkCastSocket(service: device.address))
        }
        #elseif canImport(GoogleCast)
        player.playOn.castFinder = GoogleCastFinder()
        player.playOn.castPlayer = { device in GoogleCastPlayer(device: device) }
        #endif
    }

    /// Whether the signed-in server can do this (Quick Connect and API keys
    /// are the sign-in screen's own questions, never here).
    func can(_ capability: ServerCapability) -> Bool {
        credentials?.capabilities.contains(capability) ?? false
    }

    /// "Jellyfin", "Navidrome": what the screens call the server ("your
    /// Navidrome server"), ServerWords.swift.
    var serverKindName: String {
        credentials?.kind.displayName ?? String(localized: "music")
    }

    /// What is at the address typed on the sign-in screen, before anyone
    /// has signed in: Jellyfin or a Subsonic server, its name and what it
    /// offers. The kit asks every address it makes of it both ways at once.
    func detectServer(at typed: String) async throws -> DetectedServer {
        try await MusicServers.detect(typed, identity: identity)
    }

    /// Signing in to the server that answered: user name and password, and
    /// Quick Connect or an API key where it offers them (`as? any
    /// QuickConnectSignIn`, `as? any APIKeySignIn`).
    func signIn(to server: DetectedServer) -> any ServerSignIn {
        MusicServers.signIn(to: server, identity: identity)
    }

    /// Signed in last time: open as it was, the library from disk at once.
    /// The keychain's entry of the Jellyfin-only app reads as a Jellyfin
    /// session (ServerCredentials decodes its Credentials), and an install
    /// from before the list of accounts has its one session as the list's
    /// only entry (Accounts.restore), so the update signs nobody out.
    func restore() async {
        guard phase == .launching else { return }
        let saved = accounts.restore()
        // Once a launch (Stats): how many starts, on which system, and on
        // which kind of server — jellyfin, navidrome or subsonic, no more.
        Stats.track(.appOpen, ["server": Stats.server(saved?.kind)])
        if let saved {
            await begin(saved)
        } else {
            phase = .signedOut
        }
    }

    /// After the sign-in screen has credentials: the first account, one
    /// more (Settings' Add Account), or one already here signed in again.
    /// Over an account signed in, that one is put away first, as a switch
    /// does.
    func signIn(_ credentials: ServerCredentials) async {
        if self.credentials != nil { putAway() }
        if accounts.activate(credentials) {
            Stats.track(.accountAdded, ["server": Stats.server(credentials.kind),
                                        "count": Stats.accountCount(accounts.saved.count)])
        }
        // As the list keeps it: perhaps with a folder name of its own.
        await begin(accounts.active ?? credentials)
    }

    /// Another saved account: the player stops (its queue is this server's
    /// songs), every store takes that account's, and the window goes Home.
    /// Its server is asked first: one that does not answer leaves this
    /// account signed in, and the words why come back; offline, an account
    /// with songs on the device is switched to all the same, to play them.
    func switchAccount(to account: ServerCredentials) async -> String? {
        guard let current = credentials, !current.isSameAccount(as: account), !isSwitching else { return nil }
        isSwitching = true
        defer { isSwitching = false }
        let name = ServerWords.name(of: account)
        switch await AccountStores.reach(MusicServers.open(account, identity: identity)) {
        case .answers:
            break
        case .refuses:
            return String(localized: "\(name) no longer accepts this sign-in. Sign out of it, then add it again.")
        case .silent:
            guard offline.hasSongs(of: account) else {
                return String(localized: "\(name) isn’t answering, so Jukebox stays on \(ServerWords.name(of: current)).")
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

    /// Signs out of an account (the one signed in when none is named). It
    /// goes from the list with what this device kept of it: its library,
    /// recent stations and downloaded songs (its history stays, for a
    /// sign-in again). The one signed in: the next saved account opens, or
    /// the sign-in screen when none is left. Another: the one signed in
    /// plays on.
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
        // What was heard offline and not yet told to the server goes on the
        // way out, when the server answers. Then the account's downloads go
        // (OfflineStore.signOut): the next account never plays its songs.
        let unsent = AccountStores(app: self).close(forgetting: true)
        credentials = nil
        self.server = nil
        if let next = accounts.remove(current) {
            resetNavigation()
            await begin(next)
        } else {
            phase = .signedOut
            // After the tabs have gone, so nothing pops on screen: the next
            // sign-in, perhaps to another server, starts on Home rather than
            // on the last account's album pages.
            resetNavigation()
        }
        if let server, !unsent.isEmpty { await OfflineReports.send(unsent, with: server) }
        // Jellyfin forgets the token; a Subsonic server has no sign-out, and
        // its token, forgotten here, holds until the password changes.
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

    /// The account signed in, put away for another: everything of it stays
    /// on the device.
    private func putAway() {
        AccountStores(app: self).close(forgetting: false)
        credentials = nil
        server = nil
        resetNavigation()
    }

    /// Home, with nothing over it: the next account's pages are not the
    /// last one's.
    private func resetNavigation() {
        navigator.isNowPlayingPresented = false
        navigator.isSettingsPresented = false
        navigator.isAddingAccount = false
        navigator.addToPlaylist = nil
        navigator.tab = .home
        navigator.place = .home
        navigator.searchQuery = ""
        navigator.homePath = NavigationPath()
        navigator.radioPath = NavigationPath()
        navigator.libraryPath = NavigationPath()
        navigator.searchPath = NavigationPath()
        navigator.widePath = NavigationPath()
    }

    /// What the server can do now, asked once a launch, in the background:
    /// it may have been upgraded since sign-in (a Jellyfin past 10.9 has
    /// lyrics, a Navidrome a new extension), and the sign-in the
    /// Jellyfin-only app kept has no version for Settings. A changed
    /// session is saved and every store goes on with it; an answer that
    /// does not come (offline) leaves it as it was.
    private func refreshServer(_ server: any MusicServer) {
        Task {
            guard let fresh = try? await server.currentCapabilities() else { return }
            var updated = server.credentials
            updated.capabilities = fresh
            if updated.serverVersion.isEmpty, let jellyfin = server as? JellyfinServer,
               let info = try? await jellyfin.client.publicInfo() {
                updated.serverVersion = info.version
            }
            // Signed out, or in again elsewhere, meanwhile: not this session's.
            guard updated != server.credentials, self.credentials == server.credentials else { return }
            accounts.update(updated)
            use(MusicServers.open(updated, identity: identity))
        }
    }

    /// The same session with what the server said of itself just now.
    private func use(_ server: any MusicServer) {
        credentials = server.credentials
        self.server = server
        AccountStores(app: self).use(server)
    }

    /// The network went, or came back (OfflineStore): the player and the
    /// radio play what can play now, and back online the library is read
    /// from the server again, so Home's notice goes by itself.
    private func connectivityChanged() {
        player.connectivityChanged()
        radio.connectivityChanged()
        if !offline.isOffline, case .failed = library.state {
            Task { await library.refresh() }
        }
    }

    /// One id per installation, kept in UserDefaults: Jellyfin lists the
    /// device by it, and a new one each launch would fill its device list.
    /// (Subsonic servers list a player by its name, `c`, alone.)
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
