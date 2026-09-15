# A3-S1 build-only transform: consume the exact per-frame raster jitter published by
# the 32-bit b-bridge and hand the same render-pixel offset to DLSS SR.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GeneratedRoot)
$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "A3-S1 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
$vk = [IO.File]::ReadAllText($vkPath)

$stateOld = 'static bool g_m3kArmed = false, g_m3kWasUsed = false;'
$stateNew = @'
static bool g_m3kArmed = false, g_m3kWasUsed = false;

// A3-S1 cross-process jitter handoff. The 32-bit bridge applies the raster shift
// to GTA IV and publishes the exact render-pixel sample before Present. This 64-bit
// reader uses a tiny seqlock snapshot so DLSS receives that same sample, not an
// independently generated approximation.
#pragma pack(push, 4)
struct M3kJitterSharedV1 {
    uint32_t magic;
    uint32_t version;
    volatile LONG writeSeq;
    LONG active;
    LONG frame;
    LONG epoch;
    LONG renderWidth;
    LONG renderHeight;
    float jitterX;
    float jitterY;
};
#pragma pack(pop)

struct M3kBridgeJitterSnapshot {
    bool valid = false;
    bool active = false;
    LONG frame = 0;
    LONG epoch = 0;
    UINT renderWidth = 0;
    UINT renderHeight = 0;
    float jitterX = 0.0f;
    float jitterY = 0.0f;
};

static constexpr uint32_t kM3kJitterMagic = 0x314A334Du;
static constexpr uint32_t kM3kJitterVersion = 1u;
static HANDLE g_m3kJitterMap = nullptr;
static const M3kJitterSharedV1 *g_m3kJitterShared = nullptr;
static ULONGLONG g_m3kJitterNextOpen = 0;
static bool g_m3kJitterStateKnown = false;
static bool g_m3kJitterLastActive = false;
static LONG g_m3kJitterLastEpoch = -1;
static LONG g_m3kJitterLastFrame = -1;

static bool M3kReadBridgeJitter(M3kBridgeJitterSnapshot *out)
{
    if (!out) return false;
    *out = M3kBridgeJitterSnapshot{};

    if (!g_m3kJitterShared)
    {
        const ULONGLONG now = GetTickCount64();
        if (now < g_m3kJitterNextOpen) return false;
        g_m3kJitterNextOpen = now + 1000;
        g_m3kJitterMap = OpenFileMappingW(FILE_MAP_READ, FALSE, L"Local\\M3K_GTAIV_Jitter_v1");
        if (!g_m3kJitterMap) return false;
        g_m3kJitterShared = reinterpret_cast<const M3kJitterSharedV1 *>(
            MapViewOfFile(g_m3kJitterMap, FILE_MAP_READ, 0, 0, sizeof(M3kJitterSharedV1)));
        if (!g_m3kJitterShared)
        {
            CloseHandle(g_m3kJitterMap); g_m3kJitterMap = nullptr;
            return false;
        }
        Log("M3K-A3-S1: bridge jitter handoff opened: Local\\M3K_GTAIV_Jitter_v1");
    }

    const volatile M3kJitterSharedV1 *s = g_m3kJitterShared;
    for (int attempt = 0; attempt < 4; ++attempt)
    {
        const LONG seq1 = s->writeSeq;
        if (seq1 & 1) { YieldProcessor(); continue; }
        MemoryBarrier();
        M3kBridgeJitterSnapshot snap;
        const uint32_t magic = s->magic;
        const uint32_t version = s->version;
        snap.active = s->active != 0;
        snap.frame = s->frame;
        snap.epoch = s->epoch;
        snap.renderWidth = s->renderWidth > 0 ? static_cast<UINT>(s->renderWidth) : 0;
        snap.renderHeight = s->renderHeight > 0 ? static_cast<UINT>(s->renderHeight) : 0;
        snap.jitterX = s->jitterX;
        snap.jitterY = s->jitterY;
        MemoryBarrier();
        const LONG seq2 = s->writeSeq;
        if (seq1 != seq2 || (seq2 & 1)) continue;
        if (magic != kM3kJitterMagic || version != kM3kJitterVersion) return false;
        snap.valid = true;
        *out = snap;
        return true;
    }
    return false;
}
'@
$vk = Replace-ExactOnce $vk $stateOld $stateNew 'shared jitter reader state'

$jitterOld = @'
        sr.InJitterOffsetX = 0.0f;
        sr.InJitterOffsetY = 0.0f;
'@
$jitterNew = @'
        M3kBridgeJitterSnapshot bridgeJitter;
        const bool bridgeJitterReadable = M3kReadBridgeJitter(&bridgeJitter);
        const bool bridgeJitterActive = bridgeJitterReadable && bridgeJitter.valid && bridgeJitter.active &&
            bridgeJitter.renderWidth == g_m3kSrW && bridgeJitter.renderHeight == g_m3kSrH;
        sr.InJitterOffsetX = bridgeJitterActive ? bridgeJitter.jitterX : 0.0f;
        sr.InJitterOffsetY = bridgeJitterActive ? bridgeJitter.jitterY : 0.0f;
        const bool bridgeJitterTransition = !g_m3kJitterStateKnown
            ? bridgeJitterActive
            : (bridgeJitterActive != g_m3kJitterLastActive) ||
              (bridgeJitterActive && bridgeJitter.epoch != g_m3kJitterLastEpoch);
'@
$vk = Replace-ExactOnce $vk $jitterOld $jitterNew 'SR jitter handoff'

$resetOld = '        if (g_m3kSrNeedsReset) sr.InReset = 1;'
$resetNew = @'
        if (g_m3kSrNeedsReset || bridgeJitterTransition) sr.InReset = 1;
'@
$vk = Replace-ExactOnce $vk $resetOld $resetNew 'history reset on jitter transition'

$successOld = '        g_m3kSrNeedsReset = false;'
$successNew = @'
        g_m3kSrNeedsReset = false;
        g_m3kJitterStateKnown = true;
        g_m3kJitterLastActive = bridgeJitterActive;
        g_m3kJitterLastEpoch = bridgeJitterActive ? bridgeJitter.epoch : -1;
        g_m3kJitterLastFrame = bridgeJitterActive ? bridgeJitter.frame : -1;
        static UINT64 a3JitterFrames = 0;
        ++a3JitterFrames;
        if (a3JitterFrames == 1 || (a3JitterFrames % 300) == 0 || bridgeJitterTransition)
            Log("M3K-A3-S1: SR raster/DLSS jitter active=%d bridgeFrame=%ld epoch=%ld render=%ux%u px=(%+.4f,%+.4f) reset=%d",
                bridgeJitterActive ? 1 : 0,
                bridgeJitterActive ? bridgeJitter.frame : -1,
                bridgeJitterActive ? bridgeJitter.epoch : -1,
                g_m3kSrW, g_m3kSrH, sr.InJitterOffsetX, sr.InJitterOffsetY, sr.InReset);
'@
$vk = Replace-ExactOnce $vk $successOld $successNew 'successful jitter state commit'

$vk = $vk.Replace('jitter=(0,0)', 'jitter=(bridge-synchronized; see M3K-A3-S1)')

foreach ($marker in @(
    'M3K-A3-S1: bridge jitter handoff opened',
    'bridgeJitterActive',
    'bridgeJitterTransition',
    'M3K-A3-S1: SR raster/DLSS jitter active=',
    'Local\\M3K_GTAIV_Jitter_v1')) {
    if ($vk.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw "A3-S1 generated source missing marker: $marker" }
}

[IO.File]::WriteAllText($vkPath, $vk, [Text.UTF8Encoding]::new($false))
Write-Host "A3-S1 bridge-synchronized jitter stage applied: $vkPath"
