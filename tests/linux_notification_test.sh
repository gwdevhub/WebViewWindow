#!/usr/bin/env bash
# Checks that a page's notification reaches the desktop's notification service on Linux. The example is allowed notifications, the
# page shows one through its Notification API, and the test watches the session bus for the Notify call the desktop receives.
#
# Skipped (not failed) when there's no notification service on the session bus, since there's nothing to receive it.
#
# Usage: tests/linux_notification_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs python3 for the local web server, and dbus-monitor and dbus-send.
set -euo pipefail

source "$(dirname "$0")/linux_common.sh"

if ! dbus-send --session --print-reply --dest=org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications.GetServerInformation >/dev/null 2>&1; then
    echo "SKIP: no notification service on the session bus"
    exit 0
fi

port=8766
site="$work/site"
mkdir -p "$site"
cat > "$site/probe.html" <<'HTML'
<!doctype html><html><body>notification
<script>
(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
  .postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));
</script></body></html>
HTML

(cd "$site" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server_pid=$!
watch_pid=""
trap 'kill "$server_pid" 2>/dev/null || true; [[ -n "$watch_pid" ]] && kill "$watch_pid" 2>/dev/null || true; cleanup' EXIT
sleep 1

# Watches for the Notify call, writing what the bus sees to a file.
dbus-monitor "interface='org.freedesktop.Notifications',member='Notify'" > "$work/bus.txt" 2>&1 &
watch_pid=$!
sleep 1

start_example "${1:-}" --url "http://localhost:$port/probe.html" --allow-permissions
if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never loaded"; fi

echo notify >&3
arrived=0
for ((i = 0; i < 100; i++)); do
    if grep -q 'WebViewWindow test' "$work/bus.txt" && grep -q 'Shown by the page' "$work/bus.txt"; then
        arrived=1
        break
    fi
    sleep 0.1
done
if [[ "$arrived" -eq 1 ]]; then
    pass "the desktop receives the page's notification, with its title and body"
else
    fail "the desktop didn't receive the page's notification"
fi

stop_example
finish
