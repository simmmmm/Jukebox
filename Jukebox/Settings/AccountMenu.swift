// The quick switch between the accounts kept (Accounts.swift), in a menu:
// the iPad's ≡ menu, as Linux's primary menu has it, and the Mac's menu
// bar, where Music has its own Account menu. The one signed in is checked;
// another chosen switches (AppModel.choose, which says in RootView's alert
// why not, when its server does not answer). Add Account… opens the
// sign-in in a sheet over the window (RootView). Signing out stays in
// Settings, where it is asked about first.

import JukeboxKit
import SwiftUI

struct AccountMenuItems: View {
    let app: AppModel

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
