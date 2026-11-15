// Jukebox for Linux starts here: one GTK application, one window.
//
// Swift's main actor runs on libdispatch's main queue, and GTK on GLib's
// main loop, both wanting the main thread. GLib's loop has it; the main
// queue tells of work through a file descriptor (as it tells Foundation's
// own run loop on Linux), which the loop watches: every `await` back to the
// main actor, every `Task { @MainActor … }`, runs from there, between two
// GTK events. Without it nothing asynchronous would ever come back.

import CAdw
import Foundation

@_silgen_name("_dispatch_get_main_queue_handle_4CF")
private func mainQueueHandle() -> Int32

@_silgen_name("_dispatch_main_queue_callback_4CF")
private func drainMainQueue(_ message: UnsafeMutableRawPointer?)

private func watchMainQueue() {
    let handle = mainQueueHandle()
    g_unix_fd_add(handle, G_IO_IN, { handle, _, _ in
        // An eventfd: read to quiet it, then run what waits.
        var count: UInt64 = 0
        _ = read(handle, &count, MemoryLayout<UInt64>.size)
        drainMainQueue(nil)
        return 1
    }, nil)
}

// dev/linux-errors.sh's check of the queue's rules: no window, no settings.
if ProcessInfo.processInfo.environment["JUKEBOX_CHECK"] == "queue" { exit(QueueCheck.run()) }
watchMainQueue()
DefaultsFile.load()
let application = adw_application_new("com.tijmen.Jukebox", G_APPLICATION_DEFAULT_FLAGS)!
on(raw(application), "activate") { MainWindow.present(in: application) }

// Every choice kept in UserDefaults (the Last.fm key, the volume, the
// panel, the device's id) was gone at the next start on Linux ("last fm api
// key word niet opgeslagen op linux nu", 14 November 2026): Foundation there
// writes nothing to disk by itself, posts no change notification, and its
// persistentDomain is empty (measured, swift 6.2). So Jukebox keeps its own
// file, ~/.config/jukebox/settings.plist: read before anything asks for a
// setting, written every two seconds when it changed, and on the way out.
on(raw(application), "shutdown") { DefaultsFile.save() }
g_timeout_add_seconds(2, { _ in
    MainActor.assumeIsolated { DefaultsFile.save() }
    return 1
}, nil)
exit(g_application_run(ptr(application), 0, nil))

enum DefaultsFile {
    static let url: URL = {
        let config = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        return config.appendingPathComponent("jukebox/settings.plist")
    }()
    private static var written: Data?

    /// Every saved choice back into UserDefaults, before the app reads one.
    static func load() {
        guard let data = try? Data(contentsOf: url),
              let saved = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return }
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        written = data
    }

    /// What UserDefaults holds now, less the system's own keys.
    static func save() {
        let kept = UserDefaults.standard.dictionaryRepresentation().filter { key, value in
            !key.hasPrefix("Apple") && !key.hasPrefix("NS")
                && PropertyListSerialization.propertyList(value, isValidFor: .binary)
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: kept, format: .binary, options: 0),
              data != written else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: url, options: .atomic)) != nil { written = data }
    }
}
