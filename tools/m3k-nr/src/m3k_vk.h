// SPDX-License-Identifier: MIT
// GTA IV adapter to the pinned Feeder 0.15.1 Vulkan path. Copyright 2026 JungleHam.
// M3kRecordVkInputs below is moved verbatim (apart from indentation) from Feeder
// 3f624855276c4bde55145c712782477639b30e85, Copyright 2026 Jean-Laurent ROUZIES
// and NIGos. The build patch defines it before including this header.
#pragma once

// A2-S0 source-tap ABI exported by the instrumented vanilla DXVK 3.0.2 runtime.
// A2-S0.5 can optionally use the same handle for a visible 1:1 GPU copy proof.
// Neither stage changes the NGX contract.
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
// A2-S0.5: visible proof that the Feeder can actually issue a GPU read from the
// true low-resolution D3D9 source image exported by DXVK. This is deliberately
// diagnostic-only: no scaling, no NR, no SR, and it is OFF by default.
// CPU contract tests intentionally do not include Vulkan; keep this runtime-only.
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

    if (info.format != static_cast<UINT>(VK_FORMAT_B8G8R8A8_UNORM) ||
        g.bb_fmt != DXGI_FORMAT_B8G8R8A8_UNORM)
    {
        static bool said = false;
        if (!said)
        {
            said = true;
            Log("M3K-A2-S0.5: GPU proof blocked: source VkFormat=%u, final DXGI format=%u",
                info.format, static_cast<UINT>(g.bb_fmt));
        }
        return;
    }

    const VkImageLayout srcLayout = static_cast<VkImageLayout>(info.layout);
    if (srcLayout != VK_IMAGE_LAYOUT_GENERAL &&
        srcLayout != VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
    {
        static bool said = false;
        if (!said)
        {
            said = true;
            Log("M3K-A2-S0.5: GPU proof blocked: unsupported source layout=%u", info.layout);
        }
        return;
    }

    // Do nothing until the genuine low-res-source / high-res-presenter split exists.
    if (info.presenterWidth != finalW || info.presenterHeight != finalH ||
        (info.width >= finalW && info.height >= finalH))
        return;

    const VkImage sourceImage = FeedVkHandle<VkImage>(info.image);
    if (sourceImage == VK_NULL_HANDLE || sourceImage == finalImage)
        return;

    // For 1920x1080 -> 2560x1440 this copies 1280x1080, 1:1, into the
    // top-left of the final frame. The visible pixel-size mismatch is intentional.
    const UINT halfW = finalW / 2u;
    const UINT copyW = info.width < halfW ? info.width : halfW;
    const UINT copyH = info.height < finalH ? info.height : finalH;
    if (!copyW || !copyH)
        return;

    // Keep DXVK's tracked source layout unchanged; this barrier only publishes
    // prior writes to the raw command that follows.
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
#else
        const bool sourceProof = false;
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
    }

    // A2-S0 remains independent of NR Mode 0/1/2. A2-S0.5 is separately gated
    // by SourceProof and only acts later, while the final Vulkan image is copy_dest.
    M3kProbeDxvkPresentSource();

    g_m3kArmed = false;
    if (!g_m3kMode || g_cfg.mode != 2 || g_cfg.passthrough || !g.ngx_inited || !g.feature) return;
    // This branch is a native real-frame experiment; reject any resampled or
    // Super Resolution configuration without changing Feeder's chosen mode.
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
    // Copy the whole existing contract. Only Color and reset at the A/B boundary
    // may differ; all temporal guides, exposure, scale, and mask stay identical.
    auto dlaa = *ep;
    int nr = g_m3kMode == 2 && g_m3kArmed ? g_m3k.Evaluate(g.list, *ep) : 0;
    if (nr < 0) {
        // Neither input copies nor NR commands have been submitted yet. Drop
        // ALL of them, then reproduce the same-frame input copies/barriers from
        // the original Vulkan transport. The queue's existing input-fence wait
        // remains in force. Never submit a partial failing NR command stream.
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
