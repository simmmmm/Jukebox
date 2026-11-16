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

// 1000 points high: the window's 900 and the menu bar above it.
let fitting = modes.filter { $0.width >= 1440 && $0.height >= 1000 && $0.isUsableForDesktopGUI() }
let sharpestThenSmallest = fitting.min { a, b in
    scale(a) != scale(b) ? scale(a) > scale(b) : a.width * a.height < b.width * b.height
}
guard let best = sharpestThenSmallest else {
    print("display: no mode of 1440 x 1000 points or more among \(modes.count)")
    exit(1)
}

var config: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&config) == .success else {
    print("display: no configuration to change")
    exit(1)
}
CGConfigureDisplayWithDisplayMode(config, display, best, nil)
let result = CGCompleteDisplayConfiguration(config, .permanently)
print("display: \(best.width) x \(best.height) points, \(best.pixelWidth) x \(best.pixelHeight) px, "
      + (result == .success ? "set" : "refused (\(result.rawValue))"))
exit(result == .success ? 0 : 1)
