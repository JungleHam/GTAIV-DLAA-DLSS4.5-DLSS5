[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s23Out = Join-Path $toolRoot 'out-m3k-s23'
$out = Join-Path $toolRoot 'out-m3k-s24'
$s23Generated = Join-Path $workRoot 'm3k-src-s23'
$generated = Join-Path $workRoot 'm3k-src-s24'
$obj = Join-Path $workRoot 'obj-s24'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A2-S2.4 gate 1/4: reproduce S2.3 live 1..5 build ==='
& (Join-Path $toolRoot 'build-s23.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s23Out 'BUILD-VERIFIED.txt'))) { throw 'S2.3 build verification marker missing' }

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s23Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A2-S2.4 gate 2/4: clone generated S2.3 source ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s23Generated -Destination $generated -Recurse

Write-Host '=== A2-S2.4 gate 3/4: add live DLSS reconstruction profiles ==='
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
$dummyFeed = Join-Path $workRoot 's24-overlay-dummy.cpp'
'        ImGui::TextWrapped("First use of a higher count may hitch briefly while its independent NR feature is created. Click 5 once to warm all five, then 1-5 comparisons are immediate without restarting GTA.");' | Set-Content -Encoding UTF8 -LiteralPath $dummyFeed
& (Join-Path $toolRoot 'a2-s24-srprofiles-stage.ps1') -GeneratedRoot $generated -FeederSource $dummyFeed
& (Join-Path $toolRoot 'a2-s24-overlay-stage.ps1') -FeederSource $feedSource

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'static constexpr unsigned MaxPasses = 5;',
    'M3K-LIVE: ACTIVE NR passes',
    'M3K-SR-LIVE: ACTIVE',
    'DLSS reconstruction (live)',
    'DLAA only (presenter)',
    'Ultra Performance')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw "Generated S2.4 source missing marker: $marker" }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A2-S2.4 gate 4/4: compile + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $out 'dlss5-feed.addon64'), (Join-Path $out 'm3k\m3k-nvngx.dll')
@(
    'M3K A2-S2.4 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Permanent ReShade M3K panel: live independent Feature18 NR passes 1..5.',
    'New live reconstruction selector: DLAA presenter baseline, Ultra Quality, Quality, Balanced, Performance, Ultra Performance.',
    'SR profile changes recreate only the DLSS feature while GTA remains running.',
    'SR profiles keep the proven true DXVK source size fixed; unsupported NVIDIA render ranges are rejected without replacing the current feature.',
    'DLAA-only is presenter-space DLAA while S1B source remains low-resolution; it is not native-rendered 1440p DLAA.',
    'Jitter remains 0 in this milestone; proper temporal jitter is still next.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A2-S2.4 BUILD VERIFIED: $out (manual install only)"
