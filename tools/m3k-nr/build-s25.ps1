[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s24Out = Join-Path $toolRoot 'out-m3k-s24'
$out = Join-Path $toolRoot 'out-m3k-s25'
$s24Generated = Join-Path $workRoot 'm3k-src-s24'
$generated = Join-Path $workRoot 'm3k-src-s25'
$obj = Join-Path $workRoot 'obj-s25'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A2-S2.5 gate 1/4: reproduce S2.4 live NR + SR profiles ==='
& (Join-Path $toolRoot 'build-s24.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s24Out 'BUILD-VERIFIED.txt'))) {
    throw 'S2.4 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s24Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A2-S2.5 gate 2/4: clone generated S2.4 source ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s24Generated -Destination $generated -Recurse

Write-Host '=== A2-S2.5 gate 3/4: add true live render-resolution switching ==='
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
& (Join-Path $toolRoot 'a2-s25-dynamicres-stage.ps1') -GeneratedRoot $generated -FeederSource $feedSource

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'M3K-RES-LIVE: profile %s requests TRUE GTA render',
    'M3K-RES-LIVE: TRUE source confirmed',
    'M3K-SR-LIVE: ACTIVE',
    'M3K-LIVE: ACTIVE NR passes',
    'True render target:',
    'DLAA native')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated S2.5 source missing marker: $marker"
    }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A2-S2.5 gate 4/4: compile + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A2-S2.5 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Permanent ReShade M3K panel keeps live independent Feature18 NR passes 1..5.',
    'DLSS selector now requests NVIDIA optimal render resolution for each profile.',
    'The Feeder writes RenderWidth/RenderHeight and posts WM_SIZE to GTA grcWindow; existing A2-S2.1 b-bridge UI virtualization and S1B DXVK then perform the true D3D9 render-size reset while presenter stays native.',
    'DLAA requests a true native-resolution GTA source before restoring DLAA.',
    'Profile switching is a GPU/runtime gate: GTA must react to synthetic WM_SIZE with a D3D9 reset.',
    'Jitter remains 0 in this milestone; proper temporal jitter/history is still next.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A2-S2.5 BUILD VERIFIED: $out (GPU runtime resize gate still required)"
