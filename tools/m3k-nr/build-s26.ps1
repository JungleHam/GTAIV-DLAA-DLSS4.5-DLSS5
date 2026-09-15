[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s25Out = Join-Path $toolRoot 'out-m3k-s25'
$out = Join-Path $toolRoot 'out-m3k-s26'
$s25Generated = Join-Path $workRoot 'm3k-src-s25'
$generated = Join-Path $workRoot 'm3k-src-s26'
$obj = Join-Path $workRoot 'obj-s26'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A2-S2.6 gate 1/4: reproduce S2.5 live true-resolution profiles ==='
& (Join-Path $toolRoot 'build-s25.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s25Out 'BUILD-VERIFIED.txt'))) {
    throw 'S2.5 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s25Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A2-S2.6 gate 2/4: clone generated S2.5 source ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s25Generated -Destination $generated -Recurse

Write-Host '=== A2-S2.6 gate 3/4: enable native NR -> DLAA and UQ fallback gate ==='
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
& (Join-Path $toolRoot 'a2-s26-native-uq-stage.ps1') -GeneratedRoot $generated -FeederSource $feedSource

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'Native + NR + DLAA',
    'M3K-A2-S2.6: NR18 -> DLAA running',
    'M3K-UQ: NGX query succeeded but returned 0x0',
    'EXPERIMENTAL 77%% true-render fallback',
    'actual UltraQuality create attempt',
    'rolling back to %s and its true render resolution',
    'static constexpr unsigned MaxPasses = 5;',
    'M3K-RES-LIVE: TRUE source confirmed')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated S2.6 source missing marker: $marker"
    }
}
if ($vkText.IndexOf('if (g_m3kSrProfileRequested == 0) return;', [StringComparison]::Ordinal) -ge 0) {
    throw 'Generated S2.6 source still contains the native NR bypass'
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A2-S2.6 gate 4/4: compile + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A2-S2.6 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Permanent ReShade M3K panel still keeps live independent Feature18 NR passes 1..5.',
    'Profile 0 is now Native + NR + DLAA: true native GTA/DXVK source -> Feature18 1..5 -> baseline DLAA -> native presenter.',
    'The S2.4 profile-0 NR bypass is removed; the proven A1 native NR->DLAA path is reused instead of adding a second native pipeline.',
    'Ultra Quality still asks NGX for official optimal settings first.',
    'Only when the UQ query succeeds but returns zero dimensions, S2.6 requests an explicitly experimental 77% linear fallback true-render size (2560x1440 => 1971x1109).',
    'The actual DLSS feature is still created with NVSDK_NGX_PerfQuality_Value_UltraQuality. The fallback ratio is not presented as an official NVIDIA UQ resolution.',
    'If UltraQuality feature creation rejects the chosen size after a live resize, S2.6 rolls back to the previously stable profile and render resolution.',
    'Quality/Balanced/Performance/Ultra Performance continue using NGX-provided optimal dimensions unchanged.',
    'Jitter remains the existing proof path in this milestone; proper temporal jitter/history is still the next quality milestone.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A2-S2.6 BUILD VERIFIED: $out (GPU native/UQ runtime gate still required)"
