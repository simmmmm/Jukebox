// A contact sheet from a folder of screenshots: a grid of thumbnails, each
// labelled with its file name, on Numa's dark page (#141414), under a title.
// And a small JPEG of the sheet, 900 pixels wide, for the places where the
// full sheet is too much: the run's log (ci/screenshots.sh prints it there as
// base64, the one thing of a run the lead can read) and the README of the
// `screenshots` branch, which the photographer opens on a phone.
//
//   xcrun swiftc -O dev/contact-sheet.swift -o build/contact-sheet
//   build/contact-sheet <folder> <sheet.png> <preview.jpg> [title...]
//
// Run with no arguments, it checks itself on made-up pictures.
//
// macOS only (CoreGraphics, ImageIO, CoreText): it runs where the pictures
// are taken, on GitHub's Mac. It was Python with Pillow until 15 November
// 2026. After Numa-mac's contact sheet, with fewer and larger thumbnails:
// four portrait screens a row (three landscape ones), so that the 900-pixel
// copy still shows each screen about 210 pixels wide.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let gap = 16
let labelHeight = 36
let previewWidth = 900
let pictureTypes: Set<String> = ["png", "jpg", "jpeg"]

func gray(_ value: CGFloat) -> CGColor { CGColor(srgbRed: value / 255, green: value / 255, blue: value / 255, alpha: 1) }

func canvas(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func image(at url: URL) -> CGImage? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}

func save(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:]) throws {
    guard let out = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(out, image, properties as CFDictionary)
    if !CGImageDestinationFinalize(out) { throw CocoaError(.fileWriteUnknown) }
}

/// Text with its top left at (x, top) on a canvas `height` tall.
func draw(_ text: String, in context: CGContext, x: Int, top: Int, height: Int, size: CGFloat, color: CGColor) {
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]))
    context.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(height - top) - CTFontGetAscent(font))
    CTLineDraw(line, context)
}

/// The sheet of every picture in `folder`, by name; how many it has.
func sheet(_ folder: URL, _ out: URL, title: String = "") throws -> Int {
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        .filter { pictureTypes.contains(($0 as NSString).pathExtension.lowercased()) }
        .sorted()
    let pictures = names.compactMap { name in
        image(at: folder.appendingPathComponent(name)).map { (label: (name as NSString).deletingPathExtension, image: $0) }
    }
    if pictures.isEmpty { return 0 }
    let landscape = pictures.filter { $0.image.width > $0.image.height }.count * 2 > pictures.count
    let (width, most) = landscape ? (480, 3) : (360, 4)
    // As large as fits width by three widths, never larger than it is.
    let sizes = pictures.map { picture -> (Int, Int) in
        let w = picture.image.width, h = picture.image.height
        let scale = min(1, Double(width) / Double(w), Double(width * 3) / Double(h))
        return (max(1, Int((Double(w) * scale).rounded())), max(1, Int((Double(h) * scale).rounded())))
    }
    let height = sizes.map { $0.1 }.max()!
    let columns = min(most, pictures.count)
    let rows = (pictures.count + columns - 1) / columns
    let top = title.isEmpty ? gap : 60
    let cell = height + labelHeight + gap
    let canvasWidth = gap + columns * (width + gap), canvasHeight = top + rows * cell
    let context = canvas(canvasWidth, canvasHeight)
    context.setFillColor(gray(20))
    context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
    context.interpolationQuality = .high
    if !title.isEmpty {
        draw(title, in: context, x: gap, top: 14, height: canvasHeight, size: 30, color: gray(235))
    }
    for (index, picture) in pictures.enumerated() {
        let x = gap + (index % columns) * (width + gap)
        let y = top + (index / columns) * cell
        let (w, h) = sizes[index]
        context.draw(picture.image, in: CGRect(x: x + (width - w) / 2, y: canvasHeight - y - h, width: w, height: h))
        // Large enough to read in the 900-pixel copy (about 14 pixels there).
        draw(picture.label, in: context, x: x, top: y + height + 6, height: canvasHeight, size: 24, color: gray(200))
    }
    try save(context.makeImage()!, to: out, type: .png)
    return pictures.count
}

/// The sheet `previewWidth` pixels wide, as a JPEG small enough for a log.
func preview(_ sheetPNG: URL, _ out: URL) throws -> Int {
    guard var picture = image(at: sheetPNG) else { throw CocoaError(.fileReadCorruptFile) }
    if picture.width > previewWidth {
        let height = Int((Double(picture.height) * Double(previewWidth) / Double(picture.width)).rounded())
        let context = canvas(previewWidth, height)
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(x: 0, y: 0, width: previewWidth, height: height))
        picture = context.makeImage()!
    }
    try save(picture, to: out, type: .jpeg, properties: [
        kCGImageDestinationLossyCompressionQuality: 0.72,
        kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true],
    ])
    return (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
}

func check() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("contact-sheet-\(getpid())")
    defer { try? FileManager.default.removeItem(at: folder) }
    func make(_ dir: URL, _ sizes: [(Int, Int)], _ name: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, size) in sizes.enumerated() {
            let context = canvas(size.0, size.1)
            context.setFillColor(CGColor(srgbRed: CGFloat(40 * index % 256) / 255, green: 90 / 255, blue: 160 / 255, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.0, height: size.1))
            try save(context.makeImage()!, to: dir.appendingPathComponent(String(format: "%02d-\(name).png", index)), type: .png)
        }
    }
    func size(_ url: URL) -> (Int, Int) { image(at: url).map { ($0.width, $0.height) } ?? (0, 0) }
    func expect(_ condition: Bool, _ what: String) {
        if !condition { FileHandle.standardError.write(Data("check failed: \(what)\n".utf8)); exit(1) }
    }
    // An iPhone 17 Pro's screen, an iPad Pro's held sideways, and odd ones.
    let shots = folder.appendingPathComponent("shots")
    let shapes: [(Int, Int)] = [(1206, 2622), (2752, 2064), (100, 100)]
    try make(shots, shapes + shapes + shapes, "shot")
    let out = folder.appendingPathComponent("sheet.png")
    expect(try sheet(shots, out, title: "test") == 9, "nine pictures")
    expect(size(out).0 == gap + 4 * (360 + gap) && size(out).1 > 3 * 360, "the sheet's size \(size(out))")
    let jpg = folder.appendingPathComponent("sheet.jpg")
    _ = try preview(out, jpg)
    let type = CGImageSourceCreateWithURL(jpg as CFURL, nil).flatMap { CGImageSourceGetType($0) }.map { $0 as String }
    expect(size(jpg).0 == previewWidth && type == UTType.jpeg.identifier, "the preview \(size(jpg)) \(type ?? "?")")
    let empty = folder.appendingPathComponent("empty")
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    expect(try sheet(empty, folder.appendingPathComponent("none.png")) == 0, "no pictures, no sheet")
    let wide = folder.appendingPathComponent("wide")
    let pads: [(Int, Int)] = Array(repeating: (2752, 2064), count: 4)
    try make(wide, pads, "pad")
    expect(try sheet(wide, out) == 4, "four pictures")
    expect(size(out).0 == gap + 3 * (480 + gap), "three landscape ones a row \(size(out))")
    print("ok")
}

let arguments = CommandLine.arguments
do {
    if arguments.count >= 4 {
        let sheetURL = URL(fileURLWithPath: arguments[2]), previewURL = URL(fileURLWithPath: arguments[3])
        let count = try sheet(URL(fileURLWithPath: arguments[1]), sheetURL, title: arguments.dropFirst(4).joined(separator: " "))
        if count > 0 {
            let bytes = try preview(sheetURL, previewURL)
            print("\(count) pictures on \(arguments[2]); \(arguments[3]) is \(bytes / 1024) KB")
        } else {
            print("no pictures in \(arguments[1])")
        }
    } else {
        try check()
    }
} catch {
    FileHandle.standardError.write(Data("contact-sheet: \(error)\n".utf8))
    exit(1)
}
