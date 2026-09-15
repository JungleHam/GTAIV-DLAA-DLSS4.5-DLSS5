# A2-S2 build-only source transform.
# Keeps the proven A2-S1 source files unchanged until the first NR->SR runtime gate passes.
# The generated copies are compiled from tools/m3k-nr/_work/m3k-src-s2.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$GeneratedRoot
)

$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0
    $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) {
        $count++
        $pos = $i + $Old.Length
    }
    if ($count -ne 1) { throw "A2-S2 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

if (-not (Test-Path -LiteralPath $SourceRoot)) { throw "Missing M3K source root: $SourceRoot" }
if (Test-Path -LiteralPath $GeneratedRoot) { Remove-Item -LiteralPath $GeneratedRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $GeneratedRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $SourceRoot '*') -Destination $GeneratedRoot -Recurse -Force

$nrPath = Join-Path $GeneratedRoot 'm3k_nr.h'
$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $nrPath) -or -not (Test-Path -LiteralPath $vkPath)) {
    throw 'Generated M3K headers missing'
}

$nr = [IO.File]::ReadAllText($nrPath)
$vk = [IO.File]::ReadAllText($vkPath)

# Feature 18 is created at the true low render size, but A2-S1's shared D3D12
# transport textures remain presenter-sized. The private feature-18 contract already
# carries explicit 0,0 render subrects, so accept resources that are at least as large
# as the low-res contract instead of requiring the allocation itself to be low-res.
$nrOld = @'
        bool valid = cd.Width == w_ && cd.Height == h_ && dd.Width == w_ && dd.Height == h_ &&
            md.Width == w_ && md.Height == h_ && dd.Format == DXGI_FORMAT_R32_FLOAT && md.Format == DXGI_FORMAT_R16G16_FLOAT &&
            cd.SampleDesc.Count == 1 && dd.SampleDesc.Count == 1 && md.SampleDesc.Count == 1 &&
            (cd.Format == DXGI_FORMAT_B8G8R8A8_UNORM || cd.Format == DXGI_FORMAT_R8G8B8A8_UNORM || cd.Format == DXGI_FORMAT_R16G16B16A16_FLOAT);
        if (!valid || !MakeOutput()) {
'@
$nrNew = @'
        bool valid = cd.Width >= w_ && cd.Height >= h_ && dd.Width >= w_ && dd.Height >= h_ &&
            md.Width >= w_ && md.Height >= h_ && dd.Format == DXGI_FORMAT_R32_FLOAT && md.Format == DXGI_FORMAT_R16G16_FLOAT &&
            cd.SampleDesc.Count == 1 && dd.SampleDesc.Count == 1 && md.SampleDesc.Count == 1 &&
            (cd.Format == DXGI_FORMAT_B8G8R8A8_UNORM || cd.Format == DXGI_FORMAT_R8G8B8A8_UNORM || cd.Format == DXGI_FORMAT_R16G16B16A16_FLOAT);
        if (valid && (cd.Width != w_ || cd.Height != h_ || dd.Width != w_ || dd.Height != h_ || md.Width != w_ || md.Height != h_)) {
            static bool saidSubrect = false;
            if (!saidSubrect) {
                saidSubrect = true;
                Log("M3K-A2-S2: feature 18 uses %ux%u subrect inside shared color=%llux%u depth=%llux%u mv=%llux%u resources",
                    w_, h_, static_cast<unsigned long long>(cd.Width), cd.Height,
                    static_cast<unsigned long long>(dd.Width), dd.Height,
                    static_cast<unsigned long long>(md.Width), md.Height);
            }
        }
        if (!valid || !MakeOutput()) {
'@
$nr = Replace-ExactOnce $nr $nrOld $nrNew 'feature18 shared-resource subrect validation'

# SRProof may now run either raw-SR (Mode=0) or NR->SR (Mode=2).
$modeOld = @'
    if (g_m3kMode != 0)
    {
        static bool saidMode = false;
        if (!saidMode)
        {
            saidMode = true;
            Log("M3K-A2-S1: SRProof waits for M3K Mode=0; NR is intentionally excluded from A2-S1");
        }
        return;
    }
'@
$modeNew = @'
    if (g_m3kMode != 0 && g_m3kMode != 2)
    {
        if (g_m3kSrFeatureActive)
            M3kRestoreDlaaFeature();
        static bool saidMode = false;
        if (!saidMode)
        {
            saidMode = true;
            Log("M3K-A2-S2: SRProof requires Mode=0 (raw SR) or Mode=2 (feature18 NR -> SR)");
        }
        return;
    }
'@
$vk = Replace-ExactOnce $vk $modeOld $modeNew 'SR mode gate'

# When the independent low-res/presenter split is active, create feature18 at the
# true source resolution, not at the presenter resolution. The SR feature remains
# the final 1600x900 -> 2560x1440 reconstruction stage.
$prepareOld = @'
    g_m3kArmed = false;
    if (!g_m3kMode || g_cfg.mode != 2 || g_cfg.passthrough || !g.ngx_inited || !g.feature) return;
    // Native feature18 remains intentionally isolated from the SR experiment.
    const auto out = g.tex12[SLOT_OUTPUT]->GetDesc();
    if (g.sr_active || g_cfg.work_resolution != 100 || out.Width != g.width || out.Height != g.height) {
        static bool said = false;
        if (!said) Log("M3K: NR bypass: native work_resolution=100 / DLAA required");
        said = true; return;
    }
    g_m3kArmed = g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags);
}
'@
$prepareNew = @'
    g_m3kArmed = false;
    if (!g_m3kMode || g_cfg.mode != 2 || g_cfg.passthrough || !g.ngx_inited || !g.feature) return;
    const auto out = g.tex12[SLOT_OUTPUT]->GetDesc();

#if defined(VK_VERSION_1_0)
    if (g_m3kSrFeatureActive)
    {
        if (g_m3kMode != 2 || !g_m3kSrW || !g_m3kSrH || !g_m3kSrOutW || !g_m3kSrOutH)
            return;
        if (g_cfg.work_resolution != 100 || out.Width != g_m3kSrOutW || out.Height != g_m3kSrOutH)
        {
            static bool saidS2Block = false;
            if (!saidS2Block)
            {
                saidS2Block = true;
                Log("M3K-A2-S2: NR bypass: SR output resource/presenter mismatch");
            }
            return;
        }
        g_m3kArmed = g_m3k.Prepare(g_self, g.dev12, g.queue, g_m3kSrW, g_m3kSrH, g.create_flags);
        static bool saidS2Ready = false;
        if (g_m3kArmed && !saidS2Ready)
        {
            saidS2Ready = true;
            Log("M3K-A2-S2: feature 18 armed at true source %ux%u before DLSS SR -> %ux%u",
                g_m3kSrW, g_m3kSrH, g_m3kSrOutW, g_m3kSrOutH);
        }
        return;
    }
#endif

    if (g.sr_active || g_cfg.work_resolution != 100 || out.Width != g.width || out.Height != g.height) {
        static bool said = false;
        if (!said) Log("M3K: NR bypass: native work_resolution=100 / DLAA required");
        said = true; return;
    }
    g_m3kArmed = g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags);
}
'@
$vk = Replace-ExactOnce $vk $prepareOld $prepareNew 'low-res feature18 prepare path'

# Chain feature18 ahead of the already-proven SR evaluation. If feature18 records a
# bad frame, discard that unsubmitted D3D12 list and replay the same frame as raw SR.
$evalOld = @'
    if (g_m3kSrFeatureActive)
    {
        // A2-S1A functional proof. True 1080 colour + 1080 guide subrect go to a
        // genuine SR feature whose Output resource remains the native 1440 target.
        auto sr = *ep;
        sr.InRenderSubrectDimensions.Width  = g_m3kSrW;
        sr.InRenderSubrectDimensions.Height = g_m3kSrH;
        sr.InJitterOffsetX = 0.0f;
        sr.InJitterOffsetY = 0.0f;
        sr.InMVScaleX = ep->InMVScaleX * (static_cast<float>(g_m3kSrW) / static_cast<float>(g_m3kSrOutW));
        sr.InMVScaleY = ep->InMVScaleY * (static_cast<float>(g_m3kSrH) / static_cast<float>(g_m3kSrOutH));
        sr.pInBiasCurrentColorMask = nullptr;
        if (g_m3kSrNeedsReset) sr.InReset = 1;

        const NVSDK_NGX_Result result = SafeEvaluateDLSS(&sr, code);
        if (*code || NVSDK_NGX_FAILED(result))
        {
            g_m3kSrLatchedFail = true;
            Log("M3K-A2-S1: SR evaluate failed result=0x%08X exception=0x%08X; Feeder will discard/rebuild this frame",
                result, *code);
            return result;
        }

        g_m3kSrNeedsReset = false;
        g_m3kWasUsed = false;
        static UINT64 srFrames = 0;
        ++srFrames;
        if (srFrames == 1 || (srFrames % 300) == 0)
            Log("M3K-A2-S1: DLSS SR running %ux%u -> %ux%u result=0x%08X reset=%d mvScale=(%.3f,%.3f) jitter=(0,0)",
                g_m3kSrW, g_m3kSrH, g_m3kSrOutW, g_m3kSrOutH, result, sr.InReset,
                sr.InMVScaleX, sr.InMVScaleY);
        return result;
    }
'@
$evalNew = @'
    if (g_m3kSrFeatureActive)
    {
        // A2-S2: true low-res DXVK color + scaled guides -> feature18 at low-res ->
        // the already-proven DLSS SR feature -> presenter resolution. Jitter remains
        // zero for this functional gate; temporal-quality work stays a later milestone.
        auto sr = *ep;
        sr.InRenderSubrectDimensions.Width  = g_m3kSrW;
        sr.InRenderSubrectDimensions.Height = g_m3kSrH;
        sr.InJitterOffsetX = 0.0f;
        sr.InJitterOffsetY = 0.0f;
        sr.InMVScaleX = ep->InMVScaleX * (static_cast<float>(g_m3kSrW) / static_cast<float>(g_m3kSrOutW));
        sr.InMVScaleY = ep->InMVScaleY * (static_cast<float>(g_m3kSrH) / static_cast<float>(g_m3kSrOutH));
        sr.pInBiasCurrentColorMask = nullptr;
        if (g_m3kSrNeedsReset) sr.InReset = 1;

        int nr = g_m3kMode == 2 && g_m3kArmed ? g_m3k.Evaluate(g.list, sr) : 0;
        if (nr < 0)
        {
            AbortCommands();
            Log("M3K-A2-S2: feature 18 recording discarded; replaying same-frame raw low-res source -> DLSS SR");
            if (!BeginCommands())
            {
                *code = ERROR_GEN_FAILURE;
                return NVSDK_NGX_Result_Fail;
            }
            M3kRecordVkInputs();
            sr.InReset = 1;
        }

        const bool used = nr == 1;
        if (used != g_m3kWasUsed)
        {
            sr.InReset = 1;
            Log("M3K-A2-S2: SR color source=%s; temporal history reset=1",
                used ? "feature18 NR output" : "raw true DXVK source");
        }
        if (used)
            sr.Feature.pInColor = g_m3k.Output();

        const NVSDK_NGX_Result result = SafeEvaluateDLSS(&sr, code);
        if (used && *code == 0)
            g_m3k.Finish(g.list);
        if (*code || NVSDK_NGX_FAILED(result))
        {
            g_m3k.ResetHistory();
            g_m3kWasUsed = false;
            g_m3kSrLatchedFail = true;
            Log("M3K-A2-S2: SR evaluate failed result=0x%08X exception=0x%08X; Feeder will discard/rebuild this frame",
                result, *code);
            return result;
        }

        g_m3kSrNeedsReset = false;
        g_m3kWasUsed = used;
        static UINT64 srFrames = 0;
        ++srFrames;
        if (srFrames == 1 || (srFrames % 300) == 0)
            Log("M3K-A2-S2: %s -> DLSS SR running %ux%u -> %ux%u result=0x%08X reset=%d mvScale=(%.3f,%.3f) jitter=(0,0)",
                used ? "NR18" : "RAW", g_m3kSrW, g_m3kSrH, g_m3kSrOutW, g_m3kSrOutH,
                result, sr.InReset, sr.InMVScaleX, sr.InMVScaleY);
        return result;
    }
'@
$vk = Replace-ExactOnce $vk $evalOld $evalNew 'feature18 to SR evaluation chain'

[IO.File]::WriteAllText($nrPath, $nr, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($vkPath, $vk, (New-Object Text.UTF8Encoding($false)))

$nrVerify = [IO.File]::ReadAllText($nrPath)
$vkVerify = [IO.File]::ReadAllText($vkPath)
foreach ($marker in @(
    'M3K-A2-S2: feature 18 uses',
    'M3K-A2-S2: feature 18 armed at true source',
    'M3K-A2-S2: SR color source=',
    'M3K-A2-S2: %s -> DLSS SR running')) {
    if (($nrVerify + $vkVerify).IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A2-S2 verification marker missing: $marker"
    }
}

Write-Host "A2-S2 generated source ready: $GeneratedRoot"
Write-Host 'Base A2-S1 headers were not modified.'
