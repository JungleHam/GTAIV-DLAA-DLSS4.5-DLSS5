[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s26Out = Join-Path $toolRoot 'out-m3k-s26'
$out = Join-Path $toolRoot 'out-m3k-s27'
$s26Generated = Join-Path $workRoot 'm3k-src-s26'
$generated = Join-Path $workRoot 'm3k-src-s27'
$obj = Join-Path $workRoot 'obj-s27'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A2-S2.7 gate 1/4: reproduce S2.6 native NR + UQ hardware-gated baseline ==='
& (Join-Path $toolRoot 'build-s26.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s26Out 'BUILD-VERIFIED.txt'))) {
    throw 'S2.6 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s26Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A2-S2.7 gate 2/4: clone generated S2.6 source ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s26Generated -Destination $generated -Recurse

Write-Host '=== A2-S2.7 gate 3/4: add custom 77% MaxQuality fallback for unavailable official UQ ==='
& (Join-Path $toolRoot 'a2-s27-custom-uq-stage.ps1') -GeneratedRoot $generated

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'Native + NR + DLAA',
    'Custom Ultra Quality (77%)',
    'M3K-UQ-CUSTOM: official UQ query returned 0x0',
    'M3K-UQ-CUSTOM: creating supported MaxQuality DLSS feature',
    'M3K-A2-S2.6: NR18 -> DLAA running',
    'static constexpr unsigned MaxPasses = 5;',
    'M3K-RES-LIVE: TRUE source confirmed')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated S2.7 source missing marker: $marker"
    }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A2-S2.7 gate 4/4: compile + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A2-S2.7 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'S2.6 hardware proof established that official UltraQuality sizing returns 0x0 at 2560x1440 and actual UltraQuality feature creation fails on the tested runtime.',
    'S2.7 preserves the official UltraQuality path whenever NGX supplies valid official dimensions.',
    'When official UQ sizing returns 0x0, profile 1 becomes Custom Ultra Quality (77%): true GTA/DXVK source at 77% linear dimensions, then a supported MaxQuality DLSS feature.',
    'At 2560x1440 output the custom source target remains 1971x1109.',
    'The custom source must also be inside the MaxQuality-supported render range before feature creation is attempted.',
    'Quality/Balanced/Performance/Ultra Performance and Native + NR + DLAA remain unchanged from S2.6.',
    'Existing S2.6 rollback remains active if profile 1 feature creation still fails.',
    'Jitter remains the existing proof path in this milestone; proper temporal jitter/history is still a later quality milestone.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A2-S2.7 BUILD VERIFIED: $out (GPU custom-UQ runtime gate required)"
