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

$funcStart = $norm.IndexOf('static bool M3b1MaybeRecord(')
$funcEnd = $norm.IndexOf('static void M2cFail(', $funcStart)
if ($funcStart -lt 0 -or $funcEnd -lt 0) {
    throw 'Could not locate M3b1MaybeRecord/M2cFail anchors; no changes made.'
}

# Insert inside the existing M3B-1 prerequisite failure block instead of replacing
# its failure statement. This is resilient to prior edits of the exact M2bFail text.
$ifPos = $norm.IndexOf('    if (frame <= 1', $funcStart)
if ($ifPos -lt 0 -or $ifPos -ge $funcEnd) {
    throw 'Could not locate the M3B-1 prerequisite condition; no file written.'
}

$openBrace = $norm.IndexOf("`n    {", $ifPos)
if ($openBrace -lt 0 -or $openBrace -ge $funcEnd) {
    throw 'Could not locate the M3B-1 prerequisite block opening brace; no file written.'
}
$insertAt = $openBrace + "`n    {".Length

$insert = @'

        if (g_cfg.dlfg_m3b2b_native != 0)
        {
            // M3B-2B can become active earlier in startup than the old one-shot test did.
            // Do not poison the stream permanently when the normal NGX feature or one of
            // the interop resources is simply not ready yet; wait and log each prerequisite.
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
'@

$norm = $norm.Insert($insertAt, $insert)

if ($hadCrLf) { $norm = $norm.Replace("`n", "`r`n") }
[IO.File]::WriteAllText($source, $norm, [Text.UTF8Encoding]::new($false))

Write-Host 'Applied M3B-2B bootstrap prerequisite retry/diagnostic fix:'
Write-Host '  - M3B-2B retries inside the existing prerequisite failure block'
Write-Host '  - logs each prerequisite as 0/1 so the remaining blocker is explicit'
Write-Host '  - explicit M3B-1 one-shot failure behaviour remains unchanged'
