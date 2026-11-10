#!/usr/bin/env bash
# Checks that a see-through window shows the desktop behind it on macOS. The example's page is drawn with a solid colour, and with
# --clear-page its background is left transparent. The window is captured from the screen: the opaque window's centre has the page's
# colour, and the see-through window's centre doesn't.
#
# The capture needs Screen Recording permission for the terminal running the test. Without it the capture shows only the desktop, and
# the test reports SKIP with that reason rather than passing or failing.
#
# Usage: tests/macos_transparency_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"
export WEBVIEW_EXAMPLE_NO_DIALOGS=1
build="${1:-}"

# The window's centre pixel, as "r g b", from a screen capture of the window's frame.
centre_pixel() {
    local frame="$1" x y w h
    IFS=, read -r x y w h <<< "$frame"
    local bmp="$work/capture-$RANDOM.bmp"
    screencapture -x -t bmp -R "$x,$y,$w,$h" "$bmp"
    python3 - "$bmp" "$((w / 2))" "$((h / 2))" <<'PY'
import struct, sys
path, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
data = open(path, 'rb').read()
offset = struct.unpack_from('<I', data, 10)[0]
width, height = struct.unpack_from('<ii', data, 18)
bpp = struct.unpack_from('<H', data, 28)[0]
row = ((width * bpp + 31) // 32) * 4
rows = y if height < 0 else abs(height) - 1 - y
i = offset + rows * row + x * (bpp // 8)
print(data[i + 2], data[i + 1], data[i])
PY
}

# The page's colour is #223344 (34, 50, 68), drawn by the built-in page, so a pixel of it is within a few steps of that.
is_page_colour() {
    python3 -c 'import sys; r, g, b = map(int, sys.argv[1:4]); print("yes" if abs(r-34) <= 6 and abs(g-50) <= 6 and abs(b-68) <= 6 else "no")' "$@"
}

start_example "$build"
wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded"
wait_for_window shown || fail "the window never appeared"
focus_window
opaque_frame="$(frame_now)"
sleep 0.5
opaque_pixel="$(centre_pixel "$opaque_frame")"
stop_example

if [[ "$(is_page_colour $opaque_pixel)" != yes ]]; then
    echo "SKIP: the capture doesn't show the example's window (pixel $opaque_pixel, not the page's colour). Grant Screen Recording to the terminal app in System Settings, then run this again."
    keep_work=0
    exit 0
fi
pass "the opaque window's centre has the page's colour"

start_example "$build" --clear-page
wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded with --clear-page"
wait_for_window shown || fail "the see-through window never appeared"
focus_window
clear_frame="$(frame_now)"
sleep 0.5
clear_pixel="$(centre_pixel "$clear_frame")"
stop_example
if [[ "$(is_page_colour $clear_pixel)" == no ]]; then
    pass "a see-through window shows the desktop behind it, at pixel $clear_pixel"
else
    fail "a see-through window still shows the page's colour at pixel $clear_pixel"
fi

finish
