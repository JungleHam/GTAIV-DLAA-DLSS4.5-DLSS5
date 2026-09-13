$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$m3a = Join-Path $root 'm3a-os'
$feedCpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
$presentH = Join-Path $m2b 'feeder-src\src\feed_vk_present64.h'
$optiInc = Join-Path $m3a 'OptiScaler\OptiScaler\hooks\m3b2a-optiscaler.inc'

foreach ($p in @($feedCpp, $presentH, $optiInc)) {
    if (!(Test-Path $p)) { throw "Missing $p. Run BUILD-M3C.bat first." }
}

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
    if (!$textRef.Value.Contains($old)) { throw "M3D anchor not found: $name" }
    $textRef.Value = $textRef.Value.Replace($old, $new)
}

# -----------------------------------------------------------------------------
# Feeder config + whole-FeedFrameVk gate.
# M3C showed that the Feeder was advancing about twice per actual QueuePresent. M3D
# suppresses OptiScaler's synthetic present and also admits only the first Feeder callback
# observed under each genuine game present serial.
# -----------------------------------------------------------------------------
$feed = Read-Normalized $feedCpp
$feedRef = [ref]$feed

Replace-Exact $feedRef `
'    int   dlfg_m3c_queue; // M3C: three-entry publication FIFO for one generated publication per real frame' `
'    int   dlfg_m3c_queue; // M3C: three-entry publication FIFO for one generated publication per real frame
    int   dlfg_m3d_injected_present_gate; // M3D: suppress synthetic presents + duplicate Feeder callbacks per real present' `
'dlfg_m3d_injected_present_gate' `
'Cfg field'

Replace-Exact $feedRef `
'                     /* dlfg_m3c_queue */ 0,
                     /* hdr_bridge */ -1' `
'                     /* dlfg_m3c_queue */ 0,
                     /* dlfg_m3d_injected_present_gate */ 0,
                     /* hdr_bridge */ -1' `
'/* dlfg_m3d_injected_present_gate */' `
'Cfg initializer'

Replace-Exact $feedRef `
'        else if (_stricmp(key, "dlfg_m3c_queue") == 0) next.dlfg_m3c_queue = iv;' `
'        else if (_stricmp(key, "dlfg_m3c_queue") == 0) next.dlfg_m3c_queue = iv;
        else if (_stricmp(key, "dlfg_m3d_injected_present_gate") == 0) next.dlfg_m3d_injected_present_gate = iv;' `
'_stricmp(key, "dlfg_m3d_injected_present_gate")' `
'Cfg parser'

Replace-Exact $feedRef `
'    next.dlfg_m3c_queue = next.dlfg_m3c_queue != 0 ? 1 : 0;' `
'    next.dlfg_m3c_queue = next.dlfg_m3c_queue != 0 ? 1 : 0;
    next.dlfg_m3d_injected_present_gate = next.dlfg_m3d_injected_present_gate != 0 ? 1 : 0;' `
'next.dlfg_m3d_injected_present_gate = next.dlfg_m3d_injected_present_gate' `
'Cfg normalization'

Replace-Exact $feedRef `
'                         next.dlfg_m3b2b_native != g_cfg.dlfg_m3b2b_native ||
                         next.dlfg_m3c_queue != g_cfg.dlfg_m3c_queue;' `
'                         next.dlfg_m3b2b_native != g_cfg.dlfg_m3b2b_native ||
                         next.dlfg_m3c_queue != g_cfg.dlfg_m3c_queue ||
                         next.dlfg_m3d_injected_present_gate != g_cfg.dlfg_m3d_injected_present_gate;' `
'next.dlfg_m3d_injected_present_gate != g_cfg.dlfg_m3d_injected_present_gate' `
'Cfg rebuild trigger'

$gateOld = @'
    if ((g.frames_done % 60) == 0 && CfgReload()) g.frame_ready = false;
    if (!g_cfg.enabled || g_cfg.mode == 0) return;

    device *dev_api = rt->get_device();
'@
$gateNew = @'
    if ((g.frames_done % 60) == 0 && CfgReload()) g.frame_ready = false;
    if (!g_cfg.enabled || g_cfg.mode == 0) return;

    // M3D integration marker. OptiScaler's generated-frame present can re-enter ReShade,
    // which used to make FeedFrameVk advance temporal history again on a synthetic frame.
    // Even when the injected call does not re-enter, some layer chains invoke this technique
    // more than once inside one game present. Gate both cases before vk_frame increments or
    // any DLAA/DLSS-G work is recorded.
    if (g_cfg.dlfg_m3d_injected_present_gate != 0)
    {
        static uint64_t m3dLastRealPresent = 0;
        static uint64_t m3dAccepted = 0;
        static uint64_t m3dInjectedSkips = 0;
        static uint64_t m3dDuplicateSkips = 0;

        if (FeedM3dInjectedPresentActive())
        {
            ++m3dInjectedSkips;
            if (m3dInjectedSkips <= 8 || (m3dInjectedSkips % 120) == 0)
                Log("[feed] M3D: suppressed OptiScaler injected-present callback (injectedSkips=%llu realPresentSerial=%llu)",
                    static_cast<unsigned long long>(m3dInjectedSkips),
                    static_cast<unsigned long long>(FeedM3dRealPresentSerial()));
            return;
        }

        const uint64_t presentSerial = FeedM3dRealPresentSerial();
        if (presentSerial != 0 && presentSerial == m3dLastRealPresent)
        {
            ++m3dDuplicateSkips;
            if (m3dDuplicateSkips <= 8 || (m3dDuplicateSkips % 120) == 0)
                Log("[feed] M3D: suppressed duplicate Feeder callback inside real present=%llu (duplicateSkips=%llu)",
                    static_cast<unsigned long long>(presentSerial),
                    static_cast<unsigned long long>(m3dDuplicateSkips));
            return;
        }
        if (presentSerial != 0)
        {
            m3dLastRealPresent = presentSerial;
            ++m3dAccepted;
            if (m3dAccepted <= 8 || (m3dAccepted % 120) == 0)
                Log("[feed] M3D: accepted genuine real-present callback serial=%llu accepted=%llu injectedSeen=%llu",
                    static_cast<unsigned long long>(presentSerial),
                    static_cast<unsigned long long>(m3dAccepted),
                    static_cast<unsigned long long>(FeedM3dInjectedPresentCount()));
        }
    }

    device *dev_api = rt->get_device();
'@
Replace-Exact $feedRef $gateOld $gateNew '// M3D integration marker' 'FeedFrameVk real-present gate'
Write-Normalized $feedCpp $feedRef.Value

# -----------------------------------------------------------------------------
# Feeder present hook: count genuine present entries and identify OptiScaler's synthetic
# present through a tiny exported thread-local marker in the M3D OptiScaler binary.
# -----------------------------------------------------------------------------
$present = Read-Normalized $presentH
$presentRef = [ref]$present

$presentGlobalsOld = @'
static PFN_vkQueuePresentKHR g_vk_frame_present_orig;
static void *g_vk_frame_present_target;
'@
$presentGlobalsNew = @'
static PFN_vkQueuePresentKHR g_vk_frame_present_orig;
static void *g_vk_frame_present_target;

// M3D present-origin integration marker. The exporter lives in the M3D OptiScaler
// consumer. Resolution is lazy because proxy names vary (winmm.dll on the GTA IV rig).
using PFN_DLSS5_M3D_IsInjectedPresentActive = BOOL (WINAPI*)();
static PFN_DLSS5_M3D_IsInjectedPresentActive g_m3dInjectedPresentQuery;
static volatile LONG64 g_m3dRealPresentSerial;
static volatile LONG64 g_m3dInjectedPresentCount;

static PFN_DLSS5_M3D_IsInjectedPresentActive FeedM3dResolveInjectedPresentQuery()
{
    if (g_m3dInjectedPresentQuery != nullptr) return g_m3dInjectedPresentQuery;
    static const wchar_t *const names[] = {
        L"winmm.dll", L"version.dll", L"dbghelp.dll", L"winhttp.dll", L"wininet.dll",
        L"d3d12.dll", L"OptiScaler.dll", L"OptiScaler.asi"
    };
    for (const wchar_t *name : names)
    {
        HMODULE module = GetModuleHandleW(name);
        if (module == nullptr) continue;
        auto fn = reinterpret_cast<PFN_DLSS5_M3D_IsInjectedPresentActive>(
            GetProcAddress(module, "DLSS5_M3D_IsInjectedPresentActive"));
        if (fn != nullptr)
        {
            g_m3dInjectedPresentQuery = fn;
            break;
        }
    }
    return g_m3dInjectedPresentQuery;
}

static bool FeedM3dInjectedPresentActive()
{
    auto fn = FeedM3dResolveInjectedPresentQuery();
    return fn != nullptr && fn() != FALSE;
}

static uint64_t FeedM3dRealPresentSerial()
{
    return static_cast<uint64_t>(InterlockedCompareExchange64(&g_m3dRealPresentSerial, 0, 0));
}

static uint64_t FeedM3dInjectedPresentCount()
{
    return static_cast<uint64_t>(InterlockedCompareExchange64(&g_m3dInjectedPresentCount, 0, 0));
}
'@
Replace-Exact $presentRef $presentGlobalsOld $presentGlobalsNew '// M3D present-origin integration marker' 'present hook globals'

$presentFnOld = @'
static VKAPI_ATTR VkResult VKAPI_CALL FeedVkFramePresent(VkQueue queue, const VkPresentInfoKHR *info)
{
    FeedVkPresentContext context = { queue, info };
'@
$presentFnNew = @'
static VKAPI_ATTR VkResult VKAPI_CALL FeedVkFramePresent(VkQueue queue, const VkPresentInfoKHR *info)
{
    if (FeedM3dInjectedPresentActive())
        InterlockedIncrement64(&g_m3dInjectedPresentCount);
    else
        InterlockedIncrement64(&g_m3dRealPresentSerial);

    FeedVkPresentContext context = { queue, info };
'@
Replace-Exact $presentRef $presentFnOld $presentFnNew 'InterlockedIncrement64(&g_m3dRealPresentSerial)' 'present hook origin counter'
Write-Normalized $presentH $presentRef.Value

# -----------------------------------------------------------------------------
# OptiScaler consumer: export a thread-local marker only while making synthetic presents.
# The game's original present remains unmarked.
# -----------------------------------------------------------------------------
$opti = Read-Normalized $optiInc
$optiRef = [ref]$opti

$optiTopOld = @'
static void M3aResolveDeviceFunctions(VkDevice device);

static constexpr uint32_t kM3b2aConsumerSlots = 3;
'@
$optiTopNew = @'
static void M3aResolveDeviceFunctions(VkDevice device);

// M3D injected-present marker. Feeder resolves this export dynamically and suppresses
// ReShade/Feeder work triggered by synthetic generated-frame presents.
static thread_local uint32_t _m3dInjectedPresentDepth = 0;
extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_M3D_IsInjectedPresentActive()
{
    return _m3dInjectedPresentDepth != 0 ? TRUE : FALSE;
}
struct M3dInjectedPresentScope
{
    M3dInjectedPresentScope() { ++_m3dInjectedPresentDepth; }
    ~M3dInjectedPresentScope() { --_m3dInjectedPresentDepth; }
};

static constexpr uint32_t kM3b2aConsumerSlots = 3;
'@
Replace-Exact $optiRef $optiTopOld $optiTopNew '// M3D injected-present marker' 'Opti marker export'

$releaseOld = @'
    const VkResult r = o_QueuePresentKHR(queue, &release);
    LOG_WARN("M3B-2A: returned acquired image {} after local failure -> {}", imageIndex, (int) r);
'@
$releaseNew = @'
    VkResult r = VK_ERROR_UNKNOWN;
    {
        M3dInjectedPresentScope m3dScope;
        r = o_QueuePresentKHR(queue, &release);
    }
    LOG_WARN("M3B-2A: returned acquired image {} after local failure -> {}", imageIndex, (int) r);
'@
Replace-Exact $optiRef $releaseOld $releaseNew 'M3dInjectedPresentScope m3dScope;' 'failed-acquire synthetic present marker'

$insertOld = @'
    const VkResult insertedResult = o_QueuePresentKHR(queue, &inserted);

    // gameReady was consumed by the copy submit; never wait it twice.
'@
$insertNew = @'
    VkResult insertedResult = VK_ERROR_UNKNOWN;
    {
        M3dInjectedPresentScope m3dInsertedScope;
        insertedResult = o_QueuePresentKHR(queue, &inserted);
    }

    // gameReady was consumed by the copy submit; never wait it twice.
'@
Replace-Exact $optiRef $insertOld $insertNew 'M3dInjectedPresentScope m3dInsertedScope;' 'generated-frame synthetic present marker'
Write-Normalized $optiInc $optiRef.Value

Write-Host 'Applied M3D injected-present / real-present gate.'
Write-Host '  - default OFF: dlfg_m3d_injected_present_gate=0'
Write-Host '  - OptiScaler exports a thread-local marker only around synthetic presents'
Write-Host '  - Feeder suppresses synthetic callbacks and duplicate callbacks within one real QueuePresent'
Write-Host '  - M3C three-entry FIFO remains the transport/pipeline layer'
