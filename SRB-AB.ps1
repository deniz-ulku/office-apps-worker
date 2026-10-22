<#
    SRB-AB.ps1  -  A/B two SRBMiner builds on this machine and print the delta.

    Downloads only what it needs, runs each build for 75 seconds against the
    real pool with the real wallet, prints TH/s for both, then kills everything
    it started. Nothing is left running and nothing is installed.

    Refuses to run if a miner is already going, so it cannot fight your rig.

    Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File SRB-AB.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File SRB-AB.ps1 -Seconds 120
#>
param([int]$Seconds = 75)

$ErrorActionPreference = 'SilentlyContinue'
$out = Join-Path $env:TEMP 'srb-ab.txt'
Remove-Item $out -Force
function W($s) { Add-Content -LiteralPath $out -Value $s -Encoding UTF8; Write-Host $s }

$wallet = 'prl1p9ua7ny7ggllrq6tmh9ssusktv43tp90ty6359c7qujh5u2mheeesrz5wzx'
$pool   = 'prl-eu.kryptex.network:7048'
$base   = Join-Path $env:TEMP 'srb-ab'

W ('=== SRBMiner A/B  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ===')

$running = @(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    W '  a miner is already running - stopping. Re-run when the rig is free.'
    W ('  pids: ' + (($running | ForEach-Object { $_.Id }) -join ', '))
    exit 1
}

$builds = @(
    @{ Tag = '3.7.6'; Dir = 'SRBMiner-Multi-3-7-6'; Md5 = '550077549bf6da5ff1e1383d0ffd3a6f' },
    @{ Tag = '3.8.0'; Dir = 'SRBMiner-Multi-3-8-0'; Md5 = 'ca9f61fad66d1b4c7b9daf867baaa4c5' }
)

foreach ($b in $builds) {
    $exe = Join-Path $base ($b.Dir + '\SRBMiner-MULTI.exe')
    if (Test-Path $exe) { W ('  ' + $b.Tag + ' already unpacked'); continue }

    $v   = $b.Tag -replace '\.', '-'
    $url = 'https://github.com/doktor83/SRBMiner-Multi/releases/download/' + $b.Tag + '/SRBMiner-Multi-' + $v + '-win64.zip'
    $zip = Join-Path $base ($b.Tag + '.zip')
    New-Item -ItemType Directory -Force -Path $base | Out-Null

    W ('  downloading ' + $b.Tag + ' ...')
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'ab')
        $wc.DownloadFile($url, $zip)
        $wc.Dispose()
    } catch { W ('    FAILED: ' + $_.Exception.Message); exit 1 }

    $md5 = (Get-FileHash -LiteralPath $zip -Algorithm MD5).Hash.ToLower()
    W ('    md5 ' + $md5 + '   match=' + ($md5 -eq $b.Md5))
    if ($md5 -ne $b.Md5) { W '    fingerprint mismatch - aborting'; exit 1 }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $base)
    } catch { W ('    extract failed: ' + $_.Exception.Message); exit 1 }
    Remove-Item $zip -Force
}

function Measure-Build([string]$tag, [string]$dir) {
    $exe = Join-Path $base ($dir + '\SRBMiner-MULTI.exe')
    $log = Join-Path $base ('run-' + $tag + '.log')
    Remove-Item $log -Force

    $a = @('--algorithm-gpu', 'pearlhash', '--pool', $pool, '--wallet', $wallet,
           '--worker', 'ABTEST', '--password', 'x', '--disable-cpu',
           '--log-file', $log, '--log-file-mode', '0')

    $p = Start-Process -FilePath $exe -ArgumentList $a -WorkingDirectory (Split-Path $exe) -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds $Seconds

    $hr = 0; $pw = 0; $cc = 0
    if (Test-Path $log) {
        $txt = Get-Content -LiteralPath $log -Raw
        # Total line:  Total: 87.32 TH/s [P:239.6W EFF:0.364 A:55 ...]
        $m = [regex]::Matches($txt, 'Total:\s+([\d\.]+)\s+([KMGTP])H/s\s+\[P:([\d\.]+)W')
        if ($m.Count -gt 0) {
            $last = $m[$m.Count - 1]
            $v = [double]::Parse($last.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
            $mult = switch ($last.Groups[2].Value) { 'K' { 1e3 } 'M' { 1e6 } 'G' { 1e9 } 'T' { 1e12 } 'P' { 1e15 } default { 1 } }
            $hr = [math]::Round(($v * $mult) / 1e12, 2)
            $pw = [double]::Parse($last.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
        }
        # clock from the GPU line
        $mc = [regex]::Match($txt, 'CC:(\d+)')
        if ($mc.Success) { $cc = [int]$mc.Groups[1].Value }
    }

    Stop-Process -Id $p.Id -Force
    Get-Process SRBMiner-MULTI | Stop-Process -Force
    Start-Sleep -Seconds 5

    W ('  {0} : {1} TH/s  at {2} W  {3} MHz' -f $tag, $hr, [math]::Round($pw, 0), $cc)
    return $hr
}

W ''
W ('  measuring ' + $Seconds + ' s each ...')
$a = Measure-Build '3.7.6' 'SRBMiner-Multi-3-7-6'
$b = Measure-Build '3.8.0' 'SRBMiner-Multi-3-8-0'

W ''
if ($a -gt 0 -and $b -gt 0) {
    $pct = [math]::Round((($b - $a) / $a) * 100, 1)
    W ('  delta : ' + $(if ($pct -ge 0) { '+' } else { '' }) + $pct + '%')
    if ($b -gt $a) {
        W '  VERDICT: 3.8.0 wins -> worth deploying'
    } else {
        W '  VERDICT: 3.7.6 wins -> stay on it, the changelog lied again'
    }
} else {
    W '  VERDICT: inconclusive - one build produced no stats. Check C:\Users\<you>\AppData\Local\Temp\srb-ab\run-*.log'
}
W ''
W ('  nothing is left running: ' + (@(Get-Process SRBMiner-MULTI -ErrorAction SilentlyContinue).Count -eq 0))
W '=== done ==='
