// The desktop functions the host defines for the library on Linux. This example doesn't query the pointer or the work area, so the
// library leaves its windows where they are, and it reports errors on stderr.

#include <cstdio>
#include <optional>
#include <string>
#include <utility>

#include "WebViewWindow.h"

void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
}

std::optional<std::pair<int, int>> cursorPosition() {
    return std::nullopt;
}

std::optional<Rect> workArea() {
    return std::nullopt;
}

std::optional<Rect> workAreaAt(const Rect&) {
    return std::nullopt;
}
