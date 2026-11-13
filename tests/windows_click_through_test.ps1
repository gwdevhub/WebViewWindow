# Checks that a window opened with clickThrough passes the pointer through to the windows beneath it. The pointer is moved over the
# middle of the example's window, and the top-level window that hit testing finds there must not be the example's. The control runs
# the same check without --click-through, where the example's window must be the one under the pointer. Every wait is at most 10
# seconds.
#
# The pointer is moved with SetCursorPos, so the test needs an interactive desktop.
#
# Usage: tests/windows_click_through_test.ps1 [-BuildDir <build-dir>]
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

# The pointer's target: the middle of the example's frame, from its report.
function Get-PointerTarget {
    $x, $y, $w, $h = Split-Rect (Get-FrameNow)
    return @(($x + [math]::Floor($w / 2)), ($y + [math]::Floor($h / 2)))
}

try {
    # Both runs use one build: the given build directory, or the one Start-Example makes in the work folder.
    $build = if ($BuildDir) { $BuildDir } else { Join-Path $script:work "build" }

    Start-Example -BuildDir $BuildDir -Arguments @("--click-through")

    if (Wait-ForLineAfter 0 '^loaded$') { Pass "page loaded" } else { Fail "page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "window is shown" } else { Fail "window never appeared" }

    $px, $py = Get-PointerTarget
    [WebViewTestNative]::MovePointer($px, $py)
    Start-Sleep -Milliseconds 200
    $own = Get-ExampleWindow
    $under = [WebViewTestNative]::TopLevelAt($px, $py)
    if (($under -ne [IntPtr]::Zero) -and (-not $under.Equals($own))) {
        Pass "with --click-through, the pointer over the window reaches the window beneath it"
    } else {
        Fail "with --click-through, the pointer over the window reached the example's window: under=$under own=$own"
    }
    Stop-Example

    # The control: the same window without clickThrough takes the pointer itself.
    Start-Example -BuildDir $build

    if (Wait-ForLineAfter 0 '^loaded$') { Pass "control page loaded" } else { Fail "control page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "control window is shown" } else { Fail "control window never appeared" }

    $px, $py = Get-PointerTarget
    [WebViewTestNative]::MovePointer($px, $py)
    Start-Sleep -Milliseconds 200
    $own = Get-ExampleWindow
    $under = [WebViewTestNative]::TopLevelAt($px, $py)
    if (($own -ne [IntPtr]::Zero) -and $under.Equals($own)) {
        Pass "without --click-through, the example's window is under the pointer"
    } else {
        Fail "without --click-through, the window under the pointer is $under, not the example's $own"
    }
    Stop-Example
} finally {
    Remove-Harness
}

Finish
