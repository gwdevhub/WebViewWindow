// The desktop functions the host defines for the library on macOS. examples/Host.linux.cpp and Host.windows.cpp have the others.

#include <cstdio>
#include <string>

#import <AppKit/AppKit.h>

#include "WebViewWindow.h"

void showError(const std::string& message) {
    std::fprintf(stderr, "%s\n", message.c_str());
    // An alert needs the application object, which initializeWindowing makes. showError runs on the main thread, as the library
    // calls it from the UI thread or before the event loop starts.
    [NSApplication sharedApplication];
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithUTF8String:applicationName().c_str()];
    alert.informativeText = [NSString stringWithUTF8String:message.c_str()];
    alert.alertStyle = NSAlertStyleCritical;
    [alert runModal];
}
