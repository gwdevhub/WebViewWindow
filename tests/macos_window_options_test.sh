#!/usr/bin/env bash
# Checks the window options on macOS that the example exposes: always on top and keep below set the window's level, a window that
# starts invisible shows when asked, an autosize window takes the page's size, the minimum size holds for a user's resize, the UI scale
# resizes the window, and the taskbar, title bar, sticky and utility options start and show the window. Every wait is at most 10 seconds.
#
# Whether a window is on top or below is read from the window server's layer. The skip-taskbar, sticky and utility options have no
# system record a test can read, so those are checked only to show the window.
#
# Usage: tests/macos_window_options_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"
export WEBVIEW_EXAMPLE_NO_DIALOGS=1
build="${1:-}"

# The layer of the example's main window: the on-screen window that is as wide as the example's 320 points.
main_layer() {
    python3 -c '
import json, sys
for window in json.loads(sys.stdin.read()):
    if window["onscreen"] and window["bounds"][2] == 320 and window["bounds"][3] == 160:
        print(window["layer"])
        break
' <<< "$(os_windows_all)"
}

# Starts the example with the options, waits for its page, and sets layer_seen to the main window's layer, once it's shown.
layer_with() {
    start_example "$build" "$@"
    wait_for_line_after 0 '^loaded$' || fail "the page never loaded with $*"
    wait_for_window shown || fail "the window never appeared with $*"
    sleep 0.3
    layer_seen="$(main_layer)"
}

# 1. Levels: the default is the normal level, always on top is the floating level (3), and keep below is under the normal windows.
layer_with
stop_example
if [[ "$layer_seen" == 0 ]]; then pass "by default the window is at the normal level"; else fail "the default window is on layer $layer_seen"; fi

layer_with --always-on-top
stop_example
if [[ "$layer_seen" == 3 ]]; then pass "always on top puts the window on the floating level"; else fail "always on top gave layer $layer_seen, not 3"; fi

layer_with --keep-below
stop_example
if [[ -n "$layer_seen" && "$layer_seen" -lt 0 ]]; then
    pass "keep below puts the window under the normal windows, on layer $layer_seen"
else
    fail "keep below gave layer $layer_seen, not below the normal level"
fi

# 2. An invisible window isn't on screen until it's shown.
start_example "$build" --invisible
if wait_for_line_after 0 '^loaded$'; then pass "an invisible window's page loads"; else fail "the page never loaded"; fi
sleep 0.5
if window_shown; then fail "an invisible window was on screen"; else pass "an invisible window isn't on screen"; fi
if command_then_check show '^visible=1 open=1 ' shown; then pass "show brings the invisible window on screen"; else fail "show didn't bring it on screen"; fi
stop_example

# 3. An autosize window takes the size the page reports.
start_example "$build" --autosize
wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded"
wait_for_window shown || fail "the window never appeared"
before="$(lines_so_far)"
echo "fit 400 220" >&3
wait_for_line_after "$before" '^visible=1 open=1 frame=[0-9-]*,[0-9-]*,400,220 ' && pass "fit sizes an autosize window to the page's size, 400x220" || fail "fit didn't size the window to 400x220: $(last_state)"
stop_example

# 4. The minimum size holds when the user resizes the window smaller than it.
start_example "$build" --min-size 300 200
wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded"
wait_for_window shown || fail "the window never appeared"
focus_window
IFS=, read -r x y w h <<< "$(frame_now)"
drag_resize $((x + w - 4)) $((y + h - 4)) -200 -200 se
sleep 0.5
IFS=, read -r fx fy fw fh <<< "$(frame_now)"
if ((fw >= 300 && fh >= 200)); then
    pass "a user's resize can't go below the minimum, the window is ${fw}x${fh}"
else
    fail "the window shrank to ${fw}x${fh}, below the 300x200 minimum"
fi
stop_example

# 5. The UI scale resizes the window: 150 percent makes the 320x160 window 480x240.
start_example "$build"
wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded"
wait_for_window shown || fail "the window never appeared"
before="$(lines_so_far)"
echo "scale 150" >&3
wait_for_line_after "$before" '^visible=1 open=1 frame=[0-9-]*,[0-9-]*,480,240 ' && pass "a 150 percent scale makes the window 480x240" || fail "scale 150 didn't size the window: $(last_state)"
stop_example

# 6. The taskbar, title bar, sticky and utility options start the window, and the taskbar and title bar options can change it.
start_example "$build" --sticky --utility --no-titlebar
wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded with sticky and utility"
if wait_for_window shown; then pass "a sticky, utility window without a title bar is shown"; else fail "the window with sticky and utility options never appeared"; fi
if command_then_check "skip on" '^visible=1 open=1 ' shown; then pass "skip on keeps the window shown"; else fail "skip on didn't keep the window shown"; fi
if command_then_check "skip off" '^visible=1 open=1 ' shown; then pass "skip off keeps the window shown"; else fail "skip off didn't keep the window shown"; fi
if command_then_check "titlebar on" '^visible=1 open=1 ' shown; then pass "titlebar on keeps the window shown"; else fail "titlebar on didn't keep the window shown"; fi
stop_example

finish
