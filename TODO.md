# TODO: missing functionality across Windows, Linux and macOS

Reviewed against `include/WebViewWindow.h` and the three platform files. "Stub" means the function is
declared and called, but does nothing or returns a fixed answer. "Missing" means the option or function is
declared with no effect on that platform, or has no definition there.

## Stubs (declared, called, and do nothing)

| Feature | Windows | Linux | macOS | Where |
| --- | --- | --- | --- | --- |
| Input region (`setInputRegion`, `clickThrough`) | done | done (GTK input shape) | **stub**: whole window takes the pointer | macOS `platformSetInputRegion`, `platform/macos/WebViewWindow.mm:800` |
| Full screen (`setFullscreen`) | **stub** | done | done | Windows `platformSetFullscreen`, `platform/windows/WebViewWindow.cpp:858` |
| Tray icon picture and tooltip (`updateTrayIcon`) | **stub**: returns false | done | **stub**: returns false | `platform/windows/WebViewWindow.cpp:1299`, `platform/macos/WebViewWindow.mm:980` |

## Declared for every platform, defined on one

| Function | Defined on | Notes |
| --- | --- | --- |
| `showTrayBalloon` | Windows only | Only `host/src/DesktopWin32.cpp` calls it, so nothing breaks today. Linux and macOS need an implementation (libnotify on Linux, `NSUserNotification`/`UNUserNotificationCenter` on macOS), or the declaration should move under `#ifdef _WIN32`. |
| `executableFolder` | Windows only | Linux and macOS need `platform::executablePath()`-style code. Not called outside the library today. |

## Options that are read on one platform only

| Option | Windows | Linux | macOS | Notes |
| --- | --- | --- | --- | --- |
| `startupTimeout` (default 10 s) | done | done | done | Linux added with the same semantics; the default is now 10 s on every platform. |
| `minWidth`, `minHeight` | done | **missing** | done | Linux never reads them, so the user can resize below the minimum. |
| `clickThrough` | done | done | **missing** | Depends on the macOS input region stub above. |
| `hardwareAcceleration` | **not read** | done (WebKit policy) | **not read** | Check whether WebView2 and WKWebView have an equivalent. If not, document that the option is Linux-only. |
| `sticky` (all virtual desktops) | does nothing | done | done | Windows has no virtual desktops in the same sense. Header says this. Intentional; listed for completeness. |

## Testing gaps

- Windows: the permission hook and the click-through test have not run (README "Status").
- macOS: CI only builds the library and example. The `tests/macos_*.sh` scripts have not been run on a Mac.
- Linux: `minWidth`/`minHeight` and `startupTimeout` have no test yet. `startupTimeout` was built, not run against a page that never reports ready.
