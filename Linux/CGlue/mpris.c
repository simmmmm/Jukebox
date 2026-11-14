// org.mpris.MediaPlayer2 for Jukebox: the two interfaces GNOME Shell reads
// (the specification: https://specifications.freedesktop.org/mpris-spec/).
#include "glue.h"

static const char introspection[] =
    "<node>"
    " <interface name='org.mpris.MediaPlayer2'>"
    "  <method name='Raise'/><method name='Quit'/>"
    "  <property name='CanQuit' type='b' access='read'/>"
    "  <property name='CanRaise' type='b' access='read'/>"
    "  <property name='HasTrackList' type='b' access='read'/>"
    "  <property name='Identity' type='s' access='read'/>"
    "  <property name='DesktopEntry' type='s' access='read'/>"
    "  <property name='SupportedUriSchemes' type='as' access='read'/>"
    "  <property name='SupportedMimeTypes' type='as' access='read'/>"
    " </interface>"
    " <interface name='org.mpris.MediaPlayer2.Player'>"
    "  <method name='Next'/><method name='Previous'/><method name='Pause'/>"
    "  <method name='PlayPause'/><method name='Stop'/><method name='Play'/>"
    "  <method name='Seek'><arg name='Offset' type='x' direction='in'/></method>"
    "  <method name='SetPosition'><arg name='TrackId' type='o' direction='in'/>"
    "   <arg name='Position' type='x' direction='in'/></method>"
    "  <signal name='Seeked'><arg name='Position' type='x'/></signal>"
    "  <property name='PlaybackStatus' type='s' access='read'/>"
    "  <property name='Rate' type='d' access='read'/>"
    "  <property name='Metadata' type='a{sv}' access='read'/>"
    "  <property name='Volume' type='d' access='read'/>"
    "  <property name='Position' type='x' access='read'/>"
    "  <property name='MinimumRate' type='d' access='read'/>"
    "  <property name='MaximumRate' type='d' access='read'/>"
    "  <property name='CanGoNext' type='b' access='read'/>"
    "  <property name='CanGoPrevious' type='b' access='read'/>"
    "  <property name='CanPlay' type='b' access='read'/>"
    "  <property name='CanPause' type='b' access='read'/>"
    "  <property name='CanSeek' type='b' access='read'/>"
    "  <property name='CanControl' type='b' access='read'/>"
    " </interface>"
    "</node>";

#define PATH "/org/mpris/MediaPlayer2"
#define PLAYER "org.mpris.MediaPlayer2.Player"

static JbMprisHandler handler;
static GDBusConnection *bus;
static struct {
    char *status, *track_id, *title, *artist, *album, *art_url;
    gint64 length, position;
    gboolean can_next, can_previous;
} now = {0};

static GVariant *metadata(void) {
    GVariantBuilder b;
    g_variant_builder_init(&b, G_VARIANT_TYPE("a{sv}"));
    if (now.title) {
        g_variant_builder_add(&b, "{sv}", "mpris:trackid", g_variant_new_object_path(now.track_id));
        g_variant_builder_add(&b, "{sv}", "xesam:title", g_variant_new_string(now.title));
        if (now.artist && *now.artist) {
            const char *artists[] = {now.artist, NULL};
            g_variant_builder_add(&b, "{sv}", "xesam:artist", g_variant_new_strv(artists, -1));
        }
        if (now.album && *now.album)
            g_variant_builder_add(&b, "{sv}", "xesam:album", g_variant_new_string(now.album));
        if (now.art_url && *now.art_url)
            g_variant_builder_add(&b, "{sv}", "mpris:artUrl", g_variant_new_string(now.art_url));
        if (now.length > 0)
            g_variant_builder_add(&b, "{sv}", "mpris:length", g_variant_new_int64(now.length));
    }
    return g_variant_builder_end(&b);
}

static GVariant *property(GDBusConnection *c, const char *sender, const char *path, const char *interface,
                          const char *name, GError **error, gpointer data) {
    gboolean has = now.title != NULL;
    if (!g_strcmp0(name, "CanQuit") || !g_strcmp0(name, "CanRaise") || !g_strcmp0(name, "CanControl"))
        return g_variant_new_boolean(TRUE);
    if (!g_strcmp0(name, "HasTrackList")) return g_variant_new_boolean(FALSE);
    if (!g_strcmp0(name, "Identity")) return g_variant_new_string("Jukebox");
    if (!g_strcmp0(name, "DesktopEntry")) return g_variant_new_string("com.tijmen.Jukebox");
    if (!g_strcmp0(name, "SupportedUriSchemes") || !g_strcmp0(name, "SupportedMimeTypes"))
        return g_variant_new_strv(NULL, 0);
    if (!g_strcmp0(name, "PlaybackStatus")) return g_variant_new_string(now.status ? now.status : "Stopped");
    if (!g_strcmp0(name, "Rate") || !g_strcmp0(name, "MinimumRate") || !g_strcmp0(name, "MaximumRate") ||
        !g_strcmp0(name, "Volume"))
        return g_variant_new_double(1.0);
    if (!g_strcmp0(name, "Metadata")) return metadata();
    if (!g_strcmp0(name, "Position")) return g_variant_new_int64(now.position);
    if (!g_strcmp0(name, "CanGoNext")) return g_variant_new_boolean(has && now.can_next);
    if (!g_strcmp0(name, "CanGoPrevious")) return g_variant_new_boolean(has && now.can_previous);
    if (!g_strcmp0(name, "CanPlay") || !g_strcmp0(name, "CanPause") || !g_strcmp0(name, "CanSeek"))
        return g_variant_new_boolean(has);
    g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY, "No property %s", name);
    return NULL;
}

static void call(GDBusConnection *c, const char *sender, const char *path, const char *interface,
                 const char *method, GVariant *parameters, GDBusMethodInvocation *invocation, gpointer data) {
    gint64 value = 0;
    JbMprisCommand command;
    if (!g_strcmp0(method, "PlayPause")) command = JB_MPRIS_PLAY_PAUSE;
    else if (!g_strcmp0(method, "Play")) command = JB_MPRIS_PLAY;
    else if (!g_strcmp0(method, "Pause")) command = JB_MPRIS_PAUSE;
    else if (!g_strcmp0(method, "Next")) command = JB_MPRIS_NEXT;
    else if (!g_strcmp0(method, "Previous")) command = JB_MPRIS_PREVIOUS;
    else if (!g_strcmp0(method, "Stop")) command = JB_MPRIS_STOP;
    else if (!g_strcmp0(method, "Raise")) command = JB_MPRIS_RAISE;
    else if (!g_strcmp0(method, "Quit")) command = JB_MPRIS_QUIT;
    else if (!g_strcmp0(method, "Seek")) {
        command = JB_MPRIS_SEEK_BY;
        g_variant_get(parameters, "(x)", &value);
    } else if (!g_strcmp0(method, "SetPosition")) {
        const char *track = NULL;
        command = JB_MPRIS_SEEK_TO;
        g_variant_get(parameters, "(&ox)", &track, &value);
        // For another song than the one playing: ignored, as MPRIS says.
        if (g_strcmp0(track, now.track_id)) {
            g_dbus_method_invocation_return_value(invocation, NULL);
            return;
        }
    } else {
        g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD,
                                              "No method %s", method);
        return;
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
    if (handler) handler(command, value);
}

static const GDBusInterfaceVTable vtable = {call, property, NULL, {0}};

static void acquired(GDBusConnection *connection, const char *name, gpointer data) {
    GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(introspection, NULL);
    bus = connection;
    for (int i = 0; info->interfaces[i]; i++)
        g_dbus_connection_register_object(connection, PATH, info->interfaces[i], &vtable, NULL, NULL, NULL);
}

void jb_mpris_start(JbMprisHandler h) {
    handler = h;
    g_bus_own_name(G_BUS_TYPE_SESSION, "org.mpris.MediaPlayer2.Jukebox", G_BUS_NAME_OWNER_FLAGS_NONE,
                   acquired, NULL, NULL, NULL, NULL);
}

static void set(char **field, const char *value) {
    g_free(*field);
    *field = g_strdup(value);
}

void jb_mpris_update(const char *status, const char *track_id, const char *title, const char *artist,
                     const char *album, const char *art_url, gint64 length, gboolean can_next,
                     gboolean can_previous) {
    set(&now.status, status);
    set(&now.track_id, track_id);
    set(&now.title, title);
    set(&now.artist, artist);
    set(&now.album, album);
    set(&now.art_url, art_url);
    now.length = length;
    now.can_next = can_next;
    now.can_previous = can_previous;
    if (!bus) return;
    gboolean has = title != NULL;
    GVariantBuilder changed;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&changed, "{sv}", "PlaybackStatus", g_variant_new_string(status));
    g_variant_builder_add(&changed, "{sv}", "Metadata", metadata());
    g_variant_builder_add(&changed, "{sv}", "CanGoNext", g_variant_new_boolean(has && can_next));
    g_variant_builder_add(&changed, "{sv}", "CanGoPrevious", g_variant_new_boolean(has && can_previous));
    g_variant_builder_add(&changed, "{sv}", "CanPlay", g_variant_new_boolean(has));
    g_variant_builder_add(&changed, "{sv}", "CanPause", g_variant_new_boolean(has));
    g_variant_builder_add(&changed, "{sv}", "CanSeek", g_variant_new_boolean(has));
    g_dbus_connection_emit_signal(bus, NULL, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                  g_variant_new("(sa{sv}as)", PLAYER, &changed, NULL), NULL);
}

void jb_mpris_set_position(gint64 position, gboolean seeked) {
    now.position = position;
    if (bus && seeked)
        g_dbus_connection_emit_signal(bus, NULL, PATH, PLAYER, "Seeked", g_variant_new("(x)", position), NULL);
}
