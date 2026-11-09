// Signing in to a Subsonic server (docs/SERVERS.md, "Signing in, and what
// the keychain keeps"):
//
// 1. A salt of 16 random hex digits, t = md5(password + salt), and a ping
//    with u, t and s. The pair is the session from then on, for every call
//    and in every image and stream URL — one salt, so the URLs stay the
//    same and the image cache keeps working (Navidrome accepts the same
//    salt on every call, measured; Feishin does the same). The password is
//    kept nowhere.
// 2. Error 40: the wrong user name or password.
// 3. Error 41 or 42 (the server keeps only a hash of the password, so it
//    cannot check a token; or this way is off): an API key, if the server
//    offers them (OpenSubsonic's `apiKeyAuthentication`), since a key can
//    be revoked and a password is often the person's everywhere; else the
//    password itself (`p=enc:`), but only over https or to the home
//    network, as it then goes with every request.
// 4. A server older than API 1.13.0 has no tokens: step 3 at once.

import Foundation

public struct SubsonicSignIn: ServerSignIn {
    public let server: DetectedServer
    let identity: ClientIdentity
    let transport: any HTTPTransport

    public init(server: DetectedServer, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.server = server
        self.identity = identity
        self.transport = transport
    }

    /// The server, with no credentials yet.
    var anonymous: SubsonicConnection {
        SubsonicConnection(baseURL: server.url, serverAPIVersion: server.apiVersion,
                           clientName: identity.clientName, transport: transport)
    }

    public func signIn(username: String, password: String) async throws -> ServerCredentials {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { throw MusicServerError.unauthorized }

        // Tokens came with API 1.13.0. A server that does not say its
        // version is asked anyway: the ping says.
        if server.apiVersion == nil || SubsonicConnection.atLeast(server.apiVersion, "1.13.0") {
            let salt = SubsonicConnection.makeSalt()
            let secret = ServerSecret.subsonicToken(token: SubsonicConnection.token(password: password, salt: salt),
                                                    salt: salt)
            let ping = try await anonymous.with(auth: SubsonicConnection.auth(secret, user: user)).answer("ping", timeout: 15)
            if ping.isOK { return try await session(secret, user: user, ping: ping) }
            guard let code = ping.error?.code, code == 41 || code == 42 else {
                throw SubsonicConnection.error(ping.error)
            }
            if server.capabilities.contains(.apiKeySignIn) {
                throw MusicServerError.needsAPIKey(helpURL: ping.error?.helpURL)
            }
        } else if server.capabilities.contains(.apiKeySignIn) {
            throw MusicServerError.needsAPIKey(helpURL: nil)
        }

        guard ServerAddress.mayCarryPassword(server.url) else { throw MusicServerError.passwordNeedsHTTPS }
        let secret = ServerSecret.subsonicPassword(password)
        let ping = try await anonymous.with(auth: SubsonicConnection.auth(secret, user: user)).answer("ping", timeout: 15)
        guard ping.isOK else { throw SubsonicConnection.error(ping.error) }
        return try await session(secret, user: user, ping: ping)
    }

    /// The signed-in session: who the server says it is now, and what it
    /// can do. getUser once, so a user who may not stream hears so now
    /// rather than at the first song (a server without getUser, or one that
    /// will not tell, is taken at its word).
    func session(_ secret: ServerSecret, user: String, ping: SubsonicBody) async throws -> ServerCredentials {
        let apiVersion = ping.version ?? server.apiVersion
        let connection = anonymous.with(auth: SubsonicConnection.auth(secret, user: user), serverAPIVersion: apiVersion)
        async let account = try? await connection.call("getUser", [URLQueryItem(name: "username", value: user)], timeout: 15)
        let openSubsonic = ping.openSubsonic == true
        let extensions = openSubsonic ? await connection.extensions() : []
        if await account?.user?.streamRole == false { throw MusicServerError.notAllowed }
        let kind = ping.type.map { ServerKind.subsonic(flavour: SubsonicFlavour(type: $0)) } ?? server.kind
        let capabilities = SubsonicConnection.capabilities(apiVersion: apiVersion, openSubsonic: openSubsonic,
                                                           extensions: extensions)
        return ServerCredentials(kind: kind, serverURL: server.url, serverID: server.id, serverName: server.name,
                                 serverVersion: ping.serverVersion ?? server.version, apiVersion: apiVersion,
                                 userID: user, userName: user, secret: secret,
                                 capabilities: capabilities.subtracting(ServerCapability.signingInOnly))
    }
}

/// A Subsonic server that lists `apiKeyAuthentication`: a key made in its
/// own settings instead of the password (`MusicServers.signIn(to:)` gives
/// this one then).
public struct SubsonicAPIKeySignIn: APIKeySignIn {
    let base: SubsonicSignIn

    public init(server: DetectedServer, identity: ClientIdentity,
                transport: any HTTPTransport = URLSessionTransport()) {
        base = SubsonicSignIn(server: server, identity: identity, transport: transport)
    }

    public var server: DetectedServer { base.server }

    public func signIn(username: String, password: String) async throws -> ServerCredentials {
        try await base.signIn(username: username, password: password)
    }

    /// A ping with `apiKey` and no `u` (with `u` the spec makes it error
    /// 43), then tokenInfo for whose key it is. A wrong key is 44:
    /// .unauthorized.
    public func signIn(apiKey: String) async throws -> ServerCredentials {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MusicServerError.unauthorized }
        let secret = ServerSecret.subsonicAPIKey(key)
        let connection = base.anonymous.with(auth: SubsonicConnection.auth(secret, user: ""))
        let ping = try await connection.answer("ping", timeout: 15)
        guard ping.isOK else { throw SubsonicConnection.error(ping.error) }
        let info = try await connection.call("tokenInfo", timeout: 15)
        guard let user = info.tokenInfo?.username, !user.isEmpty else {
            throw MusicServerError.decoding("tokenInfo names no user")
        }
        return try await base.session(secret, user: user, ping: ping)
    }
}
