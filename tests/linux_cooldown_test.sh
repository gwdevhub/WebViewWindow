#!/usr/bin/env bash
# Checks the cooldown: a hidden window keeps its web view until the cooldown ends, then frees it, and a window that is shown again
# within the cooldown keeps it. The example runs with a one second cooldown, so the test finishes within 10 seconds.
#
# Usage: tests/linux_cooldown_test.sh [build-dir]
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

cooldown_ms=1000
wait_past_cooldown() {
    sleep 1.5
}

start_example "${1:-}" --cooldown-ms "$cooldown_ms"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

# 1. Hidden, the window keeps its web view straight after the hide.
if command_then_check hide '^visible=0 open=1 ' hidden; then
    pass "a hidden window keeps its web view while the cooldown runs"
else
    fail "hide didn't hide the window, or freed its web view at once"
fi

# 2. After the cooldown, the web view is freed.
wait_past_cooldown
if command_then_check report '^visible=0 open=0 frame=none ' hidden; then
    pass "a hidden window frees its web view when the cooldown ends"
else
    fail "a hidden window still has its web view after the cooldown"
fi

# 3. A freed window opens again when it's shown.
if command_then_check show '^visible=1 open=1 ' shown; then
    pass "show opens a window whose web view was freed"
else
    fail "show didn't open the freed window"
fi

# 4. Shown again within the cooldown, the window keeps its web view past the cooldown's end.
command_then_check hide '^visible=0 open=1 ' hidden || fail "hide before the cancel check didn't hide the window"
sleep 0.3
command_then_check show '^visible=1 open=1 ' shown || fail "show within the cooldown didn't show the window"
wait_past_cooldown
if command_then_check report '^visible=1 open=1 ' shown; then
    pass "a show within the cooldown cancels it: the window keeps its web view"
else
    fail "the cooldown freed the web view of a window that was shown again"
fi

stop_example
finish
