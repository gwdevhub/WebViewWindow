#!/usr/bin/env bash
# Checks that resizing the example's window honours the snapping grid: a resize from the south-east corner and one from the
# north-west corner each end with the edges they moved on the grid of 8 pixels, at the nearest grid line to where the pointer
# put them. The window's rectangle is read from the example's report. Every wait is at most 10 seconds.
#
# The drags are made with the pointer, so the test needs a logged-in desktop session. The grid is 8 device pixels, which is 8 /
# the display's scale in points, so it is read from the display.
#
# Usage: tests/macos_resize_snapping_test.sh [build-dir]
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"


start_example "${1:-}"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

# 1. South-east resize. The right and bottom edges move by dx and dy. Those are chosen so the unsnapped right edge is 3 pixels past
#    a grid line and the unsnapped bottom edge is 2 pixels past one, so the snapped edges can only match if they snap.
IFS=, read -r x y w h <<< "$(frame_now)"
dx=$((((3 - (x + w)) % grid + grid) % grid + 2 * grid))
dy=$((((2 - (y + h)) % grid + grid) % grid + 2 * grid))
unsnapped_right=$((x + w + dx))
unsnapped_bottom=$((y + h + dy))
want_right="$(nearest "$unsnapped_right")"
want_bottom="$(nearest "$unsnapped_bottom")"
if ((unsnapped_right % grid == 0 || unsnapped_bottom % grid == 0)); then
    fail "setup: the unsnapped edges are already on the grid, so the check would prove nothing"
fi
drag_resize $((x + w - 4)) $((y + h - 4)) "$dx" "$dy" se
frame="$(settle "$x" "$y" "$want_right" "$want_bottom")"
IFS=, read -r fx fy fw fh <<< "$frame"
if [[ "$fx" == "$x" && "$fy" == "$y" ]]; then
    pass "a south-east resize keeps the window's top-left corner"
else
    fail "a south-east resize moved the top-left corner from $x,$y to $fx,$fy"
fi
if ((fx + fw == want_right)); then
    pass "the right edge snapped to $want_right (unsnapped $unsnapped_right)"
else
    fail "the right edge is at $((fx + fw)), expected the grid line $want_right (unsnapped $unsnapped_right)"
fi
if ((fy + fh == want_bottom)); then
    pass "the bottom edge snapped to $want_bottom (unsnapped $unsnapped_bottom)"
else
    fail "the bottom edge is at $((fy + fh)), expected the grid line $want_bottom (unsnapped $unsnapped_bottom)"
fi

# Let the south-east drag finish before the next one starts.
sleep 0.05

# 2. North-west resize from the window as it is now. The left and top edges move by dx and dy, chosen the same way: the unsnapped
#    left edge is 3 pixels past a grid line and the unsnapped top edge 2 pixels past one.
IFS=, read -r x y w h <<< "$frame"
dx=$((-(((x - 3) % grid + grid) % grid + 2 * grid)))
dy=$((-(((y - 2) % grid + grid) % grid + 2 * grid)))
unsnapped_left=$((x + dx))
unsnapped_top=$((y + dy))
want_left="$(nearest "$unsnapped_left")"
want_top="$(nearest "$unsnapped_top")"
if ((unsnapped_left % grid == 0 || unsnapped_top % grid == 0)); then
    fail "setup: the unsnapped edges are already on the grid, so the check would prove nothing"
fi
drag_resize $((x + 4)) $((y + 4)) "$dx" "$dy" nw
frame="$(settle "$want_left" "$want_top" $((x + w)) $((y + h)))"
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
if ((fx + fw == x + w && fy + fh == y + h)); then
    pass "a north-west resize keeps the bottom-right corner"
else
    fail "a north-west resize moved the bottom-right corner"
fi

stop_example
finish
