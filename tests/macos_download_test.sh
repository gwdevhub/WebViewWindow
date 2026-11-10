#!/usr/bin/env bash
# Checks that a download from a page is saved where the host's download chooser says, on macOS. The page is served over
# http://localhost, with a link that has a download attribute. The example's download command clicks it, and the file is
# checked on disk. Every wait is at most 10 seconds.
#
# Usage: tests/macos_download_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs python3 for the local web server.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"

port=8765
site="$work/site"
downloads="$work/downloads"
mkdir -p "$site" "$downloads"
printf 'hello from the download test\n' > "$site/hello.txt"
cat > "$site/download.html" <<'HTML'
<!doctype html><html><body>download
<a id="link" href="hello.txt" download>get the file</a>
<script>
(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
  .postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));
</script></body></html>
HTML

(cd "$site" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; cleanup' EXIT
sleep 1

start_example "${1:-}" --url "http://localhost:$port/download.html" --download-folder "$downloads"
if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never loaded"; fi

echo download >&3
saved="$downloads/hello.txt"
for ((i = 0; i < 100; i++)); do
    if [[ -f "$saved" ]] && [[ "$(cat "$saved")" == "hello from the download test" ]]; then
        break
    fi
    sleep 0.1
done
if [[ -f "$saved" ]] && [[ "$(cat "$saved")" == "hello from the download test" ]]; then
    pass "the download is saved to the folder the chooser picked, under the suggested name"
else
    fail "the download didn't arrive at $saved"
    ls -la "$downloads" >&2 || true
fi

stop_example
finish
