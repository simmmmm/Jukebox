#include "glue.h"
#include <math.h>
#include <libsecret/secret.h>

// Two items, as the iPhone's keychain has them, told apart by "account":
// "credentials", the session signed in, and "accounts", every one kept.
static const SecretSchema *schema(void) {
    static const SecretSchema s = {
        "com.tijmen.Jukebox", SECRET_SCHEMA_NONE,
        {{"account", SECRET_SCHEMA_ATTRIBUTE_STRING}, {NULL, 0}},
    };
    return &s;
}

gboolean jb_secret_available(void) {
    static int known = -1;
    if (known >= 0) return known;
    known = 0;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (!bus) return FALSE;
    // Running, or started when asked for.
    const char *lists[] = {"ListNames", "ListActivatableNames"};
    for (int i = 0; i < 2 && !known; i++) {
        GVariant *reply = g_dbus_connection_call_sync(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", lists[i], NULL, G_VARIANT_TYPE("(as)"), G_DBUS_CALL_FLAGS_NONE, 2000, NULL, NULL);
        if (!reply) continue;
        GVariantIter *names;
        const char *name;
        g_variant_get(reply, "(as)", &names);
        while (g_variant_iter_next(names, "&s", &name))
            if (!g_strcmp0(name, "org.freedesktop.secrets")) known = 1;
        g_variant_iter_free(names);
        g_variant_unref(reply);
    }
    g_object_unref(bus);
    return known;
}

gboolean jb_secret_store(const char *account, const char *json) {
    // Stored over the item with the same attributes, in place (libsecret
    // replaces it): never cleared first, so a failed store keeps the old.
    // The session keeps the label it always had; the list has its own.
    const char *label = g_strcmp0(account, "credentials") ? "Jukebox accounts" : "Jukebox";
    return secret_password_store_sync(schema(), SECRET_COLLECTION_DEFAULT, label,
                                      json, NULL, NULL, "account", account, NULL);
}

char *jb_secret_load(const char *account, gboolean *failed) {
    GError *error = NULL;
    char *found = secret_password_lookup_sync(schema(), NULL, &error, "account", account, NULL);
    // No item is no error; a keyring that would not answer (locked, gone) is.
    *failed = error != NULL;
    g_clear_error(&error);
    if (!found) return NULL;
    char *copy = g_strdup(found);
    secret_password_free(found);
    return copy;
}

void jb_secret_clear(const char *account) {
    secret_password_clear_sync(schema(), NULL, NULL, "account", account, NULL);
}

void jb_set_string(gpointer object, const char *name, const char *value) { g_object_set(object, name, value, NULL); }
void jb_set_double(gpointer object, const char *name, double value) { g_object_set(object, name, value, NULL); }
void jb_set_int(gpointer object, const char *name, int value) { g_object_set(object, name, value, NULL); }
void jb_set_bool(gpointer object, const char *name, gboolean value) { g_object_set(object, name, value, NULL); }
void jb_set_object(gpointer object, const char *name, gpointer value) { g_object_set(object, name, value, NULL); }

GstMessageType jb_message_type(GstMessage *message) { return GST_MESSAGE_TYPE(message); }
gboolean jb_message_is_from(GstMessage *message, gpointer object) { return GST_MESSAGE_SRC(message) == GST_OBJECT_CAST(object); }

char *jb_message_error(GstMessage *message) {
    GError *error = NULL;
    gst_message_parse_error(message, &error, NULL);
    char *text = g_strdup(error ? error->message : "");
    g_clear_error(&error);
    return text;
}

gint64 jb_seconds(double seconds) { return (gint64)(seconds * GST_SECOND); }
double jb_from_nanoseconds(gint64 nanoseconds) { return (double)nanoseconds / GST_SECOND; }

AdwBreakpoint *jb_breakpoint(GtkWidget *window, const char *condition) {
    AdwBreakpoint *breakpoint = adw_breakpoint_new(adw_breakpoint_condition_parse(condition));
    adw_application_window_add_breakpoint(ADW_APPLICATION_WINDOW(window), breakpoint);
    return breakpoint;
}

void jb_breakpoint_set(AdwBreakpoint *breakpoint, gpointer object, const char *property, gboolean value) {
    GValue setting = G_VALUE_INIT;
    g_value_init(&setting, G_TYPE_BOOLEAN);
    g_value_set_boolean(&setting, value);
    adw_breakpoint_add_setter(breakpoint, G_OBJECT(object), property, &setting);
    g_value_unset(&setting);
}

typedef struct {
    JbPointHandler handler;
    gpointer data;
    GDestroyNotify destroy;
} PointClosure;

static void point_pressed(GtkGestureClick *gesture, int presses, double x, double y, gpointer user) {
    PointClosure *closure = user;
    gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
    closure->handler(x, y, closure->data);
}

static void point_free(gpointer user, GClosure *unused) {
    PointClosure *closure = user;
    if (closure->destroy) closure->destroy(closure->data);
    g_free(closure);
}

void jb_on_secondary_click(GtkWidget *widget, JbPointHandler handler, gpointer data, GDestroyNotify destroy) {
    PointClosure *closure = g_new0(PointClosure, 1);
    closure->handler = handler;
    closure->data = data;
    closure->destroy = destroy;
    GtkGesture *click = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), GDK_BUTTON_SECONDARY);
    g_signal_connect_data(click, "pressed", G_CALLBACK(point_pressed), closure, point_free, 0);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click));
}

// A click on a song's row, for picking songs (Jukebox/Library/TrackPicks.swift):
// with Ctrl or Shift held it is claimed, so the list does not also play the
// row; a plain one is told too, and left to the list, which plays it.
typedef struct {
    JbRowClick handler;
    gpointer data;
    GDestroyNotify destroy;
} RowClickClosure;

static void row_click_pressed(GtkGestureClick *gesture, int presses, double x, double y, gpointer user) {
    RowClickClosure *closure = user;
    GdkModifierType state = gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(gesture));
    int toggle = (state & GDK_CONTROL_MASK) != 0, extend = (state & GDK_SHIFT_MASK) != 0;
    if (toggle || extend) gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
    closure->handler(toggle, extend, closure->data);
}

static void row_click_free(gpointer user, GClosure *unused) {
    RowClickClosure *closure = user;
    if (closure->destroy) closure->destroy(closure->data);
    g_free(closure);
}

void jb_on_row_click(GtkWidget *widget, JbRowClick handler, gpointer data, GDestroyNotify destroy) {
    RowClickClosure *closure = g_new0(RowClickClosure, 1);
    closure->handler = handler;
    closure->data = data;
    closure->destroy = destroy;
    GtkGesture *click = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), GDK_BUTTON_PRIMARY);
    g_signal_connect_data(click, "pressed", G_CALLBACK(row_click_pressed), closure, row_click_free, 0);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(click));
}

void jb_popover_point_to(GtkWidget *popover, double x, double y) {
    GdkRectangle at = {(int)x, (int)y, 1, 1};
    gtk_popover_set_pointing_to(GTK_POPOVER(popover), &at);
}

// A row dragged onto another, as libadwaita's own lists reorder (its demo,
// GNOME Settings): a GtkDragSource and a GtkDropTarget on each row, the
// row's place as the drag's value, and the row itself as what is dragged.
// The prepare and drop signals take doubles and give a value back, which a
// Swift closure connected as a signal cannot.
typedef struct {
    JbRowPlace place;
    JbRowMoved moved;
    gpointer data;
    GDestroyNotify destroy;
    double x, y;           // where the drag took hold of the row
} RowClosure;

static void row_free(gpointer user) {
    RowClosure *closure = user;
    if (closure->destroy) closure->destroy(closure->data);
    g_free(closure);
}

static GdkContentProvider *row_prepare(GtkDragSource *source, double x, double y, gpointer user) {
    RowClosure *closure = user;
    closure->x = x;
    closure->y = y;
    GValue place = G_VALUE_INIT;
    g_value_init(&place, G_TYPE_INT);
    g_value_set_int(&place, closure->place(closure->data));
    GdkContentProvider *content = gdk_content_provider_new_for_value(&place);
    g_value_unset(&place);
    return content;
}

static void row_begin(GtkDragSource *source, GdkDrag *drag, gpointer user) {
    RowClosure *closure = user;
    GtkWidget *row = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(source));
    GdkPaintable *icon = gtk_widget_paintable_new(row);
    gtk_drag_source_set_icon(source, icon, (int)closure->x, (int)closure->y);
    g_object_unref(icon);
}

static gboolean row_drop(GtkDropTarget *target, const GValue *value, double x, double y, gpointer user) {
    RowClosure *closure = user;
    if (!G_VALUE_HOLDS_INT(value)) return FALSE;
    closure->moved(g_value_get_int(value), closure->place(closure->data), closure->data);
    return TRUE;
}

void jb_reorderable_row(GtkWidget *row, JbRowPlace place, JbRowMoved moved, gpointer data, GDestroyNotify destroy) {
    RowClosure *closure = g_new0(RowClosure, 1);
    closure->place = place;
    closure->moved = moved;
    closure->data = data;
    closure->destroy = destroy;
    // Freed with the row, after both controllers.
    g_object_set_data_full(G_OBJECT(row), "jb-reorderable", closure, row_free);
    GtkDragSource *source = gtk_drag_source_new();
    gtk_drag_source_set_actions(source, GDK_ACTION_MOVE);
    g_signal_connect(source, "prepare", G_CALLBACK(row_prepare), closure);
    g_signal_connect(source, "drag-begin", G_CALLBACK(row_begin), closure);
    gtk_widget_add_controller(row, GTK_EVENT_CONTROLLER(source));
    GtkDropTarget *target = gtk_drop_target_new(G_TYPE_INT, GDK_ACTION_MOVE);
    g_signal_connect(target, "drop", G_CALLBACK(row_drop), closure);
    gtk_widget_add_controller(row, GTK_EVENT_CONTROLLER(target));
}

// Drag to scroll a shelf, as the photographer asked: "kan je bij die
// scrollable dingen ervoor zorgen dat ik met de muis kan slepen".
// Below 8 px of movement nothing is claimed, so a press on a tile stays a
// click; past it the gesture claims the press, and the tile under the
// pointer never sees a click.
typedef struct {
    GtkAdjustment *adjustment;
    double start;          // the adjustment's value when the press began
    double last_x;         // the pointer's offset at the last update
    gint64 last_time;      // and when, in microseconds
    double velocity;       // px per second, for the throw
    gboolean dragging;
    guint tick;            // the throw's tick callback, 0 when none
    GtkWidget *widget;
} Drag;

static void drag_stop_throw(Drag *d) {
    if (d->tick) {
        gtk_widget_remove_tick_callback(d->widget, d->tick);
        d->tick = 0;
    }
}

static gboolean drag_throw(GtkWidget *widget, GdkFrameClock *clock, gpointer user) {
    Drag *d = user;
    gint64 now = gdk_frame_clock_get_frame_time(clock);
    double dt = (now - d->last_time) / 1e6;
    d->last_time = now;
    if (dt <= 0 || dt > 0.1) dt = 1.0 / 60;
    gtk_adjustment_set_value(d->adjustment, gtk_adjustment_get_value(d->adjustment) - d->velocity * dt);
    // Friction: the throw loses most of its speed in about half a second.
    d->velocity *= pow(0.004, dt);
    if (fabs(d->velocity) < 20) {
        d->tick = 0;
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static void drag_begin(GtkGestureDrag *gesture, double x, double y, gpointer user) {
    Drag *d = user;
    drag_stop_throw(d);
    d->start = gtk_adjustment_get_value(d->adjustment);
    d->last_x = 0;
    d->last_time = g_get_monotonic_time();
    d->velocity = 0;
    d->dragging = FALSE;
}

static void drag_update(GtkGestureDrag *gesture, double x, double y, gpointer user) {
    Drag *d = user;
    if (!d->dragging) {
        if (fabs(x) < 8 || fabs(y) > fabs(x)) return;
        d->dragging = TRUE;
        gtk_gesture_set_state(GTK_GESTURE(gesture), GTK_EVENT_SEQUENCE_CLAIMED);
        gtk_widget_set_cursor_from_name(d->widget, "grabbing");
    }
    gint64 now = g_get_monotonic_time();
    double dt = (now - d->last_time) / 1e6;
    if (dt > 0) d->velocity = 0.7 * d->velocity + 0.3 * ((x - d->last_x) / dt);
    d->last_x = x;
    d->last_time = now;
    gtk_adjustment_set_value(d->adjustment, d->start - x);
}

static void drag_end(GtkGestureDrag *gesture, double x, double y, gpointer user) {
    Drag *d = user;
    if (!d->dragging) return;
    d->dragging = FALSE;
    gtk_widget_set_cursor(d->widget, NULL);
    // Let go after a pause: no throw.
    if (g_get_monotonic_time() - d->last_time > 80000) d->velocity = 0;
    if (fabs(d->velocity) > 200) {
        d->last_time = 0;
        d->tick = gtk_widget_add_tick_callback(d->widget, drag_throw, d, NULL);
    }
}

void jb_drag_to_scroll(GtkWidget *scrolled) {
    Drag *d = g_new0(Drag, 1);
    d->adjustment = gtk_scrolled_window_get_hadjustment(GTK_SCROLLED_WINDOW(scrolled));
    d->widget = scrolled;
    GtkGesture *drag = gtk_gesture_drag_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(drag), GDK_BUTTON_PRIMARY);
    // Mouse only: touch and touchpads already scroll the shelf themselves.
    gtk_gesture_single_set_exclusive(GTK_GESTURE_SINGLE(drag), FALSE);
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(drag), GTK_PHASE_CAPTURE);
    g_signal_connect(drag, "drag-begin", G_CALLBACK(drag_begin), d);
    g_signal_connect(drag, "drag-update", G_CALLBACK(drag_update), d);
    g_signal_connect(drag, "drag-end", G_CALLBACK(drag_end), d);
    gtk_widget_add_controller(scrolled, GTK_EVENT_CONTROLLER(drag));
    g_object_set_data_full(G_OBJECT(scrolled), "jb-drag", d, g_free);
}

// A picture chosen for a playlist's cover (Linux/App/Extras.swift): GTK's
// file dialog, the portal's under Flatpak, showing images only. `handler`
// hears the file's path, or NULL when nothing was chosen.
typedef struct {
    JbPathHandler handler;
    gpointer data;
    GDestroyNotify destroy;
} PathClosure;

static void picture_chosen(GObject *source, GAsyncResult *result, gpointer user) {
    PathClosure *closure = user;
    GFile *file = gtk_file_dialog_open_finish(GTK_FILE_DIALOG(source), result, NULL);
    char *path = file ? g_file_get_path(file) : NULL;
    closure->handler(path, closure->data);
    g_free(path);
    if (file) g_object_unref(file);
    if (closure->destroy) closure->destroy(closure->data);
    g_free(closure);
}

void jb_choose_picture(GtkWindow *parent, const char *title, JbPathHandler handler, gpointer data, GDestroyNotify destroy) {
    PathClosure *closure = g_new0(PathClosure, 1);
    closure->handler = handler;
    closure->data = data;
    closure->destroy = destroy;
    GtkFileDialog *dialog = gtk_file_dialog_new();
    gtk_file_dialog_set_title(dialog, title);
    GtkFileFilter *filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, "Pictures");
    gtk_file_filter_add_pixbuf_formats(filter);
    GListStore *filters = g_list_store_new(GTK_TYPE_FILE_FILTER);
    g_list_store_append(filters, filter);
    gtk_file_dialog_set_filters(dialog, G_LIST_MODEL(filters));
    gtk_file_dialog_open(dialog, parent, NULL, picture_chosen, closure);
    g_object_unref(filters);
    g_object_unref(filter);
    g_object_unref(dialog);
}

// The picture at `path` as a JPEG of at most `side` on its longer side, for
// a server to take: a photographer's file may be 50 MB. NULL when GdkPixbuf
// cannot read it; g_free the bytes.
guchar *jb_jpeg_from_file(const char *path, int side, gsize *length) {
    GdkPixbuf *pixbuf = gdk_pixbuf_new_from_file_at_scale(path, side, side, TRUE, NULL);
    if (!pixbuf) return NULL;
    // The camera's orientation, as the photograph is seen.
    GdkPixbuf *upright = gdk_pixbuf_apply_embedded_orientation(pixbuf);
    g_object_unref(pixbuf);
    gchar *buffer = NULL;
    char *keys[] = {"quality", NULL};
    char *values[] = {"90", NULL};
    gboolean done = gdk_pixbuf_save_to_bufferv(upright, &buffer, length, "jpeg", keys, values, NULL);
    g_object_unref(upright);
    return done ? (guchar *)buffer : NULL;
}

void jb_accessible_label(GtkWidget *widget, const char *label) {
    gtk_accessible_update_property(GTK_ACCESSIBLE(widget), GTK_ACCESSIBLE_PROPERTY_LABEL, label, -1);
}
