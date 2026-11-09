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
import UIKit

@Observable
final class AppModel {
    enum Phase: Equatable {
        /// Reading the keychain; a blank screen for a moment.
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    /// The session as the keychain keeps it: the server's kind, name and
    /// version, the user, what the server can do.
    private(set) var credentials: ServerCredentials?
    private(set) var server: (any MusicServer)?

    let identity: ClientIdentity
    let settings: AppSettings
    let navigator: Navigator
    let library: LibraryStore
    let history: HistoryStore
    let player: AudioPlayer
    let radio: RadioController
    let mixes: MixStore
    let offline: OfflineStore

    init() {
        identity = ClientIdentity(
            clientName: "Jukebox",
            clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            deviceName: UIDevice.current.name,
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
    /// session (ServerCredentials decodes its Credentials), so the update
    /// signs nobody out.
    func restore() async {
        guard phase == .launching else { return }
        let saved = Keychain.loadCredentials()
        // Once a launch (Stats): how many starts, on which system, and on
        // which kind of server — jellyfin, navidrome or subsonic, no more.
        Stats.track(.appOpen, ["server": Stats.server(saved?.kind)])
        if let saved {
            await begin(saved)
        } else {
            phase = .signedOut
        }
    }

    /// After the sign-in screen has credentials.
    func signIn(_ credentials: ServerCredentials) async {
        Keychain.save(credentials)
        await begin(credentials)
    }

    func signOut() async {
        Stats.track(.signedOut)
        player.stop()
        // Also forgets this account's thumbs and recent stations.
        radio.reset()
        let server = self.server
        // What was heard offline and not yet told to the server goes on the
        // way out, when the server answers. Then the account's downloads go
        // (OfflineStore.signOut): the next account never plays its songs.
        let unsent = offline.takeReports()
        offline.signOut()
        Keychain.deleteCredentials()
        credentials = nil
        self.server = nil
        // Nothing streams, reports or asks the old server from here on.
        player.server = nil
        radio.server = nil
        library.reset()
        mixes.reset()
        phase = .signedOut
        // After the tabs have gone, so nothing pops on screen: the next
        // sign-in, perhaps to another server, starts on Home rather than on
        // the last account's album pages.
        navigator.isNowPlayingPresented = false
        navigator.addToPlaylist = nil
        navigator.tab = .home
        navigator.homePath = NavigationPath()
        navigator.radioPath = NavigationPath()
        navigator.libraryPath = NavigationPath()
        navigator.searchPath = NavigationPath()
        if let server, !unsent.isEmpty { await OfflineReports.send(unsent, with: server) }
        // Jellyfin forgets the token; a Subsonic server has no sign-out, and
        // its token, forgotten here, holds until the password changes.
        await server?.signOut()
    }

    private func begin(_ credentials: ServerCredentials) async {
        let server = MusicServers.open(credentials, identity: identity)
        self.credentials = credentials
        self.server = server
        player.server = server
        radio.server = server
        phase = .signedIn
        // The songs on the phone first: they play before the library from
        // the server has come, or without it.
        await offline.open(server: server)
        await library.open(server: server)
        // The radio first: its graph is made in the background and needs
        // nothing from the mixes, so it does not wait for them to be made.
        radio.prepare()
        refreshServer(server)
        await mixes.rebuild(library: library, history: history, settings: settings)
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
            Keychain.save(updated)
            use(MusicServers.open(updated, identity: identity))
        }
    }

    /// The same session with what the server said of itself just now.
    private func use(_ server: any MusicServer) {
        credentials = server.credentials
        self.server = server
        player.server = server
        radio.server = server
        library.use(server)
        offline.use(server)
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
