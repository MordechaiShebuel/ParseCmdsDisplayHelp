#define GTK_DISABLE_AUTOPTR_SUPPORT
#define G_DISABLE_AUTOPTR_SUPPORT

#include <gtk/gtk.h>          /* real headers only here */
#include "gtk_shim.h"

#include "gtk_shim.h"

GtkApplication *kb_application_new(const char *application_id) {
    return gtk_application_new(
        application_id,
        G_APPLICATION_DEFAULT_FLAGS
    );
}

void kb_application_connect_activate(
    GtkApplication *app,
    KeybindActivateFn callback,
    gpointer user_data
) {
    g_signal_connect(
        app,
        "activate",
        G_CALLBACK(callback),
        user_data
    );
}

int kb_application_run(GtkApplication *app) {
    return g_application_run(
        G_APPLICATION(app),
        0,
        NULL
    );
}

GtkWidget *kb_create_window(GtkApplication *app) {
    GtkWidget *window = gtk_application_window_new(app);

    gtk_window_set_title(
        GTK_WINDOW(window),
        "Lua Keybindings"
    );

    gtk_window_set_default_size(
        GTK_WINDOW(window),
        650,
        400
    );

    return window;
}

void kb_configure_window(GtkWidget *window) {
    gtk_widget_show_all(window);
}

GtkWidget *kb_create_text_view(const char *text) {
    GtkWidget *text_view = gtk_text_view_new();

    gtk_text_view_set_editable(
        GTK_TEXT_VIEW(text_view),
        FALSE
    );

    gtk_text_view_set_cursor_visible(
        GTK_TEXT_VIEW(text_view),
        FALSE
    );

    gtk_text_view_set_monospace(
        GTK_TEXT_VIEW(text_view),
        TRUE
    );

    gtk_text_view_set_wrap_mode(
        GTK_TEXT_VIEW(text_view),
        GTK_WRAP_NONE
    );

    GtkTextBuffer *buffer =
        gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));

    gtk_text_buffer_set_text(
        buffer,
        text,
        -1
    );

    return text_view;
}

GtkWidget *kb_create_scrolled_window(GtkWidget *text_view) {
    GtkWidget *scrolled_window =
        gtk_scrolled_window_new(NULL, NULL);

    gtk_scrolled_window_set_policy(
        GTK_SCROLLED_WINDOW(scrolled_window),
        GTK_POLICY_AUTOMATIC,
        GTK_POLICY_AUTOMATIC
    );

    gtk_container_add(
        GTK_CONTAINER(scrolled_window),
        text_view
    );

    return scrolled_window;
}

void kb_window_set_child(GtkWidget *window, GtkWidget *child) {
    gtk_container_add(
        GTK_CONTAINER(window),
        child
    );
}

void kb_window_show(GtkWidget *window) {
    gtk_widget_show_all(window);
}

void kb_application_unref(GtkApplication *app) {
    g_object_unref(app);
}
