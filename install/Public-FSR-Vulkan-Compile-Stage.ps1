[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference = 'Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    $count=0; $pos=0
    while (($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal)) -ge 0) {
        $count++; $pos=$i+$Old.Length
    }
    if ($count -ne 1) { throw "FSR compile stage ${Label}: expected one match, found $count" }
    return $Text.Replace($Old,$New)
}

$vkPath=Join-Path $GeneratedRoot 'm3k_vk.h'
if(-not(Test-Path -LiteralPath $vkPath)){throw "Missing generated source: $vkPath"}
if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}

$backendSource=Join-Path $PSScriptRoot 'm3k_fsr_backend.h'
if(-not(Test-Path -LiteralPath $backendSource)){throw "Missing FSR backend header: $backendSource"}
Copy-Item -LiteralPath $backendSource -Destination (Join-Path $GeneratedRoot 'm3k_fsr_backend.h') -Force

$vk=[IO.File]::ReadAllText($vkPath)

$include=@'
#pragma once

// FSR-B0: compile-only backend attachment. Runtime selection/dispatch is added only
// after this exact production Feeder + FidelityFX combination is compile-proven.
#include "m3k_fsr_backend.h"
'@
$vk=Once $vk '#pragma once' $include 'backend include'

$stateOld=@'
#if defined(VK_VERSION_1_0)
static bool g_m3kSrRequested = false;
'@
$stateNew=@'
#if defined(VK_VERSION_1_0)
// FSR-B0 stays inert. This object proves the AMD backend can coexist in the exact
// production translation unit without changing the active DLSS/NR path.
static M3kFsrBackend g_m3kFsrBackend;
static bool g_m3kFsrRuntimeEnabled = false;

static bool g_m3kSrRequested = false;
'@
$vk=Once $vk $stateOld $stateNew 'inert backend state'

foreach($marker in @(
    '#include "m3k_fsr_backend.h"',
    'static M3kFsrBackend g_m3kFsrBackend;',
    'static bool g_m3kFsrRuntimeEnabled = false;'
)){
    if($vk.IndexOf($marker,[StringComparison]::Ordinal) -lt 0){throw "FSR compile marker missing: $marker"}
}

[IO.File]::WriteAllText($vkPath,$vk,[Text.UTF8Encoding]::new($false))
Write-Host "FSR-B0 compile-only backend attached: $vkPath"
