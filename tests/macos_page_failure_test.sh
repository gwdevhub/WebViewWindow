#!/usr/bin/env bash
# Checks what happens when the web view fails on macOS. A page that reports an error fails the window, and the failure hook is told
# the message. A page that never reports ready fails the window at its startup timeout, and the window never appears. The example
# closes a failed window and reports the failure, so the tests don't wait on a dialog. Every wait is at most 10 seconds.
#
# Usage: tests/macos_page_failure_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"
export WEBVIEW_EXAMPLE_NO_DIALOGS=1
build="${1:-}"

# 1. A page's own error fails the window, which reports the page's message and closes.
start_example "$build"
if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi
before="$(lines_so_far)"
echo frontenderror >&3
if wait_for_line_after "$before" '^failure the page reported an error$' && wait_for_window hidden; then
    pass "a page's error fails the window, and the failure hook gets its message"
else
    fail "a page's error didn't fail the window: $(tail -n 2 "$work/out.txt" | tr '\n' ' ')"
fi
stop_example

# 2. A page that never reports ready fails at the startup timeout, and its window is never shown.
start_example "$build" --no-ready --startup-timeout 1
if wait_for_line_after 0 '^failure Loading the page took too long'; then
    pass "a page that never reports ready fails at its startup timeout"
else
    fail "the startup timeout didn't fail the window: $(cat "$work/out.txt" | tr '\n' ' ')"
fi
if window_shown; then fail "the window was shown although its page never reported ready"; else pass "the window never appears for a page that never reports ready"; fi
stop_example

finish
