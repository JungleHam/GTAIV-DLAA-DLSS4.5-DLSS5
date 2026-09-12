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

# Patch by stable function anchors instead of matching a large formatting-sensitive block.
$funcStart = $norm.IndexOf('static bool M3b1MaybeRecord(')
$funcEnd = $norm.IndexOf('static void M2cFail(', $funcStart)
if ($funcStart -lt 0 -or $funcEnd -lt 0) {
    throw 'Could not locate M3b1MaybeRecord/M2cFail anchors; no changes made.'
}

$featureNeedle = "    if (g.dlfg_feature == nullptr)`n    {"
$featurePos = $norm.IndexOf($featureNeedle, $funcStart)
if ($featurePos -lt 0 -or $featurePos -ge $funcEnd) {
    throw 'Could not locate the M3B-1 feature-create block; no changes made.'
}

$gate = @'
    // GTA IV loading/menu transitions can expose valid depth before Lumenite's
    // motion-vector probe reflects moving gameplay. Do not consume the one-shot
    // A/B attempt until the latest guide probe shows meaningful motion.
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

'@

$norm = $norm.Insert($featurePos, $gate)

# Log exactly when the one-shot is finally allowed to arm.
$funcEnd = $norm.IndexOf('static void M2cFail(', $funcStart)
$featurePos = $norm.IndexOf($featureNeedle, $funcStart)
$openBraceEnd = $featurePos + $featureNeedle.Length
$armLog = @'

        Log("[feed] M3B-1: moving gameplay detected; arming on current guide probe (meanMV=%.6f px)",
            g_mv_probe_mean_px);
'@
$norm = $norm.Insert($openBraceEnd, $armLog)

# Make the final zero-MV/material-motion validation rejection retryable instead of terminal.
$rejectNeedle = '        M2bFail("motion vectors were zero while frames A and B contained material motion");'
$rejectPos = $norm.IndexOf($rejectNeedle)
if ($rejectPos -lt 0) {
    throw 'Could not find the M3B-1 zero-MV rejection line; no file written.'
}

$retry = @'
        // Bad temporal pair, not a terminal M3B-1 failure. This commonly occurs
        // at the end of GTA IV loading before the periodic MV probe catches up.
        Log("[feed] M3B-1: temporal pair rejected: motion vectors were zero while A/B contained material motion; retrying when moving gameplay is detected");
        g.dlfg_state = kM2bIdle;
        g.dlfg_history_frame = 0;
        g.dlfg_readback_fence = 0;
        g.dlfg_last_skip_frame = 0;
        // The image has not been published to Vulkan on a rejected pair, so it is
        // safe to reuse it for the next one-shot attempt.
        g.m3b1a_copy_queued = false;
        g.m3b1a_source_frame = 0;
        g.m3b1_ready_value = 0;
'@
$norm = $norm.Remove($rejectPos, $rejectNeedle.Length).Insert($rejectPos, $retry)

if ($hadCrLf) { $norm = $norm.Replace("`n", "`r`n") }
[IO.File]::WriteAllText($source, $norm, [Text.UTF8Encoding]::new($false))

Write-Host 'Applied M3B-1 loading/MV retry fix:'
Write-Host '  - waits for valid depth plus mean MV > 0.05 px before arming'
Write-Host '  - zero-MV/material-motion validation rejection is retryable, not terminal'
Write-Host "Updated: $source"
