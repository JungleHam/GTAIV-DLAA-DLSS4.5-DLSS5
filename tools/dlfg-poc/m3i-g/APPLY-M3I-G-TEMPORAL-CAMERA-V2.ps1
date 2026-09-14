$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
$legacyPatch = Join-Path $PSScriptRoot 'APPLY-M3I-G-TEMPORAL-CAMERA.ps1'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-G.bat from this branch." }
if (!(Test-Path $legacyPatch)) { throw "Missing $legacyPatch" }

function Read-Normalized([string]$path) { return (Get-Content $path -Raw).Replace("`r`n", "`n") }
function Write-Normalized([string]$path, [string]$text) { Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8 }

$text = Read-Normalized $cpp

# Reuse the already-reviewed C++ helper body from the v1 patcher rather than
# maintaining a second copy. v1 failed only because it required one exact
# three-line identity block; the helper itself was never written to source.
$legacy = Read-Normalized $legacyPatch
$startToken = "`$helper = @'"
$start = $legacy.IndexOf($startToken)
if ($start -lt 0) { throw 'M3I-G v2 could not locate helper start in v1 patcher' }
$bodyStart = $legacy.IndexOf("`n", $start)
if ($bodyStart -lt 0) { throw 'M3I-G v2 malformed helper start' }
$bodyStart++
$endToken = "`n'@"
$bodyEnd = $legacy.IndexOf($endToken, $bodyStart)
if ($bodyEnd -lt 0) { throw 'M3I-G v2 could not locate helper end in v1 patcher' }
$helper = $legacy.Substring($bodyStart, $bodyEnd - $bodyStart)

if (!$text.Contains('#include <tlhelp32.h>')) {
    $a = '#include <cmath>'
    $p = $text.IndexOf($a)
    if ($p -lt 0) { throw 'M3I-G v2 include anchor missing: <cmath>' }
    $text = $text.Insert($p + $a.Length, "`n#include <tlhelp32.h>")
}
if (!$text.Contains('#include <vector>')) {
    $a = '#include <string>'
    $p = $text.IndexOf($a)
    if ($p -lt 0) { throw 'M3I-G v2 include anchor missing: <string>' }
    $text = $text.Insert($p + $a.Length, "`n#include <vector>")
}

$func = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
$funcPos = $text.IndexOf($func)
if ($funcPos -lt 0) { throw 'M3I-G v2 anchor missing: M2bBuildConstants' }

if (!$text.Contains('// M3I-G live GTA IV temporal camera transforms')) {
    $text = $text.Insert($funcPos, $helper + "`n")
    # Function moved forward by the inserted helper; resolve it again.
    $funcPos = $text.IndexOf($func)
    if ($funcPos -lt 0) { throw 'M3I-G v2 lost M2bBuildConstants after helper insertion' }
}

$call = '    M3gApplyTemporalCamera(op, reset); // M3I-G: live GTA IV current/previous camera transform'
if (!$text.Contains($call)) {
    # Robust anchor: only require the one line that actually matters. The v1
    # patcher unnecessarily required clipToLensClip + both temporal identity
    # lines to be byte-for-byte adjacent.
    $line = '    M2bIdentity(op->prevClipToClip);'
    $p = $text.IndexOf($line, $funcPos)
    if ($p -lt 0) { throw 'M3I-G v2 prevClipToClip identity anchor not found' }
    $next = $p + $line.Length
    $text = $text.Insert($next, "`n" + $call)
}

Write-Normalized $cpp $text
Write-Host 'Applied M3I-G v2: live GTA IV current/previous VIEW temporal clip transforms.'
Write-Host 'Robust anchor used: insertion directly after prevClipToClip identity.'
Write-Host 'M3I-F projection, MV scale/data, cameraMotionIncluded, pacing and transport are unchanged.'
