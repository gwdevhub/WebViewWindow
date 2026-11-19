#!/usr/bin/env bash
# Checks that a window resized and then moved lands where it was moved to, once it has settled. The window is moved to a spot
# 20 pixels in from the right edge of its work area, so a move that sizes its target from the old frame clamps it back. Each case
# runs once confined to the work area, and once unconfined. Every wait is at most 10 seconds.
#
# The check uses the example's report, so the test needs an X display.
#
# Usage: tests/linux_move_after_resize_test.sh [build-dir]
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

given_build="${1:-}"

# Starts the example with the given options, resizes it to 200 by 150, moves it near the right edge of its work area, and checks
# the frame once the move has settled.
check_resize_then_move() {
    local label="$1"
    shift
    start_example "$given_build" "$@"

    if ! wait_for_line_after 0 '^loaded$'; then
        fail "$label: page never reported loaded"
        stop_example
        return
    fi
    if ! wait_for_window shown; then
        fail "$label: window never appeared"
        stop_example
        return
    fi

    local ax ay aw ah x y frame
    frame_now > /dev/null
    IFS=, read -r ax ay aw ah <<< "$(area_now)"
    x=$((ax + aw - 200 - 20))
    y=$((ay + 50))
    echo "size 200 150" >&3
    echo "place $x $y" >&3
    sleep 1
    frame="$(frame_now)"
    if [[ "$frame" == "$x,$y,200,150" ]]; then
        pass "$label: after a resize and a move, the frame is $frame"
    else
        fail "$label: after a resize and a move, expected $x,$y,200,150 but the frame is $frame"
    fi
    stop_example
}

check_resize_then_move "confined"
check_resize_then_move "unconfined" --unconfined

finish
