[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)

$ErrorActionPreference = 'Stop'

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }

$vk = [IO.File]::ReadAllText($vkPath)
$feed = [IO.File]::ReadAllText($FeederSource)

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old,$pos,[StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "Public startup-prime fix ${Label}: expected exactly one match, found $count" }
    return $Text.Replace($Old,$New)
}

# Remember the profile that actually armed the cold-start stabilizer. A later public
# UI request is explicit user intent and must be allowed to take over immediately.
$stateAnchor = 'static LONG g_m3kStartupPrimeEpoch = -1;'
$stateNew = @'
static LONG g_m3kStartupPrimeEpoch = -1;
static UINT g_m3kStartupPrimeInitialProfile = 0xFFFFFFFFu;
'@
$vk = Replace-ExactOnce $vk $stateAnchor $stateNew 'initial profile state'

# Patch only the configure function body so newline style in the generated source is irrelevant.
$configureStart = $vk.IndexOf('static void M3kStartupPrimeConfigure(', [StringComparison]::Ordinal)
$observeStart = $vk.IndexOf('static void M3kStartupPrimeObserve(', $configureStart, [StringComparison]::Ordinal)
if ($configureStart -lt 0 -or $observeStart -le $configureStart) { throw 'Could not locate startup-prime configure boundaries' }
$configure = $vk.Substring($configureStart, $observeStart - $configureStart)
$epochLine = '    g_m3kStartupPrimeEpoch = -1;'
if (($configure.Split($epochLine).Count - 1) -ne 1) { throw 'Startup-prime configure epoch anchor mismatch' }
$configure = $configure.Replace($epochLine, $epochLine + "`r`n    g_m3kStartupPrimeInitialProfile = g_m3kSrProfileRequested;")
$vk = $vk.Substring(0,$configureStart) + $configure + $vk.Substring($observeStart)

# The old hardware gate reset the 180-frame counter whenever a frame was not a valid
# synchronized jitter frame. Real gameplay/menu traffic can interleave such frames,
# which can leave the game pinned at 1485x835 forever. Count only valid synchronized
# frames, but do not throw already-proven good frames away when an unrelated frame occurs.
$observeStart = $vk.IndexOf('static void M3kStartupPrimeObserve(', [StringComparison]::Ordinal)
$manualStart = $vk.IndexOf('static bool M3kReadManualRenderSize(', $observeStart, [StringComparison]::Ordinal)
if ($observeStart -lt 0 -or $manualStart -le $observeStart) { throw 'Could not locate startup-prime observer boundaries' }
$observeNew = @'
static void M3kStartupPrimeObserve(bool bridgeJitterActive, LONG bridgeEpoch, UINT renderW, UINT renderH)
{
    if (!g_m3kStartupPrimeActive) return;
    if (renderW != g_m3kStartupPrimeW || renderH != g_m3kStartupPrimeH) return;
    if (!bridgeJitterActive) return;

    if (g_m3kStartupPrimeEpoch != bridgeEpoch) {
        g_m3kStartupPrimeEpoch = bridgeEpoch;
        Log("M3K-A3-S5: prime synchronized to A3-S2 jitter epoch=%ld at %ux%u; valid frames=%u/%u",
            bridgeEpoch, renderW, renderH, g_m3kStartupPrimeStableFrames, g_m3kStartupPrimeRequiredFrames);
    }

    ++g_m3kStartupPrimeStableFrames;
    if (g_m3kStartupPrimeStableFrames < g_m3kStartupPrimeRequiredFrames) return;

    g_m3kStartupPrimeActive = false;
    g_m3kStartupPrimeCompleted = true;
    g_m3kResolutionPlanProfile = 0xFFFFFFFFu;
    g_m3kResolutionPlanOutW = g_m3kResolutionPlanOutH = 0;
    g_m3kResolutionConfirmedLogged = false;
    g_m3kSrNeedsReset = true;
    g_m3kWasUsed = false;
    g_m3k.ResetHistory();
    Log("M3K-A3-S5: STARTUP PRIME COMPLETE after %u cumulative synchronized SR frames; releasing to saved %s",
        g_m3kStartupPrimeStableFrames, M3kSrProfileName(g_m3kSrProfileRequested));
}

static bool M3kStartupPrimeIsActive() { return g_m3kStartupPrimeActive; }
static UINT M3kStartupPrimeValidFrames() { return g_m3kStartupPrimeStableFrames; }
static UINT M3kStartupPrimeRequiredFramesPublic() { return g_m3kStartupPrimeRequiredFrames; }
static UINT M3kStartupPrimeWidthPublic() { return g_m3kStartupPrimeW; }
static UINT M3kStartupPrimeHeightPublic() { return g_m3kStartupPrimeH; }

'@
$vk = $vk.Substring(0,$observeStart) + $observeNew + $vk.Substring($manualStart)

# Explicit live mode changes must not remain trapped behind the startup-prime override.
$queryStart = $vk.IndexOf('static bool M3kQueryProfileRenderSize(', [StringComparison]::Ordinal)
if ($queryStart -lt 0) { throw 'Could not locate profile render-size query' }
$primeIf = $vk.IndexOf('    if (g_m3kStartupPrimeActive) {', $queryStart, [StringComparison]::Ordinal)
if ($primeIf -lt 0) { throw 'Could not locate startup-prime render override' }
$cancelBlock = @'
    if (g_m3kStartupPrimeActive && g_m3kStartupPrimeInitialProfile <= 5 &&
        g_m3kSrProfileRequested != g_m3kStartupPrimeInitialProfile) {
        const UINT initial = g_m3kStartupPrimeInitialProfile;
        g_m3kStartupPrimeActive = false;
        g_m3kStartupPrimeCompleted = true;
        g_m3kResolutionPlanProfile = 0xFFFFFFFFu;
        g_m3kResolutionPlanOutW = g_m3kResolutionPlanOutH = 0;
        g_m3kResolutionConfirmedLogged = false;
        g_m3kSrNeedsReset = true;
        g_m3kWasUsed = false;
        g_m3k.ResetHistory();
        Log("M3K-A3-S5: startup prime cancelled by live profile change %s -> %s; honoring user request immediately",
            M3kSrProfileName(initial), M3kSrProfileName(g_m3kSrProfileRequested));
    }

'@
$vk = $vk.Substring(0,$primeIf) + $cancelBlock + $vk.Substring($primeIf)

# Make the temporary override visible in the public panel instead of showing a profile
# name that suggests it already owns the real render resolution.
$appliedAnchor = '        ImGui::Text("Applied: %s", M3kSrProfileName(M3kAppliedSrProfile()));'
$appliedNew = @'
        if (M3kStartupPrimeIsActive()) {
            ImGui::TextColored(ImVec4(1.0f, 0.78f, 0.25f, 1.0f),
                "Startup stabilization: %u x %u (%u/%u synchronized frames)",
                M3kStartupPrimeWidthPublic(), M3kStartupPrimeHeightPublic(),
                M3kStartupPrimeValidFrames(), M3kStartupPrimeRequiredFramesPublic());
            ImGui::TextWrapped("Selecting a different DLSS/DLAA mode exits startup stabilization immediately and applies your requested mode.");
        }
        ImGui::Text("Applied: %s", M3kSrProfileName(M3kAppliedSrProfile()));
'@
$feed = Replace-ExactOnce $feed $appliedAnchor $appliedNew 'public prime status'

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))

$verify = [IO.File]::ReadAllText($vkPath) + [IO.File]::ReadAllText($FeederSource)
foreach ($marker in @(
    'g_m3kStartupPrimeInitialProfile',
    'STARTUP PRIME COMPLETE after %u cumulative synchronized SR frames',
    'startup prime cancelled by live profile change',
    'M3kStartupPrimeIsActive()',
    'Startup stabilization:',
    'exits startup stabilization immediately')) {
    if ($verify.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) { throw "Public startup-prime fix verification marker missing: $marker" }
}

Write-Host 'Public startup-prime fix ready: cumulative synchronized frames + live mode-change escape + visible stabilization status.'
