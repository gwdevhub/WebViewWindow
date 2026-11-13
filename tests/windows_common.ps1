# Shared helpers for the Windows tests of examples/. Dot-source this file; it doesn't run anything itself.
#
# A test starts the example with Start-Example, sends it commands on its standard input (Send-Command, Invoke-CommandThenCheck),
# reads its state lines from out.txt, and ends it with Stop-Example. Every wait gives up after 10 seconds at most. A test runs its
# checks inside try, calls Remove-Harness in finally, and ends with Finish.

$script:title = "WebViewWindow Example"
$script:root = Split-Path -Parent $PSScriptRoot
$script:work = Join-Path ([System.IO.Path]::GetTempPath()) ("webview-test-" + [guid]::NewGuid().ToString("N"))
$script:outputPath = Join-Path $script:work "out.txt"
$script:errorPath = Join-Path $script:work "err.txt"
$script:process = $null
$script:stdin = $null
$script:failures = 0
New-Item -ItemType Directory -Path $script:work | Out-Null

if (-not ("WebViewTestNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public delegate bool WebViewTestEnumProc(IntPtr window, IntPtr parameter);

public static class WebViewTestNative {
    [StructLayout(LayoutKind.Sequential)]
    private struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(WebViewTestEnumProc callback, IntPtr parameter);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int maxCount);
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out RECT rect);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")]
    private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")]
    private static extern IntPtr GetAncestor(IntPtr window, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT {
        public int X;
        public int Y;
    }

    // The top-level window of a process with the title, shown or hidden, or IntPtr.Zero.
    public static IntPtr FindWindow(uint processId, string title) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr window, IntPtr parameter) {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner != processId) {
                return true;
            }
            StringBuilder text = new StringBuilder(256);
            GetWindowText(window, text, text.Capacity);
            if (text.ToString() == title) {
                found = window;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    public static bool IsShown(IntPtr window) {
        return IsWindowVisible(window);
    }

    // The window's rectangle on the screen, as x, y, width, height.
    public static int[] FrameOf(IntPtr window) {
        RECT rect;
        GetWindowRect(window, out rect);
        return new int[] { rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top };
    }

    public static void MovePointer(int x, int y) {
        SetCursorPos(x, y);
    }

    // The top-level window that hit testing finds at the screen point, skipping windows that are click-through, or IntPtr.Zero.
    public static IntPtr TopLevelAt(int x, int y) {
        const uint gaRoot = 2;
        POINT point;
        point.X = x;
        point.Y = y;
        IntPtr window = WindowFromPoint(point);
        return window == IntPtr.Zero ? IntPtr.Zero : GetAncestor(window, gaRoot);
    }

    // The left button, pressed or released where the pointer is.
    public static void SetLeftButton(bool down) {
        const uint leftDown = 0x0002;
        const uint leftUp = 0x0004;
        mouse_event(down ? leftDown : leftUp, 0, 0, 0, UIntPtr.Zero);
    }
}

public static class WebViewTestPump {
    // Copies a stream into a file, flushing after each read, so the test can read the file while the program is still running.
    public static Thread Start(Stream source, string path) {
        Thread thread = new Thread(delegate() {
            byte[] buffer = new byte[4096];
            using (FileStream target = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite)) {
                int count;
                while ((count = source.Read(buffer, 0, buffer.Length)) > 0) {
                    target.Write(buffer, 0, count);
                    target.Flush();
                }
            }
        });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }
}
"@
}

function Pass([string]$message) {
    Write-Host "PASS: $message"
}

function Fail([string]$message) {
    Write-Host "FAIL: $message"
    $script:failures++
}

# Runs cmake with its output in a log in the work folder. Prints the log and throws when it fails.
function Invoke-CMake([string]$name, [string[]]$arguments) {
    $log = Join-Path $script:work "$name.log"
    $errorLog = Join-Path $script:work "$name.err.log"
    $process = Start-Process -FilePath "cmake" -ArgumentList $arguments -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $errorLog
    if ($process.ExitCode -ne 0) {
        Get-Content $log, $errorLog -ErrorAction SilentlyContinue
        Fail $name
        throw "cmake $name failed"
    }
}

# Builds the example unless a build directory is given, then starts it with the given arguments. Usage: Start-Example [build-dir] [args]
function Start-Example {
    param([string]$BuildDir = "", [string[]]$Arguments = @())
    if (-not $BuildDir) {
        $BuildDir = Join-Path $script:work "build"
        Invoke-CMake "configure" @("-S", $script:root, "-B", $BuildDir, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $script:root 'cmake\toolchains\mingw-w64.cmake')", "-DWEBVIEW_WINDOW_BUILD_EXAMPLE=ON")
        Invoke-CMake "build" @("--build", $BuildDir)
    }
    $exe = Join-Path $BuildDir "examples\webview_window_example.exe"
    if (-not (Test-Path $exe)) {
        Fail "no example at $exe"
        throw "no example"
    }
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.Arguments = $Arguments -join " "
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $script:process = [System.Diagnostics.Process]::Start($info)
    $script:stdin = $script:process.StandardInput.BaseStream
    [WebViewTestPump]::Start($script:process.StandardOutput.BaseStream, $script:outputPath) | Out-Null
    [WebViewTestPump]::Start($script:process.StandardError.BaseStream, $script:errorPath) | Out-Null
    # The pipe starts with a byte-order mark, which the example's first line would carry. The example ignores an empty line, so the
    # mark goes there and the first command is read intact.
    Send-Command ""
}

# Sends the example a command on its standard input, as UTF-8 without a byte-order mark, with a bare newline after it.
function Send-Command([string]$command) {
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes("$command`n")
    $script:stdin.Write($bytes, 0, $bytes.Length)
    $script:stdin.Flush()
}

# Ends the example with quit, and checks that it exits with status 0.
function Stop-Example {
    Send-Command "quit"
    $script:stdin.Close()
    if ($script:process.WaitForExit(10000)) {
        if ($script:process.ExitCode -eq 0) {
            Pass "quit stops the example with exit status 0"
        } else {
            Fail "the example didn't exit cleanly, with status $($script:process.ExitCode)"
        }
    } else {
        Fail "the example didn't exit cleanly"
    }
}

# The example's output lines so far, without the carriage returns Windows adds. The unfinished last line is left out.
function Get-OutputLines {
    if (-not (Test-Path $script:outputPath)) {
        return @()
    }
    $stream = [System.IO.File]::Open($script:outputPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.StreamReader($stream)
        $text = $reader.ReadToEnd()
    } finally {
        $stream.Dispose()
    }
    $lines = $text -split "`n"
    if ($lines.Count -le 1) {
        return @()
    }
    return @($lines[0..($lines.Count - 2)] | ForEach-Object { $_.TrimEnd("`r") })
}

function Get-LineCount {
    return @(Get-OutputLines).Count
}

# Waits until the output has a line matching the pattern after the first <before> lines.
function Wait-ForLineAfter([int]$before, [string]$pattern, [int]$seconds = 10) {
    for ($i = 0; $i -lt ($seconds * 10); $i++) {
        $matching = @(Get-OutputLines | Select-Object -Skip $before | Where-Object { $_ -match $pattern })
        if ($matching.Count -gt 0) {
            return $true
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

# The most recent state line.
function Get-LastState {
    $states = @(Get-OutputLines | Where-Object { $_ -match '^visible=' })
    if ($states.Count -eq 0) {
        return ""
    }
    return $states[-1]
}

# A field of the most recent state line, such as frame or area.
function Get-StateField([string]$name) {
    if ((Get-LastState) -match "$name=(\S*)") {
        return $matches[1]
    }
    return ""
}

# The window the example opened, shown or hidden, or IntPtr.Zero when it has none.
function Get-ExampleWindow {
    if (-not $script:process) {
        return [IntPtr]::Zero
    }
    return [WebViewTestNative]::FindWindow([uint32]$script:process.Id, $script:title)
}

# Whether the window is on screen, as Windows reports it.
function Test-ExampleWindowShown {
    $window = Get-ExampleWindow
    return ($window -ne [IntPtr]::Zero) -and [WebViewTestNative]::IsShown($window)
}

# Waits until the window is shown or hidden on screen.
function Wait-ForWindow([string]$want) {
    for ($i = 0; $i -lt 100; $i++) {
        $shown = Test-ExampleWindowShown
        if ($want -eq "shown" -and $shown) {
            return $true
        }
        if ($want -eq "hidden" -and -not $shown) {
            return $true
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

# Sends a command to the example and waits for the state it reports, and the window to match. Usage: Invoke-CommandThenCheck cmd state window
function Invoke-CommandThenCheck([string]$command, [string]$state, [string]$window) {
    $before = Get-LineCount
    Send-Command $command
    return (Wait-ForLineAfter $before $state) -and (Wait-ForWindow $window)
}

# The window's rectangle as "x,y,width,height", from a report of the example's state.
function Get-FrameNow {
    $before = Get-LineCount
    Send-Command "report"
    Wait-ForLineAfter $before '^visible=' | Out-Null
    return Get-StateField "frame"
}

# Splits "x,y,width,height" into four integers. Throws when the text isn't a rectangle, such as "none" for a window without one.
function Split-Rect([string]$text) {
    $parts = $text -split ","
    if ($parts.Count -ne 4) {
        throw "not a rectangle: '$text'"
    }
    return @($parts | ForEach-Object { [int]$_ })
}

# The work area as "x,y,width,height", from the same report. Usage: Get-AreaNow
function Get-AreaNow {
    return Get-StateField "area"
}

# Presses in the window, starts a move, moves the pointer by (dx, dy), and releases it. The pointer must end on the screen.
function Invoke-DragMove([int]$px, [int]$py, [int]$dx, [int]$dy) {
    [WebViewTestNative]::MovePointer($px, $py)
    [WebViewTestNative]::SetLeftButton($true)
    Start-Sleep -Milliseconds 200
    Send-Command "move"
    Start-Sleep -Milliseconds 300
    [WebViewTestNative]::MovePointer($px + $dx, $py + $dy)
    Start-Sleep -Milliseconds 300
    [WebViewTestNative]::SetLeftButton($false)
}

# Moves the pointer to the corner, presses, starts a resize from the edge, moves the pointer by (dx, dy), and releases it.
function Invoke-DragResize([int]$px, [int]$py, [int]$dx, [int]$dy, [string]$edge) {
    [WebViewTestNative]::MovePointer($px, $py)
    [WebViewTestNative]::SetLeftButton($true)
    Start-Sleep -Milliseconds 200
    Send-Command "resize $edge"
    Start-Sleep -Milliseconds 300
    [WebViewTestNative]::MovePointer($px + $dx, $py + $dy)
    Start-Sleep -Milliseconds 300
    [WebViewTestNative]::SetLeftButton($false)
}

# The snapping grid, in pixels. Windows snaps the edges a move or resize changes to it.
$script:grid = 8

# The grid line nearest to a positive coordinate, rounding halves up.
function Get-NearestGridLine([int]$value) {
    return [int]([math]::Floor(($value + $script:grid / 2) / $script:grid) * $script:grid)
}

# Waits until the window reports the expected edges. Usage: Wait-ForSettledFrame left top right bottom. Returns the frame it last saw.
function Wait-ForSettledFrame([int]$wantLeft, [int]$wantTop, [int]$wantRight, [int]$wantBottom) {
    $frame = ""
    for ($i = 0; $i -lt 20; $i++) {
        $frame = Get-FrameNow
        $fx, $fy, $fw, $fh = Split-Rect $frame
        if ($fx -eq $wantLeft -and $fy -eq $wantTop -and ($fx + $fw) -eq $wantRight -and ($fy + $fh) -eq $wantBottom) {
            break
        }
        Start-Sleep -Milliseconds 100
    }
    return $frame
}

# Checks that the harness and the example measure the window the same way. The drags are made in screen pixels, so a mismatch
# (one of the two processes being DPI aware, say) would make the checks meaningless.
function Test-HarnessAgrees {
    $window = Get-ExampleWindow
    if ($window -eq [IntPtr]::Zero) {
        Fail "setup: the example has no window to measure"
        return
    }
    $measured = ([WebViewTestNative]::FrameOf($window)) -join ","
    $reported = Get-FrameNow
    if ($measured -eq $reported) {
        Pass "the harness and the example measure the window the same way"
    } else {
        Fail "setup: the harness measures the window at $measured but the example reports $reported"
    }
}

# Ends the example if it's still running, and removes the work folder unless a check failed.
function Remove-Harness {
    if ($script:process -and -not $script:process.HasExited) {
        $script:process.Kill()
        $script:process.WaitForExit(5000) | Out-Null
    }
    if ($script:failures -eq 0) {
        Remove-Item -Recurse -Force $script:work -ErrorAction SilentlyContinue
    }
}

# Finishes the test: prints the result, and says where the output is when a check failed. Exits with status 1 when a check failed.
function Finish {
    if ($script:failures -eq 0) {
        Write-Host "All checks passed."
        exit 0
    }
    Write-Host "$($script:failures) check(s) failed. Output is in $($script:outputPath) and $($script:errorPath)."
    exit 1
}
