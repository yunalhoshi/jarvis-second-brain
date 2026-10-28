# Phone access for Jarvis through Tailscale.
#   jarvis-phone.ps1         start the server in the background and publish it privately
#   jarvis-phone.ps1 -Stop   take the private address down again and stop the server
# Only devices signed in to the same Tailscale account can open the address.
param([switch]$Stop)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8765
$tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$flag = Join-Path $env:LOCALAPPDATA 'Jarvis\keep-server'   # tells the desktop app not to stop the server on close

function Test-Server {
    $client = New-Object System.Net.Sockets.TcpClient
    try { $client.Connect('127.0.0.1', $port); return $true } catch { return $false } finally { $client.Close() }
}

if (-not (Test-Path $tailscale)) {
    Write-Host 'Tailscale bu bilgisayarda kurulu degil.'
    Write-Host 'Once tailscale.com/download adresinden kur ve giris yap, sonra bu dosyayi tekrar calistir.'
    exit 1
}

if ($Stop) {
    & $tailscale serve reset
    Remove-Item $flag -ErrorAction SilentlyContinue
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -like 'python*') { Stop-Process -Id $process.Id -Force }
    }
    Write-Host 'Telefon erisimi kapatildi.'
    exit 0
}

# Tailscale sometimes sits in "starting" until its own app is opened: open it and wait for the connection
& $tailscale status *> $null
if ($LASTEXITCODE -ne 0) {
    $app = Join-Path $env:ProgramFiles 'Tailscale\tailscale-ipn.exe'
    if (Test-Path $app) { Start-Process $app }
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        & $tailscale status *> $null
        if ($LASTEXITCODE -eq 0) { break }
    }
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build-graph.ps1') | Out-Null

if (-not (Test-Server)) {
    $python = (Get-Command pythonw -ErrorAction SilentlyContinue).Source
    if (-not $python) { $python = (Get-Command python -ErrorAction SilentlyContinue).Source }
    if (-not $python) { Write-Host 'Python bulunamadi.'; exit 1 }
    Start-Process -FilePath $python -ArgumentList ('"' + (Join-Path $root 'jarvis-server.py') + '"'), '--no-browser' `
        -WorkingDirectory $root -WindowStyle Hidden
    for ($i = 0; $i -lt 40 -and -not (Test-Server); $i++) { Start-Sleep -Milliseconds 250 }
}
if (-not (Test-Server)) { Write-Host 'Jarvis sunucusu baslatilamadi.'; exit 1 }

New-Item -ItemType Directory -Force (Split-Path $flag) | Out-Null
Set-Content -Path $flag -Value 'phone' -Encoding ascii

& $tailscale serve --bg $port
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host 'Tailscale adresi acilamadi. Yukaridaki mesajda bir baglanti varsa onu acip HTTPS ozelligini etkinlestir,'
    Write-Host 'sonra bu dosyayi tekrar calistir.'
    exit 1
}

$name = ((& $tailscale status --json | ConvertFrom-Json).Self.DNSName).TrimEnd('.')
Write-Host ''
Write-Host 'Jarvis telefon icin hazir. Telefonda Tailscale acikken Safari ile su adresi ac:'
Write-Host ''
Write-Host "    https://$name"
Write-Host ''
Write-Host 'Bilgisayar acik kaldigi surece calisir. Kapatmak icin Jarvis-Telefon-Kapat.bat dosyasini calistir.'
