// The library as it was when last loaded, kept on disk so the next launch
// shows it at once and the radio can start before the server has answered;
// LibraryStore then loads it fresh behind it.

import Foundation

public struct CachedLibrary: Codable, Sendable {
    /// Bump when the models change shape: an old cache is then ignored.
    public static let version = 1

    public var version: Int
    public var savedAt: Date
    public var tracks: [Track]
    public var albums: [Album]
    public var artists: [Artist]
    public var playlists: [Playlist]
    public var genres: [Genre]

    public init(savedAt: Date, tracks: [Track], albums: [Album], artists: [Artist],
                playlists: [Playlist], genres: [Genre]) {
        self.version = Self.version
        self.savedAt = savedAt
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
        self.playlists = playlists
        self.genres = genres
    }
}

public enum LibraryCache {
    /// One file per server and user.
    public static func url(in directory: URL, serverID: String, userID: String) -> URL {
        let safe = { (s: String) in String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init)) }
        return directory.appendingPathComponent("library-\(safe(serverID))-\(safe(userID)).json")
    }

    public static func load(from url: URL) -> CachedLibrary? {
        guard let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(CachedLibrary.self, from: data),
              library.version == CachedLibrary.version else { return nil }
        return library
    }

    public static func save(_ library: CachedLibrary, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(library).write(to: url, options: .atomic)
    }
}
