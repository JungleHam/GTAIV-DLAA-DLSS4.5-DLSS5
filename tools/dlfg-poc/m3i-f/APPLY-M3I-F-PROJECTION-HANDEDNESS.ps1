$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-F.bat from this branch." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}

$text = Read-Normalized $cpp

$func = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
$pos = $text.IndexOf($func)
if ($pos -lt 0) { throw 'M3I-F anchor not found: M2bBuildConstants' }

$old1 = '    op->cameraViewToClip[2][2] = a;'
$new1 = '    op->cameraViewToClip[2][2] = -a; // M3I-F: GTA IV right-handed projection'
$old2 = '    op->cameraViewToClip[2][3] = 1.0f;'
$new2 = '    op->cameraViewToClip[2][3] = -1.0f; // M3I-F: GTA IV right-handed projection'
$old3 = '    op->clipToCameraView[3][2] = 1.0f;'
$new3 = '    op->clipToCameraView[3][2] = -1.0f; // M3I-F: exact inverse of GTA IV projection'

if ($text.Contains('M3I-F: GTA IV right-handed projection')) {
    Write-Host 'M3I-F projection handedness patch already applied.'
    exit 0
}

foreach ($pair in @(@($old1,$new1), @($old2,$new2), @($old3,$new3))) {
    $old = $pair[0]; $new = $pair[1]
    $p = $text.IndexOf($old, $pos)
    if ($p -lt 0) { throw "M3I-F anchor not found: $old" }
    if ($text.IndexOf($old, $p + 1) -ge 0) { throw "M3I-F anchor not unique: $old" }
    $text = $text.Remove($p, $old.Length).Insert($p, $new)
}

$aspectLine = '    const float aspect = static_cast<float>(g.width) / static_cast<float>(g.height);'
$aspectPos = $text.IndexOf($aspectLine, $pos)
if ($aspectPos -lt 0) { throw 'M3I-F aspect anchor not found' }
$insertPos = $aspectPos + $aspectLine.Length
$log = @'
    static bool m3i_f_logged = false;
    if (!m3i_f_logged) {
        Log("[feed] M3I-F: GTA projection matrix convention active: RH m22=-a m23=-1 inverse_m32=-1 FOVdeg=45 near=0.05 far=1500");
        m3i_f_logged = true;
    }
'@
$text = $text.Insert($insertPos, "`n" + $log)

Write-Normalized $cpp $text
Write-Host 'Applied M3I-F: GTA IV right-handed cameraViewToClip + exact inverse.'
Write-Host 'No temporal matrices, MV data/scale, pacing, transport or presentation behavior changed.'
