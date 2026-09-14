$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-B.bat from this branch." }

$text = (Get-Content $cpp -Raw).Replace("`r`n", "`n")

$old = '    op->motionVectorsDilated = false;'
$new = @'
    // M3I-B diagnostic: our MV texture is full output resolution. OptiScaler's
    // DLSS-G path marks full-resolution vectors as already dilated; test that
    // contract directly while leaving every other feature-11 value unchanged.
    op->motionVectorsDilated = true; // M3I-B full-res MV dilation diagnostic
'@

if ($text.Contains('M3I-B full-res MV dilation diagnostic')) {
    Write-Host 'M3I-B MV dilation diagnostic is already present.'
    exit 0
}

$first = $text.IndexOf($old)
if ($first -lt 0) { throw 'M3I-B anchor not found: op->motionVectorsDilated = false;' }
if ($text.IndexOf($old, $first + 1) -ge 0) { throw 'M3I-B anchor is not unique; refusing to patch ambiguously.' }

$text = $text.Replace($old, $new)
Set-Content -Path $cpp -Value $text -NoNewline -Encoding UTF8

Write-Host 'Applied M3I-B: motionVectorsDilated=true for the native DLSS-G contract.'
Write-Host 'No resource, MV data, scale, camera matrix, pacing, transport, or presentation values were changed.'
