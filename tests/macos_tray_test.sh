#!/usr/bin/env bash
# Checks the tray icon on macOS. The icon appears in the menu bar, a click on it reports "tray activate", a right click opens its menu,
# choosing the Ping item reports "tray ping", and untray removes the icon. The icon and the menu are found in the window server's list,
# which the example owns. Every wait is at most 10 seconds.
#
# The icon needs an application icon, so the test passes one. Usage: tests/macos_tray_test.sh [build-dir]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
#   Needs a logged-in desktop session. The test writes a small PNG icon into its work folder.
set -euo pipefail

source "$(dirname "$0")/macos_common.sh"

export WEBVIEW_EXAMPLE_NO_DIALOGS=1
python3 - "$work/icon.png" <<'PY'
import struct, sys, zlib
w = h = 32
rows = b''.join(b'\x00' + b''.join(bytes([40, 120, 200, 255]) for _ in range(w)) for _ in range(h))
def chunk(tag, data): return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))
PY

start_example "${1:-}" --icon "$work/icon.png"

if wait_for_line_after 0 '^loaded$'; then pass "page loaded"; else fail "page never reported loaded"; fi

# 1. The tray icon appears, and the menu bar holds it.
before="$(lines_so_far)"
echo tray >&3
if wait_for_line_after "$before" '^tray shown=1$'; then
    pass "the tray icon is shown"
else
    fail "the tray icon wasn't shown: $(tail -n 1 "$work/out.txt")"
fi
icon="$(wait_for_layer 25)"
if [[ -n "$icon" ]]; then
    pass "the menu bar holds the icon, at $icon"
else
    fail "no status item window of the example is on screen"
fi

# 2. A click on the icon runs its activate action.
before="$(lines_so_far)"
click_rect "$icon" left
if wait_for_line_after "$before" '^tray activate$'; then
    pass "a click on the icon reports tray activate"
else
    fail "a click on the icon didn't report tray activate"
fi

# 3. A right click opens the menu, and the Ping item runs its action. The menu is the window on layer 101 (the pop-up menu level).
click_rect "$icon" right
menu="$(wait_for_layer 101)"
if [[ -n "$menu" ]]; then
    pass "a right click opens the menu, at $menu"
else
    fail "a right click didn't open the menu"
fi
if [[ -n "$menu" ]]; then
    read -r mx my mw mh <<< "$menu"
    # The Ping item is the menu's only row, at its top.
    before="$(lines_so_far)"
    click_rect "$mx $((my + 8)) $mw $((mh - 16))" left
    if wait_for_line_after "$before" '^tray ping$'; then
        pass "choosing the Ping item reports tray ping"
    else
        fail "choosing the Ping item didn't report tray ping"
    fi
fi

# 4. untray removes the icon from the menu bar.
before="$(lines_so_far)"
echo untray >&3
if wait_for_line_after "$before" '^tray removed$'; then
    if wait_for_no_layer 25; then pass "untray removes the icon from the menu bar"; else fail "the icon is still in the menu bar"; fi
else
    fail "untray didn't report tray removed"
fi

stop_example
finish
