#!/usr/bin/env bash
# Checks that a window given an input region takes the pointer only over that region. Without a region the example's window takes
# the pointer everywhere. With the region set to the window's top-left quarter, the pointer over that quarter must reach the example's
# window, and the pointer over the bottom-right quarter must reach the window beneath. Every wait is at most 10 seconds.
#
# The check uses xdotool, so the test needs an X display.
#
# Usage: tests/linux_input_region_test.sh [build-dir]
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

# The window the X server reports under the pointer, as a hexadecimal id, or "none" when the query gives nothing.
window_under_pointer() {
    local px="$1" py="$2" id
    xdotool mousemove --sync "$px" "$py"
    id="$(xdotool getmouselocation --shell | sed -n 's/^WINDOW=//p')"
    echo "${id:-none}"
}

# The example's own window, by its title. Empty when it isn't on screen.
example_window_id() {
    xdotool search --onlyvisible --name "^${title}$" 2>/dev/null | head -n 1
}

given_build="${1:-}"

start_example "$given_build"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

# The control: with no region set, the example's window is under the pointer over either quarter.
IFS=, read -r fx fy fw fh <<< "$(frame_now)"
top_x=$((fx + fw / 4))
top_y=$((fy + fh / 4))
bottom_x=$((fx + 3 * fw / 4))
bottom_y=$((fy + 3 * fh / 4))
own="$(example_window_id)"
under="$(window_under_pointer "$bottom_x" "$bottom_y")"
if [[ -n "$own" && "$under" == "$own" ]]; then
    pass "without a region, the example's window is under the pointer over the bottom-right quarter"
else
    fail "without a region, the window under the bottom-right quarter is $under, not the example's $own"
fi

# Sets the region to the top-left quarter of the window, in the window's own units.
echo "region 0 0 $((fw / 2)) $((fh / 2))" >&3
sleep 1

own="$(example_window_id)"
under="$(window_under_pointer "$top_x" "$top_y")"
if [[ -n "$own" && "$under" == "$own" ]]; then
    pass "with the region, the pointer over the top-left quarter reaches the example's window"
else
    fail "with the region, the window under the top-left quarter is $under, not the example's $own"
fi

under="$(window_under_pointer "$bottom_x" "$bottom_y")"
if [[ -n "$own" && "$under" != "none" && "$under" != "$own" ]]; then
    pass "with the region, the pointer over the bottom-right quarter reaches the window beneath ($under, not $own)"
else
    fail "with the region, the window under the bottom-right quarter is $under, own=$own"
fi

stop_example
finish
