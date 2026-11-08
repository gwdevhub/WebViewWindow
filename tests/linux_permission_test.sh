#!/usr/bin/env bash
# Checks how the example answers a page's permission requests on Linux. The page is served over http://localhost, since WebKitGTK
# only offers the microphone and notifications to a secure origin.
#
# Without --allow-permissions the host has no answer, so the platform's default applies: the microphone is refused and the page
# starts with notifications denied. With --allow-permissions the host allows them: the microphone request is granted and the page
# starts with notifications granted. Every wait is at most 10 seconds.
#
# Usage: tests/linux_permission_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs python3 for the local web server.
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

port=8765
site="$work/site"
mkdir -p "$site"
cat > "$site/probe.html" <<'HTML'
<!doctype html><html><body>probe
<script>
(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
  .postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));
</script></body></html>
HTML

(cd "$site" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; cleanup' EXIT
sleep 1

url="http://localhost:$port/probe.html"

# Starts the example with the given options, asks it to probe the page, and sets probe_line to the probe's report. The example is
# stopped again, so each run starts from the same state.
probe_with() {
    probe_line=""
    start_example "${build:-}" --url "$url" "$@"
    if ! wait_for_line_after 0 '^loaded$'; then
        fail "the page never loaded"
        stop_example
        return 1
    fi
    echo probe >&3
    if wait_for_line_after 0 '^probe '; then
        probe_line="$(grep '^probe ' "$work/out.txt" | tail -n 1)"
    else
        fail "the page never reported its probe"
    fi
    stop_example
}

build="${1:-}"

# 1. The platform's default: the microphone is refused, and notifications are not allowed.
probe_with || true
line="$probe_line"
if [[ "$line" == *'"notificationBefore":"default"'* ]]; then
    pass "without a host answer, notifications start at the platform's default"
else
    fail "without a host answer, notifications didn't start at the default: $line"
fi
if [[ "$line" == *'"microphone":"NotAllowedError"'* ]]; then
    pass "without a host answer, the microphone request is refused"
else
    fail "without a host answer, the microphone request wasn't refused: $line"
fi

# 2. The host allows: the microphone request is granted, and notifications are granted for the page's origin.
probe_with --allow-permissions || true
line="$probe_line"
if [[ "$line" == *'"notificationBefore":"granted"'* ]]; then
    pass "with --allow-permissions, notifications are granted for the page's origin"
else
    fail "with --allow-permissions, notifications weren't granted: $line"
fi
if [[ "$line" == *'"microphone":"granted"'* ]]; then
    pass "with --allow-permissions, the microphone request is granted"
else
    fail "with --allow-permissions, the microphone request wasn't granted: $line"
fi

finish
