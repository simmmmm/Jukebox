// Why a sign-in did not work, in the same words on every client, and the
// word the usage counts keep for it (docs/STATS.md, `sign_in_failed`).
// "volgens mij krijg je nu geen feedback waarom je login niet werkt?" (the
// photographer, 23 November 2026): every failure says what went wrong and
// what to try, in a sentence or two, "beknopt niet zo over uitleggerig".
//
// And the one question a sign-in may ask: plain http away from home
// ("This Server Isn't Secure"), with what was answered kept per address.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - The connection

/// What a request that reached no answer ran into, from URLError's code.
/// The kit's `.transport` errors carry `message` as their text, so the
/// sign-in screens and the counts can tell them apart again (`init?(message:)`).
public enum ConnectionProblem: String, CaseIterable, Sendable {
    case timedOut = "timed_out"
    case hostNotFound = "host_not_found"
    case cannotConnect = "cannot_connect"
    case offline
    case untrustedCertificate = "untrusted_certificate"
    case secureConnectionFailed = "tls_failed"
    /// Apple's App Transport Security refused plain http. Jukebox allows
    /// it (NSAllowsArbitraryLoads), so this is only kept apart in case.
    case insecureBlocked = "ats_blocked"

    public init?(_ error: Error) {
        guard let code = (error as? URLError)?.code else { return nil }
        switch code {
        case .timedOut: self = .timedOut
        case .cannotFindHost, .dnsLookupFailed: self = .hostNotFound
        case .cannotConnectToHost, .networkConnectionLost, .badServerResponse: self = .cannotConnect
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed: self = .offline
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            self = .untrustedCertificate
        case .secureConnectionFailed, .clientCertificateRejected, .clientCertificateRequired: self = .secureConnectionFailed
        case .appTransportSecurityRequiresSecureConnection: self = .insecureBlocked
        default: return nil
        }
    }

    public init?(message: String) {
        guard let found = Self.allCases.first(where: { $0.message == message }) else { return nil }
        self = found
    }

    public var message: String {
        switch self {
        case .timedOut: "The server took too long to answer. Check the address, or try again."
        case .hostNotFound: "No server has this name. Check the address for typos."
        case .cannotConnect: "Nothing answered at this address. Check the address and port, and that the server is on."
        case .offline: "This device is offline. Connect to the internet and try again."
        case .untrustedCertificate: "This server's certificate isn't trusted. Use an address with a valid certificate, such as one from Let's Encrypt."
        case .secureConnectionFailed: "A secure connection to the server failed. If it uses plain http, type http:// before the address."
        case .insecureBlocked: "This device blocked a plain http connection. Use the server's https:// address."
        }
    }

    /// The text of a `.transport` error for `error`: these words where the
    /// code is known, else the system's.
    static func describe(_ error: Error) -> String {
        Self(error)?.message ?? error.localizedDescription
    }
}

// MARK: - The failure

/// A sign-in that did not work: the words for the screen, the reason for
/// the counts.
public struct SignInFailure: Sendable, Equatable {
    /// Where the person was: the address (detection), the password, an API
    /// key or token, or Quick Connect.
    public enum Step: Sendable { case address, password, apiKey, quickConnect }

    public var reason: String
    public var message: String

    /// `address` is the first address tried (`MusicServers.candidateAddresses`),
    /// for the "type http://" hint when Jukebox guessed https.
    public init(_ error: Error, step: Step, address: URL? = nil) {
        let guessedHTTPS = step == .address && address?.scheme == "https"
        switch error as? MusicServerError {
        case let .transport(text)?:
            let problem = ConnectionProblem(message: text)
            reason = problem?.rawValue ?? "unreachable"
            switch problem {
            case nil where guessedHTTPS, .cannotConnect? where guessedHTTPS, .timedOut? where guessedHTTPS:
                message = "Nothing answered at this address. If your server uses plain http, type http:// before it."
            case let problem?: message = problem.message
            case nil: message = "Nothing answered at this address. Check it, and that the server is on."
            }
        case .invalidServerAddress?:
            reason = "not_a_server"
            message = "There's no music server at this address. If it's in a folder, such as /jellyfin, add that too."
        // Only detection makes these (ServerAddress.probeAsked): a server's
        // own 401 and 403 are .unauthorized and .notAllowed.
        case let .server(status, _)? where status == 401 || status == 403:
            reason = "behind_login"
            message = "Something in front of the server, such as a proxy's sign-in, turned Jukebox away. Use the server's own address."
        case .unauthorized?:
            switch step {
            case .quickConnect:
                // For Quick Connect the server says so when it is turned
                // off there, not of a password.
                reason = "quick_connect_off"
                message = "Quick Connect is turned off on this server. Sign in with your password instead."
            case .apiKey:
                reason = "wrong_password"
                message = "That key didn't work on this server."
            default:
                reason = "wrong_password"
                message = "That user name and password didn't work on this server."
            }
        case .needsAPIKey?:
            reason = "needs_api_key"
            message = "This server signs in with an API key. Make one in its settings, then paste it here."
        case .passwordNeedsHTTPS?:
            reason = "needs_https"
            message = "Not signed in: the connection isn't secure. Use the server's https:// address if it has one."
        case let .movedElsewhere(host)?:
            reason = "moved_elsewhere"
            message = "This address sends Jukebox on to \(host). If that is your server, type its address."
        case .passwordItself?:
            reason = "password_itself"
            message = "Not signed in: this server would get your password itself. Use an API key if it offers one."
        case .notAllowed?:
            reason = "not_allowed"
            message = "This server doesn't let this account play music."
        case .notFound? where step == .quickConnect:
            reason = "code_expired"
            message = "The code has expired. Use Quick Connect again for a new one."
        case let .server(status: 30, message: text)?:
            reason = "server_too_old"
            message = text ?? "This server is too old for Jukebox."
        case let .server(status, _)?:
            reason = "server_error"
            message = "The server answered with error \(status). Try again, or check the server."
        default:
            reason = "other"
            message = error.localizedDescription
        }
    }
}

// MARK: - Plain http away from home

/// The words of the question, the same on every client: Apple's alert and
/// GNOME's AdwAlertDialog. "hou de warning tekst wel beknopt" (the
/// photographer, 23 November 2026).
public enum InsecureServerWords {
    public static let title = "This Server Isn't Secure"
    public static let body = "Your password and what you play will be sent without encryption. Use an https address if you can."
    public static let cancel = "Cancel"
    public static let signInAnyway = "Sign In Anyway"
    /// On the account's card in Settings, for as long as it is kept.
    public static let note = "Not secure"
}

extension ServerCredentials {
    /// Whether any address the account is reached at is plain http to an
    /// address not of the home's shape (a Plex account's remote one too):
    /// its card says "Not secure" for as long as it is kept. Without a
    /// lookup, so a view may ask (`ServerAddress.isInsecureAnywhere`).
    public var isInsecure: Bool {
        ([serverURL] + addresses).contains(where: ServerAddress.isInsecureAnywhere)
    }
}

/// The question before a server is sent the password itself, with every
/// request, rather than a token made from it or a key: a Subsonic server
/// that keeps only a hash of it and offers no API keys. Asked over https
/// too, since a password is often the person's everywhere.
public enum PasswordItselfWords {
    public static let title = "This Server Gets Your Password"
    public static let body = "This server can't sign in with a token or an API key, so your password itself goes with every request."
    /// Added when the address is plain http.
    public static let unencrypted = "Without encryption, too."
    public static let cancel = "Cancel"
    public static let signInAnyway = "Sign In Anyway"

    public static func message(for url: URL) -> String {
        url.scheme?.lowercased() == "https" ? body : "\(body) \(unencrypted)"
    }
}

/// The addresses someone said Sign In Anyway for, kept so a sign-in there
/// again (after a sign-out, another user) does not ask again. Only plain
/// http away from home is ever asked about (`ServerAddress.isInsecure`).
public struct PlainHTTPConsent: Sendable {
    static let key = "signIn.plainHTTPAccepted"
    /// UserDefaults is not Sendable; only its own thread-safe calls are made.
    nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether this sign-in has to ask first: plain http away from home,
    /// not yet accepted. May resolve a name: not on the main thread.
    public func mustAsk(_ url: URL) -> Bool {
        !isAccepted(url) && ServerAddress.isInsecure(url)
    }

    public func isAccepted(_ url: URL) -> Bool {
        (defaults.stringArray(forKey: Self.key) ?? []).contains(url.absoluteString)
    }

    /// Whether an accepted address has `url`'s own origin (scheme, host
    /// and port): what the transport asks of each request it sends.
    public func isAcceptedOrigin(_ url: URL) -> Bool {
        (defaults.stringArray(forKey: Self.key) ?? []).contains { accepted in
            guard let accepted = URL(string: accepted) else { return false }
            return accepted.scheme?.lowercased() == url.scheme?.lowercased() && RedirectPolicy.sameOrigin(accepted, url)
        }
    }

    /// Sign In Anyway, for this address.
    public func accept(_ url: URL) {
        add(url, to: Self.key)
    }

    static let passwordKey = "signIn.passwordItselfAccepted"

    /// Whether Sign In Anyway was said to "This Server Gets Your Password"
    /// for this address (SubsonicSignIn's last way in).
    public func sendsPasswordItself(_ url: URL) -> Bool {
        (defaults.stringArray(forKey: Self.passwordKey) ?? []).contains(url.absoluteString)
    }

    public func acceptPasswordItself(_ url: URL) {
        add(url, to: Self.passwordKey)
    }

    private func add(_ url: URL, to key: String) {
        var accepted = defaults.stringArray(forKey: key) ?? []
        guard !accepted.contains(url.absoluteString) else { return }
        accepted.append(url.absoluteString)
        defaults.set(accepted, forKey: key)
    }
}
