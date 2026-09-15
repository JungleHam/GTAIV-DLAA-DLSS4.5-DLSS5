# A3-S1.2: deterministic visual A/B capture harness on top of A3-S1.1.
# Adds a separate ReShade in-game panel with four exact states and four Capture-3 buttons.
# Each capture request applies the state, closes the overlay, settles, then asks ReShade
# to save three consecutive post-effects/presented frames. No renderer/jitter math changes.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FeederSource)
$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "A3-S1.2 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }
$feed = [IO.File]::ReadAllText($FeederSource)

$presentOld = @'
static void OnReShadePresent(reshade::api::effect_runtime * /*rt*/)
{
    FeedPollConfig();
}
'@

$captureBlock = @'
// ---------------------------------------------------------------------------
// M3K A3-S1.2 controlled visual capture lab.
// Four states: NR OFF/ON x Custom UQ77/Ultra Performance. The raster jitter bridge
// and A3-S1.1 DLSS sign=-1 path are untouched. ReShade owns screenshot capture so
// the saved image is the actual final backbuffer rather than an intermediate texture.
// ---------------------------------------------------------------------------
enum M3kCaptureState : int {
    M3K_CAP_NR_OFF_UQ = 0,
    M3K_CAP_NR_ON_UQ  = 1,
    M3K_CAP_NR_OFF_UP = 2,
    M3K_CAP_NR_ON_UP  = 3,
};

struct M3kCaptureJob {
    bool active = false;
    int state = -1;
    int captured = 0;
    unsigned setSerial = 0;
    ULONGLONG readyAfter = 0;
};

static M3kCaptureJob g_m3kCaptureJob;
static unsigned g_m3kCaptureSerial = 0;
static int g_m3kCaptureLastRequested = -1;

static const char *M3kCaptureTag(int state)
{
    switch (state) {
        case M3K_CAP_NR_OFF_UQ: return "NR_OFF_UQ";
        case M3K_CAP_NR_ON_UQ:  return "NR_ON_UQ";
        case M3K_CAP_NR_OFF_UP: return "NR_OFF_UP";
        case M3K_CAP_NR_ON_UP:  return "NR_ON_UP";
        default: return "UNKNOWN";
    }
}

static const char *M3kCaptureLabel(int state)
{
    switch (state) {
        case M3K_CAP_NR_OFF_UQ: return "NR OFF + Custom UQ 77%";
        case M3K_CAP_NR_ON_UQ:  return "NR ON + Custom UQ 77%";
        case M3K_CAP_NR_OFF_UP: return "NR OFF + Ultra Performance";
        case M3K_CAP_NR_ON_UP:  return "NR ON + Ultra Performance";
        default: return "Unknown";
    }
}

static bool M3kCaptureNrOn(int state)
{
    return state == M3K_CAP_NR_ON_UQ || state == M3K_CAP_NR_ON_UP;
}

static UINT M3kCaptureProfile(int state)
{
    return (state == M3K_CAP_NR_OFF_UP || state == M3K_CAP_NR_ON_UP) ? 5u : 1u;
}

static bool M3kCaptureIniPath(wchar_t *path, size_t count)
{
    if (!path || count == 0) return false;
    DWORD n = GetModuleFileNameW(g_self, path, static_cast<DWORD>(count));
    if (!n || n >= count) return false;
    wchar_t *slash = wcsrchr(path, L'\\');
    if (!slash) return false;
    *(slash + 1) = 0;
    return wcscat_s(path, count, L"m3k-nr.ini") == 0;
}

static void M3kCaptureWriteIniInt(const wchar_t *key, int value)
{
    wchar_t path[MAX_PATH] = {};
    if (!M3kCaptureIniPath(path, MAX_PATH)) return;
    wchar_t text[24] = {};
    _snwprintf_s(text, _TRUNCATE, L"%d", value);
    WritePrivateProfileStringW(L"M3K", key, text, path);
}

static int M3kCaptureReadIniInt(const wchar_t *key, int fallback)
{
    wchar_t path[MAX_PATH] = {};
    if (!M3kCaptureIniPath(path, MAX_PATH)) return fallback;
    return static_cast<int>(GetPrivateProfileIntW(L"M3K", key, fallback, path));
}

static void M3kCaptureApplyState(int state)
{
    if (state < M3K_CAP_NR_OFF_UQ || state > M3K_CAP_NR_ON_UP) return;
    const bool nr = M3kCaptureNrOn(state);
    const UINT profile = M3kCaptureProfile(state);

    M3kCaptureWriteIniInt(L"Mode", nr ? 2 : 0);
    M3kCaptureWriteIniInt(L"NRPasses", 1);
    M3kCaptureWriteIniInt(L"TemporalJitter", 1);
    M3kCaptureWriteIniInt(L"SRProfile", static_cast<int>(profile));
    M3kRequestSrProfileLive(profile);
    g_m3kCaptureLastRequested = state;
    Log("M3K-A3-S1.2-CAP: requested state=%s mode=%d NRPasses=1 SRProfile=%u TemporalJitter=1",
        M3kCaptureTag(state), nr ? 2 : 0, profile);
}

static void M3kCaptureArm(reshade::api::effect_runtime *rt, int state)
{
    if (!rt || g_m3kCaptureJob.active) return;
    M3kCaptureApplyState(state);
    g_m3kCaptureJob.active = true;
    g_m3kCaptureJob.state = state;
    g_m3kCaptureJob.captured = 0;
    g_m3kCaptureJob.setSerial = ++g_m3kCaptureSerial;
    // Wall-clock settle avoids refresh-rate dependence. The profile must also report
    // applied, NR must be ready when requested, and bridge jitter must be live before F1.
    g_m3kCaptureJob.readyAfter = GetTickCount64() + 3500;
    rt->open_overlay(false, reshade::api::input_source::none);
    Log("M3K-A3-S1.2-CAP: armed set=%u state=%s; overlay closed; settle>=3500ms",
        g_m3kCaptureJob.setSerial, M3kCaptureTag(state));
}

static bool M3kCaptureReadyForFrame()
{
    if (!g_m3kCaptureJob.active || GetTickCount64() < g_m3kCaptureJob.readyAfter)
        return false;
    const UINT profile = M3kCaptureProfile(g_m3kCaptureJob.state);
    if (M3kAppliedSrProfile() != profile)
        return false;
    if (M3kCaptureNrOn(g_m3kCaptureJob.state) && !g_m3k.Ready())
        return false;
    M3kBridgeJitterSnapshot snap;
    if (!M3kReadBridgeJitter(&snap) || !snap.valid || !snap.active)
        return false;
    return true;
}

static void M3kCaptureOnPresent(reshade::api::effect_runtime *rt)
{
    if (!rt || !M3kCaptureReadyForFrame()) return;

    const int frameNo = g_m3kCaptureJob.captured + 1;
    char postfix[96] = {};
    _snprintf_s(postfix, sizeof(postfix), _TRUNCATE, "M3K_%s_SET%02u_F%d",
        M3kCaptureTag(g_m3kCaptureJob.state), g_m3kCaptureJob.setSerial, frameNo);

    M3kBridgeJitterSnapshot snap;
    const bool haveJitter = M3kReadBridgeJitter(&snap) && snap.valid && snap.active;
    rt->save_screenshot(postfix);

    Log("M3K-A3-S1.2-CAP: SAVED set=%u state=%s F%d profile=%u nr=%d bridgeFrame=%ld epoch=%ld render=%ux%u rasterPx=(%+.4f,%+.4f) dlssPx=(%+.4f,%+.4f)",
        g_m3kCaptureJob.setSerial, M3kCaptureTag(g_m3kCaptureJob.state), frameNo,
        M3kCaptureProfile(g_m3kCaptureJob.state), M3kCaptureNrOn(g_m3kCaptureJob.state) ? 1 : 0,
        haveJitter ? snap.frame : -1, haveJitter ? snap.epoch : -1,
        haveJitter ? snap.renderWidth : 0, haveJitter ? snap.renderHeight : 0,
        haveJitter ? snap.jitterX : 0.0f, haveJitter ? snap.jitterY : 0.0f,
        haveJitter ? -snap.jitterX : 0.0f, haveJitter ? -snap.jitterY : 0.0f);

    ++g_m3kCaptureJob.captured;
    if (g_m3kCaptureJob.captured >= 3) {
        Log("M3K-A3-S1.2-CAP: COMPLETE set=%u state=%s three consecutive presented frames requested",
            g_m3kCaptureJob.setSerial, M3kCaptureTag(g_m3kCaptureJob.state));
        g_m3kCaptureJob.active = false;
        rt->open_overlay(true, reshade::api::input_source::none);
    }
}

static void M3kCaptureOverlay(reshade::api::effect_runtime *rt)
{
    ImGui::TextUnformatted("M3K A3-S1.2 Controlled Capture Lab");
    ImGui::TextWrapped("Keep the camera completely still. Each Capture 3 button applies its state, closes this overlay, settles for at least 3.5 seconds, then saves exactly three consecutive post-effects frames and reopens the overlay.");
    ImGui::Separator();

    for (int state = M3K_CAP_NR_OFF_UQ; state <= M3K_CAP_NR_ON_UP; ++state) {
        ImGui::PushID(state);
        if (ImGui::Button("Activate", ImVec2(88.0f, 0.0f)))
            M3kCaptureApplyState(state);
        ImGui::SameLine();
        if (g_m3kCaptureJob.active) ImGui::BeginDisabled();
        if (ImGui::Button("Capture 3", ImVec2(100.0f, 0.0f)))
            M3kCaptureArm(rt, state);
        if (g_m3kCaptureJob.active) ImGui::EndDisabled();
        ImGui::SameLine();
        ImGui::TextUnformatted(M3kCaptureLabel(state));
        ImGui::PopID();
    }

    ImGui::Separator();
    if (g_m3kCaptureJob.active) {
        const ULONGLONG now = GetTickCount64();
        const ULONGLONG left = now < g_m3kCaptureJob.readyAfter ? g_m3kCaptureJob.readyAfter - now : 0;
        ImGui::Text("ARMED: %s", M3kCaptureLabel(g_m3kCaptureJob.state));
        ImGui::Text("Set %u | settle remaining: %llu ms | captured: %d / 3",
            g_m3kCaptureJob.setSerial, static_cast<unsigned long long>(left), g_m3kCaptureJob.captured);
    } else {
        ImGui::Text("Last requested: %s", g_m3kCaptureLastRequested >= 0 ? M3kCaptureLabel(g_m3kCaptureLastRequested) : "none");
    }
    ImGui::Text("INI: Mode=%d NRPasses=%d SRProfile=%d TemporalJitter=%d | Applied SR=%s",
        M3kCaptureReadIniInt(L"Mode", -1), M3kCaptureReadIniInt(L"NRPasses", -1),
        M3kCaptureReadIniInt(L"SRProfile", -1), M3kCaptureReadIniInt(L"TemporalJitter", -1),
        M3kSrProfileName(M3kAppliedSrProfile()));
}

static void OnReShadePresent(reshade::api::effect_runtime *rt)
{
    FeedPollConfig();
    M3kCaptureOnPresent(rt);
}
'@

$feed = Replace-ExactOnce $feed $presentOld $captureBlock 'present capture scheduler'

$registerOld = '        reshade::register_overlay(nullptr, DrawOverlay);'
$registerNew = @'
        reshade::register_overlay(nullptr, DrawOverlay);
        reshade::register_overlay("M3K Capture Lab", M3kCaptureOverlay);
'@
$feed = Replace-ExactOnce $feed $registerOld $registerNew 'capture overlay registration'

$unregisterOld = '        reshade::unregister_overlay(nullptr, DrawOverlay);'
$unregisterNew = @'
        reshade::unregister_overlay("M3K Capture Lab", M3kCaptureOverlay);
        reshade::unregister_overlay(nullptr, DrawOverlay);
'@
$feed = Replace-ExactOnce $feed $unregisterOld $unregisterNew 'capture overlay unregister'

foreach ($marker in @(
    'M3K A3-S1.2 Controlled Capture Lab',
    'M3K-A3-S1.2-CAP: SAVED',
    'M3K_CAP_NR_OFF_UQ',
    'M3K_CAP_NR_ON_UQ',
    'M3K_CAP_NR_OFF_UP',
    'M3K_CAP_NR_ON_UP',
    'save_screenshot(postfix)',
    'reshade::register_overlay("M3K Capture Lab", M3kCaptureOverlay)')) {
    if ($feed.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A3-S1.2 feeder source missing marker: $marker"
    }
}

[IO.File]::WriteAllText($FeederSource, $feed, [Text.UTF8Encoding]::new($false))
Write-Host "A3-S1.2 deterministic capture lab stage applied: $FeederSource"
