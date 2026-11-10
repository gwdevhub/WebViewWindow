# WebViewWindow

A frameless desktop window whose page is HTML: a WebView2 window on Windows and a WebKitGTK window on Linux. The page draws
everything, including its own background. Where the platform can, the window itself is see-through, so the page can be a
transparent layer over the desktop.

The library is meant to be used as a submodule. The host application:

- calls `setApplicationName` and `initializeWindowing` at startup, and `setApplicationIcon` if it has a PNG icon to show,
- subclasses `WebViewWindow`, overriding `html()` (or `devUrl()`) and `title()`,
- defines `showError` for each platform it runs on, the one desktop function the library leaves to the host. The
  `examples/Host.*` files have the Windows, Linux and macOS versions.

## Lifecycle

- A window is hidden until its page reports that it's ready, so it never shows as an empty frame. A `show` or `present` that
  comes before then takes effect once the page is ready. The page reports it by posting `{id, method: 'ready', args: []}` to the
  host, once it has subscribed to the events it needs. Until then, host events wait for it.
- Events queue until the page is ready, and replies from a page that has since been reloaded are dropped.
- On Windows, if the page doesn't report ready within `WindowOptions::startupTimeout` (30 seconds by default), or the web view
  fails, the window calls `onWebViewFailure`. Linux has no startup timeout yet. The default shows the error and closes the window. A page can report its own failure by
  posting `{id, method: 'frontendError', args: [message]}`. `reload()` recreates the web view and loads the page again.
- `WindowOptions::webViewDataFolder` sets where WebView2 keeps its profile. Empty means a folder beside the executable.
- `hide` frees the window's web view after two minutes, unless the window is shown again first. The next `show` or `present`
  opens the window again.
- When the user closes a window, `allowClose` decides. If it returns true, the window is destroyed. A window that should stay
  reusable returns false and hides itself, as it would through `hide`.
- `WindowOptions::resizeEdges` draws strips along the window's edges, after each page load, and a press on one starts a resize
  from that edge. The page doesn't need to draw them. It applies when `resizable` is set and the window isn't autosize.

## Permissions

- When a page asks for the microphone, camera or notifications, the host's `onPermissionRequest` answers. Return true to allow,
  false to deny, or nothing to leave the platform's default: WebKitGTK denies the request, and WebView2 asks the user. The
  answer comes from `decidePermission`, which the platform calls with the page's address.
- On Linux, notifications are decided once for the window's own page origin (its `devUrl`) when the window opens, since WebKitGTK
  otherwise denies them. A page at another origin is asked when it asks.
- Other permission kinds reach `onPermissionRequest` as `PagePermission::Other` on Windows and are left to the platform on Linux.

## Layout

- `include/`: the public headers. `WebViewWindow.h` is the window; `Messages.h` is the page-to-host message dispatch.
- `src/`: the parts shared by both platforms.
- `platform/windows/`: the Win32 window, WebView2 callbacks, and DirectComposition for see-through windows.
- `platform/linux/`: the GTK and WebKitGTK window. GTK is loaded at runtime, so only the headers in `third_party/gtk` are needed.
- `platform/macos/`: the AppKit and WebKit window, in Objective-C++. See Status.
- `third_party/`: WebView2 headers and loader, GTK headers, and nlohmann/json.

## Build

    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/mingw-w64.cmake
    cmake --build build

The Windows build uses MinGW-w64. The example is built with `WEBVIEW_WINDOW_BUILD_EXAMPLE` (on by default). Set it to OFF
when the library is used as a submodule. The WebView2 runtime must be installed on the machine that runs the program.

## Status

- Windows: built and run with the example. The permission hook compiles with MinGW but hasn't been run on Windows yet.
- Linux: built and run with the example. `tests/linux_example_test.sh` and `tests/linux_permission_test.sh` check it.
- macOS: the window, its WKWebView, and the example's features are implemented in `platform/macos/`. The
  `.github/workflows/macos.yml` workflow builds the library and example on a macOS runner. The `tests/macos_*.sh` scripts check the
  window's behaviour on a Mac; CI only builds them.
