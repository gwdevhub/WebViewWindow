// A window that the tests drive. The page reports "loaded" once it has loaded. Each line on stdin is a command:
//   hide, show, present: the window call of the same name, then the state is reported
//   report: the state is reported
//   confine <on|off>: the window is confined to its work area, or may go past its edges
//   move: a move starts, and follows the pointer until the button is released
//   resize <nw|n|ne|w|e|sw|s|se>: a resize from that edge starts, and follows the pointer until the button is released
//   probe: the page asks for the microphone and for notifications, and the result is reported as "probe {json}": the
//          notification permission before the request, the microphone request's result, and the notification request's result
//   quit: the event loop stops
// Options: --cooldown-ms N, --allow-permissions, and --url <address> to show a page other than the built-in one. A page at --url
// must report ready itself, as the built-in page does.
// With --allow-permissions, the host allows the microphone, camera and notification requests. Without it, they're left to the
// platform's default.
// The state is one line: "visible=<0|1> open=<0|1> frame=<x>,<y>,<width>,<height> area=<x>,<y>,<width>,<height>". The frame is the
// window's rectangle on the screen in pixels, or "frame=none" when it has no native window. The area is the work area of the
// monitor the window is on, or "area=none".

#include <chrono>
#include <cstdio>
#include <exception>
#include <iostream>
#include <optional>
#include <string>
#include <thread>

#include "WebViewWindow.h"

namespace {

class ExampleWindow : public WebViewWindow {
public:
    ExampleWindow(std::chrono::milliseconds cooldown, bool allowPermissions, std::string url)
        : WebViewWindow(options(cooldown)), allowPermissions_(allowPermissions), url_(std::move(url)) {
        handler().on("probe", [](WebViewWindow&, const Json& args, const Reply& reply) {
            std::printf("probe %s\n", args.at(0).get<std::string>().c_str());
            std::fflush(stdout);
            reply.result(nullptr);
        });
    }

    // The page to show instead of the built-in one, when the host was started with --url.
    std::string devUrl() const override { return url_; }

    // The page's permission requests are allowed only when the host was started with --allow-permissions.
    std::optional<bool> onPermissionRequest(PagePermission, const std::string&) override {
        if (allowPermissions_) {
            return true;
        }
        return std::nullopt;
    }

    void onPageReady() override {
        std::printf("loaded\n");
        std::fflush(stdout);
    }

    std::string html() const override {
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head>"
               "<body style=\"margin:0;font-family:sans-serif;color:#fff;background:#234\">"
               "<script>(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)"
               ".postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));</script>"
               "Example window</body></html>";
    }

    std::string title() const override { return "WebViewWindow Example"; }

    void report() const {
        const auto bounds = frame();
        std::printf("visible=%d open=%d ", isVisible() ? 1 : 0, bounds ? 1 : 0);
        if (bounds) {
            std::printf("frame=%d,%d,%d,%d ", bounds->x, bounds->y, bounds->width, bounds->height);
        } else {
            std::printf("frame=none ");
        }
        const auto area = bounds ? workAreaAt(*bounds) : std::nullopt;
        if (area) {
            std::printf("area=%d,%d,%d,%d\n", area->x, area->y, area->width, area->height);
        } else {
            std::printf("area=none\n");
        }
        std::fflush(stdout);
    }

private:
    bool allowPermissions_;
    std::string url_;

    static WindowOptions options(std::chrono::milliseconds cooldown) {
        WindowOptions options;
        options.cooldown = cooldown;
        options.title = "WebViewWindow Example";
        options.width = 320;
        options.height = 160;
        return options;
    }
};

// Reports the notification permission the page starts with, then asks for the microphone and for notifications. Each answer is the
// error's name, "granted" or "denied", or "pending" when nobody answered in five seconds.
const char* const kProbeScript = R"JS(
(async () => {
  // A request that nobody answers stays open (WebView2 shows its prompt), so it's reported as pending after a few seconds.
  const within = (promise) => Promise.race([
    promise.then((value) => value, (e) => (e && e.name ? e.name : String(e))),
    new Promise((resolve) => setTimeout(() => resolve('pending'), 5000)),
  ]);
  const result = {notificationBefore: typeof Notification === 'undefined' ? 'none' : Notification.permission};
  result.microphone = await within(navigator.mediaDevices.getUserMedia({audio: true}).then(() => 'granted'));
  result.notification = await within(Notification.requestPermission());
  (window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
    .postMessage(JSON.stringify({id: Date.now(), method: 'probe', args: [JSON.stringify(result)]}));
})();
)JS";

// The edge a "resize" command names, as the library's ResizeEdge.
std::optional<ResizeEdge> edgeNamed(const std::string& name) {
    if (name == "nw") return ResizeEdge::NorthWest;
    if (name == "n") return ResizeEdge::North;
    if (name == "ne") return ResizeEdge::NorthEast;
    if (name == "w") return ResizeEdge::West;
    if (name == "e") return ResizeEdge::East;
    if (name == "sw") return ResizeEdge::SouthWest;
    if (name == "s") return ResizeEdge::South;
    if (name == "se") return ResizeEdge::SouthEast;
    return std::nullopt;
}

}  // namespace

int main(int argc, char** argv) {
    // --cooldown-ms N sets how long a hidden window keeps its web view. The default is the library's.
    std::chrono::milliseconds cooldown = std::chrono::minutes(2);
    bool allowPermissions = false;
    std::string url;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--cooldown-ms" && i + 1 < argc) {
            cooldown = std::chrono::milliseconds(std::stol(argv[++i]));
        } else if (arg == "--allow-permissions") {
            allowPermissions = true;
        } else if (arg == "--url" && i + 1 < argc) {
            url = argv[++i];
        }
    }
    try {
        setApplicationName("WebViewWindow Example");
        initializeWindowing();
        ExampleWindow window(cooldown, allowPermissions, url);
        window.open();

        std::thread reader([&window] {
            std::string line;
            while (std::getline(std::cin, line)) {
                if (line == "hide") {
                    runOnUiThread([&window] { window.hide(); window.report(); });
                } else if (line == "show") {
                    runOnUiThread([&window] { window.show(); window.report(); });
                } else if (line == "present") {
                    runOnUiThread([&window] { window.present(); window.report(); });
                } else if (line == "report") {
                    runOnUiThread([&window] { window.report(); });
                } else if (line == "confine on" || line == "confine off") {
                    const bool confined = line == "confine on";
                    runOnUiThread([&window, confined] { window.setConfinedToWorkArea(confined); window.report(); });
                } else if (line == "move") {
                    runOnUiThread([&window] { window.beginMove(); });
                } else if (line.rfind("resize ", 0) == 0) {
                    if (const auto edge = edgeNamed(line.substr(7))) {
                        runOnUiThread([&window, edge] { window.beginResize(*edge); });
                    }
                } else if (line == "probe") {
                    runOnUiThread([&window] { window.runScript(kProbeScript); });
                } else if (line == "quit") {
                    runOnUiThread([] { stopEventLoop(); });
                    break;
                }
            }
        });
        runEventLoop();
        reader.join();
    } catch (const RuntimeMissingError&) {
        // The dialog has already said what's missing.
        return 1;
    } catch (const std::exception& error) {
        showError(error.what());
        return 1;
    }
    return 0;
}
