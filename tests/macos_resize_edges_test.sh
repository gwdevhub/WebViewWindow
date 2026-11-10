#!/usr/bin/env bash
# Checks the resize strips a window draws when it's given resizeEdges. A press on the bottom-right strip of the page starts a
# resize from that corner, which the page's own strip does, so no command is sent. Without resizeEdges the page draws no strip and
# the same press does nothing. Every wait is at most 10 seconds.
#
# Usage: tests/macos_resize_edges_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"
export WEBVIEW_EXAMPLE_NO_DIALOGS=1
build="${1:-}"

# Starts the example with the options, waits for it to show, and presses on its bottom-right corner, then drags by (20, 15). The
# frame after the drag is set in after.
corner_drag() {
    start_example "$build" "$@"
    wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded with $*"
    wait_for_window shown || fail "the window never appeared with $*"
    focus_window
    IFS=, read -r x y w h <<< "$(frame_now)"
    # Pressing 4 points in from the corner is on the page's strip, which is 8 points across.
    press_at $((x + w - 4)) $((y + h - 4))
    sleep 0.3
    drag_to $((x + w - 4 + 20)) $((y + h - 4 + 15))
    sleep 0.5
    after="$(frame_now)"
    stop_example
}

corner_drag --resize-edges
IFS=, read -r fx fy fw fh <<< "$after"
if ((fw > 320 && fh > 160)); then
    pass "a press on the bottom-right strip resizes the window, to ${fw}x${fh}"
else
    fail "a press on the bottom-right strip didn't resize the window: $after"
fi

corner_drag
if [[ "$after" == "704,469,320,160" ]]; then
    pass "without resizeEdges the same press doesn't resize the window"
else
    fail "without resizeEdges the window changed to $after"
fi

finish
