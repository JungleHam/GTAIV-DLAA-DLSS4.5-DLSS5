$ErrorActionPreference = 'Stop'

$m2b = Join-Path $PSScriptRoot '..\m2b'
$src = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
$ring = Join-Path $m2b 'feeder-src\src\m3b2a-feed.inc'
$incSrc = Join-Path $PSScriptRoot 'm3b2b-feed.inc'
$incDst = Join-Path $m2b 'feeder-src\src\m3b2b-feed.inc'

if (!(Test-Path $src)) { throw "Missing $src. Run BUILD-M3B2A.bat first." }
if (!(Test-Path $ring)) { throw "Missing $ring. M3B-2A must be applied before M3B-2B." }
if (!(Test-Path $incSrc)) { throw "Missing $incSrc" }
Copy-Item $incSrc $incDst -Force

$text = (Get-Content $src -Raw).Replace("`r`n", "`n")
$ringText = (Get-Content $ring -Raw).Replace("`r`n", "`n")

if ($text.Contains('// M3B-2B integration marker')) {
    Write-Host 'M3B-2B Feeder integration already applied.'
    exit 0
}
if (!$text.Contains('// M3B-2A integration marker')) { throw 'M3B-2A base integration is not present.' }
if (!$text.Contains('static bool M3b1MaybeRecord(')) { throw 'M3B-1 native feature-11 bootstrap is not present.' }

function Replace-Exact([string]$old, [string]$new, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if (!$script:text.Contains($old)) { throw "Anchor not found in dlss5-feed.cpp: $name" }
    $script:text = $script:text.Replace($old, $new)
}
function Replace-Ring([string]$old, [string]$new, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if (!$script:ringText.Contains($old)) { throw "Anchor not found in m3b2a-feed.inc: $name" }
    $script:ringText = $script:ringText.Replace($old, $new)
}

# Parse-only/default-off switch. Like M3B-2A, leave it out of CfgSave's owned keys so
# a hand-set experimental line survives the Feeder's normal config rewrite.
Replace-Exact `
'    int   dlfg_m3b2a_stream; // M3B-2A: continuous reusable copied-frame transport; NO DLSS-G' `
'    int   dlfg_m3b2a_stream; // M3B-2A: continuous reusable copied-frame transport; NO DLSS-G
    int   dlfg_m3b2b_native; // M3B-2B: continuous native feature-11 producer through M3B-2A transport' `
'Cfg field'

Replace-Exact `
'                     /* dlfg_m3b2a_stream */ 0,
                     /* hdr_bridge */ -1' `
'                     /* dlfg_m3b2a_stream */ 0,
                     /* dlfg_m3b2b_native */ 0,
                     /* hdr_bridge */ -1' `
'Cfg initializer'

Replace-Exact `
'        else if (_stricmp(key, "dlfg_m3b2a_stream") == 0) next.dlfg_m3b2a_stream = iv;' `
'        else if (_stricmp(key, "dlfg_m3b2a_stream") == 0) next.dlfg_m3b2a_stream = iv;
        else if (_stricmp(key, "dlfg_m3b2b_native") == 0) next.dlfg_m3b2b_native = iv;' `
'Cfg parser'

Replace-Exact `
'    next.dlfg_m3b2a_stream = next.dlfg_m3b2a_stream != 0 ? 1 : 0;' `
'    next.dlfg_m3b2a_stream = next.dlfg_m3b2a_stream != 0 ? 1 : 0;
    next.dlfg_m3b2b_native = next.dlfg_m3b2b_native != 0 ? 1 : 0;' `
'Cfg normalization'

Replace-Exact `
'                         next.dlfg_m3b1_present != g_cfg.dlfg_m3b1_present ||
                         next.dlfg_m3b2a_stream != g_cfg.dlfg_m3b2a_stream;' `
'                         next.dlfg_m3b1_present != g_cfg.dlfg_m3b1_present ||
                         next.dlfg_m3b2a_stream != g_cfg.dlfg_m3b2a_stream ||
                         next.dlfg_m3b2b_native != g_cfg.dlfg_m3b2b_native;' `
'Cfg rebuild trigger'

# M3B-2B uses the exact same three-slot ring and consumer-return timeline that passed
# M3B-2A. Only the producer bytes change.
Replace-Ring `
'static bool M3b2aEnabled()
{
    return g_cfg.dlfg_m3b2a_stream != 0;
}' `
'static bool M3b2aEnabled()
{
    return g_cfg.dlfg_m3b2a_stream != 0 || g_cfg.dlfg_m3b2b_native != 0;
}' `
'M3B-2A transport enable'

# Include after M3B-2A so the native producer can reuse its ring helpers/state.
Replace-Exact `
'#include "m3b2a-feed.inc"

// ---------------------------------------------------------------------------
// Resources' `
'#include "m3b2a-feed.inc"
// M3B-2B integration marker
#include "m3b2b-feed.inc"

// ---------------------------------------------------------------------------
// Resources' `
'M3B-2B include'

# The proven M3B-1 feature writes to this shareable UAV. M3B-2B keeps that exact output
# resource as a private D3D12 staging surface before copying into a free ring slot.
Replace-Exact `
'    if (g_cfg.dlfg_m3b1a_publish != 0 || g_cfg.dlfg_m3b1_present != 0)' `
'    if (g_cfg.dlfg_m3b1a_publish != 0 || g_cfg.dlfg_m3b1_present != 0 || g_cfg.dlfg_m3b2b_native != 0)' `
'M3B-1 shared output allocation gate'

Replace-Exact `
'        else if (!MakeM3b1aSharedTexVk(w, h, g_cfg.dlfg_m3b1_present != 0))' `
'        else if (!MakeM3b1aSharedTexVk(w, h, g_cfg.dlfg_m3b1_present != 0 || g_cfg.dlfg_m3b2b_native != 0))' `
'M3B-1 shared output UAV flag'

# Let the proven M3B-1 routine create + validate feature 11 even though the old one-shot
# presentation switch stays off. kM2bPassed is the hand-off point to M3B-2B.
Replace-Exact `
'    if (g_cfg.dlfg_m3b1_present == 0 || g.dlfg_state == kM2bPassed ||
        g.dlfg_state == kM2bFailed || g.dlfg_state == kM2bReadbackPending)' `
'    if ((g_cfg.dlfg_m3b1_present == 0 && g_cfg.dlfg_m3b2b_native == 0) ||
        g.dlfg_state == kM2bPassed || g.dlfg_state == kM2bFailed ||
        g.dlfg_state == kM2bReadbackPending)' `
'M3B-1 bootstrap gate'

# In the per-frame D3D12 block, M3B-2B claims the native M3B-1 path for bootstrap.
Replace-Exact `
'                    const bool m3b1_active = g_cfg.dlfg_m3b1_present != 0;' `
'                    const bool m3b2b_active = g_cfg.dlfg_m3b2b_native != 0;
                    const bool m3b1_active = g_cfg.dlfg_m3b1_present != 0 || m3b2b_active;' `
'M3B-2B active flag'

# One-shot publication fence bookkeeping belongs only to the explicit M3B-1 switch.
Replace-Exact `
'                    m3b1_signal_this_frame = m3b1_active && g.dlfg_state == kM2bReadbackPending &&' `
'                    m3b1_signal_this_frame = g_cfg.dlfg_m3b1_present != 0 && g.dlfg_state == kM2bReadbackPending &&' `
'M3B-1 one-shot signal gate'

# After M3B-1 bootstrap reaches kM2bPassed, evaluate feature 11 continuously. This call
# may assign m3b2a_slot_this_frame to a generated frame. An SEH fault aborts the list.
Replace-Exact `
'                    if (!dlfg_ok)
                    {
                        AbortCommands();' `
'                    bool m3b2b_ok = true;
                    if (m3b2b_active && dlfg_ok && NVSDK_NGX_SUCCEED(re) &&
                        g.dlfg_state == kM2bPassed)
                        m3b2b_ok = M3b2bRecordNative(n, reset != 0, &m3b2a_slot_this_frame);
                    if (!dlfg_ok || !m3b2b_ok)
                    {
                        AbortCommands();' `
'M3B-2B continuous evaluation'

Replace-Exact `
'                            m3b1_active ? "M3B-1" : m2c_active ? "M2C" : "M2B");' `
'                            m3b2b_active ? "M3B-2B" : m3b1_active ? "M3B-1" : m2c_active ? "M2C" : "M2B");' `
'fault log owner'

# Disable the ordinary post-NR copy producer when native output is active. The consumer
# and publication ABI stay exactly M3B-2A.
Replace-Exact `
'                    if (M3b2aEnabled() && !M3b2aHasConflictingExperiment() && NVSDK_NGX_SUCCEED(re))
                        m3b2a_slot_this_frame = M3b2aRecordCopy(n);' `
'                    if (M3b2aEnabled() && !m3b2b_active && !M3b2aHasConflictingExperiment() && NVSDK_NGX_SUCCEED(re))
                        m3b2a_slot_this_frame = M3b2aRecordCopy(n);' `
'disable copied producer under M3B-2B'

# Preserve M3B-2A publication exactly, but capture the serial for native provenance logs.
Replace-Exact `
'                    if (SUCCEEDED(signal_hr))
                        M3b2aPublish(static_cast<uint32_t>(m3b2a_slot_this_frame), n, n);' `
'                    if (SUCCEEDED(signal_hr))
                    {
                        const uint64_t m3b2_serial = M3b2aPublish(static_cast<uint32_t>(m3b2a_slot_this_frame), n, n);
                        M3b2bOnPublished(m3b2_serial, n, static_cast<uint32_t>(m3b2a_slot_this_frame));
                    }' `
'native publication provenance'

# Clear only M3B-2B counters on a resource rebuild. Existing M3B-1/M3B-2A teardown
# remains the owner of the actual feature/ring resources.
Replace-Exact `
'    GuideProbeAbort();
    M2bRelease();
    M3b2aRelease();' `
'    GuideProbeAbort();
    M3b2bReleaseState();
    M2bRelease();
    M3b2aRelease();' `
'M3B-2B teardown state'

Set-Content -Path $ring -Value $ringText -NoNewline -Encoding UTF8
Set-Content -Path $src -Value $text -NoNewline -Encoding UTF8
Write-Host 'Applied M3B-2B Feeder integration (continuous native NVIDIA feature-11 producer over proven M3B-2A transport).'
