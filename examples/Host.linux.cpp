// The desktop functions the host defines for the library on Linux. The pointer and the monitors' work areas come from the library
// itself, which already loads GTK.

#include <cstdio>
#include <string>

#include "WebViewWindow.h"

void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
}

// The native windows' settings, as the example's describe command prints them. Only the macOS host reads them; the other hosts have none.
std::string describeHostWindows() {
    return {};
}
