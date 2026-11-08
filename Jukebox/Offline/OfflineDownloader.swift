// The downloads themselves: one background URLSession, so a song goes on
// downloading while the app is in the background, suspended, or ended by the
// system — the system does the fetching, and wakes the app (through
// JukeboxAppDelegate) when there is news. Each task carries its song in its
// description (OfflineDownloadTag: account, song, quality), so the news makes
// sense after a relaunch, when nothing else of the app's memory is left.
//
// URLSession calls its delegate on the session's own queue, never the main
// actor: this class is `nonisolated` (the app's default is the main actor),
// moves a finished file into the account's folder there and then — the system
// deletes it when the call returns — and hands every event on to the store,
// which hops to the main actor itself. Events that arrive before the store
// is listening (a relaunch in the background) wait here for it.

import Foundation
import JukeboxKit
import UIKit

/// Which song a download is, for whom, at what quality.
nonisolated struct OfflineDownloadTag: Codable, Sendable, Hashable {
    var account: String
    var trackID: ItemID
    var quality: DownloadQuality

    init(account: String, trackID: ItemID, quality: DownloadQuality) {
        self.account = account
        self.trackID = trackID
        self.quality = quality
    }

    /// From a task's description; nil for a task that is not one of ours.
    init?(text: String?) {
        guard let text, let data = text.data(using: .utf8),
              let tag = try? JSONDecoder().decode(OfflineDownloadTag.self, from: data) else { return nil }
        self = tag
    }

    var text: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated enum OfflineDownloadEvent: Sendable {
    case progress(OfflineDownloadTag, written: Int64, expected: Int64)
    /// In the account's folder now, as `fileName`.
    case finished(OfflineDownloadTag, fileName: String, bytes: Int64)
    /// `permanent`: the server said it has no such file, or cannot give it in
    /// that form; asking again would not help.
    case failed(OfflineDownloadTag, permanent: Bool)
    case cancelled(OfflineDownloadTag)
}

nonisolated final class OfflineDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.tijmen.Jukebox.downloads"
    /// One session for the app's life: a background session's identifier
    /// may belong to one session at a time.
    static let shared = OfflineDownloader()

    /// A progress event every quarter of a megabyte a song: some tens for a
    /// song, not one for every packet.
    private static let progressStep: Int64 = 262_144

    // Guarded by `lock`: the session's queue and the main actor both reach them.
    private let lock = NSLock()
    private var sink: (@Sendable (OfflineDownloadEvent) -> Void)?
    private var waiting: [OfflineDownloadEvent] = []
    private var reported: [Int: Int64] = [:]

    // Set once, in init, before anything else can see it.
    private var session: URLSession!

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        // Woken, or launched, when downloads finish while the app is not running.
        configuration.sessionSendsLaunchEvents = true
        // Chosen downloads go now; the keep's are asked for at low priority.
        configuration.isDiscretionary = false
        // Each request says whether it may use mobile data and Low Data
        // Mode (`start`); the session allows both so the request decides.
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpMaximumConnectionsPerHost = 4
        let queue = OperationQueue()
        queue.name = "Jukebox.downloads"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// Where the events go from now on; any that came before are handed over first.
    func attach(_ sink: @escaping @Sendable (OfflineDownloadEvent) -> Void) {
        lock.lock()
        self.sink = sink
        let earlier = waiting
        waiting = []
        lock.unlock()
        for event in earlier { sink(event) }
    }

    func start(_ tag: OfflineDownloadTag, from url: URL, overCellular: Bool, inLowDataMode: Bool,
               expectedBytes: Int64, isChosen: Bool) {
        var request = URLRequest(url: url)
        // Settings › Downloads › Download over Cellular, off by default: a
        // task that may not use mobile data waits for Wi-Fi by itself.
        request.allowsCellularAccess = overCellular
        request.allowsExpensiveNetworkAccess = overCellular
        request.allowsConstrainedNetworkAccess = inLowDataMode
        let task = session.downloadTask(with: request)
        task.taskDescription = tag.text
        if expectedBytes > 0 { task.countOfBytesClientExpectsToReceive = expectedBytes }
        task.priority = isChosen ? URLSessionTask.highPriority : URLSessionTask.lowPriority
        task.resume()
    }

    /// Cancels every download whose tag `matches`; each says so (`.cancelled`).
    func cancel(where matches: @escaping @Sendable (OfflineDownloadTag) -> Bool) {
        session.getAllTasks { tasks in
            for task in tasks {
                guard let tag = OfflineDownloadTag(text: task.taskDescription), matches(tag) else { continue }
                task.cancel()
            }
        }
    }

    /// The downloads the session still has, also those it kept across a
    /// relaunch.
    func running(_ done: @escaping @Sendable ([OfflineDownloadTag]) -> Void) {
        session.getAllTasks { tasks in
            let live = tasks.filter { $0.state == .running || $0.state == .suspended }
            done(live.compactMap { OfflineDownloadTag(text: $0.taskDescription) })
        }
    }

    // MARK: The session's news, on its queue

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        lock.lock()
        let last = reported[id] ?? 0
        let due = totalBytesWritten - last >= Self.progressStep
        if due { reported[id] = totalBytesWritten }
        lock.unlock()
        guard due, let tag = OfflineDownloadTag(text: downloadTask.taskDescription) else { return }
        emit(.progress(tag, written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        forget(downloadTask)
        guard let tag = OfflineDownloadTag(text: downloadTask.taskDescription) else { return }
        // An HTTP error arrives here too, as a file of the error's words;
        // the task then completes without an error.
        let response = downloadTask.response as? HTTPURLResponse
        let status = response?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            emit(.failed(tag, permanent: [400, 404, 410, 415].contains(status)))
            return
        }
        // Named by what the server sent, not by the quality asked for: the
        // file itself in any container the phone plays, or an m4a when
        // Jellyfin converted it; AVPlayer reads a local file by its extension.
        let contentType = response?.value(forHTTPHeaderField: "Content-Type") ?? response?.mimeType
        let fileName = OfflineFile.fileName(trackID: tag.trackID, contentType: contentType)
        let folder = OfflinePaths.files(tag.account)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            emit(.failed(tag, permanent: false))
            return
        }
        let bytes = OfflineDisk.fileSize(destination)
        guard bytes > 0 else {
            try? FileManager.default.removeItem(at: destination)
            emit(.failed(tag, permanent: false))
            return
        }
        emit(.finished(tag, fileName: fileName, bytes: bytes))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        forget(task)
        // Without an error the file was handed over above.
        guard let error, let tag = OfflineDownloadTag(text: task.taskDescription) else { return }
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain, failure.code == NSURLErrorCancelled {
            emit(.cancelled(tag))
        } else {
            emit(.failed(tag, permanent: false))
        }
    }

    /// Everything the system had for the app, while it was in the background,
    /// has been handed over: the system may be told (OfflineBackgroundEvents).
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in OfflineBackgroundEvents.finished() }
    }

    // MARK: Inside

    private func emit(_ event: OfflineDownloadEvent) {
        lock.lock()
        let sink = self.sink
        if sink == nil { waiting.append(event) }
        lock.unlock()
        sink?(event)
    }

    private func forget(_ task: URLSessionTask) {
        lock.lock()
        reported[task.taskIdentifier] = nil
        lock.unlock()
    }
}

/// The system's completion handler for the downloads' background events,
/// kept until the store has written down what they brought.
enum OfflineBackgroundEvents {
    static var completion: (() -> Void)?
    /// The store that writes the news down; set when it is made.
    static weak var store: OfflineStore?

    /// The session has handed everything over: once it is saved, the system
    /// is told, so it can put the app back to sleep.
    static func finished() {
        guard completion != nil else { return }
        if let store {
            store.saveNowThenTellSystem()
        } else {
            tellSystem()
        }
    }

    static func tellSystem() {
        let done = completion
        completion = nil
        done?()
    }
}

/// UIKit's delegate, for the one thing SwiftUI has no place for: the
/// downloads' news while the app was in the background or not running.
final class JukeboxAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == OfflineDownloader.identifier else {
            completionHandler()
            return
        }
        OfflineBackgroundEvents.completion = completionHandler
        // The session, made again for this launch when the app was not
        // running, is what takes the events (AppModel's store made it too).
        _ = OfflineDownloader.shared
    }
}
