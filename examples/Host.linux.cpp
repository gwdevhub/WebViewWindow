// The desktop functions the host defines for the library on Linux. They ask GDK, which the library has already loaded, for the
// pointer and the monitors' work areas.

#include <dlfcn.h>

#include <cstdio>
#include <optional>
#include <string>
#include <utility>

#include "WebViewWindow.h"

namespace {

// GdkRectangle's layout.
struct GdkRectangle {
    int x;
    int y;
    int width;
    int height;
};

// The GDK functions the host uses, resolved from GTK 3.
struct GdkFunctions {
    void* (*display_get_default)() = nullptr;
    void (*display_get_pointer)(void*, void**, int*, int*, unsigned int*) = nullptr;
    void* (*display_get_primary_monitor)(void*) = nullptr;
    void* (*display_get_monitor_at_point)(void*, int, int) = nullptr;
    void (*monitor_get_workarea)(void*, GdkRectangle*) = nullptr;
};

// The GDK functions, or nothing when GTK isn't there. The library has already reported a missing GTK by the time a window is open.
const GdkFunctions* gdk() {
    static GdkFunctions loaded;
    static const bool ready = [] {
        void* library = dlopen("libgtk-3.so.0", RTLD_LAZY | RTLD_LOCAL);
        if (!library) {
            return false;
        }
        loaded.display_get_default = reinterpret_cast<decltype(loaded.display_get_default)>(dlsym(library, "gdk_display_get_default"));
        loaded.display_get_pointer = reinterpret_cast<decltype(loaded.display_get_pointer)>(dlsym(library, "gdk_display_get_pointer"));
        loaded.display_get_primary_monitor =
            reinterpret_cast<decltype(loaded.display_get_primary_monitor)>(dlsym(library, "gdk_display_get_primary_monitor"));
        loaded.display_get_monitor_at_point =
            reinterpret_cast<decltype(loaded.display_get_monitor_at_point)>(dlsym(library, "gdk_display_get_monitor_at_point"));
        loaded.monitor_get_workarea = reinterpret_cast<decltype(loaded.monitor_get_workarea)>(dlsym(library, "gdk_monitor_get_workarea"));
        return loaded.display_get_default && loaded.display_get_pointer && loaded.display_get_primary_monitor &&
               loaded.display_get_monitor_at_point && loaded.monitor_get_workarea;
    }();
    return ready ? &loaded : nullptr;
}

std::optional<Rect> areaOf(void* monitor) {
    if (!monitor) {
        return std::nullopt;
    }
    GdkRectangle area{};
    gdk()->monitor_get_workarea(monitor, &area);
    return Rect{area.x, area.y, area.width, area.height};
}

}  // namespace

void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
}

std::optional<std::pair<int, int>> cursorPosition() {
    const GdkFunctions* functions = gdk();
    void* display = functions ? functions->display_get_default() : nullptr;
    if (!display) {
        return std::nullopt;
    }
    int x = 0;
    int y = 0;
    functions->display_get_pointer(display, nullptr, &x, &y, nullptr);
    return std::make_pair(x, y);
}

std::optional<Rect> workArea() {
    const GdkFunctions* functions = gdk();
    void* display = functions ? functions->display_get_default() : nullptr;
    return display ? areaOf(functions->display_get_primary_monitor(display)) : std::nullopt;
}

std::optional<Rect> workAreaAt(const Rect& rect) {
    const GdkFunctions* functions = gdk();
    void* display = functions ? functions->display_get_default() : nullptr;
    if (!display) {
        return std::nullopt;
    }
    // The monitor under the rectangle's centre.
    return areaOf(functions->display_get_monitor_at_point(display, rect.x + rect.width / 2, rect.y + rect.height / 2));
}
