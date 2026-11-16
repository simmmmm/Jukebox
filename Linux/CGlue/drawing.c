// What the brand's drawings need of C (Linux/App/Drawings.swift): a blur,
// which cairo lacks, and a widget that shows a drawing past its own box, as
// the sleeve's shadows fall on the page (build/design-round/drawings/spec.md).
#include "glue.h"
#include <math.h>

// One box over `n` pixels `step` bytes apart, its radius `r`, with what lies
// outside the line counted as clear. `sums` holds (n + 1) * 4.
static void box_line(guint8 *line, int n, int step, int r, guint32 *sums) {
    for (int c = 0; c < 4; c++) sums[c] = 0;
    for (int i = 0; i < n; i++)
        for (int c = 0; c < 4; c++) sums[(i + 1) * 4 + c] = sums[i * 4 + c] + line[i * step + c];
    int width = 2 * r + 1;
    for (int i = 0; i < n; i++) {
        int low = MAX(i - r, 0), high = MIN(i + r + 1, n);
        for (int c = 0; c < 4; c++)
            line[i * step + c] = (guint8)((sums[high * 4 + c] - sums[low * 4 + c] + width / 2) / width);
    }
}

// Three boxes make a Gaussian of `sigma` to within a level or two, in time
// that does not grow with the radius. The widths are the W3C's "boxes for
// Gauss": three passes, each of variance sigma² / 3.
void jb_blur(unsigned char *data, int width, int height, int stride, double sigma) {
    if (sigma <= 0 || width <= 0 || height <= 0) return;
    double ideal = sqrt(4 * sigma * sigma + 1);
    int lower = (int)floor(ideal);
    if (lower % 2 == 0) lower--;
    int upper = lower + 2;
    int lowerCount = (int)round((12 * sigma * sigma - 3.0 * lower * lower - 12.0 * lower - 9) / (-4.0 * lower - 4));
    guint32 *sums = g_new(guint32, (MAX(width, height) + 1) * 4);
    for (int pass = 0; pass < 3; pass++) {
        int r = ((pass < lowerCount ? lower : upper) - 1) / 2;
        if (r < 1) continue;
        for (int y = 0; y < height; y++) box_line(data + (gsize)y * stride, width, 4, r, sums);
        for (int x = 0; x < width; x++) box_line(data + x * 4, height, stride, r, sums);
    }
    g_free(sums);
}

// A texture shown in a rect of the widget's own points, which may reach past
// its allocation: GTK draws a widget's content unclipped unless it says
// otherwise, as it does a CSS box-shadow. Its natural size is `width` by
// `height`; given less width (a narrow window), down to `min_width`, the
// whole drawing shrinks with it, height for width, rather than widen the
// window. Decoration: hidden from screen readers.
struct _JbDrawing {
    GtkWidget parent;
    GdkTexture *texture;
    graphene_rect_t bounds;
    int width, height, min_width;
};

G_DECLARE_FINAL_TYPE(JbDrawing, jb_drawing, JB, DRAWING, GtkWidget)
G_DEFINE_FINAL_TYPE(JbDrawing, jb_drawing, GTK_TYPE_WIDGET)

static double jb_drawing_fit(JbDrawing *self, int width) {
    return self->width > 0 && width >= 0 && width < self->width ? (double)width / self->width : 1;
}

static GtkSizeRequestMode jb_drawing_request_mode(GtkWidget *widget) { return GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH; }

static void jb_drawing_measure(GtkWidget *widget, GtkOrientation orientation, int for_size,
                               int *minimum, int *natural, int *minimum_baseline, int *natural_baseline) {
    JbDrawing *self = JB_DRAWING(widget);
    if (orientation == GTK_ORIENTATION_HORIZONTAL) {
        *minimum = self->min_width;
        *natural = self->width;
    } else {
        *minimum = *natural = (int)ceil(self->height * jb_drawing_fit(self, for_size));
    }
}

static void jb_drawing_snapshot(GtkWidget *widget, GtkSnapshot *snapshot) {
    JbDrawing *self = JB_DRAWING(widget);
    if (!self->texture) return;
    double fit = jb_drawing_fit(self, gtk_widget_get_width(widget));
    gtk_snapshot_save(snapshot);
    gtk_snapshot_scale(snapshot, fit, fit);
    gtk_snapshot_append_texture(snapshot, self->texture, &self->bounds);
    gtk_snapshot_restore(snapshot);
}

static void jb_drawing_dispose(GObject *object) {
    g_clear_object(&JB_DRAWING(object)->texture);
    G_OBJECT_CLASS(jb_drawing_parent_class)->dispose(object);
}

static void jb_drawing_class_init(JbDrawingClass *klass) {
    G_OBJECT_CLASS(klass)->dispose = jb_drawing_dispose;
    GTK_WIDGET_CLASS(klass)->get_request_mode = jb_drawing_request_mode;
    GTK_WIDGET_CLASS(klass)->measure = jb_drawing_measure;
    GTK_WIDGET_CLASS(klass)->snapshot = jb_drawing_snapshot;
    gtk_widget_class_set_accessible_role(GTK_WIDGET_CLASS(klass), GTK_ACCESSIBLE_ROLE_PRESENTATION);
}

static void jb_drawing_init(JbDrawing *self) {}

GtkWidget *jb_drawing_new(int width, int height, int min_width) {
    JbDrawing *self = g_object_new(jb_drawing_get_type(), NULL);
    self->width = width;
    self->height = height;
    self->min_width = MIN(min_width, width);
    return GTK_WIDGET(self);
}

void jb_drawing_resize(GtkWidget *widget, int width, int height, int min_width) {
    JbDrawing *self = JB_DRAWING(widget);
    self->width = width;
    self->height = height;
    self->min_width = MIN(min_width, width);
    gtk_widget_queue_resize(widget);
}

void jb_drawing_set(GtkWidget *widget, GdkTexture *texture, double x, double y, double width, double height) {
    JbDrawing *self = JB_DRAWING(widget);
    g_set_object(&self->texture, texture);
    graphene_rect_init(&self->bounds, x, y, width, height);
    gtk_widget_queue_draw(widget);
}
