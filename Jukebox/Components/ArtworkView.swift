// Covers and artist photos from Jellyfin, at the size they are drawn, held
// in memory and on disk (URLCache): Jellyfin's image URLs carry the image's
// tag, so a cached one is never stale and scrolling back never refetches.

import JukeboxKit
import SwiftUI
import UIKit

@MainActor
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memory.countLimit = 500
        // Decoded bytes, not a count: a 900 px cover is 3.2 MB once prepared
        // for display, so 500 of them would be 1.6 GB. 256 MB is about 80.
        memory.totalCostLimit = 256 << 20
    }

    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let session = self.session
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let pixels = image.size.width * image.scale * image.size.height * image.scale
            memory.setObject(image, forKey: url as NSURL, cost: Int(pixels) * 4)
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
    static func averageColor(of image: UIImage) -> AverageColor? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .high
            // Drawn by UIKit, whatever backs the image; upside down in
            // Core Graphics' coordinates, which an average does not mind.
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else { return nil }
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

    @Environment(AppModel.self) private var app
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    init(_ artwork: Artwork?, size: CGFloat? = nil, cornerRadius: CGFloat = Theme.Radius.artwork,
         placeholder: String = "music.note") {
        self.artwork = artwork
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholder = placeholder
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .overlay {
                // The current url's cover first: `loaded` can still be the
                // last one's for a moment after the artwork changes in place.
                if let image = url.flatMap({ ImagePipeline.shared.cached($0) }) ?? loaded {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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
                loaded = image
            }
            .accessibilityHidden(true)
    }

    private var url: URL? {
        guard let artwork, let client = app.client else { return nil }
        let points = size ?? 300
        return client.imageURL(artwork, maxPixelSize: ImagePipeline.bucket(Int(points * displayScale)))
    }
}

/// An artist's photo in a circle, or their initials when Jellyfin has none.
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
