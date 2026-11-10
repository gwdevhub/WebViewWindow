#!/usr/bin/env bash
# Checks minimise and maximise on macOS. A minimised window leaves the screen and reports no frame, and present brings it back. A
# maximised window fills its monitor's work area, and maximising it again restores the frame it had before. Every wait is at most
# 10 seconds.
#
# Usage: tests/macos_window_state_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"

start_example "${1:-}"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

# 1. Minimise takes the window off the screen. The example reports no frame for it.
# 1. Minimise takes the window off the screen. The window server and a fresh report both see no frame. The minimise animation takes a
#    moment, so the window is waited for first.
echo minimize >&3
if wait_for_window hidden && [[ "$(frame_now)" == "none" ]]; then
    pass "minimise takes the window off the screen"
else
    fail "minimise didn't take the window off the screen: $(last_state)"
fi

# 2. present restores it.
echo present >&3
if wait_for_window shown && [[ "$(frame_now)" != "none" ]]; then
    pass "present restores a minimised window"
else
    fail "present didn't restore the minimised window: $(last_state)"
fi

# 3. Maximise fills the work area.
before="$(frame_now)"
IFS=, read -r x y w h <<< "$before"
IFS=, read -r ax ay aw ah <<< "$(area_now)"
before_area="$(area_now)"
command_then_check maximize '^visible=1 open=1 ' shown > /dev/null || true
sleep 0.3
maximised="$(frame_now)"
if [[ "$maximised" == "$before_area" ]]; then
    pass "maximise fills the work area, $maximised"
else
    fail "maximise gave $maximised, not the work area $before_area"
fi

# 4. Maximising again restores the frame it had.
command_then_check maximize '^visible=1 open=1 ' shown > /dev/null || true
sleep 0.3
restored="$(frame_now)"
if [[ "$restored" == "$before" ]]; then
    pass "maximising again restores the frame $restored"
else
    fail "restoring gave $restored, not the frame $before"
fi

stop_example
finish
