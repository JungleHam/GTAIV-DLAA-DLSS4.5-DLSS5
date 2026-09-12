$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'feeder-src\src\dlss5-feed.cpp'
if (-not (Test-Path $source)) {
    throw "Feeder source not found: $source"
}

$text = [IO.File]::ReadAllText($source)
$hadCrLf = $text.Contains("`r`n")
$norm = $text.Replace("`r`n", "`n")

$marker = 'M3B-1: waiting for moving gameplay; depth valid, MV probe insufficient'
if ($norm.Contains($marker)) {
    Write-Host 'M3B-1 loading/MV retry fix is already applied.'
    exit 0
}

$oldGate = @'
    if (!g_m2b_depth_valid)
    {
        if (g.dlfg_last_skip_frame == 0 || frame - g.dlfg_last_skip_frame >= 300)
        {
            g.dlfg_last_skip_frame = frame;
            Log("[feed] M3B-1: waiting for valid non-flat depth from the existing 600-frame probe");
        }
        return true;
    }

    if (g.dlfg_feature == nullptr)
'@

$newGate = @'
    if (!g_m2b_depth_valid)
    {
        if (g.dlfg_last_skip_frame == 0 || frame - g.dlfg_last_skip_frame >= 300)
        {
            g.dlfg_last_skip_frame = frame;
            Log("[feed] M3B-1: waiting for valid non-flat depth from the existing 600-frame probe");
        }
        return true;
    }

    // Loading/menu transitions can expose valid depth before Lumenite's motion-vector
    // probe reflects moving gameplay. Do not consume the one-shot A/B attempt there.
    constexpr double kM3b1MinMovingMvMeanPx = 0.05;
    if (g_mv_probe_mean_px <= kM3b1MinMovingMvMeanPx)
    {
        if (g.dlfg_last_skip_frame == 0 || frame - g.dlfg_last_skip_frame >= 300)
        {
            g.dlfg_last_skip_frame = frame;
            Log("[feed] M3B-1: waiting for moving gameplay; depth valid, MV probe insufficient (mean=%.6f px, need > %.3f px)",
                g_mv_probe_mean_px, kM3b1MinMovingMvMeanPx);
        }
        return true;
    }

    if (g.dlfg_feature == nullptr)
    {
        Log("[feed] M3B-1: moving gameplay detected; arming on current guide probe (meanMV=%.6f px)",
            g_mv_probe_mean_px);
'@

# newGate intentionally opens the existing feature-null block, so remove its original opening brace.
$oldFeatureStart = @'
    if (g.dlfg_feature == nullptr)
    {
'@

if (-not $norm.Contains($oldGate)) {
    throw 'Could not find the expected M3B-1 depth/arming block. Source differs from the hardware-tested checkpoint; no changes made.'
}

# Replace through the feature-null line, then consume the original brace exactly once.
$norm = $norm.Replace($oldGate, $newGate)
$featureBraceNeedle = "`n    {`n        if (!M3b1CheckCapabilities())"
if (-not $norm.Contains($featureBraceNeedle)) {
    throw 'Could not align the M3B-1 feature-create block after arming edit; no file written.'
}
$norm = $norm.Replace($featureBraceNeedle, "`n        if (!M3b1CheckCapabilities())")

$oldReject = @'
    if (g.dlfg_owner == 2 && g_mv_probe_mean_px <= 0.0001 && diff_ab >= material)
    {
        M2bFail("motion vectors were zero while frames A and B contained material motion");
        return;
    }
'@

$newReject = @'
    if (g.dlfg_owner == 2 && g_mv_probe_mean_px <= 0.0001 && diff_ab >= material)
    {
        // This is a bad temporal pair, not a terminal M3B-1 failure. It commonly
        // happens at the end of GTA IV loading before the MV probe catches up.
        Log("[feed] M3B-1: temporal pair rejected: motion vectors were zero while A/B contained material motion; retrying when moving gameplay is detected");
        g.dlfg_state = kM2bIdle;
        g.dlfg_history_frame = 0;
        g.dlfg_readback_fence = 0;
        g.dlfg_last_skip_frame = 0;
        g.m3b1a_copy_queued = false;
        g.m3b1a_source_frame = 0;
        g.m3b1_ready_value = 0;
        return;
    }
'@

if (-not $norm.Contains($oldReject)) {
    throw 'Could not find the expected terminal zero-MV rejection block. Source differs from the hardware-tested checkpoint; no file written.'
}
$norm = $norm.Replace($oldReject, $newReject)

if ($hadCrLf) { $norm = $norm.Replace("`n", "`r`n") }
[IO.File]::WriteAllText($source, $norm, [Text.UTF8Encoding]::new($false))

Write-Host 'Applied M3B-1 loading/MV retry fix:'
Write-Host '  - waits for depth + mean MV > 0.05 px before the one-shot A/B sequence'
Write-Host '  - zero-MV/material-motion validation rejection is retryable, not terminal'
Write-Host "Updated: $source"
