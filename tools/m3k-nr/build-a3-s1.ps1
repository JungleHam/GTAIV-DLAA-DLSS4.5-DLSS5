[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s27Out = Join-Path $toolRoot 'out-m3k-s27'
$out = Join-Path $toolRoot 'out-m3k-a3-s1'
$s27Generated = Join-Path $workRoot 'm3k-src-s27'
$generated = Join-Path $workRoot 'm3k-src-a3-s1'
$obj = Join-Path $workRoot 'obj-a3-s1'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A3-S1 gate 1/4: reproduce frozen S2.7 Custom UQ 77% Feeder baseline ==='
& (Join-Path $toolRoot 'build-s27.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s27Out 'BUILD-VERIFIED.txt'))) {
    throw 'S2.7 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s27Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A3-S1 gate 2/4: clone exact generated S2.7 source ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s27Generated -Destination $generated -Recurse

Write-Host '=== A3-S1 gate 3/4: add bridge-synchronized raster/DLSS temporal jitter ==='
& (Join-Path $toolRoot 'a3-s1-jitter-stage.ps1') -GeneratedRoot $generated

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'Custom Ultra Quality (77%)',
    'M3K-UQ-CUSTOM: creating supported MaxQuality DLSS feature',
    'M3K-A3-S1: bridge jitter handoff opened',
    'M3K-A3-S1: SR raster/DLSS jitter active=',
    'Local\\M3K_GTAIV_Jitter_v1',
    'bridgeJitterTransition',
    'static constexpr unsigned MaxPasses = 5;')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated A3-S1 source missing marker: $marker"
    }
}
if ($vkText.IndexOf('sr.InJitterOffsetX = 0.0f;', [StringComparison]::Ordinal) -ge 0 -or
    $vkText.IndexOf('sr.InJitterOffsetY = 0.0f;', [StringComparison]::Ordinal) -ge 0) {
    throw 'Generated A3-S1 source still contains the S2.7 forced-zero SR jitter assignment'
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A3-S1 gate 4/4: compile + CPU contract tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A3-S1 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Base=frozen S2.7 Custom UQ 77%.',
    'A3-S1 removes only the S2.7 forced-zero SR jitter assignment.',
    'The 32-bit bridge owns raster jitter and publishes the exact render-pixel sample immediately before Present.',
    'The 64-bit Feeder reads Local\\M3K_GTAIV_Jitter_v1 and hands that exact sample to DLSS SR.',
    'History resets on jitter active/inactive transitions or bridge jitter epoch changes; steady frames keep reset=0.',
    'If the mapping is absent, inactive, or dimensions do not match the active SR render size, Feeder safely uses jitter 0.',
    'Feature18 NR, true-source capture, guide scaling, SR profiles, UQ77 and rollback logic are unchanged from S2.7.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A3-S1 BUILD VERIFIED: $out (paired A3-S1 bridge runtime gate required)"
