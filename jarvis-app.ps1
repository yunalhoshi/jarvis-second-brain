# Opens Jarvis as its own app window (no tabs, no address bar).
# Refreshes the graph, starts the local server in the background if it is not
# running yet, opens the window, and stops the server again when the window closes.

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8765
$url = "http://localhost:$port/"

function Test-Server {
    $client = New-Object System.Net.Sockets.TcpClient
    try { $client.Connect('127.0.0.1', $port); return $true } catch { return $false } finally { $client.Close() }
}

# 1) Refresh the graph data from the notes
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build-graph.ps1') | Out-Null

# 2) Start the server hidden, unless one is already running
$server = $null
if (-not (Test-Server)) {
    $python = (Get-Command pythonw -ErrorAction SilentlyContinue).Source
    if (-not $python) { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }
    if ($python) {
        $server = Start-Process -FilePath $python -ArgumentList ('"' + (Join-Path $root 'jarvis-server.py') + '"'), '--no-browser' `
            -WorkingDirectory $root -WindowStyle Hidden -PassThru
        for ($i = 0; $i -lt 40 -and -not (Test-Server); $i++) { Start-Sleep -Milliseconds 250 }
    }
}
if (-not (Test-Server)) { $url = 'file:///' + (Join-Path $root 'index.html').Replace('\', '/') }

# 3) Open the page in an app window. Chrome or Edge, with a profile of its own so that
#    the microphone permission is remembered and closing the window is noticed.
$browser = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($browser) {
    $profileDir = Join-Path $env:LOCALAPPDATA 'Jarvis\browser-profile'
    Start-Process -FilePath $browser -Wait -ArgumentList "--app=$url", ('--user-data-dir="' + $profileDir + '"'),
        '--no-first-run', '--no-default-browser-check', '--window-size=1400,900'
} else {
    Start-Process $url
    $server = $null   # ordinary browser tab: we cannot tell when it closes, so leave the server running
}

# 4) Window closed: stop the server we started, unless phone access (Jarvis-Telefon.bat) still needs it
$keepForPhone = Test-Path (Join-Path $env:LOCALAPPDATA 'Jarvis\keep-server')
if ($server -and -not $server.HasExited -and -not $keepForPhone) {
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
}
