// A window that the tests drive. The page reports "loaded" once it has loaded. Each line on stdin is a command:
//   hide, show, present: the window call of the same name, then the state is reported
//   report: the state is reported
//   quit: the event loop stops
// The state is one line, "visible=<0|1> open=<0|1>": whether the window is shown, and whether it has a native window.

#include <cstdio>
#include <exception>
#include <iostream>
#include <string>
#include <thread>

#include "WebViewWindow.h"

namespace {

class ExampleWindow : public WebViewWindow {
public:
    ExampleWindow() : WebViewWindow(options()) {
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
        std::printf("visible=%d open=%d\n", isVisible() ? 1 : 0, frame() ? 1 : 0);
        std::fflush(stdout);
    }

private:
    static WindowOptions options() {
        WindowOptions options;
        options.title = "WebViewWindow Example";
        options.width = 320;
        options.height = 160;
        return options;
    }
};

}  // namespace

int main() {
    try {
        setApplicationName("WebViewWindow Example");
        initializeWindowing();
        ExampleWindow window;
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
