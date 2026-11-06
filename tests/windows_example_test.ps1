# Drives the example on the desktop and checks the window: it appears once its page has loaded, hide and show work, present shows the
# window again, and quit exits cleanly. Every wait is at most 10 seconds.
#
# The cooldown (a hidden window freeing its web view after two minutes) is not checked here: it can't finish inside 10 seconds.
#
# Usage: tests/windows_example_test.ps1 [-BuildDir <build-dir>]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

try {
    Start-Example -BuildDir $BuildDir

    # 1. The page loads, and the window appears only then.
    if (Wait-ForLineAfter 0 '^loaded$') { Pass "page loaded" } else { Fail "page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "window is shown after its page loads" } else { Fail "window never appeared" }

    # 2. hide hides the window and keeps its web view.
    if (Invoke-CommandThenCheck "hide" '^visible=0 open=1 ' "hidden") {
        Pass "hide hides the window and keeps its web view"
    } else {
        Fail "hide didn't hide the window, or freed its web view at once"
    }

    # 3. show brings it back.
    if (Invoke-CommandThenCheck "show" '^visible=1 open=1 ' "shown") {
        Pass "show shows the hidden window again"
    } else {
        Fail "show didn't show the window"
    }

    # 4. present shows the window again.
    if (Invoke-CommandThenCheck "present" '^visible=1 open=1 ' "shown") {
        Pass "present shows the window"
    } else {
        Fail "present didn't show the window"
    }

    # 5. quit stops the event loop, and the example exits cleanly.
    Stop-Example
} finally {
    Remove-Harness
}

Finish
