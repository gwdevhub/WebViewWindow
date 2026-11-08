# Shared helpers for the Linux tests of examples/. Source this file; it doesn't run anything itself.
#
# A test starts the example with start_example, sends it commands on fd 3 (command_then_check, send), reads its state lines from
# out.txt, and ends it with stop_example. Every wait gives up after 10 seconds at most.

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

# Builds the example unless a build directory is given, then starts it with its commands on fd 3. Usage: start_example [build-dir]
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

# Whether the window is on screen, as the window manager reports it.
window_shown() {
    xdotool search --onlyvisible --name "^${title}$" 2>/dev/null | head -n 1 | grep -q .
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

# Presses in the window, starts a move, moves the pointer by (dx, dy), and releases it. The pointer must end on the screen.
drag_move() {
    local px="$1" py="$2" dx="$3" dy="$4"
    xdotool mousemove --sync "$px" "$py"
    xdotool mousedown 1
    sleep 0.2
    echo "move" >&3
    sleep 0.3
    xdotool mousemove --sync $((px + dx)) $((py + dy))
    sleep 0.3
    xdotool mouseup 1
}

# The work area as "x,y,width,height", from the same report. Usage: area_now
area_now() {
    last_state | sed -n 's/.*area=\([^ ]*\).*/\1/p'
}

# The snapping grid, in pixels. Windows snaps the edges a move or resize changes to it.
grid=8

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
