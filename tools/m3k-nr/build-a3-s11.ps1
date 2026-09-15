[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s1Out = Join-Path $toolRoot 'out-m3k-a3-s1'
$out = Join-Path $toolRoot 'out-m3k-a3-s11'
$s1Generated = Join-Path $workRoot 'm3k-src-a3-s1'
$generated = Join-Path $workRoot 'm3k-src-a3-s11'
$obj = Join-Path $workRoot 'obj-a3-s11'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A3-S1.1 gate 1/4: reproduce exact A3-S1 bridge-synchronized jitter Feeder ==='
& (Join-Path $toolRoot 'build-a3-s1.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s1Out 'BUILD-VERIFIED.txt'))) {
    throw 'A3-S1 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s1Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A3-S1.1 gate 2/4: clone exact generated A3-S1 source ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s1Generated -Destination $generated -Recurse

Write-Host '=== A3-S1.1 gate 3/4: invert DLSS jitter sign only; raster jitter unchanged ==='
& (Join-Path $toolRoot 'a3-s11-jitter-sign-stage.ps1') -GeneratedRoot $generated

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'Custom Ultra Quality (77%)',
    'M3K-A3-S1: bridge jitter handoff opened',
    'M3K-A3-S1.1: raster jitter unchanged; DLSS sign=-1',
    'sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;',
    'sr.InJitterOffsetY = bridgeJitterActive ? -bridgeJitter.jitterY : 0.0f;',
    'static constexpr unsigned MaxPasses = 5;')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated A3-S1.1 source missing marker: $marker"
    }
}
if ($vkText.IndexOf('sr.InJitterOffsetX = bridgeJitterActive ? bridgeJitter.jitterX : 0.0f;', [StringComparison]::Ordinal) -ge 0 -or
    $vkText.IndexOf('sr.InJitterOffsetY = bridgeJitterActive ? bridgeJitter.jitterY : 0.0f;', [StringComparison]::Ordinal) -ge 0) {
    throw 'Generated A3-S1.1 source still contains the A3-S1 same-sign DLSS jitter assignment'
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A3-S1.1 gate 4/4: compile + CPU contract tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A3-S1.1 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Base=A3-S1 paired bridge-synchronized real raster jitter.',
    'ONLY experimental change: DLSS receives the negative of the raster jitter published by the bridge.',
    'The 32-bit bridge binary and its raster projection shift are unchanged from A3-S1.',
    'History/reset policy, Feature18 NR, true-source capture, guide scaling, SR profiles, UQ77 and rollback remain unchanged.',
    'Primary runtime A/B: Ultra Performance should strongly amplify whether sign=-1 improves or worsens stationary image stability.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A3-S1.1 BUILD VERIFIED: $out (reuse exact A3-S1 bridge binary)"
