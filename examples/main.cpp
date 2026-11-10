// A window that the tests drive. The page reports "loaded" once it has loaded. Each line on stdin is a command:
//   hide, show, present: the window call of the same name, then the state is reported
//   report: the state is reported
//   confine <on|off>: the window is confined to its work area, or may go past its edges
//   move: a move starts, and follows the pointer until the button is released
//   resize <nw|n|ne|w|e|sw|s|se>: a resize from that edge starts, and follows the pointer until the button is released
//   download: the page clicks its first link with a download attribute, and the file is saved to the download folder
//   probe: the page asks for the microphone and for notifications, and the result is reported as "probe {json}": the
//          notification permission before the request, the microphone request's result, and the notification request's result
//   minimize: the window is minimised, then the state is reported
//   maximize: the window is maximised, or restored when it already is, then the state is reported
//   skip <on|off>: the window is kept off the taskbar, or put back on it, then the state is reported
//   titlebar <on|off>: the page's title bar is shown or hidden, then the state is reported
//   fit <width> <height>: an autosize window is sized to the page's reported size, then the state is reported
//   scale <percent>: the UI scale is changed, then the state is reported
//   tray: the application icon is shown in the system tray, reported as "tray shown=<0|1>". A click prints "tray activate", and
//         the menu's Ping item prints "tray ping"
//   untray: the tray icon is removed, reported as "tray removed"
//   frontenderror: the page reports an error, which the window's failure hook reports as "failure <message>"
//   devtools: the page's developer tools are opened, reported as "devtools opened"
//   describe: each of the example's native windows is described (macOS only): "native class=... level=... behavior=... excluded=..."
//   quit: the event loop stops
// Options:
//   --cooldown-ms N           how long a hidden window keeps its web view
//   --allow-permissions       the host allows the microphone, camera and notification requests (otherwise the platform's default)
//   --url <address>           a page to show instead of the built-in one. A page at --url must report ready itself.
//   --data-folder <path>      the folder WebView2 keeps its profile in
//   --download-folder <path>  where downloads are saved
//   --icon <png file>         the application icon, which the tray icon needs
//   --always-on-top, --keep-below, --sticky, --skip-taskbar, --utility: the window options of the same names
//   --opaque                  the window isn't see-through
//   --clear-page              the built-in page's background is see-through, so the desktop shows through a transparent window
//   --no-titlebar             the page starts without its title bar; --not-resizable: the page's edges don't resize the window
//   --resize-edges            the library draws resize strips along the window's edges
//   --autosize                the page sizes the window; --invisible: the window isn't shown when its page is ready
//   --min-size <w> <h>        the smallest size the user can resize the window to
//   --startup-timeout <s>     seconds the page has to report ready before the window fails (0 for no limit)
//   --no-ready                the built-in page never reports ready, so the window fails at the startup timeout
// The state is one line: "visible=<0|1> open=<0|1> frame=<x>,<y>,<width>,<height> area=<x>,<y>,<width>,<height>". The frame is the
// window's rectangle on the screen in pixels, or "frame=none" when it has no native window. The area is the work area of the
// monitor the window is on, or "area=none".

#include <chrono>
#include <cstdio>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "WebViewWindow.h"

// The native windows' settings, as the host describes them. Only macOS has any to describe.
std::string describeHostWindows();

namespace {

// Everything the command line sets, so the window and the commands can read it.
struct Settings {
    std::chrono::milliseconds cooldown = std::chrono::minutes(2);
    bool allowPermissions = false;
    std::string url;
    std::filesystem::path dataFolder;
    std::filesystem::path downloadFolder;
    std::filesystem::path iconPath;
    bool alwaysOnTop = false;
    bool keepBelow = false;
    bool sticky = false;
    bool skipTaskbar = false;
    bool utility = false;
    bool opaque = false;
    bool clearPage = false;
    bool noTitleBar = false;
    bool notResizable = false;
    bool resizeEdges = false;
    bool autosize = false;
    bool invisible = false;
    bool noReady = false;
    int minWidth = 0;
    int minHeight = 0;
    std::chrono::seconds startupTimeout = std::chrono::seconds(30);
};

// Prints a line of output for the tests to read, and flushes it so it's read at once.
void printLine(const std::string& line) {
    std::printf("%s\n", line.c_str());
    std::fflush(stdout);
}

class ExampleWindow : public WebViewWindow {
public:
    explicit ExampleWindow(const Settings& settings) : WebViewWindow(options(settings)), settings_(settings) {
        handler().on("probe", [](WebViewWindow&, const Json& args, const Reply& reply) {
            printLine("probe " + args.at(0).get<std::string>());
            reply.result(nullptr);
        });
    }

    // The page to show instead of the built-in one, when the host was started with --url.
    std::string devUrl() const override { return settings_.url; }

    // The page's permission requests are allowed only when the host was started with --allow-permissions. Each request is reported
    // as "permission <kind> <allowed|default>", so a test can see what the platform asked.
    std::optional<bool> onPermissionRequest(PagePermission permission, const std::string&) override {
        const char* kind = "other";
        switch (permission) {
            case PagePermission::Microphone: kind = "microphone"; break;
            case PagePermission::Camera: kind = "camera"; break;
            case PagePermission::Notifications: kind = "notifications"; break;
            case PagePermission::Other: break;
        }
        if (settings_.allowPermissions && permission != PagePermission::Other) {
            printLine(std::string("permission ") + kind + " allowed");
            return true;
        }
        printLine(std::string("permission ") + kind + " default");
        return std::nullopt;
    }

    void onPageReady() override { printLine("loaded"); }

    // The failure hook. The library's default shows a dialog; the example reports the failure and closes the window instead, so a
    // test can see it without a dialog waiting for someone to answer.
    void onWebViewFailure(const std::string& message) override {
        printLine("failure " + message);
        close();
    }

    std::string html() const override {
        const std::string background = settings_.clearPage ? "transparent" : "#234";
        const std::string ready = settings_.noReady ? "" :
            "(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)"
            ".postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));";
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head>"
               "<body style=\"margin:0;font-family:sans-serif;color:#fff;background:" + background + "\">"
               "<script>" + ready + "</script>"
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
    Settings settings_;

    static WindowOptions options(const Settings& settings) {
        WindowOptions options;
        options.cooldown = settings.cooldown;
        options.webViewDataFolder = settings.dataFolder;
        options.title = "WebViewWindow Example";
        options.width = 320;
        options.height = 160;
        options.alwaysOnTop = settings.alwaysOnTop;
        options.keepBelow = settings.keepBelow;
        options.sticky = settings.sticky;
        options.skipTaskbar = settings.skipTaskbar;
        options.utility = settings.utility;
        options.transparent = !settings.opaque;
        options.titleBar = !settings.noTitleBar;
        options.resizable = !settings.notResizable;
        options.resizeEdges = settings.resizeEdges;
        options.autosize = settings.autosize;
        options.visible = !settings.invisible;
        options.minWidth = settings.minWidth;
        options.minHeight = settings.minHeight;
        options.startupTimeout = settings.startupTimeout;
        return options;
    }
};

// Clicks the page's first link that has a download attribute. The click starts the download, which the chooser places.
const char* const kDownloadScript = R"JS(
(() => {
  const link = document.querySelector('a[download]');
  if (link) link.click();
})();
)JS";

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
  // WKWebView on macOS has no Notification object, so the request is reported as unsupported there.
  result.notification = typeof Notification === 'undefined' ? 'unsupported' : await within(Notification.requestPermission());
  (window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
    .postMessage(JSON.stringify({id: Date.now(), method: 'probe', args: [JSON.stringify(result)]}));
})();
)JS";

// The page reports an error the way a page does, which makes the window fail.
const char* const kFrontendErrorScript = R"JS(
(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
  .postMessage(JSON.stringify({id: 2, method: 'frontendError', args: ['the page reported an error']}));
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

// Reads a file's bytes, or nothing when it can't be read.
std::optional<std::string> readFile(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return std::nullopt;
    }
    return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

// Parses the options. Returns false when one is unknown or is missing its value.
bool parseSettings(int argc, char** argv, Settings& settings) {
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        const bool hasValue = i + 1 < argc;
        if (arg == "--cooldown-ms" && hasValue) {
            settings.cooldown = std::chrono::milliseconds(std::stol(argv[++i]));
        } else if (arg == "--allow-permissions") {
            settings.allowPermissions = true;
        } else if (arg == "--url" && hasValue) {
            settings.url = argv[++i];
        } else if (arg == "--data-folder" && hasValue) {
            settings.dataFolder = argv[++i];
        } else if (arg == "--download-folder" && hasValue) {
            settings.downloadFolder = argv[++i];
        } else if (arg == "--icon" && hasValue) {
            settings.iconPath = argv[++i];
        } else if (arg == "--always-on-top") {
            settings.alwaysOnTop = true;
        } else if (arg == "--keep-below") {
            settings.keepBelow = true;
        } else if (arg == "--sticky") {
            settings.sticky = true;
        } else if (arg == "--skip-taskbar") {
            settings.skipTaskbar = true;
        } else if (arg == "--utility") {
            settings.utility = true;
        } else if (arg == "--opaque") {
            settings.opaque = true;
        } else if (arg == "--clear-page") {
            settings.clearPage = true;
        } else if (arg == "--no-titlebar") {
            settings.noTitleBar = true;
        } else if (arg == "--not-resizable") {
            settings.notResizable = true;
        } else if (arg == "--resize-edges") {
            settings.resizeEdges = true;
        } else if (arg == "--autosize") {
            settings.autosize = true;
        } else if (arg == "--invisible") {
            settings.invisible = true;
        } else if (arg == "--no-ready") {
            settings.noReady = true;
        } else if (arg == "--min-size" && i + 2 < argc) {
            settings.minWidth = std::stoi(argv[++i]);
            settings.minHeight = std::stoi(argv[++i]);
        } else if (arg == "--startup-timeout" && hasValue) {
            settings.startupTimeout = std::chrono::seconds(std::stol(argv[++i]));
        } else {
            return false;
        }
    }
    return true;
}

// Runs one command from stdin on the event loop's thread. Returns false when the command is quit.
bool runCommand(ExampleWindow& window, const std::string& line) {
    std::istringstream words(line);
    std::string command;
    std::string argument;
    words >> command >> argument;
    if (command == "hide") {
        runOnUiThread([&window] { window.hide(); window.report(); });
    } else if (command == "show") {
        runOnUiThread([&window] { window.show(); window.report(); });
    } else if (command == "present") {
        runOnUiThread([&window] { window.present(); window.report(); });
    } else if (command == "report") {
        runOnUiThread([&window] { window.report(); });
    } else if (command == "confine") {
        const bool confined = argument == "on";
        runOnUiThread([&window, confined] { window.setConfinedToWorkArea(confined); window.report(); });
    } else if (command == "move") {
        runOnUiThread([&window] { window.beginMove(); });
    } else if (command == "resize") {
        if (const auto edge = edgeNamed(argument)) {
            runOnUiThread([&window, edge] { window.beginResize(*edge); });
        }
    } else if (command == "download") {
        runOnUiThread([&window] { window.runScript(kDownloadScript); });
    } else if (command == "probe") {
        runOnUiThread([&window] { window.runScript(kProbeScript); });
    } else if (command == "minimize") {
        runOnUiThread([&window] { window.minimize(); window.report(); });
    } else if (command == "maximize") {
        runOnUiThread([&window] { window.toggleMaximize(); window.report(); });
    } else if (command == "skip") {
        const bool skip = argument == "on";
        runOnUiThread([&window, skip] { window.setSkipTaskbar(skip); window.report(); });
    } else if (command == "titlebar") {
        const bool shown = argument == "on";
        runOnUiThread([&window, shown] { window.setTitleBar(shown); window.report(); });
    } else if (command == "fit") {
        std::istringstream sizes(line.substr(command.size()));
        int width = 0;
        int height = 0;
        sizes >> width >> height;
        runOnUiThread([&window, width, height] { window.fitToPage(width, height); window.report(); });
    } else if (command == "scale") {
        const int percent = std::stoi(argument);
        runOnUiThread([&window, percent] { setUiScale(percent); window.report(); });
    } else if (command == "tray") {
        runOnUiThread([] {
            const bool shown = showTrayIcon("WebViewWindow Example", [] { printLine("tray activate"); },
                                            {TrayMenuItem{"Ping", [] { printLine("tray ping"); }}});
            printLine(std::string("tray shown=") + (shown ? "1" : "0"));
        });
    } else if (command == "untray") {
        runOnUiThread([] {
            removeTrayIcon();
            printLine("tray removed");
        });
    } else if (command == "frontenderror") {
        runOnUiThread([&window] { window.runScript(kFrontendErrorScript); });
    } else if (command == "devtools") {
        runOnUiThread([&window] {
            window.openDevTools();
            printLine("devtools opened");
        });
    } else if (command == "describe") {
        runOnUiThread([] {
            const std::string text = describeHostWindows();
            std::printf("%s", text.c_str());
            std::printf("describe done\n");
            std::fflush(stdout);
        });
    } else if (command == "quit") {
        runOnUiThread([] { stopEventLoop(); });
        return false;
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    Settings settings;
    if (!parseSettings(argc, argv, settings)) {
        std::fprintf(stderr, "Unknown or incomplete option. See the top of examples/main.cpp.\n");
        return 2;
    }
    try {
        setApplicationName("WebViewWindow Example");
        if (!settings.downloadFolder.empty()) {
            setDownloadChooser([folder = settings.downloadFolder](const std::string& name) -> std::optional<std::filesystem::path> {
                return folder / name;
            });
        }
        initializeWindowing();
        if (!settings.iconPath.empty()) {
            if (const auto png = readFile(settings.iconPath)) {
                setApplicationIcon(*png);
            }
        }
        ExampleWindow window(settings);
        window.open();

        std::thread reader([&window] {
            std::string line;
            while (std::getline(std::cin, line)) {
                if (!runCommand(window, line)) {
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
