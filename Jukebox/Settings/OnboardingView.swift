// Signed out: the welcome, then signing in to a server in two steps — where
// the server is, then who is listening. One address field for any server:
// what answers there is found, not asked ("Jellyfin or Subsonic?" is no
// question a listener should get; docs/SERVERS.md, decision 5).
// MusicServers.detect asks the address both ways at once, Jellyfin's
// /System/Info/Public and Subsonic's /rest/ping.view, without a password, so
// a typing mistake shows at once and the second step can say "Signing in to
// Tijmen's Music · Jellyfin 12.4.0" or "Navidrome 0.64.2". Then the user name
// and password, for every server; where a Jellyfin offers Quick Connect, a
// code to type into another Jellyfin app that is signed in already saves
// typing a password on the phone; where a Subsonic server signs in with API
// keys instead, a key. An address typed without a port is tried as typed and
// then on each server's own (http: Jellyfin's 8096, Navidrome's 4533,
// Gonic's 4747, Airsonic's 4040, LMS's 5082; MusicServers.candidateAddresses):
// "192.168.1.10" or "nas.local" for a fresh install, which listens on its
// own port only, then simply works rather than saying there is nothing there.
// The photographer, 9 November 2026: "Kun je die navidunges en subsonic
// toevoegen dan Istie erna wel klaar voor release".
//
// The fields on the page's ground between hairlines, no card (docs/design/
// tells.md, 6), under the mark on its sleeve: the first thing anyone sees
// of Jukebox is its mark coming on, close, then the sleeve whole and its
// record sliding out (WelcomeSleeve, in ShellAppMark.swift).
// The address and the user name are remembered for the next sign-in (after a
// sign-out); the password never is — the keychain's AutoFill offers it.
//
// In a wide window (the iPad, the Mac) it is Linux's sign-in, 1:1
// (17-sign-in.png; "ik wil dat de linux app en de apple app 1:1 op elkaar
// lijken", the photographer, 14 November 2026): a column of 420 centred in
// the window, its words starting at its left edge, "Jukebox" at a page
// title's size, and one page, not two steps: the address, the user name
// and the password in one group of rows, Sign In centred under them, as
// wide as its word (OnboardingWideForm).

import AuthenticationServices
import JukeboxKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.isWide) private var isWide

    @State private var step: OnboardingStep = .server
    @State private var address = OnboardingMemory.serverAddress
    @State private var isConnecting = false
    @State private var serverError: String?
    @FocusState private var isAddressFocused: Bool
    /// Wide: the second step was asked for by Quick Connect on the one
    /// page, so it starts there and its Cancel comes back to the page.
    @State private var startsQuickConnect = false
    /// Settings' Add Account: the same screen in a sheet, with Cancel; it
    /// closes once the new account is the one signed in.
    let isAdding: Bool
    @Environment(\.dismiss) private var dismiss

    init(isAdding: Bool = false) {
        self.isAdding = isAdding
        // Often the same server and another user: the address stays, the
        // user name is typed afresh.
        if isAdding { OnboardingMemory.userName = "" }
    }

    var body: some View {
        page
            .onChange(of: app.credentials) { _, signedIn in
                if isAdding, signedIn != nil { dismiss() }
            }
    }

    private var page: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    // Linux's column: 24 between each of its parts.
                    VStack(spacing: isWide ? Theme.Space.xl : Theme.Space.xxl) {
                        OnboardingWelcome(animatesIn: !isAdding)
                        // One on top of the other while they cross-fade, so
                        // the page does not grow by both for a moment.
                        ZStack(alignment: .top) {
                            switch step {
                            case .server:
                                Group {
                                    if isWide {
                                        OnboardingWideForm(quickConnect: { server in quickConnect(on: server) })
                                    } else {
                                        serverForm
                                    }
                                }
                                .transition(.opacity)
                            case let .account(server):
                                OnboardingAccountForm(server: server, serverSignIn: app.signIn(to: server),
                                                      changeServer: { changeServer() },
                                                      startsQuickConnect: startsQuickConnect)
                                    .transition(.opacity)
                            }
                        }
                    }
                    // A phone's width on the iPad too: a sign-in form
                    // stretched across 1000 points reads as nothing. Wide,
                    // Linux's: 420 with its margins of 24.
                    .frame(maxWidth: isWide ? 372 : 440)
                    // Wide, the fields and their words in Linux's 15.
                    .desktopFont(Tokens.Size.body15.size, phone: nil)
                    .padding(.horizontal, isWide ? Theme.Space.xl : Theme.margin)
                    .padding(.vertical, Theme.Space.xl)
                    // Centred in the screen while it fits, scrolling when the
                    // keyboard leaves less room.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.ground.ignoresSafeArea())
            .inlineTitle()
            .toolbar {
                if isAdding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            #if os(macOS)
            // Every Mac window has a name (the Window menu, Mission
            // Control); the page says it again in the serif, as Linux's
            // header does over its sign-in.
            .navigationTitle("Jukebox")
            #endif
        }
    }

    // MARK: Step 1, the server

    private var serverForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            OnboardingFields {
                TextField("Server Address", text: $address, prompt: Text(verbatim: "music.example.com"))
                    .urlEntry()
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isAddressFocused)
                    .onSubmit { connect() }
                    .frame(minHeight: 52)
            }
            Text("The address you open your Jellyfin, Emby, Plex or Navidrome server at in a browser, such as music.example.com or 192.168.1.10:8096.")
                .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                .foregroundStyle(.secondary)
            if let serverError {
                OnboardingErrorText(message: serverError)
            }
            Button {
                connect()
            } label: {
                OnboardingButtonLabel(title: "Continue", isWorking: isConnecting)
            }
            .buttonStyle(.prominent)
            // Centred under the fields, as the welcome above them and Linux's.
            .frame(maxWidth: .infinity)
            .disabled(trimmedAddress.isEmpty)
            .accessibilityLabel(isConnecting ? Text("Connecting") : Text("Continue"))
            .padding(.top, Theme.Space.s)

            // Plex's people seldom know their server's address: plex.tv
            // does, once they have signed in there.
            PlexSignInButton(show: show)
                .disabled(isConnecting)
            Text("For Plex, sign in at plex.tv in your browser instead; Jukebox never sees your Plex password.")
                .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connect() {
        guard !isConnecting else { return }
        let typed = trimmedAddress
        guard !typed.isEmpty else { return }
        let candidates = MusicServers.candidateAddresses(for: typed)
        guard let first = candidates.first else {
            show(String(localized: "That is not a server address. Try one like music.example.com."))
            return
        }
        serverError = nil
        isConnecting = true
        isAddressFocused = false
        Task {
            do {
                // Every candidate at once, both ways at once; the first in
                // order that proves to be a server wins, so the address as
                // typed wins whenever it works, and the fallback ports add no
                // wait of their own. What it offers (Quick Connect, an API
                // key) comes with it, so the second step opens complete.
                let server = try await app.detectServer(at: typed)
                // What answered, for the next sign-in: the port written out
                // when it took a fallback, so the next one goes straight there.
                OnboardingMemory.serverAddress = server.url == first ? typed : server.url.absoluteString
                isConnecting = false
                withAnimation(.easeInOut(duration: Tokens.Motion.move)) {
                    step = .account(server)
                }
            } catch {
                isConnecting = false
                // The kit's error is the address as typed's: the fallbacks
                // were this app's guess, and their "no answer on 8096" would
                // only confuse what went wrong with the first.
                Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                show(Self.message(for: error, at: first))
            }
        }
    }

    private func changeServer() {
        startsQuickConnect = false
        withAnimation(.easeInOut(duration: Tokens.Motion.move)) {
            step = .server
        }
    }

    private func quickConnect(on server: DetectedServer) {
        startsQuickConnect = true
        withAnimation(.easeInOut(duration: Tokens.Motion.move)) {
            step = .account(server)
        }
    }

    private func show(_ message: String) {
        serverError = message
        // Inline text appears silently; VoiceOver is told.
        AccessibilityNotification.Announcement(message).post()
    }

    fileprivate static func message(for error: Error, at url: URL) -> String {
        switch error as? MusicServerError {
        case .invalidServerAddress?:
            return String(localized: "There is no Jellyfin, Emby, Plex, Navidrome or other Subsonic server at this address.")
        case let .transport(reason)?:
            // Jukebox guesses https for a name with dots; a home server
            // behind plain http (or a certificate the phone does not trust)
            // fails here, and the fix is one word away.
            if url.scheme == "https" {
                return String(localized: "\(reason) If your server uses plain http, type http:// in front of the address.")
            }
            return reason
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Step 2, the account

private enum OnboardingStep: Equatable {
    case server
    /// The server that answered, its kind and what it offers.
    case account(DetectedServer)
}

private struct OnboardingAccountForm: View {
    let server: DetectedServer
    /// The kit's sign-in for this server: also a QuickConnectSignIn or an
    /// APIKeySignIn where the server offers one, so an option the server
    /// lacks is not a button at all.
    let serverSignIn: any ServerSignIn
    let changeServer: () -> Void
    /// Opened by Quick Connect on the wide page: the code at once, and
    /// Cancel goes back to that page.
    let startsQuickConnect: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.isWide) private var isWide
    /// The code is read off this screen and typed elsewhere: as large as
    /// the screen allows, and larger still with a larger text size.
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 56

    @State private var username = OnboardingMemory.userName
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    /// Waiting for Quick Connect: asking for a code, then polling. Cancelled
    /// by Cancel, by Change Server, and when this step goes away.
    @State private var quickConnectTask: Task<Void, Never>?
    @State private var quickConnectCode: String?
    /// The API key's form instead of the password's: chosen, or because the
    /// server said it takes no tokens made from a password.
    @State private var usesAPIKey = false
    @State private var apiKey = ""
    /// Where the server says to make a key (OpenSubsonic's `helpUrl`).
    @State private var apiKeyHelp: URL?
    @FocusState private var focus: Field?
    @Environment(\.openURL) private var openURL

    private enum Field: Hashable {
        case username
        case password
        case apiKey
    }

    init(server: DetectedServer, serverSignIn: any ServerSignIn, changeServer: @escaping () -> Void,
         startsQuickConnect: Bool = false) {
        self.server = server
        self.serverSignIn = serverSignIn
        self.changeServer = changeServer
        self.startsQuickConnect = startsQuickConnect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            if isQuickConnecting {
                quickConnectPanel
            } else if usesAPIKey, apiKeySignIn != nil {
                apiKeyForm
            } else if server.kind == .plex {
                plexForm
            } else {
                passwordForm
            }
        }
        .multilineTextAlignment(isWide ? .center : .leading)
        .toolbar {
            ToolbarItem(placement: .barLeading) {
                Button {
                    cancelQuickConnect()
                    changeServer()
                } label: {
                    Label("Change Server", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(isSigningIn)
            }
        }
        .onDisappear {
            quickConnectTask?.cancel()
        }
        .onAppear {
            if startsQuickConnect { startQuickConnect() }
        }
    }

    private var isQuickConnecting: Bool { quickConnectTask != nil }

    /// Wide, the buttons and the notes under the rows on the column's axis,
    /// as the first step and Linux have them; the iPhone's stay at the
    /// margin under its full-width Sign In.
    private var formAlignment: HorizontalAlignment { isWide ? .center : .leading }

    /// Quick Connect, where a Jellyfin has it turned on.
    private var quickConnect: (any QuickConnectSignIn)? {
        guard server.capabilities.contains(.quickConnect) else { return nil }
        return serverSignIn as? any QuickConnectSignIn
    }

    /// An API key, where a Subsonic server lists `apiKeyAuthentication`.
    private var apiKeySignIn: (any APIKeySignIn)? {
        serverSignIn as? any APIKeySignIn
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var header: some View {
        // Centred on every width, as the welcome above it.
        VStack(spacing: Theme.Space.xs) {
            Text("Signing in to \(server.name)")
                .desktopFont(Tokens.Size.body15.size, weight: .bold, phone: .headline)
            Text(verbatim: serverDetail)
                .desktopFont(Tokens.Size.fact13.size, phone: .subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    /// "Jellyfin 12.4.0 · music.example.com", "Navidrome 0.64.2 ·
    /// nas.local:4533": which kind of server, and with the port when there
    /// is one, as the address may be a fallback, not the one typed, and this
    /// says which answered. A Subsonic server has no name, so the header has
    /// its host already: not said twice when there is no port to add.
    private var serverDetail: String {
        var parts = [ServerWords.product(server.kind, version: server.version)]
        if let host = server.url.host() {
            if let port = server.url.port {
                parts.append("\(host):\(port)")
            } else if host != server.name {
                parts.append(host)
            }
        } else {
            parts.append(server.url.absoluteString)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: User name and password

    private var passwordForm: some View {
        VStack(alignment: formAlignment, spacing: Theme.Space.m) {
            OnboardingFields {
                TextField("User Name", text: $username)
                    .textContentType(.username)
                    .plainTextEntry()
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
                    .frame(minHeight: 52)
                Divider()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { signIn() }
                    .frame(minHeight: 52)
            }
            if let errorMessage {
                OnboardingErrorText(message: errorMessage)
            }
            Button {
                signIn()
            } label: {
                OnboardingButtonLabel(title: "Sign In", isWorking: isSigningIn)
            }
            .buttonStyle(.prominent)
            // Centred under the fields, as the welcome above them and Linux's.
            .frame(maxWidth: .infinity)
            // A Jellyfin user may have no password: only the name is needed.
            .disabled(trimmedUsername.isEmpty)
            .accessibilityLabel(isSigningIn ? Text("Signing In") : Text("Sign In"))
            .padding(.top, Theme.Space.s)

            if quickConnect != nil {
                Button {
                    startQuickConnect()
                } label: {
                    Text("Use Quick Connect")
                }
                .buttonStyle(.secondary)
                // Centred under the fields, as the welcome above them and Linux's.
                .frame(maxWidth: .infinity)
                .disabled(isSigningIn)
                Text("Sign in from another Jellyfin app that is already signed in, without typing your password here.")
                    .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                    .foregroundStyle(.secondary)
            }
            if apiKeySignIn != nil {
                Button {
                    switchToAPIKey(help: nil)
                } label: {
                    Text("Use an API Key")
                }
                .buttonStyle(.secondary)
                // Centred under the fields, as the welcome above them and Linux's.
                .frame(maxWidth: .infinity)
                .disabled(isSigningIn)
            }
        }
    }

    private func signIn() {
        guard !isSigningIn, !isQuickConnecting else { return }
        let name = trimmedUsername
        guard !name.isEmpty else { return }
        let password = self.password
        let passwordSignIn = serverSignIn
        errorMessage = nil
        isSigningIn = true
        focus = nil
        // Not tied to this view: once signed in the app swaps this screen
        // for the library while `signIn` is still loading it.
        Task {
            do {
                let credentials = try await passwordSignIn.signIn(username: name, password: password)
                OnboardingMemory.userName = name
                Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "password"])
                await app.signIn(credentials)
            } catch MusicServerError.needsAPIKey(let help) {
                // The server keeps only a hash of the password, so it cannot
                // check a token made from it, and it takes keys: one is
                // asked for rather than the password itself, which would go
                // with every request (docs/SERVERS.md, "Signing in").
                isSigningIn = false
                Stats.track(.signInFailed, ["reason": "needs_api_key"])
                switchToAPIKey(help: help)
                show(String(localized: "This server signs in with an API key rather than a password. Make one in its settings, then paste it here."))
            } catch {
                isSigningIn = false
                Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                show(Self.signInMessage(for: error))
            }
        }
    }

    // MARK: Plex

    /// A Plex server has no passwords of its own: its people sign in at
    /// plex.tv. A token, for a server reached without plex.tv, goes where
    /// an API key goes.
    private var plexForm: some View {
        VStack(alignment: formAlignment, spacing: Theme.Space.m) {
            Text("Plex opens in your browser to sign in; Jukebox never sees your Plex password.")
                .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                .foregroundStyle(.secondary)
            if let errorMessage {
                OnboardingErrorText(message: errorMessage)
            }
            PlexSignInButton(server: server, prominent: true, show: show)
                .padding(.top, Theme.Space.s)
            Button {
                switchToAPIKey(help: PlexSignIn.tokenHelp)
            } label: {
                Text("Use a Token")
            }
            .buttonStyle(.secondary)
            // Centred under the fields, as the welcome above them and Linux's.
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: An API key

    private var apiKeyForm: some View {
        VStack(alignment: formAlignment, spacing: Theme.Space.m) {
            OnboardingFields {
                // Plex's own word for its key (X-Plex-Token).
                SecureField(LocalizedStringKey(isPlex ? "Token" : "API Key"), text: $apiKey)
                    .plainTextEntry()
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focus, equals: .apiKey)
                    .onSubmit { signInWithAPIKey() }
                    .frame(minHeight: 52)
            }
            Group {
                if isPlex {
                    Text("Plex’s token for this server, for a server you reach without plex.tv.")
                } else {
                    Text("A key made in the server’s own settings, for Jukebox alone: it can be taken back there without changing your password.")
                }
            }
            .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
            .foregroundStyle(.secondary)
            if let errorMessage {
                OnboardingErrorText(message: errorMessage)
            }
            Button {
                signInWithAPIKey()
            } label: {
                OnboardingButtonLabel(title: "Sign In", isWorking: isSigningIn)
            }
            .buttonStyle(.prominent)
            // Centred under the fields, as the welcome above them and Linux's.
            .frame(maxWidth: .infinity)
            .disabled(trimmedAPIKey.isEmpty)
            .accessibilityLabel(isSigningIn ? Text("Signing In") : Text("Sign In"))
            .padding(.top, Theme.Space.s)

            if let apiKeyHelp {
                Button {
                    openURL(apiKeyHelp)
                } label: {
                    isPlex ? Text("How to Find a Token") : Text("How to Make a Key")
                }
                .buttonStyle(.secondary)
                // Centred under the fields, as the welcome above them and Linux's.
                .frame(maxWidth: .infinity)
            }
            Button {
                usesAPIKey = false
                errorMessage = nil
            } label: {
                isPlex ? Text("Sign In with Plex Instead") : Text("Use a Password Instead")
            }
            .buttonStyle(.secondary)
            // Centred under the fields, as the welcome above them and Linux's.
            .frame(maxWidth: .infinity)
            .disabled(isSigningIn)
        }
    }

    private var isPlex: Bool { server.kind == .plex }

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func switchToAPIKey(help: URL?) {
        if let help { apiKeyHelp = help }
        errorMessage = nil
        usesAPIKey = true
        focus = .apiKey
    }

    private func signInWithAPIKey() {
        guard !isSigningIn, let keySignIn = apiKeySignIn else { return }
        let key = trimmedAPIKey
        guard !key.isEmpty else { return }
        errorMessage = nil
        isSigningIn = true
        focus = nil
        Task {
            do {
                let credentials = try await keySignIn.signIn(apiKey: key)
                Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "api_key"])
                await app.signIn(credentials)
            } catch {
                isSigningIn = false
                Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                show(Self.apiKeyMessage(for: error))
            }
        }
    }

    // MARK: Quick Connect

    private var quickConnectPanel: some View {
        VStack(spacing: Theme.Space.m) {
            VStack(spacing: Theme.Space.l) {
                if let code = quickConnectCode {
                    Text(code)
                        .font(.system(size: codeSize, weight: .semibold))
                        .monospacedDigit()
                        .tracking(codeSize * 0.12)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .textSelection(.enabled)
                        // Read digit by digit, as it is typed.
                        .accessibilityLabel(Text(verbatim: code.map { String($0) }.joined(separator: " ")))
                    Text("Enter this code in another Jellyfin app: Settings › Quick Connect")
                        .desktopFont(Tokens.Size.fact13.size, phone: .subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: Theme.Space.s) {
                        ProgressView()
                        Text("Waiting…")
                    }
                    .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                } else {
                    ProgressView()
                    Text("Asking \(server.name) for a code…")
                        .desktopFont(Tokens.Size.fact13.size, phone: .subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }

            Button {
                cancelQuickConnect()
                // Back to the one page it was asked for from.
                if startsQuickConnect { changeServer() }
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.secondary)
            // Centred under the fields, as the welcome above them and Linux's.
            .frame(maxWidth: .infinity)
        }
    }

    private func startQuickConnect() {
        guard !isQuickConnecting, !isSigningIn, let quickConnect else { return }
        errorMessage = nil
        focus = nil
        quickConnectTask = Task {
            do {
                var state = try await quickConnect.quickConnectStart()
                // Cancelled while the server answered: a newer attempt's
                // code may already be on screen.
                try Task.checkCancellation()
                quickConnectCode = state.code
                // The server says nothing by itself: ask until the code has
                // been entered elsewhere. Every 3 s is quick to notice and
                // gentle on the server for the few minutes a code lives.
                while !state.isAuthenticated {
                    try await Task.sleep(for: .seconds(3))
                    state = try await quickConnect.quickConnectState(secret: state.secret)
                }
                let credentials = try await quickConnect.signIn(quickConnectSecret: state.secret)
                // Cancel tapped in that last moment still means cancel.
                try Task.checkCancellation()
                // From here it is signing in, not waiting: nothing for Cancel
                // or this view's going away to stop.
                quickConnectTask = nil
                Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "quick_connect"])
                await app.signIn(credentials)
            } catch {
                // Cancelled: Cancel or Change Server already put the form back.
                guard !Task.isCancelled else { return }
                quickConnectTask = nil
                quickConnectCode = nil
                Stats.track(.signInFailed, ["reason": Stats.signInFailure(error, quickConnect: true)])
                show(Self.quickConnectMessage(for: error))
            }
        }
    }

    private func cancelQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectCode = nil
    }

    private func show(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }

    fileprivate static func signInMessage(for error: Error) -> String {
        switch error as? MusicServerError {
        case .unauthorized?:
            return String(localized: "That user name and password did not work on this server.")
        case .passwordNeedsHTTPS?:
            // A server that takes neither tokens nor keys has the password
            // itself sent with every request and in every song's address:
            // only over https, or at home (docs/SERVERS.md, "Signing in").
            return String(localized: "This server needs your password sent with every song, so Jukebox only signs in to it over a secure connection. Use its https:// address.")
        case .notAllowed?:
            return String(localized: "This server does not let this account play music.")
        default:
            return error.localizedDescription
        }
    }

    fileprivate static func apiKeyMessage(for error: Error) -> String {
        switch error as? MusicServerError {
        case .unauthorized?:
            return String(localized: "That API key did not work on this server.")
        case .notAllowed?:
            return String(localized: "This server does not let this account play music.")
        default:
            return error.localizedDescription
        }
    }

    private static func quickConnectMessage(for error: Error) -> String {
        switch error as? MusicServerError {
        case .notFound?:
            // The server forgets a code after a few minutes.
            return String(localized: "The code has expired. Use Quick Connect again for a new one.")
        case .unauthorized?:
            return String(localized: "Quick Connect is turned off on this server. Sign in with your password instead.")
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Wide: one page, as Linux's

/// Linux's sign-in for a wide window (17-sign-in.png): the address, the user
/// name and the password in one group of rows, and Sign In, which finds the
/// server and signs in to it. The address is asked as soon as it is left,
/// so what that server offers (Quick Connect, an API key) shows under Sign
/// In; a server that signs in with a key turns the password's row into the
/// key's, as on Linux.
private struct OnboardingWideForm: View {
    let quickConnect: (DetectedServer) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var address = OnboardingMemory.serverAddress
    @State private var username = OnboardingMemory.userName
    @State private var secret = ""
    /// What answered at `detectedAt`, and the kit's way in to it.
    @State private var server: DetectedServer?
    @State private var serverSignIn: (any ServerSignIn)?
    @State private var detectedAt = ""
    /// The key's row instead of the password's: chosen, or because the
    /// server takes no tokens made from a password.
    @State private var usesAPIKey = false
    /// Where the server says to make a key (OpenSubsonic's `helpUrl`).
    @State private var apiKeyHelp: URL?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case address
        case username
        case secret
    }

    init(quickConnect: @escaping (DetectedServer) -> Void) {
        self.quickConnect = quickConnect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            OnboardingFields {
                // Named for the screenshot walk: here the first text field
                // is the address, not the user name as on the second step.
                TextField("Server Address", text: $address)
                    .urlEntry()
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .address)
                    .onSubmit { focus = usesAPIKey ? .secret : .username }
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("signIn.address")
                if !usesAPIKey {
                    Divider()
                    TextField("User Name", text: $username)
                        .textContentType(.username)
                        .plainTextEntry()
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .secret }
                        .frame(minHeight: 52)
                        .accessibilityIdentifier("signIn.user")
                }
                Divider()
                Group {
                    if usesAPIKey {
                        SecureField("API Key", text: $secret)
                            .plainTextEntry()
                    } else {
                        SecureField("Password", text: $secret)
                            .textContentType(.password)
                    }
                }
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .secret)
                .onSubmit { signIn() }
                .frame(minHeight: 52)
                .accessibilityIdentifier("signIn.password")
            }
            if let errorMessage {
                OnboardingErrorText(message: errorMessage)
            }
            // Centred under the rows, as Linux has it; what the server
            // offers besides a password under it, once it has answered.
            VStack(spacing: Theme.Space.s) {
                Button {
                    signIn()
                } label: {
                    OnboardingButtonLabel(title: "Sign In", isWorking: isWorking)
                }
                .buttonStyle(.prominent)
                // Centred under the fields, as the welcome above them and Linux's.
                .frame(maxWidth: .infinity)
                .fixedSize()
                .disabled(!canSignIn)
                .accessibilityLabel(isWorking ? Text("Signing In") : Text("Sign In"))
                if let server, server.capabilities.contains(.quickConnect),
                   (serverSignIn as? any QuickConnectSignIn) != nil, !usesAPIKey {
                    Button {
                        quickConnect(server)
                    } label: {
                        Text("Use Quick Connect")
                    }
                    .buttonStyle(.secondary)
                    // Centred under the fields, as the welcome above them and Linux's.
                    .frame(maxWidth: .infinity)
                    .disabled(isWorking)
                }
                if (serverSignIn as? any APIKeySignIn) != nil {
                    Button {
                        usesAPIKey.toggle()
                        secret = ""
                        errorMessage = nil
                        focus = .secret
                    } label: {
                        usesAPIKey ? Text("Use a Password Instead") : Text("Use an API Key")
                    }
                    .buttonStyle(.secondary)
                    // Centred under the fields, as the welcome above them and Linux's.
                    .frame(maxWidth: .infinity)
                    .disabled(isWorking)
                }
                if usesAPIKey, let apiKeyHelp {
                    Button {
                        openURL(apiKeyHelp)
                    } label: {
                        Text("How to Make a Key")
                    }
                    .buttonStyle(.secondary)
                    // Centred under the fields, as the welcome above them and Linux's.
                    .frame(maxWidth: .infinity)
                }
                // Where Quick Connect is, as on Linux: a Plex server found
                // at the address is the one signed in to; with none, the
                // account's own.
                PlexSignInButton(server: server?.kind == .plex ? server : nil, show: show)
                    .disabled(isWorking)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // The first row still to fill has the keys, as on Linux.
            if trimmed(address).isEmpty {
                focus = .address
            } else {
                focus = trimmed(username).isEmpty ? .username : .secret
                detectQuietly()
            }
        }
        // The address left: asked now, so the options it has show.
        .onChange(of: focus) { old, _ in
            if old == .address { detectQuietly() }
        }
        // Another address: what the last one offered no longer holds.
        .onChange(of: address) { _, _ in
            guard !detectedAt.isEmpty, trimmed(address) != detectedAt else { return }
            server = nil
            serverSignIn = nil
            detectedAt = ""
            usesAPIKey = false
        }
    }

    private var canSignIn: Bool {
        guard !trimmed(address).isEmpty else { return false }
        // A Jellyfin user may have no password: only the name is needed.
        return usesAPIKey ? !trimmed(secret).isEmpty : !trimmed(username).isEmpty
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func signIn() {
        guard !isWorking, canSignIn else { return }
        let typed = trimmed(address)
        guard let first = MusicServers.candidateAddresses(for: typed).first else {
            show(String(localized: "That is not a server address. Try one like music.example.com."))
            return
        }
        let name = trimmed(username)
        let typedSecret = secret
        let withKey = usesAPIKey
        errorMessage = nil
        isWorking = true
        focus = nil
        // Not tied to this view: once signed in the app swaps this screen
        // for the library while `signIn` is still loading it.
        Task {
            guard let way = await signInWay(at: typed, first: first) else {
                isWorking = false
                return
            }
            do {
                if withKey, let keySignIn = way as? any APIKeySignIn {
                    let credentials = try await keySignIn.signIn(apiKey: trimmed(typedSecret))
                    Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "api_key"])
                    await app.signIn(credentials)
                } else {
                    let credentials = try await way.signIn(username: name, password: typedSecret)
                    OnboardingMemory.userName = name
                    Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "password"])
                    await app.signIn(credentials)
                }
            } catch MusicServerError.needsAPIKey(let help) {
                // As on the iPhone: a key is asked for rather than the
                // password itself, which would go with every request.
                isWorking = false
                Stats.track(.signInFailed, ["reason": "needs_api_key"])
                if let help { apiKeyHelp = help }
                usesAPIKey = true
                secret = ""
                focus = .secret
                show(String(localized: "This server signs in with an API key rather than a password. Make one in its settings, then paste it here."))
            } catch {
                isWorking = false
                Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                show(withKey ? OnboardingAccountForm.apiKeyMessage(for: error)
                             : OnboardingAccountForm.signInMessage(for: error))
            }
        }
    }

    /// The way in to the server at `typed`, asked once an address; nil
    /// when nothing answered there, said why.
    private func signInWay(at typed: String, first: URL) async -> (any ServerSignIn)? {
        if detectedAt == typed, let serverSignIn { return serverSignIn }
        do {
            let found = try await app.detectServer(at: typed)
            return keep(found, at: typed, first: first)
        } catch {
            // The address as typed's error, as the iPhone's first step says.
            Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
            show(OnboardingView.message(for: error, at: first))
            return nil
        }
    }

    /// Asks the address without a word when it fails: Sign In says why.
    private func detectQuietly() {
        let typed = trimmed(address)
        guard !isWorking, !typed.isEmpty, typed != detectedAt,
              let first = MusicServers.candidateAddresses(for: typed).first else { return }
        Task {
            guard let found = try? await app.detectServer(at: typed), trimmed(address) == typed else { return }
            keep(found, at: typed, first: first)
        }
    }

    /// The server that answered and the way in to it, kept for this
    /// address; the way returned.
    @discardableResult
    private func keep(_ found: DetectedServer, at typed: String, first: URL) -> any ServerSignIn {
        let way = app.signIn(to: found)
        server = found
        serverSignIn = way
        detectedAt = typed
        // What answered, for the next sign-in: the port written out when it
        // took a fallback, so the next one goes straight there.
        OnboardingMemory.serverAddress = found.url == first ? typed : found.url.absoluteString
        return way
    }

    private func show(_ message: String) {
        errorMessage = message
        // Inline text appears silently; VoiceOver is told.
        AccessibilityNotification.Announcement(message).post()
    }
}

// MARK: - Plex

/// Sign In with Plex: plex.tv's own page in the browser (Apple's web
/// sign-in, with Safari's Plex sign-in if there is one), so the password
/// goes to Plex and never to Jukebox; meanwhile the kit asks plex.tv every
/// 2 s whether it is done (JukeboxKit's PlexAccount, docs/SERVERS.md
/// "Plex"). Then the account's server: the one found at the address typed,
/// the only one, or the one chosen from a list when there are several.
/// The owner, 17 November 2026: "emby en plex kunnen beide toch".
private struct PlexSignInButton: View {
    /// The Plex server found at the address typed: that one is signed in to.
    var server: DetectedServer?
    /// The step's one filled button (a Plex server's account step).
    var prominent = false
    let show: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var task: Task<Void, Never>?
    @State private var choices: [PlexAccount.Server] = []
    @State private var accountToken = ""
    @State private var isChoosing = false

    var body: some View {
        Group {
            if task != nil {
                VStack(spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.s) {
                        ProgressView()
                        Text("Waiting for Plex…")
                    }
                    .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    Button {
                        task?.cancel()
                        task = nil
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.secondary)
                    // Centred under the fields, as the welcome above them and Linux's.
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            } else if prominent {
                Button {
                    start()
                } label: {
                    Text("Sign In with Plex")
                }
                .buttonStyle(.prominent)
                // Centred under the fields, as the welcome above them and Linux's.
                .frame(maxWidth: .infinity)
            } else {
                Button {
                    start()
                } label: {
                    Text("Sign In with Plex")
                }
                .buttonStyle(.secondary)
                // Centred under the fields, as the welcome above them and Linux's.
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Which Plex Server?", isPresented: $isChoosing, titleVisibility: .visible) {
            ForEach(choices) { choice in
                Button(choice.name) { finish(choice) }
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func start() {
        let account = PlexAccount(identity: app.identity)
        let session = webAuthenticationSession
        task = Task {
            do {
                let pin = try await account.start(forwardURL: URL(string: "jukebox://plex"))
                // Plex's page and the asking side by side: the token ends
                // both, the page cancelled rather than waited for (Plex may
                // not go on to jukebox:// by itself). The page closed by the
                // person stops the asking; closed by Plex going on, the
                // asking finishes.
                let asking = Task { try await account.token(for: pin) }
                let page = Task { @MainActor in
                    do {
                        _ = try await session.authenticate(using: pin.authURL, callbackURLScheme: "jukebox")
                    } catch {
                        asking.cancel()
                    }
                }
                let token: String
                do {
                    token = try await withTaskCancellationHandler {
                        try await asking.value
                    } onCancel: {
                        asking.cancel()
                    }
                } catch {
                    page.cancel()
                    throw error
                }
                page.cancel()
                var servers = try await account.servers(token: token)
                if let server {
                    servers = servers.filter { $0.id == server.id }
                    guard !servers.isEmpty else {
                        return fail(String(localized: "This Plex account cannot play from \(server.name)."))
                    }
                }
                guard !servers.isEmpty else {
                    return fail(String(localized: "This Plex account has no server to play from yet."))
                }
                accountToken = token
                if servers.count == 1 {
                    await signIn(servers[0], account: account)
                } else {
                    // The dialog is the wait now; its Cancel leaves the button.
                    task = nil
                    choices = servers
                    isChoosing = true
                }
            } catch {
                // Cancel already put the button back.
                guard !Task.isCancelled else { return }
                guard !(error is CancellationError) else {
                    task = nil
                    return
                }
                Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
                fail(Self.message(for: error))
            }
        }
    }

    private func finish(_ choice: PlexAccount.Server) {
        task = Task { await signIn(choice, account: PlexAccount(identity: app.identity)) }
    }

    private func signIn(_ choice: PlexAccount.Server, account: PlexAccount) async {
        do {
            let credentials = try await account.signIn(to: choice, accountToken: accountToken, preferring: server?.url)
            task = nil
            Stats.track(.signedIn, ["server": Stats.server(credentials.kind), "method": "plex_pin"])
            await app.signIn(credentials)
        } catch {
            guard !Task.isCancelled else { return }
            Stats.track(.signInFailed, ["reason": Stats.signInFailure(error)])
            fail(Self.message(for: error))
        }
    }

    private func fail(_ message: String) {
        task = nil
        show(message)
    }

    private static func message(for error: Error) -> String {
        switch error as? MusicServerError {
        case .notFound?:
            // plex.tv forgets a sign-in after 30 minutes.
            return String(localized: "The sign-in at Plex took too long. Sign in with Plex again.")
        case .unauthorized?:
            return String(localized: "Plex did not accept this sign-in. Sign in with Plex again.")
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Parts

/// The mark coming on on its sleeve, the name in the serif, and what
/// Jukebox is for: a fact, not a slogan.
private struct OnboardingWelcome: View {
    let animatesIn: Bool

    @Environment(\.isWide) private var isWide

    var body: some View {
        // One centred column on every client, as GNOME's welcome and status
        // pages and the iPhone have it. The photographer, 20 November 2026,
        // of a page half left, half centred: "weer parity, dit staat
        // opeens voor de helft links uitgelijnd?". Wide, Linux's column:
        // 24 between the mark, the name and the fact.
        VStack(spacing: isWide ? Theme.Space.xl : Theme.Space.l) {
            // 300 by 200 on the iPhone; wide, 240 by 160.
            WelcomeSleeve(width: isWide ? 240 : 300, animatesIn: animatesIn)
            VStack(spacing: isWide ? Theme.Space.xl : Theme.Space.s) {
                // Wide, a page title's 40, as Linux's sign-in sets "Jukebox".
                Text("Jukebox")
                    .desktopFont(Tokens.Size.pageTitle.size, design: .serif, phone: .serif(.largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Text("Music from your Jellyfin, Emby, Plex, Navidrome or other Subsonic server.")
                    .desktopFont(Tokens.Size.body15.size, phone: .body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    // Two lines rather than cut short where the page is
                    // tight (the first two steps cut it at "other…").
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Fields on the page's ground, a hairline above and below them, as a
/// form's rows without its card. Wide, Linux's group of rows instead
/// (17-sign-in.png): libadwaita's boxed list, its card one step up from
/// the ground (white by day; white at 8 % by night, #252423 on Night).
private struct OnboardingFields<Content: View>: View {
    let content: Content

    @Environment(\.isWide) private var isWide

    /// Computed: a generic type has no stored statics.
    private static var card: Color { Color(Tokens.field) }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if isWide {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, Theme.Space.m)
                // grid-ok: libadwaita's own radius for a boxed list.
                .background(Self.card, in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    Divider()
                    content
                    Divider()
                }
            }
        }
        #if os(macOS)
        // The rows are the fields' edges: no Mac bezel inside them as well.
        .textFieldStyle(.plain)
        #endif
    }
}

/// The button's word, or a spinner in its place while it works; the word
/// stays (hidden) so the button keeps its size.
private struct OnboardingButtonLabel: View {
    let title: LocalizedStringKey
    let isWorking: Bool

    var body: some View {
        ZStack {
            Text(title)
                .opacity(isWorking ? 0 : 1)
            if isWorking {
                ProgressView()
                    .tint(Theme.onAccent)
            }
        }
    }
}

/// An error under the fields: the system's red for the sign only, the words
/// in grey like the rest of the page's notes.
private struct OnboardingErrorText: View {
    let message: String

    @Environment(\.isWide) private var isWide

    var body: some View {
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
        .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
        .foregroundStyle(.secondary)
        // Wide, on the column's axis, as Linux's note under its rows.
        .multilineTextAlignment(isWide ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: isWide ? .center : .leading)
    }
}

/// What the last sign-in typed, for the next one: not secret, and a
/// sign-out (or a server move) should not mean typing it all again.
private enum OnboardingMemory {
    private static let addressKey = "onboarding.serverAddress"
    private static let userNameKey = "onboarding.userName"

    static var serverAddress: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: addressKey) }
    }

    static var userName: String {
        get { UserDefaults.standard.string(forKey: userNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }
}
