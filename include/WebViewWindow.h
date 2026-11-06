#pragma once

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <stdexcept>
#include <memory>
#include <optional>
#include <utility>
#include <string>
#include <vector>

#include "Geometry.h"
#include "Messages.h"


// The edges and corners a window can be resized from, in the order GDK's edges use.
enum class ResizeEdge { NorthWest, North, NorthEast, West, East, SouthWest, South, SouthEast };

struct WindowOptions {
    std::string title;
    int width = 300;
    int height = 340;
    // The smallest size a user can resize the window to, in device-independent pixels. Zero means no minimum. Only the user's
    // resizing is held to it, so the page can still set a smaller size.
    int minWidth = 0;
    int minHeight = 0;
    // Every window is frameless: the page draws the title bar, and moves, resizes and closes the window through the calls below.
    bool titleBar = true;
    // Whether the page offers edges to resize the window from. An autosize window never has them.
    bool resizable = true;
    bool skipTaskbar = false;
    bool alwaysOnTop = false;
    bool visible = true;
    // The page sizes the window: its reports through fitToPage set the window's size, in device-independent pixels.
    bool autosize = false;
    // Whether the window stays inside the work area of the monitor it's on. When it's confined, the window is moved back in when it
    // opens, is resized, or is dropped after a move or resize, so it never goes past the monitor's edges. When it isn't confined,
    // the window may go past them, and part of it can be off the screen.
    bool confinedToWorkArea = true;
    // How long a hidden window keeps its web view before the web view is freed. A show or present before then keeps it.
    std::chrono::milliseconds cooldown = std::chrono::minutes(2);
    // Kept under other windows, so the window reads as part of the desktop.
    bool keepBelow = false;
    // Shown on every virtual desktop. Windows has none, so there it does nothing.
    bool sticky = false;
    // A utility window, which the desktop's Show Desktop leaves showing. Only Linux's window manager distinguishes these.
    bool utility = false;
    // The window's background is see-through, where the platform can show the desktop through it. Nothing is drawn behind the
    // page, so the page fills whatever it wants drawn.
    bool transparent = true;
    // The folder WebView2 keeps its profile and caches in. Empty means a folder beside the executable.
    std::filesystem::path webViewDataFolder;
    // How long a page may take to report that it's ready before the window fails. Zero means no limit.
    std::chrono::seconds startupTimeout = std::chrono::seconds(30);
};

// The platform's window and web view. Each platform defines it in its own source file.
struct NativeWindow;

struct NativeWindowDeleter {
    void operator()(NativeWindow* native) const;
};

// A native window with a web view that shows a page and talks to it. Subclasses choose the page and the title.
class WebViewWindow {
public:
    explicit WebViewWindow(WindowOptions options);
    virtual ~WebViewWindow();
    WebViewWindow(const WebViewWindow&) = delete;
    WebViewWindow& operator=(const WebViewWindow&) = delete;

    // Creates the native window and loads the page. Call once, before runEventLoop.
    void open();
    // Recreates the web view and loads the page again, then shows the window. The way back from a failed web view.
    void reload();

    // Shows the window, opening it first if it was never opened or its web view was freed.
    void show();
    // Hides the window. Its web view is freed after a cooldown, unless the window is shown again first.
    void hide();
    // Brings the window to the front and gives it the focus. A hidden or minimised window is shown and restored first.
    void present();
    // The window's rectangle on the screen, when the platform can give it.
    std::optional<Rect> frame() const;
    // Whether the pointer is over the window, when the platform can tell.
    bool containsPointer() const;
    // The window's size in the units resize takes, read back from the screen. Missing when the window isn't open.
    std::optional<std::pair<int, int>> frameUnscaled() const;

    // Whether the window is shown, as far as this layer knows: it's kept in step by open, show and hide.
    bool isVisible() const { return visible_; }
    void resize(int width, int height);
    // Sizes the window to the page's reported size, in device-independent pixels. Only for windows with autosize set.
    void fitToPage(int width, int height);
    // Records the window's unscaled size from the screen, before the scale changes.
    void rememberSize();
    // Sizes the window to its unscaled size at the current scale.
    void applyScale();
    void move(int x, int y);
    void setTitle(const std::string& title);

    // What the page draws around its view: the title, whether there's a title bar, and whether the edges resize the window.
    Json chrome() const;
    // Shows or hides the page's title bar. The page is told straight away.
    void setTitleBar(bool shown);
    // Keeps the window off the taskbar, or puts it back. Applies straight away when the window is open.
    void setSkipTaskbar(bool skip);
    // Confines the window to its monitor's work area, or lets it go past the edges. Confining moves the window back in straight away.
    void setConfinedToWorkArea(bool confined);
    // Start moving or resizing the window, following the pointer's button press on the page.
    void beginMove();
    void beginResize(ResizeEdge edge);
    void minimize();
    void toggleMaximize();
    // Asks the window to close, as the window manager's close would: allowClose decides.
    void close();
    // Keeps the web view of a hidden window past its cooldown, until the window is shown or presented again.
    void keepWebView();

    // Sends an event to the page: window.hostReceive({event, data}).
    void emit(const std::string& event, const Json& data);
    void runScript(const std::string& script);

    // Opens the page's developer tools.
    void openDevTools();

    MessageHandler& handler() { return handler_; }

    // The page to show: the inline HTML, or the URL when devUrl is set.
    virtual std::string html() const { return {}; }
    virtual std::string devUrl() const { return {}; }
    virtual std::string title() const { return options_.title; }
    // The message shown when the page's process died and the page was loaded again.
    virtual std::string pageReloadedMessage() const { return "The page stopped unexpectedly, so it has been loaded again."; }

    // Called by the platform when the page posts a message, when the user asks to close the window, and after it closes.
    void receive(const std::string& text);
    // Called by the platform, on the window's thread, when the web view can't carry on. onWebViewFailure decides what happens.
    void notifyWebViewFailed(const std::string& message);
    bool requestClose();
    void notifyClosed();
    void notifyFocusLost();
    void notifyFrameChanged();

protected:
    // Return false to keep the window open. A window that returns false should hide itself to stay reusable.
    virtual bool allowClose() { return true; }
    virtual void onClosed() {}
    // Called when another window takes the focus from this one.
    virtual void onFocusLost() {}
    // Called when the window is moved or resized by the user, or by a call above.
    virtual void onFrameChanged() {}
    // Called when the page reports that it's ready. The window has been shown by then.
    virtual void onPageReady() {}
    bool pageReady() const { return pageReady_; }
    // Called when the web view fails: its page didn't report ready in time, its process failed, or the page reported an error.
    // The default shows the error and closes the window.
    virtual void onWebViewFailure(const std::string& message);

private:
    // Each platform implements these in platform/<os>/WebViewWindow.cpp.
    void platformOpen();
    void platformShow(bool visible);
    void platformPresent();
    void platformResize(int width, int height);
    void platformMove(int x, int y);
    std::optional<Rect> platformFrame() const;
    void platformSetTitle(const std::string& title);
    // Applies options_.skipTaskbar, which is already updated when it runs.
    void platformSetSkipTaskbar();
    // Applies whether the window is confined to the work area, which is already updated when it runs.
    void platformConfine(bool confined);
    // Destroys the native window and its web view. The window can be opened again after this.
    void platformUnload();
    void platformBeginMove();
    void platformBeginResize(ResizeEdge edge);
    void platformMinimize();
    void platformToggleMaximize();
    void platformClose();
    void platformRunScript(const std::string& script);
    // The page reported that it's ready: the window is shown, and host events can reach the page.
    void platformPageReady();
    void platformOpenDevTools();
    // Converts a size on the screen to the device-independent pixels resize takes, before the UI scale is removed.
    int platformToIndependent(int pixels) const;
    // Moves the window back inside its monitor's work area when it has gone past an edge.
    void keepOnScreen();
    // Starts the cooldown after which a hidden window frees its web view. A show or present cancels it.
    void startCooldown();
    void freeWebView();

    WindowOptions options_;
    // The window's size without the UI scale, which is what the page and the settings work in.
    int baseWidth_ = 0;
    int baseHeight_ = 0;
    bool visible_ = false;
    bool opened_ = false;
    // Counts the page loads, so a reply from an earlier page is dropped once the window has loaded another.
    std::uint64_t pageGeneration_ = 0;
    // Whether the current page has reported ready. Host events wait for it, in pendingEvents_.
    bool pageReady_ = false;
    std::vector<std::string> pendingEvents_;
    // Counts the hides and shows, so a cooldown started by an earlier hide does nothing once the window is shown again.
    std::uint64_t cooldownGeneration_ = 0;
    // Expires with the window, so a cooldown still waiting when the window is destroyed does nothing.
    std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
    MessageHandler handler_;
    std::unique_ptr<NativeWindow, NativeWindowDeleter> native_;
};

// Thrown when a runtime the windows need is missing. The user has already been shown why in a dialog, so the caller only stops.
class RuntimeMissingError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// What's missing for the windows to open: a message for the user, and a web page that gets it (empty when there's none).
// Nothing when it's all there. GTK 3, WebKitGTK 4.1 and a display on Linux; the WebView2 runtime on Windows.
struct RuntimeProblem {
    std::string message;
    std::string link;
};
std::optional<RuntimeProblem> missingWindowingRuntime();

// Asks the user in a dialog whether to open the page at link, and opens it when they say yes. Without a link, shows the message.
void offerLink(const std::string& message, const std::string& link);

// Shows what's missing in a dialog and throws RuntimeMissingError, when something is missing. Each window checks before it opens.
void requireWindowingRuntime();

// Starts the platform's windowing, so that windows and menus can be made. Throws RuntimeMissingError when a runtime is missing.
void initializeWindowing();

// The folder the executable runs from. Windows finds the WebView2 loader beside it.
std::filesystem::path executableFolder();

// Whether a transparent page shows the desktop behind the window. Where it doesn't, the page is told so and draws a solid background.
bool transparentBackgroundSupported();

// The platform's event loop. runEventLoop returns once stopEventLoop has been called.
void runEventLoop();
void stopEventLoop();

// The application's name, which the windows' own dialogs use as their title. Set it before a window opens. The default is "Application".
void setApplicationName(const std::string& name);
const std::string& applicationName();

// Sets the icon every window shows, from the PNG bytes the host embeds. Windows takes its icon from the executable's resource
// instead, so there it does nothing.
void setApplicationIcon(const std::string& png);

// The desktop's side of the library. The host application defines these for each platform it runs on: the library uses them, but
// they aren't part of the window.

// Shows an error in a dialog, and writes it to stderr. Used where nothing else would show the failure.
void showError(const std::string& message);
// Shows an error in a dialog and then stops the event loop. Can be called from any thread.
void reportFatalError(const std::string& message);
// Called with true before the library shows a modal dialog, and with false after it, so a watchdog can wait for the user.
void setDialogObserver(std::function<void(bool shown)> observer);

// Runs a task on the event loop's thread, from any thread.
void runOnUiThread(std::function<void()> task);

// The UI scale in percent. Window sizes are given unscaled: resize and the opened size multiply them by it.
void setUiScale(int percent);
int scaledSize(int size);
int unscaledSize(int size);

// The part of the screen the panels leave free, when the platform can give it.
std::optional<Rect> workArea();

// The work area of the monitor the rectangle is on, when the platform can tell which monitor that is. Missing otherwise, and
// windows are then left where they are.
std::optional<Rect> workAreaAt(const Rect& rect);

// The mouse position on screen, when the platform can give it.
std::optional<std::pair<int, int>> cursorPosition();

