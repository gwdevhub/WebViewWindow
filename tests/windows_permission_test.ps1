# Checks how the example answers a page's permission requests on Windows. The page is served over http://localhost, since WebView2
# only offers the microphone and notifications to a secure origin. The server is Python's http.server, which must be on the PATH.
#
# Without --allow-permissions the host has no answer, so WebView2 keeps its own default: it shows a prompt, which nobody answers, so
# the microphone stays pending and notifications aren't granted. With --allow-permissions the host allows them: notifications start
# granted, and the microphone request isn't refused. The microphone may still be missing on the machine (a runner has none), so the
# check is that the request isn't refused or left pending, not that a device answered. Every wait is at most 10 seconds, and the
# probe reports a request nobody answers after five.
#
# Usage: tests/windows_permission_test.ps1 [-BuildDir <build-dir>]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

$port = 8765
$site = Join-Path $script:work "site"
New-Item -ItemType Directory -Path $site | Out-Null
@'
<!doctype html><html><body>probe
<script>
(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
  .postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));
</script></body></html>
'@ | Set-Content -Path (Join-Path $site "probe.html") -Encoding UTF8

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Fail "python isn't on the PATH, so the page can't be served"
    Finish
    exit 1
}
$server = Start-Process -FilePath $python.Source -ArgumentList @("-m", "http.server", "$port", "--bind", "127.0.0.1") `
    -WorkingDirectory $site -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 1
$url = "http://localhost:$port/probe.html"

# Starts the example with the options and a profile folder of its own, asks it to probe the page, and returns the probe's line, or
# nothing when it didn't report. Each run gets a new profile, so a permission one run decides can't carry into the next.
$script:runs = 0
function Invoke-Probe([string[]]$options) {
    $script:runs++
    $profile = Join-Path $script:work "profile-$($script:runs)"
    Start-Example -BuildDir $BuildDir -Arguments (@("--url", $url, "--data-folder", $profile) + $options)
    # A new profile takes WebView2 a while to create, so the page gets longer than the usual ten seconds.
    if (-not (Wait-ForLineAfter 0 '^loaded$' 60)) {
        Fail "the page never loaded"
        Stop-Example
        return $null
    }
    Send-Command "probe"
    $line = $null
    if (Wait-ForLineAfter 0 '^probe ' 30) {
        $line = Get-OutputLines | Where-Object { $_ -match '^probe ' } | Select-Object -Last 1
    } else {
        Fail "the page never reported its probe"
    }
    # The requests the platform made, for the log: what the host was asked, and what it answered.
    Get-OutputLines | Where-Object { $_ -match '^permission ' } | ForEach-Object { Write-Host "  $_" }
    Stop-Example
    return $line
}

# The microphone is only asked for when the machine has one: without a device, the request fails before any permission is asked.
function Test-MicrophoneCheck([string]$line, [string]$label, [scriptblock]$check) {
    if ($line -match '"microphone":"NotFoundError"') {
        Write-Host "SKIP: $label. This machine has no microphone, so the request fails before it's asked."
        return
    }
    if ($line -and (& $check)) {
        Pass $label
    } else {
        Fail "$label, but the probe said: $line"
    }
}

try {
    # 1. No host answer: notifications aren't granted, and a microphone request isn't granted.
    $line = Invoke-Probe @()
    if ($line -and $line -notmatch '"notificationBefore":"granted"' -and $line -notmatch '"notification":"granted"') {
        Pass "without a host answer, notifications aren't granted"
    } else {
        Fail "without a host answer, notifications were granted or unknown: $line"
    }
    Test-MicrophoneCheck $line "without a host answer, the microphone request is refused or left to WebView2's prompt" {
        $line -match '"microphone":"(NotAllowedError|pending)"'
    }

    # 2. The host allows: notifications are granted for the page's origin, and the microphone isn't refused.
    $line = Invoke-Probe @("--allow-permissions")
    # Granted either before the request, as on Linux, or by the request, as on WebView2.
    if ($line -and ($line -match '"notificationBefore":"granted"' -or $line -match '"notification":"granted"')) {
        Pass "with --allow-permissions, notifications are granted for the page's origin"
    } else {
        Fail "with --allow-permissions, notifications weren't granted: $line"
    }
    Test-MicrophoneCheck $line "with --allow-permissions, the microphone request isn't refused" {
        $line -notmatch '"microphone":"(NotAllowedError|pending)"'
    }
} finally {
    if ($server -and -not $server.HasExited) {
        $server.Kill()
    }
    Remove-Harness
}

Finish
