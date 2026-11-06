# Checks that dragging the example's window honours the snapping grid: when the drag ends, the window's top-left corner sits on the
# nearest grid line to where the pointer put it, and its size is unchanged. The window's rectangle is read from the example's
# report. Every wait is at most 10 seconds.
#
# The drag is made with mouse_event and SetCursorPos, so the test needs an interactive desktop.
#
# Usage: tests/windows_move_snapping_test.ps1 [-BuildDir <build-dir>]
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

try {
    Start-Example -BuildDir $BuildDir

    if (Wait-ForLineAfter 0 '^loaded$') { Pass "page loaded" } else { Fail "page never reported loaded" }
    if (Wait-ForWindow "shown") { Pass "window is shown" } else { Fail "window never appeared" }
    Test-HarnessAgrees

    # The window's position is chosen so the drag leaves its left edge 3 pixels past a grid line and its top edge 2 pixels past one,
    # so the snapped position can only match if the drop snaps.
    $x, $y, $w, $h = Split-Rect (Get-FrameNow)
    $grid = $script:grid
    $dx = ((((3 - $x) % $grid) + $grid) % $grid) + 2 * $grid
    $dy = ((((2 - $y) % $grid) + $grid) % $grid) + 2 * $grid
    $unsnappedLeft = $x + $dx
    $unsnappedTop = $y + $dy
    $wantLeft = Get-NearestGridLine $unsnappedLeft
    $wantTop = Get-NearestGridLine $unsnappedTop
    if (($unsnappedLeft % $grid -eq 0) -or ($unsnappedTop % $grid -eq 0)) {
        Fail "setup: the unsnapped edges are already on the grid, so the check would prove nothing"
    }

    Invoke-DragMove ($x + [math]::Floor($w / 2)) ($y + [math]::Floor($h / 2)) $dx $dy
    $frame = Wait-ForSettledFrame $wantLeft $wantTop ($wantLeft + $w) ($wantTop + $h)
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
    if ($fw -eq $w -and $fh -eq $h) {
        Pass "a move keeps the window's size"
    } else {
        Fail "a move changed the window's size from ${w}x${h} to ${fw}x${fh}"
    }

    Stop-Example
} finally {
    Remove-Harness
}

Finish
