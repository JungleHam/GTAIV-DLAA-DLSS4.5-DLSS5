[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old,$pos,[StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "UX/master ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old,$New)
}

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }
$vk = [IO.File]::ReadAllText($vkPath)
$feed = [IO.File]::ReadAllText($FeederSource)

foreach ($required in @('M3kRequestSrProfileLive','M3kRequestNrEnabledLive','M3kCurrentSourceWidth','M3K-A3-S5: STARTUP PRIME COMPLETE','GTA IV DLSS')) {
    if (($vk + $feed).IndexOf($required,[StringComparison]::Ordinal) -lt 0) { throw "UX/master prerequisite missing: $required" }
}

# Public master state lives beside the existing public UI helpers. OFF is deliberately
# a two-stage transition: first NR/jitter are stopped and GTA is moved to native profile 0;
# only after the DXVK source tap proves native==presenter do we bypass the Feeder path.
$stateAnchor = 'static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }'
$stateNew = @'
static bool g_m3kMasterEnabled = true;
static bool g_m3kMasterStateInitialized = false;
static UINT g_m3kMasterSavedProfile = 2;
static bool g_m3kMasterSavedNr = false;

static bool M3kMasterConfigPath(wchar_t *path, size_t count)
{
    if (!path || !count || !GetModuleFileNameW(g_self, path, static_cast<DWORD>(count))) return false;
    wchar_t *slash = wcsrchr(path, L'\\');
    if (!slash) return false;
    *(slash + 1) = 0;
    wcscat_s(path, count, L"m3k-nr.ini");
    return true;
}

static void M3kWriteMasterIni(const wchar_t *key, UINT value)
{
    wchar_t path[MAX_PATH] = {};
    if (!M3kMasterConfigPath(path, MAX_PATH)) return;
    wchar_t text[16] = {};
    _snwprintf_s(text, _TRUNCATE, L"%u", value);
    WritePrivateProfileStringW(L"M3K", key, text, path);
}

static bool M3kMasterEnabledRequested() { return g_m3kMasterEnabled; }

static bool M3kMasterNativePassthroughReady()
{
    if (g_m3kMasterEnabled || !g_m3kSourceTapReady || !g.width || !g.height) return false;
    if (g_m3kSrProfileRequested != 0 || g_m3kSrProfileApplied != 0) return false;
    return g_m3kPresentSource.width == g.width &&
           g_m3kPresentSource.height == g.height &&
           g_m3kPresentSource.presenterWidth == g.width &&
           g_m3kPresentSource.presenterHeight == g.height;
}

static void M3kRequestMasterEnabledLive(bool enabled)
{
    if (enabled == g_m3kMasterEnabled) return;

    if (!enabled)
    {
        UINT profile = M3kRequestedSrProfile();
        if (profile > 5) profile = 2;
        g_m3kMasterSavedProfile = profile;
        g_m3kMasterSavedNr = M3kNrEnabledRequested();
        M3kWriteMasterIni(L"LastSRProfile", g_m3kMasterSavedProfile);
        M3kWriteMasterIni(L"LastNRMode", g_m3kMasterSavedNr ? 2u : 0u);

        g_m3kMasterEnabled = false;
        M3kWriteMasterIni(L"MasterEnabled", 0);
        M3kWriteMasterIni(L"TemporalJitter", 0);
        M3kRequestNrEnabledLive(false);
        M3kRequestSrProfileLive(0);
        g_m3k.ResetHistory();
        Log("M3K-MASTER: OFF requested; NR/jitter disabled, moving GTA to native before raw passthrough");
    }
    else
    {
        g_m3kMasterEnabled = true;
        M3kWriteMasterIni(L"MasterEnabled", 1);
        M3kWriteMasterIni(L"TemporalJitter", 1);
        M3kRequestSrProfileLive(g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2);
        M3kRequestNrEnabledLive(g_m3kMasterSavedNr);
        g_m3k.ResetHistory();
        Log("M3K-MASTER: ON requested; restoring reconstruction=%s NR=%s jitter=ON",
            M3kSrProfileName(g_m3kMasterSavedProfile <= 5 ? g_m3kMasterSavedProfile : 2),
            g_m3kMasterSavedNr ? "ON" : "OFF");
    }
}

static UINT M3kRequestedNrPasses() { return g_m3kNrPasses; }
'@
$vk = Replace-ExactOnce $vk $stateAnchor $stateNew 'master state/API'

# Read the persistent master state in the existing one-second M3K config poll. While OFF,
# force Mode=0 and SRProfile=0 in memory even if somebody hand-edits stale values.
$modeOld = '        const UINT requested = GetPrivateProfileIntW(L"M3K", L"Mode", 0, path);'
$modeNew = @'
        const bool masterFromIni = GetPrivateProfileIntW(L"M3K", L"MasterEnabled", 1, path) != 0;
        const UINT savedProfileRaw = GetPrivateProfileIntW(L"M3K", L"LastSRProfile", 2, path);
        const UINT savedNrRaw = GetPrivateProfileIntW(L"M3K", L"LastNRMode", 0, path);
        g_m3kMasterSavedProfile = savedProfileRaw <= 5 ? savedProfileRaw : 2;
        g_m3kMasterSavedNr = savedNrRaw == 2;
        if (!g_m3kMasterStateInitialized || masterFromIni != g_m3kMasterEnabled)
        {
            g_m3kMasterEnabled = masterFromIni;
            g_m3kMasterStateInitialized = true;
            Log("M3K-MASTER: persistent state=%s saved reconstruction=%s saved NR=%s",
                g_m3kMasterEnabled ? "ON" : "OFF", M3kSrProfileName(g_m3kMasterSavedProfile),
                g_m3kMasterSavedNr ? "ON" : "OFF");
        }
        const UINT requested = g_m3kMasterEnabled ? GetPrivateProfileIntW(L"M3K", L"Mode", 0, path) : 0;
'@
$vk = Replace-ExactOnce $vk $modeOld $modeNew 'persistent master poll'

$srOld = '        const UINT requestedSrProfile = GetPrivateProfileIntW(L"M3K", L"SRProfile", 2, path);'
$srNew = '        const UINT requestedSrProfile = g_m3kMasterEnabled ? GetPrivateProfileIntW(L"M3K", L"SRProfile", 2, path) : 0;'
$vk = Replace-ExactOnce $vk $srOld $srNew 'master SR profile gate'

# Clicking OFF must stop NR immediately rather than waiting for the next one-second INI poll.
$armOld = '    if (!g_m3kMode || g_cfg.mode != 2 || g_cfg.passthrough || !g.ngx_inited || !g.feature) return;'
$armNew = '    if (!g_m3kMasterEnabled || !g_m3kMode || g_cfg.mode != 2 || g_cfg.passthrough || !g.ngx_inited || !g.feature) return;'
$vk = Replace-ExactOnce $vk $armOld $armNew 'immediate NR master gate'

# Once OFF has reached true native render, leave the frame untouched. This is the steady-state
# no-DLSS path: no NR evaluate, no SR/DLAA evaluate, no Feeder capture/copy-home. The DLAA
# feature may remain allocated for fast re-enable, but it is not evaluated while OFF.
$prepareOld = '        M3kPrepareFrame(); // A0 creates on a separate list; displayed color remains original'
$prepareNew = @'
        M3kPrepareFrame(); // M3K live state + resolution planner
        static bool m3kMasterRawReported = false;
        if (M3kMasterNativePassthroughReady())
        {
            if (!m3kMasterRawReported)
            {
                m3kMasterRawReported = true;
                Log("M3K-MASTER: OFF ACTIVE - native GTA frame passes through untouched; no NR/SR/DLAA evaluate");
            }
            return;
        }
        m3kMasterRawReported = false;
'@
$feed = Replace-ExactOnce $feed $prepareOld $prepareNew 'native raw bypass'

# Replace the old developer-oriented M3K submenu with a compact public panel. ReShade owns
# the outer "DLSS 5 Feed" Add-ons tree node; this inner node is forced open whenever Home
# appears, so it no longer needs to be reopened every time the overlay is toggled.
$uiMarker = '    if (ImGui::CollapsingHeader("GTA IV DLSS"))'
$uiStart = $feed.IndexOf($uiMarker,[StringComparison]::Ordinal)
if ($uiStart -lt 0) { throw 'UX/master could not locate GTA IV DLSS submenu' }
$brace = $feed.IndexOf('{',$uiStart)
if ($brace -lt 0) { throw 'UX/master could not locate submenu opening brace' }
$depth = 0; $uiEnd = -1
for ($i = $brace; $i -lt $feed.Length; $i++) {
    if ($feed[$i] -eq '{') { $depth++ }
    elseif ($feed[$i] -eq '}') {
        $depth--
        if ($depth -eq 0) { $uiEnd = $i + 1; break }
    }
}
if ($uiEnd -lt 0) { throw 'UX/master could not locate submenu closing brace' }

$uiNew = @'
    ImGui::SetNextItemOpen(true, ImGuiCond_Appearing);
    if (ImGui::CollapsingHeader("GTA IV DLSS", ImGuiTreeNodeFlags_DefaultOpen))
    {
        bool masterEnabled = M3kMasterEnabledRequested();
        if (ImGui::Checkbox("DLSS / DLAA processing##M3KMaster", &masterEnabled))
            M3kRequestMasterEnabledLive(masterEnabled);
        ImGui::SameLine();
        if (masterEnabled)
            ImGui::TextColored(ImVec4(0.35f, 1.0f, 0.45f, 1.0f), "ON");
        else if (M3kMasterNativePassthroughReady())
            ImGui::TextColored(ImVec4(0.35f, 1.0f, 0.45f, 1.0f), "OFF - native raw rendering");
        else
            ImGui::TextColored(ImVec4(1.0f, 0.78f, 0.25f, 1.0f), "DISABLING - switching GTA to native...");
        if (!masterEnabled)
            ImGui::TextWrapped("OFF disables Neural Rendering, temporal jitter and every DLSS/DLAA evaluate. GTA first returns to native render size, then the original frame passes through untouched.");

        ImGui::Separator();
        ImGui::TextUnformatted("Reconstruction");
        ImGui::BeginDisabled(!masterEnabled);
        int reconstruction = static_cast<int>(M3kRequestedSrProfile());
        const char *reconstructionItems = "DLAA Native\0Custom Ultra Quality (77%)\0Quality\0Balanced\0Performance\0Ultra Performance\0\0";
        if (ImGui::Combo("Mode##M3KSRProfile", &reconstruction, reconstructionItems))
            M3kRequestSrProfileLive(static_cast<UINT>(reconstruction));
        ImGui::EndDisabled();
        ImGui::Text("Current: %s", M3kSrProfileName(M3kAppliedSrProfile()));
        if (masterEnabled && M3kAppliedSrProfile() != M3kRequestedSrProfile())
            ImGui::TextColored(ImVec4(1.0f, 0.78f, 0.25f, 1.0f), "Applying %s...", M3kSrProfileName(M3kRequestedSrProfile()));

        ImGui::Separator();
        ImGui::TextUnformatted("Neural Rendering");
        bool nrEnabled = M3kNrEnabledRequested();
        ImGui::BeginDisabled(!masterEnabled);
        if (ImGui::Checkbox("Enable Neural Rendering##M3KNrEnabled", &nrEnabled))
            M3kRequestNrEnabledLive(nrEnabled);
        ImGui::EndDisabled();
        ImGui::SameLine();
        ImGui::TextDisabled("%s", nrEnabled && masterEnabled ? "DLSS 5 NR before reconstruction" : "Off");

        if (ImGui::CollapsingHeader("Advanced##M3KAdvanced"))
        {
            ImGui::BeginDisabled(!masterEnabled || !nrEnabled);
            const UINT requested = M3kRequestedNrPasses();
            ImGui::TextUnformatted("Neural Rendering passes");
            ImGui::TextWrapped("1 pass is the tested default. Higher counts are experimental and cost more GPU time.");
            for (UINT p = 1; p <= 5; ++p)
            {
                if (p > 1) ImGui::SameLine();
                char label[24] = {};
                _snprintf_s(label, sizeof(label), _TRUNCATE, "%u##M3KPass", p);
                if (ImGui::RadioButton(label, requested == p))
                    M3kRequestNrPassesLive(p);
            }
            const UINT active = M3kActiveNrPasses();
            const UINT created = M3kCreatedNrPasses();
            ImGui::Text("Active: %u    Warmed: %u / 5", active, created);
            if (created < requested)
                ImGui::TextColored(ImVec4(1.0f, 0.78f, 0.25f, 1.0f), "Warming pass %u...", created + 1);
            ImGui::EndDisabled();
        }

        if (ImGui::CollapsingHeader("Diagnostics##M3KDiagnostics"))
        {
            const UINT desiredW = M3kDesiredRenderWidth();
            const UINT desiredH = M3kDesiredRenderHeight();
            const UINT sourceW = M3kCurrentSourceWidth();
            const UINT sourceH = M3kCurrentSourceHeight();
            if (desiredW && desiredH) ImGui::Text("Requested render: %u x %u", desiredW, desiredH);
            else ImGui::TextUnformatted("Requested render: waiting for output size");
            if (sourceW && sourceH) ImGui::Text("DXVK source: %u x %u", sourceW, sourceH);
            else ImGui::TextUnformatted("DXVK source: waiting for source tap");
            ImGui::Text("Output / presenter: %u x %u", g.width, g.height);
            ImGui::Text("Requested reconstruction: %s", M3kSrProfileName(M3kRequestedSrProfile()));
            ImGui::Text("Applied reconstruction: %s", M3kSrProfileName(M3kAppliedSrProfile()));
        }
        ImGui::Separator();
    }
'@
$feed = $feed.Substring(0,$uiStart) + $uiNew + $feed.Substring($uiEnd)

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))

$verify = $vk + $feed
foreach ($marker in @(
    'M3K-MASTER: OFF ACTIVE',
    'M3kMasterNativePassthroughReady',
    'MasterEnabled',
    'LastSRProfile',
    'DLSS / DLAA processing##M3KMaster',
    'ImGuiCond_Appearing',
    'Advanced##M3KAdvanced',
    'Diagnostics##M3KDiagnostics',
    'no NR/SR/DLAA evaluate')) {
    if ($verify.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) { throw "UX/master verification marker missing: $marker" }
}
Write-Host 'Public ReShade UX + master DLSS bypass stage applied.'
