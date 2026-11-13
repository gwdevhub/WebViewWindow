// Linux: GTK 3 and WebKitGTK 4.1. The libraries are opened when the first window is made, so the program starts without
// them and reports the missing library when it's needed. Only the headers are used at build time.

#include <dlfcn.h>

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <string>

#include "WebViewWindow.h"


struct NativeWindow {
    GtkWidget* window = nullptr;
    WebKitWebView* view = nullptr;
    WebKitUserContentManager* manager = nullptr;
    // Set while the user drags or resizes the window: the window follows the pointer, and the frame it began with is kept here.
    bool snapping = false;
    ScreenRect dragStart;
    // The pointer where the drag began, and whether it resizes from edge.
    int pressX = 0;
    int pressY = 0;
    bool resizing = false;
    ResizeEdge edge = ResizeEdge::NorthWest;
    // Whether the library moves the window as it is dragged, rather than the window manager.
    bool manual = false;
    // The window stays hidden until its page has loaded, so it never shows as an empty frame.
    // The window stays hidden until its page reports that it's ready, so it never shows an empty or half-drawn page.
    bool pageReady = false;
    bool wantsVisible = false;
    bool wantsFocus = false;
    // The window's position when it was last hidden. GTK centres a toplevel again each time it's shown, so it's put back on show.
    bool hasHiddenPosition = false;
    int hiddenX = 0;
    int hiddenY = 0;
    // Whether a window dropped after a move or resize is kept inside its monitor's work area.
    bool confined = true;
    // The window this belongs to, which the load events report to.
    WebViewWindow* owner = nullptr;
};

namespace {

// GdkRGBA's layout, which WebKitGTK reads for the page's background.
struct RgbaColor {
    double red;
    double green;
    double blue;
    double alpha;
};

// The GTK and WebKitGTK functions this window uses, resolved from the opened library.
struct GtkApi {
    gboolean (*init_check)(int*, char***) = nullptr;
    GtkWidget* (*window_new)(GtkWindowType) = nullptr;
    void (*window_set_title)(GtkWindow*, const gchar*) = nullptr;
    void (*window_set_default_size)(GtkWindow*, gint, gint) = nullptr;
    void (*window_set_position)(GtkWindow*, GtkWindowPosition) = nullptr;
    void (*window_resize)(GtkWindow*, gint, gint) = nullptr;
    void (*window_move)(GtkWindow*, gint, gint) = nullptr;
    void (*window_get_position)(GtkWindow*, gint*, gint*) = nullptr;
    void (*window_get_size)(GtkWindow*, gint*, gint*) = nullptr;
    void (*window_set_decorated)(GtkWindow*, gboolean) = nullptr;
    void (*window_set_skip_taskbar_hint)(GtkWindow*, gboolean) = nullptr;
    void (*window_set_keep_above)(GtkWindow*, gboolean) = nullptr;
    void (*window_present)(GtkWindow*) = nullptr;
    void (*window_present_with_time)(GtkWindow*, guint32) = nullptr;
    void (*window_deiconify)(GtkWindow*) = nullptr;
    void (*window_stick)(GtkWindow*) = nullptr;
    void (*window_set_keep_below)(GtkWindow*, gboolean) = nullptr;
    void (*window_set_type_hint)(GtkWindow*, int) = nullptr;
    void (*window_set_skip_pager_hint)(GtkWindow*, gboolean) = nullptr;
    void (*widget_set_app_paintable)(GtkWidget*, gboolean) = nullptr;
    GdkScreen* (*widget_get_screen)(GtkWidget*) = nullptr;
    void* (*screen_get_rgba_visual)(GdkScreen*) = nullptr;
    void (*widget_set_visual)(GtkWidget*, void*) = nullptr;
    void (*container_add)(GtkContainer*, GtkWidget*) = nullptr;
    void (*widget_show)(GtkWidget*) = nullptr;
    void (*widget_show_all)(GtkWidget*) = nullptr;
    GdkWindow* (*widget_get_window)(GtkWidget*) = nullptr;
    void (*widget_realize)(GtkWidget*) = nullptr;
    // The input shape takes a cairo region, which the cairo library makes. Both come from the libraries opened at start.
    void (*widget_input_shape_combine_region)(GtkWidget*, void*) = nullptr;
    void* (*cairo_region_create)() = nullptr;
    void (*cairo_region_destroy)(void*) = nullptr;
    guint32 (*x11_server_time)(GdkWindow*) = nullptr;
    void (*window_begin_resize_drag)(GtkWindow*, GdkWindowEdge, gint, gint, gint, guint32) = nullptr;
    void (*window_begin_move_drag)(GtkWindow*, gint, gint, gint, guint32) = nullptr;
    void (*window_iconify)(GtkWindow*) = nullptr;
    void (*window_maximize)(GtkWindow*) = nullptr;
    void (*window_unmaximize)(GtkWindow*) = nullptr;
    gboolean (*window_is_maximized)(GtkWindow*) = nullptr;
    void (*window_close)(GtkWindow*) = nullptr;
    void (*widget_hide)(GtkWidget*) = nullptr;
    void (*widget_destroy)(GtkWidget*) = nullptr;
    void (*main_loop)() = nullptr;
    void (*main_quit)() = nullptr;
    guint (*idle_add)(GSourceFunc, gpointer) = nullptr;
    guint (*timeout_add)(guint, GSourceFunc, gpointer) = nullptr;
    GdkDisplay* (*display_get_default)() = nullptr;
    void (*display_get_pointer)(void*, void*, gint*, gint*, guint*) = nullptr;
    GdkMonitor* (*display_get_primary_monitor)(GdkDisplay*) = nullptr;
    GdkMonitor* (*display_get_monitor_at_point)(GdkDisplay*, gint, gint) = nullptr;
    void (*monitor_get_workarea)(GdkMonitor*, GdkRectangle*) = nullptr;
    gint (*widget_get_scale_factor)(GtkWidget*) = nullptr;
    void (*window_set_icon)(GtkWindow*, GdkPixbuf*) = nullptr;
    GdkDisplay* (*widget_get_display)(GtkWidget*) = nullptr;
    GdkSeat* (*display_get_default_seat)(GdkDisplay*) = nullptr;
    GdkDevice* (*seat_get_pointer)(GdkSeat*) = nullptr;
    GdkWindow* (*device_get_window_at_position)(GdkDevice*, gint*, gint*) = nullptr;
    GdkWindow* (*window_get_toplevel)(GdkWindow*) = nullptr;
    WebKitUserContentManager* (*user_content_manager_new)() = nullptr;
    gboolean (*user_content_manager_register_script_message_handler_with_reply)(WebKitUserContentManager*, const gchar*,
                                                                                const gchar*) = nullptr;
    GtkWidget* (*web_view_new_with_user_content_manager)(WebKitUserContentManager*) = nullptr;
    void (*web_view_load_html)(WebKitWebView*, const gchar*, const gchar*) = nullptr;
    void (*web_view_load_uri)(WebKitWebView*, const gchar*) = nullptr;
    void (*web_view_run_javascript)(WebKitWebView*, const gchar*, GCancellable*, GAsyncReadyCallback, gpointer) = nullptr;
    void (*web_view_set_background_color)(WebKitWebView*, const RgbaColor*) = nullptr;
    WebKitSettings* (*web_view_get_settings)(WebKitWebView*) = nullptr;
    void (*settings_set_enable_developer_extras)(WebKitSettings*, gboolean) = nullptr;
    void (*settings_set_hardware_acceleration_policy)(WebKitSettings*, WebKitHardwareAccelerationPolicy) = nullptr;
    WebKitWebInspector* (*web_view_get_inspector)(WebKitWebView*) = nullptr;
    void (*web_inspector_show)(WebKitWebInspector*) = nullptr;
    gulong (*g_signal_connect_data)(gpointer, const gchar*, GCallback, gpointer, GClosureNotify, GConnectFlags) = nullptr;
    void (*g_free)(gpointer) = nullptr;
    void* (*status_icon_new_from_pixbuf)(GdkPixbuf*) = nullptr;
    void (*status_icon_set_tooltip_text)(void*, const gchar*) = nullptr;
    void (*status_icon_set_visible)(void*, gboolean) = nullptr;
    void (*status_icon_position_menu)(GtkWidget*, gint*, gint*, gboolean*, gpointer) = nullptr;
    GtkWidget* (*menu_new)() = nullptr;
    GtkWidget* (*menu_item_new_with_label)(const gchar*) = nullptr;
    void (*menu_shell_append)(GtkMenuShell*, GtkWidget*) = nullptr;
    void (*menu_popup)(GtkWidget*, GtkWidget*, GtkWidget*, void*, gpointer, guint, guint32) = nullptr;
    char* (*jsc_value_to_string)(JSCValue*) = nullptr;
    // Permission requests: the page asks for the microphone, camera or notifications, and the host allows or denies them.
    gboolean (*permission_request_allow)(WebKitPermissionRequest*) = nullptr;
    gboolean (*permission_request_deny)(WebKitPermissionRequest*) = nullptr;
    void (*web_context_initialize_notification_permissions)(WebKitWebContext*, GList*, GList*) = nullptr;
    WebKitWebContext* (*web_view_get_context)(WebKitWebView*) = nullptr;
    gpointer (*security_origin_new_for_uri)(const gchar*) = nullptr;
    GList* (*list_append)(GList*, gpointer) = nullptr;
    void (*list_free)(GList*) = nullptr;
    void (*download_set_destination)(WebKitDownload*, const gchar*) = nullptr;
    gchar* (*filename_to_uri)(const gchar*, const gchar*, GError**) = nullptr;
    gsize (*user_media_permission_request_get_type)() = nullptr;
    gsize (*notification_permission_request_get_type)() = nullptr;
    gboolean (*user_media_permission_is_for_audio_device)(WebKitUserMediaPermissionRequest*) = nullptr;
    gboolean (*user_media_permission_is_for_video_device)(WebKitUserMediaPermissionRequest*) = nullptr;
    const gchar* (*web_view_get_uri)(WebKitWebView*) = nullptr;
    gboolean (*g_type_check_instance_is_a)(gpointer, gsize) = nullptr;
};

template <typename F>
void bind(F& slot, void* library, const char* name) {
    void* symbol = dlsym(library, name);
    if (!symbol) {
        throw std::runtime_error(std::string("WebKitGTK 4.1 is missing ") + name + ".");
    }
    slot = reinterpret_cast<F>(symbol);
}

GtkApi loadApi() {
    // The WebKitGTK library depends on GTK and GLib, so symbols from those resolve through this handle too.
    void* library = dlopen("libwebkit2gtk-4.1.so.0", RTLD_LAZY | RTLD_LOCAL);
    if (!library) {
        throw std::runtime_error(std::string("WebKitGTK 4.1 couldn't be opened: ") + dlerror());
    }
    GtkApi api;
    bind(api.init_check, library, "gtk_init_check");
    bind(api.window_new, library, "gtk_window_new");
    bind(api.window_set_title, library, "gtk_window_set_title");
    bind(api.window_set_default_size, library, "gtk_window_set_default_size");
    bind(api.window_set_position, library, "gtk_window_set_position");
    bind(api.window_resize, library, "gtk_window_resize");
    bind(api.window_move, library, "gtk_window_move");
    bind(api.window_get_position, library, "gtk_window_get_position");
    bind(api.window_get_size, library, "gtk_window_get_size");
    bind(api.window_set_decorated, library, "gtk_window_set_decorated");
    bind(api.window_set_skip_taskbar_hint, library, "gtk_window_set_skip_taskbar_hint");
    bind(api.window_set_keep_above, library, "gtk_window_set_keep_above");
    bind(api.window_present, library, "gtk_window_present");
    bind(api.window_present_with_time, library, "gtk_window_present_with_time");
    bind(api.window_deiconify, library, "gtk_window_deiconify");
    bind(api.window_begin_resize_drag, library, "gtk_window_begin_resize_drag");
    bind(api.window_begin_move_drag, library, "gtk_window_begin_move_drag");
    bind(api.timeout_add, library, "g_timeout_add");
    bind(api.display_get_default, library, "gdk_display_get_default");
    bind(api.display_get_pointer, library, "gdk_display_get_pointer");
    bind(api.display_get_primary_monitor, library, "gdk_display_get_primary_monitor");
    bind(api.display_get_monitor_at_point, library, "gdk_display_get_monitor_at_point");
    bind(api.monitor_get_workarea, library, "gdk_monitor_get_workarea");
    bind(api.widget_get_scale_factor, library, "gtk_widget_get_scale_factor");
    bind(api.window_set_icon, library, "gtk_window_set_icon");
    bind(api.widget_get_display, library, "gtk_widget_get_display");
    bind(api.display_get_default_seat, library, "gdk_display_get_default_seat");
    bind(api.seat_get_pointer, library, "gdk_seat_get_pointer");
    bind(api.device_get_window_at_position, library, "gdk_device_get_window_at_position");
    bind(api.window_get_toplevel, library, "gdk_window_get_toplevel");
    bind(api.window_iconify, library, "gtk_window_iconify");
    bind(api.window_maximize, library, "gtk_window_maximize");
    bind(api.window_unmaximize, library, "gtk_window_unmaximize");
    bind(api.window_is_maximized, library, "gtk_window_is_maximized");
    bind(api.window_close, library, "gtk_window_close");
    bind(api.window_stick, library, "gtk_window_stick");
    bind(api.window_set_keep_below, library, "gtk_window_set_keep_below");
    bind(api.window_set_type_hint, library, "gtk_window_set_type_hint");
    bind(api.window_set_skip_pager_hint, library, "gtk_window_set_skip_pager_hint");
    bind(api.widget_set_app_paintable, library, "gtk_widget_set_app_paintable");
    bind(api.widget_get_screen, library, "gtk_widget_get_screen");
    bind(api.screen_get_rgba_visual, library, "gdk_screen_get_rgba_visual");
    bind(api.widget_set_visual, library, "gtk_widget_set_visual");
    bind(api.web_view_set_background_color, library, "webkit_web_view_set_background_color");
    bind(api.container_add, library, "gtk_container_add");
    bind(api.widget_show, library, "gtk_widget_show");
    bind(api.widget_show_all, library, "gtk_widget_show_all");
    bind(api.widget_get_window, library, "gtk_widget_get_window");
    bind(api.widget_realize, library, "gtk_widget_realize");
    bind(api.widget_input_shape_combine_region, library, "gtk_widget_input_shape_combine_region");
    // Cairo is the library GTK draws with, so it's there whenever GTK is. It's opened here for the one region the input shape needs.
    if (void* cairo = dlopen("libcairo.so.2", RTLD_LAZY | RTLD_LOCAL)) {
        bind(api.cairo_region_create, cairo, "cairo_region_create");
        bind(api.cairo_region_destroy, cairo, "cairo_region_destroy");
    }
    // Only on X11. Without it the focus request carries no time, and the window manager may refuse it.
    api.x11_server_time = reinterpret_cast<decltype(api.x11_server_time)>(dlsym(library, "gdk_x11_get_server_time"));
    bind(api.widget_hide, library, "gtk_widget_hide");
    bind(api.widget_destroy, library, "gtk_widget_destroy");
    bind(api.main_loop, library, "gtk_main");
    bind(api.main_quit, library, "gtk_main_quit");
    bind(api.idle_add, library, "g_idle_add");
    bind(api.user_content_manager_new, library, "webkit_user_content_manager_new");
    bind(api.user_content_manager_register_script_message_handler_with_reply, library,
         "webkit_user_content_manager_register_script_message_handler_with_reply");
    bind(api.web_view_new_with_user_content_manager, library, "webkit_web_view_new_with_user_content_manager");
    bind(api.web_view_load_html, library, "webkit_web_view_load_html");
    bind(api.web_view_load_uri, library, "webkit_web_view_load_uri");
    bind(api.web_view_run_javascript, library, "webkit_web_view_run_javascript");
    bind(api.web_view_get_settings, library, "webkit_web_view_get_settings");
    bind(api.settings_set_enable_developer_extras, library, "webkit_settings_set_enable_developer_extras");
    bind(api.settings_set_hardware_acceleration_policy, library, "webkit_settings_set_hardware_acceleration_policy");
    bind(api.web_view_get_inspector, library, "webkit_web_view_get_inspector");
    bind(api.web_inspector_show, library, "webkit_web_inspector_show");
    bind(api.g_signal_connect_data, library, "g_signal_connect_data");
    bind(api.g_free, library, "g_free");
    bind(api.status_icon_new_from_pixbuf, library, "gtk_status_icon_new_from_pixbuf");
    bind(api.status_icon_set_tooltip_text, library, "gtk_status_icon_set_tooltip_text");
    bind(api.status_icon_set_visible, library, "gtk_status_icon_set_visible");
    bind(api.status_icon_position_menu, library, "gtk_status_icon_position_menu");
    bind(api.menu_new, library, "gtk_menu_new");
    bind(api.menu_item_new_with_label, library, "gtk_menu_item_new_with_label");
    bind(api.menu_shell_append, library, "gtk_menu_shell_append");
    bind(api.menu_popup, library, "gtk_menu_popup");
    bind(api.jsc_value_to_string, library, "jsc_value_to_string");
    bind(api.permission_request_allow, library, "webkit_permission_request_allow");
    bind(api.permission_request_deny, library, "webkit_permission_request_deny");
    bind(api.user_media_permission_request_get_type, library, "webkit_user_media_permission_request_get_type");
    bind(api.notification_permission_request_get_type, library, "webkit_notification_permission_request_get_type");
    bind(api.user_media_permission_is_for_audio_device, library, "webkit_user_media_permission_is_for_audio_device");
    bind(api.user_media_permission_is_for_video_device, library, "webkit_user_media_permission_is_for_video_device");
    bind(api.web_view_get_uri, library, "webkit_web_view_get_uri");
    bind(api.g_type_check_instance_is_a, library, "g_type_check_instance_is_a");
    bind(api.web_context_initialize_notification_permissions, library, "webkit_web_context_initialize_notification_permissions");
    bind(api.web_view_get_context, library, "webkit_web_view_get_context");
    bind(api.download_set_destination, library, "webkit_download_set_destination");
    bind(api.filename_to_uri, library, "g_filename_to_uri");
    bind(api.security_origin_new_for_uri, library, "webkit_security_origin_new_for_uri");
    bind(api.list_append, library, "g_list_append");
    bind(api.list_free, library, "g_list_free");
    return api;
}

const GtkApi& api() {
    static const GtkApi loaded = loadApi();
    return loaded;
}

void ensureGtk() {
    static const bool initialized = [] {
        if (!api().init_check(nullptr, nullptr)) {
            throw std::runtime_error("GTK couldn't open a display.");
        }
        return true;
    }();
    (void)initialized;
}

// The launcher's icon, set by setApplicationIcon and given to each window as it opens.
GdkPixbuf* applicationIcon = nullptr;

// The X server's time, which a window manager needs on a focus or move request. GDK_CURRENT_TIME when it isn't available.
guint32 serverTime(GtkWidget* widget) {
    if (!api().x11_server_time) {
        return GDK_CURRENT_TIME;
    }
    GdkWindow* gdkWindow = api().widget_get_window(widget);
    return gdkWindow ? api().x11_server_time(gdkWindow) : GDK_CURRENT_TIME;
}

// Shows the window once its page has reported ready, if it's wanted yet. Focus goes to it only if it was asked for.
void showReadyPage(NativeWindow* native) {
    if (!native->window || !native->wantsVisible || !native->pageReady) {
        return;
    }
    api().widget_show_all(native->window);
    if (native->wantsFocus) {
        native->wantsFocus = false;
        api().window_present_with_time(reinterpret_cast<GtkWindow*>(native->window), serverTime(native->window));
    }
}

void onLoadChanged(WebKitWebView*, WebKitLoadEvent event, gpointer data) {
    auto* native = static_cast<NativeWindow*>(data);
    if (event == WEBKIT_LOAD_FINISHED) {
        if (native->owner) {
            native->owner->notifyPageLoaded();
        }
    }
}

// A script message from the page: window.webkit.messageHandlers.host.postMessage(text).
void onScriptMessage(WebKitUserContentManager*, JSCValue* value, WebKitUserMessage*, gpointer data) {
    auto* window = static_cast<WebViewWindow*>(data);
    char* text = api().jsc_value_to_string(value);
    if (text) {
        window->receive(text);
        api().g_free(text);
    }
}

// Returning TRUE keeps the window open. The window decides, through requestClose.
gboolean onFocusOut(GtkWidget*, GdkEvent*, gpointer data) {
    static_cast<WebViewWindow*>(data)->notifyFocusLost();
    return FALSE;
}

// WebKit runs the page in a process of its own, which can die. The page is loaded again from the window's own page, since
// it asks the host for its state as it loads, and the user is told why the page blanked for a moment.
gboolean onWebProcessCrashed(WebKitWebView* view, gpointer data) {
    auto* window = static_cast<WebViewWindow*>(data);
    const std::string url = window->devUrl();
    if (!url.empty()) {
        api().web_view_load_uri(view, url.c_str());
    } else {
        api().web_view_load_html(view, window->html().c_str(), nullptr);
    }
    const std::string message = window->pageReloadedMessage();
    runOnUiThread([message] {
        showError(message);
    });
    return TRUE;
}

// WebKitGTK denies notifications for an origin until the application has said otherwise. The window's own page origin is decided
// here, once, by the host: allowed when the host allows notifications, and disallowed when it refuses them. An origin the host leaves
// open is asked about when the page asks, through onPermissionRequested.
void initializeNotifications(WebViewWindow& window, WebKitWebContext* context) {
    const std::string url = window.devUrl();
    if (url.empty()) {
        return;
    }
    const std::optional<bool> answer = window.decidePermission(PagePermission::Notifications, url);
    if (!answer) {
        return;
    }
    gpointer origin = api().security_origin_new_for_uri(url.c_str());
    GList* list = api().list_append(nullptr, origin);
    if (*answer) {
        api().web_context_initialize_notification_permissions(context, list, nullptr);
    } else {
        api().web_context_initialize_notification_permissions(context, nullptr, list);
    }
    // WebKit keeps the origin, so only the list is freed here.
    api().list_free(list);
}

// WebKit asks where a download goes: the chooser answers, and WebKit's default stays in place when there's no answer.
gboolean onDecideDestination(WebKitDownload* download, const gchar* suggestedFilename, gpointer) {
    const std::optional<std::filesystem::path> path = chooseDownloadPath(suggestedFilename ? suggestedFilename : "");
    if (!path) {
        return FALSE;
    }
    gchar* uri = api().filename_to_uri(path->c_str(), nullptr, nullptr);
    if (!uri) {
        return FALSE;
    }
    api().download_set_destination(download, uri);
    api().g_free(uri);
    return TRUE;
}

// A download has started on the context. Its destination is decided when WebKit asks for it.
void onDownloadStarted(WebKitWebContext*, WebKitDownload* download, gpointer) {
    api().g_signal_connect_data(download, "decide-destination", reinterpret_cast<GCallback>(onDecideDestination), nullptr,
                                nullptr, static_cast<GConnectFlags>(0));
}

// The page asks for a permission. The host decides for each part of the request; when any part has no answer, WebKit's default
// (deny) stays in place by returning FALSE. Returning TRUE tells WebKit the request was answered.
gboolean onPermissionRequested(WebKitWebView* view, WebKitPermissionRequest* request, gpointer data) {
    auto* window = static_cast<WebViewWindow*>(data);
    const char* uri = api().web_view_get_uri(view);
    const std::string pageUrl = uri ? uri : "";

    std::vector<PagePermission> parts;
    if (api().g_type_check_instance_is_a(request, api().user_media_permission_request_get_type())) {
        auto* media = reinterpret_cast<WebKitUserMediaPermissionRequest*>(request);
        if (api().user_media_permission_is_for_audio_device(media)) {
            parts.push_back(PagePermission::Microphone);
        }
        if (api().user_media_permission_is_for_video_device(media)) {
            parts.push_back(PagePermission::Camera);
        }
        // A screen share and other media kinds have no answer here, so they keep WebKit's default.
        if (parts.empty()) {
            return FALSE;
        }
    } else if (api().g_type_check_instance_is_a(request, api().notification_permission_request_get_type())) {
        parts.push_back(PagePermission::Notifications);
    } else {
        return FALSE;
    }

    bool allowed = true;
    for (const PagePermission part : parts) {
        const std::optional<bool> answer = window->decidePermission(part, pageUrl);
        if (!answer) {
            return FALSE;
        }
        allowed = allowed && *answer;
    }
    if (allowed) {
        api().permission_request_allow(request);
    } else {
        api().permission_request_deny(request);
    }
    return TRUE;
}

// Fires on every move and resize. FALSE lets GTK apply the change as usual.
gboolean onConfigure(GtkWidget*, GdkEvent*, gpointer data) {
    static_cast<WebViewWindow*>(data)->notifyFrameChanged();
    return FALSE;
}

gboolean onDeleteEvent(GtkWidget*, GdkEvent*, gpointer data) {
    auto* window = static_cast<WebViewWindow*>(data);
    if (!window->requestClose()) {
        return TRUE;
    }
    window->notifyClosed();
    return FALSE;
}

}  // namespace

void NativeWindowDeleter::operator()(NativeWindow* native) const {
    if (native && native->window) {
        api().widget_destroy(native->window);
    }
    delete native;
}

void WebViewWindow::platformOpen() {
    ensureGtk();
    const GtkApi& gtk = api();
    native_.reset(new NativeWindow);
    NativeWindow& native = *native_;
    native.owner = this;

    native.window = gtk.window_new(GTK_WINDOW_TOPLEVEL);
    auto* window = reinterpret_cast<GtkWindow*>(native.window);
    gtk.window_set_title(window, title().c_str());
    gtk.window_set_default_size(window, scaledSize(options_.width), scaledSize(options_.height));
    // Opened in the middle of the screen. A caller that places the window moves it after it's opened.
    gtk.window_set_position(window, GTK_WIN_POS_CENTER);
    // The page draws the title bar, so the window manager draws none.
    gtk.window_set_decorated(window, FALSE);
    // Left resizable even for an autosize window: GTK keeps a fixed-size web view window at least 200 pixels square, and
    // a frameless window offers the user no edges unless the page draws them.
    gtk.window_set_skip_taskbar_hint(window, options_.skipTaskbar);
    gtk.window_set_keep_above(window, options_.alwaysOnTop);
    gtk.window_set_keep_below(window, options_.keepBelow);
    if (options_.utility) {
        // GDK_WINDOW_TYPE_HINT_UTILITY. Show Desktop minimises normal windows, but not these.
        gtk.window_set_type_hint(window, 5);
        gtk.window_set_skip_pager_hint(window, TRUE);
    }
    if (options_.sticky) {
        gtk.window_stick(window);
    }
    if (options_.transparent) {
        // The window needs an RGBA visual before its page can let the desktop show through.
        gtk.widget_set_app_paintable(native.window, TRUE);
        if (void* visual = gtk.screen_get_rgba_visual(gtk.widget_get_screen(native.window))) {
            gtk.widget_set_visual(native.window, visual);
        }
    }

    // The icon is set on each window: the taskbar and the window list read the window's own icon.
    if (applicationIcon) {
        gtk.window_set_icon(window, applicationIcon);
    }

    native.manager = gtk.user_content_manager_new();
    // The signal is connected before the handler is registered, as WebKitGTK recommends.
    gtk.g_signal_connect_data(native.manager, "script-message-with-reply-received::host",
                              reinterpret_cast<GCallback>(onScriptMessage), this, nullptr, static_cast<GConnectFlags>(0));
    gtk.user_content_manager_register_script_message_handler_with_reply(native.manager, "host", nullptr);
    native.view = reinterpret_cast<WebKitWebView*>(gtk.web_view_new_with_user_content_manager(native.manager));
    if (options_.hardwareAcceleration) {
        WebKitHardwareAccelerationPolicy policy = WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND;
        switch (*options_.hardwareAcceleration) {
            case HardwareAcceleration::OnDemand: policy = WEBKIT_HARDWARE_ACCELERATION_POLICY_ON_DEMAND; break;
            case HardwareAcceleration::Always: policy = WEBKIT_HARDWARE_ACCELERATION_POLICY_ALWAYS; break;
            case HardwareAcceleration::Never: policy = WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER; break;
        }
        gtk.settings_set_hardware_acceleration_policy(gtk.web_view_get_settings(native.view), policy);
    }
    if (options_.transparent) {
        const RgbaColor clear{0, 0, 0, 0};
        gtk.web_view_set_background_color(native.view, &clear);
    }
    if (options_.clickThrough && gtk.cairo_region_create) {
        // An empty input shape means the window takes no pointer input, so clicks reach whatever is beneath it. The shape is set once
        // the widget is realized, and GTK copies the region, so it's released straight after.
        gtk.widget_realize(native.window);
        void* empty = gtk.cairo_region_create();
        gtk.widget_input_shape_combine_region(native.window, empty);
        gtk.cairo_region_destroy(empty);
    }
    gtk.container_add(reinterpret_cast<GtkContainer*>(native.window), reinterpret_cast<GtkWidget*>(native.view));
    gtk.g_signal_connect_data(native.view, "web-process-crashed", reinterpret_cast<GCallback>(onWebProcessCrashed), this,
                              nullptr, static_cast<GConnectFlags>(0));
    WebKitWebContext* context = gtk.web_view_get_context(native.view);
    // The download handler is the same for every window, so it's connected to the shared context once.
    static bool downloadsConnected = false;
    if (!downloadsConnected) {
        downloadsConnected = true;
        gtk.g_signal_connect_data(context, "download-started", reinterpret_cast<GCallback>(onDownloadStarted), nullptr,
                                  nullptr, static_cast<GConnectFlags>(0));
    }
    initializeNotifications(*this, context);
    gtk.g_signal_connect_data(native.view, "permission-request", reinterpret_cast<GCallback>(onPermissionRequested), this,
                              nullptr, static_cast<GConnectFlags>(0));

    native.wantsVisible = options_.visible;
    native.confined = options_.confinedToWorkArea;
    gtk.g_signal_connect_data(native.view, "load-changed", reinterpret_cast<GCallback>(onLoadChanged), &native, nullptr,
                              static_cast<GConnectFlags>(0));

    gtk.g_signal_connect_data(native.window, "delete-event", reinterpret_cast<GCallback>(onDeleteEvent), this, nullptr,
                              static_cast<GConnectFlags>(0));
    gtk.g_signal_connect_data(native.window, "configure-event", reinterpret_cast<GCallback>(onConfigure), this, nullptr,
                              static_cast<GConnectFlags>(0));
    // The window is closing: GTK destroys it after this, so the NativeWindow must stop pointing at it.
    gtk.g_signal_connect_data(native.window, "destroy", reinterpret_cast<GCallback>(+[](GtkWidget*, gpointer data) {
                                  static_cast<NativeWindow*>(data)->window = nullptr;
                              }), &native, nullptr,
                              static_cast<GConnectFlags>(0));
    gtk.g_signal_connect_data(native.window, "focus-out-event", reinterpret_cast<GCallback>(onFocusOut), this, nullptr,
                              static_cast<GConnectFlags>(0));

    const std::string url = devUrl();
    if (!url.empty()) {
        gtk.web_view_load_uri(native.view, url.c_str());
    } else {
        gtk.web_view_load_html(native.view, html().c_str(), nullptr);
    }
}

void WebViewWindow::platformUnload() {
    native_.reset();
}

void WebViewWindow::platformPresent() {
    if (!native_ || !native_->window) {
        return;
    }
    native_->wantsVisible = true;
    if (!native_->pageReady) {
        native_->wantsFocus = true;
        return;
    }
    // Restores it from minimised, shows it if it's hidden, and asks the window manager to raise it and give it the focus. The
    // timestamp is the current time, since a window manager may ignore a request that has none.
    auto* window = reinterpret_cast<GtkWindow*>(native_->window);
    api().window_deiconify(window);
    api().widget_show_all(native_->window);
    api().window_present_with_time(window, serverTime(native_->window));
}

namespace {

// Moves and resizes snap the edges they move to this grid, in screen pixels.
constexpr int kSnapGrid = 8;
constexpr guint kDragPollMilliseconds = 20;
constexpr guint kButton1Mask = 1u << 8;

// The logical coordinate nearest to a point on the grid of screen pixels, which are the logical pixels times the scale.
int snapToGrid(int logical, int scale) {
    const long screen = std::lround(static_cast<double>(logical) * scale / kSnapGrid) * kSnapGrid;
    return static_cast<int>(std::lround(static_cast<double>(screen) / scale));
}

// The pointer's position on the screen, and whether the left button is held.
bool pointerState(int& x, int& y) {
    guint mask = 0;
    api().display_get_pointer(api().display_get_default(), nullptr, &x, &y, &mask);
    return (mask & kButton1Mask) != 0;
}

// The window's frame as GTK reports it, in logical pixels.
ScreenRect frameOf(GtkWidget* widget) {
    auto* window = reinterpret_cast<GtkWindow*>(widget);
    gint x = 0;
    gint y = 0;
    gint width = 0;
    gint height = 0;
    api().window_get_position(window, &x, &y);
    api().window_get_size(window, &width, &height);
    return ScreenRect{x, y, width, height};
}

// The frame a drag asks for when the pointer has moved by (dx, dy) since it began: snapped to the grid, and inside the work area
// when the window is confined to it. A move keeps the size; a resize moves only the edges its edge names.
ScreenRect dragTarget(const NativeWindow& native, int dx, int dy) {
    const ScreenRect start = native.dragStart;
    const int scale = api().widget_get_scale_factor(native.window);
    std::optional<ScreenRect> area;
    if (native.confined) {
        area = workAreaAt(start);
    }
    if (!native.resizing) {
        int x = snapToGrid(start.x + dx, scale);
        int y = snapToGrid(start.y + dy, scale);
        if (area) {
            x = std::max(area->x, std::min(x, area->right() - start.width));
            y = std::max(area->y, std::min(y, area->bottom() - start.height));
        }
        return ScreenRect{x, y, start.width, start.height};
    }
    const ResizeEdge edge = native.edge;
    const bool west = edge == ResizeEdge::West || edge == ResizeEdge::NorthWest || edge == ResizeEdge::SouthWest;
    const bool east = edge == ResizeEdge::East || edge == ResizeEdge::NorthEast || edge == ResizeEdge::SouthEast;
    const bool north = edge == ResizeEdge::North || edge == ResizeEdge::NorthWest || edge == ResizeEdge::NorthEast;
    const bool south = edge == ResizeEdge::South || edge == ResizeEdge::SouthWest || edge == ResizeEdge::SouthEast;
    int left = start.x;
    int top = start.y;
    int right = start.right();
    int bottom = start.bottom();
    if (west) {
        left = snapToGrid(start.x + dx, scale);
        if (area) {
            left = std::max(left, area->x);
        }
        left = std::min(left, right - 1);
    }
    if (east) {
        right = snapToGrid(start.right() + dx, scale);
        if (area) {
            right = std::min(right, area->right());
        }
        right = std::max(right, left + 1);
    }
    if (north) {
        top = snapToGrid(start.y + dy, scale);
        if (area) {
            top = std::max(top, area->y);
        }
        top = std::min(top, bottom - 1);
    }
    if (south) {
        bottom = snapToGrid(start.bottom() + dy, scale);
        if (area) {
            bottom = std::min(bottom, area->bottom());
        }
        bottom = std::max(bottom, top + 1);
    }
    return ScreenRect{left, top, right - left, bottom - top};
}

// Moves and resizes the window to the target, changing only what differs.
void applyTarget(NativeWindow* native, const ScreenRect& target) {
    const ScreenRect frame = frameOf(native->window);
    auto* window = reinterpret_cast<GtkWindow*>(native->window);
    if (target.x != frame.x || target.y != frame.y) {
        api().window_move(window, target.x, target.y);
    }
    if (target.width != frame.width || target.height != frame.height) {
        api().window_resize(window, target.width, target.height);
    }
}

// Settles a drag the window manager ran, once the button is let go: the grid, then the work area when confined.
void settleDroppedFrame(NativeWindow* native) {
    const ScreenRect start = native->dragStart;
    const ScreenRect frame = frameOf(native->window);
    const int scale = api().widget_get_scale_factor(native->window);
    ScreenRect target = frame;
    if (!native->resizing) {
        target.x = snapToGrid(frame.x, scale);
        target.y = snapToGrid(frame.y, scale);
    } else {
        int left = frame.x;
        int top = frame.y;
        int right = frame.right();
        int bottom = frame.bottom();
        if (left != start.x) {
            left = snapToGrid(left, scale);
        }
        if (right != start.right()) {
            right = snapToGrid(right, scale);
        }
        if (top != start.y) {
            top = snapToGrid(top, scale);
        }
        if (bottom != start.bottom()) {
            bottom = snapToGrid(bottom, scale);
        }
        target = ScreenRect{left, top, right - left, bottom - top};
    }
    if (native->confined) {
        if (const auto area = workAreaAt(target)) {
            target.x = std::max(area->x, std::min(target.x, area->right() - target.width));
            target.y = std::max(area->y, std::min(target.y, area->bottom() - target.height));
        }
    }
    applyTarget(native, target);
}

// Runs each time the drag's poll fires: a drag the window follows itself moves with the pointer, and the rest are settled once
// the button is let go.
gboolean onDragPoll(gpointer data) {
    auto* native = static_cast<NativeWindow*>(data);
    int x = 0;
    int y = 0;
    if (pointerState(x, y)) {
        if (native->manual && native->window) {
            applyTarget(native, dragTarget(*native, x - native->pressX, y - native->pressY));
        }
        return TRUE;
    }
    if (native->window && !native->manual) {
        settleDroppedFrame(native);
    }
    native->snapping = false;
    return FALSE;
}

// Records where a drag began, and starts its poll. A new press restarts the drag, even while the last one's poll still runs.
void beginDrag(NativeWindow* native, bool resizing, ResizeEdge edge, bool manual) {
    int x = 0;
    int y = 0;
    if (!native->window || !pointerState(x, y)) {
        return;
    }
    native->resizing = resizing;
    native->edge = edge;
    native->manual = manual;
    native->pressX = x;
    native->pressY = y;
    native->dragStart = frameOf(native->window);
    if (!native->snapping) {
        native->snapping = true;
        api().timeout_add(kDragPollMilliseconds, onDragPoll, native);
    }
}

}  // namespace

// A confined window on X11 is moved by the library, so it stays inside the work area as it's dragged. Otherwise the window manager
// does the drag, which is the only way a window can go past the work area while it's being dragged.
void WebViewWindow::platformBeginMove() {
    if (!native_ || !native_->window) {
        return;
    }
    const bool manual = api().x11_server_time && native_->confined;
    beginDrag(native_.get(), false, ResizeEdge::NorthWest, manual);
    if (!manual) {
        if (const auto pointer = cursorPosition()) {
            api().window_begin_move_drag(reinterpret_cast<GtkWindow*>(native_->window), 1, pointer->first, pointer->second,
                                         serverTime(native_->window));
        }
    }
}

void WebViewWindow::platformBeginResize(ResizeEdge edge) {
    if (!native_ || !native_->window) {
        return;
    }
    const bool manual = api().x11_server_time && native_->confined;
    beginDrag(native_.get(), true, edge, manual);
    if (!manual) {
        if (const auto pointer = cursorPosition()) {
            api().window_begin_resize_drag(reinterpret_cast<GtkWindow*>(native_->window), static_cast<GdkWindowEdge>(edge), 1,
                                           pointer->first, pointer->second, serverTime(native_->window));
        }
    }
}

void WebViewWindow::platformMinimize() {
    if (native_ && native_->window) {
        api().window_iconify(reinterpret_cast<GtkWindow*>(native_->window));
    }
}

// Full screen is not implemented on this platform yet; the macOS backend has it.
void WebViewWindow::platformSetFullscreen(bool) {}

void WebViewWindow::platformToggleMaximize() {
    if (native_ && native_->window) {
        auto* window = reinterpret_cast<GtkWindow*>(native_->window);
        if (api().window_is_maximized(window)) {
            api().window_unmaximize(window);
        } else {
            api().window_maximize(window);
        }
    }
}

// Sends the delete event the window manager's close would, so onDeleteEvent asks requestClose.
void WebViewWindow::platformClose() {
    if (native_ && native_->window) {
        api().window_close(reinterpret_cast<GtkWindow*>(native_->window));
    }
}

void WebViewWindow::platformShow(bool visible) {
    if (!native_ || !native_->window) {
        return;
    }
    native_->wantsVisible = visible;
    if (!native_->pageReady) {
        return;
    }
    if (visible) {
        // Moved before the window is shown: a window manager can place a window that's moved after it maps.
        if (native_->hasHiddenPosition) {
            api().window_move(reinterpret_cast<GtkWindow*>(native_->window), native_->hiddenX, native_->hiddenY);
            native_->hasHiddenPosition = false;
        }
        api().widget_show_all(native_->window);
    } else {
        const ScreenRect frame = frameOf(native_->window);
        native_->hiddenX = frame.x;
        native_->hiddenY = frame.y;
        native_->hasHiddenPosition = true;
        api().widget_hide(native_->window);
    }
}

void WebViewWindow::platformResize(int width, int height) {
    if (native_ && native_->window) {
        api().window_resize(reinterpret_cast<GtkWindow*>(native_->window), width, height);
    }
}

void WebViewWindow::platformMove(int x, int y) {
    if (native_ && native_->window) {
        api().window_move(reinterpret_cast<GtkWindow*>(native_->window), x, y);
    }
}

// GTK sizes are already in the units resize takes: the display's scale is GTK's own.
int WebViewWindow::platformToIndependent(int pixels) const {
    return pixels;
}

std::optional<ScreenRect> WebViewWindow::platformFrame() const {
    if (!native_ || !native_->window) {
        return std::nullopt;
    }
    auto* window = reinterpret_cast<GtkWindow*>(native_->window);
    gint x = 0;
    gint y = 0;
    gint width = 0;
    gint height = 0;
    api().window_get_position(window, &x, &y);
    api().window_get_size(window, &width, &height);
    return ScreenRect{x, y, width, height};
}

bool WebViewWindow::containsPointer() const {
    if (!native_ || !native_->window) {
        return false;
    }
    GdkWindow* window = api().widget_get_window(native_->window);
    GdkDisplay* display = api().widget_get_display(native_->window);
    GdkSeat* seat = display ? api().display_get_default_seat(display) : nullptr;
    GdkDevice* pointer = seat ? api().seat_get_pointer(seat) : nullptr;
    GdkWindow* underPointer = pointer ? api().device_get_window_at_position(pointer, nullptr, nullptr) : nullptr;
    // Wayland has no global coordinates; compare the actual windows, including WebKit's child windows.
    return window && underPointer && api().window_get_toplevel(underPointer) == window;
}

void WebViewWindow::platformConfine(bool confined) {
    if (native_) {
        native_->confined = confined;
    }
}

void WebViewWindow::platformSetSkipTaskbar() {
    if (native_ && native_->window) {
        api().window_set_skip_taskbar_hint(reinterpret_cast<GtkWindow*>(native_->window), options_.skipTaskbar);
    }
}

void WebViewWindow::platformSetTitle(const std::string& title) {
    if (native_ && native_->window) {
        api().window_set_title(reinterpret_cast<GtkWindow*>(native_->window), title.c_str());
    }
}

void WebViewWindow::platformOpenDevTools() {
    if (native_ && native_->view) {
        // WebKitGTK keeps the inspector off until its developer extras are on.
        api().settings_set_enable_developer_extras(api().web_view_get_settings(native_->view), TRUE);
        api().web_inspector_show(api().web_view_get_inspector(native_->view));
    }
}

// WebKitGTK shows the window when its page has loaded, so a ready page has nothing more to do here.
void WebViewWindow::platformPageReady() {
    if (!native_) {
        return;
    }
    native_->pageReady = true;
    showReadyPage(native_.get());
}

void WebViewWindow::platformRunScript(const std::string& script) {
    if (native_ && native_->view) {
        api().web_view_run_javascript(native_->view, script.c_str(), nullptr, nullptr, nullptr);
    }
}

std::optional<RuntimeProblem> missingWindowingRuntime() {
    if (!dlopen("libgtk-3.so.0", RTLD_LAZY | RTLD_LOCAL)) {
        return RuntimeProblem{"GTK 3 isn't installed, so the windows can't open. Install GTK 3 (libgtk-3-0 on Debian and Ubuntu, gtk3 on Fedora and Arch) and start the application again.", ""};
    }
    if (!dlopen("libwebkit2gtk-4.1.so.0", RTLD_LAZY | RTLD_LOCAL)) {
        return RuntimeProblem{"WebKitGTK 4.1 isn't installed, so the windows can't open. Install it (libwebkit2gtk-4.1-0 on Debian and Ubuntu, webkit2gtk4.1 on Fedora, webkit2gtk-4.1 on Arch) and start the application again.", ""};
    }
    try {
        if (!api().init_check(nullptr, nullptr)) {
            return RuntimeProblem{"GTK couldn't open a display. Start the application from a desktop session.", ""};
        }
    } catch (const std::exception& error) {
        return RuntimeProblem{std::string("The windowing libraries are incomplete: ") + error.what(), ""};
    }
    return std::nullopt;
}

bool transparentBackgroundSupported() {
    return true;
}

void offerLink(const std::string& message, const std::string&) {
    // Linux has no runtime that's offered as a download, so the message is all there is to show.
    showError(message);
}

void initializeWindowing() {
    requireWindowingRuntime();
    ensureGtk();
}

void setApplicationIcon(const std::string& png) {
    ensureGtk();
    void* library = dlopen("libgtk-3.so.0", RTLD_LAZY | RTLD_LOCAL);
    if (!library) {
        return;
    }
    using LoaderNew = GdkPixbufLoader* (*)();
    using LoaderWrite = gboolean (*)(GdkPixbufLoader*, const guchar*, gsize, GError**);
    using LoaderClose = gboolean (*)(GdkPixbufLoader*, GError**);
    using LoaderPixbuf = GdkPixbuf* (*)(GdkPixbufLoader*);
    using Scale = GdkPixbuf* (*)(const GdkPixbuf*, gint, gint, GdkInterpType);
    using Unref = void (*)(gpointer);
    using Size = int (*)(const GdkPixbuf*);
    auto loaderNew = reinterpret_cast<LoaderNew>(dlsym(library, "gdk_pixbuf_loader_new"));
    auto loaderWrite = reinterpret_cast<LoaderWrite>(dlsym(library, "gdk_pixbuf_loader_write"));
    auto loaderClose = reinterpret_cast<LoaderClose>(dlsym(library, "gdk_pixbuf_loader_close"));
    auto loaderPixbuf = reinterpret_cast<LoaderPixbuf>(dlsym(library, "gdk_pixbuf_loader_get_pixbuf"));
    auto scale = reinterpret_cast<Scale>(dlsym(library, "gdk_pixbuf_scale_simple"));
    auto unref = reinterpret_cast<Unref>(dlsym(library, "g_object_unref"));
    auto width = reinterpret_cast<Size>(dlsym(library, "gdk_pixbuf_get_width"));
    auto height = reinterpret_cast<Size>(dlsym(library, "gdk_pixbuf_get_height"));
    if (!loaderNew || !loaderWrite || !loaderClose || !loaderPixbuf || !scale || !unref || !width || !height) {
        return;
    }
    GdkPixbufLoader* loader = loaderNew();
    const bool written = loaderWrite(loader, reinterpret_cast<const guchar*>(png.data()), png.size(), nullptr) &&
                         loaderClose(loader, nullptr);
    GdkPixbuf* decoded = written ? loaderPixbuf(loader) : nullptr;
    // The picture is kept at the size it was made, so it isn't stretched; the copy is owned here, and the loader's picture is released.
    GdkPixbuf* scaled = decoded ? scale(decoded, width(decoded), height(decoded), GDK_INTERP_BILINEAR) : nullptr;
    unref(loader);
    if (scaled) {
        if (applicationIcon) {
            unref(applicationIcon);
        }
        applicationIcon = scaled;
    }
}

namespace {

// The tray icon and its menu. Its callbacks run on the GTK thread, which is the event loop's thread.
struct TrayState {
    void* icon = nullptr;
    GtkWidget* menu = nullptr;
    std::function<void()> onActivate;
    std::vector<std::unique_ptr<std::function<void()>>> actions;
};

std::unique_ptr<TrayState> trayState;

void onTrayActivate(void*, gpointer) {
    if (trayState && trayState->onActivate) {
        trayState->onActivate();
    }
}

void onTrayPopupMenu(void*, guint button, guint time, gpointer) {
    if (!trayState || !trayState->menu) {
        return;
    }
    api().widget_show_all(trayState->menu);
    api().menu_popup(trayState->menu, nullptr, nullptr, reinterpret_cast<void*>(api().status_icon_position_menu),
                     trayState->icon, button, time);
}

void onMenuItemActivate(void*, gpointer action) {
    auto* run = static_cast<std::function<void()>*>(action);
    if (run && *run) {
        (*run)();
    }
}

}  // namespace

bool showTrayIcon(const std::string& tooltip, std::function<void()> onActivate, std::vector<TrayMenuItem> menu) {
    ensureGtk();
    if (!applicationIcon) {
        return false;
    }
    removeTrayIcon();
    auto state = std::make_unique<TrayState>();
    state->onActivate = std::move(onActivate);
    state->menu = api().menu_new();
    for (auto& entry : menu) {
        auto action = std::make_unique<std::function<void()>>(std::move(entry.action));
        GtkWidget* item = api().menu_item_new_with_label(entry.label.c_str());
        api().g_signal_connect_data(item, "activate", reinterpret_cast<GCallback>(onMenuItemActivate), action.get(), nullptr, static_cast<GConnectFlags>(0));
        api().menu_shell_append(reinterpret_cast<GtkMenuShell*>(state->menu), item);
        state->actions.push_back(std::move(action));
    }
    state->icon = api().status_icon_new_from_pixbuf(applicationIcon);
    api().status_icon_set_tooltip_text(state->icon, tooltip.c_str());
    api().g_signal_connect_data(state->icon, "activate", reinterpret_cast<GCallback>(onTrayActivate), nullptr, nullptr, static_cast<GConnectFlags>(0));
    api().g_signal_connect_data(state->icon, "popup-menu", reinterpret_cast<GCallback>(onTrayPopupMenu), nullptr, nullptr, static_cast<GConnectFlags>(0));
    api().status_icon_set_visible(state->icon, TRUE);
    trayState = std::move(state);
    return true;
}

void removeTrayIcon() {
    if (!trayState) {
        return;
    }
    api().status_icon_set_visible(trayState->icon, FALSE);
    if (trayState->menu) {
        api().widget_destroy(trayState->menu);
    }
    trayState.reset();
}

void runEventLoop() {
    ensureGtk();
    api().main_loop();
}

void stopEventLoop() {
    api().main_quit();
}

namespace {

gboolean runQueuedTask(gpointer data) {
    auto* task = static_cast<std::function<void()>*>(data);
    (*task)();
    delete task;
    return FALSE;
}

}  // namespace

void runOnUiThread(std::function<void()> task) {
    api().idle_add(runQueuedTask, new std::function<void()>(std::move(task)));
}

namespace {

// The work area of a monitor, or nothing when there's no monitor.
std::optional<ScreenRect> areaOf(GdkMonitor* monitor) {
    if (!monitor) {
        return std::nullopt;
    }
    GdkRectangle area{};
    api().monitor_get_workarea(monitor, &area);
    return ScreenRect{area.x, area.y, area.width, area.height};
}

}  // namespace

std::optional<ScreenRect> workArea() {
    GdkDisplay* display = api().display_get_default();
    return display ? areaOf(api().display_get_primary_monitor(display)) : std::nullopt;
}

std::optional<ScreenRect> workAreaAt(const ScreenRect& rect) {
    GdkDisplay* display = api().display_get_default();
    if (!display) {
        return std::nullopt;
    }
    // The monitor under the rectangle's centre.
    return areaOf(api().display_get_monitor_at_point(display, rect.centreX(), rect.centreY()));
}

std::optional<std::pair<int, int>> cursorPosition() {
    GdkDisplay* display = api().display_get_default();
    if (!display) {
        return std::nullopt;
    }
    gint x = 0;
    gint y = 0;
    api().display_get_pointer(display, nullptr, &x, &y, nullptr);
    return std::make_pair(static_cast<int>(x), static_cast<int>(y));
}

