// The smallest application on the library: one window with a page, which the host's desktop functions in Host.cpp support.

#include <exception>
#include <string>

#include "WebViewWindow.h"

namespace {

class HelloWindow : public WebViewWindow {
public:
    HelloWindow() : WebViewWindow(options()) {}

    std::string html() const override {
        // The page fills whatever it wants drawn: the window itself has no background of its own.
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head>"
               "<body style=\"margin:0;font-family:sans-serif;color:#fff;background:transparent\">"
               "<div style=\"height:100vh;box-sizing:border-box;padding:12px;background:rgba(0,0,0,0.4)\">"
               "Hello from WebViewWindow</div></body></html>";
    }

    std::string title() const override { return "Hello"; }

private:
    static WindowOptions options() {
        WindowOptions options;
        options.title = "Hello";
        options.width = 320;
        options.height = 160;
        return options;
    }
};

}  // namespace

int main() {
    try {
        setApplicationName("Hello");
        initializeWindowing();
        HelloWindow window;
        window.open();
        runEventLoop();
    } catch (const RuntimeMissingError&) {
        // The dialog has already said what's missing.
        return 1;
    } catch (const std::exception& error) {
        showError(error.what());
        return 1;
    }
    return 0;
}
