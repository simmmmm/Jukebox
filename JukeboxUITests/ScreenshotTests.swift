// The screenshot walk: Jukebox used as a listener would use it, in the iOS
// Simulator on GitHub's Mac, against the fake Jellyfin of
// dev/fake-jellyfin.py on localhost. Every main screen of the iPhone in dark
// (`testPhone`), Home and Now Playing again in light (`testPhoneLight`), and
// the main screens of the iPad (`testPad`). ci/screenshots.sh runs each on its
// own simulator and appearance, exports the pictures and makes the contact
// sheets. There is no Mac here, so nobody has seen the app; the photographer
// asked for pictures ("Als je plaatjes hebt om te delen zie ik ze graag"),
// and the lead needs them to see what to fix.
//
// The walk is forgiving on purpose. The app is being changed while this is
// written, and a walk that stops at the first missing button shows none of
// the screens after it. So every wait has a timeout. A step that finds
// nothing is written down (MISSED in the log, and the `missed-…` attachment
// that the script puts beside the pictures), the picture is taken anyway (a
// missing button then shows as a screen that did not change), and the walk
// goes on. Only the app no longer running fails a test. Each interaction runs
// inside XCTExpectFailure, so XCTest's own complaints ("not hittable",
// "no keyboard focus") are written down too but do not fail the test.
//
// Elements are found by the labels the app's SwiftUI gives them (the words of
// its Text, Label and accessibilityLabel), because the app has no
// accessibility identifiers and this walk may not change the app. When the
// app's words change, the step is missed and the missed list says which one.

import UIKit
import XCTest

final class ScreenshotTests: XCTestCase {
    /// The iPhone, in dark: the welcome and the sign-in, Home, Radio, the
    /// library and its pages, Settings, Your Station started from Home, Now
    /// Playing with its lyrics and its queue, the mini player above the
    /// tabs, and a search.
    @MainActor
    func testPhone() throws {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        try XCTSkipUnless(isPhone, "The iPad has its own walk, testPad.")
        let walk = Walk(test: self, name: "phone")
        defer { walk.finish() }
        let app = walk.app

        try walk.launch()
        guard try walk.signIn(takingPictures: true) else { return }
        walk.waitForLibrary()

        walk.picture("home")
        try walk.swipe(up: true)
        walk.picture("home-scrolled")
        // Back to the top: the tab bar comes back from its minimised state,
        // and Your Station's card is where the walk later needs it.
        try walk.swipe(up: false)

        try walk.tab("Radio")
        walk.picture("radio")
        let picking = try walk.tap(app.buttons["Start a Station"], "Radio: Start a Station")
        if picking { walk.pause(2) }
        walk.picture("radio-start-a-station")
        if picking { try walk.closeSheet(with: "Cancel") }

        try walk.tab("Library")
        walk.picture("library")

        let albums = try walk.push("Albums")
        walk.picture("albums")
        var album = false
        if albums, let tile = walk.firstTile("Albums: an album's cover") {
            album = try walk.tap(tile, "Albums: open an album")
            if album { walk.pause(3) }
        }
        walk.picture("album")
        if album { try walk.goBack(to: "Albums") }
        if albums { try walk.goBack(to: "Library") }

        let artists = try walk.push("Artists")
        walk.picture("artists")
        var artist = false
        if artists, let row = walk.firstRow("Artists: an artist") {
            walk.artistName = walk.label(of: row)
            artist = try walk.tap(row, "Artists: open an artist")
            if artist { walk.pause(3) }
        }
        walk.picture("artist")
        if artist { try walk.goBack(to: "Artists") }
        if artists { try walk.goBack(to: "Library") }

        let playlists = try walk.push("Playlists")
        walk.picture("playlists")
        if playlists { try walk.goBack(to: "Library") }

        try walk.tab("Home")
        let settings = try walk.tap(app.buttons["Settings"], "Home: Settings (the person in the toolbar)")
        if settings {
            _ = app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: 8)
            walk.pause(1.5)
        }
        walk.picture("settings")
        if settings { try walk.closeSheet(with: "Done") }

        _ = try walk.startYourStation()
        walk.picture("home-playing")

        let nowPlaying = try walk.openNowPlaying()
        walk.picture("now-playing")
        if nowPlaying {
            let lyrics = try walk.tap(app.buttons["Lyrics"], "Now Playing: Lyrics")
            if lyrics { walk.pause(3) }
            walk.picture("lyrics")
            if lyrics { try walk.tap(app.buttons["Lyrics"], "Lyrics: back to the cover") }

            let queue = try walk.tap(app.buttons["Up Next"], "Now Playing: Up Next")
            if queue { walk.pause(2) }
            walk.picture("queue")
            if queue { try walk.tap(app.buttons["Up Next"], "Up Next: back to the cover") }

            try walk.closeNowPlaying()
        } else {
            walk.picture("lyrics")
            walk.picture("queue")
        }

        // The mini player above the tab bar, over another tab's page.
        try walk.tab("Library")
        walk.picture("mini-player")

        // The radio's own page with a station on the air: its card and dial.
        try walk.tab("Radio")
        walk.picture("radio-on-air")

        // Last: on iOS 26 a search takes the tab bar over until it is cancelled.
        try walk.tab("Search")
        let field = app.searchFields.firstMatch
        if walk.find(field, "Search: the search field", timeout: 8) {
            try walk.enter(walk.searchTerm, into: field, "Search: typing a term")
            walk.pause(2.5)
        }
        walk.picture("search")
    }

    /// The iPhone in light (the script turns the simulator to light first):
    /// Home, the library and Now Playing. Now Playing is dark by design, so
    /// its picture shows the cover's presentation staying dark over a light
    /// app.
    @MainActor
    func testPhoneLight() throws {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        try XCTSkipUnless(isPhone, "The iPad has its own walk, testPad.")
        let walk = Walk(test: self, name: "phone-light", prefix: "light-")
        defer { walk.finish() }

        try walk.launch()
        guard try walk.signIn(takingPictures: false) else { return }
        walk.waitForLibrary()
        walk.picture("home")

        try walk.tab("Library")
        walk.picture("library")

        try walk.tab("Home")
        _ = try walk.startYourStation()
        let nowPlaying = try walk.openNowPlaying()
        walk.picture("now-playing")
        if nowPlaying { try walk.closeNowPlaying() }
        walk.picture("home-playing")
    }

    /// The iPad, held sideways as on a stand, in dark: the sign-in, Home, an
    /// album's page and Now Playing in its wide layout.
    @MainActor
    func testPad() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        try XCTSkipUnless(isPad, "The iPhone has its own walk, testPhone.")
        XCUIDevice.shared.orientation = .landscapeLeft
        let walk = Walk(test: self, name: "pad")
        defer { walk.finish() }
        let app = walk.app

        try walk.launch()
        guard try walk.signIn(takingPictures: true) else { return }
        walk.waitForLibrary()
        walk.picture("home")

        try walk.tab("Library")
        walk.picture("library")
        let albums = try walk.push("Albums")
        var album = false
        if albums, let tile = walk.firstTile("Albums: an album's cover") {
            album = try walk.tap(tile, "Albums: open an album")
            if album { walk.pause(3) }
        }
        walk.picture("album")
        if album { try walk.goBack(to: "Albums") }
        if albums { try walk.goBack(to: "Library") }

        try walk.tab("Home")
        _ = try walk.startYourStation()
        let nowPlaying = try walk.openNowPlaying()
        walk.picture("now-playing")
        if nowPlaying {
            if try walk.tap(app.buttons["Up Next"], "Now Playing: Up Next") {
                walk.pause(2)
                walk.picture("queue")
            }
        }
    }
}

/// One walk through the app: the app, the pictures taken so far, and the
/// steps that found nothing.
@MainActor
final class Walk {
    let app = XCUIApplication()
    /// The first artist the Artists list shows: a word of it is what the
    /// search types, so the search finds something in whatever library the
    /// fake server has.
    var artistName: String?

    private let test: XCTestCase
    private let name: String
    private let prefix: String
    private var count = 0
    private var lastPicture = "the start"
    private var missed: [String] = []
    /// Where ci/screenshots.sh wants every picture as a file as well
    /// (JUKEBOX_SHOTS, from its TEST_RUNNER_JUKEBOX_SHOTS), or nil. The
    /// simulator's processes write to the Mac's own disk, so the pictures
    /// taken are there even when the test runner is stopped before its
    /// result bundle is whole, and whatever layout xcresulttool exports in.
    private let folder: URL? = {
        guard let path = ProcessInfo.processInfo.environment["JUKEBOX_SHOTS"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// `name` names the missed list's attachment ("missed-phone");
    /// `prefix` goes before each picture's number ("light-01-home").
    init(test: XCTestCase, name: String, prefix: String = "") {
        self.test = test
        self.name = name
        self.prefix = prefix
    }

    // MARK: Pictures and notes

    /// The whole screen as it is, kept with the test's results under
    /// `NN-what`; the script names the PNG after it.
    func picture(_ what: String) {
        count += 1
        let title = prefix + String(format: "%02d-", count) + what
        lastPicture = title
        // An iPad held sideways comes back as the panel's pixels, portrait,
        // with the turn only in the image's orientation, which the PNG of an
        // attachment ignores. Drawn again, the turn is applied and the
        // picture stands up (Numa-mac's walk found this on the iPad).
        let raw = XCUIScreen.main.screenshot().image
        let format = UIGraphicsImageRendererFormat()
        format.scale = raw.scale
        let upright = UIGraphicsImageRenderer(size: raw.size, format: format).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: raw.size))
        }
        let attachment = XCTAttachment(image: upright)
        attachment.name = title
        attachment.lifetime = .keepAlways
        test.add(attachment)
        if let folder = folder, let png = upright.pngData() {
            try? png.write(to: folder.appendingPathComponent(title + ".png"), options: .atomic)
        }
        print("PICTURE: \(title)")
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
        attachment.name = "missed-" + name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        saveMissed()
    }

    private var missedText: String {
        missed.isEmpty ? "Nothing missed." : missed.joined(separator: "\n")
    }

    private func saveMissed() {
        guard let folder = folder else { return }
        try? (missedText + "\n").write(to: folder.appendingPathComponent("missed-" + name + ".txt"),
                                       atomically: true, encoding: .utf8)
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: The app

    func launch() throws {
        // English and the US region, whatever the simulator was set to: the
        // labels this walk looks for are the app's English words.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        try alive("launch")
    }

    /// Throws, and fails the test, when the app is no longer running: it
    /// crashed. The one way this walk fails.
    func alive(_ step: String) throws {
        if app.state == .runningForeground { return }
        // Sent to the background (a system sheet took over): back to it.
        if app.state == .runningBackground || app.state == .runningBackgroundSuspended {
            app.activate()
            pause(2)
            if app.state == .runningForeground { return }
        }
        let message = "Jukebox stopped running at “\(step)” (state \(app.state.rawValue))"
        note(message)
        XCTFail(message)
        throw NSError(domain: "ScreenshotTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: Finding and tapping

    /// Waits until one of `elements` is there; false after `timeout`.
    func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if elements.contains(where: { $0.exists }) { return true }
            pause(0.5)
        } while Date() < deadline
        return false
    }

    /// Waits for `element`; when it does not come, the step is written down.
    @discardableResult
    func find(_ element: XCUIElement, _ step: String, timeout: TimeInterval = 10) -> Bool {
        if element.firstMatch.waitForExistence(timeout: timeout) { return true }
        note("\(step): not found within \(Int(timeout)) s")
        return false
    }

    /// Whether the middle of `element` is on the screen. In a ScrollView an
    /// element exists far below the screen, where a tap would miss.
    func onScreen(_ element: XCUIElement) -> Bool {
        XCTExpectFailure("Where an element is, for the screenshot walk", strict: false) { () -> Bool in
            guard element.exists else { return false }
            let frame = element.frame
            return !frame.isEmpty && self.app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    func isHittable(_ element: XCUIElement) -> Bool {
        XCTExpectFailure("Whether an element can be tapped, for the screenshot walk", strict: false) { () -> Bool in
            element.exists && element.isHittable
        }
    }

    /// The words of an element (a list row's), or nil.
    func label(of element: XCUIElement) -> String? {
        XCTExpectFailure("An element's words, for the screenshot walk", strict: false) { () -> String? in
            guard element.exists else { return nil }
            let own = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !own.isEmpty { return own }
            let text = element.staticTexts.firstMatch
            return text.exists ? text.label : nil
        }
    }

    /// Scrolls until `element` is on the screen: down the page when it lies
    /// below, up when above (Home scrolled). Three swipes at most.
    func reveal(_ element: XCUIElement) {
        for _ in 0..<3 {
            if onScreen(element) { return }
            let above = XCTExpectFailure("Where an element is, for the screenshot walk", strict: false) { () -> Bool in
                element.exists && element.frame.midY < self.app.frame.midY
            }
            XCTExpectFailure("A swipe of the screenshot walk", strict: false) {
                if above { self.app.swipeDown() } else { self.app.swipeUp() }
            }
            pause(1)
        }
    }

    /// Taps `element` when it is there to be tapped. When it is not, the
    /// step is written down and the walk goes on. False when nothing was
    /// tapped.
    @discardableResult
    func tap(_ element: XCUIElement, _ step: String, timeout: TimeInterval = 10) throws -> Bool {
        let element = element.firstMatch
        guard element.waitForExistence(timeout: timeout) else {
            note("\(step): not found within \(Int(timeout)) s")
            try alive(step)
            return false
        }
        if !onScreen(element) { reveal(element) }
        guard onScreen(element) else {
            note("\(step): found, but not on the screen")
            return false
        }
        XCTExpectFailure("A tap of the screenshot walk", strict: false) {
            if element.isHittable {
                element.tap()
            } else {
                // Under something clear (a glass bar's edge) `tap()` refuses;
                // a touch at its middle still lands, as a finger's would.
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
        try alive(step)
        return true
    }

    /// Types `text` into a field. With `tapping`, the field is tapped first
    /// for the keyboard's focus; without, the focus is expected to be there
    /// already (Return moved it on). What the field holds already is kept
    /// when it is `text` (the address and the user name are remembered from
    /// the last sign-in), and deleted when it is something else.
    @discardableResult
    func enter(_ text: String, into field: XCUIElement, _ step: String, tapping: Bool = true) throws -> Bool {
        let field = field.firstMatch
        guard field.waitForExistence(timeout: 10) else {
            note("\(step): no field")
            return false
        }
        XCTExpectFailure("Typing in the screenshot walk", strict: false) {
            let current = field.value as? String ?? ""
            if tapping {
                field.tap()
                // The keyboard's focus arrives a moment after the tap.
                self.pause(0.8)
            }
            if current == text { return }
            // An empty field's value is its placeholder: nothing to delete.
            if !current.isEmpty, current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
            }
            field.typeText(text)
        }
        try alive(step)
        return true
    }

    /// Return in the field that has the focus: the form's own Go and Next.
    /// A thumb does that, and a button may lie under the keyboard.
    func pressReturn(in field: XCUIElement) {
        XCTExpectFailure("Return in the screenshot walk", strict: false) {
            field.firstMatch.typeText("\n")
        }
    }

    func swipe(up: Bool) throws {
        XCTExpectFailure("A swipe of the screenshot walk", strict: false) {
            if up { self.app.swipeUp() } else { self.app.swipeDown() }
        }
        pause(2)
        try alive(up ? "swipe up" : "swipe down")
    }

    /// A drag from `from` to `to`, in fractions of the screen.
    func drag(from: CGVector, to: CGVector) {
        XCTExpectFailure("A drag of the screenshot walk", strict: false) {
            let start = self.app.coordinate(withNormalizedOffset: from)
            start.press(forDuration: 0.1, thenDragTo: self.app.coordinate(withNormalizedOffset: to))
        }
    }

    // MARK: Going places

    /// A tab: on the iPhone from the tab bar, on the iPad from its bar at
    /// the top or its sidebar, whichever the system shows.
    @discardableResult
    func tab(_ label: String) throws -> Bool {
        let byLabel = NSPredicate(format: "label == %@", label)
        let candidates = [
            app.tabBars.buttons.matching(byLabel).firstMatch,
            app.buttons.matching(byLabel).firstMatch,
            app.cells.matching(byLabel).firstMatch,
        ]
        for (i, candidate) in candidates.enumerated() {
            guard candidate.waitForExistence(timeout: i == 0 ? 5 : 1) else { continue }
            if !isHittable(candidate) {
                // A tab bar minimised by scrolling shows the current tab
                // only; scrolling back up brings the others back.
                try swipe(up: false)
            }
            if try tap(candidate, "the \(label) tab", timeout: 1) {
                pause(2)
                return true
            }
        }
        note("no \(label) tab")
        return false
    }

    /// One of the Library's kinds (Albums, Artists, Playlists): its row,
    /// then its page. False when the row was not there.
    func push(_ label: String) throws -> Bool {
        guard try tap(app.buttons[label], "Library: \(label)") else { return false }
        if !app.navigationBars[label].firstMatch.waitForExistence(timeout: 8) {
            note("Library: \(label) has no navigation bar named \(label)")
        }
        pause(2)
        return true
    }

    /// Back one page, to `previous`: the navigation bar's back button,
    /// named after the page it goes back to (or "Back"); else the bar's
    /// first button when it sits at the leading edge and is no other kind
    /// of button (Home's Settings, the iPad's sidebar); else the edge swipe
    /// a thumb would make.
    func goBack(to previous: String) throws {
        let step = "back to \(previous)"
        let named = app.navigationBars.buttons
            .matching(NSPredicate(format: "label == %@ OR label == %@", previous, "Back")).firstMatch
        var went = false
        if named.waitForExistence(timeout: 3) {
            went = try tap(named, step, timeout: 1)
        } else {
            let first = app.navigationBars.buttons.element(boundBy: 0)
            let isBack = XCTExpectFailure("The back button, for the screenshot walk", strict: false) { () -> Bool in
                guard first.exists else { return false }
                let label = first.label.lowercased()
                return first.frame.minX < self.app.frame.width * 0.25
                    && label != "settings" && !label.contains("sidebar")
            }
            if isBack { went = try tap(first, step, timeout: 1) }
        }
        if !went {
            drag(from: CGVector(dx: 0.01, dy: 0.5), to: CGVector(dx: 0.85, dy: 0.5))
        }
        pause(1.5)
        try alive(step)
    }

    /// The first album of a grid of covers: the first wide button on the
    /// screen inside its scroll view, else anywhere above the tab bar.
    func firstTile(_ step: String) -> XCUIElement? {
        let inGrid = app.scrollViews.firstMatch.buttons
        if inGrid.firstMatch.waitForExistence(timeout: 15), let tile = firstLarge(inGrid, minWidth: 100) {
            return tile
        }
        if let tile = firstLarge(app.buttons, minWidth: 120) { return tile }
        note("\(step): none on the screen")
        return nil
    }

    /// The first row of a list (Artists).
    func firstRow(_ step: String) -> XCUIElement? {
        let cells = app.cells
        if cells.firstMatch.waitForExistence(timeout: 15), let row = firstLarge(cells, minWidth: 200) {
            return row
        }
        note("\(step): no row on the screen")
        return nil
    }

    /// Of the first twelve elements of `query`, the first that is on the
    /// screen, at least `minWidth` points wide (a cover or a row, not a
    /// glyph), below the navigation bar (where the iPad keeps its tabs) and
    /// above the bottom fifth (the iPhone's tab bar and the mini player),
    /// and not a tab.
    private func firstLarge(_ query: XCUIElementQuery, minWidth: CGFloat) -> XCUIElement? {
        XCTExpectFailure("Looking through elements, for the screenshot walk", strict: false) { () -> XCUIElement? in
            let bar = self.app.navigationBars.firstMatch
            let top = bar.exists ? bar.frame.maxY - 1 : 0
            let bottom = self.app.frame.height * 0.8
            let tabs = ["Home", "Radio", "Library", "Search"]
            for i in 0..<min(query.count, 12) {
                let element = query.element(boundBy: i)
                guard element.exists, !tabs.contains(element.label) else { continue }
                let frame = element.frame
                if frame.width >= minWidth, frame.minY >= top, frame.midY < bottom, self.onScreen(element) {
                    return element
                }
            }
            return nil
        }
    }

    /// Closes a sheet with its button (Cancel, Done), or pulls it down.
    func closeSheet(with label: String) throws {
        if try tap(app.buttons[label], "the sheet's \(label)", timeout: 4) {
            pause(1.5)
            return
        }
        drag(from: CGVector(dx: 0.5, dy: 0.12), to: CGVector(dx: 0.5, dy: 0.95))
        pause(1.5)
        try alive("closing the sheet")
    }

    // MARK: Signing in

    /// Signs in to the fake Jellyfin as a listener would: the address, then
    /// the user name and the password, each ended with Return. With
    /// `takingPictures`, the welcome, the address typed, and the account
    /// step. True once Home is there; already signed in (the keychain kept
    /// the last walk's session), at once.
    func signIn(takingPictures: Bool) throws -> Bool {
        // Signs of the tabs: Home's bar, its tab, or its card.
        let home = [app.navigationBars["Home"].firstMatch, app.tabBars.buttons["Home"].firstMatch,
                    app.staticTexts["Your Station"].firstMatch]
        let address = app.textFields.firstMatch
        var onboarding = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if home.contains(where: { $0.exists }) { return true }
            if address.exists {
                onboarding = true
                break
            }
            pause(0.5)
        }
        guard onboarding else {
            note("launch: neither the welcome nor Home within 30 s")
            picture("launch")
            try alive("launch")
            return false
        }

        // The eclipse's intro has settled.
        pause(2.5)
        if takingPictures { picture("onboarding") }
        try enter("localhost:8096", into: address, "Welcome: the server's address")
        if takingPictures { picture("onboarding-server") }
        pressReturn(in: address)

        let password = app.secureTextFields.firstMatch
        if !password.waitForExistence(timeout: 30) {
            note("Welcome: Return did not go on to the account step")
            try tap(app.buttons["Continue"], "Welcome: Continue", timeout: 2)
        }
        guard password.waitForExistence(timeout: 30) else {
            note("Welcome: no account step (is the fake Jellyfin answering on localhost:8096?)")
            picture("onboarding-server-error")
            return false
        }
        // Both steps are on the screen while they cross-fade.
        pause(1.5)

        let user = app.textFields.firstMatch
        try enter("test", into: user, "Sign in: the user name")
        // Return moves on to the password, as the form does it.
        pressReturn(in: user)
        pause(0.8)
        try enter("test", into: password, "Sign in: the password", tapping: false)
        let typed = XCTExpectFailure("The password's dots, for the screenshot walk", strict: false) { () -> String in
            password.value as? String ?? ""
        }
        if !typed.contains("•") {
            // The focus did not move with Return: tapped, as a finger would,
            // and emptied first, so a password typed but not shown as dots
            // is not typed twice.
            if try tap(password, "Sign in: the password field", timeout: 2) {
                XCTExpectFailure("Typing in the screenshot walk", strict: false) {
                    password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "test")
                }
            }
        }
        if takingPictures { picture("sign-in") }
        pressReturn(in: password)

        dismissSavePassword(wait: 3)
        if !waitForAny(home, timeout: 45) {
            note("Sign in: Return did not sign in within 45 s")
            try tap(app.buttons["Sign In"], "Sign in: Sign In", timeout: 2)
        }
        guard waitForAny(home, timeout: 60) else {
            note("Sign in: Home did not come (the fake Jellyfin's log says what it was asked)")
            picture("sign-in-error")
            return false
        }
        return true
    }

    /// iOS may offer to save the password just typed: Not Now, so the sheet
    /// is not over the pictures that follow.
    func dismissSavePassword(wait: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for button in [app.buttons["Not Now"].firstMatch, springboard.buttons["Not Now"].firstMatch] {
            if button.waitForExistence(timeout: wait) {
                XCTExpectFailure("Not Now, for the screenshot walk", strict: false) {
                    button.tap()
                }
                pause(1)
                return
            }
        }
    }

    /// Home with the library read (Your Station's card, or a shelf), then
    /// the mixes made (their grey placeholders gone) and a moment for the
    /// covers. A library that does not come is written down and the walk
    /// goes on: the other screens' pictures then show how the app says so.
    func waitForLibrary() {
        let loaded = [app.staticTexts["Your Station"].firstMatch, app.staticTexts["Made for You"].firstMatch,
                      app.staticTexts["Recently Added"].firstMatch]
        if !waitForAny(loaded, timeout: 150) {
            note("Home: the library did not load within 150 s (no Your Station, no shelves)")
            return
        }
        let making = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Making your mixes")).firstMatch
        let deadline = Date().addingTimeInterval(45)
        while making.exists && Date() < deadline {
            pause(1)
        }
        if making.exists { note("Home: the mixes were still being made after 45 s") }
        pause(4)
        dismissSavePassword(wait: 0.5)
    }

    // MARK: Playing

    /// Your Station from Home's card. Its Play is the one enabled Play on
    /// Home while nothing plays (the mini player's is greyed out then), and
    /// the highest on the screen. True when it was tapped.
    func startYourStation() throws -> Bool {
        let card = app.staticTexts["Your Station"].firstMatch
        guard find(card, "Home: Your Station's card", timeout: 15) else { return false }
        if !onScreen(card) { reveal(card) }
        guard let play = highestEnabledButton("Play") else {
            note("Home: no enabled Play on Your Station's card")
            return false
        }
        guard try tap(play, "Home: Your Station's Play") else { return false }
        // Playing: the card's button and the mini player's say Pause.
        if !app.buttons["Pause"].firstMatch.waitForExistence(timeout: 45) {
            note("Your Station: nothing was playing 45 s after Play")
        }
        pause(3)
        return true
    }

    /// Of the enabled buttons labelled `label`, the one highest on the screen.
    private func highestEnabledButton(_ label: String) -> XCUIElement? {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        return XCTExpectFailure("Looking through buttons, for the screenshot walk", strict: false) { () -> XCUIElement? in
            var best: XCUIElement?
            var bestY = CGFloat.greatestFiniteMagnitude
            for i in 0..<min(matches.count, 8) {
                let button = matches.element(boundBy: i)
                guard button.exists, button.isEnabled else { continue }
                let y = button.frame.minY
                if y < bestY {
                    best = button
                    bestY = y
                }
            }
            return best
        }
    }

    /// Now Playing, from Home's card while its station is on the air (a tap
    /// anywhere on the card but its button opens it), else from the mini
    /// player. True once its Close button is there.
    func openNowPlaying() throws -> Bool {
        let close = app.buttons["Close"].firstMatch
        let onAir = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Now Playing")).firstMatch
        if onAir.waitForExistence(timeout: 5),
           try tap(onAir, "Home: the card of the station on the air"),
           close.waitForExistence(timeout: 8) {
            pause(3)
            return true
        }
        // The mini player's titles lie left of its play and next buttons
        // (each 40 points wide); its own label is the song, unknown here.
        let next = app.buttons["Next"].firstMatch
        if next.waitForExistence(timeout: 3) {
            XCTExpectFailure("The mini player, for the screenshot walk", strict: false) {
                next.coordinate(withNormalizedOffset: CGVector(dx: -3, dy: 0.5)).tap()
            }
            try alive("the mini player")
            if close.waitForExistence(timeout: 8) {
                pause(3)
                return true
            }
        }
        note("Now Playing did not open, from Home's card nor from the mini player")
        return false
    }

    /// Closes Now Playing with its chevron, or pulls it down by the top.
    func closeNowPlaying() throws {
        if try tap(app.buttons["Close"], "Now Playing: Close", timeout: 3) {
            pause(2)
            return
        }
        drag(from: CGVector(dx: 0.5, dy: 0.1), to: CGVector(dx: 0.5, dy: 0.9))
        pause(2)
        try alive("closing Now Playing")
    }

    /// What the search types: JUKEBOX_SEARCH when the script gives one
    /// (TEST_RUNNER_JUKEBOX_SEARCH), else a word of the first artist's name,
    /// else "a".
    var searchTerm: String {
        if let given = ProcessInfo.processInfo.environment["JUKEBOX_SEARCH"], !given.isEmpty {
            return given
        }
        // Words only: a row's label may carry a comma or a semicolon
        // ("Amsterdam Strings; Clara Venn"), which a search would not match.
        let words = (artistName ?? "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let word = words.first(where: { $0.count >= 3 && $0.lowercased() != "the" })
        return word ?? words.first ?? "a"
    }
}
