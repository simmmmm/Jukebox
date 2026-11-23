// The screenshot walk: Jukebox used as a listener would use it, in the iOS
// Simulator on GitHub's Mac, against the fake Jellyfin of
// dev/fake-jellyfin.swift on localhost. Every main screen of the iPhone in dark
// (`testPhone`), Home and Now Playing again in light (`testPhoneLight`),
// Linux's walk on an iPad held sideways (`testPad`), and the narrowest wide
// window on an 11-inch iPad held upright (`testPadUpright`).
// ci/screenshots.sh runs each on its own simulator and appearance, exports
// the pictures and makes the contact sheets. There is no Mac here, so nobody
// has seen the app; the photographer asked for pictures ("Als je plaatjes
// hebt om te delen zie ik ze graag"), and the lead needs them to see what to
// fix. The Mac's own walk, for the Mac App Store's pictures, is
// MacScreenshotTests.swift; the iPad's pictures stand for the wide layout.
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
// its Text, Label and accessibilityLabel), and on the iPad by the few
// accessibility identifiers the wide layout sets for this walk: the
// sidebar's `place.<name>`, the player bar's `bar.song`, `bar.upNext` and
// `bar.lyrics`, Now Playing's `nowPlaying.close`. When the app's words
// change, or an identifier is not there, the step is missed (a skip, with the
// identifier's name) and the missed list says which one.

#if os(iOS)
import UIKit
import XCTest

final class ScreenshotTests: XCTestCase {
    /// The iPhone, in dark: the welcome and the sign-in, Home, Radio, a
    /// station's page before it plays, the library and its pages, Settings,
    /// Your Station started from Home, Now Playing with its lyrics and its
    /// queue, the mini player above the tabs, a station's page on the air,
    /// and a search.
    @MainActor
    func testPhone() throws {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        try XCTSkipUnless(isPhone, "The iPad has its own walk, testPad.")
        let walk = Walk(test: self, name: "phone")
        defer { walk.finish() }
        let app = walk.app

        // Now Playing as most see it, D2's land, though the simulator has
        // Reduce Motion on (ci/screenshots.sh), which shows D1: the land
        // standing still. The light walk keeps D1, the wall.
        try walk.launch(extra: ["-showLandStill", "YES"])
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

        // A station's card opens its page: what the radio made of it, before
        // anything plays (the photographer, 8 November 2026: "ipv dat je
        // kan zien wat je van de playlist gemaakt hebt"). Then its songs.
        let station = try walk.openStation("Discovery")
        walk.picture("station-page")
        if station {
            try walk.swipe(up: true)
            walk.picture("station-page-songs")
            try walk.goBack(to: "Radio")
        }

        let picking = try walk.tap(app.buttons["Start a Station"], "Radio: Start a Station")
        if picking { walk.pause(2) }
        walk.picture("radio-start-a-station")
        // Choosing a station in the sheet closes it and opens the station's
        // page on the Radio tab.
        var picked = false
        // A suggested station's row, by its name ("… Radio"): the first cell
        // of the sheet can be the space by its search field (run 22).
        if picking {
            let station = app.buttons.matching(NSPredicate(format: "label CONTAINS ' Radio'")).firstMatch
            if station.waitForExistence(timeout: 10) {
                picked = try walk.tap(station, "Start a Station: choose a station")
            } else if let row = walk.firstRow("Start a Station: a suggested station") {
                picked = try walk.tap(row, "Start a Station: choose a station")
            }
        }
        if picked {
            walk.pause(2)
            if walk.find(app.buttons["New Picks"], "Start a Station: the chosen station's page") { walk.pause(2) }
            walk.picture("station-picked")
            // The sheet still up (the tap went elsewhere): closed as before.
            if app.buttons["Cancel"].exists { try walk.closeSheet(with: "Cancel") }
            try walk.goBack(to: "Radio")
        } else if picking {
            try walk.closeSheet(with: "Cancel")
        }

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
        // Accounts: each account kept a card, one signed in (the walk keeps one).
        if settings, try walk.openSettingsPage("accounts", "Accounts") {
            walk.picture("settings-accounts")
            try walk.tap(app.navigationBars["Accounts"].buttons.element(boundBy: 0), "Settings › Accounts: back", timeout: 2)
            walk.pause(1)
        }
        // Settings is a list of pages: one of them open, then back to it.
        if settings, try walk.openSettingsPage("playback", "Playback") {
            walk.picture("settings-playback")
            // Its bar's first button: "Settings" is also Home's own, under the sheet.
            try walk.tap(app.navigationBars["Playback"].buttons.element(boundBy: 0), "Settings › Playback: back", timeout: 2)
            walk.pause(1)
        }
        // Radio: the dial, Enhance Radio and the Last.fm username.
        if settings, try walk.openSettingsPage("radio", "Radio") {
            walk.picture("settings-radio")
            try walk.tap(app.navigationBars["Radio"].buttons.element(boundBy: 0), "Settings › Radio: back", timeout: 2)
            walk.pause(1)
        }
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
        // Your Station's page while it plays, from its row under Stations:
        // the song playing and what the radio has queued.
        if try walk.openStation("Your Station") {
            walk.picture("station-on-air")
            try walk.goBack(to: "Radio")
        } else {
            walk.picture("station-on-air")
        }

        // An album while a song plays: the version filter's menu on the
        // demo's album of remastered and unplugged songs, Remastered turned
        // off, then the page's end clear of the mini player and the tabs
        // (the photographer's TestFlight 1.3, 22 November 2026).
        try walk.tab("Library")
        if try walk.push("Albums") {
            if try walk.openAlbum("Lantern Hours") {
                if try walk.tap(app.buttons["page.versions"].firstMatch, "Album: the version filter") {
                    walk.pause(1.5)
                    walk.picture("album-versions-menu")
                    if try walk.tap(app.buttons["Remastered"].firstMatch, "Album: Remastered off", timeout: 3) {
                        walk.pause(1)
                        walk.picture("album-versions-off")
                    }
                    // Away from the menu: a tap on the page's cover.
                    XCTExpectFailure("Closing a menu in the screenshot walk", strict: false) {
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
                    }
                    walk.pause(1)
                }
                try walk.swipe(up: true)
                try walk.swipe(up: true)
                try walk.swipe(up: true)
                walk.picture("album-bottom")
                try walk.goBack(to: "Albums")
            }
            try walk.goBack(to: "Library")
        }

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

    /// The iPad, held sideways as on a stand (1376 wide, the nearest to
    /// Linux's 1440), in dark: Linux's walk (Linux/App/Shots.swift) step for
    /// step, each picture named as Linux names its twin in
    /// linux-screens/1440x900-dark, so the two lie side by side ("ik wil dat
    /// de linux app en de apple app 1:1 op elkaar lijken", the photographer,
    /// 14 November 2026). Linux's sign-in is its last picture; here it is the
    /// first thing done, and keeps its name. Search typed in the bar comes
    /// after Settings, so no picture before it shows the term; the sidebar
    /// with fewer places last, as it needs a launch of its own.
    ///
    /// It goes by the sidebar's places and the bar's buttons only, never by
    /// tabs or back buttons: an edge drag over a sidebar would press a place.
    /// A place, button or close that is not there is a skip in the missed
    /// list, the picture is taken anyway, and the walk goes on.
    @MainActor
    func testPad() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        try XCTSkipUnless(isPad, "The iPhone has its own walk, testPhone.")
        XCUIDevice.shared.orientation = .landscapeLeft
        let walk = Walk(test: self, name: "pad", numbered: false)
        defer { walk.finish() }
        let app = walk.app

        // D2's land, standing still (see testPhone). The panel closed, as a
        // listener first finds it, whatever an earlier launch left: the
        // argument domain wins over what PanelState remembered.
        try walk.launch(extra: ["-showLandStill", "YES", "-panelOpen", "NO"])
        guard try walk.signIn(takingPictures: true,
                              names: ["17-sign-in", "17b-sign-in-address", "17c-sign-in-filled"])
        else { return }
        walk.waitForLibrary()
        walk.picture("01-home")

        let radio = try walk.place("radio")
        walk.picture("02-radio")
        if radio { _ = try walk.openStation("Your Station") }
        walk.picture("03-station")

        let albums = try walk.place("albums")
        walk.picture("04-albums")
        if albums { _ = try walk.openAlbum(nil) }
        walk.picture("05-album")

        // Linux's artists are covers in a grid; rows, should they be a list.
        if try walk.place("artists"),
           let artist = walk.firstTile("Artists: an artist") ?? walk.firstRow("Artists: an artist") {
            // A word of it is what the search types at the end.
            walk.artistName = walk.label(of: artist)
            if try walk.tap(artist, "Artists: open an artist") { walk.pause(3) }
        }
        walk.picture("06-artist")

        try walk.place("songs")
        walk.picture("07-songs")
        try walk.place("playlists")
        walk.picture("08-playlists")

        // Music, as Linux's walk has it: Dust Windows playing on Home, then
        // Up Next in the panel over the albums and over another album's page:
        // the first cover, Dust Parades, where Linux opens Quiet Rooms, which
        // lies far down the grid. (Linux also queues two songs from
        // elsewhere; a walk that taps has no quick way to.)
        if try walk.place("albums"), try walk.openAlbum("Dust Windows") {
            _ = try walk.play("Dust Windows: Play")
        }
        try walk.place("home")
        walk.picture("09-home-playing")
        try walk.showPanel("upNext")
        let albumsBeside = try walk.place("albums")
        walk.picture("10a-albums-panel")
        if albumsBeside { _ = try walk.openAlbum(nil) }
        walk.picture("10-album-up-next")
        // Now Playing as the room, from the bar's song, Up Next beside it;
        // then its More.
        let room = try walk.openRoom()
        walk.picture("10b-now-playing")
        if room {
            let menu = try walk.openRoomMenu()
            walk.picture("10c-now-playing-menu")
            if menu { walk.dismissMenu() }
            try walk.closeRoom()
        }

        // The panel on the words: Silver Roads begins with Night Drive, whose
        // lyrics are timed (dev/demo/lyrics.json).
        if try walk.place("albums"), try walk.openAlbum("Silver Roads"), try walk.play("Silver Roads: Play") {
            walk.waitForSong("Night Drive")
        }
        try walk.showPanel("lyrics")
        walk.picture("11-album-lyrics")
        let words = try walk.openRoom()
        walk.picture("12-now-playing-lyrics")
        if words { try walk.closeRoom() }

        // Your Station on the air, the panel closed; then the panel with what
        // the radio queued, and the room with the station's song.
        try walk.closePanel()
        try walk.place("home")
        _ = try walk.startYourStation()
        try walk.place("radio")
        walk.picture("13-radio-on-air")
        try walk.showPanel("upNext")
        walk.picture("14-radio-up-next")
        let station = try walk.openRoom()
        walk.picture("15-now-playing-station")
        if station { try walk.closeRoom() }

        try walk.place("home")
        let settings = try walk.openSettings()
        walk.picture("16-preferences")
        if settings {
            // The page with Pages, as Linux's 16c opens its Preferences' Library.
            if try walk.openSettingsPage("library", "Library") {
                let pages = app.switches["Playlists in the Sidebar"].firstMatch
                for _ in 0..<2 where !walk.onScreen(pages) {
                    try walk.swipe(up: true)
                }
                if !walk.onScreen(pages) { walk.note("Settings › Library: no Pages switches after two swipes") }
            }
            walk.picture("16c-preferences-pages")
            try walk.closeSheet(with: "Done")
        }

        // Search is the window bar's field (`.searchable` in the toolbar),
        // where Linux's header has it; typed in, the Search page shows.
        // Linux's twin (08c-search-query) types "blue", so this does too.
        // Return sends the keyboard away: Linux's window has none over its bar.
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 5) {
            walk.note("Search: no field in the bar within 5 s; its Search button instead")
            try walk.tap(app.buttons["Search"], "Search: the bar's Search button", timeout: 2)
        }
        if field.waitForExistence(timeout: 3) {
            let given = ProcessInfo.processInfo.environment["JUKEBOX_SEARCH"] ?? ""
            try walk.enter(given.isEmpty ? "blue" : given, into: field, "Search: typing a term")
            walk.pressReturn(in: field)
            walk.pause(2.5)
        } else {
            walk.note("Search: no field in the bar")
        }
        walk.picture("08c-search-query")

        // A sidebar with fewer places (Settings › Pages), as Linux's 23:
        // launched again with the pages Linux's walk switches off in the
        // argument domain, which wins over what was chosen, and leaves it be.
        // The values are AppSettings.Page's raw ones; unquoted, as the
        // argument domain reads an array.
        app.terminate()
        try walk.launch(extra: ["-hiddenPages", "(radio,songs,favorites,genres,recently_added,sidebar_playlists)"])
        guard try walk.signIn(takingPictures: false) else { return }
        walk.waitForLibrary()
        try walk.place("albums")
        walk.picture("23-pages-trimmed")
    }

    /// The tightest wide window: an 11-inch iPad held upright, 834 points,
    /// still regular width, where the sidebar and the panel are open at
    /// once. Named after Linux's narrow walk (linux-screens/760x900-dark):
    /// Home, an album with Up Next beside it, and the places over it.
    @MainActor
    func testPadUpright() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        try XCTSkipUnless(isPad, "The iPhone has its own walk, testPhone.")
        XCUIDevice.shared.orientation = .portrait
        let walk = Walk(test: self, name: "pad-upright", numbered: false)
        defer { walk.finish() }

        try walk.launch(extra: ["-showLandStill", "YES", "-panelOpen", "NO"])
        guard try walk.signIn(takingPictures: false) else { return }
        walk.waitForLibrary()
        walk.picture("01-home")

        if try walk.place("albums"), try walk.openAlbum(nil) {
            _ = try walk.play("The album: Play")
        }
        try walk.showPanel("upNext")
        walk.picture("10-album-up-next")
        // The sidebar, folded away upright, shown over the page beside the
        // panel.
        walk.showSidebar()
        walk.picture("09-places-over")
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
    private let numbered: Bool
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
    /// Not `numbered`, each picture is named as the walk says, whole (the
    /// iPad's "10-album-up-next", its Linux twin's name).
    init(test: XCTestCase, name: String, prefix: String = "", numbered: Bool = true) {
        self.test = test
        self.name = name
        self.prefix = prefix
        self.numbered = numbered
    }

    // MARK: Pictures and notes

    /// The whole screen as it is, kept with the test's results under
    /// `NN-what` (or `what`, not numbered); the script names the PNG after it.
    func picture(_ what: String) {
        count += 1
        let title = prefix + (numbered ? String(format: "%02d-", count) : "") + what
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

    /// `extra`: launch arguments of one walk, such as `-showLandStill YES`.
    func launch(extra: [String] = []) throws {
        // English and the US region, whatever the simulator was set to: the
        // labels this walk looks for are the app's English words.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // No usage counts from CI's walk on the photographer's OpenPanel
        // (docs/STATS.md): the argument domain turns Share Anonymous Usage off.
        app.launchArguments += ["-shareUsage", "NO"]
        // The automatic keep off (docs/OFFLINE.md): it would fetch from the
        // fake server while the walk goes, and the pictures would differ by
        // how far it got.
        app.launchArguments += ["-keepSongs", "NO"]
        app.launchArguments += extra
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
            // The iPhone's tabs are Jukebox's own row (TabRow), by these; a
            // back button or the keyboard's key can have the same label.
            // The system's tab bar on the iPad.
            app.buttons.matching(identifier: "tab.\(label.lowercased())").firstMatch,
            app.tabBars.buttons.matching(byLabel).firstMatch,
            app.buttons.matching(byLabel).firstMatch,
            app.cells.matching(byLabel).firstMatch,
        ]
        // A tab bar minimised by scrolling (tabBarMinimizeBehavior) shows the
        // current tab only, and the others are not there at all, not merely
        // hidden: scrolling back up brings them back. Seen on run 22, where
        // every tab after a scrolled station page was "not found".
        for attempt in 0..<3 {
            for (i, candidate) in candidates.enumerated() {
                guard candidate.waitForExistence(timeout: attempt == 0 && i == 0 ? 5 : 1) else { continue }
                if !isHittable(candidate) {
                    try swipe(up: false)
                }
                if try tap(candidate, "the \(label) tab", timeout: 1) {
                    pause(2)
                    return true
                }
            }
            try swipe(up: false)
            try swipe(up: false)
            pause(1)
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
        // A tap lost while the simulator stalled leaves the page where it was
        // (run 43763579467: the picked station's page stayed, and the walk
        // after it went astray). Not at `previous` (its navigation bar, as
        // push checks) and a back button still there: once more.
        if !app.navigationBars[previous].firstMatch.waitForExistence(timeout: 10), named.exists {
            note("\(step): the page stayed, back once more")
            if try tap(named, step, timeout: 1) { pause(1.5) }
        }
    }

    /// The first album of a grid of covers: the first cover-shaped button on
    /// the screen inside a scroll view, else anywhere above the tab bar.
    /// Cover-shaped (at least nearly as tall as wide): beside a sidebar and
    /// a panel, their rows are wide buttons too. Not a place: the wide
    /// window's sidebar is a scroll view of buttons, before the page's.
    func firstTile(_ step: String) -> XCUIElement? {
        let notPlaces = NSPredicate(format: "NOT (identifier BEGINSWITH %@)", "place.")
        let inGrid = app.scrollViews.buttons.matching(notPlaces)
        if inGrid.firstMatch.waitForExistence(timeout: 15), let tile = firstLarge(inGrid, minWidth: 100, tall: true) {
            return tile
        }
        if let tile = firstLarge(app.buttons.matching(notPlaces), minWidth: 120, tall: true) { return tile }
        note("\(step): none on the screen")
        return nil
    }

    /// The first row of a list (Artists). At least 44 points tall: a
    /// section's letter is a cell of 40, and tapping it opens nothing (run
    /// 67: the "A" was tapped, no artist opened, and the walk lost its way
    /// to Playlists).
    func firstRow(_ step: String) -> XCUIElement? {
        let cells = app.cells
        if cells.firstMatch.waitForExistence(timeout: 15), let row = firstLarge(cells, minWidth: 200, minHeight: 44) {
            return row
        }
        note("\(step): no row on the screen")
        return nil
    }

    /// Of the first twelve elements of `query`, the first that is on the
    /// screen, at least `minWidth` points wide and `minHeight` tall (a cover
    /// or a row, not a glyph or a heading), with `tall` nearly as tall as
    /// wide, below the navigation bar (where the iPad keeps its tabs) and
    /// above the bottom fifth (the iPhone's tab bar and the mini player),
    /// and neither a tab nor a place of the sidebar.
    private func firstLarge(_ query: XCUIElementQuery, minWidth: CGFloat, minHeight: CGFloat = 0,
                            tall: Bool = false) -> XCUIElement? {
        XCTExpectFailure("Looking through elements, for the screenshot walk", strict: false) { () -> XCUIElement? in
            let bar = self.app.navigationBars.firstMatch
            let top = bar.exists ? bar.frame.maxY - 1 : 0
            let bottom = self.app.frame.height * 0.8
            let tabs = ["Home", "Radio", "Library", "Search"]
            for i in 0..<min(query.count, 12) {
                let element = query.element(boundBy: i)
                guard element.exists, !tabs.contains(element.label),
                      !element.identifier.hasPrefix("place.") else { continue }
                let frame = element.frame
                if frame.width >= minWidth, frame.height >= minHeight,
                   !tall || frame.height >= frame.width * 0.9,
                   frame.minY >= top, frame.midY < bottom, self.onScreen(element) {
                    return element
                }
            }
            return nil
        }
    }

    /// A station's page, from its row or tile on the Radio tab, found by
    /// the start of its label (a row's label is its title, then when it last
    /// played). True once the page is there — its New Picks, or while the
    /// station is on the air its "Up next" heading — after a moment for the
    /// songs to be chosen and their covers to come.
    func openStation(_ title: String) throws -> Bool {
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        guard try tap(link, "Radio: the \(title) station") else { return false }
        // "Up first" before it plays, on the wide window's page.
        let upNext = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@",
                                                          "Up next", "Up first")).firstMatch
        let page = [app.buttons["New Picks"].firstMatch, upNext]
        guard waitForAny(page, timeout: 10) else {
            note("Radio: the \(title) station's page did not open (no New Picks, no Up Next)")
            return false
        }
        pause(3)
        return true
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
    /// step, under `names`. True once Home is there; already signed in (the
    /// keychain kept the last walk's session), at once.
    func signIn(takingPictures: Bool,
                names: [String] = ["onboarding", "onboarding-server", "sign-in"]) throws -> Bool {
        // Signs of the tabs: Home's bar, its tab, or its card; the wide
        // window's Home in its sidebar.
        let home = [app.navigationBars["Home"].firstMatch, app.tabBars.buttons["Home"].firstMatch,
                    app.buttons["tab.home"].firstMatch,
                    app.staticTexts["Your Station"].firstMatch,
                    app.descendants(matching: .any).matching(identifier: "place.home").firstMatch]
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

        // The welcome's picture has settled: the mark on, the record out.
        pause(5)
        if takingPictures { picture(names[0]) }
        try enter(fakeServer, into: address, "Welcome: the server's address")
        if takingPictures { picture(names[1]) }
        pressReturn(in: address)

        let password = app.secureTextFields.firstMatch
        if !password.waitForExistence(timeout: 30) {
            note("Welcome: Return did not go on to the account step")
            try tap(app.buttons["Continue"], "Welcome: Continue", timeout: 2)
        }
        guard password.waitForExistence(timeout: 30) else {
            note("Welcome: no account step (is the fake Jellyfin answering on \(fakeServer)?)")
            picture("onboarding-server-error")
            return false
        }
        // Both steps are on the screen while they cross-fade.
        pause(1.5)

        // The wide window's sign-in is one page, its address the first
        // field: the user name by its identifier there.
        let named = app.textFields["signIn.user"].firstMatch
        let user = named.exists ? named : app.textFields.firstMatch
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
        if takingPictures { picture(names[2]) }
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
        try betterRadio(takingPicture: takingPictures)
        return true
    }

    /// Better Radio, the step after signing in: its picture, then Turn On,
    /// so the walk's radio is the one most will have. Not there (chosen in
    /// an earlier walk, a build without Jukebox's key): nothing to do.
    func betterRadio(takingPicture: Bool) throws {
        let turnOn = app.buttons["betterRadio.turnOn"].firstMatch
        guard turnOn.waitForExistence(timeout: 8) else { return }
        pause(1.5)
        if takingPicture { picture("better-radio") }
        _ = try tap(turnOn, "Better Radio: Turn On")
        pause(1)
    }

    /// iOS may offer to save the password just typed: Not Now, so the sheet
    /// is not over the pictures that follow.
    func dismissSavePassword(wait: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Not Better Radio's own Not Now (betterRadio.notNow), which would
        // turn Enhance Radio off for the walk.
        let ours = NSPredicate(format: "label == 'Not Now' AND identifier != 'betterRadio.notNow'")
        for button in [app.buttons.matching(ours).firstMatch, springboard.buttons["Not Now"].firstMatch] {
            if button.waitForExistence(timeout: wait) {
                XCTExpectFailure("Not Now, for the screenshot walk", strict: false) {
                    button.tap()
                }
                pause(1)
                return
            }
        }
    }

    /// Home with the library read (Your Station, or a shelf's heading),
    /// then the mixes made (their grey placeholders gone) and a moment for
    /// the covers. A library that does not come is written down and the
    /// walk goes on: the other screens' pictures then show how the app says so.
    func waitForLibrary() {
        let loaded = [app.staticTexts["Your Station"].firstMatch, app.staticTexts["Mixes"].firstMatch,
                      app.staticTexts["Recently added"].firstMatch]
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

    /// Your Station from the top of Home. Its Play is the one enabled Play
    /// on Home while nothing plays (the mini player's is greyed out then),
    /// and the highest on the screen. True when it was tapped.
    func startYourStation() throws -> Bool {
        let card = app.staticTexts["Your Station"].firstMatch
        guard find(card, "Home: Your Station's card", timeout: 15) else { return false }
        if !onScreen(card) { reveal(card) }
        // Home's card is one button since its Play became a word at its
        // foot ("het hele ding gewoon klikbaar maken"): labelled "Your
        // Station, …, Play", with no Play of its own to find.
        let whole = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Your Station")).firstMatch
        if whole.exists, whole.isEnabled {
            guard try tap(whole, "Home: Your Station's card") else { return false }
            if !app.buttons["Pause"].firstMatch.waitForExistence(timeout: 45) {
                note("Home: Your Station's card: nothing was playing 45 s after it")
            }
            pause(3)
            return true
        }
        return try play("Home: Your Station's Play")
    }

    /// The page's Play (Your Station's card, an album's head): the highest
    /// enabled Play on the screen. True when it was tapped.
    func play(_ step: String) throws -> Bool {
        guard let play = highestEnabledButton("Play") else {
            note("\(step): no enabled Play")
            return false
        }
        guard try tap(play, step) else { return false }
        // Playing: the page's button and the player's say Pause.
        if !app.buttons["Pause"].firstMatch.waitForExistence(timeout: 45) {
            note("\(step): nothing was playing 45 s after it")
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

    /// Now Playing, from Home's Your Station while its station is on the
    /// air (a tap anywhere on it but its button opens it; its label says
    /// "On air"), else from the mini player. True once its Close button is
    /// there.
    func openNowPlaying() throws -> Bool {
        let close = app.buttons["Close"].firstMatch
        let onAir = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@",
                                                         "On air", "Now Playing")).firstMatch
        if onAir.waitForExistence(timeout: 5),
           try tap(onAir, "Home: the card of the station on the air"),
           close.waitForExistence(timeout: 8) {
            pause(3)
            return true
        }
        // The mini player's titles: its own label is the song, unknown
        // here, so by its identifier (NowPlaying/MiniPlayer*.swift).
        let mini = app.buttons["mini-player"].firstMatch
        if mini.waitForExistence(timeout: 3) {
            XCTExpectFailure("The mini player, for the screenshot walk", strict: false) {
                mini.tap()
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

    // MARK: The wide window (the iPad's)

    /// The element the wide layout marks with `id` (`bar.song`,
    /// `place.albums`), whatever kind of element it was put on; nil after
    /// `timeout`, written down as a skip with the identifier's name. Where
    /// the wide layout is not there yet, every one is a short skip.
    func byID(_ id: String, timeout: TimeInterval = 4) -> XCUIElement? {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        if element.waitForExistence(timeout: timeout) { return element }
        note("skipped: no \(id) within \(Int(timeout)) s")
        return nil
    }

    /// A place of the sidebar (`place.<name>`), tapped. Folded away (an
    /// upright iPad: the places fold below 900 wide), the sidebar is shown
    /// first. Held sideways it never folds, and is not asked: each question
    /// is a snapshot of the whole window, which a busy app may not answer in
    /// time. True when it was tapped.
    @discardableResult
    func place(_ name: String) throws -> Bool {
        let id = "place." + name
        if XCUIDevice.shared.orientation.isPortrait,
           !app.descendants(matching: .any).matching(identifier: id).firstMatch.exists {
            showSidebar()
        }
        guard let found = byID(id, timeout: 3), try tap(found, id, timeout: 1) else { return false }
        pause(2)
        return true
    }

    /// The system's button that shows the sidebar, tapped when it is there
    /// to show it (not to hide it).
    func showSidebar() {
        let show = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND NOT (label CONTAINS[c] %@)",
                                                    "sidebar", "hide")).firstMatch
        guard show.waitForExistence(timeout: 2) else { return }
        XCTExpectFailure("The sidebar's button, for the screenshot walk", strict: false) {
            show.tap()
        }
        pause(1.5)
    }

    /// The panel on `content` ("upNext", "lyrics"), by the bar's button for
    /// it (`bar.upNext`, `bar.lyrics`). The buttons toggle (PanelState: the
    /// one lit closes the panel), so a lit one, said selected, is left be.
    func showPanel(_ content: String) throws {
        guard let button = byID("bar." + content), !isSelected(button) else { return }
        if try tap(button, "bar." + content, timeout: 1) { pause(2.5) }
    }

    /// The panel closed, by the bar's lit button.
    func closePanel() throws {
        for content in ["upNext", "lyrics"] {
            let button = app.descendants(matching: .any).matching(identifier: "bar." + content).firstMatch
            if isSelected(button) {
                if try tap(button, "bar." + content, timeout: 1) { pause(1.5) }
                return
            }
        }
    }

    /// Whether a bar's button is lit: the bar says so as the selected trait.
    func isSelected(_ element: XCUIElement) -> Bool {
        XCTExpectFailure("Whether a button is lit, for the screenshot walk", strict: false) { () -> Bool in
            element.exists && element.isSelected
        }
    }

    /// Now Playing's More (`nowPlaying.more`), opened. True when tapped.
    func openRoomMenu() throws -> Bool {
        guard let more = byID("nowPlaying.more", timeout: 2), try tap(more, "nowPlaying.more", timeout: 1) else {
            return false
        }
        pause(1.5)
        return true
    }

    /// A menu sent away as a finger does, by a touch beside it: the system's
    /// own place for that, else the room's empty top (a touch on its ground
    /// stays in the room).
    func dismissMenu() {
        let outside = app.otherElements["PopoverDismissRegion"].firstMatch
        XCTExpectFailure("Sending a menu away, for the screenshot walk", strict: false) {
            if outside.exists {
                outside.tap()
            } else {
                self.app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.05)).tap()
            }
        }
        pause(1.5)
    }

    /// An album's page from the albums' grid: the cover whose label begins
    /// with `name` (a cover says "Album, Artist"), else the first cover.
    /// The grid is lazy, a cover made only near the screen, so the walk goes
    /// down the page until it comes, eight swipes at most.
    func openAlbum(_ name: String?) throws -> Bool {
        var cover: XCUIElement?
        if let name {
            let named = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            var found = named.waitForExistence(timeout: 3)
            for _ in 0..<8 where !found {
                // Slowly, so that no row is flung past and let go.
                XCTExpectFailure("A swipe of the screenshot walk", strict: false) {
                    self.app.swipeUp(velocity: .slow)
                }
                found = named.waitForExistence(timeout: 1.5)
            }
            if found {
                cover = named
            } else {
                note("Albums: no cover of \(name) after eight swipes; the first on the screen instead")
            }
        }
        guard let tile = cover ?? firstTile("Albums: an album's cover") else { return false }
        let opened = try tap(tile, "Albums: open \(name ?? "the first album")")
        if opened { pause(3) }
        return opened
    }

    /// Now Playing as the room, from the bar's song (`bar.song`), waited
    /// for by its close (`nowPlaying.close`). True when the song was
    /// tapped: whatever came of it, the walk then tries to close it.
    func openRoom() throws -> Bool {
        guard let song = byID("bar.song") else { return false }
        // On its cover: the song's middle is the artist's name, a button of
        // its own that opens the artist.
        song.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        let close = app.descendants(matching: .any).matching(identifier: "nowPlaying.close").firstMatch
        if !close.waitForExistence(timeout: 8) {
            note("Now Playing: no nowPlaying.close 8 s after bar.song")
        }
        pause(3)
        return true
    }

    /// The room closed by `nowPlaying.close`, until it is gone: a menu
    /// still up takes the first tap for itself, and a room left open would
    /// lie over every picture after it. Without the close, as the cover is
    /// closed on the iPhone (its Close, else a pull down).
    func closeRoom() throws {
        guard let close = byID("nowPlaying.close", timeout: 2) else {
            try closeNowPlaying()
            return
        }
        for _ in 0..<2 where close.exists {
            try tap(close, "nowPlaying.close", timeout: 1)
            pause(2)
        }
        if close.exists { note("Now Playing: still open after two taps of nowPlaying.close") }
    }

    /// Until the bar's song (`bar.song`, labelled with the song) is
    /// `title`: a Play while something else plays says Pause at once.
    func waitForSong(_ title: String) {
        let song = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "bar.song", title)).firstMatch
        if !song.waitForExistence(timeout: 15) { note("the bar's song was not \(title) within 15 s") }
    }

    /// Settings: in the wide window from the sidebar head's Main Menu, item
    /// "Settings…", where Linux's primary menu keeps its Preferences; on the
    /// tabs from the button that says Settings in Home's toolbar. True once
    /// tapped.
    func openSettings() throws -> Bool {
        let menu = app.buttons["Main Menu"].firstMatch
        var opened = false
        if menu.waitForExistence(timeout: 3) {
            if try tap(menu, "the sidebar's Main Menu", timeout: 1) {
                opened = try tap(app.buttons["Settings…"], "Main Menu: Settings…", timeout: 4)
            }
        } else {
            opened = try tap(app.buttons["Settings"], "Settings (no Main Menu, no button Settings)", timeout: 4)
        }
        guard opened else { return false }
        _ = app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: 8)
        pause(1.5)
        return true
    }

    /// One of Settings' pages, from its list: the row by its identifier
    /// (SettingsView's `settings.page.<page>`), as "Radio" and "Library"
    /// are the tabs' and the sidebar's names too. True once tapped.
    func openSettingsPage(_ page: String, _ title: String) throws -> Bool {
        let row = app.descendants(matching: .any).matching(identifier: "settings.page.\(page)").firstMatch
        guard try tap(row, "Settings: \(title)", timeout: 4) else { return false }
        if !app.navigationBars[title].firstMatch.waitForExistence(timeout: 6) {
            note("Settings: \(title) has no navigation bar named \(title)")
        }
        pause(1.5)
        return true
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

/// The fake Jellyfin's address: localhost:8096, or the port ci/screenshots.sh
/// gives a runner of the MacBook (JUKEBOX_SERVER), where two runners walk at
/// once, each with a server of its own.
let fakeServer: String = {
    let given = ProcessInfo.processInfo.environment["JUKEBOX_SERVER"] ?? ""
    return given.isEmpty ? "localhost:8096" : given
}()
#endif
