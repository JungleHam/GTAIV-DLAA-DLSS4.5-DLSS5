// SPDX-License-Identifier: MIT
// GTA IV adapter to the pinned Feeder 0.15.1 Vulkan path. Copyright 2026 JungleHam.
// M3kRecordVkInputs below is moved verbatim (apart from indentation) from Feeder
// 3f624855276c4bde55145c712782477639b30e85, Copyright 2026 Jean-Laurent ROUZIES
// and NIGos. The build patch defines it before including this header.
#pragma once

// A2-S0 source-tap ABI exported by the instrumented vanilla DXVK 3.0.2 runtime.
// A2-S0.5 can optionally use the same handle for a visible 1:1 GPU copy proof.
// A2-S1A reuses that same source as the real low-resolution DLSS-SR colour input.
struct M3kDxvkPresentSourceV1
{
    UINT size;
    UINT version;
    UINT64 sequence;
    UINT64 image;
    UINT64 view;
    UINT64 device;
    UINT width;
    UINT height;
    UINT format;
    UINT layout;
    UINT presenterWidth;
    UINT presenterHeight;
};
using M3kQueryPresentSourceV1 = int (__cdecl *)(M3kDxvkPresentSourceV1 *);

static M3kDxvkPresentSourceV1 g_m3kPresentSource = {};
static bool g_m3kSourceTapReady = false;
static bool g_m3kSourceProof = false;

#if defined(VK_VERSION_1_0)
static bool g_m3kSrRequested = false;
static bool g_m3kSrFeatureActive = false;
static bool g_m3kSrLatchedFail = false;
static bool g_m3kSrNeedsReset = true;
static UINT g_m3kSrW = 0, g_m3kSrH = 0, g_m3kSrOutW = 0, g_m3kSrOutH = 0;
#endif

static void M3kProbeDxvkPresentSource()
{
    static HMODULE dxvk = nullptr;
    static M3kQueryPresentSourceV1 query = nullptr;
    static bool missingExportReported = false;
    static UINT64 samples = 0;
    static UINT lastW = 0, lastH = 0, lastPW = 0, lastPH = 0;

    if (!dxvk)
        dxvk = GetModuleHandleW(L"d3d9vk_x64.dll");
    if (dxvk && !query)
        query = reinterpret_cast<M3kQueryPresentSourceV1>(GetProcAddress(dxvk, "M3K_QueryPresentSourceV1"));

    if (!query)
    {
        g_m3kSourceTapReady = false;
        if (dxvk && !missingExportReported)
        {
            missingExportReported = true;
            Log("M3K-A2-S0: d3d9vk_x64.dll has no M3K_QueryPresentSourceV1 export; source tap inactive");
        }
        return;
    }

    M3kDxvkPresentSourceV1 info = {};
    info.size = sizeof(info);
    if (!query(&info) || info.version != 1 || info.size < sizeof(info) || !info.image || !info.width || !info.height)
    {
        g_m3kSourceTapReady = false;
        return;
    }

    g_m3kPresentSource = info;
    g_m3kSourceTapReady = true;
    ++samples;

    const bool changed = info.width != lastW || info.height != lastH ||
                         info.presenterWidth != lastPW || info.presenterHeight != lastPH;
    if (samples == 1 || changed || (samples % 300) == 0)
    {
        Log("M3K-A2-S0: DXVK source tap OK seq=%llu source=%ux%u presenter=%ux%u fmt=%u layout=%u image=0x%llX device=0x%llX",
            static_cast<unsigned long long>(info.sequence),
            info.width, info.height, info.presenterWidth, info.presenterHeight,
            info.format, info.layout,
            static_cast<unsigned long long>(info.image),
            static_cast<unsigned long long>(info.device));
        lastW = info.width; lastH = info.height;
        lastPW = info.presenterWidth; lastPH = info.presenterHeight;
    }
}

#if defined(VK_VERSION_1_0)
static bool M3kBgra8SourceCompatible()
{
    const bool sourceBgra8 = g_m3kPresentSource.format == static_cast<UINT>(VK_FORMAT_B8G8R8A8_UNORM);
    const bool feederBgra8 = g.color_fmt == DXGI_FORMAT_B8G8R8A8_UNORM;
    return sourceBgra8 && feederBgra8;
}

// A2-S0.5: visible proof that the Feeder can actually issue a GPU read from the
// true low-resolution D3D9 source image exported by DXVK. This is deliberately
// diagnostic-only: no scaling, no NR, no SR, and it is OFF by default.
static void M3kSourceGpuProof(VkCommandBuffer cb, VkImage finalImage, UINT finalW, UINT finalH)
{
    if (!g_m3kSourceProof || !g_m3kSourceTapReady || !g.vk.ok ||
        cb == VK_NULL_HANDLE || finalImage == VK_NULL_HANDLE)
        return;

    const M3kDxvkPresentSourceV1 info = g_m3kPresentSource;
    const UINT64 feederDevice = FeedVkValue(g.vk.dev);
    if (info.device != feederDevice)
    {
        static bool said = false;
        if (!said)
        {
            said = true;
            Log("M3K-A2-S0.5: GPU proof blocked: source VkDevice=0x%llX but Feeder VkDevice=0x%llX",
                static_cast<unsigned long long>(info.device),
                static_cast<unsigned long long>(feederDevice));
        }
        return;
    }

    const bool sourceBgra8 = info.format == static_cast<UINT>(VK_FORMAT_B8G8R8A8_UNORM);
    const bool finalBgra8 = g.bb_fmt == DXGI_FORMAT_B8G8R8A8_UNORM ||
                            g.bb_fmt == DXGI_FORMAT_B8G8R8A8_TYPELESS ||
                            g.bb_fmt == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB;
    if (!sourceBgra8 || !finalBgra8)
    {
        static bool said = false;
        if (!said)
        {
            said = true;
            Log("M3K-A2-S0.5: GPU proof blocked: incompatible source VkFormat=%u, final DXGI format=%u",
                info.format, static_cast<UINT>(g.bb_fmt));
        }
        return;
    }

    const VkImageLayout srcLayout = static_cast<VkImageLayout>(info.layout);
    if (srcLayout != VK_IMAGE_LAYOUT_GENERAL && srcLayout != VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
    {
        static bool said = false;
        if (!said)
        {
            said = true;
            Log("M3K-A2-S0.5: GPU proof blocked: unsupported source layout=%u", info.layout);
        }
        return;
    }

    if (info.presenterWidth != finalW || info.presenterHeight != finalH ||
        (info.width >= finalW && info.height >= finalH))
        return;

    const VkImage sourceImage = FeedVkHandle<VkImage>(info.image);
    if (sourceImage == VK_NULL_HANDLE || sourceImage == finalImage)
        return;

    const UINT halfW = finalW / 2u;
    const UINT copyW = info.width < halfW ? info.width : halfW;
    const UINT copyH = info.height < finalH ? info.height : finalH;
    if (!copyW || !copyH)
        return;

    FeedVkBarrier(&g.vk, cb, sourceImage, srcLayout, srcLayout);
    FeedVkCopyImage(&g.vk, cb, sourceImage, srcLayout,
                    finalImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, copyW, copyH);

    static UINT64 proofFrames = 0;
    ++proofFrames;
    if (proofFrames == 1 || (proofFrames % 300) == 0)
        Log("M3K-A2-S0.5: GPU source copy ACTIVE seq=%llu raw=%ux%u -> top-left %ux%u of final=%ux%u (1:1, no scaling)",
            static_cast<unsigned long long>(info.sequence),
            info.width, info.height, copyW, copyH, finalW, finalH);
}

static void M3kVkBlitScale(VkCommandBuffer cb, VkImage src, VkImageLayout srcLayout,
                           VkImage dst, VkImageLayout dstLayout,
                           UINT srcW, UINT srcH, UINT dstW, UINT dstH)
{
    VkImageBlit bl = {};
    bl.srcSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
    bl.dstSubresource = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 };
    bl.srcOffsets[1] = { static_cast<int32_t>(srcW), static_cast<int32_t>(srcH), 1 };
    bl.dstOffsets[1] = { static_cast<int32_t>(dstW), static_cast<int32_t>(dstH), 1 };
    g.vk.CmdBlitImage(cb, src, srcLayout, dst, dstLayout, 1, &bl, VK_FILTER_NEAREST);
}

static bool M3kSwapToSrFeature(UINT renderW, UINT renderH, UINT targetW, UINT targetH)
{
    if (!g.ngx_inited || g.feature == nullptr || g.dev12 == nullptr || g.queue == nullptr)
        return false;
    if (!PickSrQuality(renderW, renderH, targetW, targetH))
    {
        Log("M3K-A2-S1: no DLSS SR preset covers %ux%u -> %ux%u", renderW, renderH, targetW, targetH);
        return false;
    }

    NVSDK_NGX_Handle *old = g.feature;
    const bool oldSrActive = g.sr_active;
    const bool oldSrRequested = g.sr_requested;
    const UINT oldOutW = g.output_width, oldOutH = g.output_height;

    g.feature = nullptr;
    g.sr_requested = true;
    g.sr_active = true;
    g.output_width = targetW;
    g.output_height = targetH;

    const bool inverted = g_cfg.depth_inverted >= 0 ? g_cfg.depth_inverted != 0 : g.depth_reversed;
    bool crashed = false;
    const bool ok = CreateDlssFeature(renderW, renderH, inverted, &crashed);
    if (!ok)
    {
        if (g.feature != nullptr && g.feature != old)
            SafeReleaseFeature(g.feature);
        g.feature = old;
        g.sr_active = oldSrActive;
        g.sr_requested = oldSrRequested;
        g.output_width = oldOutW;
        g.output_height = oldOutH;
        g.frame_ready = true;
        g.warmup_done = true;
        Log("M3K-A2-S1: SR feature create %s; keeping previous DLAA feature",
            crashed ? "crashed (caught)" : "failed");
        return false;
    }

    DrainGpu();
    SafeReleaseFeature(old);
    g.warmup_done = true;
    g.need_reset = true;
    g_m3kSrFeatureActive = true;
    g_m3kSrNeedsReset = true;
    g_m3kSrW = renderW; g_m3kSrH = renderH;
    g_m3kSrOutW = targetW; g_m3kSrOutH = targetH;
    Log("M3K-A2-S1: SR feature ACTIVE %ux%u -> %ux%u DLSS %s (real DXVK source, proof jitter=0)",
        renderW, renderH, targetW, targetH, g.sr_quality_name);
    return true;
}

static bool M3kRestoreDlaaFeature()
{
    if (!g_m3kSrFeatureActive)
        return true;
    if (!g.ngx_inited || g.feature == nullptr || g.dev12 == nullptr || g.queue == nullptr)
    {
        g_m3kSrFeatureActive = false;
        g.sr_active = false;
        g.sr_requested = false;
        g.output_width = g.output_height = 0;
        return false;
    }

    NVSDK_NGX_Handle *old = g.feature;
    const bool oldSrActive = g.sr_active;
    const bool oldSrRequested = g.sr_requested;
    const UINT oldOutW = g.output_width, oldOutH = g.output_height;

    g.feature = nullptr;
    g.sr_active = false;
    g.sr_requested = false;
    g.output_width = g.output_height = 0;

    const bool inverted = g_cfg.depth_inverted >= 0 ? g_cfg.depth_inverted != 0 : g.depth_reversed;
    bool crashed = false;
    const bool ok = CreateDlssFeature(g.width, g.height, inverted, &crashed);
    if (!ok)
    {
        if (g.feature != nullptr && g.feature != old)
            SafeReleaseFeature(g.feature);
        g.feature = old;
        g.sr_active = oldSrActive;
        g.sr_requested = oldSrRequested;
        g.output_width = oldOutW;
        g.output_height = oldOutH;
        g.frame_ready = true;
        g.warmup_done = true;
        Log("M3K-A2-S1: baseline DLAA restore %s; keeping SR feature until restart/toggle retry",
            crashed ? "crashed (caught)" : "failed");
        return false;
    }

    DrainGpu();
    SafeReleaseFeature(old);
    g.warmup_done = true;
    g.need_reset = true;
    g_m3kSrFeatureActive = false;
    g_m3kSrNeedsReset = true;
    g_m3kSrW = g_m3kSrH = g_m3kSrOutW = g_m3kSrOutH = 0;
    Log("M3K-A2-S1: restored baseline %ux%u DLAA", g.width, g.height);
    return true;
}

static void M3kSrUpdate()
{
    if (g_m3kSrFeatureActive && !g.sr_active)
    {
        g_m3kSrFeatureActive = false;
        g_m3kSrNeedsReset = true;
        g_m3kSrW = g_m3kSrH = g_m3kSrOutW = g_m3kSrOutH = 0;
        Log("M3K-A2-S1: Feeder rebuilt the feature; SR state will be re-established if the split still qualifies");
    }

    if (!g_m3kSrRequested || !g_m3kSourceTapReady || g_m3kSourceProof)
    {
        if (g_m3kSrFeatureActive)
            M3kRestoreDlaaFeature();
        return;
    }

    if (g_m3kSrLatchedFail)
        return;

    const auto &info = g_m3kPresentSource;
    const bool split = info.presenterWidth == g.width && info.presenterHeight == g.height &&
                       info.width < info.presenterWidth && info.height < info.presenterHeight;
    if (!split)
    {
        if (g_m3kSrFeatureActive)
            M3kRestoreDlaaFeature();
        return;
    }

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
    if (g_cfg.mode != 2 || g_cfg.passthrough || !g.frame_ready)
        return;
    if (!M3kBgra8SourceCompatible())
    {
        static bool saidFmt = false;
        if (!saidFmt)
        {
            saidFmt = true;
            Log("M3K-A2-S1: SRProof blocked: source VkFormat=%u / Feeder color format=%u",
                info.format, static_cast<UINT>(g.color_fmt));
        }
        return;
    }
    if (info.device != FeedVkValue(g.vk.dev))
    {
        static bool saidDev = false;
        if (!saidDev)
        {
            saidDev = true;
            Log("M3K-A2-S1: SRProof blocked: source and Feeder VkDevice differ");
        }
        return;
    }

    if (g_m3kSrFeatureActive)
    {
        if (g_m3kSrW == info.width && g_m3kSrH == info.height &&
            g_m3kSrOutW == info.presenterWidth && g_m3kSrOutH == info.presenterHeight)
            return;
        if (!M3kRestoreDlaaFeature())
            return;
    }

    if (!M3kSwapToSrFeature(info.width, info.height, info.presenterWidth, info.presenterHeight))
    {
        g_m3kSrLatchedFail = true;
        Log("M3K-A2-S1: SRProof latched off after create failure; set SRProof=0 then 1 to retry");
    }
}

static void M3kSrCaptureVk(VkCommandBuffer cb, VkImage mvImage, VkImage depthImage, UINT finalW, UINT finalH)
{
    if (!g_m3kSrFeatureActive || !g_m3kSourceTapReady || cb == VK_NULL_HANDLE)
        return;
    const auto info = g_m3kPresentSource;
    if (info.width != g_m3kSrW || info.height != g_m3kSrH ||
        finalW != g_m3kSrOutW || finalH != g_m3kSrOutH)
        return;
    if (g.vk_img[SLOT_COLOR] == VK_NULL_HANDLE ||
        g.vk_img[SLOT_MV] == VK_NULL_HANDLE ||
        g.vk_img[SLOT_DEPTH] == VK_NULL_HANDLE)
        return;

    const VkImage sourceImage = FeedVkHandle<VkImage>(info.image);
    const VkImageLayout sourceLayout = static_cast<VkImageLayout>(info.layout);
    if (sourceImage == VK_NULL_HANDLE ||
        (sourceLayout != VK_IMAGE_LAYOUT_GENERAL && sourceLayout != VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL))
        return;

    FeedVkBarrier(&g.vk, cb, sourceImage, sourceLayout, sourceLayout);
    FeedVkCopyImage(&g.vk, cb, sourceImage, sourceLayout,
                    g.vk_img[SLOT_COLOR], VK_IMAGE_LAYOUT_GENERAL, info.width, info.height);

    // Guides are the only things resampled in A2-S1A. The GTA colour source is not.
    M3kVkBlitScale(cb, mvImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   g.vk_img[SLOT_MV], VK_IMAGE_LAYOUT_GENERAL,
                   finalW, finalH, info.width, info.height);
    M3kVkBlitScale(cb, depthImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   g.vk_img[SLOT_DEPTH], VK_IMAGE_LAYOUT_GENERAL,
                   finalW, finalH, info.width, info.height);

    static UINT64 frames = 0;
    ++frames;
    if (frames == 1 || (frames % 300) == 0)
        Log("M3K-A2-S1: captured true source %ux%u + scaled guides -> SR inputs; target=%ux%u seq=%llu",
            info.width, info.height, finalW, finalH,
            static_cast<unsigned long long>(info.sequence));
}
#endif

static int g_m3kMode = 0;
static bool g_m3kArmed = false, g_m3kWasUsed = false;

static void M3kPrepareFrame()
{
    static ULONGLONG nextPoll = 0;
    const ULONGLONG now = GetTickCount64();
    if (now >= nextPoll) {
        nextPoll = now + 1000;
        wchar_t path[MAX_PATH] = {};
        GetModuleFileNameW(g_self, path, MAX_PATH);
        if (wchar_t *slash = wcsrchr(path, L'\\')) {
            *(slash + 1) = 0;
            wcscat_s(path, L"m3k-nr.ini");
        }
        const UINT requested = GetPrivateProfileIntW(L"M3K", L"Mode", 0, path);
        const int mode = requested <= 2 ? int(requested) : 0;
#if defined(VK_VERSION_1_0)
        const bool sourceProof = GetPrivateProfileIntW(L"M3K", L"SourceProof", 0, path) != 0;
        const bool srProof = GetPrivateProfileIntW(L"M3K", L"SRProof", 0, path) != 0;
#else
        const bool sourceProof = false;
        const bool srProof = false;
#endif
        static bool first = true;
        if (first || mode != g_m3kMode) {
            Log("M3K: mode=%d (%s); config=%ls", mode,
                mode == 0 ? "NR disabled / existing DLAA" : mode == 1 ? "A0 create only / existing DLAA" : "A1 NR enabled before DLAA", path);
            g_m3k.ResetHistory();
            if (mode == 0) g_m3k.ShutdownRuntime(g_ngx_dying);
            g_m3kMode = mode; first = false;
        }
        static bool proofFirst = true;
        if (proofFirst || sourceProof != g_m3kSourceProof)
        {
            Log("M3K-A2-S0.5: SourceProof=%d (1 = raw true-source pixels overwrite the top-left of the final frame)",
                sourceProof ? 1 : 0);
            proofFirst = false;
        }
        g_m3kSourceProof = sourceProof;
#if defined(VK_VERSION_1_0)
        static bool srFirst = true;
        if (srFirst || srProof != g_m3kSrRequested)
        {
            Log("M3K-A2-S1: SRProof=%d (1 = true DXVK low-res source -> DLSS SR -> presenter resolution)",
                srProof ? 1 : 0);
            if (!srProof) g_m3kSrLatchedFail = false;
            srFirst = false;
        }
        g_m3kSrRequested = srProof;
#endif
    }

    M3kProbeDxvkPresentSource();
#if defined(VK_VERSION_1_0)
    M3kSrUpdate();
#endif

    g_m3kArmed = false;
    if (!g_m3kMode || g_cfg.mode != 2 || g_cfg.passthrough || !g.ngx_inited || !g.feature) return;
    const auto out = g.tex12[SLOT_OUTPUT]->GetDesc();
    if (g.sr_active || g_cfg.work_resolution != 100 || out.Width != g.width || out.Height != g.height) {
        static bool said = false;
        if (!said) Log("M3K: NR bypass: native work_resolution=100 / DLAA required");
        said = true; return;
    }
    g_m3kArmed = g_m3k.Prepare(g_self, g.dev12, g.queue, g.width, g.height, g.create_flags);
}

static NVSDK_NGX_Result M3kEvaluateBeforeDlaa(NVSDK_NGX_D3D12_DLSS_Eval_Params *ep, DWORD *code)
{
#if defined(VK_VERSION_1_0)
    if (g_m3kSrFeatureActive)
    {
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
            g_m3kSrFeatureActive = false;
            g.sr_active = false;
            g.sr_requested = false;
            g.output_width = g.output_height = 0;
            Log("M3K-A2-S1: SR evaluate failed result=0x%08X exception=0x%08X; latched off until SRProof toggles 0->1",
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
#endif

    auto dlaa = *ep;
    int nr = g_m3kMode == 2 && g_m3kArmed ? g_m3k.Evaluate(g.list, *ep) : 0;
    if (nr < 0) {
        AbortCommands();
        Log("M3K-A1: NR recording discarded; replaying same-frame raw input -> DLAA");
        if (!BeginCommands()) {
            *code = ERROR_GEN_FAILURE;
            return NVSDK_NGX_Result_Fail;
        }
        M3kRecordVkInputs();
        dlaa.InReset = 1;
    }
    const bool used = nr == 1;
    if (used != g_m3kWasUsed) {
        dlaa.InReset = 1;
        Log("M3K-A1: DLAA color source=%s; temporal history reset=1", used ? "NR output" : "original GTA color");
    }
    if (used) dlaa.Feature.pInColor = g_m3k.Output();
    const NVSDK_NGX_Result result = SafeEvaluateDLSS(&dlaa, code);
    if (used && *code == 0) g_m3k.Finish(g.list);
    if (*code || NVSDK_NGX_FAILED(result)) g_m3k.ResetHistory();
    g_m3kWasUsed = used && !*code && NVSDK_NGX_SUCCEED(result);
    static UINT64 nrDlaaFrames = 0;
    if (used && (++nrDlaaFrames == 1 || nrDlaaFrames % 300 == 0 || NVSDK_NGX_FAILED(result)))
        Log("M3K-A1: DLAA running after NR result=0x%08X reset=%d (same-frame guides retained)", result, dlaa.InReset);
    return result;
}
