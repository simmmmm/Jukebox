// The brand's drawings on Linux: a station's art, the mark on its tile, a
// mix's collage, and Now Playing's sleeve with its record half out, drawn as
// the iPhone draws them (Components/StationArtwork.swift, ArchMark.swift,
// ArtworkView.swift's CollageArtwork, Settings/ShellAppMark.swift,
// NowPlaying/SleeveRecord.swift) from the same numbers (ArtMeasures.swift,
// TurntableMeasures.swift, both shared). The recipe, checked against the
// iPhone's screenshots, is build/design-round/drawings/spec.md and its
// prototypes, call for call: `cr.arc` there is `cairo_arc` here. Numbers
// that are only in those Swift views (the record's and sleeve's literals)
// are copied: change both together.
//
// Each drawing is made once, off the main thread, into a bitmap at the
// window's real scale, kept (DrawingCache), and shown as a texture: in a
// GtkImage for the squares, in a JbDrawing (Linux/CGlue/drawing.c) for the
// sleeve, whose shadows fall past its box onto the page, as on the iPhone.
// Covers come in as the GdkTextures ArtworkLoader keeps: gdk_texture_download
// writes cairo's own ARGB32.
//
// Still pictures only: the label does not turn and there is no land under
// the page yet. Whether the land turns is the photographer's call
// (build/WORKPLAN.md, "Waiting on him").

import CAdw
import CGlue
import Foundation
import JukeboxKit
import Observation

// MARK: - The screen

/// What the drawings are made for, read in `observe` so a change draws them
/// again. `scale`: the window's device pixels a point, fractional
/// (gdk_surface_get_scale, GTK 4.12), not GTK's rounded-up integer: a bitmap
/// drawn at 2 and shown at 1.5 smears its fine lines.
@Observable
final class Screen {
    static let shared = Screen()
    private(set) var scale = 1.0

    /// Once the window has its surface.
    static func follow(_ window: Widget) {
        guard let native = gtk_widget_get_native(window), let surface = gtk_native_get_surface(native) else { return }
        let read = {
            let scale = gdk_surface_get_scale(surface)
            if scale > 0, scale != shared.scale { shared.scale = scale }
        }
        read()
        on(surface, "notify::scale") { read() }
    }
}

// MARK: - Made once, kept

/// Drawings made, by what they depend on.
/// ponytail: one cache by bytes, 64 MB, oldest out (spec.md).
enum DrawingCache {
    private static var kept: [String: (texture: Texture, bytes: Int)] = [:]
    private static var order: [String] = []
    private static var total = 0

    static func get(_ key: String) -> Texture? {
        guard let found = kept[key] else { return nil }
        if let index = order.lastIndex(of: key) { order.remove(at: index) }
        order.append(key)
        return found.texture
    }

    /// The texture kept for `key`: this one, or the one drawn first.
    static func put(_ key: String, _ texture: Texture, bytes: Int) -> Texture {
        if let found = kept[key] { return found.texture }
        kept[key] = (texture, bytes)
        order.append(key)
        total += bytes
        while total > 64 << 20, order.count > 1 {
            let oldest = order.removeFirst()
            if let gone = kept.removeValue(forKey: oldest) { total -= gone.bytes }
        }
        return texture
    }
}

/// What a drawing is called in the cache: its own key and the scale.
func drawingKey(_ key: String, scale: Double) -> String { "\(key) @\(scale)" }

/// The drawing `key`, kept or made: `draw` runs off the main thread on a
/// bitmap of `width` by `height` points at `scale`, given `covers` as cairo
/// surfaces.
func drawn(_ key: String, width: Double, height: Double, scale: Double, covers: [Texture] = [],
           _ draw: @escaping @Sendable (OpaquePointer, [Draw.Cover]) -> Void) async -> Texture? {
    let key = drawingKey(key, scale: scale)
    if let found = DrawingCache.get(key) { return found }
    let made = await Task.detached(priority: .utility) {
        Draw.render(width: width, height: height, scale: scale, covers: covers, draw)
    }.value
    // Held here until the drawing is back: a cover ArtworkLoader let go
    // meanwhile is then freed on the main thread, not the drawing's.
    withExtendedLifetime(covers) {}
    guard let made else { return nil }
    return DrawingCache.put(key, made.texture, bytes: made.bytes)
}

// MARK: - The drawings

/// The drawings themselves, in cairo, in points. Off the main thread: each
/// call has its own surface and its own Pango layout.
nonisolated enum Draw {
    /// A cover as cairo has it, and its average colour.
    struct Cover {
        let surface: OpaquePointer
        let average: AverageColor
    }

    static let copper = Tokens.Arch.copper
    static let glow = Tokens.Arch.glow
    static let cabinet = Tokens.Arch.cabinet
    static let outerTube = Tokens.Arch.outerTube
    static let innerTube = Tokens.Arch.innerTube
    static let paper = Tokens.Arch.paper
    /// Titles as on sleeves (BRAND.md, "On Linux"); words in the system's sans.
    static let serif = "New York,Source Serif 4,Source Serif Pro,Noto Serif,DejaVu Serif"
    static let sans = "Adwaita Sans,Inter,Cantarell,sans-serif"

    /// A bitmap of `width` by `height` points at `scale`, `draw` on it, as a
    /// GdkMemoryTexture, and its size in bytes.
    static func render(width: Double, height: Double, scale: Double, covers: [Texture],
                       _ draw: (OpaquePointer, [Cover]) -> Void) -> (texture: Texture, bytes: Int)? {
        let wide = Int32((width * scale).rounded(.up)), high = Int32((height * scale).rounded(.up))
        guard wide > 0, high > 0, let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, wide, high) else { return nil }
        defer { cairo_surface_destroy(surface) }
        cairo_surface_set_device_scale(surface, scale, scale)
        var buffers: [UnsafeMutableRawPointer] = []
        var loaded: [Cover] = []
        for texture in covers {
            guard let (cover, buffer) = pixels(of: texture) else { continue }
            loaded.append(cover)
            buffers.append(buffer)
        }
        let cr = cairo_create(surface)!
        draw(cr, loaded)
        cairo_destroy(cr)
        for cover in loaded { cairo_surface_destroy(cover.surface) }
        for buffer in buffers { free(buffer) }
        cairo_surface_flush(surface)
        let stride = Int(cairo_image_surface_get_stride(surface))
        let bytes = g_bytes_new(cairo_image_surface_get_data(surface), gsize(stride * Int(high)))
        defer { g_bytes_unref(bytes) }
        // cairo's ARGB32 is premultiplied BGRA in memory on a little-endian machine.
        guard let texture = gdk_memory_texture_new(wide, high, GDK_MEMORY_B8G8R8A8_PREMULTIPLIED, bytes, gsize(stride))
        else { return nil }
        return (Texture(owning: texture), stride * Int(high))
    }

    /// A cover's pixels in a cairo surface (the buffer is the caller's to
    /// free once the surface is gone), with its average colour: the mean of
    /// every pixel, the same number as ImagePipeline's 8 by 8.
    private static func pixels(of texture: Texture) -> (Cover, UnsafeMutableRawPointer)? {
        let wide = gdk_texture_get_width(texture.pointer), high = gdk_texture_get_height(texture.pointer)
        let rowBytes = Int(wide) * 4
        guard wide > 0, high > 0, let buffer = malloc(rowBytes * Int(high)) else { return nil }
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        gdk_texture_download(texture.pointer, bytes, gsize(rowBytes))
        var blue = 0, green = 0, red = 0
        for i in stride(from: 0, to: rowBytes * Int(high), by: 4) {
            blue += Int(bytes[i])
            green += Int(bytes[i + 1])
            red += Int(bytes[i + 2])
        }
        let count = Double(wide) * Double(high) * 255
        let average = AverageColor(red: Double(red) / count, green: Double(green) / count, blue: Double(blue) / count)
        guard let surface = cairo_image_surface_create_for_data(bytes, CAIRO_FORMAT_ARGB32, wide, high, Int32(rowBytes)) else {
            free(buffer)
            return nil
        }
        return (Cover(surface: surface, average: average), buffer)
    }

    // MARK: Helpers

    static func color(_ cr: OpaquePointer, _ hex: UInt32, _ alpha: Double = 1) {
        cairo_set_source_rgba(cr, Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255,
                              Double(hex & 0xFF) / 255, alpha)
    }

    /// Color(hue:saturation:brightness:).
    static func color(_ cr: OpaquePointer, hue: Double, saturation: Double, brightness: Double) {
        let h = (hue - hue.rounded(.down)) * 6, sector = h.rounded(.down), f = h - sector
        let v = brightness, p = v * (1 - saturation), q = v * (1 - saturation * f), t = v * (1 - saturation * (1 - f))
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        cairo_set_source_rgb(cr, r, g, b)
    }

    static func roundedRect(_ cr: OpaquePointer, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) {
        cairo_new_sub_path(cr)
        cairo_arc(cr, x + w - r, y + r, r, -.pi / 2, 0)
        cairo_arc(cr, x + w - r, y + h - r, r, 0, .pi / 2)
        cairo_arc(cr, x + r, y + h - r, r, .pi / 2, .pi)
        cairo_arc(cr, x + r, y + r, r, .pi, 3 * .pi / 2)
        cairo_close_path(cr)
    }

    static func circles(_ cr: OpaquePointer, _ cx: Double, _ cy: Double, _ radii: [Double]) {
        for r in radii where r > 0 {
            cairo_new_sub_path(cr)
            cairo_arc(cr, cx, cy, r, 0, 2 * .pi)
        }
    }

    /// A cover scaled to fill a `side` square at (x, y), its middle shown.
    static func paint(_ cr: OpaquePointer, _ cover: Cover, x: Double, y: Double, side: Double) {
        let w = Double(cairo_image_surface_get_width(cover.surface)), h = Double(cairo_image_surface_get_height(cover.surface))
        let s = side / min(w, h)
        cairo_save(cr)
        cairo_rectangle(cr, x, y, side, side)
        cairo_clip(cr)
        cairo_translate(cr, x + side / 2, y + side / 2)
        cairo_scale(cr, s, s)
        cairo_set_source_surface(cr, cover.surface, -w / 2, -h / 2)
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD)
        cairo_paint(cr)
        cairo_restore(cr)
    }

    /// A surface blurred in place: a Gaussian of `sigma` device pixels.
    static func blur(_ surface: OpaquePointer, _ sigma: Double) {
        cairo_surface_flush(surface)
        jb_blur(cairo_image_surface_get_data(surface), cairo_image_surface_get_width(surface),
                cairo_image_surface_get_height(surface), cairo_image_surface_get_stride(surface), sigma)
        cairo_surface_mark_dirty(surface)
    }

    /// SwiftUI's `.shadow`: `shape` (a path at the origin, `w` by `h`)
    /// filled in `hex`, blurred by `radius` (a Gaussian's sigma, as SwiftUI's
    /// radius measures, spec.md) and laid on at `alpha`, moved by (dx, dy).
    static func shadow(_ cr: OpaquePointer, scale: Double, width w: Double, height h: Double,
                       shape: (OpaquePointer) -> Void, hex: UInt32, alpha: Double, radius: Double, dx: Double, dy: Double) {
        let pad = radius * 3 + 2
        guard let mask = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, Int32(((w + 2 * pad) * scale).rounded(.up)),
                                                    Int32(((h + 2 * pad) * scale).rounded(.up))) else { return }
        let m = cairo_create(mask)!
        cairo_scale(m, scale, scale)
        cairo_translate(m, pad, pad)
        shape(m)
        color(m, hex)
        cairo_fill(m)
        cairo_destroy(m)
        blur(mask, radius * scale)
        cairo_save(cr)
        cairo_translate(cr, dx - pad, dy - pad)
        cairo_scale(cr, 1 / scale, 1 / scale)
        cairo_set_source_surface(cr, mask, 0, 0)
        cairo_paint_with_alpha(cr, min(1, alpha))
        cairo_restore(cr)
        cairo_surface_destroy(mask)
    }

    // MARK: A station's art

    /// ArchLine: up the left leg, over the top, down the right, in the
    /// art's 300 units.
    private static func tube(_ cr: OpaquePointer, radius r: Double, spring: Double, leg: Double) {
        cairo_move_to(cr, 150 - r, leg)
        cairo_line_to(cr, 150 - r, spring)
        cairo_arc(cr, 150, spring, r, .pi, 2 * .pi)
        cairo_line_to(cr, 150 + r, leg)
    }

    private static func tubes(_ cr: OpaquePointer, _ cut: StationArtCut, outer: UInt32, inner: UInt32, width: Double) {
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_width(cr, width)
        for (r, hex) in [(Double(cut.outerRadius), outer), (Double(cut.innerRadius), inner)] {
            tube(cr, radius: r, spring: cut.spring, leg: cut.leg)
            color(cr, hex)
            cairo_stroke(cr)
        }
    }

    /// StationArtworkFace, `side` points square at the origin: the room, the
    /// one glow on air, the window (four panes, one cover, or the core), the
    /// tubes; clipped to the one radius. No covers and no core: the window
    /// empty, its covers on their way.
    static func station(_ cr: OpaquePointer, side: Double, scale: Double, covers: [Cover],
                        core: StationCore?, panes: Bool, lit: Bool) {
        let cut = StationArtCut.forSide(side)
        let u = side / 300
        cairo_save(cr)
        roundedRect(cr, 0, 0, side, side, 6)
        cairo_clip(cr)

        // The room: the first cover's colour darkened, else Cabinet.
        if core == nil, let first = covers.first {
            let room = StationRoom(first.average)
            color(cr, hue: room.hue, saturation: room.saturation, brightness: StationRoom.groundBrightness)
        } else {
            color(cr, cabinet)
        }
        cairo_paint(cr)

        cairo_save(cr)
        cairo_scale(cr, u, u)
        // The one glow, on the air only: the light the tubes throw on the room.
        if lit {
            let px = Int32((side * scale).rounded(.up))
            if let glow = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, px, px) {
                let g = cairo_create(glow)!
                cairo_scale(g, Double(px) / 300, Double(px) / 300)
                tubes(g, cut, outer: outerTube, inner: innerTube, width: cut.t * 2.2)
                cairo_destroy(g)
                blur(glow, 7 * u * scale)
                cairo_save(cr)
                cairo_scale(cr, 300 / Double(px), 300 / Double(px))
                cairo_set_source_surface(cr, glow, 0, 0)
                cairo_paint_with_alpha(cr, 0.42)
                cairo_restore(cr)
                cairo_surface_destroy(glow)
            }
        }

        // The window: a flat sill, straight sides, a half circle as wide as it.
        let wx = 150 - Double(cut.rw), wy = Double(cut.windowTop)
        let ww = Double(cut.rw) * 2, wh = Double(cut.base - cut.windowTop)
        cairo_save(cr)
        cairo_move_to(cr, wx, wy + wh)
        cairo_line_to(cr, wx, wy + ww / 2)
        cairo_arc(cr, wx + ww / 2, wy + ww / 2, ww / 2, .pi, 2 * .pi)
        cairo_line_to(cr, wx + ww, wy + wh)
        cairo_close_path(cr)
        cairo_clip(cr)
        if let core {
            color(cr, Tokens.Art.stationRoom)
            cairo_paint(cr)
            let rc = Double(cut.coreRadius)
            let height = Double(cut.base - cut.spring) + rc
            let top = Double(cut.base) - height
            roundedRect(cr, 150 - rc, top, rc * 2, height, rc)
            let colors = core.colors
            if lit {
                // On the air, the core's own light from its top to its foot.
                let gradient = cairo_pattern_create_linear(0, top, 0, top + height)!
                for (offset, hex) in [(0.0, colors.top), (1.0, colors.foot)] {
                    cairo_pattern_add_color_stop_rgb(gradient, offset, Double((hex >> 16) & 0xFF) / 255,
                                                     Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
                }
                cairo_set_source(cr, gradient)
                cairo_pattern_destroy(gradient)
            } else {
                color(cr, colors.flat)
            }
            cairo_fill(cr)
        } else if panes && covers.count >= 4 && cut != .small {
            // Four covers as panes, two by two, each square and cut to its
            // pane, its middle shown; the mullions the room, half dark.
            let gap = 3.0
            let pw = (ww - gap) / 2, ph = (wh - gap) / 2, s = max(pw, ph)
            cairo_set_source_rgba(cr, 0, 0, 0, 0.5)
            cairo_paint(cr)
            for (j, cover) in covers.prefix(4).enumerated() {
                let x = wx + Double(j % 2) * (pw + gap), y = wy + Double(j / 2) * (ph + gap)
                cairo_save(cr)
                cairo_rectangle(cr, x, y, pw, ph)
                cairo_clip(cr)
                paint(cr, cover, x: x + pw / 2 - s / 2, y: y + ph / 2 - s / 2, side: s)
                cairo_restore(cr)
            }
        } else if let first = covers.first {
            // One cover as tall as the window, its middle seen through it.
            paint(cr, first, x: 150 - wh / 2, y: wy, side: wh)
        } else {
            // An empty place, as a cover's is before it comes.
            cairo_set_source_rgba(cr, 1, 1, 1, 0.08)
            cairo_paint(cr)
        }
        cairo_restore(cr)

        // The tubes: Copper and Glow at half strength, so the covers lead;
        // their own oranges, in full, on the air.
        if lit {
            tubes(cr, cut, outer: outerTube, inner: innerTube, width: cut.t)
        } else {
            cairo_push_group(cr)
            tubes(cr, cut, outer: copper, inner: glow, width: cut.t)
            cairo_pop_group_to_source(cr)
            cairo_paint_with_alpha(cr, 0.55)
        }
        cairo_restore(cr)
        cairo_restore(cr)
    }

    // MARK: The mark

    /// ArchMarkFace, flat, `size` points square at the origin: the outer
    /// tube, the inner, the core, each its colour.
    static func mark(_ cr: OpaquePointer, size: Double, outer: UInt32, inner: UInt32, core: UInt32) {
        let cut = ArchCut.forSize(size)
        cairo_save(cr)
        cairo_scale(cr, size / 32, size / 32)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_width(cr, cut.stroke)
        for (r, hex) in [(Double(cut.outerRadius), outer), (Double(cut.innerRadius), inner)] {
            cairo_move_to(cr, 16 - r, cut.leg)
            cairo_line_to(cr, 16 - r, cut.spring)
            cairo_arc(cr, 16, cut.spring, r, .pi, 2 * .pi)
            cairo_line_to(cr, 16 + r, cut.leg)
            color(cr, hex)
            cairo_stroke(cr)
        }
        let rc = Double(cut.coreRadius)
        roundedRect(cr, 16 - rc, cut.spring - rc, 2 * rc, Double(cut.base - cut.spring) + rc, rc)
        color(cr, core)
        cairo_fill(cr)
        cairo_restore(cr)
    }

    /// ShellAppMark: the mark flat on Cabinet, at 0.7 of the tile and a
    /// little below its middle, with the night's core; the icon's corners
    /// (Apple's continuous curve; a plain radius on GNOME) and a hairline,
    /// white at 8%, as the tile is dark in either appearance.
    static func shellTile(_ cr: OpaquePointer, side: Double) {
        let radius = side * 0.2237
        roundedRect(cr, 0, 0, side, side, radius)
        color(cr, cabinet)
        cairo_fill(cr)
        let m = side * 0.7
        cairo_save(cr)
        cairo_translate(cr, (side - m) / 2, (side - m) / 2 + side * 12 / 1024)
        mark(cr, size: m, outer: copper, inner: glow, core: Tokens.Arch.markCore.dark)
        cairo_restore(cr)
        roundedRect(cr, 0.25, 0.25, side - 0.5, side - 0.5, radius - 0.25)
        cairo_set_source_rgba(cr, 1, 1, 1, 0.08)
        cairo_set_line_width(cr, 0.5)
        cairo_stroke(cr)
    }

    /// The welcome's picture, the Mac's WelcomeSleeve at rest: the mark on
    /// its Cabinet sleeve, the record half out with its Copper label, in
    /// units of a 300th of `width` (the sleeve 180 square at (20, 10), the
    /// record 172 across, its centre at (208, 100)); `width` by two thirds
    /// of it. One welcome on every client ("Los ze op", 20 November 2026).
    static func welcomeSleeve(_ cr: OpaquePointer, scale: Double, width: Double) {
        let u = width / 300
        record(cr, scale: scale, center: (208 * u, 100 * u), diameter: 172 * u, bands: [],
               label: RecordLabel(title: "Jukebox", artist: "", disc: nil),
               tone: AverageColor(red: 0xA8 / 255, green: 0x4A / 255, blue: 0x17 / 255), strength: 1)
        let side = 180 * u, m = side * 0.7
        cairo_save(cr)
        cairo_translate(cr, 20 * u, 10 * u)
        sleeve(cr, scale: scale, side: side, cover: nil, words: nil, strength: 1)
        cairo_translate(cr, (side - m) / 2, (side - m) / 2 + side * 12 / 1024)
        mark(cr, size: m, outer: copper, inner: glow, core: Tokens.Arch.markCore.dark)
        cairo_restore(cr)
    }

    /// One of the welcome's two pictures for its build-up (SignInPage),
    /// drawn once as welcomeSleeve draws it, `room` round it: the record
    /// alone, or the sleeve's card alone, without its mark, which the
    /// build-up draws as it comes on (welcomeMark).
    static func welcomeLayer(scale: Double, width: Double, room: Double, record isRecord: Bool) -> OpaquePointer? {
        let u = width / 300
        let wide = Int32(((width + 2 * room) * scale).rounded(.up)), high = Int32(((width * 2 / 3 + 2 * room) * scale).rounded(.up))
        guard let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, wide, high) else { return nil }
        cairo_surface_set_device_scale(surface, scale, scale)
        let cr = cairo_create(surface)!
        cairo_translate(cr, room, room)
        if isRecord {
            record(cr, scale: scale, center: (208 * u, 100 * u), diameter: 172 * u, bands: [],
                   label: RecordLabel(title: "Jukebox", artist: "", disc: nil),
                   tone: AverageColor(red: 0xA8 / 255, green: 0x4A / 255, blue: 0x17 / 255), strength: 1)
        } else {
            cairo_translate(cr, 20 * u, 10 * u)
            sleeve(cr, scale: scale, side: 180 * u, cover: nil, words: nil, strength: 1)
        }
        cairo_destroy(cr)
        return surface
    }

    /// The welcome's mark as the Mac's WelcomeSleeve builds it up, on the
    /// sleeve's place (`width` as welcomeSleeve's): each band drawn up its
    /// left leg, over the top and down the right as far as `outer` and
    /// `inner` (0 to 1, ArchLine's trim), the core on at `core`, its colour
    /// from `pageCore` (on the page alone) to the sleeve's at `onSleeve`.
    static func welcomeMark(_ cr: OpaquePointer, width: Double, outer: Double, inner: Double, core: Double,
                            pageCore: UInt32, onSleeve: Double) {
        let u = width / 300, side = 180 * u, size = side * 0.7
        let cut = ArchCut.forSize(size)
        cairo_save(cr)
        cairo_translate(cr, 20 * u + (side - size) / 2, 10 * u + (side - size) / 2 + side * 12 / 1024)
        cairo_scale(cr, size / 32, size / 32)
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        cairo_set_line_width(cr, cut.stroke)
        for (r, hex, drawn) in [(Double(cut.outerRadius), copper, outer), (Double(cut.innerRadius), glow, inner)] where drawn > 0 {
            let leg = Double(cut.leg - cut.spring), arc = Double.pi * r
            var left = drawn * (2 * leg + arc)
            cairo_move_to(cr, 16 - r, Double(cut.leg))
            cairo_line_to(cr, 16 - r, Double(cut.leg) - min(left, leg))
            left -= leg
            if left > 0 { cairo_arc(cr, 16, Double(cut.spring), r, .pi, .pi + min(left, arc) / r) }
            left -= arc
            if left > 0 { cairo_line_to(cr, 16 + r, Double(cut.spring) + min(left, leg)) }
            color(cr, hex)
            cairo_stroke(cr)
        }
        if core > 0 {
            let rc = Double(cut.coreRadius)
            for (hex, alpha) in [(pageCore, core), (Tokens.Arch.markCore.dark, core * onSleeve)] where alpha > 0 {
                roundedRect(cr, 16 - rc, Double(cut.spring) - rc, 2 * rc, Double(cut.base - cut.spring) + rc, rc)
                color(cr, hex, alpha)
                cairo_fill(cr)
            }
        }
        cairo_restore(cr)
    }

    // MARK: The collage

    /// CollageArtwork: four covers two by two with no gap; fewer, the first.
    /// The radius is the image's place's (`.artwork`).
    static func collage(_ cr: OpaquePointer, side: Double, covers: [Cover]) {
        guard covers.count >= 4 else {
            if let first = covers.first { paint(cr, first, x: 0, y: 0, side: side) }
            return
        }
        let half = side / 2
        for (j, cover) in covers.prefix(4).enumerated() {
            paint(cr, cover, x: Double(j % 2) * half, y: Double(j / 2) * half, side: half)
        }
    }

    // MARK: The title sleeve

    /// An album without a cover, as a printed sleeve (TitleSleeve, the rule
    /// for both platforms; the iPhone's TitleSleeveFace): its print's flat
    /// ground, the title in the serif, the artist under it in the sans, each
    /// line set at TitleSleeve's baseline. Measured here with Pango as it is
    /// drawn, unhinted, as the record's label.
    static func titleSleeve(_ cr: OpaquePointer, side: Double, words: TitleSleeve.Words) {
        let layout = pango_cairo_create_layout(cr)!
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        let options = cairo_font_options_create()
        cairo_font_options_set_hint_metrics(options, CAIRO_HINT_METRICS_OFF)
        cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_NONE)
        pango_cairo_context_set_font_options(pango_layout_get_context(layout), options)
        cairo_font_options_destroy(options)
        pango_layout_context_changed(layout)
        let description = pango_font_description_new()
        defer { pango_font_description_free(description) }
        pango_font_description_set_weight(description, PANGO_WEIGHT_NORMAL)
        let unit = Double(PANGO_SCALE)
        func set(_ text: String, _ face: TitleSleeve.Face, _ size: Double) {
            pango_font_description_set_family(description, face == .title ? serif : sans)
            pango_font_description_set_absolute_size(description, size * unit)
            pango_layout_set_font_description(layout, description)
            pango_layout_set_text(layout, text, -1)
        }
        let sleeve = TitleSleeve.layout(words, side: side) { text, face, size in
            set(text, face, size)
            var logical = PangoRectangle()
            pango_layout_get_extents(layout, nil, &logical)
            return Double(logical.width) / unit
        }
        color(cr, sleeve.print.ground)
        cairo_paint(cr)
        func line(_ text: String, _ face: TitleSleeve.Face, _ size: Double, baseline: Double, ink: UInt32) {
            set(text, face, size)
            cairo_move_to(cr, sleeve.padding, baseline - Double(pango_layout_get_baseline(layout)) / unit)
            color(cr, ink)
            pango_cairo_show_layout(cr, layout)
        }
        for (index, text) in sleeve.lines.enumerated() {
            line(text, .title, sleeve.titleSize, baseline: sleeve.lineBaseline(index), ink: sleeve.print.title)
        }
        if let artist = sleeve.artist {
            line(artist, .artist, sleeve.artistSize, baseline: sleeve.artistBaseline, ink: sleeve.print.artist)
        }
    }

    // MARK: The sleeve and its record

    /// Now Playing's sleeve and record where `layout` puts them, from the
    /// bitmap's (x, y): the record, its shadows and its sheen, then the
    /// sleeve over it with its own. Shadows black at `strength` (1.5 on D2's
    /// dark land). No cover: the album's title sleeve, from `words`.
    static func sleeveAndRecord(_ cr: OpaquePointer, scale: Double, layout: SleeveLayout, x: Double, y: Double,
                                cover: Cover?, words: TitleSleeve.Words? = nil, bands: [Double], label: RecordLabel?,
                                strength: Double) {
        cairo_save(cr)
        cairo_translate(cr, x, y)
        record(cr, scale: scale, center: (layout.recordCenter.x, layout.recordCenter.y), diameter: layout.recordDiameter,
               bands: bands, label: label, tone: cover?.average, strength: strength)
        cairo_translate(cr, layout.sleeve.minX, layout.sleeve.minY)
        sleeve(cr, scale: scale, side: layout.sleeve.width, cover: cover, words: words, strength: strength)
        cairo_restore(cr)
    }

    /// How much of the card's record shows beside its art, of the art's side.
    static let cardRecordPeek = 0.14

    /// The record peeking from behind a card of Home's art (the iPhone's
    /// HomeCardRecord): Now Playing's, small and still, 0.92 of the art,
    /// its label Copper; drawn from the art's left edge, the art over it.
    static func cardRecord(_ cr: OpaquePointer, side: Double) {
        let d = side * 0.92, R = d / 2
        cairo_save(cr)
        cairo_translate(cr, side * (1 + cardRecordPeek) - d, (side - d) / 2)
        recordBody(cr, diameter: d, bands: [])
        let lr = R * 0.33
        cairo_translate(cr, R - lr, R - lr)
        recordLabel(cr, radius: lr, label: nil, tone: AverageColor(red: 0xA8 / 255, green: 0x4A / 255, blue: 0x17 / 255),
                    hole: max(1.6, R * 0.016))
        cairo_restore(cr)
    }

    /// VinylShadow, VinylDisc (its label still), VinylSheen.
    private static func record(_ cr: OpaquePointer, scale: Double, center: (Double, Double), diameter d: Double,
                               bands: [Double], label: RecordLabel?, tone: AverageColor?, strength: Double) {
        let R = d / 2
        let x0 = center.0 - R, y0 = center.1 - R
        // The disc three times, each with its own shadow.
        for (alpha, radius, dy) in [(0.40, 1.5, 2.0), (0.32, 14, 14), (0.16, 30, 30)] {
            shadow(cr, scale: scale, width: d, height: d, shape: { cairo_arc($0, R, R, R, 0, 2 * .pi) },
                   hex: 0x000000, alpha: alpha * strength, radius: radius, dx: x0, dy: y0 + dy)
            cairo_arc(cr, center.0, center.1, R, 0, 2 * .pi)
            color(cr, Tokens.Art.vinyl)
            cairo_fill(cr)
        }
        cairo_save(cr)
        cairo_translate(cr, x0, y0)
        recordBody(cr, diameter: d, bands: bands)
        let lr = R * 0.33
        cairo_translate(cr, R - lr, R - lr)
        recordLabel(cr, radius: lr, label: label, tone: tone, hole: max(1.6, R * 0.016))
        cairo_restore(cr)
        sheen(cr, cx: center.0, cy: center.1, R: R)
    }

    /// Everything of the record but its label: concentric, so turning it
    /// would change no pixel.
    private static func recordBody(_ cr: OpaquePointer, diameter d: Double, bands: [Double]) {
        let R = d / 2, c = R
        let outer = R * 0.955, inner = R * 0.40
        cairo_arc(cr, c, c, R, 0, 2 * .pi)
        color(cr, Tokens.Art.vinyl)
        cairo_fill(cr)
        // The lead-in at the rim.
        cairo_arc(cr, c, c, R * 0.985, 0, 2 * .pi)
        cairo_set_source_rgba(cr, 1, 1, 1, 0.07)
        cairo_set_line_width(cr, R * 0.02)
        cairo_stroke(cr)
        // The grooves, every third a little stronger.
        let step = max(1.1, d / 240)
        var weak: [Double] = [], strong: [Double] = []
        var r = outer, k = 0
        while r > inner {
            if k % 3 == 0 { strong.append(r) } else { weak.append(r) }
            r -= step
            k += 1
        }
        for (radii, alpha) in [(weak, 0.045), (strong, 0.075)] {
            circles(cr, c, c, radii)
            cairo_set_source_rgba(cr, 1, 1, 1, alpha)
            cairo_set_line_width(cr, 0.5)
            cairo_stroke(cr)
        }
        // The songs' bands: smooth darker vinyl, a light edge.
        let width = max(2.2, R * 0.022)
        let radii = bands.map { outer - (outer - inner) * $0 }
        circles(cr, c, c, radii)
        color(cr, Tokens.Art.land)
        cairo_set_line_width(cr, width)
        cairo_stroke(cr)
        circles(cr, c, c, radii.map { $0 + width / 2 })
        cairo_set_source_rgba(cr, 1, 1, 1, 0.16)
        cairo_set_line_width(cr, 0.6)
        cairo_stroke(cr)
        // The run-out, and its fine ring.
        cairo_arc(cr, c, c, inner, 0, 2 * .pi)
        color(cr, Tokens.Art.runOut)
        cairo_fill(cr)
        cairo_arc(cr, c, c, R * 0.37, 0, 2 * .pi)
        cairo_set_source_rgba(cr, 1, 1, 1, 0.06)
        cairo_set_line_width(cr, 0.6)
        cairo_stroke(cr)
    }

    /// VinylLabelFace about (lr, lr): the cover's colour, a fine ring, the
    /// album and its artist in paper white, the hole.
    private static func recordLabel(_ cr: OpaquePointer, radius lr: Double, label: RecordLabel?, tone: AverageColor?, hole: Double) {
        if let tone {
            let hsb = tone.hueSaturationBrightness
            color(cr, hue: hsb.hue, saturation: min(hsb.saturation, 0.45), brightness: 0.3)
        } else {
            color(cr, Tokens.Art.blankLabel)
        }
        cairo_arc(cr, lr, lr, lr, 0, 2 * .pi)
        cairo_fill(cr)
        cairo_arc(cr, lr, lr, lr * 0.92, 0, 2 * .pi)
        color(cr, paper, 0.28)
        cairo_set_line_width(cr, 0.6)
        cairo_stroke(cr)
        if lr >= 10, let label {
            let lines: [(String, String, Double, Double, Double, Double)] = [
                (label.title, serif, max(5.5, lr * 0.17), 0.65, 0.92, 1.3),
                (label.artist, sans, max(4.5, lr * 0.122), 1.38, 0.72, 1.3),
                (label.disc.map { "Disc \($0)" } ?? "", sans, max(4.5, lr * 0.122), 1.62, 0.55, 0.8),
            ]
            for (text, family, size, at, alpha, width) in lines where !text.isEmpty {
                let layout = fitted(cr, text, family: family, size: size, width: lr * width)
                var logical = PangoRectangle()
                pango_layout_get_extents(layout, nil, &logical)
                let scale = Double(PANGO_SCALE)
                cairo_move_to(cr, lr - Double(logical.width) / scale / 2 - Double(logical.x) / scale,
                              lr * at - Double(logical.height) / scale / 2 - Double(logical.y) / scale)
                color(cr, paper, alpha)
                pango_cairo_show_layout(cr, layout)
                g_object_unref(UnsafeMutableRawPointer(layout))
            }
        }
        cairo_arc(cr, lr, lr, hole, 0, 2 * .pi)
        color(cr, Tokens.Art.hole)
        cairo_fill(cr)
    }

    /// One line, as the label's Text: smaller to 0.6 of its size, then cut
    /// short. Unhinted, with fractional metrics: at 5 points hinting eats
    /// the spaces (spec.md, zoom-label.png).
    private static func fitted(_ cr: OpaquePointer, _ text: String, family: String, size: Double, width: Double) -> OpaquePointer {
        let layout = pango_cairo_create_layout(cr)!
        let options = cairo_font_options_create()
        cairo_font_options_set_hint_metrics(options, CAIRO_HINT_METRICS_OFF)
        cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_NONE)
        pango_cairo_context_set_font_options(pango_layout_get_context(layout), options)
        cairo_font_options_destroy(options)
        pango_layout_context_changed(layout)
        let description = pango_font_description_new()
        defer { pango_font_description_free(description) }
        pango_font_description_set_family(description, family)
        pango_font_description_set_weight(description, PANGO_WEIGHT_NORMAL)
        pango_layout_set_text(layout, text, -1)
        for k in [1, 0.9, 0.8, 0.7, 0.6] {
            pango_font_description_set_absolute_size(description, size * k * Double(PANGO_SCALE))
            pango_layout_set_font_description(layout, description)
            var logical = PangoRectangle()
            pango_layout_get_extents(layout, nil, &logical)
            if Double(logical.width) / Double(PANGO_SCALE) <= width { return layout }
        }
        pango_layout_set_width(layout, Int32(width * Double(PANGO_SCALE)))
        pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END)
        return layout
    }

    /// VinylSheen: a ring from 0.34 R to R lit by two soft wedges, half a
    /// turn apart, that never turn. A mesh of one-degree wedges, as cairo
    /// has no conic gradient.
    private static func sheen(_ cr: OpaquePointer, cx: Double, cy: Double, R: Double) {
        let stops: [(Double, Double)] = [(0, 0), (14, 0.12), (30, 0), (180, 0), (194, 0.09), (210, 0), (360, 0)]
        func alpha(_ degrees: Double) -> Double {
            for (a, b) in zip(stops, stops.dropFirst()) where a.0 <= degrees && degrees <= b.0 {
                return a.1 + (b.1 - a.1) * (degrees - a.0) / (b.0 - a.0)
            }
            return 0
        }
        let mesh = cairo_pattern_create_mesh()!
        for step in 0..<360 {
            let degrees = Double(step)
            if alpha(degrees) == 0 && alpha(degrees + 1) == 0 { continue }
            let a0 = (degrees - 118) * .pi / 180, a1 = (degrees - 117) * .pi / 180
            cairo_mesh_pattern_begin_patch(mesh)
            cairo_mesh_pattern_move_to(mesh, cx + 0.34 * R * cos(a0), cy + 0.34 * R * sin(a0))
            cairo_mesh_pattern_line_to(mesh, cx + R * cos(a0), cy + R * sin(a0))
            cairo_mesh_pattern_line_to(mesh, cx + R * cos(a1), cy + R * sin(a1))
            cairo_mesh_pattern_line_to(mesh, cx + 0.34 * R * cos(a1), cy + 0.34 * R * sin(a1))
            for (corner, at) in [(0, degrees), (1, degrees), (2, degrees + 1), (3, degrees + 1)] {
                cairo_mesh_pattern_set_corner_color_rgba(mesh, UInt32(corner), 1, 244.0 / 255, 228.0 / 255, alpha(at))
            }
            cairo_mesh_pattern_end_patch(mesh)
        }
        cairo_save(cr)
        cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
        circles(cr, cx, cy, [R, 0.34 * R])
        cairo_clip(cr)
        cairo_set_source(cr, mesh)
        cairo_paint(cr)
        cairo_restore(cr)
        cairo_pattern_destroy(mesh)
    }

    /// SleeveCard at the origin: its thickness with four shadows, then the
    /// printed face.
    private static func sleeve(_ cr: OpaquePointer, scale: Double, side: Double, cover: Cover?, words: TitleSleeve.Words?,
                               strength: Double) {
        // The card's edge: the cover's colour with 45% black.
        let edge = cover.map { ($0.average.red * 0.55, $0.average.green * 0.55, $0.average.blue * 0.55) }
        let card: (OpaquePointer) -> Void = { roundedRect($0, 0, 0, side, side, 6) }
        cairo_save(cr)
        cairo_translate(cr, 0.6, 2.6)
        for (alpha, radius, dx, dy) in [(0.45, 1.0, 0.0, 1.0), (0.34, 13, 0, 12), (0.22, 35, 0, 34), (0.10, 7, -6, 0)] {
            shadow(cr, scale: scale, width: side, height: side, shape: card, hex: 0x000000,
                   alpha: alpha * strength, radius: radius, dx: dx, dy: dy)
            card(cr)
            if let edge { cairo_set_source_rgb(cr, edge.0, edge.1, edge.2) } else { color(cr, Tokens.Art.sleeveEdge) }
            cairo_fill(cr)
        }
        cairo_restore(cr)

        cairo_save(cr)
        card(cr)
        cairo_clip(cr)
        if let cover {
            paint(cr, cover, x: 0, y: 0, side: side)
        } else if let words {
            titleSleeve(cr, side: side, words: words)
        } else {
            // No cover: Cabinet, as Now Playing has it (BRAND.md).
            color(cr, cabinet)
            cairo_paint(cr)
        }
        // Ring wear: the record's rim and label pressed into the card, white
        // at 4%, softened.
        let px = Int32((side * scale).rounded(.up))
        if let wear = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, px, px) {
            let w = cairo_create(wear)!
            cairo_scale(w, scale, scale)
            let cx = side / 2 - side * 0.01, cy = side / 2
            cairo_set_source_rgb(w, 1, 1, 1)
            cairo_arc(w, cx, cy, side * 0.458, 0, 2 * .pi)
            cairo_set_line_width(w, side * 0.014)
            cairo_stroke(w)
            cairo_set_source_rgba(w, 1, 1, 1, 0.6)
            cairo_arc(w, cx, cy, side * 0.165, 0, 2 * .pi)
            cairo_set_line_width(w, side * 0.006)
            cairo_stroke(w)
            cairo_destroy(w)
            blur(wear, side * 0.006 * scale)
            cairo_save(cr)
            cairo_scale(cr, 1 / scale, 1 / scale)
            cairo_set_source_surface(cr, wear, 0, 0)
            cairo_paint_with_alpha(cr, 0.04)
            cairo_restore(cr)
            cairo_surface_destroy(wear)
        }
        // Grain: SleeveGrain's tile at 2 pixels a point, repeated.
        let grainSide = Int32(SleeveGrain.side)
        if let tile = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, grainSide, grainSide) {
            cairo_surface_flush(tile)
            let bytes = SleeveGrain.bytes()
            let rowBytes = Int(cairo_image_surface_get_stride(tile))
            if let data = cairo_image_surface_get_data(tile) {
                for row in 0..<SleeveGrain.side {
                    for i in 0..<(SleeveGrain.side * 4) { data[row * rowBytes + i] = bytes[row * SleeveGrain.side * 4 + i] }
                }
            }
            cairo_surface_mark_dirty(tile)
            let pattern = cairo_pattern_create_for_surface(tile)!
            cairo_pattern_set_extend(pattern, CAIRO_EXTEND_REPEAT)
            cairo_pattern_set_filter(pattern, CAIRO_FILTER_NEAREST)
            var matrix = cairo_matrix_t()
            cairo_matrix_init_scale(&matrix, 2, 2)
            cairo_pattern_set_matrix(pattern, &matrix)
            cairo_set_source(cr, pattern)
            cairo_paint(cr)
            cairo_pattern_destroy(pattern)
            cairo_surface_destroy(tile)
        }
        // Light on the top edge; the open edge, where the record comes out,
        // a little in shade.
        cairo_rectangle(cr, 0, 0, side, 1)
        cairo_set_source_rgba(cr, 1, 1, 1, 0.22)
        cairo_fill(cr)
        let shade = cairo_pattern_create_linear(side - 3, 0, side, 0)!
        cairo_pattern_add_color_stop_rgba(shade, 0, 0, 0, 0, 0)
        cairo_pattern_add_color_stop_rgba(shade, 1, 0, 0, 0, 0.18)
        cairo_rectangle(cr, side - 3, 0, 3, side)
        cairo_set_source(cr, shade)
        cairo_fill(cr)
        cairo_pattern_destroy(shade)
        // The printed edge, inside: black at 18%, half a point.
        roundedRect(cr, 0.25, 0.25, side - 0.5, side - 0.5, 5.75)
        cairo_set_source_rgba(cr, 0, 0, 0, 0.18)
        cairo_set_line_width(cr, 0.5)
        cairo_stroke(cr)
        cairo_restore(cr)
    }
}

