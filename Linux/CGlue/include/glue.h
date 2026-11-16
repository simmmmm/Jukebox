// What Swift cannot call in C as it is: functions with "..." and macros.
// One small function each, nothing more.
#ifndef JUKEBOX_GLUE_H
#define JUKEBOX_GLUE_H

#include <adwaita.h>
#include <gst/gst.h>

// The keyring (libsecret's calls take attribute lists as "...").
// jb_secret_load's answer is the caller's, freed with g_free.
// Whether the desktop has a keyring at all (GNOME Keyring, KWallet): a
// bare Hyprland or XFCE may have none, and asking one that is not there
// waits out D-Bus's 25 seconds.
gboolean jb_secret_available(void);
gboolean jb_secret_store(const char *json);
char *jb_secret_load(void);
void jb_secret_clear(void);

// g_object_set, one property of each kind used.
void jb_set_string(gpointer object, const char *name, const char *value);
void jb_set_double(gpointer object, const char *name, double value);
void jb_set_int(gpointer object, const char *name, int value);
void jb_set_bool(gpointer object, const char *name, gboolean value);
void jb_set_object(gpointer object, const char *name, gpointer value);

// GStreamer's message macros.
GstMessageType jb_message_type(GstMessage *message);
gboolean jb_message_is_from(GstMessage *message, gpointer object);
// The error's text; the caller's, freed with g_free.
char *jb_message_error(GstMessage *message);
gint64 jb_seconds(double seconds);
double jb_from_nanoseconds(gint64 nanoseconds);

// The window's breakpoints: what folds, and what goes, when it is narrow
// (an AdwBreakpoint's setter takes a GValue, whose types are macros). One
// breakpoint applies at a time, the last added that matches.
AdwBreakpoint *jb_breakpoint(GtkWidget *window, const char *condition);
void jb_breakpoint_set(AdwBreakpoint *breakpoint, gpointer object, const char *property, gboolean value);

// A click with the secondary button, with where it was: the gesture's
// arguments are doubles, which a Swift closure connected as a signal cannot
// take. `destroy` frees `data` when the widget goes.
typedef void (*JbPointHandler)(double x, double y, gpointer data);
void jb_on_secondary_click(GtkWidget *widget, JbPointHandler handler, gpointer data, GDestroyNotify destroy);
// A horizontal GtkScrolledWindow scrolled by dragging with the mouse, and
// thrown with a little momentum when let go. A press that hardly moves is
// still a click on what it is over.
void jb_drag_to_scroll(GtkWidget *scrolled);
// A popover's arrow at a point of its parent.
void jb_popover_point_to(GtkWidget *popover, double x, double y);
// A list's row that can be dragged onto another row of its list: `moved`
// gets the dragged row's place and the place of the row it was dropped on,
// each as `place` says it at that moment (a list reuses its rows).
typedef int (*JbRowPlace)(gpointer data);
typedef void (*JbRowMoved)(int from, int to, gpointer data);
void jb_reorderable_row(GtkWidget *row, JbRowPlace place, JbRowMoved moved, gpointer data, GDestroyNotify destroy);

// The brand's drawings (drawing.c). A Gaussian blur of `sigma` pixels over
// an ARGB32 image surface's bytes, in place.
void jb_blur(unsigned char *data, int width, int height, int stride, double sigma);
// A widget that shows `texture` at (x, y, width, height) of its own points,
// which may reach past its box. `width` by `height` points; in less width,
// down to `min_width`, all of it smaller.
GtkWidget *jb_drawing_new(int width, int height, int min_width);
// The drawing's own size changed (Now Playing's sleeve follows its room).
void jb_drawing_resize(GtkWidget *widget, int width, int height, int min_width);
void jb_drawing_set(GtkWidget *widget, GdkTexture *texture, double x, double y, double width, double height);

// MPRIS: how GNOME's own media controls (the clock's menu, the lock
// screen, the keyboard's media keys) see and steer a player. D-Bus by hand
// is C's work; Swift gives the state and gets the commands.
typedef enum {
    JB_MPRIS_PLAY_PAUSE, JB_MPRIS_PLAY, JB_MPRIS_PAUSE, JB_MPRIS_NEXT, JB_MPRIS_PREVIOUS,
    JB_MPRIS_STOP, JB_MPRIS_SEEK_BY, JB_MPRIS_SEEK_TO, JB_MPRIS_RAISE, JB_MPRIS_QUIT
} JbMprisCommand;
// `microseconds`: for SEEK_BY the step, for SEEK_TO the place.
typedef void (*JbMprisHandler)(JbMprisCommand command, gint64 microseconds);
void jb_mpris_start(JbMprisHandler handler);
// What plays now; NULL title for nothing. `position` in microseconds, as
// MPRIS counts; asked for again whenever a client reads Position.
void jb_mpris_update(const char *status, const char *track_id, const char *title, const char *artist,
                     const char *album, const char *art_url, gint64 length, gboolean can_next,
                     gboolean can_previous);
void jb_mpris_set_position(gint64 position, gboolean seeked);

#endif
