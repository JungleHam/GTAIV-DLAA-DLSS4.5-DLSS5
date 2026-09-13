$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot '..\m2b\feeder-src\src\dlss5-feed.cpp'
if (!(Test-Path $source)) { throw "Feeder source not found: $source" }

$text = [IO.File]::ReadAllText($source)
$hadCrLf = $text.Contains("`r`n")
$norm = $text.Replace("`r`n", "`n")

$marker = 'M3B-2B: bootstrap prerequisites not ready; retrying'
if ($norm.Contains($marker)) {
    Write-Host 'M3B-2B prerequisite retry/diagnostic fix is already applied.'
    exit 0
}

# Patch only the stable terminal action inside M3b1MaybeRecord rather than matching
# the entire surrounding prerequisite condition. Earlier M3B-1/M3B-2B patches can
# legitimately change that condition's formatting/gates while this failure call stays
# the same. This keeps the patch resilient and preserves the original one-shot path.
$old = @'
        M2bFail("required existing NGX/session and 2560x1440 shared B8/R32/R16G16 resources are unavailable");
        return true;
'@

$new = @'
        if (g_cfg.dlfg_m3b2b_native != 0)
        {
            // M3B-2B can become active earlier in startup than the old one-shot test did.
            // A temporarily missing normal NGX feature or interop resource must not poison
            // the native-stream state permanently. Wait for the exact proven prerequisites
            // and report each component so a genuinely missing resource is diagnosable.
            static UINT64 s_m3b2b_last_prereq_log = 0;
            if (s_m3b2b_last_prereq_log == 0 || frame - s_m3b2b_last_prereq_log >= 300)
            {
                s_m3b2b_last_prereq_log = frame;
                Log("[feed] M3B-2B: bootstrap prerequisites not ready; retrying "
                    "(frameOk=%d sizeOk=%d colorOk=%d outputFmtOk=%d outputTex=%d depthTex=%d mvTex=%d "
                    "sharedOut=%d sharedReleased=%d normalFeature=%d ngxInited=%d)",
                    frame > 1 ? 1 : 0,
                    (g.width == 2560 && g.height == 1440) ? 1 : 0,
                    g.color_fmt == DXGI_FORMAT_B8G8R8A8_UNORM ? 1 : 0,
                    g.output_fmt == DXGI_FORMAT_B8G8R8A8_UNORM ? 1 : 0,
                    g.tex12[SLOT_OUTPUT] != nullptr ? 1 : 0,
                    g.tex12[SLOT_DEPTH] != nullptr ? 1 : 0,
                    g.tex12[SLOT_MV] != nullptr ? 1 : 0,
                    g.m3b1a_tex12 != nullptr ? 1 : 0,
                    g.m3b1a_vk_released ? 1 : 0,
                    g.feature != nullptr ? 1 : 0,
                    g.ngx_inited ? 1 : 0);
            }
            return true;
        }

        // Preserve the exact known-good M3B-1 one-shot failure behaviour when M3B-2B
        // is not the owner of the experiment.
        M2bFail("required existing NGX/session and 2560x1440 shared B8/R32/R16G16 resources are unavailable");
        return true;
'@

$pos = $norm.IndexOf($old)
if ($pos -lt 0) {
    throw 'Could not find the stable M3B-1 prerequisite failure action; no file written.'
}
$second = $norm.IndexOf($old, $pos + $old.Length)
if ($second -ge 0) {
    throw 'Found more than one M3B-1 prerequisite failure action; refusing ambiguous patch.'
}
$norm = $norm.Remove($pos, $old.Length).Insert($pos, $new)

if ($hadCrLf) { $norm = $norm.Replace("`n", "`r`n") }
[IO.File]::WriteAllText($source, $norm, [Text.UTF8Encoding]::new($false))

Write-Host 'Applied M3B-2B bootstrap prerequisite retry/diagnostic fix:'
Write-Host '  - M3B-2B retries temporary missing bootstrap resources instead of permanently failing'
Write-Host '  - logs each prerequisite as 0/1 so the remaining blocker is explicit'
Write-Host '  - explicit M3B-1 one-shot behaviour is unchanged'
