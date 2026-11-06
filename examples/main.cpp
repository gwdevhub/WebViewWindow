// A window that the tests drive. The page reports "loaded" once it has loaded. Each line on stdin is a command:
//   hide, show, present: the window call of the same name, then the state is reported
//   report: the state is reported
//   confine <on|off>: the window is confined to its work area, or may go past its edges
//   move: a move starts, and follows the pointer until the button is released
//   resize <nw|n|ne|w|e|sw|s|se>: a resize from that edge starts, and follows the pointer until the button is released
//   quit: the event loop stops
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
    explicit ExampleWindow(std::chrono::milliseconds cooldown) : WebViewWindow(options(cooldown)) {
        handler().on("ready", [](WebViewWindow&, const Json&, const Reply& reply) {
            std::printf("loaded\n");
            std::fflush(stdout);
            reply.result(nullptr);
        });
    }

    std::string html() const override {
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head>"
               "<body style=\"margin:0;font-family:sans-serif;color:#fff;background:#234\">"
               "<script>window.webkit.messageHandlers.host.postMessage("
               "JSON.stringify({id: 1, method: 'ready', args: []}));</script>"
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
    static WindowOptions options(std::chrono::milliseconds cooldown) {
        WindowOptions options;
        options.cooldown = cooldown;
        options.title = "WebViewWindow Example";
        options.width = 320;
        options.height = 160;
        return options;
    }
};

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
    if (argc == 3 && std::string(argv[1]) == "--cooldown-ms") {
        cooldown = std::chrono::milliseconds(std::stol(argv[2]));
    }
    try {
        setApplicationName("WebViewWindow Example");
        initializeWindowing();
        ExampleWindow window(cooldown);
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
