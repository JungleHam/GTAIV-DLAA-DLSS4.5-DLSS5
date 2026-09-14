$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-H.bat from this branch." }

$text = (Get-Content $cpp -Raw).Replace("`r`n", "`n")

$marker = '// M3I-H: live GTA IV camera world position/basis'
if ($text.Contains($marker)) {
    Write-Host 'M3I-H camera basis patch already applied.'
    exit 0
}

$anchor = '    if (reset || !g_m3g_havePrev)'
$p = $text.IndexOf($anchor)
if ($p -lt 0) { throw 'M3I-H anchor not found in M3gApplyTemporalCamera' }

$insert = @'
    // M3I-H: live GTA IV camera world position/basis.
    // GTA is row-vector / right-handed here. VIEWINV is camera-to-world:
    // rows 0/1 are right/up, row 2 is local +Z (backward), row 3 is position.
    op->cameraPos[0] = cur.viewInv[12];
    op->cameraPos[1] = cur.viewInv[13];
    op->cameraPos[2] = cur.viewInv[14];
    op->cameraRight[0] = cur.viewInv[0];
    op->cameraRight[1] = cur.viewInv[1];
    op->cameraRight[2] = cur.viewInv[2];
    op->cameraUp[0] = cur.viewInv[4];
    op->cameraUp[1] = cur.viewInv[5];
    op->cameraUp[2] = cur.viewInv[6];
    op->cameraFwd[0] = -cur.viewInv[8];
    op->cameraFwd[1] = -cur.viewInv[9];
    op->cameraFwd[2] = -cur.viewInv[10];
    if (g_m3g_evalCount <= 4 || (g_m3g_evalCount % 120ull) == 0)
        Log("[feed] M3I-H: LIVE camera basis eval=%llu pos=(%.4f,%.4f,%.4f) fwd=(%.6f,%.6f,%.6f)",
            g_m3g_evalCount,
            op->cameraPos[0], op->cameraPos[1], op->cameraPos[2],
            op->cameraFwd[0], op->cameraFwd[1], op->cameraFwd[2]);

'@

$text = $text.Insert($p, $insert)
Set-Content -Path $cpp -Value $text -NoNewline -Encoding UTF8

Write-Host 'Applied M3I-H: live GTA IV camera position/right/up/forward from VIEWINV.'
Write-Host 'M3I-G temporal transforms, projection, MV data/scale, pacing and transport are unchanged.'
