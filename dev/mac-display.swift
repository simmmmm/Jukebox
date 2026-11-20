// The runner's display made large enough for the Mac's screenshot walk
// (ci/screenshots.sh, MacScreenshotTests.swift). The Mac App Store takes a
// picture of 1440 by 900 exactly, and the picture is the window, so the
// screen must hold a window that size under its menu bar; GitHub's Mac
// comes up at 1024 by 768 (run 43766325380). This lists the display's modes
// and sets the one that fits: the sharpest first (a 2x mode makes the
// picture 2880 by 1800, which the store takes too), then the smallest.
// For good, not for this process alone: CGDisplaySetDisplayMode's change
// ends with the program that made it.
//
//   xcrun swiftc -O dev/mac-display.swift -o mac-display && ./mac-display
//
// On the photographer's MacBook, a runner of its own and his laptop, the
// display is his: `./mac-display <file>` writes the mode it had into the
// file before it changes it, and `./mac-display --restore <file>` sets that
// mode again after the walk. A mode that fits already is left as it is.
//
// Exit 1 when no mode fits or the change was refused; the modes are printed
// either way, so the log says what the display can do.

import CoreGraphics
import Foundation

let display = CGMainDisplayID()
// Low-resolution twins of the 2x modes too: on a 1x display they are all
// there is.
let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
for mode in modes {
    print("mode: \(mode.width) x \(mode.height) points, \(mode.pixelWidth) x \(mode.pixelHeight) px")
}

func scale(_ mode: CGDisplayMode) -> Int {
    mode.width > 0 ? mode.pixelWidth / mode.width : 1
}

func describe(_ mode: CGDisplayMode) -> String {
    "\(mode.width) \(mode.height) \(mode.pixelWidth) \(mode.pixelHeight)"
}

func apply(_ mode: CGDisplayMode) -> CGError {
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { return .failure }
    CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
    return CGCompleteDisplayConfiguration(config, .permanently)
}

let arguments = CommandLine.arguments.dropFirst()
if arguments.first == "--restore", let file = arguments.dropFirst().first {
    let saved = (try? String(contentsOfFile: file, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard let mode = modes.first(where: { describe($0) == saved }) else {
        print("display: the saved mode \(saved.isEmpty ? "(none)" : saved) is not among the display's modes")
        exit(saved.isEmpty ? 0 : 1)
    }
    if let current = CGDisplayCopyDisplayMode(display), describe(current) == saved {
        print("display: still \(saved), as it was")
        exit(0)
    }
    let result = apply(mode)
    print("display: back to \(saved), " + (result == .success ? "set" : "refused (\(result.rawValue))"))
    exit(result == .success ? 0 : 1)
}
if let current = CGDisplayCopyDisplayMode(display), current.width >= 1440, current.height >= 1000 {
    print("display: \(current.width) x \(current.height) points already, left as it is")
    exit(0)
}
if let file = arguments.first, let current = CGDisplayCopyDisplayMode(display) {
    try? describe(current).write(toFile: file, atomically: true, encoding: .utf8)
}

// 1000 points high: the window's 900 and the menu bar above it.
let fitting = modes.filter { $0.width >= 1440 && $0.height >= 1000 && $0.isUsableForDesktopGUI() }
let sharpestThenSmallest = fitting.min { a, b in
    scale(a) != scale(b) ? scale(a) > scale(b) : a.width * a.height < b.width * b.height
}
guard let best = sharpestThenSmallest else {
    print("display: no mode of 1440 x 1000 points or more among \(modes.count)")
    exit(1)
}

let result = apply(best)
print("display: \(best.width) x \(best.height) points, \(best.pixelWidth) x \(best.pixelHeight) px, "
      + (result == .success ? "set" : "refused (\(result.rawValue))"))
exit(result == .success ? 0 : 1)
