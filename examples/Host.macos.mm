// The desktop functions the host defines for the library on macOS. examples/Host.linux.cpp and Host.windows.cpp have the others.

#include <cstdio>
#include <cstdlib>
#include <string>

#import <AppKit/AppKit.h>

#include "WebViewWindow.h"

void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
    // The tests set WEBVIEW_EXAMPLE_NO_DIALOGS, since a dialog waits for someone to answer it.
    if (std::getenv("WEBVIEW_EXAMPLE_NO_DIALOGS")) {
        return;
    }
    // An alert needs the application object, which initializeWindowing makes. showError runs on the main thread, as the library
    // calls it from the UI thread or before the event loop starts.
    [NSApplication sharedApplication];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithUTF8String:applicationName().c_str()];
    alert.informativeText = [NSString stringWithUTF8String:message.c_str()];
    alert.alertStyle = NSAlertStyleCritical;
    [alert runModal];
}

// Describes each of the library's windows as the system holds it: the class, the level, the collection behaviour (which holds sticky and
// the skip-taskbar bits) and whether the window is excluded from the Window menu. The example's describe command prints these.
std::string describeHostWindows() {
    std::string text;
    for (NSWindow* window in [NSApp windows]) {
        char line[512];
        std::snprintf(line, sizeof line,
                      "native title=%s class=%s level=%ld behavior=%lu excluded=%d style=%lu visible=%d\n",
                      window.title.UTF8String ?: "", NSStringFromClass([window class]).UTF8String, (long)window.level,
                      (unsigned long)window.collectionBehavior, window.excludedFromWindowsMenu ? 1 : 0,
                      (unsigned long)window.styleMask, window.visible ? 1 : 0);
        text += line;
    }
    return text;
}
