// The macOS window. A skeleton: it builds and links, but the window and web view are not implemented yet. Each member that still
// does nothing is marked TODO. The event loop, the UI thread, the work area and the cursor are implemented, but untested.

#include <cstdio>
#include <optional>
#include <string>
#include <utility>

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <dispatch/dispatch.h>

#include "WebViewWindow.h"

// TODO: the window and its WKWebView. Until these exist, the windows are never shown.
struct NativeWindow {
    NSWindow* window = nil;
    WKWebView* view = nil;
};

namespace {

// Screen coordinates on macOS start at the bottom left of the primary screen, with y growing upwards. The rest of the library
// uses the top left, so the primary screen's height flips them.
CGFloat primaryScreenHeight() {
    NSScreen* primary = [NSScreen screens].firstObject;
    return primary ? primary.frame.size.height : 0;
}

ScreenRect toTopLeft(NSRect rect) {
    const CGFloat top = primaryScreenHeight() - (rect.origin.y + rect.size.height);
    return ScreenRect{static_cast<int>(rect.origin.x), static_cast<int>(top), static_cast<int>(rect.size.width),
                static_cast<int>(rect.size.height)};
}

}  // namespace

// --- Native window ---------------------------------------------------------------------------------------------------------

void NativeWindowDeleter::operator()(NativeWindow* native) const {
    delete native;
}

void WebViewWindow::platformOpen() {}                       // TODO: create the NSWindow and WKWebView.
void WebViewWindow::platformUnload() {}                     // TODO
void WebViewWindow::platformPresent() {}                    // TODO
void WebViewWindow::platformBeginMove() {}                  // TODO
void WebViewWindow::platformBeginResize(ResizeEdge) {}      // TODO
void WebViewWindow::platformMinimize() {}                   // TODO
void WebViewWindow::platformToggleMaximize() {}             // TODO
void WebViewWindow::platformClose() {}                      // TODO
void WebViewWindow::platformShow(bool) {}                   // TODO
void WebViewWindow::platformResize(int, int) {}             // TODO
void WebViewWindow::platformMove(int, int) {}               // TODO
void WebViewWindow::platformConfine(bool) {}                // TODO
void WebViewWindow::platformSetSkipTaskbar() {}             // TODO
void WebViewWindow::platformSetTitle(const std::string&) {} // TODO
void WebViewWindow::platformOpenDevTools() {}               // TODO
void WebViewWindow::platformPageReady() {}                  // TODO
void WebViewWindow::platformRunScript(const std::string&) {} // TODO: WKWebView evaluateJavaScript.

// The window's rectangle on the screen. Nothing until the window exists.
std::optional<ScreenRect> WebViewWindow::platformFrame() const {
    return std::nullopt;
}

// TODO: whether the pointer is over the window. Nothing until the window exists.
bool WebViewWindow::containsPointer() const {
    return false;
}

// TODO: points to pixels, using the window's backing scale. Until the window exists, pixels are returned unchanged.
int WebViewWindow::platformToIndependent(int pixels) const {
    return pixels;
}

// --- Desktop functions -----------------------------------------------------------------------------------------------------

std::optional<RuntimeProblem> missingWindowingRuntime() {
    return std::nullopt;  // TODO: check that WebKit and AppKit can be used.
}

// TODO: the WKWebView's transparent background. Until it's set up, the page is told to draw a solid background.
bool transparentBackgroundSupported() {
    return false;
}

void offerLink(const std::string& message, const std::string&) {
    showError(message);
}

void initializeWindowing() {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
}

void setApplicationIcon(const std::string&) {}  // TODO: NSApp.applicationIconImage from the PNG bytes.

void runEventLoop() {
    [NSApp run];
}

void stopEventLoop() {
    // [NSApp stop:] only takes effect after the next event, so an application-defined event wakes the loop up.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp stop:nil];
        NSEvent* wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                           location:NSZeroPoint
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:0
                                            context:nil
                                            subtype:0
                                              data1:0
                                              data2:0];
        [NSApp postEvent:wake atStart:YES];
    });
}

void runOnUiThread(std::function<void()> task) {
    auto* boxed = new std::function<void()>(std::move(task));
    dispatch_async(dispatch_get_main_queue(), ^{
        (*boxed)();
        delete boxed;
    });
}

// The work area is the screen minus the menu bar and the Dock, which is what visibleFrame gives.
std::optional<ScreenRect> workArea() {
    NSScreen* primary = [NSScreen screens].firstObject;
    return primary ? std::optional<ScreenRect>(toTopLeft(primary.visibleFrame)) : std::nullopt;
}

// The work area of the screen whose centre is under the rectangle's centre.
std::optional<ScreenRect> workAreaAt(const ScreenRect& rect) {
    const CGFloat top = primaryScreenHeight() - rect.centreY();
    const NSPoint centre = NSMakePoint(rect.centreX(), top);
    for (NSScreen* screen in [NSScreen screens]) {
        if (NSPointInRect(centre, screen.frame)) {
            return toTopLeft(screen.visibleFrame);
        }
    }
    return std::nullopt;
}

std::optional<std::pair<int, int>> cursorPosition() {
    const NSPoint point = [NSEvent mouseLocation];
    return std::make_pair(static_cast<int>(point.x), static_cast<int>(primaryScreenHeight() - point.y));
}
