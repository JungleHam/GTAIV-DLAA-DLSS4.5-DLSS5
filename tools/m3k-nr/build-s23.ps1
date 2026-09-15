[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$out = Join-Path $toolRoot 'out-m3k-s23'
$generated = Join-Path $workRoot 'm3k-src-s23'
$obj = Join-Path $workRoot 'obj-s23'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A2-S2.3 gate 1/5: reproduce proven dependency/build state ==='
& (Join-Path $toolRoot 'build.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $baseOut 'BUILD-VERIFIED.txt'))) {
    throw 'Baseline A2-S1 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared dependency: $p" }
}

Write-Host '=== A2-S2.3 gate 2/5: generate proven low-res NR -> SR source ==='
& (Join-Path $toolRoot 'a2-s2-stage.ps1') -SourceRoot (Join-Path $toolRoot 'src') -GeneratedRoot $generated

Write-Host '=== A2-S2.3 gate 3/5: layer proven independent multi-pass source ==='
& (Join-Path $toolRoot 'a2-s22-multipass-stage.ps1') -GeneratedRoot $generated

Write-Host '=== A2-S2.3 gate 4/5: add live 1..5 switching + ReShade submenu ==='
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
& (Join-Path $toolRoot 'a2-s23-live-stage.ps1') -GeneratedRoot $generated -FeederSource $feedSource

$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$feedText = [IO.File]::ReadAllText($feedSource)
foreach ($marker in @(
    'static constexpr unsigned MaxPasses = 5;',
    'M3K-LIVE: ACTIVE NR passes',
    'M3kRequestNrPassesLive',
    'M3K Neural Rendering',
    'M3K-A2-S2.3: %s passes=%u -> DLSS SR running')) {
    if (($vkText + $nrText + $feedText).IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated live source missing marker: $marker"
    }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A2-S2.3 gate 5/5: compile + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A2-S2.3 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Functional target: live 1..5 independent feature18 passes -> DLSS SR.',
    'ReShade overlay contains an M3K Neural Rendering submenu with pass-count radio buttons.',
    'Higher pass counts are created lazily once; switching among already warmed counts does not rebuild or restart GTA.',
    'Pass-count changes reset NR histories and downstream SR history.',
    'Jitter remains 0; temporal-quality work is still a later milestone.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A2-S2.3 BUILD VERIFIED: $out (manual install only)"
