# A3-S1.1 build-only transform: keep the proven A3-S1 GTA raster jitter unchanged,
# but invert only the jitter offsets handed to DLSS SR. This is a one-variable A/B
# test for projection-vs-NGX jitter sign convention.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GeneratedRoot)
$ErrorActionPreference = 'Stop'

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0; $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $Old.Length }
    if ($count -ne 1) { throw "A3-S1.1 ${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

$vkPath = Join-Path $GeneratedRoot 'm3k_vk.h'
if (-not (Test-Path -LiteralPath $vkPath)) { throw "Missing generated m3k_vk.h under $GeneratedRoot" }
$vk = [IO.File]::ReadAllText($vkPath)

$vk = Replace-ExactOnce $vk `
    '        sr.InJitterOffsetX = bridgeJitterActive ? bridgeJitter.jitterX : 0.0f;' `
    '        sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;' `
    'DLSS X sign inversion'
$vk = Replace-ExactOnce $vk `
    '        sr.InJitterOffsetY = bridgeJitterActive ? bridgeJitter.jitterY : 0.0f;' `
    '        sr.InJitterOffsetY = bridgeJitterActive ? -bridgeJitter.jitterY : 0.0f;' `
    'DLSS Y sign inversion'

$vk = $vk.Replace(
    'M3K-A3-S1: SR raster/DLSS jitter active=%d bridgeFrame=%ld epoch=%ld render=%ux%u px=(%+.4f,%+.4f) reset=%d',
    'M3K-A3-S1.1: raster jitter unchanged; DLSS sign=-1 active=%d bridgeFrame=%ld epoch=%ld render=%ux%u dlssPx=(%+.4f,%+.4f) reset=%d')

foreach ($marker in @(
    'sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;',
    'sr.InJitterOffsetY = bridgeJitterActive ? -bridgeJitter.jitterY : 0.0f;',
    'M3K-A3-S1.1: raster jitter unchanged; DLSS sign=-1')) {
    if ($vk.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "A3-S1.1 generated source missing marker: $marker"
    }
}

[IO.File]::WriteAllText($vkPath, $vk, [Text.UTF8Encoding]::new($false))
Write-Host "A3-S1.1 DLSS-only jitter sign inversion applied: $vkPath"
