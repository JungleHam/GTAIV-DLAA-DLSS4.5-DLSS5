# A3-S2.2 build-only transform: keep the hardware-validated A3-S2 bridge and
# A3-S1.2/S1.1 SR behavior unchanged, but feed Native/DLAA the same bridge-owned
# per-frame raster jitter (with the proven NGX sign=-1 convention).
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GeneratedRoot)
$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "A3-S2.2 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
$vk = [IO.File]::ReadAllText($vkPath)

# A3-S1 already inserted the shared-memory reader and SR-side state. Keep Native
# tracking separate so switching between Native and SR cannot contaminate either
# path's transition/reset bookkeeping.
$stateOld = 'static LONG g_m3kJitterLastFrame = -1;'
$stateNew = @'
static LONG g_m3kJitterLastFrame = -1;

// A3-S2.2 Native/DLAA jitter state. Separate from SR state on purpose.
static bool g_m3kNativeJitterStateKnown = false;
static bool g_m3kNativeJitterLastActive = false;
static LONG g_m3kNativeJitterLastEpoch = -1;
static LONG g_m3kNativeJitterLastFrame = -1;
'@
$vk = Replace-ExactOnce $vk $stateOld $stateNew 'Native jitter state'

$nativeOld = @'
    auto dlaa = *ep;
    int nr = g_m3kMode == 2 && g_m3kArmed ? g_m3k.Evaluate(g.list, *ep) : 0;
'@
$nativeNew = @'
    auto dlaa = *ep;

    // A3-S2.2: Native/DLAA must consume the exact sample used to jitter GTA's
    // raster, just like SR does. A3-S2 publishes render-pixel jitter before Present;
    // the NGX convention was hardware-proven at sign=-1 in A3-S1.1/A3-S2.
    M3kBridgeJitterSnapshot nativeBridgeJitter;
    const bool nativeBridgeJitterReadable = M3kReadBridgeJitter(&nativeBridgeJitter);
    const bool nativeBridgeJitterActive = nativeBridgeJitterReadable && nativeBridgeJitter.valid &&
        nativeBridgeJitter.active &&
        nativeBridgeJitter.renderWidth == g.width && nativeBridgeJitter.renderHeight == g.height;
    dlaa.InJitterOffsetX = nativeBridgeJitterActive ? -nativeBridgeJitter.jitterX : 0.0f;
    dlaa.InJitterOffsetY = nativeBridgeJitterActive ? -nativeBridgeJitter.jitterY : 0.0f;
    const bool nativeBridgeJitterTransition = !g_m3kNativeJitterStateKnown
        ? nativeBridgeJitterActive
        : (nativeBridgeJitterActive != g_m3kNativeJitterLastActive) ||
          (nativeBridgeJitterActive && nativeBridgeJitter.epoch != g_m3kNativeJitterLastEpoch);
    if (nativeBridgeJitterTransition)
        dlaa.InReset = 1;

    int nr = g_m3kMode == 2 && g_m3kArmed ? g_m3k.Evaluate(g.list, *ep) : 0;
'@
$vk = Replace-ExactOnce $vk $nativeOld $nativeNew 'Native DLAA jitter handoff'

$commitOld = @'
    g_m3kWasUsed = used && !*code && NVSDK_NGX_SUCCEED(result);
    static UINT64 nrDlaaFrames = 0;
'@
$commitNew = @'
    if (!*code && NVSDK_NGX_SUCCEED(result)) {
        g_m3kNativeJitterStateKnown = true;
        g_m3kNativeJitterLastActive = nativeBridgeJitterActive;
        g_m3kNativeJitterLastEpoch = nativeBridgeJitterActive ? nativeBridgeJitter.epoch : -1;
        g_m3kNativeJitterLastFrame = nativeBridgeJitterActive ? nativeBridgeJitter.frame : -1;
    }
    g_m3kWasUsed = used && !*code && NVSDK_NGX_SUCCEED(result);
    static UINT64 nativeJitterFrames = 0;
    ++nativeJitterFrames;
    if (nativeJitterFrames == 1 || (nativeJitterFrames % 300) == 0 || nativeBridgeJitterTransition)
        Log("M3K-A3-S2.2-NATIVE: raster/DLAA jitter active=%d bridgeFrame=%ld epoch=%ld render=%ux%u dlssPx=(%+.4f,%+.4f) reset=%d",
            nativeBridgeJitterActive ? 1 : 0,
            nativeBridgeJitterActive ? nativeBridgeJitter.frame : -1,
            nativeBridgeJitterActive ? nativeBridgeJitter.epoch : -1,
            g.width, g.height, dlaa.InJitterOffsetX, dlaa.InJitterOffsetY, dlaa.InReset);
    static UINT64 nrDlaaFrames = 0;
'@
$vk = Replace-ExactOnce $vk $commitOld $commitNew 'Native jitter state commit/log'

foreach ($marker in @(
    'g_m3kNativeJitterStateKnown',
    'nativeBridgeJitterActive',
    'dlaa.InJitterOffsetX = nativeBridgeJitterActive ? -nativeBridgeJitter.jitterX : 0.0f;',
    'dlaa.InJitterOffsetY = nativeBridgeJitterActive ? -nativeBridgeJitter.jitterY : 0.0f;',
    'M3K-A3-S2.2-NATIVE: raster/DLAA jitter active=')) {
    if ($vk.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A3-S2.2 generated source missing marker: $marker"
    }
}

# Protect the already-proven SR sign convention.
foreach ($marker in @(
    'sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;',
    'sr.InJitterOffsetY = bridgeJitterActive ? -bridgeJitter.jitterY : 0.0f;')) {
    if ($vk.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A3-S2.2 would lose proven SR jitter marker: $marker"
    }
}

[IO.File]::WriteAllText($vkPath, $vk, [Text.UTF8Encoding]::new($false))
Write-Host "Applied M3K A3-S2.2 Native/DLAA bridge-synchronized jitter: $vkPath"
