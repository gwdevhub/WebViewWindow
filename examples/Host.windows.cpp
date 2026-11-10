// The desktop functions the host defines for the library on Windows. examples/Host.linux.cpp has the Linux version.

#include <cstdio>
#include <string>

#include <windows.h>

#include "WebViewWindow.h"


void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
    MessageBoxA(nullptr, message.c_str(), applicationName().c_str(), MB_OK | MB_ICONERROR);
}

// The native windows' settings, as the example's describe command prints them. Only the macOS host reads them; the other hosts have none.
std::string describeHostWindows() {
    return {};
}
