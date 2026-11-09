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
// tells.md, 6), under the mark, flat, its bands coming on one by one as a
// fade: the first thing anyone sees of Jukebox is its mark (ShellAppMark).
// The address and the user name are remembered for the next sign-in (after a
// sign-out); the password never is — the keychain's AutoFill offers it.

import JukeboxKit
import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    @State private var step: OnboardingStep = .server
    @State private var address = OnboardingMemory.serverAddress
    @State private var isConnecting = false
    @State private var serverError: String?
    @FocusState private var isAddressFocused: Bool

    init() {}

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.Space.xxl) {
                        OnboardingWelcome()
                        // One on top of the other while they cross-fade, so
                        // the page does not grow by both for a moment.
                        ZStack(alignment: .top) {
                            switch step {
                            case .server:
                                serverForm
                                    .transition(.opacity)
                            case let .account(server):
                                OnboardingAccountForm(server: server, serverSignIn: app.signIn(to: server),
                                                      changeServer: { changeServer() })
                                    .transition(.opacity)
                            }
                        }
                    }
                    // A phone's width on the iPad too: a sign-in form
                    // stretched across 1000 points reads as nothing.
                    .frame(maxWidth: 440)
                    .padding(.horizontal, Theme.margin)
                    .padding(.vertical, Theme.Space.xl)
                    // Centred in the screen while it fits, scrolling when the
                    // keyboard leaves less room.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.ground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Step 1, the server

    private var serverForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            OnboardingFields {
                TextField("Server Address", text: $address, prompt: Text(verbatim: "music.example.com"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isAddressFocused)
                    .onSubmit { connect() }
                    .frame(minHeight: 52)
            }
            Text("The address you open your Jellyfin or Navidrome server at in a browser, such as music.example.com or 192.168.1.10:8096.")
                .font(.footnote)
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
            .disabled(trimmedAddress.isEmpty)
            .accessibilityLabel(isConnecting ? Text("Connecting") : Text("Continue"))
            .padding(.top, Theme.Space.s)
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
                withAnimation(.easeInOut(duration: 0.25)) {
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
        withAnimation(.easeInOut(duration: 0.25)) {
            step = .server
        }
    }

    private func show(_ message: String) {
        serverError = message
        // Inline text appears silently; VoiceOver is told.
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private static func message(for error: Error, at url: URL) -> String {
        switch error as? MusicServerError {
        case .invalidServerAddress?:
            return String(localized: "There is no Jellyfin, Navidrome or other Subsonic server at this address.")
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

    @Environment(AppModel.self) private var app
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

    init(server: DetectedServer, serverSignIn: any ServerSignIn, changeServer: @escaping () -> Void) {
        self.server = server
        self.serverSignIn = serverSignIn
        self.changeServer = changeServer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            if isQuickConnecting {
                quickConnectPanel
            } else if usesAPIKey, apiKeySignIn != nil {
                apiKeyForm
            } else {
                passwordForm
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
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
    }

    private var isQuickConnecting: Bool { quickConnectTask != nil }

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
        VStack(spacing: 2) {
            Text("Signing in to \(server.name)")
                .font(.headline)
            Text(verbatim: serverDetail)
                .font(.subheadline)
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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            OnboardingFields {
                TextField("User Name", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
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
                .disabled(isSigningIn)
                Text("Sign in from another Jellyfin app that is already signed in, without typing your password here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if apiKeySignIn != nil {
                Button {
                    switchToAPIKey(help: nil)
                } label: {
                    Text("Use an API Key")
                }
                .buttonStyle(.secondary)
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

    // MARK: An API key

    private var apiKeyForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            OnboardingFields {
                SecureField("API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focus, equals: .apiKey)
                    .onSubmit { signInWithAPIKey() }
                    .frame(minHeight: 52)
            }
            Text("A key made in the server’s own settings, for Jukebox alone: it can be taken back there without changing your password.")
                .font(.footnote)
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
            .disabled(trimmedAPIKey.isEmpty)
            .accessibilityLabel(isSigningIn ? Text("Signing In") : Text("Sign In"))
            .padding(.top, Theme.Space.s)

            if let apiKeyHelp {
                Button {
                    openURL(apiKeyHelp)
                } label: {
                    Text("How to Make a Key")
                }
                .buttonStyle(.secondary)
            }
            Button {
                usesAPIKey = false
                errorMessage = nil
            } label: {
                Text("Use a Password Instead")
            }
            .buttonStyle(.secondary)
            .disabled(isSigningIn)
        }
    }

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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: Theme.Space.s) {
                        ProgressView()
                        Text("Waiting…")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                } else {
                    ProgressView()
                    Text("Asking \(server.name) for a code…")
                        .font(.subheadline)
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
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.secondary)
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
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private static func signInMessage(for error: Error) -> String {
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

    private static func apiKeyMessage(for error: Error) -> String {
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

// MARK: - Parts

/// The mark coming on, the name in the serif, and what Jukebox is for: a
/// fact, not a slogan.
private struct OnboardingWelcome: View {
    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ShellAppMark(side: 112, animatesIn: true)
            VStack(spacing: Theme.Space.s) {
                Text("Jukebox")
                    .font(.serif(.largeTitle))
                    .accessibilityAddTraits(.isHeader)
                Text("Music from your Jellyfin, Navidrome or other Subsonic server.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Fields on the page's ground, a hairline above and below them, as a
/// form's rows without its card.
private struct OnboardingFields<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
            Divider()
        }
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

    var body: some View {
        Label {
            Text(verbatim: message)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
