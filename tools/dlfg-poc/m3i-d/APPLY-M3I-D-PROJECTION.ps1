$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-D.bat from this branch." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}

$text = Read-Normalized $cpp

$func = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
$pos = $text.IndexOf($func)
if ($pos -lt 0) { throw 'M3I-D anchor not found: M2bBuildConstants' }

$old = '    const float near_z = 0.1f, far_z = 1000.0f, fov = 1.0471975512f; // 60 degrees'
$new = '    const float near_z = 0.05f, far_z = 1500.0f, fov = 0.7853981634f; // M3I-D: GTA IV main viewport contract, 45 degrees'

$constPos = $text.IndexOf($old, $pos)
if ($constPos -lt 0) {
    if ($text.IndexOf($new, $pos) -ge 0) {
        Write-Host 'M3I-D projection contract already applied.'
        exit 0
    }
    throw 'M3I-D anchor not found: baseline near/far/FOV constants'
}

$text = $text.Remove($constPos, $old.Length).Insert($constPos, $new)

# Add a one-time identifying log immediately after the aspect computation.
$aspectLine = '    const float aspect = static_cast<float>(g.width) / static_cast<float>(g.height);'
$aspectPos = $text.IndexOf($aspectLine, $pos)
if ($aspectPos -lt 0) { throw 'M3I-D anchor not found: aspect line' }
$insertPos = $aspectPos + $aspectLine.Length
$log = "`n    static bool m3i_d_logged = false;`n    if (!m3i_d_logged) { Log(\"[feed] M3I-D: projection contract FOVdeg=45.000000 near=0.050000 far=1500.000 aspect=%.9f\", aspect); m3i_d_logged = true; }"
$text = $text.Insert($insertPos, $log)

Write-Normalized $cpp $text
Write-Host 'Applied M3I-D GTA IV projection contract: FOV 45 deg, near 0.05, far 1500.'
