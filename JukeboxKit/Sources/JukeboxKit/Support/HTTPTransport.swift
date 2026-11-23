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
    /// Where the answer came from after any redirects (http:// to https://,
    /// a proxy's new path): detection keeps that address rather than the
    /// one typed, so the password and every call after go straight there.
    /// Nil from a transport that does not say (the tests' fakes).
    public var url: URL?

    public init(status: Int, headers: [String: String] = [:], body: Data, url: URL? = nil) {
        self.status = status
        self.headers = headers
        self.body = body
        self.url = url
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Where a redirect may take a request that carries the server's
/// credentials (a password in a POST, a token in a header, Subsonic's in
/// the query). From the security audit, 23 November 2026: within the same
/// host, http to https included, it is followed as it is; never from
/// https down to plain http; to another host without the credential
/// headers, and not at all with a body (a 307 or 308 of the sign-in's
/// POST, which would carry the password there). Nil: stop, and the 3xx is
/// the answer.
public enum RedirectPolicy {
    static let credentialHeaders = ["Authorization", "X-Emby-Authorization", "X-Emby-Token", "X-Plex-Token"]

    public static func next(_ proposed: URLRequest, after current: URLRequest) -> URLRequest? {
        guard let from = current.url, let to = proposed.url,
              let toScheme = to.scheme?.lowercased(), toScheme == "http" || toScheme == "https" else { return nil }
        if from.scheme?.lowercased() == "https", toScheme != "https" { return nil }
        if from.host?.lowercased() == to.host?.lowercased() { return proposed }
        let method = (proposed.httpMethod ?? "GET").uppercased()
        guard method == "GET" || method == "HEAD", proposed.httpBody == nil, proposed.httpBodyStream == nil else {
            return nil
        }
        var stripped = proposed
        for header in credentialHeaders { stripped.setValue(nil, forHTTPHeaderField: header) }
        return stripped
    }
}

/// RedirectPolicy as a URLSession's delegate, for every session that
/// follows redirects itself: Apple's transport, and on both platforms the
/// covers' sessions (`URLSessionTransport.uncached`, ImagePipeline). Not
/// Apple's background downloads: a background session follows redirects
/// without asking its delegate.
public final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    public static let shared = RedirectGuard()

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(task.currentRequest.flatMap { RedirectPolicy.next(request, after: $0) })
    }
}

public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    /// URLSession.shared without its disk cache: a Subsonic call's address
    /// carries the account's credentials, and URLCache keeps answers by
    /// address. Nothing here is meant to be answered from a cache. Its
    /// redirects go by RedirectPolicy (RedirectGuard).
    public static let uncached: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: RedirectGuard.shared, delegateQueue: nil)
    }()

    public init(session: URLSession = URLSessionTransport.uncached) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        #if canImport(FoundationNetworking)
        let (data, response) = try await Self.followingRedirects(session, request)
        #else
        let (data, response) = try await session.data(for: request, delegate: RedirectGuard.shared)
        #endif
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.transport("No HTTP response.")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data, url: http.url)
    }

    #if canImport(FoundationNetworking)
    /// Linux's URLSession (swift-corelibs-foundation 6.2.4) crashes when
    /// two requests at once are redirected: "EasyHandle.swift:293: Fatal
    /// error: … libcurl.Easy Code=43", its redirect setting an option of
    /// libcurl's in the middle of a transfer. Measured 23 November 2026 on
    /// http://demo.navidrome.org, which redirects to https: detection asks
    /// three ways at once, so typing that address closed the app. So here
    /// URLSession follows none (RefusesRedirects), and each redirect is a
    /// request of its own, as Apple's URLSession would make it (303, and a
    /// POST's 301 or 302, become a GET without the body), and only where
    /// RedirectPolicy lets it go.
    private static func followingRedirects(_ session: URLSession,
                                           _ first: URLRequest) async throws -> PendingRequest.Answer {
        var request = first
        for _ in 0..<10 {
            let answer = try await uncancelledData(session, request)
            guard let http = answer.1 as? HTTPURLResponse, [301, 302, 303, 307, 308].contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { return answer }
            var proposed = request
            proposed.url = target
            if http.statusCode == 303 || (request.httpMethod == "POST" && http.statusCode <= 302) {
                proposed.httpMethod = "GET"
                proposed.httpBody = nil
                proposed.setValue(nil, forHTTPHeaderField: "Content-Type")
            }
            guard let next = RedirectPolicy.next(proposed, after: request) else { return answer }
            request = next
        }
        throw URLError(.httpTooManyRedirects)
    }
    #endif

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
                let task = session.dataTask(with: request) { data, response, error in
                    pending.finish(error.map { .failure($0) } ?? .success((data ?? Data(), response)))
                }
                task.delegate = RefusesRedirects.shared
                task.resume()
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
/// Hands every redirect back as the answer (followingRedirects).
private final class RefusesRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RefusesRedirects()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

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
