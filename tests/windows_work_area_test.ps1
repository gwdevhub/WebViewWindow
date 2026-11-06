# Checks that a window's confinement to its monitor's work area holds when it is dragged. A confined window dropped past the bottom
# and right edges is moved back in, and ends exactly on those edges. The same drag without confinement leaves the window past the
# edges, where it was dropped. Turning confinement back on moves a window that is past the edges back in. Every wait is at most
# 10 seconds.
#
# The drags are made with mouse_event and SetCursorPos, so the test needs an interactive desktop.
#
# Usage: tests/windows_work_area_test.ps1 [-BuildDir <build-dir>]
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

# How far past the work area's edges the window is dragged. It has to be more than the snapping grid, so a window that is not
# confined is clearly past the edges.
$overshoot = 40

try {
    Start-Example -BuildDir $BuildDir

    if (Wait-ForLineAfter 0 '^loaded$') { Pass "page loaded" } else { Fail "page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "window is shown" } else { Fail "window never appeared" }
    Test-HarnessAgrees

    # The window's rectangle and the work area it is on, both from the example's report.
    $x, $y, $w, $h = Split-Rect (Get-FrameNow)
    $ax, $ay, $aw, $ah = Split-Rect (Get-AreaNow)
    $right = $ax + $aw
    $bottom = $ay + $ah
    if (($x -ge $ax) -and ($y -ge $ay) -and (($x + $w) -le $right) -and (($y + $h) -le $bottom)) {
        Pass "the window starts inside its work area, $ax,$ay,$aw,$ah"
    } else {
        Fail "the window doesn't start inside its work area"
    }

    # 1. Confined by default. The drag takes the window past the right and bottom edges, so it has to be moved back in.
    Invoke-DragMove ($x + [math]::Floor($w / 2)) ($y + [math]::Floor($h / 2)) ($right + $overshoot - ($x + $w)) ($bottom + $overshoot - ($y + $h))
    $frame = Wait-ForSettledFrame ($right - $w) ($bottom - $h) $right $bottom
    $fx, $fy, $fw, $fh = Split-Rect $frame
    if (($fx + $fw -eq $right) -and ($fy + $fh -eq $bottom)) {
        Pass "a confined window dropped past the bottom-right corner ends on the edges, at $fx,$fy"
    } else {
        Fail "a confined window ends at $fx,$fy with size ${fw}x${fh}, not on the work area's bottom-right edges $right,$bottom"
    }

    # 2. Not confined. The same kind of drag leaves the window past the edges, where it was dropped.
    if (-not (Invoke-CommandThenCheck "confine off" '^visible=1 open=1 ' "shown")) {
        Fail "confine off didn't report the window shown"
    }
    $x, $y, $w, $h = Split-Rect (Get-FrameNow)
    Invoke-DragMove ($x + [math]::Floor($w / 2)) ($y + [math]::Floor($h / 2)) ($right + $overshoot - ($x + $w)) ($bottom + $overshoot - ($y + $h))
    Start-Sleep -Milliseconds 500
    $fx, $fy, $fw, $fh = Split-Rect (Get-FrameNow)
    # The window ends past both edges. It doesn't have to reach the full overshoot: the window manager may hold it short of the pointer.
    if (($fx + $fw -gt $right) -and ($fy + $fh -gt $bottom)) {
        Pass "an unconfined window dropped past the bottom-right corner stays past it, at $fx,$fy"
    } else {
        Fail "an unconfined window was moved back in: it ends at $fx,$fy with size ${fw}x${fh}"
    }

    # 3. Confined again. A window that is past the edges is moved back in straight away.
    if (-not (Invoke-CommandThenCheck "confine on" '^visible=1 open=1 ' "shown")) {
        Fail "confine on didn't report the window shown"
    }
    $frame = Wait-ForSettledFrame ($right - $w) ($bottom - $h) $right $bottom
    $fx, $fy, $fw, $fh = Split-Rect $frame
    if (($fx + $fw -eq $right) -and ($fy + $fh -eq $bottom)) {
        Pass "confining a window that is past the edges moves it back in"
    } else {
        Fail "confining a window left it at $fx,$fy, not on the work area's bottom-right edges $right,$bottom"
    }

    Stop-Example
} finally {
    Remove-Harness
}

Finish
