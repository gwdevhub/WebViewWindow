#!/usr/bin/env bash
# Drives the example on macOS and checks the window: it appears once its page has loaded, hide and show work, present shows the window
# again, the window server's frame matches the example's report, and quit exits cleanly. Every wait is at most 10 seconds.
#
# The cooldown (a hidden window freeing its web view after two minutes) is not checked here: it can't finish inside 10 seconds.
#
# Usage: tests/macos_example_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"

start_example "${1:-}"

# 1. The page loads, and the window appears only then.
if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown after its page loads"; else fail "window never appeared"; fi

# 2. The window server's frame is the example's frame.
reported="$(frame_now)"
on_screen="$(os_frame_now)"
if [[ -n "$reported" && "$reported" == "$on_screen" ]]; then
    pass "the window's frame is $reported, as the window server reports it"
else
    fail "the example reports the frame $reported, but the window server has $on_screen"
fi

# 3. hide hides the window and keeps its web view.
if command_then_check hide '^visible=0 open=1 ' hidden; then
    pass "hide hides the window and keeps its web view"
else
    fail "hide didn't hide the window, or freed its web view at once"
fi

# 4. show brings it back.
if command_then_check show '^visible=1 open=1 ' shown; then
    pass "show shows the hidden window again"
else
    fail "show didn't show the window"
fi

# 5. present shows the window again.
if command_then_check present '^visible=1 open=1 ' shown; then
    pass "present shows the window"
else
    fail "present didn't show the window"
fi

# 6. quit stops the event loop, and the example exits cleanly.
stop_example

finish
