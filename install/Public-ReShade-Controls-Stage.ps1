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
    if ($count -ne 1) { throw "Public ReShade controls ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }

$vk = [IO.File]::ReadAllText($vkPath)
$feed = [IO.File]::ReadAllText($FeederSource)

$nrStateAnchor = 'static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }'
$nrStateNew = @'
static int g_m3kUiRequestedMode = -1;

static void M3kWriteNrModeIni(int mode)
{
    wchar_t path[MAX_PATH] = {};
    if (!GetModuleFileNameW(g_self, path, MAX_PATH)) return;
    if (wchar_t *slash = wcsrchr(path, L'\\')) {
        *(slash + 1) = 0;
        wcscat_s(path, L"m3k-nr.ini");
        wchar_t value[8] = {};
        _snwprintf_s(value, _TRUNCATE, L"%d", mode);
        WritePrivateProfileStringW(L"M3K", L"Mode", value, path);
    }
}

static bool M3kNrEnabledRequested()
{
    const int requested = g_m3kUiRequestedMode >= 0 ? g_m3kUiRequestedMode : g_m3kMode;
    return requested == 2;
}

static void M3kRequestNrEnabledLive(bool enabled)
{
    const int mode = enabled ? 2 : 0;
    if (M3kNrEnabledRequested() == enabled) return;
    g_m3kUiRequestedMode = mode;
    M3kWriteNrModeIni(mode);
    Log("M3K-UI: ReShade requested Neural Rendering %s; safe runtime switch will apply on the normal config poll",
        enabled ? "ON" : "OFF");
}

static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }
'@
$vk = Replace-ExactOnce $vk $nrStateAnchor $nrStateNew 'NR UI state/API'

$pollAnchor = '        const int mode = requested <= 2 ? int(requested) : 0;'
$pollNew = @'
        const int mode = requested <= 2 ? int(requested) : 0;
        g_m3kUiRequestedMode = mode;
'@
$vk = Replace-ExactOnce $vk $pollAnchor $pollNew 'NR requested-mode sync'

# The frozen custom-UQ stage already uses the public label. Keep compatibility with
# older generated sources without requiring a second copy of the same text.
if ($vk.IndexOf('case 1: return "Custom Ultra Quality (77%)";',[StringComparison]::Ordinal) -lt 0) {
    $vk = Replace-ExactOnce $vk '        case 1: return "Ultra Quality";' '        case 1: return "Custom Ultra Quality (77%)";' 'Ultra Quality label'
}

$feed = Replace-ExactOnce $feed `
    '    if (ImGui::CollapsingHeader("M3K Neural Rendering"))' `
    '    if (ImGui::CollapsingHeader("GTA IV DLSS"))' `
    'panel title'

$passesAnchor = @'
        const UINT requested = M3kRequestedNrPasses();
        ImGui::TextUnformatted("Feature 18 passes (live)");
'@
$passesNew = @'
        bool nrEnabled = M3kNrEnabledRequested();
        if (ImGui::Checkbox("Neural Rendering##M3KNrEnabled", &nrEnabled))
            M3kRequestNrEnabledLive(nrEnabled);
        ImGui::SameLine();
        ImGui::Text("%s", nrEnabled ? "ON" : "OFF");
        ImGui::TextWrapped("DLSS 5 Neural Rendering runs before DLSS Super Resolution. This setting is saved automatically.");
        ImGui::Spacing();

        const UINT requested = M3kRequestedNrPasses();
        ImGui::TextUnformatted("Neural Rendering passes (advanced)");
'@
$feed = Replace-ExactOnce $feed $passesAnchor $passesNew 'NR toggle and pass label'

$feed = Replace-ExactOnce $feed `
    '        ImGui::TextWrapped("First use of a higher count may hitch briefly while its independent NR feature is created. Click 5 once to warm all five, then 1-5 comparisons are immediate without restarting GTA.");' `
    '        ImGui::TextWrapped("1 pass is the tested public default. Higher counts are experimental, may hitch while warming, and can cost significant performance.");' `
    'NR pass guidance'

$qualityOld = @'
        ImGui::Spacing();
        ImGui::TextUnformatted("DLSS reconstruction (live)");
        int srProfile = static_cast<int>(M3kRequestedSrProfile());
        const char *srItems = "DLAA only (presenter)\0Ultra Quality\0Quality\0Balanced\0Performance\0Ultra Performance\0\0";
        if (ImGui::Combo("Mode##M3KSRProfile", &srProfile, srItems))
            M3kRequestSrProfileLive(static_cast<UINT>(srProfile));
        ImGui::Text("Applied: %s", M3kSrProfileName(M3kAppliedSrProfile()));
        if (M3kRequestedSrProfile() == 0)
            ImGui::TextWrapped("DLAA-only is a presenter-space A/B baseline. GTA's true S1B render remains 1600x900; it is not native-rendered 1440p DLAA.");
        else
            ImGui::TextWrapped("SR profiles keep the true DXVK source resolution fixed and change NVIDIA's DLSS perf-quality profile. Unsupported profiles at this input size are rejected safely.");
'@
$qualityNew = @'
        ImGui::Spacing();
        ImGui::TextUnformatted("DLSS Super Resolution quality");
        int srProfile = static_cast<int>(M3kRequestedSrProfile());
        if (srProfile < 1 || srProfile > 5) srProfile = 2;
        int srIndex = srProfile - 1;
        const char *srItems = "Custom Ultra Quality (77%)\0Quality\0Balanced\0Performance\0Ultra Performance\0\0";
        if (ImGui::Combo("Quality##M3KSRProfile", &srIndex, srItems))
            M3kRequestSrProfileLive(static_cast<UINT>(srIndex + 1));
        ImGui::Text("Applied: %s", M3kSrProfileName(M3kAppliedSrProfile()));
        ImGui::TextWrapped("Quality changes are saved automatically and apply live. Unsupported modes are rejected safely.");
'@
$feed = Replace-ExactOnce $feed $qualityOld $qualityNew 'DLSS quality controls'

[IO.File]::WriteAllText($vkPath, $vk, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($FeederSource, $feed, (New-Object Text.UTF8Encoding($false)))

$verify = [IO.File]::ReadAllText($vkPath) + [IO.File]::ReadAllText($FeederSource)
foreach ($marker in @(
    'M3kRequestNrEnabledLive',
    'M3K-UI: ReShade requested Neural Rendering',
    'GTA IV DLSS',
    'Neural Rendering##M3KNrEnabled',
    'Neural Rendering passes (advanced)',
    '1 pass is the tested public default',
    'DLSS Super Resolution quality',
    'Custom Ultra Quality (77%)',
    'Quality##M3KSRProfile')) {
    if ($verify.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Public ReShade controls verification marker missing: $marker"
    }
}

Write-Host 'Public ReShade controls ready: Neural Rendering Off/On + 1-pass default guidance + five DLSS quality modes.'
