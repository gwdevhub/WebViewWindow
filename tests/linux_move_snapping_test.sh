#!/usr/bin/env bash
# Checks that dragging the example's window honours the snapping grid: when the drag ends, the window's top-left corner sits on the
# nearest grid line to where the pointer put it, and its size is unchanged. The window's rectangle is read from the example's
# report. Every wait is at most 10 seconds.
#
# The drag is made with xdotool, so the test needs an X display, and it assumes a display scale of 1.
#
# Usage: tests/linux_move_snapping_test.sh [build-dir]
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

start_example "${1:-}"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

# The window's position is chosen so the drag leaves its left edge 3 pixels past a grid line and its top edge 2 pixels past one,
# so the snapped position can only match if the drop snaps.
IFS=, read -r x y w h <<< "$(frame_now)"
dx=$((((3 - x) % grid + grid) % grid + 2 * grid))
dy=$((((2 - y) % grid + grid) % grid + 2 * grid))
unsnapped_left=$((x + dx))
unsnapped_top=$((y + dy))
want_left="$(nearest "$unsnapped_left")"
want_top="$(nearest "$unsnapped_top")"
if ((unsnapped_left % grid == 0 || unsnapped_top % grid == 0)); then
    fail "setup: the unsnapped edges are already on the grid, so the check would prove nothing"
fi

drag_move $((x + w / 2)) $((y + h / 2)) "$dx" "$dy"
frame="$(settle "$want_left" "$want_top" $((want_left + w)) $((want_top + h)))"
IFS=, read -r fx fy fw fh <<< "$frame"

if ((fx == want_left)); then
    pass "the left edge snapped to $want_left (unsnapped $unsnapped_left)"
else
    fail "the left edge is at $fx, expected the grid line $want_left (unsnapped $unsnapped_left)"
fi
if ((fy == want_top)); then
    pass "the top edge snapped to $want_top (unsnapped $unsnapped_top)"
else
    fail "the top edge is at $fy, expected the grid line $want_top (unsnapped $unsnapped_top)"
fi
if ((fw == w && fh == h)); then
    pass "a move keeps the window's size"
else
    fail "a move changed the window's size from ${w}x${h} to ${fw}x${fh}"
fi

stop_example
finish
