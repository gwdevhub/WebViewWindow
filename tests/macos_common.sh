# Shared helpers for the macOS tests of examples/. Source this file; it doesn't run anything itself.
#
# A test starts the example with start_example, sends it commands on fd 3 (command_then_check, send), reads its state lines from
# out.txt, and ends it with stop_example. Every wait gives up after 10 seconds at most. The window is checked against the system's
# own window list (macos_query.js), and the pointer is driven with macos_mouse.js, so the tests see what a user would see.
#
# The macOS tests need a logged-in desktop session (not a headless SSH session), since they need a window server.

title="WebViewWindow Example"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
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

# Builds the example unless a build directory is given, then starts it with its commands on fd 3. Usage: start_example [build-dir] [args]
start_example() {
    local build="${1:-}"
    shift || true
    if [[ -z "$build" ]]; then
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
    # A test can start the example more than once, so the previous run's command pipe is replaced.
    rm -f "$work/commands"
    mkfifo "$work/commands"
    mkdir -p "$work/home"
    touch "$work/out.txt"
    # The example's home is a scratch folder, so no settings are touched.
    HOME="$work/home" "$bin" "$@" < "$work/commands" > "$work/out.txt" 2> "$work/err.txt" &
    pid=$!
    exec 3> "$work/commands"
}

# Ends the example with quit, and checks that it exits with status 0.
stop_example() {
    echo quit >&3
    exec 3>&-
    if wait "$pid"; then
        pass "quit stops the example with exit status 0"
    else
        fail "the example didn't exit cleanly"
    fi
    pid=""
}

# Finishes the test: prints the result and keeps the output when a check failed.
finish() {
    if [[ "$failures" -eq 0 ]]; then
        echo "All checks passed."
    else
        keep_work=1
        echo "$failures check(s) failed. Output is in $work/out.txt and $work/err.txt."
        exit 1
    fi
}

# Waits until the output has a line matching the pattern after the first <before> lines.
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

# Waits until the example has reported the state, from the first line that matches the pattern after the first <before> lines.
# Usage: wait_for_state_after <before> <pattern>
wait_for_state_after() {
    wait_for_line_after "$1" "$2"
}

# The most recent state line.
last_state() {
    grep "^visible=" "$work/out.txt" | tail -n 1
}

# The example's on-screen windows, as the window server reports them: a JSON list of {"bounds":[x,y,width,height]}.
os_windows() {
    osascript -l JavaScript "$root/tests/macos_query.js" windows "$pid" 2>/dev/null || echo "[]"
}

# Whether the example's window is on screen, as the window server reports it. Any level counts (always on top and keep below move the
# window off the normal level), except the tray icon's (25) and the menus' (101 and above).
window_shown() {
    [[ -n "$(layer_bounds_any)" ]]
}

# The bounds of the example's first on-screen window that isn't a tray icon or a menu, or nothing. Used by window_shown.
layer_bounds_any() {
    python3 -c '
import json, sys
for window in json.loads(sys.stdin.read()):
    layer = window["layer"]
    if window["onscreen"] and window["bounds"][2] > 0 and layer != 25 and layer < 100:
        print(*window["bounds"])
        break
' <<< "$(os_windows_all)"
}

# Waits until the window is shown or hidden on screen.
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

# Sends a command to the example and waits for the state it reports, and the window to match. Usage: command_then_check cmd state window
command_then_check() {
    local cmd="$1" state="$2" window="$3" before
    before="$(lines_so_far)"
    echo "$cmd" >&3
    wait_for_line_after "$before" "$state" && wait_for_window "$window"
}

# The window's rectangle as "x,y,width,height", from a report of the example's state.
frame_now() {
    local before
    before="$(lines_so_far)"
    echo "report" >&3
    wait_for_line_after "$before" '^visible=' > /dev/null
    last_state | sed -n 's/.*frame=\([^ ]*\).*/\1/p'
}

# The window's rectangle as the window server has it, as "x,y,width,height". Waits for the window to be on screen.
os_frame_now() {
    local bounds=""
    for ((i = 0; i < 100; i++)); do
        bounds="$(os_windows | sed -n 's/.*"bounds":\[\([^]]*\)\].*/\1/p' | head -n 1)"
        if [[ -n "$bounds" ]]; then
            break
        fi
        sleep 0.1
    done
    echo "$bounds" | tr -d ' '
}

# Moves the pointer to a point, presses the button, and waits for the example to start its drag.
press_at() {
    osascript -l JavaScript "$root/tests/macos_mouse.js" move "$1" "$2" > /dev/null
    osascript -l JavaScript "$root/tests/macos_mouse.js" down "$1" "$2" > /dev/null
}

# Moves the pointer by (dx, dy) with the button held, then releases it at that point.
drag_to() {
    local x="$1" y="$2"
    osascript -l JavaScript "$root/tests/macos_mouse.js" drag "$x" "$y" > /dev/null
    sleep 0.3
    osascript -l JavaScript "$root/tests/macos_mouse.js" up "$x" "$y" > /dev/null
}

# Presses in the window, starts a move, moves the pointer by (dx, dy), and releases it. The pointer must end on the screen.
drag_move() {
    local px="$1" py="$2" dx="$3" dy="$4"
    press_at "$px" "$py"
    sleep 0.2
    echo "move" >&3
    sleep 0.3
    drag_to $((px + dx)) $((py + dy))
}

# Presses on a window edge, starts a resize from that edge, moves the pointer by (dx, dy), and releases it.
drag_resize() {
    local px="$1" py="$2" dx="$3" dy="$4" edge="$5"
    press_at "$px" "$py"
    sleep 0.2
    echo "resize $edge" >&3
    sleep 0.3
    drag_to $((px + dx)) $((py + dy))
}

# The work area as "x,y,width,height", from the same report. Usage: area_now
area_now() {
    last_state | sed -n 's/.*area=\([^ ]*\).*/\1/p'
}

# The display's backing scale. Snapping is to a grid of 8 device pixels, which is 8 / scale points.
scale="$(osascript -l JavaScript "$root/tests/macos_query.js" scale 2>/dev/null || echo 1)"
scale="${scale%.*}"
grid=$((8 / scale))

# The grid line nearest to a positive coordinate, rounding halves up.
nearest() {
    echo $(((($1 + grid / 2) / grid) * grid))
}

# Waits until the window reports the expected edges. Usage: settle left top right bottom. Prints the frame it last saw.
settle() {
    local want_left="$1" want_top="$2" want_right="$3" want_bottom="$4" frame fx fy fw fh
    for ((i = 0; i < 20; i++)); do
        frame="$(frame_now)"
        IFS=, read -r fx fy fw fh <<< "$frame"
        if [[ "$fx" == "$want_left" && "$fy" == "$want_top" && $((fx + fw)) == "$want_right" && $((fy + fh)) == "$want_bottom" ]]; then
            break
        fi
        sleep 0.1
    done
    echo "$frame"
}

# The example's windows as the window server has them, including the tray icon's and a menu's. Usage: os_windows_all
os_windows_all() {
    osascript -l JavaScript "$root/tests/macos_query.js" all "$pid" 2>/dev/null || echo "[]"
}

# The bounds, as "x y width height", of the first of the example's windows on the given layer, or nothing when there's none.
# Usage: layer_bounds <layer>
layer_bounds() {
    python3 -c '
import json, sys
layer = int(sys.argv[1])
for window in json.loads(sys.stdin.read()):
    if window["layer"] == layer and window["onscreen"]:
        print(*window["bounds"])
        break
' "$1" <<< "$(os_windows_all)"
}

# Clicks the centre of a rectangle given as "x y width height". Usage: click_rect "x y w h" [left|right]
click_rect() {
    local rect="$1" button="${2:-left}" x y w h
    read -r x y w h <<< "$rect"
    local cx=$((x + w / 2)) cy=$((y + h / 2))
    osascript -l JavaScript "$root/tests/macos_mouse.js" move "$cx" "$cy" > /dev/null
    if [[ "$button" == right ]]; then
        osascript -l JavaScript "$root/tests/macos_mouse.js" rightdown "$cx" "$cy" > /dev/null
        osascript -l JavaScript "$root/tests/macos_mouse.js" rightup "$cx" "$cy" > /dev/null
    else
        osascript -l JavaScript "$root/tests/macos_mouse.js" down "$cx" "$cy" > /dev/null
        osascript -l JavaScript "$root/tests/macos_mouse.js" up "$cx" "$cy" > /dev/null
    fi
}

# Waits up to 3 seconds for a window of the example on the given layer to be on screen, and prints its bounds. Usage: wait_for_layer <layer>
wait_for_layer() {
    local bounds=""
    for ((i = 0; i < 30; i++)); do
        bounds="$(layer_bounds "$1")"
        if [[ -n "$bounds" ]]; then
            break
        fi
        sleep 0.1
    done
    echo "$bounds"
}

# Waits up to 3 seconds for no window of the example on the given layer. Returns 0 when there's none.
wait_for_no_layer() {
    for ((i = 0; i < 30; i++)); do
        if [[ -z "$(layer_bounds "$1")" ]]; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Brings the window to the front, so a press on it reaches it rather than a window of another app that overlaps it.
focus_window() {
    command_then_check present '^visible=1 open=1 ' shown || fail "present didn't bring the window forward"
    sleep 0.3
}
