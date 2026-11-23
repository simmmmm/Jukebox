// Finding a Plex server and signing in to it (docs/SERVERS.md, "Plex").
//
// A Plex server has no user names or passwords of its own: its people are
// plex.tv accounts. So the way in is plex.tv's own, in the browser, where
// Plex asks for the password and never Jukebox (Plex's documented PIN flow,
// "Authenticating with Plex"):
//
// 1. POST https://plex.tv/api/v2/pins with strong=true: an id and a code.
// 2. The person signs in at https://app.plex.tv/auth#?clientID=…&code=…, in
//    the browser (ASWebAuthenticationSession on Apple, the default browser
//    on Linux), while the app asks GET /api/v2/pins/{id} every 2 s until it
//    carries the account's token.
// 3. GET /api/v2/resources: the servers the account may use, each with its
//    own token for this account and its addresses (local, remote, relay).
// 4. The best address that answers, its server token kept like any other
//    account's secret (`ServerSecret.plexToken`), and the plex.tv account's
//    id as the user's, so a sign-in again is the same account.
//
// Or, for a server reached without plex.tv: its address, and a token pasted
// where an API key goes (`APIKeySignIn`).
//
// The client's id (X-Plex-Client-Identifier) is the installation's own,
// ClientIdentity.deviceID, as Jellyfin's DeviceId is.
//
// Untested end to end: no plex.tv account was used to build this. The
// answers' shapes are Plex's documentation's (PlexSignInTests).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Signing in to a Plex server found at an address: a token pasted as an
/// API key. A user name and password are plex.tv's, never the server's,
/// so asked for them it says to use a key or plex.tv (`PlexAccount`).
public struct PlexSignIn: APIKeySignIn {
    public let server: DetectedServer
    let identity: ClientIdentity
    let transport: any HTTPTransport

    /// Plex's own page on finding a token (X-Plex-Token).
    public static let tokenHelp = URL(string: "https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/")!

    public init(server: DetectedServer, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.server = server
        self.identity = identity
        self.transport = transport
    }

    public func signIn(username: String, password: String) async throws -> ServerCredentials {
        throw MusicServerError.needsAPIKey(helpURL: Self.tokenHelp)
    }

    /// The token is tried on the library. Plex does not say whose token it
    /// is without plex.tv, so the user is named by the server's account
    /// (its owner, whose token this most often is) and kept apart by the
    /// token: the same token is the same account.
    public func signIn(apiKey: String) async throws -> ServerCredentials {
        let token = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw MusicServerError.unauthorized }
        let connection = PlexConnection(baseURL: server.url, token: token, identity: identity, transport: transport)
        _ = try await connection.container("/library/sections")
        let owner = try? PlexConnection.decode(PlexAccountAnswer.self, await connection.send("GET", "/myplex/account"))
        let name = owner?.account?.username ?? ""
        return ServerCredentials(kind: .plex, serverURL: server.url, serverID: server.id, serverName: server.name,
                                 serverVersion: server.version, userID: "token-" + MD5.hex(token).prefix(16),
                                 userName: name.isEmpty ? "Plex" : name, secret: .plexToken(token),
                                 capabilities: PlexServer.capabilities)
    }

    /// GET /identity, which every Plex server answers without a token:
    /// `{"MediaContainer": {"claimed": …, "machineIdentifier": …, "version":
    /// "1.43.5.11079-b3b13e506"}}` (measured). Its name is the root's
    /// friendlyName where the server shows it, else the host.
    static func probe(_ url: URL, identity: ClientIdentity,
                      transport: any HTTPTransport) async -> Result<DetectedServer, MusicServerError> {
        let connection = PlexConnection(baseURL: url, token: nil, identity: identity, transport: transport)
        do {
            let found = try await connection.container("/identity")
            guard let id = found.machineIdentifier, !id.isEmpty else { return .failure(.invalidServerAddress) }
            let name = (try? await connection.container("/"))?.friendlyName
            return .success(DetectedServer(kind: .plex, url: url, id: id,
                                           name: name ?? url.host ?? url.absoluteString,
                                           version: found.version ?? ""))
        } catch let error as MusicServerError {
            return .failure(error.isTransport ? error : .invalidServerAddress)
        } catch {
            return .failure(.transport(ConnectionProblem.describe(error)))
        }
    }
}

struct PlexAccountAnswer: Decodable {
    struct Account: Decodable { var username: String? }
    var account: Account?

    enum CodingKeys: String, CodingKey { case account = "MyPlex" }
}

// MARK: - plex.tv

/// A plex.tv account's sign-in, in the browser, and the servers it may use.
public struct PlexAccount: Sendable {
    let identity: ClientIdentity
    let transport: any HTTPTransport
    let site: URL

    public init(identity: ClientIdentity, transport: any HTTPTransport = URLSessionTransport(),
                site: URL = URL(string: "https://plex.tv")!) {
        self.identity = identity
        self.transport = transport
        self.site = site
    }

    /// A sign-in waiting in the browser.
    public struct PIN: Sendable, Hashable {
        public let id: Int
        public let code: String
        /// Where the person signs in: Plex's own page, with this app named.
        public let authURL: URL
    }

    /// A server the account may use.
    public struct Server: Sendable, Hashable, Identifiable {
        /// Its machineIdentifier, as /identity says it.
        public let id: String
        public let name: String
        public let version: String
        public let owned: Bool
        /// This account's token to it (the account's own for its own).
        let accessToken: String?
        /// Local first, then remote, then relayed, each in plex.tv's order.
        let addresses: [URL]
    }

    var plexTV: PlexConnection { PlexConnection(baseURL: site, token: nil, identity: identity, transport: transport) }

    /// POST /api/v2/pins?strong=true. `forwardURL` is where Plex's page goes
    /// once signed in (Apple's web sign-in closes on its scheme).
    public func start(forwardURL: URL? = nil) async throws -> PIN {
        let answer = try PlexConnection.decode(PlexPINAnswer.self, await plexTV.send("POST", "/api/v2/pins", [
            URLQueryItem(name: "strong", value: "true"),
        ]))
        guard let id = answer.id, let code = answer.code else { throw MusicServerError.decoding("PIN") }
        return PIN(id: id, code: code, authURL: Self.authURL(clientID: identity.deviceID, code: code,
                                                             product: identity.clientName, forwardURL: forwardURL))
    }

    /// https://app.plex.tv/auth#?clientID=…&code=…&context[device][product]=…
    static func authURL(clientID: String, code: String, product: String, forwardURL: URL?) -> URL {
        var query = [("clientID", clientID), ("code", code), ("context[device][product]", product)]
        if let forwardURL { query.append(("forwardUrl", forwardURL.absoluteString)) }
        let fragment = query.map { "\(JellyfinClient.escape($0.0))=\(JellyfinClient.escape($0.1))" }.joined(separator: "&")
        return URL(string: "https://app.plex.tv/auth#?" + fragment)!
    }

    /// The account's token, once the person has signed in in the browser:
    /// GET /api/v2/pins/{id} every 2 s. A PIN lives 30 minutes; after that
    /// plex.tv forgets it (`notFound`). Cancel the task to stop asking.
    public func token(for pin: PIN) async throws -> String {
        while true {
            let answer = try PlexConnection.decode(PlexPINAnswer.self, await plexTV.send("GET", "/api/v2/pins/\(pin.id)", [
                URLQueryItem(name: "code", value: pin.code),
            ], timeout: 15))
            if let token = answer.authToken, !token.isEmpty { return token }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// GET /api/v2/resources: the servers among the account's devices, its
    /// own first.
    public func servers(token: String) async throws -> [Server] {
        let connection = PlexConnection(baseURL: site, token: token, identity: identity, transport: transport)
        let resources = try PlexConnection.decode(SubsonicList<PlexResource>.self, await connection.send("GET", "/api/v2/resources", [
            URLQueryItem(name: "includeHttps", value: "1"), URLQueryItem(name: "includeRelay", value: "1"),
        ])).items
        return resources.compactMap(\.server).sorted { $0.owned && !$1.owned }
    }

    /// Signed in to one of `servers(token:)`: at its first address that
    /// answers, `preferring` the address the person typed, if any.
    public func signIn(to server: Server, accountToken: String, preferring typed: URL? = nil) async throws -> ServerCredentials {
        let token = server.accessToken ?? accountToken
        let addresses = (typed.map { [$0] } ?? []) + server.addresses.filter { $0 != typed }
        guard let url = await Self.firstAnswering(addresses, token: token, identity: identity, transport: transport) else {
            if addresses.contains(where: { !Self.mayAsk($0) }) {
                throw MusicServerError.transport(
                    "\(server.name) answers only at a plain http address away from home. Sign in at its https address, or at home.")
            }
            throw MusicServerError.transport("None of \(server.name)’s addresses answered.")
        }
        let account = PlexConnection(baseURL: site, token: accountToken, identity: identity, transport: transport)
        let user = try PlexConnection.decode(PlexUser.self, await account.send("GET", "/api/v2/user"))
        guard let id = user.id else { throw MusicServerError.decoding("user") }
        var credentials = ServerCredentials(kind: .plex, serverURL: url, serverID: server.id, serverName: server.name,
                                            serverVersion: server.version, userID: id,
                                            userName: user.username ?? user.title ?? "", secret: .plexToken(token),
                                            capabilities: PlexServer.capabilities)
        // All of them, in this order: the one that answers here may not
        // answer elsewhere (home's, away from home), so the account opens
        // at whichever answers then (PlexServer).
        credentials.addresses = addresses
        return credentials
    }

    /// Every address asked at once (5 s each); the first in order that
    /// answers /identity wins, so a home address beats the relay. Known
    /// as soon as every one before it has failed.
    static func firstAnswering(_ addresses: [URL], token: String, identity: ClientIdentity,
                               transport: any HTTPTransport) async -> URL? {
        let addresses = addresses.filter { mayAsk($0) }
        return await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, url) in addresses.enumerated() {
                group.addTask {
                    var request = URLRequest(url: PlexConnection(baseURL: url, token: token, identity: identity,
                                                                 transport: transport).url("/identity"))
                    request.timeoutInterval = 5
                    for (name, value) in PlexConnection.headers(identity, token: token) {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                    return (i, (try? await PlexConnection.send(request, transport)) != nil)
                }
            }
            var answers = [Bool?](repeating: nil, count: addresses.count)
            for await (i, ok) in group {
                answers[i] = ok
                if let first = answers.firstIndex(where: { $0 != false }), answers[first] == true {
                    group.cancelAll()
                    return addresses[first]
                }
            }
            return nil
        }
    }

    /// Whether an address of the server may be asked with the token: https
    /// and the home network always; plain http away from home only where
    /// someone said Sign In Anyway for it, never silently. Kept under the
    /// sign-in's own key for that question ("signIn.plainHTTPAccepted",
    /// PlainHTTPConsent on the sign-in's branch), so one answer holds for both.
    /// ponytail: read here by its key until that type is on main; then
    /// `PlainHTTPConsent().isAccepted`.
    static func mayAsk(_ url: URL, defaults: UserDefaults = .standard) -> Bool {
        ServerAddress.mayCarryPassword(url)
            || (defaults.stringArray(forKey: "signIn.plainHTTPAccepted") ?? []).contains(url.absoluteString)
    }
}

// MARK: - What plex.tv answers

/// /api/v2/pins: `{"id": 1234567890, "code": "…", "expiresIn": 1800,
/// "authToken": null, …}`; `authToken` a string once signed in.
struct PlexPINAnswer: Decodable {
    var id: Int?
    var code: String?
    var authToken: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        id = c.lenientInt(SubsonicKey("id"))
        code = c.lenientString(SubsonicKey("code"))
        authToken = c.lenientString(SubsonicKey("authToken"))
    }
}

/// /api/v2/user: `{"id": 1234, "uuid": "…", "username": "…", "title": "…", …}`.
struct PlexUser: Decodable {
    var id, username, title: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        id = c.lenientString(SubsonicKey("id"))
        username = c.lenientString(SubsonicKey("username"))
        title = c.lenientString(SubsonicKey("title"))
    }
}

/// One of /api/v2/resources' devices: `{"name", "product", "productVersion",
/// "clientIdentifier", "provides": "server", "owned", "accessToken",
/// "connections": [{"protocol", "address", "port", "uri", "local", "relay"}]}`.
struct PlexResource: Decodable {
    struct Connection: Decodable {
        var uri: String?
        var local: Bool
        var relay: Bool

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: SubsonicKey.self)
            uri = c.lenientString(SubsonicKey("uri"))
            local = c.lenientBool(SubsonicKey("local")) ?? false
            relay = c.lenientBool(SubsonicKey("relay")) ?? false
        }
    }

    var name, version, clientIdentifier, provides, accessToken: String?
    var owned: Bool
    var connections: [Connection]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: SubsonicKey.self)
        name = c.lenientString(SubsonicKey("name"))
        version = c.lenientString(SubsonicKey("productVersion"))
        clientIdentifier = c.lenientString(SubsonicKey("clientIdentifier"))
        provides = c.lenientString(SubsonicKey("provides"))
        accessToken = c.lenientString(SubsonicKey("accessToken"))
        owned = c.lenientBool(SubsonicKey("owned")) ?? false
        connections = c.lenientList(Connection.self, SubsonicKey("connections"))
    }

    var server: PlexAccount.Server? {
        guard let clientIdentifier, (provides ?? "").split(separator: ",").contains("server") else { return nil }
        func rank(_ connection: Connection) -> Int { connection.relay ? 2 : connection.local ? 0 : 1 }
        let addresses = ordered(rank).compactMap { $0.uri.flatMap(URL.init(string:)) }
        return PlexAccount.Server(id: clientIdentifier, name: name ?? clientIdentifier, version: version ?? "",
                                  owned: owned, accessToken: accessToken, addresses: addresses)
    }

    /// Stable: plex.tv's order kept within each rank.
    func ordered(_ rank: (Connection) -> Int) -> [Connection] {
        connections.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}
