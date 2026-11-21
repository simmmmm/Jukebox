// The Mac's snapshots: pictures of the Mac app's main screens for every
// push the MacBook builds, made without a window on its screen. The Mac's
// screenshot walk (JukeboxUITests/MacScreenshotTests.swift) drives the real
// window and takes over the screen, the mouse and the keyboard, so on the
// photographer's own laptop it does not run: "Ok doe dat dan voortaan voor
// tijdens developen en dan word de grote voor app store als ik t vraag"
// (20 November 2026). The store's pictures, with the real window and its
// title bar, stay the walk's, on GitHub's Mac, when he asks (store-walk).
//
// The app's own views (WideShell, NowPlayingView, each Settings pane) and stores,
// signed in to the fake Jellyfin ci/screenshots.sh starts on localhost:8096
// (the walk's made-up library), drawn in a window that is never put on
// screen, 1440 by 900 as the store's window, dark and then light. No title
// bar: the window has none, so neither has the bar's search field, which
// lives in it. Music is made ready, not played: the bar and the room show a
// song, and the laptop stays silent.
//
// Run by ci/screenshots.sh: JukeboxSnapshots.app/Contents/MacOS/JukeboxSnapshots
// <folder> [server]. Each picture is <folder>/<name>.png; a screen that
// fails is written down and the rest go on. It always ends with 0: a
// picture is never the build's verdict.

import AppKit
import JukeboxKit
import SwiftUI

@main
enum Snapshots {
    static func main() {
        // The folder and the server first; then perhaps settings for the
        // argument domain ("-deviceID snapshots"), read and never written.
        let arguments = Array(CommandLine.arguments.dropFirst().prefix { !$0.hasPrefix("-") })
        let folder = URL(fileURLWithPath: arguments.first ?? "mac-snap", isDirectory: true)
        let address = arguments.dropFirst().first ?? "localhost:8096"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // No Dock icon, no menu bar, never in front: the laptop's owner is
        // using it.
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        // Not the laptop's Now Playing: the real Jukebox open beside it keeps
        // the Play key (NowPlayingInfo.isOn).
        AudioPlayer.claimsSystemControls = false
        Task {
            await Round(folder: folder, address: address).run()
            exit(0)
        }
        application.run()
    }
}

@MainActor
private struct Round {
    let folder: URL
    let address: String
    /// The window's size in the store's pictures (docs/RELEASE.md).
    let size = CGSize(width: 1440, height: 900)
    /// The Settings window's width (SettingsView's 560), and room for its
    /// longest pane, Library with its Pages.
    let settingsSize = CGSize(width: 560, height: 1000)

    func run() async {
        let started = Date()
        // Nothing counted from a picture (Stats), and no songs kept on the
        // laptop (Keep Songs I Play fetched the whole library, 138 songs):
        // in the registration domain, read when nothing else is set and
        // written nowhere.
        UserDefaults.standard.register(defaults: [Stats.key: false, "keepSongs": false])
        let app = AppModel.shared
        guard await signIn(app) else { return }
        // The Mac's window is always wide; RootView tells the navigator so
        // in the app.
        app.navigator.isWide = true
        let panel = PanelState()
        // The panel as each picture sets it, not remembered for the next run.
        panel.remembers = false

        // A song ready in the bar, as the walk has Dust Windows playing.
        if let album = album(named: "Dust Windows", in: app) {
            app.player.play(app.library.tracks(inAlbum: album.id), context: QueueContext(.album(album.id),
                            title: album.name), paused: true)
        } else {
            note("no album Dust Windows: the bar is empty")
        }

        for dark in [true, false] {
            let prefix = dark ? "" : "light-"
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            var number = 0
            func shot(_ name: String, settle: Double = 1.5, _ set: () -> Void) async {
                number += 1
                set()
                let view = WideShell().snapshotEnvironment(app, panel: panel)
                await render(view, size: size, appearance: appearance, settle: settle,
                             as: String(format: "%@%02d-%@", prefix, number, name))
            }
            await shot("home", settle: dark ? 3 : 1.5) {
                app.navigator.isNowPlayingPresented = false
                panel.isOpen = false
                app.navigator.place = .home
            }
            await shot("albums") { app.navigator.place = .library(.albums) }
            await shot("album-up-next") {
                panel.content = .upNext
                panel.isOpen = true
                app.navigator.place = .library(.albums)
                if let album = album(named: "Dust Parades", in: app) { app.navigator.open(.album(album)) }
            }
            await shot("now-playing") { app.navigator.isNowPlayingPresented = true }
            await shot("radio") {
                app.navigator.isNowPlayingPresented = false
                panel.isOpen = false
                app.navigator.place = .radio
            }
            await shot("artists") { app.navigator.place = .library(.artists) }
            await shot("search") {
                app.navigator.searchQuery = app.library.artistsByName.first.map { String($0.name.prefix(4)) } ?? "a"
                app.navigator.place = .search
            }
            // The version filter over the demo's album of remastered and
            // unplugged songs, as the photographer's Oasis album.
            await shot("album-versions") {
                app.navigator.place = .library(.albums)
                if let album = album(named: "Lantern Hours (25th Anniversary)", in: app) { app.navigator.open(.album(album)) }
            }
            // Settings: each pane's own form alone, at the window's width
            // (SettingsView's tabs), as its toolbar of tabs is not drawn in
            // an offscreen window and the whole window came out broken.
            // Tall enough for the longest pane; the store's walk on GitHub
            // has the real window.
            for page in SettingsPage.allCases where page != .about {
                number += 1
                let view = SettingsPageForm(page: page)
                    .frame(width: settingsSize.width, height: settingsSize.height)
                    .snapshotEnvironment(app, panel: panel)
                await render(view, size: settingsSize, appearance: appearance, settle: 1,
                             as: String(format: "%@%02d-settings-%@", prefix, number, page.rawValue))
            }
        }
        // The song made ready, let go again.
        app.player.stop()
        print("SNAPSHOTS: done in \(Int(Date().timeIntervalSince(started))) s")
    }

    /// Signed in to the fake Jellyfin as the walk signs in (test, test),
    /// then the library and the mixes read.
    private func signIn(_ app: AppModel) async -> Bool {
        do {
            let detected = try await app.detectServer(at: address)
            let credentials = try await app.signIn(to: detected).signIn(username: "test", password: "test")
            await app.openForSnapshots(credentials)
            // Accounts' cards with a second one beside it, made up, never
            // asked: a Navidrome at home.
            var second = credentials
            second.kind = .subsonic(flavour: .navidrome)
            second.serverID = "snapshots-betsy"
            second.serverName = "Betsy"
            second.serverVersion = "0.64.2"
            second.userName = "anna"
            second.serverURL = URL(string: "http://betsy.local:4533")!
            app.accounts.showForSnapshots([credentials, second])
        } catch {
            note("no sign-in at \(address): \(error)")
            return false
        }
        if app.library.albums.isEmpty { note("signed in, but the library has no albums") }
        print("SNAPSHOTS: \(app.library.albums.count) albums, \(app.library.tracks.count) songs")
        return true
    }

    private func album(named name: String, in app: AppModel) -> Album? {
        app.library.albums.first { $0.name == name } ?? app.library.albums.first
    }

    /// `view` drawn in a window that is never ordered in, given `settle`
    /// seconds for its covers to come, and saved as an opaque PNG at one
    /// pixel a point, as the store's window is measured.
    private func render(_ view: some View, size: CGSize, appearance: NSAppearance?, settle: Double,
                        as name: String) async {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        defer { window.close() }
        // Twice: what the first pass starts (covers, the mixes' art) shows
        // in the second.
        for _ in 0..<2 {
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .seconds(settle / 2))
        }
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                                         pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return note("\(name): no bitmap") }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let image = rep.cgImage, let png = Self.opaquePNG(image, ground: appearance) else {
            return note("\(name): not drawn")
        }
        do {
            try png.write(to: folder.appendingPathComponent("\(name).png"))
            print("PICTURE \(name) \(image.width)x\(image.height)")
        } catch {
            note("\(name): not written: \(error)")
        }
    }

    /// Without an alpha channel, as the store takes a Mac's picture: what
    /// the window leaves clear lies on the window's own ground.
    private static func opaquePNG(_ image: CGImage, ground appearance: NSAppearance?) -> Data? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        var ground = NSColor.windowBackgroundColor.cgColor
        appearance?.performAsCurrentDrawingAppearance { ground = NSColor.windowBackgroundColor.cgColor }
        context.setFillColor(ground)
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.fill(rect)
        context.draw(image, in: rect)
        guard let opaque = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: opaque).representation(using: .png, properties: [:])
    }

    private func note(_ text: String) {
        print("SNAPSHOT MISSED: \(text)")
        try? (text + "\n").append(to: folder.appendingPathComponent("missed.txt"))
    }
}

private extension String {
    func append(to url: URL) throws {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(utf8))
        } else {
            try write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private extension View {
    /// The app's stores and its tint, as JukeboxApp's appEnvironment hands
    /// them to each window (that one is private to the app's file).
    func snapshotEnvironment(_ app: AppModel, panel: PanelState) -> some View {
        environment(app)
            .environment(app.navigator)
            .environment(app.settings)
            .environment(app.library)
            .environment(app.history)
            .environment(app.player)
            .environment(app.radio)
            .environment(app.mixes)
            .environment(app.offline)
            .environment(app.handoff)
            .environment(panel)
            .tint(Theme.accent)
    }
}
