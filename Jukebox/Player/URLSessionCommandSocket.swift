// RemoteControl's socket on the iPhone, the iPad and the Mac: URLSession's
// own websocket (Linux has libsoup's, Linux/App/RemoteSocket.swift).

import Foundation
import JukeboxKit

final class URLSessionCommandSocket: CommandSocket {
    /// The socket's address carries the server's token: its redirects go
    /// as RedirectPolicy lets them.
    private static let session = URLSession(configuration: .default, delegate: RedirectGuard.shared,
                                            delegateQueue: nil)

    var received: ((String?) -> Void)?
    private let task: URLSessionWebSocketTask
    private var isClosed = false

    init(url: URL) {
        task = Self.session.webSocketTask(with: url)
        task.resume()
        listen()
    }

    private func listen() {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                switch result {
                case let .success(.string(text)):
                    self.received?(text)
                    self.listen()
                case let .success(.data(data)):
                    self.received?(String(decoding: data, as: UTF8.self))
                    self.listen()
                case .success:
                    self.listen()
                case .failure:
                    self.isClosed = true
                    self.received?(nil)
                }
            }
        }
    }

    func send(_ text: String) {
        task.send(.string(text)) { _ in }
    }

    func close() {
        isClosed = true
        task.cancel(with: .goingAway, reason: nil)
    }
}
