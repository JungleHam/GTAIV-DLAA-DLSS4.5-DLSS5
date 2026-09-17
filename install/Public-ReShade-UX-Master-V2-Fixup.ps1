[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old,$pos,[StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "UX/master v2 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old,$New)
}

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }
$vk = [IO.File]::ReadAllText($vkPath)
$feed = [IO.File]::ReadAllText($FeederSource)

# v1 made the master flag false immediately, disabled jitter immediately, and then asked
# GTA/DXVK to resize to native. Hardware testing showed that repeated low-res -> OFF transitions
# can terminate during the effect-runtime/swapchain rebuild. v2 makes OFF a staged transition:
# keep the already-proven DLSS path alive, perform the same safe low-res -> DLAA Native switch
# a user can do manually, wait for native source stability, then disable bridge jitter, wait for
# its 250 ms config poll to observe that, and only then enter raw passthrough.
$varsOld = @'
static bool g_m3kMasterEnabled = true;
static bool g_m3kMasterStateInitialized = false;
static UINT g_m3kMasterSavedProfile = 2;
static bool g_m3kMasterSavedNr = false;
'@
$varsNew = @'
static bool g_m3kMasterEnabled = true;
static bool g_m3kMasterStateInitialized = false;
static bool g_m3kMasterDisablePending = false;
static UINT g_m3kMasterNativeStableFrames = 0;
static ULONGLONG g_m3kMasterJitterOffTick = 0;
static UINT g_m3kMasterSavedProfile = 2;
static bool g_m3kMasterSavedNr = false;
'@
$vk = Replace-ExactOnce $vk $varsOld $varsNew 'state variables'

$vk = Replace-ExactOnce $vk `
    'static bool M3kMasterEnabledRequested() { return g_m3kMasterEnabled; }' `
    'static bool M3kMasterEnabledRequested() { return g_m3kMasterEnabled && !g_m3kMasterDisablePending; }' `
    'requested master state'

$fnStartMarker = 'static void M3kRequestMasterEnabledLive(bool enabled)'
$fnEndMarker = 'static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }'
$fnStart = $vk.IndexOf($fnStartMarker,[StringComparison]::Ordinal)
$fnEnd = $vk.IndexOf($fnEndMarker,$fnStart,[StringComparison]::Ordinal)
if ($fnStart -lt 0 -or $fnEnd -lt 0) { throw 'UX/master v2 could not locate v1 master function span' }
$fnNew = @'
static void M3kRequestMasterEnabledLive(bool enabled)
{
    if (!enabled)
    {
        if (!g_m3kMasterEnabled || g_m3kMasterDisablePending) return;

        UINT profile = M3kRequestedSrProfile();
        if (profile > 5) profile = 2;
        g_m3kMasterSavedProfile = profile;
        g_m3kMasterSavedNr = M3kNrEnabledRequested();
        M3kWriteMasterIni(L"LastSRProfile", g_m3kMasterSavedProfile);
        M3kWriteMasterIni(L"LastNRMode", g_m3kMasterSavedNr ? 2u : 0u);
        // Marker only: if GTA exits while OFF, next launch restores the saved mode and starts ON.
        M3kWriteMasterIni(L"MasterEnabled", 0);

        g_m3kMasterDisablePending = true;
        g_m3kMasterNativeStableFrames = 0;
        g_m3kMasterJitterOffTick = 0;
        // Keep temporal jitter ON while the normal live-resolution path performs the same
        // transition as selecting DLAA Native manually. NR may stop immediately; it does not
        // own the D3D9/DXVK resize.
        M3kRequestNrEnabledLive(false);
        M3kRequestSrProfileLive(0);
        g_m3k.ResetHistory();
        Log("M3K-MASTER-V2: OFF stage 1 - switching through normal DLAA Native path; jitter stays ON during resize");
        return;
    }

    // ON also cancels a not-yet-finished OFF transition.
    const bool wasPending = g_m3kMasterDisablePending;
    g_m3kMasterDisablePending = false;
    g_m3kMasterNativeStableFrames = 0;
    g_m3kMasterJitterOffTick = 0;
    g_m3kMasterEnabled = true;
    M3kWriteMasterIni(L"MasterEnabled", 1);
    M3kWriteMasterIni(L"TemporalJitter", 1);
    M3kRequestSrProfileLive(g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2);
    M3kRequestNrEnabledLive(g_m3kMasterSavedNr);
    g_m3k.ResetHistory();
    Log("M3K-MASTER-V2: ON requested%s; restoring reconstruction=%s NR=%s jitter=ON",
        wasPending ? " (OFF transition cancelled)" : "",
        M3kSrProfileName(g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2),
        g_m3kMasterSavedNr ? "ON" : "OFF");
}

static void M3kAdvanceMasterDisable()
{
    if (!g_m3kMasterDisablePending) return;

    const bool nativeReady = g_m3kSourceTapReady && g.width && g.height &&
        g_m3kSrProfileRequested == 0 && g_m3kSrProfileApplied == 0 &&
        g_m3kPresentSource.width == g.width && g_m3kPresentSource.height == g.height &&
        g_m3kPresentSource.presenterWidth == g.width && g_m3kPresentSource.presenterHeight == g.height;

    if (!nativeReady)
    {
        g_m3kMasterNativeStableFrames = 0;
        g_m3kMasterJitterOffTick = 0;
        return;
    }

    if (g_m3kMasterNativeStableFrames < 30)
    {
        ++g_m3kMasterNativeStableFrames;
        return;
    }

    if (!g_m3kMasterJitterOffTick)
    {
        // b-bridge polls TemporalJitter every 250 ms. Do not enter raw passthrough until that
        // poll has had ample time to restore an unjittered WVP on the native render path.
        M3kWriteMasterIni(L"TemporalJitter", 0);
        g_m3kMasterJitterOffTick = GetTickCount64();
        Log("M3K-MASTER-V2: OFF stage 2 - native stable for 30 frames; requested jitter OFF, waiting 400 ms before raw passthrough");
        return;
    }

    if (GetTickCount64() - g_m3kMasterJitterOffTick < 400) return;

    g_m3kMasterDisablePending = false;
    g_m3kMasterEnabled = false;
    g_m3kMasterNativeStableFrames = 0;
    g_m3kMasterJitterOffTick = 0;
    g_m3k.ResetHistory();
    Log("M3K-MASTER-V2: OFF ACTIVE - native GTA frame passes through untouched; NR/SR/DLAA/jitter disabled");
}

'@
$vk = $vk.Substring(0,$fnStart) + $fnNew + $vk.Substring($fnEnd)

# Master OFF is session-only. The v1 persistence caused the next launch to begin at Native,
# bypassing A3-S5's 1485x835 stabilization prime and bringing the startup vibration back.
# If the previous session ended while OFF, restore the remembered mode before the existing
# config poll computes requested Mode/SRProfile, then clear the marker immediately.
$pollStartMarker = '        const bool masterFromIni = GetPrivateProfileIntW(L"M3K", L"MasterEnabled", 1, path) != 0;'
$pollEndMarker = '        const UINT requested = g_m3kMasterEnabled ? GetPrivateProfileIntW(L"M3K", L"Mode", 0, path) : 0;'
$pollStart = $vk.IndexOf($pollStartMarker,[StringComparison]::Ordinal)
$pollEnd = $vk.IndexOf($pollEndMarker,$pollStart,[StringComparison]::Ordinal)
if ($pollStart -lt 0 -or $pollEnd -lt 0) { throw 'UX/master v2 could not locate v1 persistent master poll' }
$pollEnd += $pollEndMarker.Length
$pollNew = @'
        const bool resumeMasterOnLaunch = GetPrivateProfileIntW(L"M3K", L"MasterEnabled", 1, path) == 0;
        const UINT savedProfileRaw = GetPrivateProfileIntW(L"M3K", L"LastSRProfile", 2, path);
        const UINT savedNrRaw = GetPrivateProfileIntW(L"M3K", L"LastNRMode", 0, path);
        g_m3kMasterSavedProfile = savedProfileRaw <= 5 ? savedProfileRaw : 2;
        g_m3kMasterSavedNr = savedNrRaw == 2;
        if (!g_m3kMasterStateInitialized)
        {
            g_m3kMasterEnabled = true;
            g_m3kMasterDisablePending = false;
            g_m3kMasterNativeStableFrames = 0;
            g_m3kMasterJitterOffTick = 0;
            if (resumeMasterOnLaunch)
            {
                M3kWriteMasterIni(L"SRProfile", g_m3kMasterSavedProfile);
                M3kWriteMasterIni(L"Mode", g_m3kMasterSavedNr ? 2u : 0u);
                Log("M3K-MASTER-V2: previous session ended OFF; startup restored reconstruction=%s NR=%s before startup prime",
                    M3kSrProfileName(g_m3kMasterSavedProfile), g_m3kMasterSavedNr ? "ON" : "OFF");
            }
            M3kWriteMasterIni(L"MasterEnabled", 1);
            M3kWriteMasterIni(L"TemporalJitter", 1);
            g_m3kMasterStateInitialized = true;
            Log("M3K-MASTER-V2: session starts ON; master OFF is not carried across launches");
        }
        const UINT requested = g_m3kMasterEnabled ? GetPrivateProfileIntW(L"M3K", L"Mode", 0, path) : 0;
'@
$vk = $vk.Substring(0,$pollStart) + $pollNew + $vk.Substring($pollEnd)

# Advance the staged transition every frame immediately after the normal planner has run.
$feed = Replace-ExactOnce $feed `
    '        M3kPrepareFrame(); // M3K live state + resolution planner' `
    "        M3kPrepareFrame(); // M3K live state + resolution planner`r`n        M3kAdvanceMasterDisable();" `
    'frame-state advance'

# Make the UI explain the staged safe transition, without changing the layout that passed v1.
$feed = $feed.Replace(
    '"DISABLING - switching GTA to native..."',
    '"DISABLING - native transition / jitter drain..."')

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))

$verify = $vk + $feed
foreach ($marker in @(
    'M3K-MASTER-V2: OFF stage 1',
    'M3K-MASTER-V2: OFF stage 2',
    'M3K-MASTER-V2: OFF ACTIVE',
    'previous session ended OFF; startup restored reconstruction=',
    'master OFF is not carried across launches',
    'M3kAdvanceMasterDisable();',
    'GetTickCount64() - g_m3kMasterJitterOffTick < 400')) {
    if ($verify.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) { throw "UX/master v2 verification marker missing: $marker" }
}
Write-Host 'Public ReShade UX/master v2 safety fixup applied.'
