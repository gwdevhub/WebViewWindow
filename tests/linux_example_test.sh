#!/usr/bin/env bash
# Drives the example on the current X display and checks the window: it appears once its page has loaded, hide and show work,
# present shows the window again, and quit exits cleanly. Every wait is at most 10 seconds.
#
# The cooldown (a hidden window freeing its web view after two minutes) is not checked here: it can't finish inside 10 seconds.
#
# Usage: tests/linux_example_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

start_example "${1:-}"

# 1. The page loads, and the window appears only then.
if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown after its page loads"; else fail "window never appeared"; fi

# 2. hide hides the window and keeps its web view.
if command_then_check hide '^visible=0 open=1 ' hidden; then
    pass "hide hides the window and keeps its web view"
else
    fail "hide didn't hide the window, or freed its web view at once"
fi

# 3. show brings it back.
if command_then_check show '^visible=1 open=1 ' shown; then
    pass "show shows the hidden window again"
else
    fail "show didn't show the window"
fi

# 4. present shows the window again.
if command_then_check present '^visible=1 open=1 ' shown; then
    pass "present shows the window"
else
    fail "present didn't show the window"
fi

# 5. quit stops the event loop, and the example exits cleanly.
stop_example

finish
