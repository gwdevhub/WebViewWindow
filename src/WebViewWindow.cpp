#include "WebViewWindow.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <set>
#include <thread>
#include <utility>


namespace {

int uiScale = 100;

// The edge a strip names, as the script posts it, or nothing when the name isn't one.
std::optional<ResizeEdge> resizeEdgeNamed(const std::string& name) {
    if (name == "n") return ResizeEdge::North;
    if (name == "ne") return ResizeEdge::NorthEast;
    if (name == "e") return ResizeEdge::East;
    if (name == "se") return ResizeEdge::SouthEast;
    if (name == "s") return ResizeEdge::South;
    if (name == "sw") return ResizeEdge::SouthWest;
    if (name == "w") return ResizeEdge::West;
    if (name == "nw") return ResizeEdge::NorthWest;
    return std::nullopt;
}

// Puts a strip along each edge of the page. Each one posts beginResize with its edge, through the channel the platform gives the
// page. Where there's no channel, it does nothing.
const char* resizeEdgesScript() {
    return R"JS((() => {
  if (document.getElementById('webview-window-edges')) return;
  const channel = window.chrome && window.chrome.webview ? window.chrome.webview
    : window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.host ? window.webkit.messageHandlers.host
    : null;
  if (!channel) return;
  const edges = [
    ['nw', 'nw-resize', 'top: 0; left: 0; width: 8px; height: 8px'],
    ['n', 'n-resize', 'top: 0; left: 8px; right: 8px; height: 5px'],
    ['ne', 'ne-resize', 'top: 0; right: 0; width: 8px; height: 8px'],
    ['w', 'w-resize', 'top: 8px; bottom: 8px; left: 0; width: 5px'],
    ['e', 'e-resize', 'top: 8px; bottom: 8px; right: 0; width: 5px'],
    ['sw', 'sw-resize', 'bottom: 0; left: 0; width: 8px; height: 8px'],
    ['s', 's-resize', 'bottom: 0; left: 8px; right: 8px; height: 5px'],
    ['se', 'se-resize', 'bottom: 0; right: 0; width: 8px; height: 8px'],
  ];
  const holder = document.createElement('div');
  holder.id = 'webview-window-edges';
  for (const [name, cursor, place] of edges) {
    const strip = document.createElement('div');
    strip.setAttribute('style', `position: fixed; z-index: 2147483647; cursor: ${cursor}; ${place}`);
    strip.addEventListener('mousedown', (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      channel.postMessage(JSON.stringify({ id: 0, method: 'beginResize', args: [name] }));
    });
    holder.appendChild(strip);
  }
  document.body.appendChild(holder);
})();)JS";
}

// The rectangle moved the least it takes to lie inside area. One larger than the area sits at the area's top left.
ScreenRect keptWithin(ScreenRect rect, const ScreenRect& area) {
    rect.x = std::max(area.x, std::min(rect.x, area.right() - rect.width));
    rect.y = std::max(area.y, std::min(rect.y, area.bottom() - rect.height));
    return rect;
}

// The windows that are open, so a change of scale reaches each of them.
std::set<WebViewWindow*>& liveWindows() {
    static std::set<WebViewWindow*> windows;
    return windows;
}

std::function<void(bool)>& dialogObserver() {
    static std::function<void(bool)> observer;
    return observer;
}

void announceDialog(bool shown) {
    if (dialogObserver()) {
        dialogObserver()(shown);
    }
}

}  // namespace

void setDialogObserver(std::function<void(bool shown)> observer) {
    dialogObserver() = std::move(observer);
}

void reportFatalError(const std::string& message) {
    runOnUiThread([message] {
        showError(message);
        stopEventLoop();
    });
}

WebViewWindow::WebViewWindow(WindowOptions options)
    : options_(std::move(options)), baseWidth_(options_.width), baseHeight_(options_.height) {
    liveWindows().insert(this);
    // The strips that resizeEdges draws post here. A request from a window without them is ignored.
    handler_.on("beginResize", [](WebViewWindow& window, const Json& args, const Reply&) {
        if (!window.options_.resizeEdges || args.size() != 1 || !args[0].is_string()) {
            return;
        }
        if (const auto edge = resizeEdgeNamed(args[0].get<std::string>())) {
            window.beginResize(*edge);
        }
    });
}

WebViewWindow::~WebViewWindow() {
    liveWindows().erase(this);
}

void requireWindowingRuntime() {
    if (const auto problem = missingWindowingRuntime()) {
        announceDialog(true);
        if (problem->link.empty()) {
            showError(problem->message);
        } else {
            offerLink(problem->message, problem->link);
        }
        announceDialog(false);
        throw RuntimeMissingError(problem->message);
    }
}

void WebViewWindow::onWebViewFailure(const std::string& message) {
    showError(message);
    close();
}

void WebViewWindow::open() {
    // Opening a window that already exists brings it to the front, so every opener restores a minimised window the same way.
    if (opened_) {
        present();
        return;
    }
    requireWindowingRuntime();
    visible_ = options_.visible;
    ++pageGeneration_;
    pageReady_ = false;
    pendingEvents_.clear();
    platformOpen();
    opened_ = true;
    keepOnScreen();
    if (!options_.visible) {
        startCooldown();
    }
}

void WebViewWindow::show() {
    ++cooldownGeneration_;
    if (!opened_) {
        options_.visible = true;
        open();
    }
    visible_ = true;
    platformShow(true);
}

void WebViewWindow::present() {
    ++cooldownGeneration_;
    if (!opened_) {
        options_.visible = true;
        open();
    }
    visible_ = true;
    platformPresent();
}

void WebViewWindow::hide() {
    visible_ = false;
    platformShow(false);
    startCooldown();
}

void WebViewWindow::startCooldown() {
    const std::uint64_t generation = ++cooldownGeneration_;
    const auto cooldown = options_.cooldown;
    // The thread only waits. Its task runs on the window's thread, and only if the window still exists and nothing has changed.
    std::thread([this, alive = std::weak_ptr<bool>(alive_), generation, cooldown] {
        std::this_thread::sleep_for(cooldown);
        runOnUiThread([this, alive, generation] {
            if (!alive.expired() && generation == cooldownGeneration_ && !visible_) {
                freeWebView();
            }
        });
    }).detach();
}

void WebViewWindow::freeWebView() {
    ++pageGeneration_;
    pageReady_ = false;
    pendingEvents_.clear();
    opened_ = false;
    platformUnload();
}

void WebViewWindow::reload() {
    ++cooldownGeneration_;
    freeWebView();
    options_.visible = true;
    open();
    present();
}

void WebViewWindow::keepWebView() {
    ++cooldownGeneration_;
}

void WebViewWindow::resize(int width, int height) {
    baseWidth_ = width;
    baseHeight_ = height;
    platformResize(scaledSize(width), scaledSize(height));
    keepOnScreen();
}

std::optional<std::pair<int, int>> WebViewWindow::frameUnscaled() const {
    const auto frame = platformFrame();
    if (!frame) {
        return std::nullopt;
    }
    return std::make_pair(unscaledSize(platformToIndependent(frame->width)), unscaledSize(platformToIndependent(frame->height)));
}

void WebViewWindow::rememberSize() {
    if (!opened_ || options_.autosize) {
        return;
    }
    if (const auto size = frameUnscaled()) {
        baseWidth_ = size->first;
        baseHeight_ = size->second;
    }
}

void WebViewWindow::applyScale() {
    if (!opened_ || options_.autosize) {
        return;
    }
    platformResize(scaledSize(baseWidth_), scaledSize(baseHeight_));
    keepOnScreen();
}

void WebViewWindow::fitToPage(int width, int height) {
    if (options_.autosize) {
        platformResize(width, height);
        keepOnScreen();
    }
}

std::optional<ScreenRect> WebViewWindow::frame() const {
    return platformFrame();
}

void WebViewWindow::move(int x, int y) {
    const auto current = platformFrame();
    if (!current) {
        platformMove(x, y);
        return;
    }
    const ScreenRect target{x, y, current->width, current->height};
    const auto area = workAreaAt(target);
    const ScreenRect kept = area ? keptWithin(target, *area) : target;
    platformMove(kept.x, kept.y);
}

void WebViewWindow::setConfinedToWorkArea(bool confined) {
    options_.confinedToWorkArea = confined;
    platformConfine(confined);
    keepOnScreen();
}

void WebViewWindow::keepOnScreen() {
    if (!options_.confinedToWorkArea) {
        return;
    }
    const auto current = platformFrame();
    if (!current) {
        return;
    }
    const auto area = workAreaAt(*current);
    if (!area) {
        return;
    }
    const ScreenRect kept = keptWithin(*current, *area);
    if (kept.x != current->x || kept.y != current->y) {
        platformMove(kept.x, kept.y);
    }
}

Json WebViewWindow::chrome() const {
    return {
        {"title", title()},
        {"titleBar", options_.titleBar},
        {"resizable", options_.resizable && !options_.autosize},
    };
}

void WebViewWindow::setTitleBar(bool shown) {
    options_.titleBar = shown;
    emit("chrome", chrome());
}

void WebViewWindow::setSkipTaskbar(bool skip) {
    options_.skipTaskbar = skip;
    platformSetSkipTaskbar();
}

void WebViewWindow::beginMove() {
    platformBeginMove();
}

void WebViewWindow::beginResize(ResizeEdge edge) {
    platformBeginResize(edge);
}

void WebViewWindow::minimize() {
    platformMinimize();
}

void WebViewWindow::toggleMaximize() {
    platformToggleMaximize();
}

void WebViewWindow::close() {
    platformClose();
}

void WebViewWindow::setTitle(const std::string& title) {
    options_.title = title;
    platformSetTitle(title);
    emit("chrome", chrome());
}

void WebViewWindow::emit(const std::string& event, const Json& data) {
    const std::string script = "window.hostReceive(" + Json{{"event", event}, {"data", data}}.dump() + ")";
    // The page subscribes to events as it starts, so events wait until it reports ready.
    if (pageReady_) {
        platformRunScript(script);
    } else {
        pendingEvents_.push_back(script);
    }
}

void WebViewWindow::openDevTools() {
    platformOpenDevTools();
}

void WebViewWindow::runScript(const std::string& script) {
    platformRunScript(script);
}

void WebViewWindow::receive(const std::string& text) {
    Request request;
    std::string error;
    if (!Request::parse(text, request, error)) {
        // A message with no id has nothing to answer, so the reason goes to stderr.
        std::fprintf(stderr, "Ignored a page message: %s\n", error.c_str());
        return;
    }
    const std::uint64_t id = request.id;
    const auto generation = pageGeneration_;
    const auto alive = std::weak_ptr<bool>(alive_);
    Reply reply{
        [this, id, alive, generation](const Json& result) {
            if (!alive.expired() && generation == pageGeneration_) runScript(replyScript(id, result));
        },
        [this, id, alive, generation](const std::string& message) {
            if (!alive.expired() && generation == pageGeneration_) runScript(errorScript(id, message));
        },
    };
    if (request.method == "ready") {
        reply.result(nullptr);
        pageReady_ = true;
        platformPageReady();
        const auto events = std::move(pendingEvents_);
        pendingEvents_.clear();
        for (const std::string& script : events) {
            platformRunScript(script);
        }
        onPageReady();
        return;
    }
    if (request.method == "frontendError") {
        reply.result(nullptr);
        notifyWebViewFailed(request.args.empty() ? "The page reported an error." : request.args.at(0).get<std::string>());
        return;
    }
    handler_.dispatch(*this, request, reply);
}

void WebViewWindow::notifyWebViewFailed(const std::string& message) {
    onWebViewFailure(message);
}

bool WebViewWindow::requestClose() {
    return allowClose();
}

void WebViewWindow::notifyClosed() {
    onClosed();
}

void WebViewWindow::notifyFocusLost() {
    onFocusLost();
}

void WebViewWindow::notifyFrameChanged() {
    onFrameChanged();
}

namespace {

DownloadChooser& downloadChooser() {
    static DownloadChooser chooser;
    return chooser;
}

}  // namespace

void setDownloadChooser(DownloadChooser chooser) {
    downloadChooser() = std::move(chooser);
}

std::optional<std::filesystem::path> chooseDownloadPath(const std::string& suggestedName) {
    const DownloadChooser& chooser = downloadChooser();
    if (!chooser) {
        return std::nullopt;
    }
    return chooser(suggestedName);
}

std::optional<bool> WebViewWindow::decidePermission(PagePermission permission, const std::string& pageUrl) {
    return onPermissionRequest(permission, pageUrl);
}

void WebViewWindow::notifyPageLoaded() {
    if (options_.resizeEdges && options_.resizable && !options_.autosize) {
        platformRunScript(resizeEdgesScript());
    }
    onPageLoaded();
}

void setUiScale(int percent) {
    if (percent < 50 || percent > 200 || percent == uiScale) {
        return;
    }
    for (WebViewWindow* window : liveWindows()) {
        window->rememberSize();
    }
    uiScale = percent;
    for (WebViewWindow* window : liveWindows()) {
        window->applyScale();
        window->emit("uiScale", percent);
    }
}

int scaledSize(int size) {
    return (size * uiScale + 50) / 100;
}

int unscaledSize(int size) {
    return (size * 100 + uiScale / 2) / uiScale;
}

namespace {

std::string& applicationNameStorage() {
    static std::string name = "Application";
    return name;
}

}  // namespace

void setApplicationName(const std::string& name) {
    applicationNameStorage() = name;
}

const std::string& applicationName() {
    return applicationNameStorage();
}

