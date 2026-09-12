$ErrorActionPreference = 'Stop'

$src = Join-Path $PSScriptRoot 'feeder-src\src\dlss5-feed.cpp'
$incSrc = Join-Path $PSScriptRoot '..\m3b2a\m3b2a-feed.inc'
$incDst = Join-Path $PSScriptRoot 'feeder-src\src\m3b2a-feed.inc'

if (!(Test-Path $src)) { throw "Missing $src. Run BUILD-M2B-PROBE.bat once first so the pinned v0.15.1 tree + M2B/M3B-1 patch exist." }
if (!(Test-Path $incSrc)) { throw "Missing $incSrc" }
Copy-Item $incSrc $incDst -Force

$text = (Get-Content $src -Raw).Replace("`r`n", "`n")
if ($text.Contains('// M3B-2A integration marker')) {
    Write-Host 'M3B-2A Feeder integration already applied.'
    exit 0
}
if (!$text.Contains('dlfg_m3b1_present')) { throw 'M3B-1 base patch is not present in dlss5-feed.cpp.' }

function Replace-Exact([string]$old, [string]$new, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if (!$script:text.Contains($old)) { throw "Anchor not found: $name" }
    $script:text = $script:text.Replace($old, $new)
}

# Parse-only/default-off config key. It is intentionally NOT added to CfgSave's owned-key
# list, so the existing carry-through behavior preserves the user's hand-set line.
Replace-Exact `
'    int   dlfg_m3b1_present; // 1: generate one native DLSS-G frame into that external image and publish it' `
'    int   dlfg_m3b1_present; // 1: generate one native DLSS-G frame into that external image and publish it
    int   dlfg_m3b2a_stream; // M3B-2A: continuous reusable copied-frame transport; NO DLSS-G' `
'Cfg field'

Replace-Exact `
'                     /* dlfg_m3b1a_publish */ 0, /* dlfg_m3b1_present */ 0,
                     /* hdr_bridge */ -1' `
'                     /* dlfg_m3b1a_publish */ 0, /* dlfg_m3b1_present */ 0,
                     /* dlfg_m3b2a_stream */ 0,
                     /* hdr_bridge */ -1' `
'Cfg initializer'

Replace-Exact `
'        else if (_stricmp(key, "dlfg_m3b1_present") == 0) next.dlfg_m3b1_present = iv;' `
'        else if (_stricmp(key, "dlfg_m3b1_present") == 0) next.dlfg_m3b1_present = iv;
        else if (_stricmp(key, "dlfg_m3b2a_stream") == 0) next.dlfg_m3b2a_stream = iv;' `
'Cfg parser'

Replace-Exact `
'    next.dlfg_m3b1_present = next.dlfg_m3b1_present != 0 ? 1 : 0;' `
'    next.dlfg_m3b1_present = next.dlfg_m3b1_present != 0 ? 1 : 0;
    next.dlfg_m3b2a_stream = next.dlfg_m3b2a_stream != 0 ? 1 : 0;' `
'Cfg normalization'

Replace-Exact `
'                         next.dlfg_m3b1a_publish != g_cfg.dlfg_m3b1a_publish ||
                         next.dlfg_m3b1_present != g_cfg.dlfg_m3b1_present;' `
'                         next.dlfg_m3b1a_publish != g_cfg.dlfg_m3b1a_publish ||
                         next.dlfg_m3b1_present != g_cfg.dlfg_m3b1_present ||
                         next.dlfg_m3b2a_stream != g_cfg.dlfg_m3b2a_stream;' `
'Cfg rebuild trigger'

# Keep the continuous transport implementation physically separate from the proven one-shot code.
Replace-Exact `
'// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------' `
'// M3B-2A integration marker
#include "m3b2a-feed.inc"

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------' `
'M3B-2A include'

# Queue-idle + D3D12 drain already happened immediately above this anchor.
Replace-Exact `
'    GuideProbeAbort();
    M2bRelease();
    FeedVkProbeRelease();' `
'    GuideProbeAbort();
    M2bRelease();
    M3b2aRelease();
    FeedVkProbeRelease();' `
'resource release'

# Allocate the ring only for the default-off M3B-2A experiment.
Replace-Exact `
'    // buffer_home: a shared LINEAR buffer for the output hop.' `
'    if (!M3b2aCreateResources(w, h))
    {
        ReleaseFrameResources();
        return false;
    }

    // buffer_home: a shared LINEAR buffer for the output hop.' `
'BuildResourcesVk ring creation'

# One-time Vulkan initialization of all ring images: UNDEFINED -> GENERAL, then release to EXTERNAL/D3D12.
Replace-Exact `
'            if (g.m3b1a_vk_img != VK_NULL_HANDLE && !g.m3b1a_vk_released)' `
'            M3b2aPrepareVulkanRelease(cb, gfx_family);

            if (g.m3b1a_vk_img != VK_NULL_HANDLE && !g.m3b1a_vk_released)' `
'Vulkan external release'

Replace-Exact `
'            bool m3b1a_copy_this_frame = false;
            bool m3b1_signal_this_frame = false;' `
'            bool m3b1a_copy_this_frame = false;
            bool m3b1_signal_this_frame = false;
            int m3b2a_slot_this_frame = -1;' `
'per-frame ring slot'

# Copy the ordinary completed post-NR output into a free reusable slot. This is M3B-2A only;
# native feature 11 stays completely out of this milestone.
Replace-Exact `
'                    if (g_cfg.dlfg_m3b1a_publish != 0 && !m3b1_active &&' `
'                    if (M3b2aEnabled() && !M3b2aHasConflictingExperiment() && NVSDK_NGX_SUCCEED(re))
                        m3b2a_slot_this_frame = M3b2aRecordCopy(n);

                    if (g_cfg.dlfg_m3b1a_publish != 0 && !m3b1_active &&' `
'producer ring copy'

# fence12_out is already the proven producer-ready D3D12->Vulkan timeline. Publish only if
# that signal was queued successfully.
Replace-Exact `
'                CK("queue Signal(fence12_out)");
                if (m3b1_signal_this_frame)' `
'                CK("queue Signal(fence12_out)");
                if (m3b2a_slot_this_frame >= 0)
                {
                    if (SUCCEEDED(signal_hr))
                        M3b2aPublish(static_cast<uint32_t>(m3b2a_slot_this_frame), n, n);
                    else
                        Log("[feed] M3B-2A: fence12_out signal failed 0x%08X; slot %d publication withheld",
                            signal_hr, m3b2a_slot_this_frame);
                }
                if (m3b1_signal_this_frame)' `
'producer publication'

Set-Content -Path $src -Value $text -NoNewline -Encoding UTF8
Write-Host 'Applied M3B-2A Feeder integration (3-slot copied-frame transport; DLSS-G remains disabled).'
