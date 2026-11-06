# Checks that resizing the example's window honours the snapping grid: a resize from the south-east corner and one from the
# north-west corner each end with the edges they moved on the grid of 8 pixels, at the nearest grid line to where the pointer
# put them. The window's rectangle is read from the example's report. Every wait is at most 10 seconds.
#
# The drags are made with mouse_event and SetCursorPos, so the test needs an interactive desktop.
#
# Usage: tests/windows_resize_snapping_test.ps1 [-BuildDir <build-dir>]
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

try {
    Start-Example -BuildDir $BuildDir

    if (Wait-ForLineAfter 0 '^loaded$') { Pass "page loaded" } else { Fail "page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "window is shown" } else { Fail "window never appeared" }
    Test-HarnessAgrees

    $grid = $script:grid

    # 1. South-east resize. The right and bottom edges move by dx and dy. Those are chosen so the unsnapped right edge is 3 pixels past
    #    a grid line and the unsnapped bottom edge is 2 pixels past one, so the snapped edges can only match if they snap.
    $x, $y, $w, $h = Split-Rect (Get-FrameNow)
    $dx = ((((3 - ($x + $w)) % $grid) + $grid) % $grid) + 2 * $grid
    $dy = ((((2 - ($y + $h)) % $grid) + $grid) % $grid) + 2 * $grid
    $unsnappedRight = $x + $w + $dx
    $unsnappedBottom = $y + $h + $dy
    $wantRight = Get-NearestGridLine $unsnappedRight
    $wantBottom = Get-NearestGridLine $unsnappedBottom
    if (($unsnappedRight % $grid -eq 0) -or ($unsnappedBottom % $grid -eq 0)) {
        Fail "setup: the unsnapped edges are already on the grid, so the check would prove nothing"
    }
    Invoke-DragResize ($x + $w - 4) ($y + $h - 4) $dx $dy "se"
    $frame = Wait-ForSettledFrame $x $y $wantRight $wantBottom
    $fx, $fy, $fw, $fh = Split-Rect $frame
    if ($fx -eq $x -and $fy -eq $y) {
        Pass "a south-east resize keeps the window's top-left corner"
    } else {
        Fail "a south-east resize moved the top-left corner from $x,$y to $fx,$fy"
    }
    if ($fx + $fw -eq $wantRight) {
        Pass "the right edge snapped to $wantRight (unsnapped $unsnappedRight)"
    } else {
        Fail "the right edge is at $($fx + $fw), expected the grid line $wantRight (unsnapped $unsnappedRight)"
    }
    if ($fy + $fh -eq $wantBottom) {
        Pass "the bottom edge snapped to $wantBottom (unsnapped $unsnappedBottom)"
    } else {
        Fail "the bottom edge is at $($fy + $fh), expected the grid line $wantBottom (unsnapped $unsnappedBottom)"
    }

    # Let the south-east drag finish before the next one starts.
    Start-Sleep -Milliseconds 50

    # 2. North-west resize from the window as it is now. The left and top edges move by dx and dy, chosen the same way: the unsnapped
    #    left edge is 3 pixels past a grid line and the unsnapped top edge 2 pixels past one.
    $x, $y, $w, $h = Split-Rect $frame
    $dx = -((((($x - 3) % $grid) + $grid) % $grid) + 2 * $grid)
    $dy = -((((($y - 2) % $grid) + $grid) % $grid) + 2 * $grid)
    $unsnappedLeft = $x + $dx
    $unsnappedTop = $y + $dy
    $wantLeft = Get-NearestGridLine $unsnappedLeft
    $wantTop = Get-NearestGridLine $unsnappedTop
    if (($unsnappedLeft % $grid -eq 0) -or ($unsnappedTop % $grid -eq 0)) {
        Fail "setup: the unsnapped edges are already on the grid, so the check would prove nothing"
    }
    Invoke-DragResize ($x + 4) ($y + 4) $dx $dy "nw"
    $frame = Wait-ForSettledFrame $wantLeft $wantTop ($x + $w) ($y + $h)
    $fx, $fy, $fw, $fh = Split-Rect $frame
    if ($fx -eq $wantLeft) {
        Pass "the left edge snapped to $wantLeft (unsnapped $unsnappedLeft)"
    } else {
        Fail "the left edge is at $fx, expected the grid line $wantLeft (unsnapped $unsnappedLeft)"
    }
    if ($fy -eq $wantTop) {
        Pass "the top edge snapped to $wantTop (unsnapped $unsnappedTop)"
    } else {
        Fail "the top edge is at $fy, expected the grid line $wantTop (unsnapped $unsnappedTop)"
    }
    if ($fx + $fw -eq $x + $w -and $fy + $fh -eq $y + $h) {
        Pass "a north-west resize keeps the bottom-right corner"
    } else {
        Fail "a north-west resize moved the bottom-right corner"
    }

    Stop-Example
} finally {
    Remove-Harness
}

Finish
