# A2-S2.3: live 1..5 pass switching in the existing ReShade overlay.
# This deliberately keeps the proven S2.2 ownership model: changing pass count
# rebuilds the independent feature-18 chain in-process on the next frame.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)

$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0
    $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) {
        $count++
        $pos = $i + $Old.Length
    }
    if ($count -ne 1) { throw "A2-S2.3 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

$nrPath = Join-Path $GeneratedRoot 'm3k_nr.h'
$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $nrPath) -or -not (Test-Path -LiteralPath $vkPath)) {
    throw "A2-S2.3 generated headers missing under $GeneratedRoot"
}
if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }

$nr = [IO.File]::ReadAllText($nrPath)
$vk = [IO.File]::ReadAllText($vkPath)
$feed = [IO.File]::ReadAllText($FeederSource)

# S2.2 already has independent per-pass handles/params/outputs/histories. Raise its ceiling.
$nr = Replace-ExactOnce $nr `
    'static constexpr unsigned MaxPasses = 3;' `
    'static constexpr unsigned MaxPasses = 5;' `
    'MaxPasses 3 -> 5'

# Raise the config clamp.
$vk = Replace-ExactOnce $vk `
    'const UINT nrPasses = requestedPasses < 1 ? 1 : (requestedPasses > 3 ? 3 : requestedPasses);' `
    'const UINT nrPasses = requestedPasses < 1 ? 1 : (requestedPasses > 5 ? 5 : requestedPasses);' `
    'NRPasses clamp 1..5'
$vk = Replace-ExactOnce $vk `
    'Log("M3K-A2-S2.2: NRPasses=%u (independent feature18 instances; allowed 1..3)", nrPasses);' `
    'Log("M3K-A2-S2.3: NRPasses=%u (independent feature18 instances; live allowed 1..5)", nrPasses);' `
    'NRPasses live log'

# Accessors and live request entry point used by the ReShade overlay.
$stateOld = @'
static UINT g_m3kSrW = 0, g_m3kSrH = 0, g_m3kSrOutW = 0, g_m3kSrOutH = 0;
#endif
'@
$stateNew = @'
static UINT g_m3kSrW = 0, g_m3kSrH = 0, g_m3kSrOutW = 0, g_m3kSrOutH = 0;
#endif

static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }
static UINT M3kActiveNrPasses() { return g_m3k.PassCount(); }

static void M3kRequestNrPassesLive(UINT passes)
{
    if (passes < 1) passes = 1;
    if (passes > 5) passes = 5;
    if (passes == g_m3kNrPasses) return;

    const UINT old = g_m3kNrPasses;
    g_m3kNrPasses = passes;
    g_m3k.ResetHistory();
#if defined(VK_VERSION_1_0)
    g_m3kSrNeedsReset = true;
#endif

    wchar_t path[MAX_PATH] = {};
    if (GetModuleFileNameW(g_self, path, MAX_PATH))
    {
        if (wchar_t *slash = wcsrchr(path, L'\\'))
        {
            *(slash + 1) = 0;
            wcscat_s(path, L"m3k-nr.ini");
            wchar_t value[8] = {};
            _snwprintf_s(value, _TRUNCATE, L"%u", passes);
            WritePrivateProfileStringW(L"M3K", L"NRPasses", value, path);
        }
    }

    Log("M3K-LIVE: ReShade requested NR passes %u -> %u; chain rebuilds in-process on next frame", old, passes);
}
'@
$vk = Replace-ExactOnce $vk $stateOld $stateNew 'live request API'

# Rename the periodic path marker so the runtime log proves this exact build is active.
$vk = $vk.Replace('M3K-A2-S2.2: %s passes=%u -> DLSS SR running',
                  'M3K-A2-S2.3: %s passes=%u -> DLSS SR running')

# Add a collapsible M3K section inside the add-on's existing ReShade overlay.
$overlayOld = @'
static void DrawOverlay(reshade::api::effect_runtime *rt)
{
    bool dirty = false;
'@
$overlayNew = @'
static void DrawOverlay(reshade::api::effect_runtime *rt)
{
    bool dirty = false;

    if (ImGui::CollapsingHeader("M3K Neural Rendering"))
    {
        const UINT requested = M3kRequestedNrPasses();
        ImGui::TextUnformatted("Feature 18 passes (live)");
        for (UINT p = 1; p <= 5; ++p)
        {
            if (p > 1) ImGui::SameLine();
            char label[24] = {};
            _snprintf_s(label, sizeof(label), _TRUNCATE, "%u##M3KPass", p);
            if (ImGui::RadioButton(label, requested == p))
                M3kRequestNrPassesLive(p);
        }
        ImGui::Text("Requested: %u    Active chain: %u", requested, M3kActiveNrPasses());
        ImGui::TextWrapped("Changes apply without restarting GTA. A brief hitch is expected while the independent Feature 18 chain is rebuilt; after that you can inspect the new pass count immediately in the same scene.");
        ImGui::Separator();
    }
'@
$feed = Replace-ExactOnce $feed $overlayOld $overlayNew 'ReShade M3K submenu'

[IO.File]::WriteAllText($nrPath, $nr, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($vkPath, $vk, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($FeederSource, $feed, (New-Object Text.UTF8Encoding($false)))

$verify = [IO.File]::ReadAllText($nrPath) + [IO.File]::ReadAllText($vkPath) + [IO.File]::ReadAllText($FeederSource)
foreach ($marker in @(
    'static constexpr unsigned MaxPasses = 5;',
    'requestedPasses > 5 ? 5',
    'M3kRequestNrPassesLive',
    'M3K Neural Rendering',
    'Changes apply without restarting GTA',
    'M3K-A2-S2.3: %s passes=%u -> DLSS SR running')) {
    if ($verify.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A2-S2.3 verification marker missing: $marker"
    }
}

Write-Host "A2-S2.3 live 1..5 source ready: $GeneratedRoot"
Write-Host 'ReShade overlay patched with M3K Neural Rendering live pass selector.'
