#!/usr/bin/env bash
# Checks the window settings that have no on-screen effect a test can see, by reading the native windows the example owns. The
# example's describe command prints each native window's collection behaviour, whether it's excluded from the Window menu, and its
# style. Checked here:
#   sticky sets the can-join-all-spaces bit of the collection behaviour;
#   skip taskbar sets the ignore-cycle bit and excludes the window from the Window menu, both at start-up and through skip on/off;
#   utility changes nothing on macOS, which the header says (AppKit drops the utility style on a borderless window);
#   devtools opens a Web Inspector window.
# Every wait is at most 10 seconds.
#
# Usage: tests/macos_native_options_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"
export WEBVIEW_EXAMPLE_NO_DIALOGS=1
build="${1:-}"

CAN_JOIN_ALL_SPACES=1
IGNORE_CYCLE=64

# Asks the example to describe its windows, and sets main_line to the example's own window's description once it's printed.
describe_now() {
    local before
    before="$(lines_so_far)"
    echo describe >&3
    wait_for_line_after "$before" '^describe done$' > /dev/null || true
    main_line="$(tail -n +"$((before + 1))" "$work/out.txt" | grep '^native title=WebViewWindow Example ' | tail -n 1 || true)"
}

# The value of one field of the main window's description. Usage: field <name>
field() {
    echo "$main_line" | tr ' ' '\n' | sed -n "s/^$1=//p"
}

wait_for_main_window() {
    wait_for_line_after 0 '^loaded$' > /dev/null || fail "the page never loaded with $*"
    wait_for_window shown || fail "the window never appeared with $*"
}

# 1. Sticky: the window joins every space.
start_example "$build" --sticky
wait_for_main_window --sticky
describe_now
behavior="$(field behavior)"
if (( (behavior & CAN_JOIN_ALL_SPACES) != 0 )); then
    pass "sticky sets the can-join-all-spaces bit (behavior $behavior)"
else
    fail "sticky didn't set the can-join-all-spaces bit: $main_line"
fi
stop_example

# 2. Skip taskbar at start-up: the window is excluded from the Window menu and cycling.
start_example "$build" --skip-taskbar
wait_for_main_window --skip-taskbar
describe_now
behavior="$(field behavior)"
if (( (behavior & IGNORE_CYCLE) != 0 )) && [[ "$(field excluded)" == 1 ]]; then
    pass "skip taskbar at start-up excludes the window from the Window menu and cycling"
else
    fail "skip taskbar at start-up didn't exclude the window: $main_line"
fi
stop_example

# 3. The skip command changes it while the window is open, both ways.
start_example "$build"
wait_for_main_window
describe_now
if [[ "$(field excluded)" == 0 ]]; then pass "by default the window is in the Window menu"; else fail "by default the window is excluded: $main_line"; fi
before="$(lines_so_far)"
echo "skip on" >&3
wait_for_line_after "$before" '^visible=1 open=1 ' > /dev/null || true
describe_now
if [[ "$(field excluded)" == 1 ]]; then pass "skip on excludes the open window from the Window menu"; else fail "skip on didn't exclude the window: $main_line"; fi
echo "skip off" >&3
sleep 0.3
describe_now
if [[ "$(field excluded)" == 0 ]]; then pass "skip off puts the window back in the Window menu"; else fail "skip off didn't put the window back: $main_line"; fi
stop_example

# 4. Utility changes nothing on macOS: its window has the same settings as the default window.
start_example "$build"
wait_for_main_window
describe_now
default_line="$main_line"
stop_example
start_example "$build" --utility
wait_for_main_window --utility
describe_now
if [[ "$(echo "$main_line" | sed 's/ visible=.*//')" == "$(echo "$default_line" | sed 's/ visible=.*//')" ]]; then
    pass "utility leaves the window's settings as they are on macOS"
else
    fail "utility changed the window's settings: $main_line, default $default_line"
fi
stop_example

# 5. Developer tools open a Web Inspector window.
start_example "$build"
wait_for_main_window
before="$(lines_so_far)"
echo devtools >&3
inspector=""
for ((i = 0; i < 80; i++)); do
    describe_now
    if grep -q '^native title=Web Inspector.*visible=1$' <<< "$(tail -n +"$((before + 1))" "$work/out.txt")"; then
        inspector=yes
        break
    fi
    sleep 0.1
done
if [[ -n "$inspector" ]]; then pass "devtools open a Web Inspector window"; else fail "devtools didn't open a Web Inspector window"; fi
stop_example

finish
