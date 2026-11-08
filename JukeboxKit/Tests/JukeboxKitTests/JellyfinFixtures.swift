// Answers of the Jellyfin 12.4 test server (8 November 2026), trimmed to
// the fields Jukebox reads plus a few it must ignore, and a transport that
// answers for the server in the unit tests.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JukeboxKit

enum JellyfinFixtures {
    static let identity = ClientIdentity(clientName: "Jukebox", clientVersion: "1.0",
                                         deviceName: "Test iPhone", deviceID: "device-1")
    static let server = URL(string: "https://jf.example.com/jellyfin")!
    static let userID = "32c60d1fd64b4a7ca7da417c157fde48"
    static let token = "3f7f848c7c664fa2a82af149b66eb8a6"

    static func client(_ transport: JellyfinMockTransport, signedIn: Bool = true) -> JellyfinClient {
        JellyfinClient(serverURL: server, identity: identity,
                       accessToken: signedIn ? token : nil, userID: signedIn ? userID : nil,
                       transport: transport)
    }

    /// A track with a guest (ArtistItems differ from AlbumArtists), from
    /// GET /Items?IncludeItemTypes=Audio&Fields=Genres,DateCreated, with
    /// NormalizationGain, LastPlayedDate and PlaylistItemId added as 12.4
    /// sends them when they are there.
    static let track = #"""
    {
      "Name": "Blue Parade",
      "ServerId": "ab1b921a10354a07a7dfbbc2c8061335",
      "Id": "2c4a765f5c8d9b4907be5d835a82513c",
      "DateCreated": "2026-11-08T01:26:02.3483093Z",
      "HasLyrics": false,
      "Container": "mov,mp4,m4a,3gp,3g2,mj2",
      "PremiereDate": "2016-01-01T00:00:00.0000000Z",
      "ChannelId": null,
      "Genres": ["Hip-Hop", "Nederhop"],
      "RunTimeTicks": 60000000,
      "ProductionYear": 2016,
      "IndexNumber": 1,
      "ParentIndexNumber": 1,
      "IsFolder": false,
      "Type": "Audio",
      "GenreItems": [{"Name": "Hip-Hop", "Id": "7ae1b9fdfd37e9182e7921677fc7b5ac"}],
      "UserData": {
        "PlaybackPositionTicks": 0, "PlayCount": 3, "IsFavorite": true, "Played": true,
        "LastPlayedDate": "2026-11-08T01:49:18.4805246Z",
        "Key": "MC Polder-Iron Gardens-0001-0001Blue Parade", "ItemId": "2c4a765f5c8d9b4907be5d835a82513c"
      },
      "Artists": ["MC Polder", "Lyric Engine"],
      "ArtistItems": [
        {"Name": "MC Polder", "Id": "45c0fee6139602552d2167741735c07e"},
        {"Name": "Lyric Engine", "Id": "9462cf3929c2979a36a5e8bed4ee77cf"}
      ],
      "Album": "Iron Gardens",
      "AlbumId": "db819dd856243bb2ee6e34f20cebf984",
      "AlbumPrimaryImageTag": "b63e8160ef7d966248696c03c30e0626",
      "AlbumArtist": "MC Polder",
      "AlbumArtists": [{"Name": "MC Polder", "Id": "45c0fee6139602552d2167741735c07e"}],
      "ImageTags": {},
      "BackdropImageTags": [],
      "ImageBlurHashes": {"Primary": {"b63e8160ef7d966248696c03c30e0626": "e04zZKy,fQy,fQy"}},
      "NormalizationGain": -7.5,
      "PlaylistItemId": "2c4a765f5c8d9b4907be5d835a82513c",
      "LocationType": "FileSystem",
      "MediaType": "Audio"
    }
    """#

    /// GET /Items?IncludeItemTypes=MusicAlbum&Fields=Genres,DateCreated,ChildCount.
    static let album = #"""
    {
      "Name": "Dust Parades",
      "Id": "d69312c4d583d8619adbb036b73e79fe",
      "DateCreated": "2026-11-08T01:32:53.0234082Z",
      "PremiereDate": "2019-01-01T00:00:00.0000000Z",
      "Genres": ["Electronic; Techno"],
      "RunTimeTicks": 470000000,
      "ProductionYear": 2019,
      "IsFolder": true,
      "Type": "MusicAlbum",
      "UserData": {"PlaybackPositionTicks": 0, "PlayCount": 0, "IsFavorite": false, "Played": false},
      "ChildCount": 7,
      "Artists": ["Hexagon Lights", "Hexagon Lights; Low Orbit"],
      "ArtistItems": [
        {"Name": "Hexagon Lights", "Id": "6630c43097f3b47f81a35c0dd57fec0f"},
        {"Name": "Hexagon Lights; Low Orbit", "Id": "cda283e38d4686cbf7ddd6d88e7443cf"}
      ],
      "AlbumArtist": "Hexagon Lights",
      "AlbumArtists": [{"Name": "Hexagon Lights", "Id": "6630c43097f3b47f81a35c0dd57fec0f"}],
      "ImageTags": {"Primary": "a0afaf02c8097145cf98ab95ad6bb91e"},
      "LocationType": "FileSystem",
      "MediaType": "Unknown"
    }
    """#

    /// GET /Artists/AlbumArtists?Fields=Genres,Overview,ItemCounts.
    static let artist = #"""
    {
      "Name": "Amsterdam Strings",
      "Id": "67b37b6aab140ac9da5cb06c6a6db8e9",
      "Overview": "A string ensemble.",
      "Genres": ["Classical"],
      "RunTimeTicks": 1390000000,
      "Type": "MusicArtist",
      "UserData": {"PlayCount": 0, "IsFavorite": true, "Played": false},
      "ChildCount": 25,
      "SongCount": 22,
      "AlbumCount": 3,
      "ImageTags": {"Primary": "f00d"},
      "ImageBlurHashes": {},
      "MediaType": "Unknown"
    }
    """#

    /// GET /MusicGenres?Fields=ItemCounts.
    static let genre = #"""
    {
      "Name": "Classical", "Id": "5d98424b382b886304766be2851d2682", "Type": "MusicGenre",
      "ChildCount": 26, "ImageTags": {"Primary": "74cbd217f604ebcaa43c8022d81a14ca"},
      "SongCount": 22, "AlbumCount": 3, "ArtistCount": 1, "MovieCount": 0
    }
    """#

    /// GET /Items?IncludeItemTypes=Playlist&Fields=ChildCount,DateCreated.
    static let playlist = #"""
    {
      "Name": "jf-agent probe", "Id": "ef78e9ded245b898db79ee08250526b8",
      "ChildCount": 4, "RunTimeTicks": 280000000, "DateCreated": "2026-11-08T01:46:52.0000000Z",
      "ImageTags": {"Primary": "8e5f2179618b4a86790236cc3d8fa0f4"}, "MediaType": "Audio", "Type": "Playlist"
    }
    """#

    static func page(_ items: [String], total: Int? = nil, start: Int = 0) -> String {
        #"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(total ?? items.count),"StartIndex":\#(start)}"#
    }

    /// A minimal track, for paging tests.
    static func track(id: String, name: String) -> String {
        #"{"Id":"\#(id)","Name":"\#(name)","Type":"Audio","RunTimeTicks":50000000}"#
    }

    static let publicInfo = #"""
    {"LocalAddress":"http://172.18.0.2:8096","ServerName":"0548ac3b6612","Version":"12.4.0",
     "ProductName":"Jellyfin Server","OperatingSystem":"","Id":"ab1b921a10354a07a7dfbbc2c8061335",
     "StartupWizardCompleted":true}
    """#

    static let authResult = #"""
    {"User":{"Name":"test","ServerId":"ab1b921a10354a07a7dfbbc2c8061335","ServerName":null,
             "Id":"32c60d1fd64b4a7ca7da417c157fde48","HasPassword":true},
     "SessionInfo":{"PlayState":{"CanSeek":false},"Id":"72e788a439cdb43fa3c5a2d132d1441f",
                    "LastActivityDate":"2026-11-08T01:44:47.6738535Z","LastPlaybackCheckIn":"0001-01-01T00:00:00.0000000Z"},
     "AccessToken":"3f7f848c7c664fa2a82af149b66eb8a6","ServerId":"ab1b921a10354a07a7dfbbc2c8061335"}
    """#

    static let quickConnect = #"""
    {"Authenticated":false,"Secret":"7E53089B6931599088F77D07612D2FC68812A82FF172E7F23C170CCC6D39E670",
     "Code":"588758","DeviceId":"jukebox-jf-qc","DeviceName":"Linux","AppName":"JukeboxTests",
     "AppVersion":"1.0","DateAdded":"2026-11-08T01:45:43.8535613Z"}
    """#

    /// 12.4's 404, an RFC 9110 problem.
    static let notFound = #"""
    {"type":"https://tools.ietf.org/html/rfc9110#section-15.5.5","title":"Not Found","status":404,
     "traceId":"00-f40492b24b85b22e286bc9b61c9cd610-e3e3c705cda67e0f-00"}
    """#

    static let validationProblem = #"""
    {"type":"https://tools.ietf.org/html/rfc9110#section-15.5.1","title":"One or more validation errors occurred.",
     "status":400,"errors":{"itemId":["The value 'nonsense' is not valid."]},"traceId":"00-a8-bd-00"}
    """#
}

/// Answers requests in the tests instead of a server, and keeps them.
final class JellyfinMockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> HTTPResponse

    private let lock = NSLock()
    private var handler: Handler
    private var sent: [URLRequest] = []

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Every request answered with this status and body.
    convenience init(status: Int = 200, body: String) {
        self.init { _ in HTTPResponse(status: status, body: Data(body.utf8)) }
    }

    var requests: [URLRequest] {
        lock.withLock { sent }
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let handler = lock.withLock {
            sent.append(request)
            return self.handler
        }
        return try handler(request)
    }

    static func respond(_ status: Int, _ body: String = "") -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
}

extension URLRequest {
    /// The query of the request as name → value (the last one wins).
    var jellyfinQuery: [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items { result[item.name] = item.value ?? "" }
        return result
    }

    var jellyfinPath: String {
        url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath } ?? ""
    }

    var jellyfinBody: [String: Any] {
        guard let httpBody,
              let object = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] else { return [:] }
        return object
    }
}
