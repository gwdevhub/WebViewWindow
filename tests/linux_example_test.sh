#!/usr/bin/env bash
# Drives the example on the current X display and checks the window: it appears once its page has loaded, hide and show work,
# present shows the window again, and quit exits cleanly. Every wait is at most 10 seconds.
#
# The cooldown (a hidden window freeing its web view after two minutes) is not checked here: it can't finish inside 10 seconds.
#
# Usage: tests/linux_example_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built into a scratch folder first.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
title="WebViewWindow Example"
pid=""
failures=0
keep_work=0

cleanup() {
    exec 3>&- 2>/dev/null || true
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
    if [[ "$keep_work" -eq 0 ]]; then
        rm -rf "$work"
    fi
}
trap cleanup EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# Waits until the output has a line matching the pattern after the first <before> lines. Gives up after 10 seconds.
wait_for_line_after() {
    local before="$1" pattern="$2"
    for ((i = 0; i < 100; i++)); do
        if tail -n +"$((before + 1))" "$work/out.txt" 2>/dev/null | grep -qE "$pattern"; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

lines_so_far() {
    wc -l < "$work/out.txt"
}

# Whether the window is on screen, as the window manager reports it.
window_shown() {
    xdotool search --onlyvisible --name "^${title}$" 2>/dev/null | head -n 1 | grep -q .
}

# Waits until the window is shown or hidden on screen. Gives up after 10 seconds.
wait_for_window() {
    local want="$1"
    for ((i = 0; i < 100; i++)); do
        if [[ "$want" == shown ]] && window_shown; then
            return 0
        fi
        if [[ "$want" == hidden ]] && ! window_shown; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Sends a command to the example, then waits for the state it reports and the window to match. Usage: command state-pattern window
command_then_check() {
    local cmd="$1" state="$2" window="$3" before
    before="$(lines_so_far)"
    echo "$cmd" >&3
    wait_for_line_after "$before" "$state" && wait_for_window "$window"
}

if [[ $# -ge 1 ]]; then
    build="$1"
else
    build="$work/build"
    if ! cmake -S "$root" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DWEBVIEW_WINDOW_BUILD_EXAMPLE=ON > "$work/configure.log" 2>&1; then
        cat "$work/configure.log"
        echo "FAIL: configure"
        keep_work=1
        exit 1
    fi
    if ! cmake --build "$build" > "$work/build.log" 2>&1; then
        cat "$work/build.log"
        echo "FAIL: build"
        keep_work=1
        exit 1
    fi
fi
bin="$build/examples/webview_window_example"
if [[ ! -x "$bin" ]]; then
    echo "FAIL: no example at $bin"
    exit 1
fi

mkfifo "$work/commands"
mkdir -p "$work/home"
touch "$work/out.txt"

# The example reads commands from the FIFO. Its home is a scratch folder, so no settings are touched.
HOME="$work/home" "$bin" < "$work/commands" > "$work/out.txt" 2> "$work/err.txt" &
pid=$!
exec 3> "$work/commands"

# 1. The page loads, and the window appears only then.
if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi
if wait_for_window shown; then pass "window is shown after its page loads"; else fail "window never appeared"; fi

# 2. hide hides the window and keeps its web view.
if command_then_check hide '^visible=0 open=1$' hidden; then
    pass "hide hides the window and keeps its web view"
else
    fail "hide didn't hide the window, or freed its web view at once"
fi

# 3. show brings it back.
if command_then_check show '^visible=1 open=1$' shown; then
    pass "show shows the hidden window again"
else
    fail "show didn't show the window"
fi

# 4. present shows the window again.
if command_then_check present '^visible=1 open=1$' shown; then
    pass "present shows the window"
else
    fail "present didn't show the window"
fi

# 5. quit stops the event loop, and the example exits cleanly.
echo quit >&3
exec 3>&-
if wait "$pid"; then
    pass "quit stops the example with exit status 0"
else
    fail "the example didn't exit cleanly"
fi
pid=""

if [[ "$failures" -eq 0 ]]; then
    echo "All checks passed."
else
    keep_work=1
    echo "$failures check(s) failed. Output is in $work/out.txt and $work/err.txt."
    exit 1
fi
