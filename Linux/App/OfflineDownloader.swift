// The downloads on Linux: the iPhone's OfflineDownloader
// (Jukebox/Offline/OfflineDownloader.swift) by the same name and calls, so
// the shared OfflineStore drives either. A plain URLSession while Jukebox
// runs: a desktop has no system that fetches for an app that is closed.
// What was still to come when it quit waits in the store's queue and starts
// again at the next launch.
//
// The same checks as the iPhone's on what came: an HTTP error is no song
// (and 400, 404, 410 and 415 will not become one), nor are words (a
// Subsonic server's errors come as HTTP 200 with JSON or XML), nor nothing.
// A song is moved into the account's folder only once it is whole: a file
// there is a finished download (OfflineDisk.load takes it as one).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import JukeboxKit

nonisolated final class OfflineDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = OfflineDownloader()

    /// A progress event every quarter of a megabyte a song, as the iPhone's.
    private static let progressStep: Int64 = 262_144
    /// Songs fetched at once, as the iPhone's session asks of a server.
    private static let connections = 4

    // Guarded by `lock`: the session's queue and the main actor both reach them.
    private let lock = NSLock()
    private var sink: (@Sendable (OfflineDownloadEvent) -> Void)?
    private var waiting: [OfflineDownloadEvent] = []
    /// The downloads under way or waiting their turn, by the task's identifier.
    private var tasks: [Int: (task: URLSessionDownloadTask, tag: OfflineDownloadTag, isChosen: Bool)] = [:]
    /// Waiting their turn: what the listener chose before what the keep
    /// would like, as the iPhone's session runs them by priority. Without
    /// it an album clicked waited behind the keep's two dozen.
    private var queued: [Int] = []
    private var active: Set<Int> = []
    private var reported: [Int: Int64] = [:]

    // Set once, in init, before anything else can see it.
    private var session: URLSession!

    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
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

    /// The iPhone's call; a desktop's network is not told apart, so the
    /// mobile-data and Low Data Mode leaves mean nothing here.
    func start(_ tag: OfflineDownloadTag, from url: URL, overCellular: Bool, inLowDataMode: Bool,
               expectedBytes: Int64, isChosen: Bool) {
        let task = session.downloadTask(with: URLRequest(url: url))
        let id = task.taskIdentifier
        lock.lock()
        tasks[id] = (task, tag, isChosen)
        if isChosen, let at = queued.firstIndex(where: { tasks[$0]?.isChosen == false }) {
            queued.insert(id, at: at)
        } else {
            queued.append(id)
        }
        let next = nextTurns()
        lock.unlock()
        for task in next { task.resume() }
    }

    /// Cancels every download whose tag `matches`; each says so (`.cancelled`)
    /// at once, and whatever its task still says after is not heard.
    func cancel(where matches: @escaping @Sendable (OfflineDownloadTag) -> Bool) {
        lock.lock()
        let found = tasks.filter { matches($0.value.tag) }
        for id in found.keys { forget(id) }
        let next = nextTurns()
        lock.unlock()
        for (_, entry) in found {
            entry.task.cancel()
            emit(.cancelled(entry.tag))
        }
        for task in next { task.resume() }
    }

    /// The downloads under way. At a launch none: nothing went on while
    /// Jukebox was closed.
    func running(_ done: @escaping @Sendable ([OfflineDownloadTag]) -> Void) {
        lock.lock()
        let tags = tasks.values.map(\.tag)
        lock.unlock()
        done(tags)
    }

    // MARK: The session's news, on its queue

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        lock.lock()
        let tag = tasks[id]?.tag
        let last = reported[id] ?? 0
        let due = tag != nil && totalBytesWritten - last >= Self.progressStep
        if due { reported[id] = totalBytesWritten }
        lock.unlock()
        guard due, let tag else { return }
        emit(.progress(tag, written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let tag = take(downloadTask) else { return }
        let response = downloadTask.response as? HTTPURLResponse
        let status = response?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            emit(.failed(tag, permanent: [400, 404, 410, 415].contains(status)))
            return
        }
        let contentType = response?.value(forHTTPHeaderField: "Content-Type") ?? response?.mimeType
        if let type = contentType?.lowercased(), type.contains("json") || type.contains("xml") || type.hasPrefix("text/") {
            emit(.failed(tag, permanent: true))
            return
        }
        // Named by what the server sent, as on the iPhone: GStreamer reads
        // a file by what is in it, but the name says what it is to anyone.
        let fileName = OfflineFile.fileName(trackID: tag.trackID, contentType: contentType)
        let folder = OfflinePaths.files(tag.account)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        do {
            try place(location, at: destination, in: folder)
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
        // Handed over (or cancelled) already: nothing more to say.
        guard let tag = take(task) else { return }
        let failure = error as NSError?
        if failure?.domain == NSURLErrorDomain, failure?.code == NSURLErrorCancelled {
            emit(.cancelled(tag))
        } else {
            // An error, or done without a file: either way not a song.
            emit(.failed(tag, permanent: false))
        }
    }

    // MARK: Inside

    /// The download, whole, at `destination`. The session's file is in the
    /// system's temporary folder, often another file system than the
    /// user's data: then it is copied beside the destination under a name
    /// no song has, and renamed, so `destination` is never half a file.
    private func place(_ location: URL, at destination: URL, in folder: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
        do {
            try files.moveItem(at: location, to: destination)
        } catch {
            let part = folder.appendingPathComponent("." + destination.lastPathComponent + ".part", isDirectory: false)
            try? files.removeItem(at: part)
            try files.copyItem(at: location, to: part)
            try files.moveItem(at: part, to: destination)
            try? files.removeItem(at: location)
        }
    }

    /// The task's song, forgotten, and the next one's turn: each task's
    /// news is told once.
    private func take(_ task: URLSessionTask) -> OfflineDownloadTag? {
        lock.lock()
        let tag = tasks[task.taskIdentifier]?.tag
        forget(task.taskIdentifier)
        let next = nextTurns()
        lock.unlock()
        for task in next { task.resume() }
        return tag
    }

    /// Under `lock`.
    private func forget(_ id: Int) {
        tasks[id] = nil
        reported[id] = nil
        active.remove(id)
        queued.removeAll { $0 == id }
    }

    /// Under `lock`: the tasks whose turn it is now, to resume once it is let go.
    private func nextTurns() -> [URLSessionDownloadTask] {
        var next: [URLSessionDownloadTask] = []
        while active.count < Self.connections, !queued.isEmpty {
            let id = queued.removeFirst()
            guard let entry = tasks[id] else { continue }
            active.insert(id)
            next.append(entry.task)
        }
        return next
    }

    private func emit(_ event: OfflineDownloadEvent) {
        lock.lock()
        let sink = self.sink
        if sink == nil { waiting.append(event) }
        lock.unlock()
        sink?(event)
    }
}
