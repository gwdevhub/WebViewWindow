# Checks the cooldown: a hidden window keeps its web view until the cooldown ends, then frees it, and a window that is shown again
# within the cooldown keeps it. The example runs with a one second cooldown, so the test finishes within 10 seconds.
#
# Usage: tests/windows_cooldown_test.ps1 [-BuildDir <build-dir>]
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

$cooldownMs = 1000
function Wait-PastCooldown {
    Start-Sleep -Milliseconds 1500
}

try {
    Start-Example -BuildDir $BuildDir -Arguments @("--cooldown-ms", "$cooldownMs")

    if (Wait-ForLineAfter 0 '^loaded$') { Pass "page loaded" } else { Fail "page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "window is shown" } else { Fail "window never appeared" }

    # 1. Hidden, the window keeps its web view straight after the hide.
    if (Invoke-CommandThenCheck "hide" '^visible=0 open=1 ' "hidden") {
        Pass "a hidden window keeps its web view while the cooldown runs"
    } else {
        Fail "hide didn't hide the window, or freed its web view at once"
    }

    # 2. After the cooldown, the web view is freed.
    Wait-PastCooldown
    if (Invoke-CommandThenCheck "report" '^visible=0 open=0 frame=none ' "hidden") {
        Pass "a hidden window frees its web view when the cooldown ends"
    } else {
        Fail "a hidden window still has its web view after the cooldown"
    }

    # 3. A freed window opens again when it's shown.
    if (Invoke-CommandThenCheck "show" '^visible=1 open=1 ' "shown") {
        Pass "show opens a window whose web view was freed"
    } else {
        Fail "show didn't open the freed window"
    }

    # 4. Shown again within the cooldown, the window keeps its web view past the cooldown's end.
    if (-not (Invoke-CommandThenCheck "hide" '^visible=0 open=1 ' "hidden")) { Fail "hide before the cancel check didn't hide the window" }
    Start-Sleep -Milliseconds 300
    if (-not (Invoke-CommandThenCheck "show" '^visible=1 open=1 ' "shown")) { Fail "show within the cooldown didn't show the window" }
    Wait-PastCooldown
    if (Invoke-CommandThenCheck "report" '^visible=1 open=1 ' "shown") {
        Pass "a show within the cooldown cancels it: the window keeps its web view"
    } else {
        Fail "the cooldown freed the web view of a window that was shown again"
    }

    Stop-Example
} finally {
    Remove-Harness
}

Finish
