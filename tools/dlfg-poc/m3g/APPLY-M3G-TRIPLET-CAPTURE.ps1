$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$feedCpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
if (!(Test-Path $feedCpp)) { throw "Missing $feedCpp. Run BUILD-M3F.bat first." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}
function Replace-Exact([ref]$textRef, [string]$old, [string]$new, [string]$already, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if ($already -and $textRef.Value.Contains($already)) { return }
    if (!$textRef.Value.Contains($old)) { throw "M3G anchor not found: $name" }
    $textRef.Value = $textRef.Value.Replace($old, $new)
}

$text = Read-Normalized $feedCpp
$ref = [ref]$text

# BMP writer used only after the GPU fence for a requested capture has retired.
if (!$ref.Value.Contains('// M3G manual triplet BMP writer')) {
    $anchor = 'static bool M2bWriteBmp('
    $pos = $ref.Value.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3G anchor not found: M2bWriteBmp' }

    $helper = @'
// M3G manual triplet BMP writer. This is diagnostic-only CPU file output after the
// existing D3D12 fence retires; it never changes the live render/present path.
static bool M3gWriteBmpNamed(const uint8_t *p, UINT row_pitch, const char *name, char path[MAX_PATH])
{
    if (p == nullptr || name == nullptr || name[0] == '\0') return false;
    GetModuleFileNameA(g_self, path, MAX_PATH);
    char *slash = strrchr(path, '\\');
    if (slash == nullptr) return false;
    strcpy_s(slash + 1, MAX_PATH - static_cast<size_t>(slash + 1 - path), name);

    FILE *f = nullptr;
    if (fopen_s(&f, path, "wb") != 0 || f == nullptr) return false;

    BITMAPFILEHEADER fileHeader = {};
    BITMAPINFOHEADER infoHeader = {};
    const DWORD imageBytes = static_cast<DWORD>(g.width * g.height * 4u);
    fileHeader.bfType = 0x4D42;
    fileHeader.bfOffBits = sizeof(fileHeader) + sizeof(infoHeader);
    fileHeader.bfSize = fileHeader.bfOffBits + imageBytes;
    infoHeader.biSize = sizeof(infoHeader);
    infoHeader.biWidth = static_cast<LONG>(g.width);
    infoHeader.biHeight = static_cast<LONG>(g.height);
    infoHeader.biPlanes = 1;
    infoHeader.biBitCount = 32;
    infoHeader.biCompression = BI_RGB;
    infoHeader.biSizeImage = imageBytes;

    bool ok = fwrite(&fileHeader, 1, sizeof(fileHeader), f) == sizeof(fileHeader) &&
              fwrite(&infoHeader, 1, sizeof(infoHeader), f) == sizeof(infoHeader);
    for (UINT y = g.height; ok && y-- > 0; )
        ok = fwrite(p + static_cast<size_t>(y) * row_pitch, 1, g.width * 4u, f) == g.width * 4u;
    fclose(f);
    return ok;
}

'@
    $ref.Value = $ref.Value.Insert($pos, $helper)
}

# Runtime capture state is inserted immediately before the continuous native producer.
# PgUp requests capture slot 1 and PgDn requests slot 2. A request records real A on
# one genuine source frame, then real B + feature-11 G on the next sequential valid frame.
if (!$ref.Value.Contains('// M3G manual runtime triplet capture')) {
    $anchor = 'static bool M3b2bRecordNative(UINT64 frame, bool dlssReset, int *slotOut)'
    $pos = $ref.Value.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3G anchor not found: M3b2bRecordNative' }

    $runtime = @'
// M3G manual runtime triplet capture. PgUp = capture set 1, PgDn = capture set 2.
// The capture is taken from the continuous native feature-11 stream rather than the
// startup bootstrap, so the user can choose a controlled camera pan in live gameplay.
struct M3gManualCaptureState
{
    ID3D12Resource *aReadback;
    ID3D12Resource *gReadback;
    ID3D12Resource *bReadback;
    int requestedSlot;
    int activeSlot;
    int activeMvMode;
    UINT64 aFrame;
    UINT64 bFrame;
    UINT64 fenceValue;
    bool haveA;
    bool pendingWrite;
    bool pgUpWasDown;
    bool pgDnWasDown;
};

static M3gManualCaptureState g_m3g_manual = {};

static bool M3gEnsureManualReadbacks()
{
    if (g_m3g_manual.aReadback != nullptr &&
        g_m3g_manual.gReadback != nullptr &&
        g_m3g_manual.bReadback != nullptr)
        return true;

    SafeRelease(g_m3g_manual.aReadback);
    SafeRelease(g_m3g_manual.gReadback);
    SafeRelease(g_m3g_manual.bReadback);
    if (g.dlfg_readback_bytes == 0 || g.dlfg_footprint.Footprint.RowPitch < g.width * 4u)
        return false;

    if (!M2bCreateReadback(&g_m3g_manual.aReadback) ||
        !M2bCreateReadback(&g_m3g_manual.gReadback) ||
        !M2bCreateReadback(&g_m3g_manual.bReadback))
    {
        SafeRelease(g_m3g_manual.aReadback);
        SafeRelease(g_m3g_manual.gReadback);
        SafeRelease(g_m3g_manual.bReadback);
        return false;
    }
    return true;
}

static void M3gRequestManualCapture(int slot)
{
    if (slot != 1 && slot != 2) return;
    if (g_m3g_manual.pendingWrite || g_m3g_manual.haveA)
    {
        Log("[feed] M3G: capture key %d ignored because another A/G/B capture is already in flight", slot);
        return;
    }
    g_m3g_manual.requestedSlot = slot;
    Log("[feed] M3G: manual capture %d ARMED (MV mode=%d); waiting for next clean native pair",
        slot, g_cfg.dlfg_m3f_mv_mode);
}

static void M3gPollManualKeys()
{
    const bool pgUpDown = (GetAsyncKeyState(VK_PRIOR) & 0x8000) != 0; // Page Up
    const bool pgDnDown = (GetAsyncKeyState(VK_NEXT)  & 0x8000) != 0; // Page Down
    if (pgUpDown && !g_m3g_manual.pgUpWasDown) M3gRequestManualCapture(1);
    if (pgDnDown && !g_m3g_manual.pgDnWasDown) M3gRequestManualCapture(2);
    g_m3g_manual.pgUpWasDown = pgUpDown;
    g_m3g_manual.pgDnWasDown = pgDnDown;
}

static void M3gPollManualWriteback()
{
    if (!g_m3g_manual.pendingWrite || g.fence12 == nullptr ||
        g.fence12->GetCompletedValue() < g_m3g_manual.fenceValue)
        return;

    void *a = nullptr, *gen = nullptr, *b = nullptr;
    const D3D12_RANGE read = { 0, g.dlfg_readback_bytes };
    const HRESULT ha = g_m3g_manual.aReadback->Map(0, &read, &a);
    const HRESULT hg = g_m3g_manual.gReadback->Map(0, &read, &gen);
    const HRESULT hb = g_m3g_manual.bReadback->Map(0, &read, &b);
    if (FAILED(ha) || FAILED(hg) || FAILED(hb) || a == nullptr || gen == nullptr || b == nullptr)
    {
        if (a)   g_m3g_manual.aReadback->Unmap(0, nullptr);
        if (gen) g_m3g_manual.gReadback->Unmap(0, nullptr);
        if (b)   g_m3g_manual.bReadback->Unmap(0, nullptr);
        Log("[feed] M3G: manual capture %d readback map FAILED A=0x%08X G=0x%08X B=0x%08X",
            g_m3g_manual.activeSlot, ha, hg, hb);
        g_m3g_manual.pendingWrite = false;
        g_m3g_manual.activeSlot = 0;
        return;
    }

    char nameA[96] = {}, nameG[96] = {}, nameB[96] = {};
    sprintf_s(nameA, sizeof(nameA), "dlfg-m3g-%d-mode%d-A-prev-real.bmp",
              g_m3g_manual.activeSlot, g_m3g_manual.activeMvMode);
    sprintf_s(nameG, sizeof(nameG), "dlfg-m3g-%d-mode%d-G-generated.bmp",
              g_m3g_manual.activeSlot, g_m3g_manual.activeMvMode);
    sprintf_s(nameB, sizeof(nameB), "dlfg-m3g-%d-mode%d-B-next-real.bmp",
              g_m3g_manual.activeSlot, g_m3g_manual.activeMvMode);

    char pathA[MAX_PATH] = {}, pathG[MAX_PATH] = {}, pathB[MAX_PATH] = {};
    const UINT pitch = g.dlfg_footprint.Footprint.RowPitch;
    const bool aOk = M3gWriteBmpNamed(static_cast<const uint8_t *>(a), pitch, nameA, pathA);
    const bool gOk = M3gWriteBmpNamed(static_cast<const uint8_t *>(gen), pitch, nameG, pathG);
    const bool bOk = M3gWriteBmpNamed(static_cast<const uint8_t *>(b), pitch, nameB, pathB);

    const D3D12_RANGE none = { 0, 0 };
    g_m3g_manual.aReadback->Unmap(0, &none);
    g_m3g_manual.gReadback->Unmap(0, &none);
    g_m3g_manual.bReadback->Unmap(0, &none);

    Log("[feed] M3G: manual capture %d SAVED mode=%d AFrame=%llu BFrame=%llu A=%d G=%d B=%d paths='%s' '%s' '%s'",
        g_m3g_manual.activeSlot, g_m3g_manual.activeMvMode,
        static_cast<unsigned long long>(g_m3g_manual.aFrame),
        static_cast<unsigned long long>(g_m3g_manual.bFrame),
        aOk ? 1 : 0, gOk ? 1 : 0, bOk ? 1 : 0, pathA, pathG, pathB);

    g_m3g_manual.pendingWrite = false;
    g_m3g_manual.activeSlot = 0;
    g_m3g_manual.aFrame = 0;
    g_m3g_manual.bFrame = 0;
}

static void M3gManualRuntimePoll()
{
    M3gPollManualKeys();
    M3gPollManualWriteback();
}

// Called after the current frame's reset decision but before feature-11 evaluation.
// Returns true only on the B frame of a clean sequential A->B pair, asking the caller
// to copy the generated interpolation after the evaluation succeeds.
static bool M3gPrepareManualPair(UINT64 frame, bool reset)
{
    if (g_m3g_manual.pendingWrite) return false;

    if (!g_m3g_manual.haveA)
    {
        if (g_m3g_manual.requestedSlot == 0) return false;
        if (!M3gEnsureManualReadbacks())
        {
            Log("[feed] M3G: could not allocate manual A/G/B readbacks; request remains armed");
            return false;
        }

        g_m3g_manual.activeSlot = g_m3g_manual.requestedSlot;
        g_m3g_manual.requestedSlot = 0;
        g_m3g_manual.activeMvMode = g_cfg.dlfg_m3f_mv_mode;
        M2bCopyTextureToReadback(g.tex12[SLOT_OUTPUT], g_m3g_manual.aReadback,
                                 D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        g_m3g_manual.aFrame = frame;
        g_m3g_manual.haveA = true;
        Log("[feed] M3G: capture %d copied real A frame=%llu mode=%d%s",
            g_m3g_manual.activeSlot, static_cast<unsigned long long>(frame),
            g_m3g_manual.activeMvMode, reset ? " (this frame also seeds/reset history)" : "");
        return false;
    }

    // We only accept the immediately following genuine source frame under the same MV
    // contract. A reset/discontinuity becomes the new A so G is never a stale-history frame.
    if (frame != g_m3g_manual.aFrame + 1 || reset ||
        g_cfg.dlfg_m3f_mv_mode != g_m3g_manual.activeMvMode)
    {
        g_m3g_manual.activeMvMode = g_cfg.dlfg_m3f_mv_mode;
        M2bCopyTextureToReadback(g.tex12[SLOT_OUTPUT], g_m3g_manual.aReadback,
                                 D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        g_m3g_manual.aFrame = frame;
        Log("[feed] M3G: capture %d restarted real A at frame=%llu mode=%d (reset/discontinuity/mode change)",
            g_m3g_manual.activeSlot, static_cast<unsigned long long>(frame),
            g_m3g_manual.activeMvMode);
        return false;
    }

    M2bCopyTextureToReadback(g.tex12[SLOT_OUTPUT], g_m3g_manual.bReadback,
                             D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    g_m3g_manual.bFrame = frame;
    return true;
}

static void M3gFinishManualPair(UINT64 frame)
{
    if (!g_m3g_manual.haveA || g_m3g_manual.bFrame != frame || g.m3b1a_tex12 == nullptr)
        return;

    // M3b2bEvaluate leaves feature-11 output in UAV state. The existing helper copies
    // it to our readback and restores that state before normal transport continues.
    M2bCopyTextureToReadback(g.m3b1a_tex12, g_m3g_manual.gReadback,
                             D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    g_m3g_manual.fenceValue = g.fence_value + 1; // EndCommands signal for this D3D12 list
    g_m3g_manual.pendingWrite = true;
    g_m3g_manual.haveA = false;
    Log("[feed] M3G: capture %d queued A/G/B on real frames %llu -> %llu mode=%d fence=%llu",
        g_m3g_manual.activeSlot,
        static_cast<unsigned long long>(g_m3g_manual.aFrame),
        static_cast<unsigned long long>(g_m3g_manual.bFrame),
        g_m3g_manual.activeMvMode,
        static_cast<unsigned long long>(g_m3g_manual.fenceValue));
}

static void M3gAbortManualPair(UINT64 frame)
{
    if (g_m3g_manual.bFrame != frame) return;
    Log("[feed] M3G: capture %d abandoned because feature-11 evaluation failed on B frame=%llu",
        g_m3g_manual.activeSlot, static_cast<unsigned long long>(frame));
    g_m3g_manual.haveA = false;
    g_m3g_manual.bFrame = 0;
    g_m3g_manual.requestedSlot = g_m3g_manual.activeSlot; // retry if native stream survives
    g_m3g_manual.activeSlot = 0;
}

'@
    $ref.Value = $ref.Value.Insert($pos, $runtime)
}

Replace-Exact $ref @'
static bool M3b2bRecordNative(UINT64 frame, bool dlssReset, int *slotOut)
{
    if (slotOut != nullptr) *slotOut = -1;
    if (!M3b2bEnabled() || g_m3b2b.failed) return true;
'@ @'
static bool M3b2bRecordNative(UINT64 frame, bool dlssReset, int *slotOut)
{
    if (slotOut != nullptr) *slotOut = -1;
    M3gManualRuntimePoll();
    if (!M3b2bEnabled() || g_m3b2b.failed) return true;
'@ 'M3gManualRuntimePoll();' 'runtime key/writeback poll'

Replace-Exact $ref @'
    const bool reset = dlssReset || g_m3b2b.needReset;

    // Pick a transport slot only for a publishable non-reset interpolation. Even when
'@ @'
    const bool reset = dlssReset || g_m3b2b.needReset;
    const bool m3gCaptureThisEval = M3gPrepareManualPair(frame, reset);

    // Pick a transport slot only for a publishable non-reset interpolation. Even when
'@ 'const bool m3gCaptureThisEval = M3gPrepareManualPair' 'pair preparation'

Replace-Exact $ref @'
    const M3b2bEvalResult er = M3b2bEvaluate(frame, reset);
    if (er == kM3b2bEvalFaulted)
        return false; // caller must AbortCommands(); state restoration on this list is irrelevant.

    if (er == kM3b2bEvalFailedSafe)
'@ @'
    const M3b2bEvalResult er = M3b2bEvaluate(frame, reset);
    if (er == kM3b2bEvalOk && m3gCaptureThisEval)
        M3gFinishManualPair(frame);
    else if (er != kM3b2bEvalOk && m3gCaptureThisEval)
        M3gAbortManualPair(frame);

    if (er == kM3b2bEvalFaulted)
        return false; // caller must AbortCommands(); state restoration on this list is irrelevant.

    if (er == kM3b2bEvalFailedSafe)
'@ 'M3gFinishManualPair(frame);' 'generated-frame capture hook'

Write-Normalized $feedCpp $ref.Value

Write-Host 'Applied M3G MANUAL objective A/G/B triplet capture.'
Write-Host '  Page Up   = capture set 1'
Write-Host '  Page Down = capture set 2'
Write-Host '  Capture waits for a clean sequential native pair and records:'
Write-Host '    A = real frame, G = NVIDIA generated midpoint, B = next real frame'
Write-Host '  Filenames include capture slot and active M3F MV mode.'
Write-Host '  M3F MV modes, M3E pacing, M3D gating and M3B2B transport are otherwise unchanged.'
