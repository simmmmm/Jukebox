// A Chromecast's socket (Linux/App/Cast.swift): TLS to its port 8009 with
// GIO, which GTK brings, and glib-networking for the TLS, which the app
// ships already (libsoup's https). Everything is asynchronous on GLib's
// main loop, so every callback comes on the main thread, where Swift's main
// actor runs (main.swift).
//
// A Chromecast's certificate is its own, signed by Google's device CA,
// never by a public one, and its name is no host name: every sender accepts
// it as it is (the device's authenticity is a separate castv2 exchange the
// Default Media Receiver does not ask for). So "accept-certificate" says yes.

#include "glue.h"

struct JbCast {
    int refs;
    gboolean closed;
    GCancellable *cancel;
    GSocketConnection *connection;
    // Bytes waiting to be written, in order; one write at a time.
    GQueue pending;
    gboolean writing;
    JbCastReceived received;
    gpointer data;
};

static JbCast *cast_ref(JbCast *cast) { cast->refs++; return cast; }

static void cast_unref(JbCast *cast) {
    if (--cast->refs > 0) return;
    g_queue_clear_full(&cast->pending, (GDestroyNotify)g_bytes_unref);
    g_clear_object(&cast->connection);
    g_object_unref(cast->cancel);
    g_free(cast);
}

// Once: nothing more is read or written, and Swift hears nil.
static void cast_fail(JbCast *cast) {
    if (cast->closed) return;
    cast->closed = TRUE;
    g_cancellable_cancel(cast->cancel);
    cast->received(NULL, 0, cast->data);
}

static void cast_write_next(JbCast *cast);

static void cast_wrote(GObject *source, GAsyncResult *result, gpointer user) {
    JbCast *cast = user;
    gboolean done = g_output_stream_write_all_finish(G_OUTPUT_STREAM(source), result, NULL, NULL);
    cast->writing = FALSE;
    if (!done) cast_fail(cast);
    else cast_write_next(cast);
    cast_unref(cast);
}

static void cast_write_next(JbCast *cast) {
    if (cast->closed || cast->writing || !cast->connection) return;
    GBytes *bytes = g_queue_pop_head(&cast->pending);
    if (!bytes) return;
    cast->writing = TRUE;
    gsize length = 0;
    const void *at = g_bytes_get_data(bytes, &length);
    GOutputStream *out = g_io_stream_get_output_stream(G_IO_STREAM(cast->connection));
    // GIO reads the bytes until the write is done: the GBytes is kept with
    // the stream's data until then.
    g_object_set_data_full(G_OBJECT(out), "jb-writing", bytes, (GDestroyNotify)g_bytes_unref);
    g_output_stream_write_all_async(out, at, length, G_PRIORITY_DEFAULT, cast->cancel, cast_wrote, cast_ref(cast));
}

static void cast_read_next(JbCast *cast);

static void cast_read(GObject *source, GAsyncResult *result, gpointer user) {
    JbCast *cast = user;
    GBytes *bytes = g_input_stream_read_bytes_finish(G_INPUT_STREAM(source), result, NULL);
    if (!cast->closed) {
        gsize length = bytes ? g_bytes_get_size(bytes) : 0;
        if (length == 0) {
            // The end of the stream, or an error.
            cast_fail(cast);
        } else {
            cast->received(g_bytes_get_data(bytes, NULL), length, cast->data);
            cast_read_next(cast);
        }
    }
    if (bytes) g_bytes_unref(bytes);
    cast_unref(cast);
}

static void cast_read_next(JbCast *cast) {
    if (cast->closed) return;
    GInputStream *in = g_io_stream_get_input_stream(G_IO_STREAM(cast->connection));
    g_input_stream_read_bytes_async(in, 16384, G_PRIORITY_DEFAULT, cast->cancel, cast_read, cast_ref(cast));
}

static gboolean cast_accept(GTlsConnection *tls, GTlsCertificate *certificate, GTlsCertificateFlags errors,
                            gpointer user) {
    return TRUE;
}

// The TLS connection is made inside connect_to_host: its handshake asks
// "accept-certificate" there, so the handler goes on as it is made.
static void cast_event(GSocketClient *client, GSocketClientEvent event, GSocketConnectable *connectable,
                       GIOStream *connection, gpointer user) {
    if (event == G_SOCKET_CLIENT_TLS_HANDSHAKING && G_IS_TLS_CLIENT_CONNECTION(connection)) {
        g_signal_connect(connection, "accept-certificate", G_CALLBACK(cast_accept), NULL);
    }
}

static void cast_connected(GObject *source, GAsyncResult *result, gpointer user) {
    JbCast *cast = user;
    GSocketConnection *connection = g_socket_client_connect_to_host_finish(G_SOCKET_CLIENT(source), result, NULL);
    if (cast->closed) {
        g_clear_object(&connection);
    } else if (!connection) {
        cast_fail(cast);
    } else {
        cast->connection = connection;
        cast_read_next(cast);
        cast_write_next(cast);
    }
    g_object_unref(source);
    cast_unref(cast);
}

JbCast *jb_cast_connect(const char *host, guint16 port, JbCastReceived received, gpointer data) {
    JbCast *cast = g_new0(JbCast, 1);
    cast->refs = 1;
    cast->cancel = g_cancellable_new();
    cast->received = received;
    cast->data = data;
    g_queue_init(&cast->pending);
    GSocketClient *client = g_socket_client_new();
    g_socket_client_set_tls(client, TRUE);
    // A receiver on the network answers at once; one that is gone is not
    // waited for long.
    g_socket_client_set_timeout(client, 10);
    g_signal_connect(client, "event", G_CALLBACK(cast_event), NULL);
    g_socket_client_connect_to_host_async(client, host, port, cast->cancel, cast_connected, cast_ref(cast));
    return cast;
}

void jb_cast_send(JbCast *cast, const guint8 *bytes, gsize length) {
    if (cast->closed) return;
    g_queue_push_tail(&cast->pending, g_bytes_new(bytes, length));
    cast_write_next(cast);
}

void jb_cast_close(JbCast *cast) {
    if (!cast->closed) {
        cast->closed = TRUE;
        g_cancellable_cancel(cast->cancel);
    }
    if (cast->connection) g_io_stream_close_async(G_IO_STREAM(cast->connection), G_PRIORITY_DEFAULT, NULL, NULL, NULL);
    cast_unref(cast);
}

// Finding Chromecasts: Avahi, the system's mDNS, over D-Bus on the system
// bus, as GNOME's own apps find printers and shares. Jukebox sends no mDNS
// itself. No system bus, or no Avahi on it (a container, a sandbox without
// the talk-name): nothing is found, and nothing is said.

struct JbAvahi {
    gboolean stopped;
    GCancellable *cancel;
    GDBusConnection *bus;
    guint subscription;
    char *browser;
    JbCastFound found;
    gpointer data;
};

#define AVAHI "org.freedesktop.Avahi"
#define CAST_TYPE "_googlecast._tcp"

typedef struct {
    JbAvahi *avahi;
    char *name;
    gint32 interface;
    gint32 protocol;
    char *domain;
    gboolean anyProtocol;
} Resolve;

static void resolve_free(Resolve *resolve) {
    g_free(resolve->name);
    g_free(resolve->domain);
    g_free(resolve);
}

static void avahi_resolve(Resolve *resolve);

static void avahi_resolved(GObject *source, GAsyncResult *result, gpointer user) {
    Resolve *resolve = user;
    JbAvahi *avahi = resolve->avahi;
    GVariant *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, NULL);
    if (!reply) {
        // No IPv4 address: once more with any protocol.
        if (!resolve->anyProtocol && !g_cancellable_is_cancelled(avahi->cancel)) {
            resolve->anyProtocol = TRUE;
            avahi_resolve(resolve);
            return;
        }
        resolve_free(resolve);
        return;
    }
    if (!avahi->stopped) {
        const char *address = NULL;
        guint16 port = 0;
        GVariant *txt = NULL;
        g_variant_get(reply, "(iissssi&sq@aayu)", NULL, NULL, NULL, NULL, NULL, NULL, NULL, &address, &port,
                      &txt, NULL);
        // The TXT record: fn= is the name the TV was given, id= its own.
        char *fn = NULL, *id = NULL;
        GVariantIter iter;
        GVariant *entry;
        g_variant_iter_init(&iter, txt);
        while ((entry = g_variant_iter_next_value(&iter))) {
            gsize length = 0;
            const char *bytes = g_variant_get_fixed_array(entry, &length, 1);
            char *text = g_strndup(bytes, length);
            if (g_str_has_prefix(text, "fn=") && !fn) fn = g_strdup(text + 3);
            if (g_str_has_prefix(text, "id=") && !id) id = g_strdup(text + 3);
            g_free(text);
            g_variant_unref(entry);
        }
        avahi->found(resolve->name, id ? id : resolve->name, fn ? fn : resolve->name, address, port, FALSE,
                     avahi->data);
        g_free(fn);
        g_free(id);
        g_variant_unref(txt);
    }
    g_variant_unref(reply);
    resolve_free(resolve);
}

static void avahi_resolve(Resolve *resolve) {
    JbAvahi *avahi = resolve->avahi;
    // aprotocol 0 is IPv4: an address every TV answers on.
    g_dbus_connection_call(avahi->bus, AVAHI, "/", AVAHI ".Server", "ResolveService",
                           g_variant_new("(iisssiu)", resolve->interface, resolve->protocol, resolve->name,
                                         CAST_TYPE, resolve->domain, resolve->anyProtocol ? -1 : 0, 0),
                           G_VARIANT_TYPE("(iissssisqaayu)"), G_DBUS_CALL_FLAGS_NONE, 10000, avahi->cancel,
                           avahi_resolved, resolve);
}

// Every ServiceBrowser's signals come here; those of our type are ours (a
// browser's signals can come before its path is known, so the path is not
// what is matched).
static void avahi_signal(GDBusConnection *bus, const char *sender, const char *path, const char *interface,
                         const char *member, GVariant *parameters, gpointer user) {
    JbAvahi *avahi = user;
    if (avahi->stopped || !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(iisssu)"))) return;
    gint32 iface = 0, protocol = 0;
    const char *name = NULL, *type = NULL, *domain = NULL;
    g_variant_get(parameters, "(ii&s&s&su)", &iface, &protocol, &name, &type, &domain, NULL);
    if (g_strcmp0(type, CAST_TYPE) != 0) return;
    if (g_strcmp0(member, "ItemRemove") == 0) {
        avahi->found(name, name, name, "", 0, TRUE, avahi->data);
    } else if (g_strcmp0(member, "ItemNew") == 0) {
        Resolve *resolve = g_new0(Resolve, 1);
        resolve->avahi = avahi;
        resolve->name = g_strdup(name);
        resolve->interface = iface;
        resolve->protocol = protocol;
        resolve->domain = g_strdup(domain);
        avahi_resolve(resolve);
    }
}

static void avahi_browsing(GObject *source, GAsyncResult *result, gpointer user) {
    JbAvahi *avahi = user;
    GVariant *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, NULL);
    if (!reply) return;
    if (!avahi->stopped) {
        g_variant_get(reply, "(o)", &avahi->browser);
    } else {
        // Stopped while it was asked for: freed at once.
        const char *path = NULL;
        g_variant_get(reply, "(&o)", &path);
        g_dbus_connection_call(G_DBUS_CONNECTION(source), AVAHI, path, AVAHI ".ServiceBrowser", "Free", NULL,
                               NULL, G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL, NULL);
    }
    g_variant_unref(reply);
}

static void avahi_bus(GObject *source, GAsyncResult *result, gpointer user) {
    JbAvahi *avahi = user;
    GDBusConnection *bus = g_bus_get_finish(result, NULL);
    if (!bus) return;
    if (avahi->stopped) {
        g_object_unref(bus);
        return;
    }
    avahi->bus = bus;
    avahi->subscription = g_dbus_connection_signal_subscribe(bus, NULL, AVAHI ".ServiceBrowser", NULL, NULL, NULL,
                                                             G_DBUS_SIGNAL_FLAGS_NONE, avahi_signal, avahi, NULL);
    g_dbus_connection_call(bus, AVAHI, "/", AVAHI ".Server", "ServiceBrowserNew",
                           g_variant_new("(iissu)", -1, -1, CAST_TYPE, "local", 0), G_VARIANT_TYPE("(o)"),
                           G_DBUS_CALL_FLAGS_NONE, 10000, avahi->cancel, avahi_browsing, avahi);
}

JbAvahi *jb_avahi_browse(JbCastFound found, gpointer data) {
    JbAvahi *avahi = g_new0(JbAvahi, 1);
    avahi->cancel = g_cancellable_new();
    avahi->found = found;
    avahi->data = data;
    g_bus_get(G_BUS_TYPE_SYSTEM, avahi->cancel, avahi_bus, avahi);
    return avahi;
}

// ponytail: the JbAvahi itself is kept (a few bytes a browse), as late
// replies may still name it; freeing it needs a reference count like JbCast's.
void jb_avahi_stop(JbAvahi *avahi) {
    if (avahi->stopped) return;
    avahi->stopped = TRUE;
    g_cancellable_cancel(avahi->cancel);
    if (avahi->bus) {
        g_dbus_connection_signal_unsubscribe(avahi->bus, avahi->subscription);
        if (avahi->browser) {
            g_dbus_connection_call(avahi->bus, AVAHI, avahi->browser, AVAHI ".ServiceBrowser", "Free", NULL, NULL,
                                   G_DBUS_CALL_FLAGS_NONE, -1, NULL, NULL, NULL);
        }
    }
}
