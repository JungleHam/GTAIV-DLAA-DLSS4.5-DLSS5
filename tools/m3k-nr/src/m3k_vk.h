// SPDX-License-Identifier: MIT
// GTA IV adapter to the pinned Feeder 0.15.1 Vulkan path. Copyright 2026 JungleHam.
// M3kRecordVkInputs below is moved verbatim (apart from indentation) from Feeder
// 3f624855276c4bde55145c712782477639b30e85, Copyright 2026 Jean-Laurent ROUZIES
// and NIGos. The build patch defines it before including this header.
#pragma once

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
        static bool first = true;
        if (first || mode != g_m3kMode) {
            Log("M3K: mode=%d (%s); config=%ls", mode,
                mode == 0 ? "NR disabled / existing DLAA" : mode == 1 ? "A0 create only / existing DLAA" : "A1 NR enabled before DLAA", path);
            g_m3k.ResetHistory();
            if (mode == 0) g_m3k.ShutdownRuntime(g_ngx_dying);
            g_m3kMode = mode; first = false;
        }
    }
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
