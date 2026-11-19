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

## Declared for every platform, missing on some

| Function | Windows | Linux | macOS | Notes |
| --- | --- | --- | --- | --- |
| `showTrayBalloon` | done | done (libnotify, opened on first use) | **missing**: not defined | Linux tested: the notification reached the session bus with its title and body. macOS needs `NSUserNotification` or `UNUserNotificationCenter`, or the declaration should move under `#ifdef _WIN32`. |
| `executableFolder` | done | done (`/proc/self/exe`) | **missing**: not defined | Linux tested with a test program. macOS needs `NSBundle`/`_NSGetExecutablePath`. |

## Options that are read on one platform only

| Option | Windows | Linux | macOS | Notes |
| --- | --- | --- | --- | --- |
| `startupTimeout` (default 10 s) | done | done | done | Linux added with the same semantics; the default is now 10 s on every platform. |
| `minWidth`, `minHeight` | done | done | done | Linux sets the minimum with GTK geometry hints. Tested with the example's `--min-size`: the hint is set, but a mouse drag below it was not tried. |
| `resizable` | done | done | done | Linux sets `gtk_window_set_resizable`. Tested with `--not-resizable`: the window's min and max hints are both the window size. |
| `webViewDataFolder` | done (WebView2 profile) | done (a WebKit context per folder) | **not read** | Linux tested: WebKit wrote its `data` and `cache` folders into the chosen folder. macOS would need `WKWebsiteDataStore` with a custom folder, which macOS does not offer; document it as not applicable there. |
| `clickThrough` | done | done | **missing** | Depends on the macOS input region stub above. |
| `hardwareAcceleration` | **not read** | done (WebKit policy) | **not read** | Check whether WebView2 and WKWebView have an equivalent. If not, document that the option is Linux-only. |
| `sticky` (all virtual desktops) | does nothing | done | done | Windows has no virtual desktops in the same sense. Header says this. Intentional; listed for completeness. |

## Testing rule: coverage

The rule (README, "Testing rule") is that every feature has a test that runs on each platform. A test that is platform-neutral counts
for all three.

**What runs today.** CI runs three Windows scripts (`windows-permissions.yml`: permission, download, click-through). CI on macOS only
builds (`macos.yml`). There is no Linux CI. The other scripts are run by hand, and the Windows and macOS ones have not been run by anyone yet
(README "Status"). So a script existing is not the same as a test running.

| Feature | Windows | Linux | macOS |
| --- | --- | --- | --- |
| Lifecycle: open, show, hide, present, quit | `windows_example_test.ps1` | `linux_example_test.sh` | `macos_example_test.sh` |
| Cooldown | `windows_cooldown_test.ps1` | `linux_cooldown_test.sh` | `macos_cooldown_test.sh` |
| Downloads | `windows_download_test.ps1` | `linux_download_test.sh` | `macos_download_test.sh` |
| Permissions | `windows_permission_test.ps1` | `linux_permission_test.sh` | `macos_permission_test.sh` |
| Move snapping | `windows_move_snapping_test.ps1` | `linux_move_snapping_test.sh` | `macos_move_snapping_test.sh` |
| Confined to work area | `windows_work_area_test.ps1` | `linux_work_area_test.sh` | `macos_work_area_test.sh` |
| Resize snapping | `windows_resize_snapping_test.ps1` | `linux_resize_snapping_test.sh` | `macos_resize_snapping_test.sh` |
| clickThrough | `windows_click_through_test.ps1` | `linux_click_through_test.sh` | **none** |
| Input region (`setInputRegion`) | **none** | `linux_input_region_test.sh` | **none** (stub) |
| Page notifications | **none** | `linux_notification_test.sh` | **none** |
| `resizeEdges` | **none** | **none** | `macos_resize_edges_test.sh` |
| `transparent` | **none** | **none** | `macos_transparency_test.sh` |
| Window options: always on top, keep below, start hidden, autosize | **none** | **none** | `macos_window_options_test.sh` |
| Native options: sticky, collection behaviour | **none** | **none** | `macos_native_options_test.sh` |
| Minimise and maximise | **none** | **none** | `macos_window_state_test.sh` |
| Tray icon: show, click, menu, untray | **none** | **none** | `macos_tray_test.sh` |
| Tray balloon (`showTrayBalloon`) | **none** | **none** | **missing** |
| Tray picture update (`updateTrayIcon`) | **none** (stub) | **none** | **none** (stub) |
| Startup timeout and page failure | **none** | **none** | `macos_page_failure_test.sh` |
| Fullscreen | **none** (stub) | **none** | **none** |
| Resizable and minimum size | **none** | **none** | `macos_window_options_test.sh` (minimum size only) |
| Data folder (`webViewDataFolder`) | **none** | **none** (checked by hand) | n/a |
| Executable folder | **none** | **none** (checked by hand) | **missing** |
| Hardware acceleration | **none** | **none** | n/a |
| Skip taskbar and utility windows | **none** | **none** | **none** |
| Title bar and `setUiScale` | **none** | **none** | **none** |
| DevTools (`openDevTools`) | **none** | **none** | **none** |
| Application icon | **none** | **none** | **none** |

**Evaluation.** Of the 28 features in the table, 7 have a test on all three platforms: lifecycle, cooldown, downloads, permissions, move
snapping, confined work area and resize snapping. The other 21 are missing a test on at least one platform. Three of them are stubs or
missing implementations on a platform (input region on macOS, fullscreen on Windows, tray picture update on macOS and Windows), so a test
would currently fail or have nothing to check; the rule for stubs in README asks for a test of the documented result.

**Problems with the rule itself.**
- Most tests drive real windows, the pointer, or the window server. They need a desktop session. Whether the hosted Windows and macOS
  runners give one is untested. Linux tests need an X display, so a Linux CI job would need a virtual display such as Xvfb.
- The rule counts a platform-neutral test once. That covers pure logic (for example, `scaledSize` or `rules`-style checks), not window
  behaviour, so most of the table still needs per-platform scripts.
- "Runs on each platform" means each platform's scripts run in CI, not just that a script exists. Until the Windows and macOS scripts run
  somewhere, the 7 features above are not verified on those platforms either.

**Next steps, in order.**
1. Add a Linux CI job under Xvfb that runs the `tests/linux_*.sh` scripts.
2. Run the Windows scripts in CI, not only three of them.
3. Add the missing scripts for each feature in the table, starting with the ones that have a test on two platforms already.
4. For the stubs, add a test that checks the documented result, then implement them when the platform can do it.
