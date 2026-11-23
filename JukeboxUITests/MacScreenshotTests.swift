// The Mac's screenshot walk: the Mac app itself, driven on GitHub's Mac
// against the fake Jellyfin of dev/fake-jellyfin.swift on localhost, for the
// Mac App Store's pictures (docs/RELEASE.md, Screenshots). The store takes a
// Mac's picture at 1440 by 900 exactly, without an alpha channel, so each
// picture is the window alone and the window is that size: the app sets it
// when launched with `-windowWidth 1440 -windowHeight 900` (WalkWindow in
// Jukebox/App/JukeboxApp.swift), because XCTest can click in a window but not
// size one. `-darkWindow YES` makes it dark whatever the runner's desktop is.
//
// Seven pictures, in dark, with music playing in each: Home, the albums, an
// album with Up Next beside it, Now Playing as the room, the room with timed
// lyrics, Radio with Your Station on the air, and Your Station's own page.
//
// Forgiving as the iPhone's and the iPad's walk (ScreenshotTests.swift), and
// for the same reason: nobody has seen this run. Every wait has a timeout. A
// step that finds nothing is written down (MISSED in the log, missed-mac.txt
// beside the pictures), the picture is taken anyway, and the walk goes on.
// Only the app no longer running fails the test.
//
// Elements are found by the identifiers the wide window sets (the sidebar's
// `place.<name>`, the bar's `bar.song`, `bar.upNext` and `bar.lyrics`, the
// room's `nowPlaying.close`, the sign-in's `signIn.address`, `signIn.user`
// and `signIn.password`), asked of any kind of element: what AppKit makes of
// a SwiftUI row is not known here. Buttons by their words.

#if os(macOS)
import AppKit
import XCTest

final class MacScreenshotTests: XCTestCase {
    @MainActor
    func testMac() throws {
        let walk = MacWalk(test: self)
        defer { walk.finish() }
        let app = walk.app

        try walk.launch()
        guard try walk.signIn() else { return }
        walk.waitForLibrary()

        // Music first, as the iPad's walk has it: Dust Windows playing, then
        // Home with the bar under it.
        if try walk.place("albums"), try walk.openAlbum("Dust Windows") {
            _ = try walk.play("Dust Windows: Play")
        }
        try walk.place("home")
        walk.picture("01-home-playing")

        try walk.place("albums")
        walk.picture("02-albums")

        // Up Next in the panel beside another album's page, the first cover.
        try walk.showPanel("upNext")
        _ = try walk.openAlbum("Dust Parades")
        walk.picture("03-album-up-next")

        // Now Playing as the room, from the bar's song, Up Next beside it.
        try walk.openRoom()
        walk.picture("04-now-playing")
        try walk.closeRoom()

        // The room with the words: Glass Hearts begins with Paper Heart,
        // whose lyrics are timed (dev/demo/lyrics.json). Not the iPad's
        // Silver Roads, far down the grid: thirty scrolls of the window did
        // not bring its cover (run 43767663743); Glass Hearts is in the
        // window as Albums opens.
        if try walk.place("albums"), try walk.openAlbum("Glass Hearts"), try walk.play("Glass Hearts: Play") {
            walk.waitForSong("Paper Heart")
        }
        try walk.showPanel("lyrics")
        try walk.openRoom()
        walk.picture("05-now-playing-lyrics")
        try walk.closeRoom()

        // Your Station, started from its own page: once it is on the air,
        // Radio no longer lists it and its card opens Now Playing, so the
        // page could not be reached from there. Its picture is therefore
        // taken before Radio's, and is left out when the page did not open.
        try walk.closePanel()
        if try walk.place("radio"), try walk.openStation("Your Station"), try walk.play("Your Station: Play") {
            // Stop is there only while the station is on the air.
            walk.find(app.buttons["Stop"], "Your Station: on the air", timeout: 30)
            walk.pause(4)
            walk.picture("07-station")
        } else if try walk.place("home") {
            _ = try walk.startYourStation()
        }
        try walk.place("radio")
        walk.find(app.buttons["Stop"], "Radio: a station on the air", timeout: 30)
        walk.pause(3)
        walk.picture("06-radio-on-air")
    }
}

/// The Mac's walk through the app: the app, and the steps that found nothing.
@MainActor
final class MacWalk {
    let app = XCUIApplication()

    private let test: XCTestCase
    private var lastPicture = "the start"
    private var missed: [String] = []
    /// What the panel shows, as this walk left it: "upNext", "lyrics", or
    /// nil, closed. Kept here and not asked of the bar's buttons: whether
    /// the Mac calls a lit one selected, as the iPad does, is not known.
    private var panel: String?
    /// Where ci/screenshots.sh wants every picture as a file as well
    /// (JUKEBOX_SHOTS, from its TEST_RUNNER_JUKEBOX_SHOTS), or nil: there
    /// even when the test runner is stopped before its result bundle is
    /// whole.
    private let folder: URL? = {
        guard let path = ProcessInfo.processInfo.environment["JUKEBOX_SHOTS"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init(test: XCTestCase) {
        self.test = test
    }

    // MARK: Pictures and notes

    /// The window as it is, as `name`.png in the folder and as an attachment
    /// of the test. Its size goes to the log: the store refuses any other
    /// than 1440 by 900, and a runner's display may be too small for it.
    func picture(_ name: String) {
        let window = app.windows.firstMatch
        let hasWindow = window.exists
        if !hasWindow { note("\(name): no window; the whole screen instead") }
        lastPicture = name
        let shot = XCTExpectFailure("A picture of the screenshot walk", strict: false) { () -> XCUIScreenshot in
            guard hasWindow else { return XCUIScreen.main.screenshot() }
            // The pointer to the window's top edge first: where the last
            // click left it, it lights the tile under it and, resting on a
            // button of the bar, brings up its tooltip.
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).hover()
            self.pause(0.7)
            return window.screenshot()
        }
        let frame = XCTExpectFailure("The window's size, for the screenshot walk", strict: false) { () -> CGRect in
            hasWindow ? window.frame : .zero
        }
        let (png, pixels) = opaque(shot.pngRepresentation)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        if let folder = folder {
            try? png.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
        }
        print("PICTURE: \(name) (\(pixels), the window \(Int(frame.width)) x \(Int(frame.height)) points)")
    }

    /// `png` without an alpha channel, which App Store Connect refuses, and
    /// its size in words. A window's picture may be clear outside its round
    /// corners: drawn over black, as the dark window's own edge.
    private func opaque(_ png: Data) -> (Data, String) {
        guard let bitmap = NSBitmapImageRep(data: png) else { return (png, "size unknown") }
        let pixels = "\(bitmap.pixelsWide) x \(bitmap.pixelsHigh) px"
        guard bitmap.hasAlpha, let image = bitmap.cgImage,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return (png, pixels) }
        let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(whole)
        context.draw(image, in: whole)
        guard let flat = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:])
        else { return (png, pixels) }
        return (data, pixels)
    }

    /// A step that found nothing, written down with the picture it followed.
    func note(_ what: String) {
        let line = "after \(lastPicture): \(what)"
        missed.append(line)
        print("MISSED: \(line)")
        // The file says it as it happens: a runner that is stopped never
        // reaches finish().
        saveMissed()
    }

    /// The missed list, as an attachment beside the pictures (and as a
    /// file). Called when the test ends, however it ends.
    func finish() {
        let attachment = XCTAttachment(string: missedText)
        attachment.name = "missed-mac"
        attachment.lifetime = .keepAlways
        test.add(attachment)
        saveMissed()
    }

    private var missedText: String {
        missed.isEmpty ? "Nothing missed." : missed.joined(separator: "\n")
    }

    private func saveMissed() {
        guard let folder = folder else { return }
        try? (missedText + "\n").write(to: folder.appendingPathComponent("missed-mac.txt"),
                                       atomically: true, encoding: .utf8)
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: The app

    func launch() throws {
        // English and the US region, whatever the runner was set to: the
        // words this walk looks for are the app's English ones.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // No usage counts from CI's walk (docs/STATS.md), and no automatic
        // keep fetching from the fake server meanwhile (docs/OFFLINE.md).
        app.launchArguments += ["-shareUsage", "NO", "-keepSongs", "NO"]
        // Better Radio and Enhance Radio, though the walk's build has no
        // Last.fm key (AppSettings.canEnhanceRadio).
        app.launchArguments += ["-showBetterRadio", "YES"]
        // The panel closed, whatever an earlier launch left: this walk
        // keeps count of it from there.
        app.launchArguments += ["-panelOpen", "NO"]
        // The store's size, and dark (WalkWindow in JukeboxApp.swift).
        app.launchArguments += ["-windowWidth", "1440", "-windowHeight", "900", "-darkWindow", "YES"]
        // No windows brought back from an earlier launch.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        // With the word the script's log is searched for, so it shows there.
        if let screen = NSScreen.main {
            print("The screen of every PICTURE: \(Int(screen.frame.width)) x \(Int(screen.frame.height)) points,"
                  + " \(screen.backingScaleFactor) pixels a point")
        } else {
            print("The screen of every PICTURE: none")
        }
        app.launch()
        try alive("launch")
    }

    /// Throws, and fails the test, when the app is no longer running: it
    /// crashed. The one way this walk fails. Behind something else (a
    /// dialog of the system's) it is brought to the front, and the walk
    /// goes on either way.
    func alive(_ step: String) throws {
        if app.state == .runningForeground { return }
        if app.state == .runningBackground {
            app.activate()
            pause(2)
            if app.state != .runningForeground {
                note("\(step): Jukebox is not in front (state \(app.state.rawValue))")
            }
            return
        }
        let message = "Jukebox stopped running at “\(step)” (state \(app.state.rawValue))"
        note(message)
        XCTFail(message)
        throw NSError(domain: "MacScreenshotTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: Finding and clicking

    /// The element the app marks with `id`, whatever kind it is on the Mac.
    func marked(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The same, waited for; nil after `timeout`, written down as a skip.
    func byID(_ id: String, timeout: TimeInterval = 4) -> XCUIElement? {
        let element = marked(id)
        if element.waitForExistence(timeout: timeout) { return element }
        note("skipped: no \(id) within \(Int(timeout)) s")
        return nil
    }

    /// Buttons whose words begin with `text`: a cover says "Album, Artist",
    /// a station "Your Station, Played Thursday". The words are the label or
    /// the title, whichever the Mac gives a button.
    func buttons(beginning text: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR title BEGINSWITH %@", text, text))
    }

    /// Waits for `element`; when it does not come, the step is written down.
    @discardableResult
    func find(_ element: XCUIElement, _ step: String, timeout: TimeInterval = 10) -> Bool {
        if element.firstMatch.waitForExistence(timeout: timeout) { return true }
        note("\(step): not found within \(Int(timeout)) s")
        return false
    }

    func isHittable(_ element: XCUIElement) -> Bool {
        XCTExpectFailure("Whether an element can be clicked, for the screenshot walk", strict: false) { () -> Bool in
            element.exists && element.isHittable
        }
    }

    /// Clicks `element` when it is there. When it is not, the step is
    /// written down and the walk goes on. False when nothing was clicked.
    @discardableResult
    func click(_ element: XCUIElement, _ step: String, timeout: TimeInterval = 10) throws -> Bool {
        let element = element.firstMatch
        guard element.waitForExistence(timeout: timeout) else {
            note("\(step): not found within \(Int(timeout)) s")
            try alive(step)
            return false
        }
        XCTExpectFailure("A click of the screenshot walk", strict: false) {
            if element.isHittable {
                element.click()
            } else {
                // Said not to be hittable, a click at its middle still lands.
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
        }
        try alive(step)
        return true
    }

    /// Types `text` into the field marked `id`: clicked for the keys, what
    /// it holds selected (the address and the user name are remembered from
    /// the last sign-in), so the typing takes its place.
    @discardableResult
    func enter(_ text: String, into id: String) throws -> Bool {
        guard let field = byID(id, timeout: 10), try click(field, id, timeout: 1) else { return false }
        pause(0.8)
        XCTExpectFailure("Typing in the screenshot walk", strict: false) {
            field.typeKey("a", modifierFlags: .command)
            field.typeText(text)
        }
        try alive(id)
        return true
    }

    // MARK: Signing in

    /// Signs in to the fake Jellyfin on the wide window's one page: the
    /// address, the user name and the password, then Return. True once the
    /// sidebar's Home is there; already signed in (a debug build keeps its
    /// session in the file-based keychain, Jukebox/App/Keychain.swift), at
    /// once.
    func signIn() throws -> Bool {
        let home = marked("place.home")
        let address = marked("signIn.address")
        let deadline = Date().addingTimeInterval(30)
        while !home.exists && !address.exists && Date() < deadline {
            pause(0.5)
        }
        if home.exists { return true }
        guard address.exists else {
            note("launch: neither the sign-in nor Home within 30 s")
            picture("00-launch")
            try alive("launch")
            return false
        }

        // As the iPhone's walk has it (fakeServer, ScreenshotTests.swift,
        // which is the iPhone's alone): localhost:8096 unless told.
        let given = ProcessInfo.processInfo.environment["JUKEBOX_SERVER"] ?? ""
        try enter(given.isEmpty ? "localhost:8096" : given, into: "signIn.address")
        try enter("test", into: "signIn.user")
        try enter("test", into: "signIn.password")
        XCTExpectFailure("Return in the screenshot walk", strict: false) {
            self.app.typeKey(.return, modifierFlags: [])
        }
        if !home.waitForExistence(timeout: 45) {
            note("Sign in: Return did not sign in within 45 s")
            try click(app.buttons["Sign In"], "Sign in: Sign In", timeout: 2)
        }
        guard home.waitForExistence(timeout: 60) else {
            note("Sign in: Home did not come (the fake Jellyfin's log says what it was asked)")
            picture("00-sign-in-error")
            return false
        }
        // Better Radio, the step after signing in: its picture, then Turn On.
        let turnOn = marked("betterRadio.turnOn")
        if turnOn.waitForExistence(timeout: 8) {
            pause(1.5)
            picture("00-better-radio")
            _ = try click(turnOn, "Better Radio: Turn On", timeout: 2)
            pause(1)
        }
        return true
    }

    /// Home with the library read (Your Station, or the mixes' heading),
    /// then the mixes made and a moment for the covers. A library that does
    /// not come is written down and the walk goes on.
    func waitForLibrary() {
        let station = app.staticTexts["Your Station"].firstMatch
        let mixes = app.staticTexts["Mixes"].firstMatch
        let deadline = Date().addingTimeInterval(60)
        while !station.exists && !mixes.exists && Date() < deadline {
            pause(0.5)
        }
        if !station.exists && !mixes.exists {
            note("Home: the library did not load within 60 s (no Your Station, no Mixes)")
            return
        }
        let making = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Making your mixes")).firstMatch
        let made = Date().addingTimeInterval(45)
        while making.exists && Date() < made {
            pause(1)
        }
        if making.exists { note("Home: the mixes were still being made after 45 s") }
        pause(4)
    }

    // MARK: Going places

    /// A place of the sidebar (`place.<name>`), clicked. True when it was.
    @discardableResult
    func place(_ name: String) throws -> Bool {
        let id = "place." + name
        guard let found = byID(id, timeout: 3), try click(found, id, timeout: 1) else { return false }
        pause(2)
        return true
    }

    /// An album's page from the albums' grid, by the cover whose words
    /// begin with `name`. The grid is lazy, a cover made only near the
    /// window, so the walk scrolls through the page until the cover can be
    /// clicked; then the first cover in the window instead.
    func openAlbum(_ name: String) throws -> Bool {
        let named = buttons(beginning: name).firstMatch
        var found = named.waitForExistence(timeout: 3) && isHittable(named)
        // Down the page, then back up it: which way a negative delta goes
        // is not known here, and the first run found no Silver Roads going
        // one way (run 43766325380).
        for step in 0..<30 where !found {
            // Less than the page is tall, even in a window cut short by a
            // small screen, so no row is passed unseen. The pointer is at
            // the window's middle for it, over the page.
            XCTExpectFailure("A scroll of the screenshot walk", strict: false) {
                self.app.windows.firstMatch.scroll(byDeltaX: 0, deltaY: step < 12 ? -360 : 360)
            }
            pause(0.7)
            found = isHittable(named)
        }
        var cover: XCUIElement? = named
        if !found {
            note("Albums: no cover of \(name) after thirty scrolls; the first in the window instead")
            cover = firstCover()
        }
        guard let cover, try click(cover, "Albums: open \(name)", timeout: 1) else { return false }
        pause(3)
        return true
    }

    /// The first cover in the window: of the first twelve buttons inside a
    /// scroll view that are no place of the sidebar (a scroll view of
    /// buttons too), the first cover-shaped one, at least nearly as tall as
    /// wide, that can be clicked.
    private func firstCover() -> XCUIElement? {
        let notPlaces = NSPredicate(format: "NOT (identifier BEGINSWITH %@)", "place.")
        let inGrid = app.scrollViews.buttons.matching(notPlaces)
        let cover = XCTExpectFailure("Looking through buttons, for the screenshot walk", strict: false) { () -> XCUIElement? in
            for i in 0..<min(inGrid.count, 12) {
                let button = inGrid.element(boundBy: i)
                guard button.exists else { continue }
                let frame = button.frame
                if frame.width >= 100, frame.height >= frame.width * 0.9, button.isHittable {
                    return button
                }
            }
            return nil
        }
        if cover == nil { note("Albums: no cover in the window") }
        return cover
    }

    /// A station's page, from its tile on Radio, found by the start of its
    /// words. True once the page is there: its New Picks, before it plays.
    func openStation(_ title: String) throws -> Bool {
        guard try click(buttons(beginning: title).firstMatch, "Radio: the \(title) station") else { return false }
        guard app.buttons["New Picks"].firstMatch.waitForExistence(timeout: 10) else {
            note("Radio: the \(title) station's page did not open (no New Picks)")
            return false
        }
        pause(3)
        return true
    }

    // MARK: Playing

    /// The page's Play (an album's head, a station's, Your Station's card on
    /// Home): the first enabled button that says Play, the page's coming
    /// before the bar's. True when it was clicked.
    func play(_ step: String) throws -> Bool {
        let plays = app.buttons.matching(identifier: "Play")
        guard plays.firstMatch.waitForExistence(timeout: 10) else {
            note("\(step): no Play within 10 s")
            return false
        }
        let enabled = XCTExpectFailure("Looking through buttons, for the screenshot walk", strict: false) { () -> XCUIElement? in
            for i in 0..<min(plays.count, 8) {
                let button = plays.element(boundBy: i)
                if button.exists, button.isEnabled { return button }
            }
            return nil
        }
        guard let play = enabled else {
            note("\(step): no enabled Play")
            return false
        }
        guard try click(play, step, timeout: 1) else { return false }
        // Playing: the bar's button says Pause.
        if !app.buttons["Pause"].firstMatch.waitForExistence(timeout: 45) {
            note("\(step): nothing was playing 45 s after it")
        }
        pause(3)
        return true
    }

    /// Your Station from the top of Home, should its own page not open.
    func startYourStation() throws -> Bool {
        guard find(app.staticTexts["Your Station"], "Home: Your Station's card", timeout: 15) else { return false }
        return try play("Home: Your Station's Play")
    }

    /// Until the bar's song (`bar.song`, labelled with the song) is `title`:
    /// a Play while something else plays says Pause at once.
    func waitForSong(_ title: String) {
        let song = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND (label CONTAINS %@ OR title CONTAINS %@)",
                                  "bar.song", title, title)).firstMatch
        if !song.waitForExistence(timeout: 15) { note("the bar's song was not \(title) within 15 s") }
    }

    // MARK: The panel and the room

    /// The panel on `content` ("upNext", "lyrics"), by the bar's button for
    /// it (`bar.upNext`, `bar.lyrics`). The buttons toggle (PanelState: the
    /// one lit closes the panel), so the one this walk lit is left be.
    func showPanel(_ content: String) throws {
        guard panel != content, let button = byID("bar." + content) else { return }
        if try click(button, "bar." + content, timeout: 1) {
            panel = content
            pause(2.5)
        }
    }

    /// The panel closed, by the bar's lit button.
    func closePanel() throws {
        guard let content = panel, let button = byID("bar." + content) else { return }
        if try click(button, "bar." + content, timeout: 1) {
            panel = nil
            pause(1.5)
        }
    }

    /// Now Playing as the room, from the bar's song (`bar.song`), waited
    /// for by its close (`nowPlaying.close`), with a moment for the sleeve.
    func openRoom() throws {
        guard let song = byID("bar.song"), try click(song, "bar.song", timeout: 1) else { return }
        if !marked("nowPlaying.close").waitForExistence(timeout: 8) {
            note("Now Playing: no nowPlaying.close 8 s after bar.song")
        }
        pause(4)
    }

    /// The room closed by `nowPlaying.close`, then by Escape, which the room
    /// answers too: left open it would lie over every picture after it.
    func closeRoom() throws {
        let close = marked("nowPlaying.close")
        for _ in 0..<2 where close.exists {
            try click(close, "nowPlaying.close", timeout: 1)
            pause(2)
        }
        if close.exists {
            note("Now Playing: still open after two clicks of nowPlaying.close; Escape")
            XCTExpectFailure("Escape in the screenshot walk", strict: false) {
                self.app.typeKey(.escape, modifierFlags: [])
            }
            pause(2)
        }
    }
}
#endif
