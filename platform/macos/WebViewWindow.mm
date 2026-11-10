// The macOS window: a borderless NSPanel with a WKWebView. AppKit and WebKit are used from the main thread, which is the event loop's
// thread. Compiled with ARC (see CMakeLists.txt), so the Objective-C objects here are managed by the compiler.

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <dispatch/dispatch.h>

#include "WebViewWindow.h"

@class WVWindow;
@class WVWebViewDelegate;
@class WVWindowDelegate;
@class WVDownloadDelegate;
@class WVTrayTarget;
@class WVQuitTarget;

// The native side of one window. It's created when the window opens and freed when the web view is freed or the window closes.
struct NativeWindow {
    WebViewWindow* owner = nullptr;
    // Expires with the native window, so a callback still queued when the window is freed does nothing.
    std::shared_ptr<bool> alive = std::make_shared<bool>(true);
    WVWindow* window = nil;
    WKWebView* view = nil;
    WVWebViewDelegate* webDelegate = nil;
    WVWindowDelegate* windowDelegate = nil;
    // Runs while the user drags or resizes the window, and follows the pointer until the button is let go.
    NSTimer* dragTimer = nil;
    // The window stays hidden until its page reports that it's ready, so it never shows an empty or half-drawn page.
    bool pageReady = false;
    bool wantsVisible = false;
    bool wantsFocus = false;
    // Set once the window has been shown for the first time.
    bool shownOnce = false;
    // Set once the web view has failed, so the failure is reported once.
    bool failed = false;
    // Whether a window dropped after a move or resize is kept inside its monitor's work area.
    bool confined = true;
    bool maximized = false;
    ScreenRect restoreFrame;
    // The page's minimum size, in device-independent pixels. The user's resizing is held to it.
    int minWidth = 0;
    int minHeight = 0;
    // The drag in progress: where the pointer began, the frame it began with, and which edge a resize moves.
    bool resizing = false;
    ResizeEdge edge = ResizeEdge::NorthWest;
    ScreenRect dragStart;
    int pressX = 0;
    int pressY = 0;
};

// A borderless panel. Being a panel lets it take the focus without a title bar, and AppKit's constraint on where a window may go is
// left to the library, which keeps the window in its work area only when it's confined there.
@interface WVWindow : NSPanel
@end

// The page's messages, navigation, permission requests and downloads for one window.
@interface WVWebViewDelegate : NSObject <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate>
- (instancetype)initWithNative:(NativeWindow*)native;
@end

// The window's own events: focus, moves and resizes.
@interface WVWindowDelegate : NSObject <NSWindowDelegate>
- (instancetype)initWithNative:(NativeWindow*)native;
@end

// Decides where every download is saved. One is shared by all windows, since a download outlives the navigation that started it.
@interface WVDownloadDelegate : NSObject <WKDownloadDelegate>
+ (instancetype)shared;
@end

// The system tray icon's clicks and its menu items.
@interface WVTrayTarget : NSObject
- (void)clicked:(id)sender;
- (void)runItem:(id)sender;
@end

// The Quit item of the application menu. It stops the event loop, which returns from runEventLoop, rather than ending the process.
@interface WVQuitTarget : NSObject
- (void)quit:(id)sender;
@end

@implementation WVWindow
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (BOOL)canBecomeMainWindow {
    return NO;
}
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen*)screen {
    // AppKit would move a window back below the menu bar. The library confines windows itself, so it's left where it's put.
    return frameRect;
}
@end

namespace {

// The tray icon's state, kept while the icon is shown.
struct TrayState {
    NSStatusItem* item = nil;
    NSMenu* menu = nil;
    // AppKit holds the icon's and the menu items' targets weakly, so the target is kept here while the icon is shown.
    WVTrayTarget* target = nil;
    std::function<void()> onActivate;
    // The menu items' actions. Each item points at its entry, which lives as long as the icon.
    std::vector<std::unique_ptr<std::function<void()>>> actions;
};

std::unique_ptr<TrayState> trayState;
NSImage* applicationIcon = nil;

// Screen coordinates on macOS start at the bottom left of the primary screen, with y growing upwards. The rest of the library
// uses the top left, so the primary screen's height flips them.
CGFloat primaryScreenHeight() {
    NSScreen* primary = [NSScreen screens].firstObject;
    return primary ? primary.frame.size.height : 0;
}

ScreenRect toTopLeft(NSRect rect) {
    const CGFloat top = primaryScreenHeight() - (rect.origin.y + rect.size.height);
    return ScreenRect{static_cast<int>(std::round(rect.origin.x)), static_cast<int>(std::round(top)),
                      static_cast<int>(std::round(rect.size.width)), static_cast<int>(std::round(rect.size.height))};
}

NSRect toCocoa(const ScreenRect& rect) {
    return NSMakeRect(rect.x, primaryScreenHeight() - (rect.y + rect.height), rect.width, rect.height);
}

ScreenRect frameOf(const NativeWindow* native) {
    return toTopLeft(native->window.frame);
}

NSWindowLevel levelFor(const WindowOptions& options) {
    if (options.alwaysOnTop) {
        return NSFloatingWindowLevel;
    }
    if (options.keepBelow) {
        // Just above the desktop's wallpaper, so the window reads as part of the desktop and sits under every other window.
        return CGWindowLevelForKey(kCGDesktopWindowLevelKey) + 1;
    }
    return NSNormalWindowLevel;
}

// Keeps the window off the Cmd-Tab cycle and out of the Window menu when it's skipping the taskbar, and keeps it on every space when
// it's sticky. macOS has no taskbar button for a single window, so this is the closest it gets.
void applyBehavior(WVWindow* window, bool skipTaskbar, bool sticky) {
    NSWindowCollectionBehavior behavior = NSWindowCollectionBehaviorDefault;
    if (sticky) {
        behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces;
    }
    if (skipTaskbar) {
        behavior |= NSWindowCollectionBehaviorIgnoresCycle;
    }
    window.collectionBehavior = behavior;
    window.excludedFromWindowsMenu = skipTaskbar;
}

void activateApplication() {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // On macOS 14 and later, activate alone can leave the app behind the one that started it, so the older call is made too.
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    }
    [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
}

// Brings the window to the front and gives it the focus. A minimised window is restored first.
void bringToFront(NativeWindow* native) {
    if (native->window.miniaturized) {
        [native->window deminiaturize:nil];
    }
    activateApplication();
    [native->window makeKeyAndOrderFront:nil];
}

// Shows the window once its page has reported ready, if it's wanted yet. Focus goes to it only if it was asked for.
void showReadyPage(NativeWindow* native) {
    if (!native->window || !native->wantsVisible || !native->pageReady) {
        return;
    }
    // The first showing brings the window to the front of the app, which is the one the user just started. An app that isn't
    // active would otherwise leave it behind the frontmost app's windows.
    if (native->wantsFocus || !native->shownOnce) {
        native->wantsFocus = false;
        native->shownOnce = true;
        bringToFront(native);
    } else {
        [native->window orderFront:nil];
    }
}

// Reports that the web view can't carry on, once. The owner decides what the user is shown, on the next turn of the event loop.
void failWebView(NativeWindow* native, const std::string& message) {
    if (native->failed) {
        return;
    }
    native->failed = true;
    native->owner->keepWebView();
    WebViewWindow* owner = native->owner;
    const std::weak_ptr<bool> alive = native->alive;
    // The block runs after this returns, so it holds its own copy of the message rather than the caller's.
    const std::string text = message;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!alive.expired()) {
            owner->notifyWebViewFailed(text);
        }
    });
}

// A navigation the library cancelled itself (for example, one that became a download) isn't a failure.
void reportNavigationError(NativeWindow* native, NSError* error) {
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    const char* description = error.localizedDescription.UTF8String;
    failWebView(native, std::string("Loading the page failed: ") + (description ? description : "unknown error"));
}

// Loads the page the window shows: its address when it has one, otherwise the inline HTML.
void loadPage(NativeWindow* native) {
    const std::string url = native->owner->devUrl();
    if (!url.empty()) {
        NSURL* address = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
        if (!address) {
            failWebView(native, "The page's address isn't valid: " + url);
            return;
        }
        [native->view loadRequest:[NSURLRequest requestWithURL:address]];
    } else {
        [native->view loadHTMLString:[NSString stringWithUTF8String:native->owner->html().c_str()] baseURL:nil];
    }
}

}  // namespace

namespace {

// The WKPermissionDecision for a request made of parts: granted when every part is allowed, denied when one is refused, and left to
// WebKit's own prompt when the host has no answer for a part.
WKPermissionDecision answerPermissions(WebViewWindow* owner, const std::vector<PagePermission>& parts, const std::string& pageUrl) {
    if (parts.empty()) {
        return WKPermissionDecisionPrompt;
    }
    bool allowed = true;
    for (const PagePermission part : parts) {
        const std::optional<bool> answer = owner->decidePermission(part, pageUrl);
        if (!answer) {
            return WKPermissionDecisionPrompt;
        }
        allowed = allowed && *answer;
    }
    return allowed ? WKPermissionDecisionGrant : WKPermissionDecisionDeny;
}

// Where a download goes: the chooser's path when it gives one. Otherwise the Downloads folder, with a number added to the name when
// the name is taken, so a download never replaces a file.
NSURL* downloadDestination(NSString* suggestedName) {
    const std::string name = suggestedName ? std::string(suggestedName.UTF8String) : std::string();
    if (const std::optional<std::filesystem::path> path = chooseDownloadPath(name)) {
        return [NSURL fileURLWithPath:[NSString stringWithUTF8String:path->string().c_str()]];
    }
    NSFileManager* files = [NSFileManager defaultManager];
    NSURL* folder = [files URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
    NSString* fileName = suggestedName.length > 0 ? suggestedName : @"download";
    NSString* stem = fileName.stringByDeletingPathExtension;
    NSString* extension = fileName.pathExtension;
    NSURL* candidate = [folder URLByAppendingPathComponent:fileName];
    for (int number = 2; [files fileExistsAtPath:candidate.path]; ++number) {
        NSString* numbered = [NSString stringWithFormat:@"%@ (%d)", stem, number];
        candidate = [folder URLByAppendingPathComponent:extension.length > 0 ? [numbered stringByAppendingPathExtension:extension] : numbered];
    }
    return candidate;
}

// Loads the page again after the web content process died, or the page's address didn't load, and tells the user why it blanked.
void reloadAfterProcessFailure(NativeWindow* native) {
    loadPage(native);
    WebViewWindow* owner = native->owner;
    const std::string message = owner->pageReloadedMessage();
    dispatch_async(dispatch_get_main_queue(), ^{
        showError(message);
    });
}

// The page's origin, as the permission hook gets it: its address when WebKit has one, otherwise the origin the request came from.
std::string pageAddress(WKWebView* view, WKSecurityOrigin* origin) {
    if (view.URL.absoluteString.length > 0) {
        return std::string(view.URL.absoluteString.UTF8String);
    }
    const NSInteger port = origin.port;
    NSString* text = port > 0 ? [NSString stringWithFormat:@"%@://%@:%ld", origin.protocol, origin.host, (long)port]
                              : [NSString stringWithFormat:@"%@://%@", origin.protocol, origin.host];
    return std::string(text.UTF8String);
}

// The drag's poll interval, and the grid that moves and resizes snap to, in screen pixels.
constexpr NSTimeInterval kDragPollSeconds = 0.02;
constexpr int kSnapGrid = 8;

// The logical coordinate nearest to a point on the grid of screen pixels, which are the points times the backing scale.
int snapToGrid(int logical, double scale) {
    const double screen = std::round(static_cast<double>(logical) * scale / kSnapGrid) * kSnapGrid;
    return static_cast<int>(std::round(screen / scale));
}

// Whether the primary mouse button is held.
bool buttonHeld() {
    return ([NSEvent pressedMouseButtons] & 1) != 0;
}

// The frame a drag asks for when the pointer has moved by (dx, dy) since it began: snapped to the grid, and inside the work area when
// the window is confined to it. A move keeps the size; a resize moves only the edges its edge names, and keeps the page's minimum.
ScreenRect dragTarget(const NativeWindow& native, int dx, int dy) {
    const ScreenRect start = native.dragStart;
    const double scale = native.window.backingScaleFactor;
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
    if (right - left < native.minWidth) {
        if (west) {
            left = right - native.minWidth;
        } else {
            right = left + native.minWidth;
        }
    }
    if (bottom - top < native.minHeight) {
        if (north) {
            top = bottom - native.minHeight;
        } else {
            bottom = top + native.minHeight;
        }
    }
    return ScreenRect{left, top, right - left, bottom - top};
}

// Moves and resizes the window to the target, when it differs from the window's frame.
void applyFrame(NativeWindow* native, const ScreenRect& target) {
    if (target != frameOf(native)) {
        [native->window setFrame:toCocoa(target) display:YES animate:NO];
    }
}

void stopDrag(NativeWindow* native) {
    [native->dragTimer invalidate];
    native->dragTimer = nil;
}

// Runs each time the drag's poll fires. The window follows the pointer while the button is held, and the poll stops once it's let go.
void onDragTick(NativeWindow* native) {
    if (!buttonHeld()) {
        stopDrag(native);
        return;
    }
    const auto pointer = cursorPosition();
    if (native->window && pointer) {
        applyFrame(native, dragTarget(*native, pointer->first - native->pressX, pointer->second - native->pressY));
    }
}

// Records where a drag began and starts its poll. A new press restarts the drag, even while the last one's poll still runs.
void beginDrag(NativeWindow* native, bool resizing, ResizeEdge edge) {
    const auto pointer = cursorPosition();
    if (!native->window || !pointer || !buttonHeld()) {
        return;
    }
    native->resizing = resizing;
    native->edge = edge;
    native->pressX = pointer->first;
    native->pressY = pointer->second;
    native->dragStart = frameOf(native);
    if (!native->dragTimer) {
        native->dragTimer = [NSTimer scheduledTimerWithTimeInterval:kDragPollSeconds repeats:YES block:^(NSTimer*) {
            onDragTick(native);
        }];
    }
}

// Sets the web view's background. Drawing none lets the desktop show through a transparent page.
void setDrawsBackground(WKWebView* view, bool draws) {
    if ([view respondsToSelector:NSSelectorFromString(@"setDrawsBackground:")]) {
        [view setValue:@(draws) forKey:@"drawsBackground"];
    }
    if (!draws && [view respondsToSelector:@selector(setUnderPageBackgroundColor:)]) {
        view.underPageBackgroundColor = [NSColor clearColor];
    }
}

NSString* nsString(const std::string& text) {
    return [NSString stringWithUTF8String:text.c_str()];
}

}  // namespace

@implementation WVWebViewDelegate {
    NativeWindow* native_;
}

- (instancetype)initWithNative:(NativeWindow*)native {
    self = [super init];
    if (self) {
        native_ = native;
    }
    return self;
}

// A script message from the page: window.webkit.messageHandlers.host.postMessage(text).
- (void)userContentController:(WKUserContentController*)controller didReceiveScriptMessage:(WKScriptMessage*)message {
    if (![message.body isKindOfClass:[NSString class]]) {
        return;
    }
    native_->owner->receive(std::string([(NSString*)message.body UTF8String]));
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    native_->owner->notifyPageLoaded();
}

- (void)webView:(WKWebView*)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error {
    reportNavigationError(native_, error);
}

- (void)webView:(WKWebView*)webView didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error {
    reportNavigationError(native_, error);
}

// The page's process died: the page is loaded again, and the user is told.
- (void)webViewWebContentProcessDidTerminate:(WKWebView*)webView {
    reloadAfterProcessFailure(native_);
}

// A link with a download attribute, or any navigation that the page can't show, becomes a download.
- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (@available(macOS 11.3, *)) {
        if (action.shouldPerformDownload) {
            decisionHandler(WKNavigationActionPolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationResponse:(WKNavigationResponse*)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (@available(macOS 11.3, *)) {
        if (!response.canShowMIMEType) {
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView*)webView navigationAction:(WKNavigationAction*)action didBecomeDownload:(WKDownload*)download {
    download.delegate = [WVDownloadDelegate shared];
}

- (void)webView:(WKWebView*)webView navigationResponse:(WKNavigationResponse*)response didBecomeDownload:(WKDownload*)download {
    download.delegate = [WVDownloadDelegate shared];
}

// The page asks for the camera or the microphone. The host's answer decides each part; without one, WebKit prompts the user.
- (void)webView:(WKWebView*)webView requestMediaCapturePermissionForOrigin:(WKSecurityOrigin*)origin
    initiatedByFrame:(WKFrameInfo*)frame type:(WKMediaCaptureType)type decisionHandler:(void (^)(WKPermissionDecision))decisionHandler {
    std::vector<PagePermission> parts;
    if (type == WKMediaCaptureTypeMicrophone || type == WKMediaCaptureTypeCameraAndMicrophone) {
        parts.push_back(PagePermission::Microphone);
    }
    if (type == WKMediaCaptureTypeCamera || type == WKMediaCaptureTypeCameraAndMicrophone) {
        parts.push_back(PagePermission::Camera);
    }
    decisionHandler(answerPermissions(native_->owner, parts, pageAddress(webView, origin)));
}

@end

@implementation WVWindowDelegate {
    NativeWindow* native_;
}

- (instancetype)initWithNative:(NativeWindow*)native {
    self = [super init];
    if (self) {
        native_ = native;
    }
    return self;
}

// The page takes the keyboard when the window is key, so typing and the Edit menu's shortcuts reach it.
- (void)windowDidBecomeKey:(NSNotification*)notification {
    [native_->window makeFirstResponder:native_->view];
}

- (void)windowDidResignKey:(NSNotification*)notification {
    native_->owner->notifyFocusLost();
}

- (void)windowDidMove:(NSNotification*)notification {
    native_->owner->notifyFrameChanged();
}

- (void)windowDidResize:(NSNotification*)notification {
    native_->owner->notifyFrameChanged();
}

@end

@implementation WVDownloadDelegate

+ (instancetype)shared {
    static WVDownloadDelegate* instance = [[WVDownloadDelegate alloc] init];
    return instance;
}

- (void)download:(WKDownload*)download decideDestinationUsingResponse:(NSURLResponse*)response
    suggestedFilename:(NSString*)suggestedFilename completionHandler:(void (^)(NSURL*))completionHandler {
    completionHandler(downloadDestination(suggestedFilename));
}

@end

@implementation WVTrayTarget

- (void)clicked:(id)sender {
    NSEvent* event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp) {
        if (trayState && trayState->menu) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            // The menu is shown from the icon directly. Setting the item's menu would make every click open it, not only a right click.
            [trayState->item popUpStatusItemMenu:trayState->menu];
#pragma clang diagnostic pop
        }
    } else if (trayState && trayState->onActivate) {
        trayState->onActivate();
    }
}

- (void)runItem:(id)sender {
    NSValue* value = [(NSMenuItem*)sender representedObject];
    auto* action = static_cast<std::function<void()>*>(value.pointerValue);
    if (action && *action) {
        (*action)();
    }
}

@end

@implementation WVQuitTarget

- (void)quit:(id)sender {
    stopEventLoop();
}

@end

void NativeWindowDeleter::operator()(NativeWindow* native) const {
    if (!native) {
        return;
    }
    stopDrag(native);
    if (native->view) {
        // Nothing the page does after this reaches the window: its handlers and delegates are removed before it's freed.
        native->view.navigationDelegate = nil;
        native->view.UIDelegate = nil;
        [native->view.configuration.userContentController removeScriptMessageHandlerForName:@"host"];
        [native->view stopLoading:nil];
    }
    if (native->window) {
        native->window.delegate = nil;
        [native->window orderOut:nil];
        [native->window close];
    }
    delete native;
}

void WebViewWindow::platformOpen() {
    native_.reset(new NativeWindow);
    NativeWindow* native = native_.get();
    native->owner = this;
    native->confined = options_.confinedToWorkArea;
    native->wantsVisible = options_.visible;
    native->minWidth = scaledSize(options_.minWidth);
    native->minHeight = scaledSize(options_.minHeight);

    // Sizes are in device-independent pixels, which are the points AppKit works in.
    const int width = std::max(scaledSize(options_.width), native->minWidth);
    const int height = std::max(scaledSize(options_.height), native->minHeight);
    // Opened in the middle of the work area. A caller that places the window moves it after it's opened.
    ScreenRect frame{0, 0, width, height};
    if (const auto area = workArea()) {
        frame.x = area->x + (area->width - width) / 2;
        frame.y = area->y + (area->height - height) / 2;
    }

    WVWindow* window = [[WVWindow alloc] initWithContentRect:toCocoa(frame)
                                                   styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    // Utility is a no-op here, as the header says: AppKit drops the utility window style on a borderless panel, and every window is
    // already a panel. A panel is floating by default; the window takes the level its options ask for instead.
    window.floatingPanel = NO;
    window.level = levelFor(options_);
    window.hidesOnDeactivate = NO;
    window.releasedWhenClosed = NO;
    window.title = nsString(title());
    window.opaque = !options_.transparent;
    window.backgroundColor = options_.transparent ? [NSColor clearColor] : [NSColor windowBackgroundColor];
    applyBehavior(window, options_.skipTaskbar, options_.sticky);
    native->window = window;

    // The page's messages come through the "host" handler. The WKWebView is given the window's full content area.
    WKUserContentController* controller = [[WKUserContentController alloc] init];
    native->webDelegate = [[WVWebViewDelegate alloc] initWithNative:native];
    [controller addScriptMessageHandler:native->webDelegate name:@"host"];
    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = controller;
    // WKWebView leaves navigator.mediaDevices off unless this preference is on, so the page can't ask for the microphone or camera.
    @try {
        [configuration.preferences setValue:@YES forKey:@"mediaDevicesEnabled"];
    } @catch (NSException* exception) {
        // A WebKit without the preference keeps its default.
    }
    WKWebView* view = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, width, height) configuration:configuration];
    view.navigationDelegate = native->webDelegate;
    view.UIDelegate = native->webDelegate;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (options_.transparent) {
        setDrawsBackground(view, false);
    }
    native->view = view;
    window.contentView = view;

    native->windowDelegate = [[WVWindowDelegate alloc] initWithNative:native];
    window.delegate = native->windowDelegate;

    // The window is ordered in once the page reports that it's ready, so it never shows an empty frame.
    loadPage(native);

    if (options_.startupTimeout > std::chrono::seconds::zero()) {
        const std::weak_ptr<bool> alive = native->alive;
        const auto timeout = std::chrono::duration_cast<std::chrono::nanoseconds>(options_.startupTimeout).count();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, timeout), dispatch_get_main_queue(), ^{
            if (!alive.expired() && !native->pageReady) {
                failWebView(native, "Loading the page took too long, so the page didn't report that it's ready.");
            }
        });
    }
}

void WebViewWindow::platformUnload() {
    native_.reset();
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
        // The first showing activates the app, as the page-ready path does, so a window shown later still comes to the front.
        if (!native_->shownOnce) {
            native_->shownOnce = true;
            bringToFront(native_.get());
        } else {
            [native_->window orderFront:nil];
        }
    } else {
        [native_->window orderOut:nil];
    }
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
    bringToFront(native_.get());
}

void WebViewWindow::platformPageReady() {
    if (!native_) {
        return;
    }
    native_->pageReady = true;
    showReadyPage(native_.get());
}

void WebViewWindow::platformResize(int width, int height) {
    if (!native_ || !native_->window) {
        return;
    }
    // The window keeps its top left corner, as the other platforms do.
    const ScreenRect current = frameOf(native_.get());
    [native_->window setFrame:toCocoa(ScreenRect{current.x, current.y, width, height}) display:YES animate:NO];
}

void WebViewWindow::platformMove(int x, int y) {
    if (native_ && native_->window) {
        [native_->window setFrameTopLeftPoint:NSMakePoint(x, primaryScreenHeight() - y)];
    }
}

// The window's frame in points, which are the device-independent pixels the library uses. Nothing while it's minimised, since AppKit
// reports where it was then.
std::optional<ScreenRect> WebViewWindow::platformFrame() const {
    if (!native_ || !native_->window || native_->window.miniaturized) {
        return std::nullopt;
    }
    return frameOf(native_.get());
}

bool WebViewWindow::containsPointer() const {
    const auto pointer = cursorPosition();
    const auto bounds = frame();
    return pointer && bounds && bounds->contains(pointer->first, pointer->second);
}

// AppKit measures in points, which are already the library's device-independent pixels.
int WebViewWindow::platformToIndependent(int pixels) const {
    return pixels;
}

void WebViewWindow::platformBeginMove() {
    if (native_) {
        beginDrag(native_.get(), false, ResizeEdge::NorthWest);
    }
}

void WebViewWindow::platformBeginResize(ResizeEdge edge) {
    if (native_) {
        beginDrag(native_.get(), true, edge);
    }
}

void WebViewWindow::platformMinimize() {
    if (native_ && native_->window) {
        [native_->window miniaturize:nil];
    }
}

// A borderless window has no zoom button, so the window fills its monitor's work area and goes back to its own frame when toggled again.
void WebViewWindow::platformToggleMaximize() {
    if (!native_ || !native_->window) {
        return;
    }
    NativeWindow* native = native_.get();
    if (native->maximized) {
        native->maximized = false;
        [native->window setFrame:toCocoa(native->restoreFrame) display:YES animate:NO];
        return;
    }
    const auto area = workAreaAt(frameOf(native));
    if (!area) {
        return;
    }
    native->restoreFrame = frameOf(native);
    native->maximized = true;
    [native->window setFrame:toCocoa(*area) display:YES animate:NO];
}

// The close a title bar's button would ask for: allowClose decides, and a window that closes is taken off the screen.
void WebViewWindow::platformClose() {
    if (!native_ || !native_->window) {
        return;
    }
    if (!requestClose()) {
        return;
    }
    NativeWindow* native = native_.get();
    stopDrag(native);
    native->window.delegate = nil;
    [native->window orderOut:nil];
    [native->window close];
    native->window = nil;
    notifyClosed();
}

void WebViewWindow::platformSetSkipTaskbar() {
    if (native_ && native_->window) {
        applyBehavior(native_->window, options_.skipTaskbar, options_.sticky);
    }
}

void WebViewWindow::platformConfine(bool confined) {
    if (native_) {
        native_->confined = confined;
    }
}

void WebViewWindow::platformSetTitle(const std::string& title) {
    if (native_ && native_->window) {
        native_->window.title = nsString(title);
    }
}

// WebKit's inspector is opened through its own window controller, which WKWebView exposes privately. The view is made inspectable first,
// so the inspector is available at all.
void WebViewWindow::platformOpenDevTools() {
    if (!native_ || !native_->view) {
        return;
    }
    WKWebView* view = native_->view;
    // WebKit keeps the inspector off until developer extras are on, as WebKitGTK does.
    @try {
        [view.configuration.preferences setValue:@YES forKey:@"developerExtrasEnabled"];
    } @catch (NSException* exception) {
        // A WebKit without the preference keeps its default.
    }
    if ([view respondsToSelector:@selector(setInspectable:)]) {
        view.inspectable = YES;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    SEL inspectorSelector = NSSelectorFromString(@"_inspector");
    if ([view respondsToSelector:inspectorSelector]) {
        id inspector = [view performSelector:inspectorSelector];
        SEL show = NSSelectorFromString(@"show");
        if ([inspector respondsToSelector:show]) {
            [inspector performSelector:show];
        }
    }
#pragma clang diagnostic pop
}

void WebViewWindow::platformRunScript(const std::string& script) {
    if (native_ && native_->view) {
        [native_->view evaluateJavaScript:nsString(script) completionHandler:nil];
    }
}

std::optional<RuntimeProblem> missingWindowingRuntime() {
    if (NSClassFromString(@"WKWebView") == nil) {
        return RuntimeProblem{"WebKit isn't available, so the windows can't open.", ""};
    }
    return std::nullopt;
}

bool transparentBackgroundSupported() {
    return true;
}

void offerLink(const std::string& message, const std::string&) {
    // macOS has no runtime to offer as a download here, so the message is all there is to show.
    showError(message);
}

void initializeWindowing() {
    requireWindowingRuntime();
    static bool initialized = false;
    if (initialized) {
        return;
    }
    initialized = true;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // The main menu gives the page its Edit shortcuts (copy, paste, select all), which WebKit reads from the responder chain, and a Quit
    // item that stops the event loop.
    NSString* name = nsString(applicationName());
    NSMenu* bar = [[NSMenu alloc] init];
    NSMenuItem* applicationItem = [[NSMenuItem alloc] init];
    [bar addItem:applicationItem];
    NSMenu* applicationMenu = [[NSMenu alloc] initWithTitle:name];
    NSMenuItem* quit = [[NSMenuItem alloc] initWithTitle:[@"Quit " stringByAppendingString:name]
                                                   action:@selector(quit:)
                                            keyEquivalent:@"q"];
    // Targets are held weakly by AppKit, so the quit target is kept for the life of the process.
    static WVQuitTarget* quitTarget = [[WVQuitTarget alloc] init];
    quit.target = quitTarget;
    [applicationMenu addItem:quit];
    applicationItem.submenu = applicationMenu;

    NSMenuItem* editItem = [[NSMenuItem alloc] init];
    [bar addItem:editItem];
    NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;
    [NSApp setMainMenu:bar];
}

void setApplicationIcon(const std::string& png) {
    NSImage* image = [[NSImage alloc] initWithData:[NSData dataWithBytes:png.data() length:png.size()]];
    if (!image) {
        return;
    }
    applicationIcon = image;
    if (NSApp) {
        [NSApp setApplicationIconImage:image];
    }
}

bool showTrayIcon(const std::string& tooltip, std::function<void()> onActivate, std::vector<TrayMenuItem> menu) {
    if (!applicationIcon) {
        return false;
    }
    removeTrayIcon();
    auto state = std::make_unique<TrayState>();
    state->onActivate = std::move(onActivate);
    state->menu = [[NSMenu alloc] init];
    state->target = [[WVTrayTarget alloc] init];
    WVTrayTarget* target = state->target;
    for (auto& entry : menu) {
        auto action = std::make_unique<std::function<void()>>(std::move(entry.action));
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:nsString(entry.label) action:@selector(runItem:) keyEquivalent:@""];
        item.target = target;
        item.representedObject = [NSValue valueWithPointer:action.get()];
        [state->menu addItem:item];
        state->actions.push_back(std::move(action));
    }
    state->item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton* button = state->item.button;
    NSImage* icon = [applicationIcon copy];
    icon.size = NSMakeSize(18, 18);
    button.image = icon;
    button.toolTip = nsString(tooltip);
    button.target = target;
    button.action = @selector(clicked:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    trayState = std::move(state);
    return true;
}

void removeTrayIcon() {
    if (!trayState) {
        return;
    }
    if (trayState->item) {
        [[NSStatusBar systemStatusBar] removeStatusItem:trayState->item];
    }
    trayState.reset();
}

void runEventLoop() {
    [NSApplication sharedApplication];
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
    return std::make_pair(static_cast<int>(std::round(point.x)), static_cast<int>(std::round(primaryScreenHeight() - point.y)));
}
