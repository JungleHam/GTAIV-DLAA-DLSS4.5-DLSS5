// M3B-2B: continuous native NVIDIA DLSS-G producer.
//
// M3B-2A already proved the reusable D3D12/Vulkan transport and consumer-return
// synchronization. This layer keeps that transport intact and replaces its ordinary
// post-NR copy producer with feature-11 output from the already-proven M3B-1 session.
//
// Bootstrap:
//   M3B-1 still performs its validated A/B one-shot first. Only after its CPU readback
//   reaches kM2bPassed do we begin the continuous path. Because that asynchronous
//   validation can leave a temporal gap after frame B, the first continuous evaluation
//   is always reset=true and is used only to seed fresh feature-11 history.
//
// Runtime:
//   real N -> feature 11 -> g.m3b1a_tex12 -> free M3B-2A ring slot -> Vulkan consumer.
// If no transport slot is currently publishable, feature 11 still evaluates so its
// temporal history remains current; that generated result is simply not published.

struct M3b2bState
{
    bool announced;
    bool needReset;
    bool failed;
    uint64_t evalSuccess;
    uint64_t evalSafeFailures;
    uint64_t recordedForTransport;
    uint64_t published;
    uint64_t lastSkipLogFrame;
};

static M3b2bState g_m3b2b = {};

static bool M3b2bEnabled()
{
    return g_cfg.dlfg_m3b2b_native != 0;
}

static void M3b2bReleaseState()
{
    g_m3b2b = {};
}

enum M3b2bEvalResult
{
    kM3b2bEvalOk = 0,
    kM3b2bEvalFailedSafe = 1,
    kM3b2bEvalFaulted = 2
};

static M3b2bEvalResult M3b2bEvaluate(UINT64 frame, bool reset)
{
    NVSDK_NGX_D3D12_DLSSG_Eval_Params ep = {};
    ep.pBackbuffer = g.tex12[SLOT_OUTPUT];
    ep.pDepth = g.tex12[SLOT_DEPTH];
    ep.pMVecs = g.tex12[SLOT_MV];
    ep.pOutputInterpFrame = g.m3b1a_tex12;

    NVSDK_NGX_DLSSG_Opt_Eval_Params op = {};
    M2bBuildConstants(&op, reset);

    DWORD code = 0;
    const NVSDK_NGX_Result r = SafeEvaluateDLFG(&ep, &op, &code);
    if (code != 0)
    {
        Log("[feed] M3B-2B: native evaluate reset=%d raised exception 0x%08X on frame=%llu; command list unsafe",
            reset ? 1 : 0, code, static_cast<unsigned long long>(frame));
        g_m3b2b.failed = true;
        return kM3b2bEvalFaulted;
    }

    if (NVSDK_NGX_FAILED(r))
    {
        ++g_m3b2b.evalSafeFailures;
        Log("[feed] M3B-2B: native evaluate reset=%d failed 0x%08X (%s) on frame=%llu; native stream disabled",
            reset ? 1 : 0, r, NgxResultName(r), static_cast<unsigned long long>(frame));
        g_m3b2b.failed = true;
        return kM3b2bEvalFailedSafe;
    }

    ++g_m3b2b.evalSuccess;
    if (reset || g_m3b2b.evalSuccess <= 3 || (g_m3b2b.evalSuccess % 120) == 0)
    {
        Log("[feed] M3B-2B: native feature-11 evaluate success reset=%d frame=%llu evalSuccess=%llu",
            reset ? 1 : 0, static_cast<unsigned long long>(frame),
            static_cast<unsigned long long>(g_m3b2b.evalSuccess));
    }
    return kM3b2bEvalOk;
}

// Returns false only when an SEH-protected NGX call faulted and the current D3D12 list
// must be discarded. Ordinary NGX failures are contained by disabling M3B-2B while
// letting the normal real-frame path continue.
static bool M3b2bRecordNative(UINT64 frame, bool dlssReset, int *slotOut)
{
    if (slotOut != nullptr) *slotOut = -1;
    if (!M3b2bEnabled() || g_m3b2b.failed) return true;

    // M3B-1 performs creation + a validated A/B pair. Do not stream until that exact
    // feature and output resource have already proven themselves on this process.
    if (g.dlfg_state != kM2bPassed) return true;

    if (g_chicken_present)
    {
        Log("[feed] M3B-2B: DFC is present; native feature-11 stream disabled");
        g_m3b2b.failed = true;
        return true;
    }
    if (g.dlfg_feature == nullptr || g.dlfg_params == nullptr || g.m3b1a_tex12 == nullptr ||
        g.tex12[SLOT_OUTPUT] == nullptr || g.tex12[SLOT_DEPTH] == nullptr ||
        g.tex12[SLOT_MV] == nullptr)
    {
        Log("[feed] M3B-2B: validated feature/output resources disappeared; native stream disabled");
        g_m3b2b.failed = true;
        return true;
    }

    if (!g_m3b2b.announced)
    {
        g_m3b2b.announced = true;
        // CPU validation of the bootstrap A/B pair completes on a later real frame.
        // Force a fresh history seed before the first continuous interpolation so we
        // never bridge that temporal gap with stale feature history.
        g_m3b2b.needReset = true;
        Log("[feed] M3B-2B: M3B-1 bootstrap validated; seeding fresh continuous feature-11 history");
    }

    constexpr double kM3b2bMinMovingMvMeanPx = 0.05;
    if (!g_m2b_depth_valid || g_mv_probe_mean_px <= kM3b2bMinMovingMvMeanPx)
    {
        g_m3b2b.needReset = true;
        if (g_m3b2b.lastSkipLogFrame == 0 || frame - g_m3b2b.lastSkipLogFrame >= 300)
        {
            g_m3b2b.lastSkipLogFrame = frame;
            Log("[feed] M3B-2B: pausing native publication until moving gameplay returns (depthValid=%d meanMV=%.6f px)",
                g_m2b_depth_valid ? 1 : 0, g_mv_probe_mean_px);
        }
        return true;
    }

    const bool reset = dlssReset || g_m3b2b.needReset;

    // Pick a transport slot only for a publishable non-reset interpolation. Even when
    // no slot is available, still evaluate below to keep feature-11 history sequential.
    int slotIndex = -1;
    if (!reset && !M3b2aPublicationPending())
        slotIndex = M3b2aFindFreeSlot(frame);

    if (slotIndex >= 0)
    {
        auto &slot = g_m3b2a.slots[slotIndex];
        if (slot.consumerDoneValue != 0)
        {
            // M3b2aFindFreeSlot already observed CPU completion. Keep the explicit GPU
            // dependency so Vulkan's completed read can never overlap this D3D12 write.
            const HRESULT waitHr = g.queue->Wait(g_m3b2a.consumerDoneFence12, slot.consumerDoneValue);
            if (FAILED(waitHr))
            {
                Log("[feed] M3B-2B: queue Wait(consumerDone=%llu) failed 0x%08X; frame will advance history without publication",
                    static_cast<unsigned long long>(slot.consumerDoneValue), waitHr);
                slotIndex = -1;
            }
        }
    }

    Barrier(g.tex12[SLOT_OUTPUT], D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
            D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    Barrier(g.m3b1a_tex12, D3D12_RESOURCE_STATE_COMMON,
            D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

    const M3b2bEvalResult er = M3b2bEvaluate(frame, reset);
    if (er == kM3b2bEvalFaulted)
        return false; // caller must AbortCommands(); state restoration on this list is irrelevant.

    if (er == kM3b2bEvalFailedSafe)
    {
        Barrier(g.m3b1a_tex12, D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                D3D12_RESOURCE_STATE_COMMON);
        Barrier(g.tex12[SLOT_OUTPUT], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,
                D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        return true;
    }

    if (reset)
    {
        // A reset evaluation seeds history only; presenting its output would not be a
        // valid between-frame interpolation.
        Barrier(g.m3b1a_tex12, D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                D3D12_RESOURCE_STATE_COMMON);
        Barrier(g.tex12[SLOT_OUTPUT], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,
                D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        g_m3b2b.needReset = false;
        Log("[feed] M3B-2B: temporal history reset/seeded on real frame=%llu; publication resumes next valid frame",
            static_cast<unsigned long long>(frame));
        return true;
    }

    if (slotIndex >= 0)
    {
        auto &slot = g_m3b2a.slots[slotIndex];
        Barrier(g.m3b1a_tex12, D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                D3D12_RESOURCE_STATE_COPY_SOURCE);
        Barrier(slot.tex12, D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST);
        g.list->CopyResource(slot.tex12, g.m3b1a_tex12);
        Barrier(slot.tex12, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COMMON);
        Barrier(g.m3b1a_tex12, D3D12_RESOURCE_STATE_COPY_SOURCE,
                D3D12_RESOURCE_STATE_COMMON);

        slot.sourceFrame = frame;
        ++g_m3b2b.recordedForTransport;
        if (slotOut != nullptr) *slotOut = slotIndex;

        if (g_m3b2b.recordedForTransport <= 3 || (g_m3b2b.recordedForTransport % 60) == 0)
        {
            Log("[feed] M3B-2B: native generated frame copied to reusable slot=%d sourceFrame=%llu recorded=%llu",
                slotIndex, static_cast<unsigned long long>(frame),
                static_cast<unsigned long long>(g_m3b2b.recordedForTransport));
        }
    }
    else
    {
        // No transport slot this real frame. The eval still advanced temporal history.
        Barrier(g.m3b1a_tex12, D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
                D3D12_RESOURCE_STATE_COMMON);
    }

    Barrier(g.tex12[SLOT_OUTPUT], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,
            D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    return true;
}

static void M3b2bOnPublished(uint64_t serial, UINT64 sourceFrame, uint32_t slotIndex)
{
    if (!M3b2bEnabled() || serial == 0) return;
    ++g_m3b2b.published;

    if (g_m3b2b.published <= 3 || (g_m3b2b.published % 60) == 0)
    {
        Log("[feed] M3B-2B: published native serial=%llu slot=%u sourceFrame=%llu total=%llu",
            static_cast<unsigned long long>(serial), slotIndex,
            static_cast<unsigned long long>(sourceFrame),
            static_cast<unsigned long long>(g_m3b2b.published));
    }

    if (g_m3b2b.published == 300)
    {
        Log("[feed] MILESTONE M3B-2B PRODUCER PASSED: 300 native NVIDIA feature-11 generated frames published through the reusable M3B-2A transport");
    }
}
