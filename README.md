# WebViewWindow

A frameless desktop window whose page is HTML: a WebView2 window on Windows and a WebKitGTK window on Linux. The page draws
everything, including its own background. Where the platform can, the window itself is see-through, so the page can be a
transparent layer over the desktop.

The library is meant to be used as a submodule. The host application:

- calls `gwl::setApplicationName` and `gwl::initializeWindowing` at startup,
- subclasses `gwl::WebViewWindow`, overriding `html()` (or `devUrl()`) and `title()`,
- defines the desktop functions declared in `include/WebViewWindow.h` for each platform it runs on: `showError`,
  `cursorPosition`, `workArea` and `workAreaAt`. `example/Host.cpp` has the Windows versions.

## Layout

- `include/`: the public headers. `WebViewWindow.h` is the window; `Messages.h` is the page-to-host message dispatch.
- `src/`: the parts shared by both platforms.
- `platform/windows/`: the Win32 window, WebView2 callbacks, and DirectComposition for see-through windows.
- `platform/linux/`: the GTK and WebKitGTK window. GTK is loaded at runtime, so only the headers in `third_party/gtk` are needed.
- `third_party/`: WebView2 headers and loader, GTK headers, and nlohmann/json.

## Build

    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/mingw-w64.cmake
    cmake --build build

The Windows build uses MinGW-w64. The example is built with `WEBVIEW_WINDOW_BUILD_EXAMPLE` (on by default). Set it to OFF
when the library is used as a submodule. The WebView2 runtime must be installed on the machine that runs the program.

## Status

- Windows: built and run with the example.
- Linux: the code is in the tree, but it hasn't been built or run from this repository yet.
