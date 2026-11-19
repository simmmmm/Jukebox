// The few places the iPhone and the Mac spell a thing differently, said once,
// so the screens stay one SwiftUI for both: the image type, the device's own
// words ("on this Mac"), a colour for light and dark, and the modifiers only
// the iPhone's navigation bar and keyboard have. The Mac is a native macOS
// destination of the same target, not Catalyst: its own controls, and
// "Mac" where the words say what the device is. Each shim keeps the iPhone's
// call exactly as it was, so its screens do not move.

import SwiftUI
#if os(iOS)
import UIKit

/// UIKit's image on the iPhone and the iPad, AppKit's on the Mac.
typealias PlatformImage = UIImage
#else
import AppKit

typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage image: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

extension PlatformImage {
    /// Decoded before its first draw, so scrolling does not wait on it:
    /// UIKit's own. The Mac decodes an NSImage as it draws it.
    func preparedForDisplay() async -> PlatformImage {
        #if os(iOS)
        return await byPreparingForDisplay() ?? self
        #else
        return self
        #endif
    }

    /// Its pixels, for the memory cache's cost: an NSImage's size is in
    /// points, its bitmap's pixels are on its representation.
    var pixelCount: Int {
        #if os(iOS)
        return Int(size.width * scale * size.height * scale)
        #else
        let bitmap = representations.first
        return (bitmap?.pixelsWide ?? Int(size.width)) * (bitmap?.pixelsHigh ?? Int(size.height))
        #endif
    }

    /// Drawn into `rect` of a bitmap context, whatever backs the image.
    /// UIKit's draw is upside down there and Core Graphics' upright, which
    /// an average or a histogram of the pixels does not mind.
    func draw(into context: CGContext, rect: CGRect) {
        #if os(iOS)
        UIGraphicsPushContext(context)
        draw(in: rect)
        UIGraphicsPopContext()
        #else
        guard let image = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.draw(image, in: rect)
        #endif
    }
}

#if os(macOS)
extension NSImage {
    /// UIImage's call, for the widget's covers (WidgetDoors.swift): an
    /// NSImage has no JPEG of its own, its bitmap representation does.
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif

/// What the device is, in the words the app says it with.
enum Device {
    /// "iPhone", "iPad" or "Mac": "Songs on this iPad".
    static var model: String {
        #if os(iOS)
        // The iPad's app run on a Mac is on a Mac: "Songs on this Mac".
        return ProcessInfo.processInfo.isiOSAppOnMac ? "Mac" : UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    /// The name the listener gave it ("Tijmen's MacBook Pro"): how the
    /// server and the listener's other devices know it.
    static var name: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

extension Color {
    /// A colour that follows the appearance: `light` by day, `dark` by
    /// night, asked for again by the system whenever it draws.
    /// `nonisolated`: the system may ask off the main actor.
    nonisolated init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
        #endif
    }

    /// The system's colour for a hairline between things.
    static var separatorLine: Color {
        #if os(iOS)
        return Color(uiColor: .separator)
        #else
        return Color(nsColor: .separatorColor)
        #endif
    }
}

#if os(iOS)
extension UIColor {
    /// An sRGB colour by its hex, as the brand board names it.
    nonisolated convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
#else
extension NSColor {
    /// An sRGB colour by its hex, as the brand board names it.
    nonisolated convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
#endif

extension ToolbarItemPlacement {
    /// The trailing end of the iPhone's navigation bar; the Mac's window
    /// toolbar, where its actions go.
    static var barTrailing: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }

    /// The leading end of the iPhone's navigation bar; the Mac's toolbar's
    /// navigation place.
    static var barLeading: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .navigation
        #endif
    }
}

extension SearchFieldPlacement {
    /// Always showing, under a sheet's title on the iPhone; where the Mac
    /// puts its search field.
    static var alwaysShown: SearchFieldPlacement {
        #if os(iOS)
        return .navigationBarDrawer(displayMode: .always)
        #else
        return .automatic
        #endif
    }
}

extension EnvironmentValues {
    /// Room for the wide layout: an iPad at regular width, and the Mac's
    /// window always.
    nonisolated var isWide: Bool {
        #if os(iOS)
        return horizontalSizeClass == .regular
        #else
        return true
        #endif
    }
}

extension View {
    /// The navigation bar's small title. A Mac window has one kind of title.
    func inlineTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// The navigation bar's large title, as Music's top pages have it.
    func largeTitle() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.large)
        #else
        return self
        #endif
    }

    /// Kept as typed, without a capital first letter: a name, a key. The
    /// Mac never capitalises by itself.
    func plainTextEntry() -> some View {
        #if os(iOS)
        return textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }

    /// An address: the keyboard with "/" and ".", and autofill's addresses,
    /// typed as it is. The Mac has a keyboard of its own.
    func urlEntry() -> some View {
        #if os(iOS)
        return keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }
}
