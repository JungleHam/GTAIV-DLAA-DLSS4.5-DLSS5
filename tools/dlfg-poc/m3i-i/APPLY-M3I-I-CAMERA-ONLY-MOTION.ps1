$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$cpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'

if (!(Test-Path $cpp)) { throw "Missing $cpp. Run BUILD-M3I-I.bat from this branch." }

$text = (Get-Content $cpp -Raw).Replace("`r`n", "`n")
$marker = '// M3I-I: camera-only motion diagnostic'
if ($text.Contains($marker)) {
    Write-Host 'M3I-I camera-only motion patch already applied.'
    exit 0
}

$func = 'static void M2bBuildConstants(NVSDK_NGX_DLSSG_Opt_Eval_Params *op, bool reset)'
$funcPos = $text.IndexOf($func)
if ($funcPos -lt 0) { throw 'M3I-I anchor missing: M2bBuildConstants' }

function Replace-OneAfter([string]$old, [string]$new, [string]$name) {
    $p = $script:text.IndexOf($old, $script:funcPos)
    if ($p -lt 0) { throw "M3I-I anchor missing: $name" }
    $next = $script:text.IndexOf($old, $p + $old.Length)
    if ($next -ge 0) { throw "M3I-I anchor not unique: $name" }
    $script:text = $script:text.Remove($p, $old.Length).Insert($p, $new)
}

# Diagnostic contract: the source MV texture remains bound, but its scale is forced to zero.
# cameraMotionIncluded=false tells DLSS-G that the MVec buffer has no camera motion, so the
# complete GTA camera/depth contract from M3I-H can be used to synthesize camera motion.
Replace-OneAfter '    op->cameraMotionIncluded = true;' '    op->cameraMotionIncluded = false; // M3I-I: let DLSS-G synthesize camera motion from depth/camera' 'cameraMotionIncluded'
Replace-OneAfter '    op->motionVectorsInvalidValue = 0.0f;' '    op->motionVectorsInvalidValue = 1.17549435e-38f; // M3I-I: FLT_MIN sentinel, zero MV stays valid' 'motionVectorsInvalidValue'

$scaleAnchor = '    op->mvecScale[1] = m3fScaleY / static_cast<float>(g.height);'
$scalePos = $text.IndexOf($scaleAnchor, $funcPos)
if ($scalePos -lt 0) { throw 'M3I-I anchor missing: M3F mvecScale assignment' }
$insertPos = $scalePos + $scaleAnchor.Length
$insert = @'
    // M3I-I: camera-only motion diagnostic. Keep the MV texture/resource plumbing identical,
    // but make object/provider motion contribute zero. With cameraMotionIncluded=false,
    // NVIDIA must derive static-world camera motion from depth + the live GTA camera contract.
    op->mvecScale[0] = 0.0f;
    op->mvecScale[1] = 0.0f;
    static bool m3i_i_logged = false;
    if (!m3i_i_logged)
    {
        Log("[feed] M3I-I: CAMERA-ONLY motion active: cameraMotionIncluded=0 mvecScale=(0,0) invalid=FLT_MIN; GTA projection/temporal/basis/depth unchanged");
        m3i_i_logged = true;
    }
'@
$text = $text.Insert($insertPos, "`n" + $insert)

Set-Content -Path $cpp -Value $text -NoNewline -Encoding UTF8
Write-Host 'Applied M3I-I: camera-only motion diagnostic.'
Write-Host 'Provider MV contribution is zero; DLSS-G cameraMotionIncluded=false uses GTA depth/camera motion.'
Write-Host 'M3I-H camera basis, M3I-G temporal transforms, projection, pacing and transport are unchanged.'
