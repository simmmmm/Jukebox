// SSDP's question and its answers (UPnP.swift): one UDP socket of GIO's on
// a port of the system's choosing, the M-SEARCH sent to the multicast
// group, the answers read on GLib's main loop as they come, so every
// callback is on the main thread. No group is joined: the answers come
// back to this socket alone. A host firewall that drops them (they are no
// reply it tracks) leaves only mDNS, which finds a Sonos all the same.

#include "glue.h"

struct JbSsdp {
    GSocket *socket;
    GSource *source;
    JbSsdpReceived received;
    gpointer data;
    // Answers count until then (monotonic µs): a datagram outside a
    // search's window is no answer to it.
    gint64 until;
};

static gboolean ssdp_readable(GSocket *socket, GIOCondition condition, gpointer user) {
    JbSsdp *ssdp = user;
    char buffer[4096];
    gssize length;
    GSocketAddress *from = NULL;
    // Every datagram waiting, each a whole answer; read even when it is
    // dropped, or the socket stays readable.
    while ((length = g_socket_receive_from(socket, &from, buffer, sizeof buffer - 1, NULL, NULL)) > 0) {
        buffer[length] = 0;
        if (g_get_monotonic_time() <= ssdp->until && G_IS_INET_SOCKET_ADDRESS(from)) {
            char *address = g_inet_address_to_string(
                g_inet_socket_address_get_address(G_INET_SOCKET_ADDRESS(from)));
            ssdp->received(buffer, address, ssdp->data);
            g_free(address);
        }
        g_clear_object(&from);
    }
    g_clear_object(&from);
    return G_SOURCE_CONTINUE;
}

JbSsdp *jb_ssdp_open(JbSsdpReceived received, gpointer data) {
    GSocket *socket = g_socket_new(G_SOCKET_FAMILY_IPV4, G_SOCKET_TYPE_DATAGRAM, G_SOCKET_PROTOCOL_UDP, NULL);
    if (!socket) return NULL;
    GInetAddress *any = g_inet_address_new_any(G_SOCKET_FAMILY_IPV4);
    GSocketAddress *here = g_inet_socket_address_new(any, 0);
    gboolean bound = g_socket_bind(socket, here, FALSE, NULL);
    g_object_unref(here);
    g_object_unref(any);
    if (!bound) {
        g_object_unref(socket);
        return NULL;
    }
    g_socket_set_blocking(socket, FALSE);
    // Past one router at most: the speakers are in the house.
    g_socket_set_multicast_ttl(socket, 2);
    JbSsdp *ssdp = g_new0(JbSsdp, 1);
    ssdp->socket = socket;
    ssdp->received = received;
    ssdp->data = data;
    ssdp->source = g_socket_create_source(socket, G_IO_IN, NULL);
    g_source_set_callback(ssdp->source, (GSourceFunc)ssdp_readable, ssdp, NULL);
    g_source_attach(ssdp->source, NULL);
    return ssdp;
}

void jb_ssdp_search(JbSsdp *ssdp, const char *message, int wait) {
    ssdp->until = g_get_monotonic_time() + (gint64)(wait + 1) * G_USEC_PER_SEC;
    GInetAddress *group = g_inet_address_new_from_string("239.255.255.250");
    GSocketAddress *to = g_inet_socket_address_new(group, 1900);
    g_socket_send_to(ssdp->socket, to, message, strlen(message), NULL, NULL);
    g_object_unref(to);
    g_object_unref(group);
}

// Synchronous: once it returns, nothing more is called.
void jb_ssdp_close(JbSsdp *ssdp) {
    g_source_destroy(ssdp->source);
    g_source_unref(ssdp->source);
    g_socket_close(ssdp->socket, NULL);
    g_object_unref(ssdp->socket);
    g_free(ssdp);
}
