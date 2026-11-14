// Every request Jukebox makes to Jellyfin or Last.fm goes through one
// function, so a test can answer instead of a server (MockTransport in the
// tests) and the real one is URLSession, on Linux too.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        #if canImport(FoundationNetworking)
        let (data, response) = try await Self.uncancelledData(session, request)
        #else
        let (data, response) = try await session.data(for: request)
        #endif
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.transport("No HTTP response.")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    #if canImport(FoundationNetworking)
    /// Linux's URLSession (swift-corelibs-foundation, Swift 6.2.4) cannot be
    /// cancelled safely. Its async data(for:) deadlocks when cancelled just
    /// as its request ends: the cancel runs under the Swift task's own lock
    /// and waits for the session's queue, while that queue, ending the
    /// request, waits for the same lock; after that no request of the
    /// session ever answers. And URLSessionTask.cancel() racing the end of
    /// its request crashes ("a task that in not in the registry"). CI's kit
    /// job hung on the first until its timeout (14 November 2026): detection
    /// by the host alone cancels the ports that lost just as they were
    /// refused. So here nothing is cancelled: a cancelled request answers
    /// .cancelled at once, and its transfer ends by itself, unheard.
    /// ponytail: it still reaches the server and holds its connection until
    /// it ends or times out (15 to 120 s for the clients' requests).
    private static func uncancelledData(_ session: URLSession,
                                        _ request: URLRequest) async throws -> PendingRequest.Answer {
        guard !Task.isCancelled else { throw URLError(.cancelled) }
        let pending = PendingRequest()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pending.wait(continuation) else { return }
                session.dataTask(with: request) { data, response, error in
                    pending.finish(error.map { .failure($0) } ?? .success((data ?? Data(), response)))
                }.resume()
            }
        } onCancel: {
            // Not on this thread: the handler runs under the task's lock,
            // which resuming the task takes too.
            DispatchQueue.global().async { pending.finish(.failure(URLError(.cancelled))) }
        }
    }
    #endif
}

#if canImport(FoundationNetworking)
/// A request answered once: by its transfer or by its cancel, whichever
/// comes first; the other is dropped.
private final class PendingRequest: @unchecked Sendable {
    typealias Answer = (Data, URLResponse?)
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Answer, any Error>?
    private var result: Result<Answer, any Error>?

    /// Whether to start the transfer: not when cancelled already.
    func wait(_ continuation: CheckedContinuation<Answer, any Error>) -> Bool {
        let early = lock.withLock { () -> Result<Answer, any Error>? in
            if result == nil { self.continuation = continuation }
            return result
        }
        guard let early else { return true }
        continuation.resume(with: early)
        return false
    }

    func finish(_ result: Result<Answer, any Error>) {
        let waiting = lock.withLock { () -> CheckedContinuation<Answer, any Error>? in
            guard self.result == nil else { return nil }
            self.result = result
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: result)
    }
}
#endif
