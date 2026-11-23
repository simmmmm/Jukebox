// The quick switch between the accounts kept (Accounts.swift), in a menu:
// the iPad's ≡ menu, as Linux's primary menu has it, and the Mac's menu
// bar, where Music has its own Account menu. The one signed in is checked;
// another chosen switches (AppModel.choose, which says in RootView's alert
// why not, when its server does not answer). Add Account… opens the
// sign-in in a sheet over the window (RootView). Sign Out… of the one
// signed in, as Linux's primary menu, where the menu can ask first
// (`signOut`): the iPad's ≡ there, the Mac's Account menu over the main
// window (RootView), in Settings' words (signOutConfirmation).

import JukeboxKit
import SwiftUI

struct AccountMenuItems: View {
    let app: AppModel
    /// Asks before signing out of the account signed in; nil leaves
    /// Sign Out… out (a menu with nowhere to ask).
    var signOut: (() -> Void)?

    init(app: AppModel, signOut: (() -> Void)? = nil) {
        self.app = app
        self.signOut = signOut
    }

    var body: some View {
        if app.accounts.saved.count > 1 {
            Picker("Account", selection: chosen) {
                ForEach(app.accounts.saved, id: \.self) { account in
                    Text(verbatim: "\(ServerWords.name(of: account)) · \(account.userName)")
                        .tag(OfflinePaths.account(for: account))
                }
            }
            .pickerStyle(.inline)
        }
        Button("Add Account…") { app.navigator.isAddingAccount = true }
            .disabled(app.phase != .signedIn)
        if let signOut {
            Button("Sign Out…", action: signOut)
                .disabled(app.credentials == nil)
        }
        // The account's year, out of Settings (it is content, not a
        // setting): its place in the sidebar, as Linux's primary menu has
        // On Your Jukebox. A menu bar has no Library menu; this is the one about
        // the account.
        Divider()
        Button("On Your Jukebox") { app.navigator.place = .library(.yourYear) }
            // The wide window's place; the iPhone's tabs have Library's row.
            .disabled(!app.navigator.isWide || app.phase != .signedIn)
    }

    /// The account signed in, by its folder's name; set, the switch.
    private var chosen: Binding<String> {
        Binding(get: { app.credentials.map { OfflinePaths.account(for: $0) } ?? "" },
                set: { name in
                    guard let account = app.accounts.saved.first(where: { OfflinePaths.account(for: $0) == name }) else { return }
                    app.choose(account)
                })
    }
}

extension View {
    /// Settings' question before signing out of the account signed in
    /// (SettingsAccountSection), for a menu's Sign Out….
    func signOutConfirmation(isPresented: Binding<Bool>, app: AppModel) -> some View {
        confirmationDialog(SignOutWords.title(app), isPresented: isPresented, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await app.signOut() }
            }
        } message: {
            Text(SignOutWords.message(app))
        }
    }
}

/// Settings' words for signing out of the account signed in.
enum SignOutWords {
    /// The server and the user, as Linux asks: which of several accounts
    /// goes is never a guess (docs/design/settings.md).
    static func title(_ app: AppModel) -> Text {
        if let credentials = app.credentials {
            return Text("Sign out of \(ServerWords.name(of: credentials)) as \(credentials.userName)?")
        }
        return Text("Sign out?")
    }

    /// With others kept, it says which one Jukebox goes on with.
    static func message(_ app: AppModel) -> String {
        let others = app.accounts.saved.filter { app.credentials?.isSameAccount(as: $0) != true }
        if let next = others.first {
            return String(localized: "Playback stops and Jukebox forgets this account’s library, recent stations and downloaded songs on this \(Device.model), then goes on with \(ServerWords.name(of: next)). Your music, playlists and favorites stay on the server.")
        }
        return String(localized: "Playback stops and Jukebox forgets the library, your recent stations and the downloaded songs on this \(Device.model). Your music, playlists and favorites stay on the server.")
    }
}
