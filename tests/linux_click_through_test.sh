#!/usr/bin/env bash
# Checks that a window opened with clickThrough passes the pointer through to the windows beneath it. The pointer is moved over the
# middle of the example's window, and the window the X server reports under it must not be the example's. The control runs the same
# check without --click-through, where the example's window must be the one under the pointer. Every wait is at most 10 seconds.
#
# The check uses xdotool, so the test needs an X display.
#
# Usage: tests/linux_click_through_test.sh [build-dir]
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

# The pointer's target: the middle of the example's frame, from the example's report.
pointer_target() {
    local x y w h
    IFS=, read -r x y w h <<< "$(frame_now)"
    echo "$((x + w / 2)) $((y + h / 2))"
}

# Both runs use one build: the given build directory, or the one start_example makes in the work folder.
given_build="${1:-}"
build_dir="${given_build:-$work/build}"

start_example "$given_build" --click-through

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown"; else fail "window never appeared"; fi

read -r px py <<< "$(pointer_target)"
own="$(example_window_id)"
under="$(window_under_pointer "$px" "$py")"
if [[ -n "$own" && "$under" != "none" && "$under" != "$own" ]]; then
    pass "with --click-through, the pointer over the window reaches the window beneath it ($under, not $own)"
else
    fail "with --click-through, the pointer over the window reached the example's window: under=$under own=$own"
fi
stop_example

# The control: the same window without clickThrough takes the pointer itself.
start_example "$build_dir"

if wait_for_line_after 0 '^loaded$'; then pass "control page loaded"; else fail "control page never reported loaded"; fi
if wait_for_window shown; then pass "control window is shown"; else fail "control window never appeared"; fi

read -r px py <<< "$(pointer_target)"
own="$(example_window_id)"
under="$(window_under_pointer "$px" "$py")"
if [[ -n "$own" && "$under" == "$own" ]]; then
    pass "without --click-through, the example's window is under the pointer"
else
    fail "without --click-through, the window under the pointer is $under, not the example's $own"
fi
stop_example

finish
