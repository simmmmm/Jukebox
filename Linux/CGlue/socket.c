// RemoteControl's websocket on Linux (Linux/App/RemoteSocket.swift):
// libsoup's, as Foundation's websocket fails on Swift 6.2's Linux ("not
// supported by libcurl"). libsoup is GNOME's own HTTP library; the AppImage
// ships it already and GNOME's Flatpak runtime has it. Everything on GLib's
// main loop, so every callback comes on the main thread, where Swift's main
// actor runs.

#include "glue.h"
#include <libsoup/soup.h>

struct JbSocket {
    int refs;
    gboolean closed;
    SoupSession *session;
    SoupWebsocketConnection *connection;
    GCancellable *cancel;
    JbSocketReceived received;
    gpointer data;
};

static JbSocket *socket_ref(JbSocket *socket) { socket->refs++; return socket; }

static void socket_unref(JbSocket *socket) {
    if (--socket->refs > 0) return;
    if (socket->connection) g_signal_handlers_disconnect_by_data(socket->connection, socket);
    g_clear_object(&socket->connection);
    g_clear_object(&socket->session);
    g_object_unref(socket->cancel);
    g_free(socket);
}

// Once: Swift hears NULL, and nothing after.
static void socket_end(JbSocket *socket) {
    if (socket->closed) return;
    socket->closed = TRUE;
    g_cancellable_cancel(socket->cancel);
    socket->received(NULL, socket->data);
}

static void socket_message(SoupWebsocketConnection *connection, gint type, GBytes *message, gpointer user) {
    JbSocket *socket = user;
    if (socket->closed || type != SOUP_WEBSOCKET_DATA_TEXT) return;
    gsize length = 0;
    const char *bytes = g_bytes_get_data(message, &length);
    char *text = g_strndup(bytes, length);
    socket->received(text, socket->data);
    g_free(text);
}

static void socket_closed(SoupWebsocketConnection *connection, gpointer user) {
    socket_end(user);
}

static void socket_connected(GObject *source, GAsyncResult *result, gpointer user) {
    JbSocket *socket = user;
    SoupWebsocketConnection *connection =
        soup_session_websocket_connect_finish(SOUP_SESSION(source), result, NULL);
    if (!connection || socket->closed) {
        if (connection) {
            soup_websocket_connection_close(connection, SOUP_WEBSOCKET_CLOSE_GOING_AWAY, NULL);
            g_object_unref(connection);
        }
        socket_end(socket);
    } else {
        socket->connection = connection;
        // The server's keep-alives come as text, so libsoup's own pings are
        // not needed; a socket gone quiet is noticed when a send fails.
        g_signal_connect(connection, "message", G_CALLBACK(socket_message), socket);
        g_signal_connect(connection, "closed", G_CALLBACK(socket_closed), socket);
    }
    socket_unref(socket);
}

static void socket_fail_soon(gpointer user) {
    socket_end(user);
    socket_unref(user);
}

JbSocket *jb_socket_connect(const char *url, JbSocketReceived received, gpointer data) {
    JbSocket *socket = g_new0(JbSocket, 1);
    socket->refs = 1;
    socket->cancel = g_cancellable_new();
    socket->received = received;
    socket->data = data;
    socket->session = soup_session_new();
    SoupMessage *message = soup_message_new("GET", url);
    if (!message) {
        // Not an address libsoup takes: closed at once, on the main loop.
        g_idle_add_once(socket_fail_soon, socket_ref(socket));
        return socket;
    }
    soup_session_websocket_connect_async(socket->session, message, NULL, NULL, G_PRIORITY_DEFAULT,
                                         socket->cancel, socket_connected, socket_ref(socket));
    g_object_unref(message);
    return socket;
}

void jb_socket_send(JbSocket *socket, const char *text) {
    if (socket->closed || !socket->connection) return;
    if (soup_websocket_connection_get_state(socket->connection) != SOUP_WEBSOCKET_STATE_OPEN) return;
    soup_websocket_connection_send_text(socket->connection, text);
}

void jb_socket_close(JbSocket *socket) {
    socket->closed = TRUE;
    g_cancellable_cancel(socket->cancel);
    if (socket->connection) {
        g_signal_handlers_disconnect_by_data(socket->connection, socket);
        if (soup_websocket_connection_get_state(socket->connection) == SOUP_WEBSOCKET_STATE_OPEN)
            soup_websocket_connection_close(socket->connection, SOUP_WEBSOCKET_CLOSE_GOING_AWAY, NULL);
    }
    socket_unref(socket);
}
