$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$feedCpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
if (!(Test-Path $feedCpp)) { throw "Missing $feedCpp. Run BUILD-M3E.bat first." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}
function Replace-Exact([ref]$textRef, [string]$old, [string]$new, [string]$already, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if ($already -and $textRef.Value.Contains($already)) { return }
    if (!$textRef.Value.Contains($old)) { throw "M3F anchor not found: $name" }
    $textRef.Value = $textRef.Value.Replace($old, $new)
}

$feed = Read-Normalized $feedCpp
$ref = [ref]$feed

# One integer switch gives us several A/B motion-vector contracts without rebuilding.
Replace-Exact $ref `
'    int   dlfg_m3d_injected_present_gate; // M3D: suppress synthetic presents + duplicate Feeder callbacks per real present' `
'    int   dlfg_m3d_injected_present_gate; // M3D: suppress synthetic presents + duplicate Feeder callbacks per real present
    int   dlfg_m3f_mv_mode; // M3F: DLSS-G motion-vector scale/sign diagnostic preset (0=current baseline)' `
'dlfg_m3f_mv_mode' `
'Cfg field'

Replace-Exact $ref `
'                     /* dlfg_m3d_injected_present_gate */ 0,
                     /* hdr_bridge */ -1' `
'                     /* dlfg_m3d_injected_present_gate */ 0,
                     /* dlfg_m3f_mv_mode */ 0,
                     /* hdr_bridge */ -1' `
'/* dlfg_m3f_mv_mode */' `
'Cfg initializer'

Replace-Exact $ref `
'        else if (_stricmp(key, "dlfg_m3d_injected_present_gate") == 0) next.dlfg_m3d_injected_present_gate = iv;' `
'        else if (_stricmp(key, "dlfg_m3d_injected_present_gate") == 0) next.dlfg_m3d_injected_present_gate = iv;
        else if (_stricmp(key, "dlfg_m3f_mv_mode") == 0) next.dlfg_m3f_mv_mode = iv;' `
'_stricmp(key, "dlfg_m3f_mv_mode")' `
'Cfg parser'

Replace-Exact $ref `
'    next.dlfg_m3d_injected_present_gate = next.dlfg_m3d_injected_present_gate != 0 ? 1 : 0;' `
'    next.dlfg_m3d_injected_present_gate = next.dlfg_m3d_injected_present_gate != 0 ? 1 : 0;
    if (next.dlfg_m3f_mv_mode < 0 || next.dlfg_m3f_mv_mode > 7) next.dlfg_m3f_mv_mode = 0;' `
'next.dlfg_m3f_mv_mode < 0' `
'Cfg normalization'

Replace-Exact $ref `
'                         next.dlfg_m3c_queue != g_cfg.dlfg_m3c_queue ||
                         next.dlfg_m3d_injected_present_gate != g_cfg.dlfg_m3d_injected_present_gate;' `
'                         next.dlfg_m3c_queue != g_cfg.dlfg_m3c_queue ||
                         next.dlfg_m3d_injected_present_gate != g_cfg.dlfg_m3d_injected_present_gate ||
                         next.dlfg_m3f_mv_mode != g_cfg.dlfg_m3f_mv_mode;' `
'next.dlfg_m3f_mv_mode != g_cfg.dlfg_m3f_mv_mode' `
'Cfg rebuild trigger'

$mvOld = @'
    op->mvecScale[0] = 1.0f / static_cast<float>(g.width);
    op->mvecScale[1] = 1.0f / static_cast<float>(g.height);
    op->cameraUp[1] = 1.0f;
'@
$mvNew = @'
    // M3F motion-vector alignment diagnostic. NVIDIA's documented pixel-space baseline is
    // {1/width, 1/height}; modes below deliberately perturb only the DLSS-G interpretation.
    // The source MV texture itself, DLAA path, ring transport, and M3D/M3E pacing stay unchanged.
    float m3fScaleX = 1.0f;
    float m3fScaleY = 1.0f;
    const int m3fMode = g_cfg.dlfg_m3f_mv_mode;
    switch (m3fMode)
    {
        case 1: m3fScaleX = -1.0f; m3fScaleY =  1.0f; break; // flip X only
        case 2: m3fScaleX =  1.0f; m3fScaleY = -1.0f; break; // flip Y only
        case 3: m3fScaleX = -1.0f; m3fScaleY = -1.0f; break; // flip both
        case 4: m3fScaleX =  0.50f; m3fScaleY =  0.50f; break; // half magnitude
        case 5: m3fScaleX =  0.75f; m3fScaleY =  0.75f; break; // 75% magnitude
        case 6: m3fScaleX =  1.25f; m3fScaleY =  1.25f; break; // 125% magnitude
        case 7: m3fScaleX =  1.50f; m3fScaleY =  1.50f; break; // 150% magnitude
        default: break; // documented/current baseline
    }
    op->mvecScale[0] = m3fScaleX / static_cast<float>(g.width);
    op->mvecScale[1] = m3fScaleY / static_cast<float>(g.height);
    static int m3fLastLoggedMode = -1;
    if (m3fLastLoggedMode != m3fMode)
    {
        m3fLastLoggedMode = m3fMode;
        Log("[feed] M3F: DLSS-G MV mode=%d scaleMultiplier=(%.3f,%.3f) normalizedScale=(%.9f,%.9f)",
            m3fMode, m3fScaleX, m3fScaleY,
            op->mvecScale[0], op->mvecScale[1]);
    }
    op->cameraUp[1] = 1.0f;
'@
Replace-Exact $ref $mvOld $mvNew '// M3F motion-vector alignment diagnostic.' 'M2bBuildConstants MV contract'

Write-Normalized $feedCpp $ref.Value

Write-Host 'Applied M3F motion-vector alignment diagnostic modes.'
Write-Host '  dlfg_m3f_mv_mode=0  current/documented +X,+Y baseline'
Write-Host '  dlfg_m3f_mv_mode=1  flip X'
Write-Host '  dlfg_m3f_mv_mode=2  flip Y'
Write-Host '  dlfg_m3f_mv_mode=3  flip X+Y'
Write-Host '  dlfg_m3f_mv_mode=4  50% magnitude'
Write-Host '  dlfg_m3f_mv_mode=5  75% magnitude'
Write-Host '  dlfg_m3f_mv_mode=6  125% magnitude'
Write-Host '  dlfg_m3f_mv_mode=7  150% magnitude'
Write-Host 'Changing mode triggers the existing Feeder rebuild/reset path so temporal history is not mixed.'
