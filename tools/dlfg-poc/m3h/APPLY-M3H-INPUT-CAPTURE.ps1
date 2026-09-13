$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$inc = Join-Path $m2b 'feeder-src\src\m3b2b-feed.inc'
if (!(Test-Path $inc)) { throw "Missing $inc. Run BUILD-M3G.bat first." }

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
    if (!$textRef.Value.Contains($old)) { throw "M3H anchor not found: $name" }
    $textRef.Value = $textRef.Value.Replace($old, $new)
}

$text = Read-Normalized $inc
$ref = [ref]$text

# M3H standardizes the manual trigger keys for this branch regardless of whether the
# local M3G patch still says Page Up/Page Down.
$ref.Value = $ref.Value.Replace('GetAsyncKeyState(VK_PRIOR)', 'GetAsyncKeyState(VK_OEM_3)')
$ref.Value = $ref.Value.Replace('GetAsyncKeyState(VK_NEXT)', 'GetAsyncKeyState(VK_OEM_PLUS)')
$ref.Value = $ref.Value.Replace('// Page Up', '// ` / ~')
$ref.Value = $ref.Value.Replace('// Page Down', '// = / +')
$ref.Value = $ref.Value.Replace('PgUp = capture set 1, PgDn = capture set 2.', '` = capture set 1, = = capture set 2.')

# Add diagnostic-only readback helpers immediately before the existing M3G readback allocator.
if (!$ref.Value.Contains('// M3H exact DLSS-G input capture')) {
    $anchor = 'static bool M3gEnsureManualReadbacks()'
    $pos = $ref.Value.IndexOf($anchor)
    if ($pos -lt 0) { throw 'M3H anchor not found: M3gEnsureManualReadbacks' }

    $helper = @'
// M3H exact DLSS-G input capture.
// For the same B frame used by the manual M3G A/G/B capture, copy the exact motion-vector
// and depth textures that are handed to NVIDIA feature 11. These are diagnostic readbacks
// only; normal feature inputs, transport, pacing and presentation are unchanged.
struct M3hInputCaptureState
{
    ID3D12Resource *mvReadback;
    ID3D12Resource *depthReadback;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT mvFootprint;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT depthFootprint;
    UINT mvRows;
    UINT depthRows;
    UINT64 mvRowBytes;
    UINT64 depthRowBytes;
    UINT64 mvBytes;
    UINT64 depthBytes;
    DXGI_FORMAT mvFormat;
    DXGI_FORMAT depthFormat;
    UINT width;
    UINT height;
    bool queued;
};

static M3hInputCaptureState g_m3h_inputs = {};

static bool M3hCreateReadbackForTexture(ID3D12Resource *src,
                                        ID3D12Resource **dst,
                                        D3D12_PLACED_SUBRESOURCE_FOOTPRINT *footprint,
                                        UINT *rows,
                                        UINT64 *rowBytes,
                                        UINT64 *totalBytes,
                                        DXGI_FORMAT *format,
                                        UINT *width,
                                        UINT *height)
{
    if (src == nullptr || dst == nullptr || footprint == nullptr || rows == nullptr ||
        rowBytes == nullptr || totalBytes == nullptr || format == nullptr ||
        width == nullptr || height == nullptr || g.dev12 == nullptr)
        return false;

    const D3D12_RESOURCE_DESC td = src->GetDesc();
    *format = td.Format;
    *width = static_cast<UINT>(td.Width);
    *height = td.Height;

    g.dev12->GetCopyableFootprints(&td, 0, 1, 0, footprint, rows, rowBytes, totalBytes);
    if (*totalBytes == 0 || footprint->Footprint.RowPitch == 0 || *rowBytes == 0)
        return false;

    D3D12_HEAP_PROPERTIES hp = {};
    hp.Type = D3D12_HEAP_TYPE_READBACK;
    hp.CreationNodeMask = 1;
    hp.VisibleNodeMask = 1;

    D3D12_RESOURCE_DESC bd = {};
    bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    bd.Width = *totalBytes;
    bd.Height = 1;
    bd.DepthOrArraySize = 1;
    bd.MipLevels = 1;
    bd.Format = DXGI_FORMAT_UNKNOWN;
    bd.SampleDesc.Count = 1;
    bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

    const HRESULT hr = g.dev12->CreateCommittedResource(
        &hp, D3D12_HEAP_FLAG_NONE, &bd, D3D12_RESOURCE_STATE_COPY_DEST,
        nullptr, __uuidof(ID3D12Resource), reinterpret_cast<void **>(dst));
    if (FAILED(hr))
    {
        Log("[feed] M3H: readback allocation failed hr=0x%08X bytes=%llu",
            hr, static_cast<unsigned long long>(*totalBytes));
        return false;
    }
    return true;
}

static bool M3hEnsureInputReadbacks()
{
    if (g_m3h_inputs.mvReadback != nullptr && g_m3h_inputs.depthReadback != nullptr)
        return true;

    SafeRelease(g_m3h_inputs.mvReadback);
    SafeRelease(g_m3h_inputs.depthReadback);
    g_m3h_inputs = {};

    UINT mvW = 0, mvH = 0, depthW = 0, depthH = 0;
    if (!M3hCreateReadbackForTexture(
            g.tex12[SLOT_MV], &g_m3h_inputs.mvReadback,
            &g_m3h_inputs.mvFootprint, &g_m3h_inputs.mvRows,
            &g_m3h_inputs.mvRowBytes, &g_m3h_inputs.mvBytes,
            &g_m3h_inputs.mvFormat, &mvW, &mvH) ||
        !M3hCreateReadbackForTexture(
            g.tex12[SLOT_DEPTH], &g_m3h_inputs.depthReadback,
            &g_m3h_inputs.depthFootprint, &g_m3h_inputs.depthRows,
            &g_m3h_inputs.depthRowBytes, &g_m3h_inputs.depthBytes,
            &g_m3h_inputs.depthFormat, &depthW, &depthH))
    {
        SafeRelease(g_m3h_inputs.mvReadback);
        SafeRelease(g_m3h_inputs.depthReadback);
        g_m3h_inputs = {};
        return false;
    }

    if (mvW != depthW || mvH != depthH)
    {
        Log("[feed] M3H: MV/depth dimensions differ MV=%ux%u depth=%ux%u",
            mvW, mvH, depthW, depthH);
        SafeRelease(g_m3h_inputs.mvReadback);
        SafeRelease(g_m3h_inputs.depthReadback);
        g_m3h_inputs = {};
        return false;
    }

    g_m3h_inputs.width = mvW;
    g_m3h_inputs.height = mvH;
    Log("[feed] M3H: input readbacks ready %ux%u MVfmt=%u MVrow=%llu MVpitch=%u DEPTHfmt=%u DEPTHrow=%llu DEPTHpitch=%u",
        g_m3h_inputs.width, g_m3h_inputs.height,
        static_cast<unsigned>(g_m3h_inputs.mvFormat),
        static_cast<unsigned long long>(g_m3h_inputs.mvRowBytes),
        g_m3h_inputs.mvFootprint.Footprint.RowPitch,
        static_cast<unsigned>(g_m3h_inputs.depthFormat),
        static_cast<unsigned long long>(g_m3h_inputs.depthRowBytes),
        g_m3h_inputs.depthFootprint.Footprint.RowPitch);
    return true;
}

static void M3hCopyTextureToReadback(ID3D12Resource *src,
                                     ID3D12Resource *dst,
                                     const D3D12_PLACED_SUBRESOURCE_FOOTPRINT &footprint,
                                     D3D12_RESOURCE_STATES sourceState)
{
    Barrier(src, sourceState, D3D12_RESOURCE_STATE_COPY_SOURCE);
    D3D12_TEXTURE_COPY_LOCATION from = {};
    from.pResource = src;
    from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;

    D3D12_TEXTURE_COPY_LOCATION to = {};
    to.pResource = dst;
    to.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    to.PlacedFootprint = footprint;

    g.list->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
    Barrier(src, D3D12_RESOURCE_STATE_COPY_SOURCE, sourceState);
}

static bool M3hQueueCurrentInputs()
{
    g_m3h_inputs.queued = false;
    if (!M3hEnsureInputReadbacks())
        return false;

    // M3B-2B hands both resources to feature 11 as non-pixel-shader SRVs and does not
    // otherwise transition them inside M3b2bRecordNative. Copy them only after a successful
    // evaluation, restoring the exact state before normal transport continues.
    M3hCopyTextureToReadback(g.tex12[SLOT_MV], g_m3h_inputs.mvReadback,
                             g_m3h_inputs.mvFootprint,
                             D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    M3hCopyTextureToReadback(g.tex12[SLOT_DEPTH], g_m3h_inputs.depthReadback,
                             g_m3h_inputs.depthFootprint,
                             D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    g_m3h_inputs.queued = true;
    return true;
}

static bool M3hBuildPath(const char *name, char path[MAX_PATH])
{
    if (name == nullptr || name[0] == '\0') return false;
    GetModuleFileNameA(g_self, path, MAX_PATH);
    char *slash = strrchr(path, '\\');
    if (slash == nullptr) return false;
    strcpy_s(slash + 1, MAX_PATH - static_cast<size_t>(slash + 1 - path), name);
    return true;
}

static bool M3hWritePackedRaw(ID3D12Resource *readback,
                              UINT64 totalBytes,
                              UINT rows,
                              UINT64 logicalRowBytes,
                              UINT gpuRowPitch,
                              const char *name,
                              char path[MAX_PATH])
{
    if (readback == nullptr || totalBytes == 0 || rows == 0 || logicalRowBytes == 0 ||
        !M3hBuildPath(name, path))
        return false;

    void *mapped = nullptr;
    const D3D12_RANGE read = { 0, static_cast<SIZE_T>(totalBytes) };
    const HRESULT hr = readback->Map(0, &read, &mapped);
    if (FAILED(hr) || mapped == nullptr)
        return false;

    FILE *f = nullptr;
    bool ok = fopen_s(&f, path, "wb") == 0 && f != nullptr;
    const uint8_t *p = static_cast<const uint8_t *>(mapped);
    for (UINT y = 0; ok && y < rows; ++y)
    {
        ok = fwrite(p + static_cast<size_t>(y) * gpuRowPitch,
                    1, static_cast<size_t>(logicalRowBytes), f) ==
             static_cast<size_t>(logicalRowBytes);
    }
    if (f != nullptr) fclose(f);
    const D3D12_RANGE none = { 0, 0 };
    readback->Unmap(0, &none);
    return ok;
}

static void M3hModeScale(int mode, double *sx, double *sy)
{
    double x = 1.0, y = 1.0;
    switch (mode)
    {
        case 1: x = -1.0; break;
        case 2: y = -1.0; break;
        case 3: x = -1.0; y = -1.0; break;
        case 4: x = 0.5; y = 0.5; break;
        case 5: x = 0.75; y = 0.75; break;
        case 6: x = 1.25; y = 1.25; break;
        case 7: x = 1.5; y = 1.5; break;
        default: break;
    }
    if (sx) *sx = x;
    if (sy) *sy = y;
}

static bool M3hWriteInputFiles(int slot, int mode, UINT64 aFrame, UINT64 bFrame)
{
    if (!g_m3h_inputs.queued)
        return false;

    char mvName[128] = {}, depthName[128] = {}, metaName[128] = {};
    sprintf_s(mvName, sizeof(mvName), "dlfg-m3h-%d-mode%d-MV-R16G16_FLOAT.bin", slot, mode);
    sprintf_s(depthName, sizeof(depthName), "dlfg-m3h-%d-mode%d-DEPTH-R32_FLOAT.bin", slot, mode);
    sprintf_s(metaName, sizeof(metaName), "dlfg-m3h-%d-mode%d-inputs.txt", slot, mode);

    char mvPath[MAX_PATH] = {}, depthPath[MAX_PATH] = {}, metaPath[MAX_PATH] = {};
    const bool mvOk = M3hWritePackedRaw(
        g_m3h_inputs.mvReadback, g_m3h_inputs.mvBytes, g_m3h_inputs.mvRows,
        g_m3h_inputs.mvRowBytes, g_m3h_inputs.mvFootprint.Footprint.RowPitch,
        mvName, mvPath);
    const bool depthOk = M3hWritePackedRaw(
        g_m3h_inputs.depthReadback, g_m3h_inputs.depthBytes, g_m3h_inputs.depthRows,
        g_m3h_inputs.depthRowBytes, g_m3h_inputs.depthFootprint.Footprint.RowPitch,
        depthName, depthPath);

    bool metaOk = M3hBuildPath(metaName, metaPath);
    FILE *meta = nullptr;
    if (metaOk)
        metaOk = fopen_s(&meta, metaPath, "wb") == 0 && meta != nullptr;

    double modeX = 1.0, modeY = 1.0;
    M3hModeScale(mode, &modeX, &modeY);
    if (metaOk)
    {
        fprintf(meta, "m3h_version=1\n");
        fprintf(meta, "capture_slot=%d\n", slot);
        fprintf(meta, "m3f_mv_mode=%d\n", mode);
        fprintf(meta, "a_frame=%llu\n", static_cast<unsigned long long>(aFrame));
        fprintf(meta, "b_frame=%llu\n", static_cast<unsigned long long>(bFrame));
        fprintf(meta, "captured_inputs_b_frame=%llu\n", static_cast<unsigned long long>(bFrame));
        fprintf(meta, "width=%u\nheight=%u\n", g_m3h_inputs.width, g_m3h_inputs.height);
        fprintf(meta, "mv_format_code=%u\n", static_cast<unsigned>(g_m3h_inputs.mvFormat));
        fprintf(meta, "mv_format=DXGI_FORMAT_R16G16_FLOAT\n");
        fprintf(meta, "mv_layout=interleaved_float16_x_y_little_endian\n");
        fprintf(meta, "mv_packed_row_bytes=%llu\n",
                static_cast<unsigned long long>(g_m3h_inputs.mvRowBytes));
        fprintf(meta, "mv_gpu_row_pitch=%u\n", g_m3h_inputs.mvFootprint.Footprint.RowPitch);
        fprintf(meta, "depth_format_code=%u\n", static_cast<unsigned>(g_m3h_inputs.depthFormat));
        fprintf(meta, "depth_format=DXGI_FORMAT_R32_FLOAT\n");
        fprintf(meta, "depth_layout=float32_little_endian\n");
        fprintf(meta, "depth_packed_row_bytes=%llu\n",
                static_cast<unsigned long long>(g_m3h_inputs.depthRowBytes));
        fprintf(meta, "depth_gpu_row_pitch=%u\n", g_m3h_inputs.depthFootprint.Footprint.RowPitch);
        fprintf(meta, "stored_orientation=texture_row_0_first\n");
        fprintf(meta, "dlssg_mode_multiplier_x=%.6f\n", modeX);
        fprintf(meta, "dlssg_mode_multiplier_y=%.6f\n", modeY);
        fprintf(meta, "dlssg_mvec_scale_x=%.12f\n", modeX / static_cast<double>(g_m3h_inputs.width));
        fprintf(meta, "dlssg_mvec_scale_y=%.12f\n", modeY / static_cast<double>(g_m3h_inputs.height));
        fprintf(meta, "depth_probe_valid=%d\n", g_m2b_depth_valid ? 1 : 0);
        fprintf(meta, "mv_probe_mean_px=%.9f\n", g_mv_probe_mean_px);
        fprintf(meta, "mv_file=%s\n", mvName);
        fprintf(meta, "depth_file=%s\n", depthName);
        fclose(meta);
    }

    Log("[feed] M3H: exact B-frame inputs SAVED slot=%d mode=%d frame=%llu MV=%d DEPTH=%d META=%d paths='%s' '%s' '%s'",
        slot, mode, static_cast<unsigned long long>(bFrame),
        mvOk ? 1 : 0, depthOk ? 1 : 0, metaOk ? 1 : 0,
        mvPath, depthPath, metaPath);
    g_m3h_inputs.queued = false;
    return mvOk && depthOk && metaOk;
}

'@
    $ref.Value = $ref.Value.Insert($pos, $helper)
}

# Queue exact MV/depth copies only after feature 11 succeeds for the same B frame whose
# generated output is already being copied by M3G.
Replace-Exact $ref @'
    M2bCopyTextureToReadback(g.m3b1a_tex12, g_m3g_manual.gReadback,
                             D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    g_m3g_manual.fenceValue = g.fence_value + 1; // EndCommands signal for this D3D12 list
'@ @'
    M2bCopyTextureToReadback(g.m3b1a_tex12, g_m3g_manual.gReadback,
                             D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    if (!M3hQueueCurrentInputs())
        Log("[feed] M3H: exact B-frame MV/depth capture could not be queued for frame=%llu",
            static_cast<unsigned long long>(frame));
    g_m3g_manual.fenceValue = g.fence_value + 1; // EndCommands signal for this D3D12 list
'@ 'M3hQueueCurrentInputs()' 'queue exact MV/depth inputs'

# After the same fence retires and A/G/B BMPs are written, write packed raw MV/depth +
# metadata before M3G clears the active slot/frame provenance.
Replace-Exact $ref @'
    g_m3g_manual.aReadback->Unmap(0, &none);
    g_m3g_manual.gReadback->Unmap(0, &none);
    g_m3g_manual.bReadback->Unmap(0, &none);

    Log("[feed] M3G: manual capture %d SAVED mode=%d AFrame=%llu BFrame=%llu A=%d G=%d B=%d paths='%s' '%s' '%s'",
'@ @'
    g_m3g_manual.aReadback->Unmap(0, &none);
    g_m3g_manual.gReadback->Unmap(0, &none);
    g_m3g_manual.bReadback->Unmap(0, &none);

    const bool m3hInputsOk = M3hWriteInputFiles(
        g_m3g_manual.activeSlot, g_m3g_manual.activeMvMode,
        g_m3g_manual.aFrame, g_m3g_manual.bFrame);
    if (!m3hInputsOk)
        Log("[feed] M3H: input-file write incomplete for capture=%d mode=%d",
            g_m3g_manual.activeSlot, g_m3g_manual.activeMvMode);

    Log("[feed] M3G: manual capture %d SAVED mode=%d AFrame=%llu BFrame=%llu A=%d G=%d B=%d paths='%s' '%s' '%s'",
'@ 'const bool m3hInputsOk = M3hWriteInputFiles' 'write exact MV/depth inputs'

Write-Normalized $inc $ref.Value

Write-Host 'Applied M3H exact DLSS-G input capture to generated M3B-2B include.'
Write-Host '  `  = capture set 1'
Write-Host '  =  = capture set 2'
Write-Host '  Each successful M3G triplet now also saves the SAME B-frame inputs:'
Write-Host '    MV    = packed R16G16_FLOAT x/y raw file'
Write-Host '    DEPTH = packed R32_FLOAT raw file'
Write-Host '    META  = dimensions, formats, frame IDs and active M3F scale'
Write-Host '  M3H does not change DLSS-G inputs, evaluation, transport, pacing, or present order.'
