// The desktop functions the host defines for the library. This is the Windows version; the Linux one is left to the application.

#include <cstdio>
#include <optional>
#include <string>
#include <utility>

#include <windows.h>

#include "WebViewWindow.h"


void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
    MessageBoxA(nullptr, message.c_str(), applicationName().c_str(), MB_OK | MB_ICONERROR);
}

std::optional<std::pair<int, int>> cursorPosition() {
    POINT point{};
    if (!GetCursorPos(&point)) {
        return std::nullopt;
    }
    return std::make_pair(static_cast<int>(point.x), static_cast<int>(point.y));
}

std::optional<Rect> workArea() {
    RECT area{};
    if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &area, 0)) {
        return std::nullopt;
    }
    return Rect{area.left, area.top, area.right - area.left, area.bottom - area.top};
}

std::optional<Rect> workAreaAt(const Rect& rect) {
    const RECT bounds{rect.x, rect.y, rect.right(), rect.bottom()};
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST), &info)) {
        return std::nullopt;
    }
    const RECT& area = info.rcWork;
    return Rect{area.left, area.top, area.right - area.left, area.bottom - area.top};
}

