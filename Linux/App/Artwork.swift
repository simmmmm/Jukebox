// Covers: fetched once, kept on disk and in memory, shown at one of three
// sizes so a cover has few addresses (a server's image cache is by address
// too). The drawn ones — a mix's collage, a station's arch, Now Playing's
// sleeve — are Drawings.swift's, shown here.

import CAdw
import CGlue
import Foundation
import JukeboxKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A GdkTexture, to be handed between threads (it cannot change), holding
/// its own reference: whoever has a Texture keeps the picture alive. It was
/// a bare pointer, and a station's arch kept the covers it was waiting on
/// across awaits while ArtworkLoader let the oldest go: drawing them read
/// freed covers, and Linux Jukebox crashed on Your Station's Play (19
/// November 2026).
nonisolated final class Texture: @unchecked Sendable {
    let pointer: OpaquePointer

    /// Takes over a reference the caller owns (a texture just made).
    init(owning pointer: OpaquePointer) { self.pointer = pointer }

    deinit { g_object_unref(UnsafeMutableRawPointer(pointer)) }
}

final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private var memory: [URL: Texture] = [:]
    private var recent: [URL] = []
    private var loading: [URL: Task<Texture?, Never>] = [:]
    /// Covers the server said it has not (an answer other than 200, or
    /// bytes that are no picture), this session: their album gets its title
    /// sleeve at once, not after asking again. A network that failed is not
    /// in it: that cover is asked again next time.
    private var missing: Set<URL> = []
    private let folder: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = caches.appendingPathComponent("Jukebox/covers", isDirectory: true)
        // The folder before CoverKey, its files named from the addresses.
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("Jukebox/artwork", isDirectory: true))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func known(_ url: URL) -> Texture? { memory[url] }

    func isMissing(_ url: URL) -> Bool { missing.contains(url) }

    /// The cover's file on disk, once it has been fetched: what GNOME's
    /// media controls show (MPRIS), without the server's token in an address.
    func file(for url: URL) -> URL? {
        let file = fileURL(for: url)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// The cover's file on disk, fetched first if it is not there: the
    /// media controls' size may be one no screen has shown yet.
    func fetchFile(for url: URL) async -> URL? {
        let file = fileURL(for: url)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let written = await Task.detached(priority: .utility) { () -> Bool in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return (try? data.write(to: file, options: .atomic)) != nil
        }.value
        return written ? file : nil
    }

    /// Named by a number made of the cover's CoverKey, not of its address:
    /// a Subsonic server's holds the account's token, or its password, which
    /// a quick hash of it would let anyone with the file's name try for.
    private nonisolated func fileURL(for url: URL) -> URL {
        folder.appendingPathComponent(String(Self.stableHash(CoverKey.of(url).absoluteString), radix: 16))
    }

    /// Every cover goes, from memory and disk: at a sign-out (the iPhone's
    /// ImagePipeline.removeAll).
    func removeAll() {
        memory = [:]
        recent = []
        missing = []
        let files = FileManager.default
        for file in (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? files.removeItem(at: file)
        }
    }

    func texture(for url: URL) async -> Texture? {
        if let found = memory[url] { return found }
        if let task = loading[url] { return await task.value }
        let file = fileURL(for: url)
        // The texture, or none and whether the server has none.
        let fetch = Task.detached(priority: .utility) { () -> (Texture?, missing: Bool) in
            var data = try? Data(contentsOf: file)
            if data == nil {
                guard let (fetched, response) = try? await URLSession.shared.data(from: url) else { return (nil, false) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, true) }
                try? fetched.write(to: file, options: .atomic)
                data = fetched
            }
            guard let data else { return (nil, false) }
            // Decoded here, off the main thread.
            let bytes = data.withUnsafeBytes { g_bytes_new($0.baseAddress, gsize($0.count)) }
            defer { g_bytes_unref(bytes) }
            guard let texture = gdk_texture_new_from_bytes(bytes, nil) else {
                try? FileManager.default.removeItem(at: file)
                return (nil, true)
            }
            return (Texture(owning: texture), false)
        }
        let task = Task { () -> Texture? in
            let (texture, missing) = await fetch.value
            if missing { self.missing.insert(url) }
            return texture
        }
        loading[url] = task
        let texture = await task.value
        loading[url] = nil
        if let texture {
            memory[url] = texture
            recent.append(url)
            // ponytail: 400 covers in memory, oldest out; by bytes if a
            // library of large covers proves that too many.
            if recent.count > 400, let oldest = recent.first {
                recent.removeFirst()
                // A drawing still waiting on it keeps it (Texture).
                memory.removeValue(forKey: oldest)
            }
        }
        return texture
    }

    /// FNV-1a: the same number for the same address at every launch
    /// (Swift's own hash is seeded anew each time).
    private nonisolated static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return hash
    }
}

/// The server's size for a cover shown at `points`: three sizes, whatever
/// the screen — a row's, a tile's, the playing song's (twice the points,
/// for sharp screens).
func coverPixels(_ points: Double) -> Int {
    points <= 64 ? 128 : points <= 220 ? 440 : 880
}

/// A square cover of `size` points with the one radius, or a collage.
final class Art {
    let widget: Widget
    private let image: Widget
    /// The cover's address, or the collage's drawing. Not nil at first, so
    /// a first `show(nil)` puts up what stands in for none, not nothing.
    private var wanted: String? = ""
    private var size: Int32
    /// The collage shown, drawn again at a new size.
    private var collage: [Artwork]?
    /// The words for a sleeve when the cover is missing (TitleSleeve), and
    /// whether that sleeve is up, drawn again at a new size.
    private var sleeve: TitleSleeve.Words?
    private var showsSleeve = false
    /// The image has gone (its page was rebuilt) while a cover was on its
    /// way: nothing is left to show it in.
    private var isGone = false
    /// What stands in for no cover: a note, or a genre's guitar. Changed
    /// while it stands in (a chooser's row reused for another kind), at once.
    var emptyIcon = "folder-music-symbolic" {
        didSet {
            if emptyIcon != oldValue, gtk_widget_has_css_class(image, "artwork-empty") != 0 {
                gtk_image_set_from_icon_name(ptr(image), emptyIcon)
            }
        }
    }

    init(_ size: Int32) {
        self.size = size
        image = gtk_image_new()!
        gtk_image_set_pixel_size(ptr(image), size)
        // A bin clips its child to its rounded corners; an image alone
        // does not.
        widget = adw_bin_new()!
        adw_bin_set_child(ptr(widget), image)
        gtk_widget_set_overflow(widget, GTK_OVERFLOW_HIDDEN)
        widget.css("artwork").size(width: size, height: size).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
        on(image, "destroy") { [weak self] in self?.isGone = true }
    }

    /// The page's tile size changed (PageMeasure): the cover at the new
    /// size; a collage is drawn again for it.
    func resize(_ newSize: Int32) {
        guard newSize != size else { return }
        size = newSize
        widget.size(width: size, height: size)
        let empty = gtk_widget_has_css_class(image, "artwork-empty") != 0
        gtk_image_set_pixel_size(ptr(image), empty ? max(16, grid(size / 3)) : size)
        if let collage {
            wanted = nil
            show(collage: collage)
        } else if showsSleeve {
            showSleeve()
        }
    }

    /// The cover; with `sleeve`, when the server has none, a sleeve printed
    /// with the album's title and artist (TitleSleeve) in place of the note.
    func show(_ artwork: Artwork?, sleeve: TitleSleeve.Words? = nil) {
        collage = nil
        let url = artwork.flatMap { artwork in app.server?.artworkURL(artwork, maxPixelSize: coverPixels(Double(size))) }
        let wish = url?.absoluteString ?? sleeve.map { "sleeve \($0.key) \($0.title) \($0.artist)" }
        guard wish != wanted else { return }
        wanted = wish
        self.sleeve = sleeve
        guard let url else {
            if sleeve != nil { showSleeve() } else { placeholder() }
            return
        }
        if let known = ArtworkLoader.shared.known(url) {
            set(known)
            return
        }
        if sleeve != nil, ArtworkLoader.shared.isMissing(url) {
            showSleeve()
            return
        }
        placeholder()
        Task {
            let texture = await ArtworkLoader.shared.texture(for: url)
            // The row may show another album by now.
            guard !self.isGone, self.wanted == url.absoluteString else { return }
            if let texture {
                self.set(texture)
            } else if self.sleeve != nil, ArtworkLoader.shared.isMissing(url) {
                self.showSleeve()
            }
        }
    }

    /// The title sleeve at this size, drawn once and kept.
    private func showSleeve() {
        guard let words = sleeve else { return }
        let side = Double(size), scale = Screen.shared.scale, asked = wanted
        let key = "title sleeve \(size) \(words.key) \(words.title) \(words.artist)"
        if let done = DrawingCache.get(drawingKey(key, scale: scale)) { return set(done, sleeve: true) }
        placeholder()
        // Up already, as far as a new size goes: resize draws it again.
        showsSleeve = true
        Task {
            guard let drawing = await drawn(key, width: side, height: side, scale: scale, { cr, _ in
                Draw.titleSleeve(cr, side: side, words: words)
            }), !self.isGone, self.wanted == asked, Double(self.size) == side else { return }
            self.set(drawing, sleeve: true)
        }
    }

    /// Four covers two by two with no gap, as CollageArtwork: a mix, or a
    /// playlist without an image of its own. Fewer than four: the first.
    /// ponytail: drawn at the scale of the moment; a window moved to
    /// another screen keeps it until the tile is shown again.
    func show(collage artworks: [Artwork]) {
        let urls = artworks.prefix(4).compactMap { app.server?.artworkURL($0, maxPixelSize: coverPixels(Double(size) / 2)) }
        guard urls.count == 4 else {
            show(artworks.first)
            return
        }
        collage = artworks
        let scale = Screen.shared.scale
        let key = "collage \(size) " + urls.map(\.absoluteString).joined(separator: " ")
        guard key != wanted else { return }
        wanted = key
        if let done = DrawingCache.get(drawingKey(key, scale: scale)) {
            set(done)
            return
        }
        placeholder()
        let side = Double(size)
        Task {
            var covers: [Texture] = []
            for url in urls {
                if let texture = await ArtworkLoader.shared.texture(for: url) { covers.append(texture) }
            }
            guard covers.count == 4, !self.isGone, self.wanted == key,
                  let drawing = await drawn(key, width: side, height: side, scale: scale, covers: covers, { cr, covers in
                      Draw.collage(cr, side: side, covers: covers)
                  }),
                  !self.isGone, self.wanted == key else { return }
            self.set(drawing)
        }
    }

    private func set(_ texture: Texture, sleeve: Bool = false) {
        showsSleeve = sleeve
        gtk_widget_remove_css_class(image, "artwork-empty")
        gtk_image_set_pixel_size(ptr(image), size)
        gtk_image_set_from_paintable(ptr(image), texture.pointer)
    }

    private func placeholder() {
        showsSleeve = false
        gtk_image_set_from_icon_name(ptr(image), emptyIcon)
        gtk_image_set_pixel_size(ptr(image), max(16, grid(size / 3)))
        gtk_widget_add_css_class(image, "artwork-empty")
    }
}

/// A station's art, as the iPhone draws it (Draw.station): the arch, its
/// seed's music in the window — one cover, or four panes for an artist, a
/// genre, a decade, a playlist — the room in the first cover's colour; the
/// core for the stations of the listener's own taste. Lit only while it is
/// the station on the air (tells.md 1), as the iPhone decides it
/// (RadioController.stationOnAir): starting, or the player's queue is its,
/// paused too.
final class StationArt {
    let widget: Widget
    private let size: Int32
    private var station: Station?
    private var onAirID: String?
    private var scale = 1.0
    private var wanted: String?
    /// The drawing with its covers is up: the empty window, later, is not.
    private var shown: String?
    private var isGone = false

    init(_ size: Int32) {
        self.size = size
        widget = gtk_image_new()!
        gtk_image_set_pixel_size(ptr(widget), size)
        widget.size(width: size, height: size).align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_CENTER)
        on(widget, "destroy") { [weak self] in self?.isGone = true }
        observe(widget) { [weak self] in
            // Read first, so either change draws it again.
            let onAir = app.radio.stationOnAir(player: app.player)?.id
            let scale = Screen.shared.scale
            guard let self else { return }
            self.onAirID = onAir
            self.scale = scale
            self.render()
        }
    }

    func show(_ station: Station) {
        self.station = station
        render()
    }

    /// Four covers for a station made from taste: what it draws from. Your
    /// Station, what is played most; Loved, the favourite albums; Discovery,
    /// today's albums to explore. Empty for every other station.
    private static func ownCovers(_ station: Station) -> [Artwork] {
        let library = app.library
        let albums: [Album]
        switch station.seed {
        case .personal: albums = HomeShelves.mostPlayed(tracks: library.tracks, album: library.album(id:), minimumPlays: 1, limit: 4)
        case .favorites: albums = Array(library.favoriteAlbums.prefix(4))
        case .discovery: albums = HomeShelves.explore(albums: library.albums, day: HomeShelves.dayNumber(of: Date()), limit: 4)
        default: return []
        }
        return albums.compactMap(\.artwork)
    }

    private func render() {
        guard let station else { return }
        let side = Double(size), scale = scale
        let lit = onAirID == station.id
        // The stations made from taste alone (Your Station, Discovery,
        // Loved) show the music they draw from, not the mark's core: "de
        // muziek gaat voor" (the photographer, 14 November 2026). The core
        // stays only for a library with nothing to show yet.
        let own = Self.ownCovers(station)
        let core = own.isEmpty ? StationCore.of(station) : nil
        let artwork = own.isEmpty ? station.artwork : own
        let cut = StationArtCut.forSide(side)
        let panes: Bool
        switch station.seed {
        case .track, .album: panes = false
        default: panes = core == nil && cut != .small && artwork.count >= 4
        }
        // A pane's cover is 126 of the 300 units, a lone one the window's 264.
        let pixels = coverPixels(side * (panes ? 126 : 264) / 300)
        let artworks = core != nil ? [] : Array(artwork.prefix(panes ? 4 : 1))
        let urls = artworks.compactMap { app.server?.artworkURL($0, maxPixelSize: pixels) }
        let key = "station \(size) \(lit) \(core.map { "\($0)" } ?? "covers") \(panes) "
            + urls.map(\.absoluteString).joined(separator: " ")
        // `wanted` and `shown` name the drawing at its scale.
        let named = drawingKey(key, scale: scale)
        guard named != wanted else { return }
        wanted = named
        if let done = DrawingCache.get(named) {
            set(done, as: named)
            return
        }
        let draw: @Sendable (OpaquePointer, [Draw.Cover]) -> Void = { cr, covers in
            Draw.station(cr, side: side, scale: scale, covers: covers, core: core, panes: panes, lit: lit)
        }
        let known = urls.compactMap { ArtworkLoader.shared.known($0) }
        Task {
            var covers = known
            if known.count < urls.count {
                // The arch at once, its window empty until the covers come.
                if let waiting = await drawn(key + " waiting", width: side, height: side, scale: scale, draw),
                   self.wanted == named, self.shown != named {
                    self.set(waiting, as: nil)
                }
                covers = []
                for url in urls {
                    if let texture = await ArtworkLoader.shared.texture(for: url) { covers.append(texture) }
                }
            }
            guard !self.isGone, self.wanted == named,
                  let drawing = await drawn(key, width: side, height: side, scale: scale, covers: covers, draw),
                  self.wanted == named else { return }
            self.set(drawing, as: named)
        }
    }

    private func set(_ texture: Texture, as key: String?) {
        guard !isGone else { return }
        shown = key
        gtk_image_set_from_paintable(ptr(widget), texture.pointer)
    }
}

/// Now Playing's sleeve with its record half out, still (BRAND.md, "The
/// sleeve", "The record"; D1's still state: nothing turns): the cover as
/// printed card, the black record with the album's songs as bands and its
/// label. The whole record shows, as on the iPad sideways (SleeveLayout,
/// wide). The shadows fall past the box onto the page.
final class SleeveArt {
    /// Room around sleeve and record for their shadows, for a sleeve of 300:
    /// the widest falls 34 down and blurs by 35, the record's 30 by 30; past
    /// twice its blur a shadow is under a level in 255. Scaled with the side.
    private static let spill = (left: 72.0, top: 40.0, right: 72.0, bottom: 112.0)

    let widget: Widget
    /// The sleeve's side in points: Now Playing gives 0.62 of its room.
    private(set) var side: Double
    private var layout: SleeveLayout
    private var width: Double
    private var wanted: String?
    /// The drawing up now: `wanted` once it is drawn.
    private var shown: String?
    private var track: Track?
    private var isGone = false

    /// Drawn as last asked, at its size: Now Playing opens only then.
    var isReady: Bool { shown == wanted }

    init(side: Double) {
        self.side = side
        width = Self.width(side)
        layout = SleeveLayout(room: CGSize(width: width, height: side), wide: true, margin: 0)
        // In a narrow room it shrinks rather than push the window wider.
        widget = jb_drawing_new(Int32(width.rounded(.up)), Int32(side), Int32(min(side, 300)))!
        widget.align(horizontal: GTK_ALIGN_START, vertical: GTK_ALIGN_START)
        on(widget, "destroy") { [weak self] in self?.isGone = true }
    }

    /// The sleeve and the record half out past it, side by side.
    private static func width(_ side: Double) -> Double {
        side * (1 + Double(SleeveLayout.recordSide) / 2) + Double(SleeveLayout.recordBeyond)
    }

    /// Drawn again at `newSide`, not scaled: its fine lines stay sharp.
    func resize(_ newSide: Double) {
        guard newSide != side, !isGone else { return }
        side = newSide
        width = Self.width(side)
        layout = SleeveLayout(room: CGSize(width: width, height: side), wide: true, margin: 0)
        jb_drawing_resize(widget, Int32(width.rounded(.up)), Int32(side), Int32(min(side, 300)))
        wanted = nil
        show(track)
    }

    /// The playing song's: its album's cover, its disc's songs as bands, its
    /// album and artist on the label. Called in `observe`, so a new screen
    /// or appearance draws it again.
    func show(_ track: Track?) {
        self.track = track
        let scale = Screen.shared.scale
        // Black at 1.5, as on D2's land (SleeveCard's `strength`): the room
        // is always dark, and the sleeve is drawn ahead while the window
        // may still be light.
        let strength = 1.5
        guard let track else {
            wanted = nil
            shown = nil
            jb_drawing_set(widget, nil, 0, 0, 0, 0)
            return
        }
        let url = track.artwork.flatMap { app.server?.artworkURL($0, maxPixelSize: coverPixels(side)) }
        let songs = track.albumID.map { album in
            app.library.tracks(inAlbum: album).map { TurntableSong(id: $0.id, disc: $0.discNumber, length: $0.duration) }
        } ?? []
        let turn = TurntableSide.of(track.id, in: songs) ?? .alone
        let title = track.albumName ?? "", artist = track.albumArtist?.name ?? track.artistLine
        let label = title.isEmpty && artist.isEmpty ? nil : RecordLabel(title: title, artist: artist, disc: turn.disc)
        let key = "sleeve \(side) \(url?.absoluteString ?? "none") \(turn.bands) \(title) \(artist) \(turn.disc ?? 0) \(strength)"
        let named = drawingKey(key, scale: scale)
        guard named != wanted else { return }
        wanted = named
        let grow = side / 300
        let spill = (left: Self.spill.left * grow, top: Self.spill.top * grow, right: Self.spill.right * grow, bottom: Self.spill.bottom * grow)
        let layout = layout, bands = turn.bands
        let wide = width + spill.left + spill.right, high = side + spill.top + spill.bottom
        let set = { [weak self] (drawing: Texture) in
            guard let self, !self.isGone, self.wanted == named else { return }
            self.shown = named
            jb_drawing_set(self.widget, drawing.pointer, -spill.left, -spill.top, wide, high)
        }
        // Drawn before (the room opened on this song already): at once.
        if let done = DrawingCache.get(named) { return set(done) }
        Task {
            var covers: [Texture] = []
            if let url, let texture = await ArtworkLoader.shared.texture(for: url) { covers.append(texture) }
            // No cover on the server: the album's title sleeve, as on its
            // tile (TitleSleeve). A cover the network lost: Cabinet, as before.
            let missing = url.map { ArtworkLoader.shared.isMissing($0) } ?? true
            let words = missing ? TitleSleeve.Words(track: track) : nil
            guard self.wanted == named,
                  let drawing = await drawn(key, width: wide, height: high, scale: scale, covers: covers, { cr, covers in
                      Draw.sleeveAndRecord(cr, scale: scale, layout: layout, x: spill.left, y: spill.top, cover: covers.first,
                                           words: words, bands: bands, label: label, strength: strength)
                  }) else { return }
            set(drawing)
        }
    }
}
