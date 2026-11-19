// RemoteControl's websocket on Linux: libsoup's, in C in CGlue/socket.c
// (Foundation's has no websockets on Linux: "not supported by libcurl").

import CGlue
import Foundation

final class SoupCommandSocket: CommandSocket {
    var received: ((String?) -> Void)?
    private var socket: OpaquePointer?
    /// Unmanaged's box for C, released at close.
    private var box: Unmanaged<SoupCommandSocket>?

    init(url: URL) {
        let box = Unmanaged.passRetained(self)
        self.box = box
        socket = jb_socket_connect(url.absoluteString, { text, data in
            guard let data else { return }
            let socket = Unmanaged<SoupCommandSocket>.fromOpaque(data).takeUnretainedValue()
            let message = text.map { String(cString: $0) }
            MainActor.assumeIsolated {
                socket.received?(message)
                if message == nil { socket.close() }
            }
        }, box.toOpaque())
    }

    func send(_ text: String) {
        guard let socket else { return }
        jb_socket_send(socket, text)
    }

    func close() {
        if let socket { jb_socket_close(socket) }
        socket = nil
        received = nil
        box?.release()
        box = nil
    }
}
