$ErrorActionPreference = 'Stop'

$root = Join-Path $PSScriptRoot 'OptiScaler'
$hooks = Join-Path $root 'OptiScaler\hooks\Vulkan_Hooks.cpp'
$configCpp = Join-Path $root 'OptiScaler\Config.cpp'
$configH = Join-Path $root 'OptiScaler\Config.h'
$ini = Join-Path $root 'OptiScaler.ini'
$incSrc = Join-Path $PSScriptRoot '..\m3b2a\m3b2a-optiscaler.inc'
$incDst = Join-Path $root 'OptiScaler\hooks\m3b2a-optiscaler.inc'

foreach ($p in @($hooks, $configCpp, $configH, $ini, $incSrc)) {
    if (!(Test-Path $p)) { throw "Missing $p. Run BUILD-M3A-OS.bat once first so the pinned OptiScaler tree + M3B-1 patch exist." }
}
Copy-Item $incSrc $incDst -Force

function Patch-File([string]$path, [scriptblock]$work) {
    $script:text = (Get-Content $path -Raw).Replace("`r`n", "`n")
    & $work
    Set-Content -Path $path -Value $script:text -NoNewline -Encoding UTF8
}
function Replace-Exact([string]$old, [string]$new, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if (!$script:text.Contains($old)) { throw "Anchor not found: $name" }
    $script:text = $script:text.Replace($old, $new)
}

if ((Get-Content $hooks -Raw).Contains('// M3B-2A integration marker')) {
    Write-Host 'M3B-2A OptiScaler integration already applied.'
    exit 0
}
if (!(Get-Content $hooks -Raw).Contains('GtaivVulkanOneShotExternalPresent')) {
    throw 'M3B-1A/M3B-1 OptiScaler base patch is not present.'
}

Patch-File $configH {
    Replace-Exact `
'    CustomOptional<bool> GtaivVulkanOneShotExternalPresent { false };' `
'    CustomOptional<bool> GtaivVulkanOneShotExternalPresent { false };
    // M3B-2A: reusable Feeder external-image transport. Default OFF; no DLSS-G.
    CustomOptional<bool> GtaivVulkanContinuousExternalPresent { false };' `
'Config.h field'
}

Patch-File $configCpp {
    Replace-Exact `
'            GtaivVulkanOneShotExternalPresent.set_from_config(readBool("Debug", "GtaivVulkanOneShotExternalPresent"));' `
'            GtaivVulkanOneShotExternalPresent.set_from_config(readBool("Debug", "GtaivVulkanOneShotExternalPresent"));
            GtaivVulkanContinuousExternalPresent.set_from_config(readBool("Debug", "GtaivVulkanContinuousExternalPresent"));' `
'Config.cpp read'

    Replace-Exact `
'        ini.SetValue("Debug", "GtaivVulkanOneShotExternalPresent",
                     GetBoolValue(Instance()->GtaivVulkanOneShotExternalPresent.value_for_config()).c_str());' `
'        ini.SetValue("Debug", "GtaivVulkanOneShotExternalPresent",
                     GetBoolValue(Instance()->GtaivVulkanOneShotExternalPresent.value_for_config()).c_str());
        ini.SetValue("Debug", "GtaivVulkanContinuousExternalPresent",
                     GetBoolValue(Instance()->GtaivVulkanContinuousExternalPresent.value_for_config()).c_str());' `
'Config.cpp save'
}

Patch-File $ini {
    Replace-Exact `
'GtaivVulkanOneShotExternalPresent=false' `
'GtaivVulkanOneShotExternalPresent=false
; GTA IV M3B-2A: continuous reusable external copied-frame transport. NO DLSS-G. Default false.
GtaivVulkanContinuousExternalPresent=false' `
'OptiScaler.ini debug key'
}

Patch-File $hooks {
    # Implementation is separate from the proven one-shot state/functions.
    Replace-Exact `
'static uint64_t _m3b1aLastSerial = 0;

// Those aren''t hooked, just grabbed for use' `
'static uint64_t _m3b1aLastSerial = 0;

// M3B-2A integration marker
#include "m3b2a-optiscaler.inc"

// Those aren''t hooked, just grabbed for use' `
'M3B-2A include'

    # M3B-2A also needs Acquire/GetImages/Submit pointers even when M3A/M3B one-shots are off.
    Replace-Exact `
'    if ((!M3aEnabled() && !M3bEnabled() && !M3b1aEnabled()) || device == VK_NULL_HANDLE) return;' `
'    if ((!M3aEnabled() && !M3bEnabled() && !M3b1aEnabled() && !M3b2aEnabled()) || device == VK_NULL_HANDLE) return;' `
'device function resolve gate'

    Replace-Exact `
'        M3aLogSwapchain(device, pCreateInfo, *pSwapchain);
        M3bCaptureSwapchain(device, pCreateInfo, *pSwapchain);' `
'        M3aLogSwapchain(device, pCreateInfo, *pSwapchain);
        M3bCaptureSwapchain(device, pCreateInfo, *pSwapchain);
        M3b2aCaptureSwapchain(device, pCreateInfo, *pSwapchain);' `
'swapchain capture'

    Replace-Exact `
'    const bool m3b1aEnabled = M3b1aEnabled();' `
'    const bool m3b1aEnabled = M3b1aEnabled();
    const bool m3b2aEnabled = M3b2aEnabled();' `
'present enable local'

    Replace-Exact `
'    const bool m3aQueueFamilyKnown = (m3aEnabled || m3bEnabled || m3b1aEnabled) &&
                                     MenuOverlayVk::TryGetQueueFamily(queue, &m3aQueueFamily);' `
'    const bool m3aQueueFamilyKnown = (m3aEnabled || m3bEnabled || m3b1aEnabled || m3b2aEnabled) &&
                                     MenuOverlayVk::TryGetQueueFamily(queue, &m3aQueueFamily);' `
'queue family gate'

    Replace-Exact `
'    // M3B-1A takes precedence when explicitly enabled; M3B-0 remains unchanged and
    // cannot accidentally insert a duplicate during the external-image experiment.
    const bool m3b1aForwarded = M3b1aTryExternalPresent(queue, localPresentInfo, m3aQueueFamilyKnown,
                                                        m3aQueueFamily, &result);
    const bool m3bForwarded = !m3b1aEnabled && M3bTryDuplicatePresent(
        queue, localPresentInfo, m3aQueueFamilyKnown, m3aQueueFamily, &result);
    if (!m3b1aForwarded && !m3bForwarded)
        result = o_QueuePresentKHR(queue, &localPresentInfo);
    if (m3bNormalPresent && result == VK_SUCCESS && !m3bForwarded && !m3b1aForwarded)
        ++_m3bNormalPresents;' `
'    // M3B-2A has precedence only when explicitly enabled. The known-good one-shot
    // M3B-1A/M3B-1 and duplicate paths remain intact and are suppressed, not rewritten.
    const bool m3b2aForwarded = M3b2aTryContinuousExternalPresent(
        queue, localPresentInfo, m3aQueueFamilyKnown, m3aQueueFamily, &result);
    const bool m3b1aForwarded = !m3b2aEnabled && M3b1aTryExternalPresent(
        queue, localPresentInfo, m3aQueueFamilyKnown, m3aQueueFamily, &result);
    const bool m3bForwarded = !m3b2aEnabled && !m3b1aEnabled && M3bTryDuplicatePresent(
        queue, localPresentInfo, m3aQueueFamilyKnown, m3aQueueFamily, &result);
    if (!m3b2aForwarded && !m3b1aForwarded && !m3bForwarded)
        result = o_QueuePresentKHR(queue, &localPresentInfo);
    if (m3bNormalPresent && result == VK_SUCCESS && !m3b2aForwarded && !m3bForwarded && !m3b1aForwarded)
        ++_m3bNormalPresents;' `
'present precedence'
}

Write-Host 'Applied M3B-2A OptiScaler integration (continuous copied-frame consumer; DLSS-G remains disabled).'
