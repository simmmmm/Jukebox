// Signed out: the welcome, then signing in to a Jellyfin server in two steps
// — where the server is, then who is listening. The server is asked for its
// name first (it answers without a password), so a typing mistake in the
// address shows at once and the second step can say "Signing in to Tijmen's
// Music". Where the server offers Quick Connect, a code to type into another
// Jellyfin app that is signed in already saves typing a password on the phone.
//
// One card of fields on the grouped background, as Settings draws a Form,
// under the eclipse: the first thing anyone sees of Jukebox is Numa's mark.
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
                                OnboardingAccountForm(server: server, changeServer: { changeServer() })
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
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Step 1, the server

    private var serverForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Your Server")
                .padding(.horizontal, Theme.Space.l)
            OnboardingCard {
                TextField("Server Address", text: $address, prompt: Text(verbatim: "jellyfin.example.com"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isAddressFocused)
                    .onSubmit { connect() }
                    .padding(.horizontal, Theme.Space.l)
                    .frame(minHeight: 52)
            }
            Text("The address you open Jellyfin at in a browser, such as jellyfin.example.com or 192.168.1.10:8096.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Space.l)
            if let serverError {
                OnboardingErrorText(message: serverError)
                    .padding(.horizontal, Theme.Space.l)
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
        guard let url = JellyfinClient.normalize(serverAddress: typed) else {
            show(String(localized: "That is not a server address. Try one like jellyfin.example.com."))
            return
        }
        serverError = nil
        isConnecting = true
        isAddressFocused = false
        let client = app.client(for: url)
        Task {
            do {
                // Both at once: Quick Connect's answer is ready when the
                // server's name is, and the second step opens complete.
                async let offersQuickConnect = client.quickConnectEnabled()
                let info = try await client.publicInfo()
                let quickConnect = await offersQuickConnect
                OnboardingMemory.serverAddress = typed
                isConnecting = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    step = .account(OnboardingServer(url: url, info: info, offersQuickConnect: quickConnect))
                }
            } catch {
                isConnecting = false
                show(Self.message(for: error, at: url))
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
        switch error as? JellyfinError {
        case .invalidServerAddress?:
            return String(localized: "There is no Jellyfin server at this address.")
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

/// The server that answered, and what it offers.
private struct OnboardingServer: Equatable {
    let url: URL
    let info: ServerInfo
    let offersQuickConnect: Bool
}

private enum OnboardingStep: Equatable {
    case server
    case account(OnboardingServer)
}

private struct OnboardingAccountForm: View {
    let server: OnboardingServer
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
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case username
        case password
    }

    init(server: OnboardingServer, changeServer: @escaping () -> Void) {
        self.server = server
        self.changeServer = changeServer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            if isQuickConnecting {
                quickConnectPanel
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

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Signing in to \(server.info.name)")
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

    /// "Jellyfin 10.10.7 · music.example.com"
    private var serverDetail: String {
        var parts: [String] = []
        if !server.info.version.isEmpty { parts.append("Jellyfin \(server.info.version)") }
        parts.append(server.url.host() ?? server.url.absoluteString)
        return parts.joined(separator: " · ")
    }

    // MARK: User name and password

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Eyebrow("Account")
                .padding(.horizontal, Theme.Space.l)
            OnboardingCard {
                TextField("User Name", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .username)
                    .onSubmit { focus = .password }
                    .padding(.horizontal, Theme.Space.l)
                    .frame(minHeight: 52)
                Divider()
                    .padding(.leading, Theme.Space.l)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { signIn() }
                    .padding(.horizontal, Theme.Space.l)
                    .frame(minHeight: 52)
            }
            if let errorMessage {
                OnboardingErrorText(message: errorMessage)
                    .padding(.horizontal, Theme.Space.l)
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

            if server.offersQuickConnect {
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
                    .padding(.horizontal, Theme.Space.l)
            }
        }
    }

    private func signIn() {
        guard !isSigningIn, !isQuickConnecting else { return }
        let name = trimmedUsername
        guard !name.isEmpty else { return }
        let password = self.password
        let client = app.client(for: server.url)
        errorMessage = nil
        isSigningIn = true
        focus = nil
        // Not tied to this view: once signed in the app swaps this screen
        // for the library while `signIn` is still loading it.
        Task {
            do {
                let credentials = try await client.signIn(username: name, password: password)
                OnboardingMemory.userName = name
                await app.signIn(credentials)
            } catch {
                isSigningIn = false
                show(Self.signInMessage(for: error))
            }
        }
    }

    // MARK: Quick Connect

    private var quickConnectPanel: some View {
        VStack(spacing: Theme.Space.m) {
            VStack(spacing: Theme.Space.l) {
                Eyebrow("Quick Connect")
                if let code = quickConnectCode {
                    Text(code)
                        .font(.system(size: codeSize, weight: .bold, design: .rounded))
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
                    Text("Asking \(server.info.name) for a code…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.Radius.card))

            Button {
                cancelQuickConnect()
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.secondary)
        }
    }

    private func startQuickConnect() {
        guard !isQuickConnecting, !isSigningIn else { return }
        errorMessage = nil
        focus = nil
        let client = app.client(for: server.url)
        quickConnectTask = Task {
            do {
                var state = try await client.quickConnectStart()
                // Cancelled while the server answered: a newer attempt's
                // code may already be on screen.
                try Task.checkCancellation()
                quickConnectCode = state.code
                // The server says nothing by itself: ask until the code has
                // been entered elsewhere. Every 3 s is quick to notice and
                // gentle on the server for the few minutes a code lives.
                while !state.isAuthenticated {
                    try await Task.sleep(for: .seconds(3))
                    state = try await client.quickConnectState(secret: state.secret)
                }
                let credentials = try await client.signIn(quickConnectSecret: state.secret)
                // Cancel tapped in that last moment still means cancel.
                try Task.checkCancellation()
                // From here it is signing in, not waiting: nothing for Cancel
                // or this view's going away to stop.
                quickConnectTask = nil
                await app.signIn(credentials)
            } catch {
                // Cancelled: Cancel or Change Server already put the form back.
                guard !Task.isCancelled else { return }
                quickConnectTask = nil
                quickConnectCode = nil
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
        switch error as? JellyfinError {
        case .unauthorized?:
            return String(localized: "That user name and password did not work on this server.")
        default:
            return error.localizedDescription
        }
    }

    private static func quickConnectMessage(for error: Error) -> String {
        switch error as? JellyfinError {
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

/// The eclipse, the name, and what Jukebox is in one line.
private struct OnboardingWelcome: View {
    var body: some View {
        VStack(spacing: Theme.Space.l) {
            ShellAppMark(diameter: 80, animatesIn: true)
            VStack(spacing: Theme.Space.s) {
                Text("Jukebox")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your Jellyfin music, and a radio that knows it.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Fields on one rounded card, as a Form's inset grouped section.
private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.Radius.card))
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
