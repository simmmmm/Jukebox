// Covers and artist photos from the server, at the size they are drawn, held
// in memory by URL and on disk by CoverKey: the server, the path and the
// picture's id, tag and size, never the session's credentials (a Subsonic
// cover's address carries `u`, `t` and `s`, a Plex one its token). Jellyfin's
// image URLs carry the image's tag, so a cached one is never stale and
// scrolling back never refetches; a Subsonic server's carry the coverArt id
// (Navidrome's has the image's hash in it).

import JukeboxKit
import SwiftUI

@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, PlatformImage>()
    private let session: URLSession
    /// The covers on disk, by CoverKey, in a folder of their own.
    private let disk: URLCache
    private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        // No cache of the session's own: it keeps an answer by its address.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: RedirectGuard.shared, delegateQueue: nil)
        disk = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20, directory: Self.folder)
        memory.countLimit = 500
        // Decoded bytes, not a count: a 900 px cover is 3.2 MB once prepared
        // for display, so 500 of them would be 1.6 GB. 256 MB is about 80.
        memory.totalCostLimit = 256 << 20
    }

    private static var folder: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("Jukebox/Covers", isDirectory: true)
    }

    /// Every cover on disk and in memory goes: at a sign-out, so nothing of
    /// an account's library stays behind it.
    /// ponytail: every account's covers, not the one's; they come back as
    /// they are shown.
    func removeAll() {
        memory.removeAllObjects()
        disk.removeAllCachedResponses()
        missing = []
        averages = [:]
        accents = [:]
    }

    /// Before this the covers were kept by their address, credentials and
    /// all, in the system's own cache (Library/Caches/<the bundle's id>):
    /// emptied once, at the first launch after, before anything of the app
    /// asks the network (JukeboxApp.init).
    static func forgetAddressKeyedCache() {
        let done = "coversKeptByCoverKey"
        guard !UserDefaults.standard.bool(forKey: done) else { return }
        // The files first, before anything opens them (URLCache.shared
        // keeps its database open once touched); then the caches asked to
        // empty what they hold, should a system keep it elsewhere.
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let id = Bundle.main.bundleIdentifier {
            let old = caches.appendingPathComponent(id, isDirectory: true)
            for name in ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"] {
                try? FileManager.default.removeItem(at: old.appendingPathComponent(name))
            }
        }
        URLCache.shared.removeAllCachedResponses()
        URLCache(memoryCapacity: 0, diskCapacity: 512 << 20).removeAllCachedResponses()
        UserDefaults.standard.set(true, forKey: done)
    }

    func cached(_ url: URL) -> PlatformImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Covers the server said it has not (an answer other than 200, or
    /// bytes that are no picture), this session: their album's title sleeve
    /// shows at once, not after asking again. A network that failed is not
    /// in it: that cover is asked again next time.
    private var missing: Set<URL> = []

    func isMissing(_ url: URL) -> Bool { missing.contains(url) }

    func image(for url: URL) async -> PlatformImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let session = self.session
        let disk = self.disk
        let key = URLRequest(url: CoverKey.of(url))
        let task = Task<PlatformImage?, Never> {
            let kept = await Task.detached(priority: .userInitiated) { disk.cachedResponse(for: key)?.data }.value
            if let kept, let image = PlatformImage(data: kept) { return await image.preparedForDisplay() }
            // A cover's address may carry the account's token: not over
            // plain http to a home address while away from that network.
            guard await Task.detached(operation: { PlainHTTPGuard.mayFetch(url) }).value,
                  let (data, response) = try? await session.data(from: url) else { return nil }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = PlatformImage(data: data) else {
                self.missing.insert(url)
                return nil
            }
            // Kept under the key with an answer made for it: the server's
            // own answer names the address.
            if let keyURL = key.url,
               let answer = HTTPURLResponse(url: keyURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) {
                disk.storeCachedResponse(CachedURLResponse(response: answer, data: data), for: key)
            }
            return await image.preparedForDisplay()
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL, cost: image.pixelCount * 4)
        }
        return image
    }

    // MARK: A cover's colour

    /// Each cover's average colour, by its URL: a station's art takes its
    /// room from its first cover (StationArtwork), and many tiles show one
    /// station. A few bytes each; a library's stations are a few hundred.
    private var averages: [URL: AverageColor] = [:]

    func cachedAverageColor(_ url: URL) -> AverageColor? {
        averages[url]
    }

    /// The average colour of the image at `url`, worked out once.
    func averageColor(for url: URL) async -> AverageColor? {
        if let known = averages[url] { return known }
        guard let image = await image(for: url), let average = Self.averageColor(of: image) else { return nil }
        averages[url] = average
        return average
    }

    /// The image drawn into 8 by 8 pixels, with high-quality interpolation,
    /// and those averaged: a cover's colour as the eye takes it in from
    /// across the room, not the colour of any one part of it.
    static func averageColor(of image: PlatformImage) -> AverageColor? {
        guard let pixels = Self.pixels(of: image, side: 8) else { return nil }
        // Premultiplied: a pixel's colour is already weighed by its alpha,
        // so the sums over the alphas' sum are the average of what shows.
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[i])
            green += Double(pixels[i + 1])
            blue += Double(pixels[i + 2])
            weight += Double(pixels[i + 3])
        }
        guard weight > 0 else { return nil }
        return AverageColor(red: red / weight, green: green / weight, blue: blue / weight)
    }

    /// Each cover's accent (CoverAccent), by its URL, nil for a cover with
    /// no colour of its own: Now Playing's, worked out once a song.
    private var accents: [URL: AccentColor?] = [:]

    /// Known, with nil for "no colour of its own"; nil outside when not
    /// worked out yet.
    func cachedAccent(_ url: URL) -> AccentColor?? {
        accents[url]
    }

    /// The accent of the cover at `url`, nil when it has no colour of its
    /// own (or did not load: then it is asked again next time).
    func accent(for url: URL) async -> AccentColor? {
        if let known = accents[url] { return known }
        guard let image = await image(for: url), let pixels = Self.pixels(of: image, side: CoverAccent.side) else {
            return nil
        }
        let found = CoverAccent.accent(rgba: pixels, width: CoverAccent.side, height: CoverAccent.side)
        // updateValue, not a subscript: `accents[url] = nil` would remove
        // the key rather than keep "no colour".
        accents.updateValue(found, forKey: url)
        return found
    }

    /// The image drawn into `side` by `side` pixels, RGBA, premultiplied,
    /// with high-quality interpolation (each pixel the mean of its patch).
    static func pixels(of image: PlatformImage, side: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            // Drawn by UIKit (or AppKit's image as Core Graphics' on the
            // Mac), whatever backs the image; upside down in Core Graphics'
            // coordinates, which neither an average nor a histogram minds.
            image.draw(into: context, rect: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Sizes rounded up to a few steps, so a cover drawn at 44 and at 48
    /// points is one download.
    static func bucket(_ pixels: Int) -> Int {
        for step in [120, 240, 400, 600, 900, 1200] where pixels <= step { return step }
        return 1600
    }
}

/// A square cover. `size` nil: as wide as offered.
struct ArtworkView: View {
    let artwork: Artwork?
    var size: CGFloat?
    var cornerRadius: CGFloat = Theme.Radius.artwork
    /// Shown while loading and when there is no image.
    var placeholder = "music.note"
    /// An album's words: with them, a cover the server has not is the
    /// album's title sleeve (TitleSleeve), not the note.
    var sleeve: TitleSleeve.Words?

    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var displayScale
    /// The last cover that came, with the url it came for: shown only
    /// while that is still the url asked, so a new song never wears the
    /// last one's cover while its own is on the way ("Ook verkeerde album
    /// art in dit geval", 22 November 2026).
    @State private var loaded: (url: URL, image: PlatformImage?)?
    /// The url the server had no cover for, once asked.
    @State private var missingURL: URL?

    init(_ artwork: Artwork?, size: CGFloat? = nil, cornerRadius: CGFloat = Theme.Radius.artwork,
         placeholder: String = "music.note", sleeve: TitleSleeve.Words? = nil) {
        self.artwork = artwork
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
        self.sleeve = sleeve
    }

    /// No artwork at all, or the server answered without one. While a
    /// cover is on its way, the quiet square, so covers do not flash a
    /// sleeve before they come.
    private func showsSleeve(_ url: URL?) -> Bool {
        guard sleeve != nil else { return false }
        if artwork == nil { return true }
        guard let url else { return false }
        return missingURL == url || ImagePipeline.shared.isMissing(url)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .overlay {
                // The current url's cover only: `loaded` can still be the
                // last one's for a moment after the artwork changes in place,
                // and then the quiet square shows, not the old cover.
                if let image = url.flatMap({ ImagePipeline.shared.cached($0) })
                    ?? (loaded?.url == url ? loaded?.image : nil) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let sleeve, showsSleeve(url) {
                    TitleSleeveFace(words: sleeve)
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: placeholder)
                            .font(.system(size: max(12, (size ?? 120) * 0.3)))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .task(id: url) {
                guard let url else { loaded = nil; return }
                let image = await ImagePipeline.shared.image(for: url)
                // Cancelled: the view has gone, or a newer url has its own
                // task. The download went on regardless (and is cached), but
                // this cover is not the one to show: written now, a slow old
                // cover would replace the new one.
                guard !Task.isCancelled else { return }
                loaded = (url, image)
                if image == nil, ImagePipeline.shared.isMissing(url) { missingURL = url }
            }
            .accessibilityHidden(true)
    }

    private var url: URL? {
        guard let artwork, let server = app.server else { return nil }
        let points = size ?? 300
        return server.artworkURL(artwork, maxPixelSize: ImagePipeline.bucket(Int(points * displayScale)))
    }
}

/// An album without a cover as a printed sleeve (TitleSleeve, the rule for
/// both platforms; Linux's is Draw.titleSleeve): its print's flat ground,
/// the title in New York, the artist under it in SF Pro, each line set at
/// TitleSleeve's baseline. Measured in the Canvas with the very fonts it
/// draws, at the side it is given.
struct TitleSleeveFace: View {
    let words: TitleSleeve.Words

    var body: some View {
        Canvas { context, size in
            let side = Double(min(size.width, size.height))
            let room = CGSize(width: 100_000, height: 100_000)
            func text(_ string: String, _ face: TitleSleeve.Face, _ points: Double) -> Text {
                Text(verbatim: string)
                    .font(.system(size: points, weight: .regular, design: face == .title ? .serif : .default))
            }
            let sleeve = TitleSleeve.layout(words, side: side) { string, face, points in
                Double(context.resolve(text(string, face, points)).measure(in: room).width)
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(rgb: sleeve.print.ground)))
            func line(_ string: String, _ face: TitleSleeve.Face, _ points: Double, baseline: Double, ink: UInt32) {
                var resolved = context.resolve(text(string, face, points))
                resolved.shading = .color(Color(rgb: ink))
                let measured = resolved.measure(in: room)
                let top = baseline - Double(resolved.firstBaseline(in: measured))
                context.draw(resolved, in: CGRect(x: sleeve.padding, y: top, width: Double(measured.width),
                                                  height: Double(measured.height)))
            }
            for (index, string) in sleeve.lines.enumerated() {
                line(string, .title, sleeve.titleSize, baseline: sleeve.lineBaseline(index), ink: sleeve.print.title)
            }
            if let artist = sleeve.artist {
                line(artist, .artist, sleeve.artistSize, baseline: sleeve.artistBaseline, ink: sleeve.print.artist)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An artist's photo in a circle, or their initials when the server has none.
struct ArtistAvatar: View {
    let artist: Artist
    var size: CGFloat?

    var body: some View {
        if artist.artwork != nil {
            ArtworkView(artist.artwork, size: size, cornerRadius: 0, placeholder: "music.mic")
                .clipShape(.circle)
        } else {
            Circle()
                .fill(.quaternary)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: size, height: size)
                .overlay {
                    Text(initials)
                        .font(.system(size: max(12, (size ?? 120) * 0.36), weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }

    private var initials: String {
        let words = artist.name.split(separator: " ").filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

/// Four covers in a square, for a mix or a playlist without its own image.
struct CollageArtwork: View {
    let artworks: [Artwork]
    var size: CGFloat?
    var cornerRadius: CGFloat = Theme.Radius.artwork

    var body: some View {
        Group {
            if artworks.count >= 4 {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ArtworkView(artworks[0], cornerRadius: 0)
                        ArtworkView(artworks[1], cornerRadius: 0)
                    }
                    GridRow {
                        ArtworkView(artworks[2], cornerRadius: 0)
                        ArtworkView(artworks[3], cornerRadius: 0)
                    }
                }
            } else {
                ArtworkView(artworks.first, cornerRadius: 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
