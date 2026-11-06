#!/usr/bin/env bash
# Checks that a window's confinement to its monitor's work area holds when it is dragged. A confined window dropped past the bottom
# and right edges is moved back in, and ends exactly on those edges. The same drag without confinement leaves the window past the
# edges, where it was dropped. Turning confinement back on moves a window that is past the edges back in. Every wait is at most
# 10 seconds.
#
# The drags are made with xdotool, so the test needs an X display, and it assumes a display scale of 1.
#
# Usage: tests/linux_work_area_test.sh [build-dir]
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

# How far past the work area's edges the window is dragged. It has to be more than the snapping grid, so a window that is not
# confined is clearly past the edges.
overshoot=40

start_example "${1:-}"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

# The window's rectangle and the work area it is on, both from the example's report.
IFS=, read -r x y w h <<< "$(frame_now)"
IFS=, read -r ax ay aw ah <<< "$(area_now)"
right=$((ax + aw))
bottom=$((ay + ah))
if ((x >= ax && y >= ay && x + w <= right && y + h <= bottom)); then
    pass "the window starts inside its work area, $ax,$ay,$aw,$ah"
else
    fail "the window doesn't start inside its work area"
fi

# 1. Confined by default. The drag takes the window past the right and bottom edges, so it has to be moved back in.
drag_move $((x + w / 2)) $((y + h / 2)) $((right + overshoot - (x + w))) $((bottom + overshoot - (y + h)))
frame="$(settle $((right - w)) $((bottom - h)) "$right" "$bottom")"
IFS=, read -r fx fy fw fh <<< "$frame"
if ((fx + fw == right && fy + fh == bottom)); then
    pass "a confined window dropped past the bottom-right corner ends on the edges, at $fx,$fy"
else
    fail "a confined window ends at $fx,$fy with size ${fw}x${fh}, not on the work area's bottom-right edges $right,$bottom"
fi

# 2. Not confined. The same kind of drag leaves the window past the edges, where it was dropped.
command_then_check "confine off" '^visible=1 open=1 ' shown || fail "confine off didn't report the window shown"
IFS=, read -r x y w h <<< "$(frame_now)"
drag_move $((x + w / 2)) $((y + h / 2)) $((right + overshoot - (x + w))) $((bottom + overshoot - (y + h)))
sleep 0.5
frame="$(frame_now)"
IFS=, read -r fx fy fw fh <<< "$frame"
# The window ends past both edges. It doesn't have to reach the full overshoot: the window manager may hold it short of the pointer.
if ((fx + fw > right && fy + fh > bottom)); then
    pass "an unconfined window dropped past the bottom-right corner stays past it, at $fx,$fy"
else
    fail "an unconfined window was moved back in: it ends at $fx,$fy with size ${fw}x${fh}"
fi

# 3. Confined again. A window that is past the edges is moved back in straight away.
command_then_check "confine on" '^visible=1 open=1 ' shown || fail "confine on didn't report the window shown"
frame="$(settle $((right - w)) $((bottom - h)) "$right" "$bottom")"
IFS=, read -r fx fy fw fh <<< "$frame"
if ((fx + fw == right && fy + fh == bottom)); then
    pass "confining a window that is past the edges moves it back in"
else
    fail "confining a window left it at $fx,$fy, not on the work area's bottom-right edges $right,$bottom"
fi

stop_example
finish
