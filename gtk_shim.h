#ifndef GTK_SHIM_H
#define GTK_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque types – Zig never sees the real GTK headers */
typedef struct _GtkApplication GtkApplication;
typedef struct _GtkWidget GtkWidget;
typedef void *gpointer;

typedef void (*KeybindActivateFn)(GtkApplication *, gpointer);

/* Function declarations only */
GtkApplication *kb_application_new(const char *application_id);

void kb_application_connect_activate(
    GtkApplication *app,
    KeybindActivateFn callback,
    gpointer user_data
);

int kb_application_run(GtkApplication *app);

GtkWidget *kb_create_window(GtkApplication *app);
void kb_configure_window(GtkWidget *window);

GtkWidget *kb_create_text_view(const char *text);
GtkWidget *kb_create_scrolled_window(GtkWidget *text_view);

void kb_window_set_child(GtkWidget *window, GtkWidget *child);
void kb_window_show(GtkWidget *window);

void kb_application_unref(GtkApplication *app);

#ifdef __cplusplus
}
#endif

#endif /* GTK_SHIM_H */
