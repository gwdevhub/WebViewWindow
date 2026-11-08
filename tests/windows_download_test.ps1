# Checks that a download from a page is saved where the host's download chooser says, on Windows. The page is served over
# http://localhost, with a link that has a download attribute. The example's download command clicks it, and the file is checked on
# disk. The server is Python's http.server, which must be on the PATH. Every wait is at most 10 seconds, plus a minute for a new
# WebView2 profile to load the page.
#
# Usage: tests/windows_download_test.ps1 [-BuildDir <build-dir>]
#   build-dir: a build of the root project with WEBVIEW_WINDOW_BUILD_EXAMPLE=ON. Without it, the example is built first.
param([string]$BuildDir = "")

. "$PSScriptRoot\windows_common.ps1"

$port = 8765
$site = Join-Path $script:work "site"
$downloads = Join-Path $script:work "downloads"
$profile = Join-Path $script:work "profile"
New-Item -ItemType Directory -Path $site, $downloads | Out-Null
Set-Content -Path (Join-Path $site "hello.txt") -Value "hello from the download test" -Encoding UTF8
@'
<!doctype html><html><body>download
<a id="link" href="hello.txt" download>get the file</a>
<script>
(window.chrome && window.chrome.webview ? window.chrome.webview : window.webkit.messageHandlers.host)
  .postMessage(JSON.stringify({id: 1, method: 'ready', args: []}));
</script></body></html>
'@ | Set-Content -Path (Join-Path $site "download.html") -Encoding UTF8

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Fail "python isn't on the PATH, so the page can't be served"
    Finish
    exit 1
}
$server = Start-Process -FilePath $python.Source -ArgumentList @("-m", "http.server", "$port", "--bind", "127.0.0.1") `
    -WorkingDirectory $site -PassThru -WindowStyle Hidden

try {
    Start-Sleep -Seconds 1
    Start-Example -BuildDir $BuildDir -Arguments @("--url", "http://localhost:$port/download.html", "--download-folder", $downloads,
        "--data-folder", $profile)
    # A new profile takes WebView2 a while to create, so the page gets longer than the usual ten seconds.
    if (Wait-ForLineAfter 0 '^loaded$' 60) { Pass "page loaded" } else { Fail "page never loaded" }

    Send-Command "download"
    $saved = Join-Path $downloads "hello.txt"
    $arrived = $false
    for ($i = 0; $i -lt 300; $i++) {
        if ((Test-Path $saved) -and ((Get-Content $saved -Raw) -match "hello from the download test")) {
            $arrived = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if ($arrived) {
        Pass "the download is saved to the folder the chooser picked, under the suggested name"
    } else {
        Fail "the download didn't arrive at $saved"
        Get-ChildItem $downloads | ForEach-Object { Write-Host "  in downloads: $($_.Name)" }
    }

    Stop-Example
} finally {
    if ($server -and -not $server.HasExited) {
        $server.Kill()
    }
    Remove-Harness
}

Finish
