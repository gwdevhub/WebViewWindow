#!/usr/bin/env bash
# Checks how the example answers a page's microphone request on macOS. The page is served over http://localhost, which counts as a
# secure origin, so WKWebView offers the microphone to it.
#
# Without --allow-permissions the host has no answer, so WebKit's own prompt applies: nobody answers it here, so the request stays
# pending and the microphone is not granted. With --allow-permissions the host allows it, and the request is granted.
#
# Notifications are not checked: WKWebView has no notification permission for the host to answer, so the notification request is
# denied by WebKit on macOS whichever way the host is set.
#
# Usage: tests/macos_permission_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs python3 for the local web server, and a logged-in desktop session.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"

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
build="${1:-}"

# Starts the example with the given options, asks it to probe the page, and sets probe_line to the probe's report. The example is
# stopped again, so each run starts from the same state.
probe_with() {
    probe_line=""
    start_example "$build" --url "$url" "$@"
    if ! wait_for_line_after 0 '^loaded$'; then
        fail "the page never loaded"
        stop_example
        return 1
    fi
    echo probe >&3
    # The probe answers within about ten seconds, since a request nobody answers is reported as pending after five.
    if wait_for_line_after 0 '^probe '; then
        probe_line="$(grep '^probe ' "$work/out.txt" | tail -n 1)"
    else
        fail "the page never reported its probe"
    fi
    permission_line="$(grep '^permission ' "$work/out.txt" | tail -n 1 || true)"
    stop_example
}

# 1. The platform's default: the host has no answer, so WebKit prompts, and the microphone is not granted.
probe_with || true
if [[ "$permission_line" == "permission microphone default" ]]; then
    pass "without a host answer, the microphone request is left to WebKit's prompt"
else
    fail "without a host answer, the example reported: '$permission_line'"
fi
# Whether WebKit grants the request also depends on macOS's own microphone permission for the app. The library's part is the host's
# answer, checked above, so a grant here is reported as a note rather than a failure.
if [[ "$probe_line" == *'"microphone":"granted"'* ]]; then
    echo "NOTE: macOS already holds the microphone permission for this app, so WebKit granted the request without a prompt."
else
    pass "without a host answer, the microphone is not granted"
fi

# 2. The host allows: the microphone request is granted.
probe_with --allow-permissions || true
if [[ "$permission_line" == "permission microphone allowed" ]]; then
    pass "with --allow-permissions, the host allows the microphone request"
else
    fail "with --allow-permissions, the example reported: '$permission_line'"
fi
if [[ "$probe_line" == *'"microphone":"granted"'* ]]; then
    pass "with --allow-permissions, the microphone request is granted"
else
    fail "with --allow-permissions, the microphone request wasn't granted: $probe_line"
fi

finish
