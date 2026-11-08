// The app's one root object: the session (signed out, or signed in to a
// server as a user), and the stores every screen reads — the library, the
// player, the radio, the mixes, the history, the songs on the phone and the
// settings. Made once in JukeboxApp and handed down through the environment,
// each store on its own (`@Environment(LibraryStore.self)` and so on), so a
// view reads only what it draws.

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
    private(set) var credentials: Credentials?
    private(set) var client: JellyfinClient?

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

    /// A client for a server address, before anyone has signed in: what the
    /// sign-in screen asks for the server's name and signs in with.
    func client(for serverURL: URL) -> JellyfinClient {
        JellyfinClient(serverURL: serverURL, identity: identity)
    }

    /// Signed in last time: open as it was, the library from disk at once.
    func restore() async {
        guard phase == .launching else { return }
        if let saved = Keychain.loadCredentials() {
            await begin(saved)
        } else {
            phase = .signedOut
        }
    }

    /// After the sign-in screen has credentials.
    func signIn(_ credentials: Credentials) async {
        Keychain.save(credentials)
        await begin(credentials)
    }

    func signOut() async {
        Stats.track(.signedOut)
        player.stop()
        // Also forgets this account's thumbs and recent stations.
        radio.reset()
        let client = self.client
        // What was heard offline and not yet told to the server goes on the
        // way out, when the server answers. Then the account's downloads go
        // (OfflineStore.signOut): the next account never plays its songs.
        let unsent = offline.takeReports()
        offline.signOut()
        Keychain.deleteCredentials()
        credentials = nil
        self.client = nil
        // Nothing streams, reports or asks the old server from here on.
        player.client = nil
        radio.client = nil
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
        if let client, !unsent.isEmpty { await OfflineReports.send(unsent, with: client) }
        await client?.signOut()
    }

    private func begin(_ credentials: Credentials) async {
        let client = JellyfinClient(credentials: credentials, identity: identity)
        self.credentials = credentials
        self.client = client
        player.client = client
        radio.client = client
        phase = .signedIn
        // The songs on the phone first: they play before the library from
        // the server has come, or without it.
        await offline.open(credentials: credentials, client: client)
        await library.open(client: client, credentials: credentials)
        // The radio first: its graph is made in the background and needs
        // nothing from the mixes, so it does not wait for them to be made.
        radio.prepare()
        await mixes.rebuild(library: library, history: history, settings: settings)
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
    private static func deviceID() -> String {
        let key = "deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
