// How JellyfinClient talks: the URL of a route, the Authorization header,
// one send for every request, Jellyfin's errors as JellyfinError, and the
// answers decoded. The public calls (JellyfinClient.swift) are built from
// these.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension JellyfinClient {
    // MARK: Fields asked for

    /// Not in the default answer on 12.4 (measured): Genres, DateCreated.
    /// Every other field a Track needs is there by default.
    static let trackFields = "Genres,DateCreated"
    static let albumFields = "Genres,DateCreated,ChildCount"
    /// ItemCounts gives SongCount and AlbumCount. It costs nothing that
    /// shows on 12.4: the 23 album artists in 18–19 ms with it, 17–23 ms
    /// without (3 runs each).
    static let artistFields = "Genres,Overview,ItemCounts"
    static let playlistFields = "ChildCount,DateCreated"
    static let genreFields = "ItemCounts"

    /// Only the Primary image's tag, not backdrops and the rest.
    static let imageQuery = [URLQueryItem(name: "EnableImageTypes", value: "Primary"),
                             URLQueryItem(name: "ImageTypeLimit", value: "1")]

    /// What AVPlayer plays as it is (Jellyfin's container|codec names).
    /// "mp4|…" for files Jellyfin reads as mp4 rather than m4a.
    static let directContainers = "mp3,aac,m4a|aac,m4a|alac,m4b|aac,mp4|aac,mp4|alac,flac,alac,wav,aiff"

    /// Ids per request when many go in the URL: 100 ids are 3.3 kB, well
    /// inside the 8 kB a reverse proxy (nginx's default) takes as a request
    /// line.
    static let idsPerRequest = 100

    // MARK: URLs

    /// The server's address with a route and a query. The query is encoded
    /// strictly (only A–Z a–z 0–9 - . _ ~ stay as they are): URLComponents
    /// leaves "+" alone, which ASP.NET reads as a space, so a search for
    /// "R+B" would be a search for "R B".
    func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        var string = serverURL.absoluteString
        if let cut = string.firstIndex(where: { $0 == "?" || $0 == "#" }) { string = String(string[..<cut]) }
        while string.hasSuffix("/") { string.removeLast() }
        string += path
        if !query.isEmpty {
            string += "?" + query.map { item in
                "\(Self.escape(item.name))=\(Self.escape(item.value ?? ""))"
            }.joined(separator: "&")
        }
        return URL(string: string) ?? serverURL
    }

    static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// One path segment (an id), escaped.
    static func segment(_ text: String) -> String { escape(text) }

    // MARK: The header

    /// `MediaBrowser Client="Jukebox", Device="…", DeviceId="…", Version="…", Token="…"`.
    /// Each value percent-encoded: the server decodes them (measured on 12.4:
    /// Device="Simon%E2%80%99s%20%22iPhone%22" is listed as Simon’s "iPhone"),
    /// and a quote or a curly apostrophe in a device name would otherwise
    /// break the header.
    var authorizationHeader: String {
        var parts = [
            "Client=\"\(Self.escape(identity.clientName))\"",
            "Device=\"\(Self.escape(identity.deviceName))\"",
            "DeviceId=\"\(Self.escape(identity.deviceID))\"",
            "Version=\"\(Self.escape(identity.clientVersion))\"",
        ]
        if let accessToken, !accessToken.isEmpty {
            parts.append("Token=\"\(Self.escape(accessToken))\"")
        }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    // MARK: Sending

    /// The signed-in user's id, or .notSignedIn.
    func requireUser() throws -> String {
        guard let userID, !userID.isEmpty, let accessToken, !accessToken.isEmpty else {
            throw JellyfinError.notSignedIn
        }
        return userID
    }

    func userQuery(_ userID: String) -> [URLQueryItem] {
        [URLQueryItem(name: "userId", value: userID)]
    }

    @discardableResult
    func send(_ method: String, _ path: String, query: [URLQueryItem] = [],
              json body: (any Encodable & Sendable)? = nil, timeout: TimeInterval = 30) async throws -> HTTPResponse {
        var request = URLRequest(url: url(path, query))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw JellyfinError.decoding("the request could not be written: \(error)")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as JellyfinError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            // A cancelled task's request: cancellation, not a network fault.
            throw CancellationError()
        } catch {
            throw JellyfinError.transport(error.localizedDescription)
        }
        try Self.check(response)
        return response
    }

    /// 2xx passes; 401 is .unauthorized, 404 .notFound, anything else
    /// .server with what the body says.
    static func check(_ response: HTTPResponse) throws {
        switch response.status {
        case 200..<300: return
        case 401: throw JellyfinError.unauthorized
        case 404: throw JellyfinError.notFound
        default: throw JellyfinError.server(status: response.status, message: message(from: response.body))
        }
    }

    /// What an error's body says, for a person. Jellyfin 12.4 sends RFC 9110
    /// problem details ({"title": …, "status": …, "detail"?: …, "errors"?: {field: [message]}})
    /// or plain text ("Error processing request.").
    static func message(from body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let detail = object["detail"] as? String, !detail.isEmpty { return detail }
            if let errors = object["errors"] as? [String: Any] {
                for key in errors.keys.sorted() {
                    if let list = errors[key] as? [String], let first = list.first, !first.isEmpty { return first }
                    if let one = errors[key] as? String, !one.isEmpty { return one }
                }
            }
            for key in ["Message", "message", "title", "Title"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
            }
            return nil
        }
        guard let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 500, !text.hasPrefix("<") else { return nil }
        return text
    }

    func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch let error as DecodingError {
            throw JellyfinError.decoding(Self.describe(error, as: T.self))
        } catch {
            throw JellyfinError.decoding("\(T.self): \(error.localizedDescription)")
        }
    }

    static func describe<T>(_ error: DecodingError, as type: T.Type) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return "\(T.self) at \(path(context)): \(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "\(T.self) at \(path(context)): no \(key.stringValue)"
        @unknown default:
            return "\(T.self)"
        }
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = [],
                           timeout: TimeInterval = 30) async throws -> T {
        try decode(T.self, from: try await send("GET", path, query: query, timeout: timeout))
    }

    /// The 10.9+ route, and on a 404 the 10.8 one. Only on a 404: any other
    /// error is the server's answer and is passed on as it is.
    @discardableResult
    func send(_ method: String, _ path: String, orOnNotFound legacyPath: String,
              query: [URLQueryItem] = [], legacyQuery: [URLQueryItem] = []) async throws -> HTTPResponse {
        do {
            return try await send(method, path, query: query)
        } catch JellyfinError.notFound {
            return try await send(method, legacyPath, query: legacyQuery)
        }
    }

    // MARK: Item lists

    func items(_ path: String, _ query: [URLQueryItem], timeout: TimeInterval = 30) async throws -> JellyfinItemsResult {
        try await get(JellyfinItemsResult.self, path, query: query, timeout: timeout)
    }

    /// SortBy and SortOrder: the first key in the direction asked, the
    /// tie-breakers always ascending (Jellyfin applies a single SortOrder to
    /// every key, which would sort equal years by name backwards).
    static func sortQuery(_ keys: [String], descending: Bool) -> [URLQueryItem] {
        guard !keys.isEmpty else { return [] }
        if keys == ["Random"] { return [URLQueryItem(name: "SortBy", value: "Random")] }
        let orders = keys.indices.map { $0 == 0 && descending ? "Descending" : "Ascending" }
        return [URLQueryItem(name: "SortBy", value: keys.joined(separator: ",")),
                URLQueryItem(name: "SortOrder", value: orders.joined(separator: ","))]
    }

    static func albumSortKeys(_ sort: SortOrder) -> [String] {
        switch sort {
        case .name: ["SortName"]
        case .artist: ["AlbumArtist", "SortName"]
        case .year: ["ProductionYear", "SortName"]
        case .dateAdded: ["DateCreated", "SortName"]
        case .datePlayed: ["DatePlayed", "SortName"]
        case .playCount: ["PlayCount", "SortName"]
        case .random: ["Random"]
        }
    }

    /// An album's order: disc, then track.
    static let albumOrder = ["ParentIndexNumber", "IndexNumber", "SortName"]

    static func trackSortKeys(_ sort: SortOrder) -> [String] {
        switch sort {
        case .name: ["SortName"]
        case .artist: ["Artist", "Album"] + albumOrder
        case .year: ["ProductionYear", "Album"] + albumOrder
        case .dateAdded: ["DateCreated", "SortName"]
        case .datePlayed: ["DatePlayed", "SortName"]
        case .playCount: ["PlayCount", "SortName"]
        case .random: ["Random"]
        }
    }

    static func paging(start: Int, limit: Int?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "StartIndex", value: String(max(0, start)))]
        if let limit { query.append(URLQueryItem(name: "Limit", value: String(max(0, limit)))) }
        return query
    }

    static func chunks<T>(_ list: [T], of size: Int) -> [[T]] {
        stride(from: 0, to: list.count, by: size).map { Array(list[$0..<min($0 + size, list.count)]) }
    }
}
